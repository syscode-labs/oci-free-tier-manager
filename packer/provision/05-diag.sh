#!/bin/bash
set +e
# Layer 5: Diagnose cloud-init OCI datasource import (temporary; for debugging "Could not import DataSourceOCI")
echo "===== OCI-DATASOURCE-DIAG START ====="
python3 - <<'PYEOF' 2>&1 | tee /tmp/diag.txt
import importlib, traceback
for mod in ("cloudinit.sources.DataSourceOCI", "cloudinit.sources.DataSourceOracle"):
    try:
        m = importlib.import_module(mod)
        print("IMPORT_OK", mod, "->", m)
    except Exception as e:
        print("IMPORT_FAIL", mod, "(%s):" % type(e).__name__)
        traceback.print_exc()
PYEOF
echo "===== datasource_list configured ====="
grep -rHiE "datasource_list|datasource:" /etc/cloud/cloud.cfg.d/ 2>/dev/null
echo "===== cloud-init cloud.cfg datasource ====="
grep -nE "datasource_list|Oracle|OCI|datasource:" /etc/cloud/cloud.cfg 2>/dev/null | head -20
echo "===== cloudinit/sources listing ====="
find /usr/lib/python3/dist-packages/cloudinit/sources/ -maxdepth 1 -printf "%f\n" 2>/dev/null | head -40
echo "===== pip-freeze candidates relevant to OCI/cloud ====="
dpkg -l 2>/dev/null | grep -iE "cloud|python3-(attr|netaddr|requests|cryptography|yaml|jsonschema|oauthlib|oauth|six)" | awk '{print $2,$3}'
echo "===== OCI-DATASOURCE-DIAG END ====="
