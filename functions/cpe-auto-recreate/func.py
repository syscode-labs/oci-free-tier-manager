"""
Auto-recreate the home VPN CPE/tunnels when REDACTED-ROUTER-HOSTNAME's public IP drifts.

Trigger: OCI Resource Scheduler, on a cron (see tofu/oci/cpe-auto-recreate.tf).
Auth: Resource Principal (no embedded API key -- the Function's own identity,
scoped via the dynamic group + policy in the same Terraform file).

Logic:
  1. Resolve REDACTED-DDNS-HOSTNAME (DDNS, kept current by REDACTED-ROUTER-HOSTNAME's own
     ddns-scripts-cloudflare, independent of this Function).
  2. Compare against the registered CPE's ip_address.
  3. If they match: no-op.
  4. If they differ: delete + recreate the CPE, IPSec connection, and both
     tunnel-management resources -- ip_address is immutable via the API, so
     there is no in-place update path. Phase-1/phase-2 policy is pinned to
     the exact values already proven working against REDACTED-ROUTER-HOSTNAME's strongSwan
     build (see tofu/oci/vpn.tf and the 2026-08-13/14 incident notes): no
     AEAD, no ECP/curve25519 groups available on the router.
  5. Write the new tunnel PSKs + public IPs to the cpe-tunnel-details Vault
     secret. REDACTED-ROUTER-HOSTNAME polls this (read-only, separately-scoped token) to
     re-sync swanctl.conf -- that local delivery leg is a separate, not-yet-
     built piece (see openspec/changes/oci-cpe-auto-recreate, Out of Scope).

See openspec/changes/oci-cpe-auto-recreate/ (in syscode-ai-internal-plans)
for the full design and phase plan this implements.
"""

import base64
import json
import logging
import socket
import time

import oci

logger = logging.getLogger(__name__)

DDNS_HOSTNAME = "REDACTED-DDNS-HOSTNAME"

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

RECREATE_POLL_INTERVAL_SECONDS = 5
RECREATE_POLL_TIMEOUT_SECONDS = 180


def _resolve_current_public_ip(hostname: str) -> str:
    return socket.gethostbyname(hostname)


def _wait_for_state(get_fn, ocid: str, target_states: set[str], timeout: int) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        state = get_fn(ocid).data.lifecycle_state
        if state in target_states:
            return
        if state in {"FAILED", "TERMINATED"}:
            raise RuntimeError(f"{ocid} entered unexpected state {state}")
        time.sleep(RECREATE_POLL_INTERVAL_SECONDS)
    raise TimeoutError(f"{ocid} did not reach {target_states} within {timeout}s")


def recreate_cpe_and_tunnels(
    net_client: "oci.core.VirtualNetworkClient",
    compartment_id: str,
    old_cpe_id: str,
    old_ipsec_id: str,
    new_public_ip: str,
    cpe_local_identifier: str,
    drg_id: str,
    static_route_cidrs: list[str],
) -> dict:
    """Delete + recreate the CPE, IPSec connection, and both tunnels with the
    pinned phase-1/2 policy. Returns the new tunnel details (public IPs +
    PSKs) for the caller to write to the Vault secret.
    """
    old_cpe = net_client.get_cpe(old_cpe_id).data
    display_name = old_cpe.display_name

    # 1. New CPE first (old one can't be deleted while an IPSec connection
    #    still references it -- confirmed directly: 409-IncorrectState,
    #    "CPE ... cannot be deleted because it is still used by an
    #    IPsecConnections", 2026-08-13).
    new_cpe = net_client.create_cpe(
        oci.core.models.CreateCpeDetails(
            compartment_id=compartment_id,
            ip_address=new_public_ip,
            display_name=display_name,
        )
    ).data
    _wait_for_state(
        net_client.get_cpe, new_cpe.id, {"AVAILABLE"}, RECREATE_POLL_TIMEOUT_SECONDS
    )

    # 2. New IPSec connection pointing at the new CPE.
    new_ipsec = net_client.create_ip_sec_connection(
        oci.core.models.CreateIPSecConnectionDetails(
            compartment_id=compartment_id,
            cpe_id=new_cpe.id,
            drg_id=drg_id,
            display_name=f"{display_name}-ipsec",
            static_routes=static_route_cidrs,
            cpe_local_identifier=cpe_local_identifier,
            cpe_local_identifier_type="IP_ADDRESS",
        )
    ).data
    _wait_for_state(
        net_client.get_ip_sec_connection,
        new_ipsec.id,
        {"AVAILABLE"},
        RECREATE_POLL_TIMEOUT_SECONDS,
    )

    # 3. Pin phase-1/phase-2 policy on both auto-created tunnels, same as
    #    tofu/oci/cpe-auto-recreate.tf's phase_one_details/phase_two_details.
    tunnels = net_client.list_ip_sec_connection_tunnels(new_ipsec.id).data
    tunnel_results = []
    for tunnel in tunnels:
        net_client.update_ip_sec_connection_tunnel(
            ipsc_id=new_ipsec.id,
            tunnel_id=tunnel.id,
            update_ip_sec_connection_tunnel_details=oci.core.models.UpdateIPSecConnectionTunnelDetails(
                routing="STATIC",
                phase_one_details=oci.core.models.PhaseOneConfigDetails(
                    is_custom_phase_one_config=True,
                    custom_encryption_algorithm=PHASE_ONE_ENCRYPTION,
                    custom_authentication_algorithm=PHASE_ONE_AUTHENTICATION,
                    custom_dh_group=PHASE_ONE_DH_GROUP,
                ),
                phase_two_details=oci.core.models.PhaseTwoConfigDetails(
                    is_custom_phase_two_config=True,
                    custom_encryption_algorithm=PHASE_TWO_ENCRYPTION,
                    custom_authentication_algorithm=PHASE_TWO_AUTHENTICATION,
                    dh_group=PHASE_TWO_DH_GROUP,
                    is_pfs_enabled=True,
                ),
            ),
        )
        psk = net_client.get_ip_sec_connection_tunnel_shared_secret(
            new_ipsec.id, tunnel.id
        ).data
        refreshed = net_client.get_ip_sec_connection_tunnel(
            new_ipsec.id, tunnel.id
        ).data
        tunnel_results.append({"vpn_ip": refreshed.vpn_ip, "psk": psk.shared_secret})

    # 4. Old resources last, once nothing references them -- the IPSec
    #    connection must go first (deleting the CPE while it's still
    #    referenced by a live IPSec connection fails: 409-IncorrectState,
    #    confirmed directly on 2026-08-13).
    net_client.delete_ip_sec_connection(old_ipsec_id)
    _wait_for_state(
        net_client.get_ip_sec_connection,
        old_ipsec_id,
        {"TERMINATED"},
        RECREATE_POLL_TIMEOUT_SECONDS,
    )
    net_client.delete_cpe(old_cpe_id)

    return {
        "tunnel1_ip": tunnel_results[0]["vpn_ip"] if len(tunnel_results) > 0 else None,
        "tunnel1_psk": tunnel_results[0]["psk"] if len(tunnel_results) > 0 else None,
        "tunnel2_ip": tunnel_results[1]["vpn_ip"] if len(tunnel_results) > 1 else None,
        "tunnel2_psk": tunnel_results[1]["psk"] if len(tunnel_results) > 1 else None,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "new_cpe_id": new_cpe.id,
        "new_ipsec_id": new_ipsec.id,
    }


def _find_by_display_name(list_fn, compartment_id: str, display_name: str, **extra):
    """CPE/IPSec OCIDs change every recreate -- that's the whole point of this
    Function -- so config can't pin a fixed OCID or the second drift event
    would silently operate on already-deleted resources. Discover the
    current live one by display_name each run instead.
    """
    matches = [
        r
        for r in list_fn(compartment_id=compartment_id, **extra).data
        if r.display_name == display_name and r.lifecycle_state == "AVAILABLE"
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly 1 AVAILABLE resource named {display_name!r}, found {len(matches)}"
        )
    return matches[0]


def handler(ctx, data: bytes = None):
    signer = oci.auth.signers.get_resource_principals_signer()
    net_client = oci.core.VirtualNetworkClient(config={}, signer=signer)
    vaults_client = oci.vault.VaultsClient(config={}, signer=signer)

    # Static, invocation-independent config only -- never a CPE/IPSec OCID
    # (see _find_by_display_name).
    cfg = json.loads(data) if data else {}
    compartment_id = cfg["compartment_id"]
    cpe_display_name = cfg.get("cpe_display_name", "home-openwrt-cpe")
    ipsec_display_name = cfg.get("ipsec_display_name", "home-openwrt-ipsec")
    cpe_local_identifier = cfg["cpe_local_identifier"]
    drg_id = cfg["drg_id"]
    static_route_cidrs = cfg["static_route_cidrs"]
    secret_id = cfg["secret_id"]

    cpe = _find_by_display_name(net_client.list_cpes, compartment_id, cpe_display_name)
    ipsec = _find_by_display_name(
        net_client.list_ip_sec_connections, compartment_id, ipsec_display_name
    )
    cpe_id, ipsec_id = cpe.id, ipsec.id

    current_ip = cpe.ip_address
    dns_ip = _resolve_current_public_ip(DDNS_HOSTNAME)

    if dns_ip == current_ip:
        logger.info("CPE IP %s matches DNS, no-op", current_ip)
        return {"action": "no-op", "ip": current_ip}

    logger.info("CPE IP %s != DNS %s, recreating", current_ip, dns_ip)
    result = recreate_cpe_and_tunnels(
        net_client,
        compartment_id,
        cpe_id,
        ipsec_id,
        dns_ip,
        cpe_local_identifier,
        drg_id,
        static_route_cidrs,
    )

    vaults_client.update_secret(
        secret_id=secret_id,
        update_secret_details=oci.vault.models.UpdateSecretDetails(
            secret_content=oci.vault.models.Base64SecretContentDetails(
                content=base64.b64encode(json.dumps(result).encode()).decode()
            )
        ),
    )

    logger.info("Recreated CPE/tunnels, wrote new secret version")
    return {"action": "recreated", "old_ip": current_ip, "new_ip": dns_ip}
