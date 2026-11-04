"""Offline tests against real OCI SDK models; all keys are synthetic."""

import ast
import importlib.util
import pathlib
from types import SimpleNamespace as Obj
import unittest
from unittest.mock import Mock, patch

import oci

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "functions/cpe-auto-recreate/func.py"
spec = importlib.util.spec_from_file_location("cpe_preservation", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreservationTests(unittest.TestCase):
    def setUp(self):
        self.net = Mock()
        self.state = {
            "tunnel1_ip": "192.0.2.10",
            "tunnel2_ip": "192.0.2.20",
            "tunnel1_psk": "synthetic-first",
            "tunnel2_psk": "synthetic-second",
        }
        self.source = Obj(
            id="source",
            lifecycle_state="AVAILABLE",
            drg_id="drg",
            static_routes=["10.0.0.0/24"],
            cpe_local_identifier="192.0.2.1",
            cpe_local_identifier_type="IP_ADDRESS",
        )
        self.tunnels = [
            Obj(id="second", vpn_ip="192.0.2.20"),
            Obj(id="first", vpn_ip="192.0.2.10"),
        ]
        self.net.list_ip_sec_connection_tunnels.__name__ = (
            "list_ip_sec_connection_tunnels"
        )
        self.net.list_ip_sec_connection_tunnels.return_value = oci.response.Response(
            200, {}, self.tunnels, None
        )
        self.net.get_ip_sec_connection_tunnel.side_effect = lambda _, tid: Obj(
            data=Obj(
                id=tid,
                routing="STATIC",
                ike_version="V2",
                phase_one_config=oci.core.models.PhaseOneConfigDetails(
                    is_custom_phase_one_config=True,
                    encryption_algorithm="AES_256_CBC",
                    authentication_algorithm="SHA2_384",
                    diffie_helman_group="GROUP14",
                ),
                phase_two_config=oci.core.models.PhaseTwoConfigDetails(
                    is_custom_phase_two_config=True,
                    encryption_algorithm="AES_256_CBC",
                    authentication_algorithm="HMAC_SHA2_256_128",
                    pfs_dh_group="GROUP5",
                    is_pfs_enabled=True,
                ),
            )
        )
        self.net.get_ip_sec_connection_tunnel_shared_secret.side_effect = (
            lambda _, tid: Obj(data=Obj(shared_secret="synthetic-" + tid))
        )

    def prepare(self):
        return module._prepare_replacement(
            self.net, self.source, self.state, "192.0.2.2"
        )

    def assert_read_only(self):
        self.assertTrue(
            all(
                call[0].split(".")[0].startswith(("get_", "list_"))
                for call in self.net.mock_calls
            )
        )

    def test_stable_slots_preserve_both_keys_crypto_and_routes(self):
        proposal = self.prepare()
        self.assertEqual(
            [s["old_tunnel_id"] for s in proposal["slots"]], ["first", "second"]
        )
        for index, slot in enumerate(proposal["slots"], 1):
            self.assertEqual(
                slot["create"].shared_secret, self.state[f"tunnel{index}_psk"]
            )
            self.assertEqual(
                slot["configure"].phase_one_config.diffie_helman_group, "GROUP14"
            )
            self.assertEqual(slot["configure"].phase_two_config.pfs_dh_group, "GROUP5")
        self.assertEqual(proposal["static_routes"], self.source.static_routes)
        self.assertEqual(
            proposal["cpe_local_identifier"], self.source.cpe_local_identifier
        )
        self.assert_read_only()

    def test_repeated_preparation_is_idempotent(self):
        first = self.prepare()
        self.tunnels.reverse()
        second = self.prepare()
        self.assertEqual(oci.util.to_dict(first), oci.util.to_dict(second))
        self.assert_read_only()

    def test_mismatch_fails_without_mutations(self):
        self.state["tunnel2_psk"] = "synthetic-wrong"
        with self.assertRaisesRegex(RuntimeError, "differs"):
            self.prepare()
        self.assert_read_only()

    def test_duplicate_slots_fail_without_mutations(self):
        self.state["tunnel2_ip"] = self.state["tunnel1_ip"]
        self.state["tunnel2_psk"] = self.state["tunnel1_psk"]
        with self.assertRaisesRegex(RuntimeError, "same source"):
            self.prepare()
        self.assert_read_only()

    def test_legacy_and_unknown_phases_never_resume(self):
        with patch.object(
            module.oci.auth.signers, "get_resource_principals_signer"
        ), patch.object(module.oci.core, "VirtualNetworkClient") as net, patch.object(
            module.oci.secrets, "SecretsClient"
        ), patch.object(
            module, "_read_state"
        ) as state, patch.dict(
            module.os.environ, {"SECRET_ID": "synthetic"}
        ):
            for phase in (
                "cpe_ipsec_created",
                "tunnels_configured",
                "old_ipsec_deleting",
                "unknown",
            ):
                state.return_value = {"phase": phase}
                self.assertEqual(module.handler(None)["action"], "blocked")
            net.return_value.assert_not_called()
            self.assertEqual(net.return_value.mock_calls, [])

    def test_handler_has_no_mutation_api_calls(self):
        tree = ast.parse(SOURCE.read_text())
        calls = [
            n.func.attr
            for n in ast.walk(tree)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
        ]
        self.assertFalse(
            [
                name
                for name in calls
                if name.startswith(("delete_", "create_", "update_"))
            ]
        )


if __name__ == "__main__":
    unittest.main()
