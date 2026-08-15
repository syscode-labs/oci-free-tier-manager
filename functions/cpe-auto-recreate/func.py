"""
Auto-recreate the home VPN CPE/tunnels when the home router's public IP drifts.

Trigger: bastion systemd timer (every 5 min, Instance Principal) as primary,
OCI Resource Scheduler (hourly, its own cron floor) as backup -- see
tofu/oci/cpe-auto-recreate.tf.
Auth: Resource Principal (no embedded API key -- the Function's own identity,
scoped via the dynamic group + policy in the same Terraform file).

Logic is a small phased state machine, not one blocking call. OCI Functions
has a hard 300s sync-invoke ceiling (confirmed against OCI's own docs, not
guessed) -- create-new-IPSec-then-wait-AVAILABLE and
delete-old-IPSec-then-wait-TERMINATED are each independently capable of
taking close to that alone in the real world, and a single invocation doing
both plus the tunnel-policy update in between blew the budget on the first
live forced-drift test (2026-08-15): killed mid-flow with no traceback,
after the new CPE/IPSec were created but before tunnel policy was applied.

Each invocation now does at most one step and returns. Progress is persisted
as a `phase` field in the cpe-tunnel-details Vault secret's own JSON (no new
infra -- reuses the secret that's already being written); the *next*
invocation, from whichever trigger fires next (5 min via the bastion timer
in the common case), picks up where the last one left off:

  phase == None            -> resolve DNS, compare to the current CPE. Equal:
                               no-op. Different: create new CPE + IPSec
                               (fast, no waiting), write phase
                               cpe_ipsec_created, return.
  cpe_ipsec_created         -> check new IPSec's lifecycle_state (one GET,
                               no polling loop). Not AVAILABLE yet: return
                               unchanged, retried next invocation. AVAILABLE:
                               pin phase-1/2 tunnel policy (see below),
                               capture PSKs, write phase tunnels_configured.
  tunnels_configured        -> request deletion of the old IPSec connection
                               (fire, don't wait), write phase
                               old_ipsec_deleting.
  old_ipsec_deleting        -> check old IPSec's state. Not TERMINATED (and
                               not already gone/404) yet: return unchanged.
                               Otherwise: delete the old CPE, clear phase to
                               None, write final tunnel PSKs/IPs + updated_at.

While a phase is in progress there are transiently two CPEs sharing the same
display_name -- expected and safe, since every phase after the first uses
the OCIDs captured in the state itself, never a display_name lookup (that
lookup happens only in the phase == None branch, i.e. before any duplicate
could exist).

Phase-1/phase-2 tunnel policy is pinned to the exact values already proven
working against the router's strongSwan build (see tofu/oci/vpn.tf and the
2026-08-13/14 incident notes): no AEAD, no ECP/curve25519 groups available
on the router.

The router polls the same Vault secret (read-only, separately-scoped token)
to re-sync swanctl.conf -- that local delivery leg is a separate, not-yet-
built piece (see openspec/changes/oci-cpe-auto-recreate, Out of Scope).

See openspec/changes/oci-cpe-auto-recreate/ (in syscode-ai-internal-plans)
for the full design and phase plan this implements.
"""

import base64
import json
import logging
import os
import socket
import time

import oci
import oci.secrets

logger = logging.getLogger(__name__)

# Same values as tofu/oci/cpe-auto-recreate's phase_one_details/phase_two_details
# pin -- must stay in sync. The router's strongSwan build has neither an AEAD
# nor an ecp/curve25519 plugin loaded, so it can only ever offer classical
# AES-CBC + MODP proposals (confirmed via `swanctl --list-algs` during the
# 2026-08-13/14 incident).
PHASE_ONE_ENCRYPTION = "AES_256_CBC"
PHASE_ONE_AUTHENTICATION = "SHA2_384"
PHASE_ONE_DH_GROUP = "GROUP14"
PHASE_TWO_ENCRYPTION = "AES_256_CBC"
PHASE_TWO_AUTHENTICATION = "HMAC_SHA2_256_128"
PHASE_TWO_DH_GROUP = "GROUP5"

# Recreate state-machine phases, persisted in the Vault secret's own JSON
# (field name "phase" -- not to be confused with IPSec phase-1/2 crypto
# policy above). None means no recreate in progress.
PHASE_CPE_IPSEC_CREATED = "cpe_ipsec_created"
PHASE_TUNNELS_CONFIGURED = "tunnels_configured"
PHASE_OLD_IPSEC_DELETING = "old_ipsec_deleting"


def _resolve_current_public_ip(hostname: str) -> str:
    return socket.gethostbyname(hostname)


def _find_by_display_name(list_fn, compartment_id: str, display_name: str, **extra):
    """Only called when phase is None -- every phase after the first uses the
    OCIDs captured in the state itself, since a display_name lookup would be
    ambiguous while the old and new CPE transiently share a name.

    getattr(..., default="AVAILABLE"): Cpe objects have no lifecycle_state
    attribute at all (confirmed via a live traceback, 2026-08-15 -- unlike
    IPSecConnection, which does). Treats state-less resources as always
    available while still filtering real state on the ones that have it.
    """
    matches = [
        r
        for r in list_fn(compartment_id=compartment_id, **extra).data
        if r.display_name == display_name
        and getattr(r, "lifecycle_state", "AVAILABLE") == "AVAILABLE"
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly 1 AVAILABLE resource named {display_name!r}, found {len(matches)}"
        )
    return matches[0]


def _read_state(secrets_client, secret_id: str) -> dict:
    bundle = secrets_client.get_secret_bundle(secret_id=secret_id).data
    content = base64.b64decode(bundle.secret_bundle_content.content).decode()
    return json.loads(content)


def _write_state(vaults_client, secret_id: str, state: dict) -> None:
    vaults_client.update_secret(
        secret_id=secret_id,
        update_secret_details=oci.vault.models.UpdateSecretDetails(
            secret_content=oci.vault.models.Base64SecretContentDetails(
                content=base64.b64encode(json.dumps(state).encode()).decode()
            )
        ),
    )


def _start_recreate(
    net_client,
    vaults_client,
    secret_id: str,
    compartment_id: str,
    old_cpe,
    old_ipsec,
    new_public_ip: str,
    cpe_local_identifier: str,
    drg_id: str,
    static_route_cidrs: list,
) -> dict:
    display_name = old_cpe.display_name

    # New CPE first (old one can't be deleted while an IPSec connection
    # still references it -- confirmed directly: 409-IncorrectState, "CPE
    # ... cannot be deleted because it is still used by an IPsecConnections",
    # 2026-08-13). CreateCpe is synchronous -- no state to wait for.
    new_cpe = net_client.create_cpe(
        oci.core.models.CreateCpeDetails(
            compartment_id=compartment_id,
            ip_address=new_public_ip,
            display_name=display_name,
        )
    ).data

    # New IPSec connection pointing at the new CPE. Requires DRG_ATTACH on
    # the drgs resource-type in the Function's policy, not just manage on
    # cpes/ipsec-connections -- missed on the first pass, only surfaced as a
    # live 404 NotAuthorizedOrNotFound (2026-08-15).
    # Reuse the OLD IPSec connection's own display_name verbatim -- NOT a
    # derived f"{cpe_name}-ipsec" -- so the name is stable across every
    # recreate cycle. A derived name only matches the env var default
    # ("home-openwrt-ipsec") on the very first recreate; the second
    # recreate's initial _find_by_display_name lookup then finds 0 matches
    # (confirmed live, 2026-08-15: the first full test cycle created
    # "home-openwrt-cpe-ipsec", silently diverging from what every future
    # invocation looks for).
    new_ipsec = net_client.create_ip_sec_connection(
        oci.core.models.CreateIPSecConnectionDetails(
            compartment_id=compartment_id,
            cpe_id=new_cpe.id,
            drg_id=drg_id,
            display_name=old_ipsec.display_name,
            static_routes=static_route_cidrs,
            cpe_local_identifier=cpe_local_identifier,
            cpe_local_identifier_type="IP_ADDRESS",
        )
    ).data

    state = {
        "phase": PHASE_CPE_IPSEC_CREATED,
        "new_cpe_id": new_cpe.id,
        "new_ipsec_id": new_ipsec.id,
        "old_cpe_id": old_cpe.id,
        "old_ipsec_id": old_ipsec.id,
        "new_public_ip": new_public_ip,
    }
    _write_state(vaults_client, secret_id, state)
    logger.info("Recreate started: new CPE/IPSec created, phase=%s", state["phase"])
    return {"action": "recreate_started", "phase": state["phase"]}


def _continue_after_create(
    net_client, vaults_client, secret_id: str, state: dict
) -> dict:
    ipsec = net_client.get_ip_sec_connection(state["new_ipsec_id"]).data
    if ipsec.lifecycle_state != "AVAILABLE":
        logger.info(
            "New IPSec not yet AVAILABLE (%s), waiting for next invocation",
            ipsec.lifecycle_state,
        )
        return {
            "action": "waiting",
            "phase": state["phase"],
            "ipsec_state": ipsec.lifecycle_state,
        }

    # Pin phase-1/phase-2 policy on both auto-created tunnels, same as
    # tofu/oci/cpe-auto-recreate.tf's phase_one_details/phase_two_details.
    tunnels = net_client.list_ip_sec_connection_tunnels(state["new_ipsec_id"]).data
    tunnel_results = []
    for tunnel in tunnels:
        net_client.update_ip_sec_connection_tunnel(
            ipsc_id=state["new_ipsec_id"],
            tunnel_id=tunnel.id,
            update_ip_sec_connection_tunnel_details=oci.core.models.UpdateIPSecConnectionTunnelDetails(
                routing="STATIC",
                # Field names throughout this call are the raw OCI Python
                # SDK/REST API names, NOT the Terraform provider's HCL
                # argument names (vpn.tf's custom_encryption_algorithm/
                # dh_group/phase_one_details/phase_two_details etc are the
                # Terraform provider's own abstraction, translated
                # internally to these) -- confirmed against the SDK source
                # on GitHub after two rounds of live TypeError: Unrecognized
                # keyword arguments, 2026-08-15, from copying vpn.tf's HCL
                # names verbatim into Python at two nesting levels
                # (UpdateIPSecConnectionTunnelDetails.phase_one_config, not
                # phase_one_details; PhaseOneConfigDetails.encryption_algorithm,
                # not custom_encryption_algorithm).
                phase_one_config=oci.core.models.PhaseOneConfigDetails(
                    is_custom_phase_one_config=True,
                    encryption_algorithm=PHASE_ONE_ENCRYPTION,
                    authentication_algorithm=PHASE_ONE_AUTHENTICATION,
                    diffie_helman_group=PHASE_ONE_DH_GROUP,
                ),
                phase_two_config=oci.core.models.PhaseTwoConfigDetails(
                    is_custom_phase_two_config=True,
                    encryption_algorithm=PHASE_TWO_ENCRYPTION,
                    authentication_algorithm=PHASE_TWO_AUTHENTICATION,
                    pfs_dh_group=PHASE_TWO_DH_GROUP,
                    is_pfs_enabled=True,
                ),
            ),
        )
        psk = net_client.get_ip_sec_connection_tunnel_shared_secret(
            state["new_ipsec_id"], tunnel.id
        ).data
        refreshed = net_client.get_ip_sec_connection_tunnel(
            state["new_ipsec_id"], tunnel.id
        ).data
        tunnel_results.append({"vpn_ip": refreshed.vpn_ip, "psk": psk.shared_secret})

    new_state = dict(state)
    new_state["phase"] = PHASE_TUNNELS_CONFIGURED
    new_state["tunnel1_ip"] = (
        tunnel_results[0]["vpn_ip"] if len(tunnel_results) > 0 else None
    )
    new_state["tunnel1_psk"] = (
        tunnel_results[0]["psk"] if len(tunnel_results) > 0 else None
    )
    new_state["tunnel2_ip"] = (
        tunnel_results[1]["vpn_ip"] if len(tunnel_results) > 1 else None
    )
    new_state["tunnel2_psk"] = (
        tunnel_results[1]["psk"] if len(tunnel_results) > 1 else None
    )
    _write_state(vaults_client, secret_id, new_state)
    logger.info("Tunnels configured, phase=%s", new_state["phase"])
    return {"action": "tunnels_configured", "phase": new_state["phase"]}


def _delete_old_ipsec(net_client, vaults_client, secret_id: str, state: dict) -> dict:
    # The IPSec connection must go before the CPE -- deleting the CPE while
    # it's still referenced by a live IPSec connection fails: 409-
    # IncorrectState, confirmed directly on 2026-08-13. Fire, don't wait --
    # the next invocation checks progress.
    net_client.delete_ip_sec_connection(state["old_ipsec_id"])
    new_state = dict(state)
    new_state["phase"] = PHASE_OLD_IPSEC_DELETING
    _write_state(vaults_client, secret_id, new_state)
    logger.info("Old IPSec delete requested, phase=%s", new_state["phase"])
    return {"action": "old_ipsec_deleting", "phase": new_state["phase"]}


def _finish_delete_old(net_client, vaults_client, secret_id: str, state: dict) -> dict:
    try:
        old_ipsec = net_client.get_ip_sec_connection(state["old_ipsec_id"]).data
        if old_ipsec.lifecycle_state != "TERMINATED":
            logger.info(
                "Old IPSec not yet TERMINATED (%s), waiting for next invocation",
                old_ipsec.lifecycle_state,
            )
            return {"action": "waiting", "phase": state["phase"]}
    except oci.exceptions.ServiceError as e:
        if e.status != 404:
            raise
        # 404 means it's already gone -- fine, proceed to CPE cleanup.

    net_client.delete_cpe(state["old_cpe_id"])

    final_state = {
        "phase": None,
        "tunnel1_ip": state.get("tunnel1_ip"),
        "tunnel1_psk": state.get("tunnel1_psk"),
        "tunnel2_ip": state.get("tunnel2_ip"),
        "tunnel2_psk": state.get("tunnel2_psk"),
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "new_cpe_id": state["new_cpe_id"],
        "new_ipsec_id": state["new_ipsec_id"],
    }
    _write_state(vaults_client, secret_id, final_state)
    logger.info("Recreate complete")
    return {"action": "recreated", "new_ip": state["new_public_ip"]}


def handler(ctx, data: bytes = None):
    signer = oci.auth.signers.get_resource_principals_signer()
    net_client = oci.core.VirtualNetworkClient(config={}, signer=signer)
    vaults_client = oci.vault.VaultsClient(config={}, signer=signer)
    secrets_client = oci.secrets.SecretsClient(config={}, signer=signer)

    # Static, invocation-independent config comes from the Function's own
    # `config` map (tofu/oci/cpe-auto-recreate.tf), which OCI Functions
    # exposes as environment variables -- NOT from the invocation payload.
    # Both triggers (bastion timer, Resource Scheduler) fire a bare invoke
    # with no body, so anything read from `data` here would just be empty.
    compartment_id = os.environ["COMPARTMENT_ID"]
    ddns_hostname = os.environ["DDNS_HOSTNAME"]
    cpe_display_name = os.environ.get("CPE_DISPLAY_NAME", "home-openwrt-cpe")
    ipsec_display_name = os.environ.get("IPSEC_DISPLAY_NAME", "home-openwrt-ipsec")
    cpe_local_identifier = os.environ["CPE_LOCAL_IDENTIFIER"]
    drg_id = os.environ["DRG_ID"]
    static_route_cidrs = json.loads(os.environ["STATIC_ROUTE_CIDRS_JSON"])
    secret_id = os.environ["SECRET_ID"]

    state = _read_state(secrets_client, secret_id)
    phase = state.get("phase")

    if phase == PHASE_CPE_IPSEC_CREATED:
        return _continue_after_create(net_client, vaults_client, secret_id, state)
    if phase == PHASE_TUNNELS_CONFIGURED:
        return _delete_old_ipsec(net_client, vaults_client, secret_id, state)
    if phase == PHASE_OLD_IPSEC_DELETING:
        return _finish_delete_old(net_client, vaults_client, secret_id, state)

    # No recreate in progress -- normal no-op-or-start check. Only reached
    # here (never mid-phase) so the old/new CPE can never collide on
    # display_name during this lookup.
    cpe = _find_by_display_name(net_client.list_cpes, compartment_id, cpe_display_name)
    ipsec = _find_by_display_name(
        net_client.list_ip_sec_connections, compartment_id, ipsec_display_name
    )

    current_ip = cpe.ip_address
    dns_ip = _resolve_current_public_ip(ddns_hostname)

    if dns_ip == current_ip:
        logger.info("CPE IP %s matches DNS, no-op", current_ip)
        return {"action": "no-op", "ip": current_ip}

    logger.info("CPE IP %s != DNS %s, starting recreate", current_ip, dns_ip)
    return _start_recreate(
        net_client,
        vaults_client,
        secret_id,
        compartment_id,
        cpe,
        ipsec,
        dns_ip,
        cpe_local_identifier,
        drg_id,
        static_route_cidrs,
    )
