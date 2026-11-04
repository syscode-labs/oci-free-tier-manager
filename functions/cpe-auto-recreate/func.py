"""Read-only CPE drift reconciliation preparation.

No invocation may create, update, or delete OCI resources or publish a Vault
version. Replacement execution and private router delivery require separate
approval and implementation. Legacy destructive phases fail closed.
"""

import base64
import copy
import json
import os
import socket

import oci
import oci.secrets


def _read_state(client, secret_id):
    bundle = client.get_secret_bundle(secret_id=secret_id).data
    return json.loads(base64.b64decode(bundle.secret_bundle_content.content))


def _find_by_display_name(list_fn, compartment_id, display_name):
    resources = oci.pagination.list_call_get_all_results(
        list_fn, compartment_id=compartment_id
    ).data
    matches = [
        r
        for r in resources
        if r.display_name == display_name
        and getattr(r, "lifecycle_state", "AVAILABLE") == "AVAILABLE"
    ]
    if len(matches) != 1:
        raise RuntimeError("ambiguous or unavailable source resource")
    return matches[0]


def _prepare_replacement(net, source, state, public_ip):
    """Build an IN-MEMORY proposal only; never log/return this secret payload.

    Slot identity comes from the CURRENT Vault VPN endpoint, not list order or
    sorting replacement addresses. OCI create tunnel array ordering alone is
    not proof of association: future execution must uniquely name each slot,
    read both replacement endpoints/PSKs back, and verify equality privately.
    """
    if source.lifecycle_state != "AVAILABLE":
        raise RuntimeError("source connection unavailable")
    tunnels = oci.pagination.list_call_get_all_results(
        net.list_ip_sec_connection_tunnels, source.id
    ).data
    if len(tunnels) != 2 or len({t.id for t in tunnels}) != 2:
        raise RuntimeError("expected exactly two distinct source tunnels")
    by_ip = {t.vpn_ip: t for t in tunnels}
    if len(by_ip) != 2:
        raise RuntimeError("ambiguous source endpoints")
    slots = []
    for slot in (1, 2):
        endpoint = state.get(f"tunnel{slot}_ip")
        psk = state.get(f"tunnel{slot}_psk")
        if endpoint not in by_ip or not psk:
            raise RuntimeError("current Vault slot is missing or unmatched")
        old = net.get_ip_sec_connection_tunnel(source.id, by_ip[endpoint].id).data
        actual = net.get_ip_sec_connection_tunnel_shared_secret(
            source.id, old.id
        ).data.shared_secret
        if actual != psk:
            raise RuntimeError("source shared secret differs from current Vault slot")
        if old.routing != "STATIC" or old.ike_version != "V2":
            raise RuntimeError("unsupported source tunnel routing or IKE version")
        if old.phase_one_config is None or old.phase_two_config is None:
            raise RuntimeError("source crypto configuration unavailable")
        slots.append(
            {
                "slot": slot,
                "old_tunnel_id": old.id,
                "create": oci.core.models.CreateIPSecConnectionTunnelDetails(
                    display_name=f"preserved-slot-{slot}",
                    shared_secret=psk,
                    routing=old.routing,
                    ike_version=old.ike_version,
                ),
                "configure": oci.core.models.UpdateIPSecConnectionTunnelDetails(
                    routing=old.routing,
                    ike_version=old.ike_version,
                    phase_one_config=oci.core.models.PhaseOneConfigDetails(
                        **oci.util.to_dict(old.phase_one_config)
                    ),
                    phase_two_config=oci.core.models.PhaseTwoConfigDetails(
                        **oci.util.to_dict(old.phase_two_config)
                    ),
                ),
            }
        )
    if slots[0]["old_tunnel_id"] == slots[1]["old_tunnel_id"]:
        raise RuntimeError("Vault slots refer to the same source tunnel")
    return {
        "public_ip": public_ip,
        "source_ipsec_id": source.id,
        "drg_id": source.drg_id,
        "static_routes": copy.deepcopy(source.static_routes),
        "cpe_local_identifier": source.cpe_local_identifier,
        "cpe_local_identifier_type": source.cpe_local_identifier_type,
        "slots": slots,
    }


def handler(ctx, data=None):
    signer = oci.auth.signers.get_resource_principals_signer()
    net = oci.core.VirtualNetworkClient(config={}, signer=signer)
    secrets = oci.secrets.SecretsClient(config={}, signer=signer)
    state = _read_state(secrets, os.environ["SECRET_ID"])
    # Never resume the old create/delete state machine, including unknown phases.
    if state.get("phase") is not None:
        return {"action": "blocked", "reason": "legacy_state_requires_manual_review"}
    compartment = os.environ["COMPARTMENT_ID"]
    cpe = _find_by_display_name(
        net.list_cpes,
        compartment,
        os.environ.get("CPE_DISPLAY_NAME", "home-openwrt-cpe"),
    )
    source = _find_by_display_name(
        net.list_ip_sec_connections,
        compartment,
        os.environ.get("IPSEC_DISPLAY_NAME", "home-openwrt-ipsec"),
    )
    source = net.get_ip_sec_connection(source.id).data
    if source.cpe_id != cpe.id:
        raise RuntimeError("source connection does not reference source CPE")
    public_ip = socket.gethostbyname(os.environ["DDNS_HOSTNAME"])
    if public_ip == cpe.ip_address:
        return {"action": "no-op"}
    _prepare_replacement(net, source, state, public_ip)
    # The proposal contains secrets: deliberately discard it at this boundary.
    return {
        "action": "blocked",
        "reason": "replacement_approval_and_private_delivery_required",
    }
