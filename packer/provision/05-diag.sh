#!/bin/bash
set +e
# Layer 5: Diagnose cloud-init OCI datasource import (temporary; for debugging "Could not import DataSourceOCI")
echo "===== OCI-DATASOURCE-DIAG START ====="
python3 - <<'PYEOF' 2>&1 | tee /tmp/diag.txt
import importlib, traceback
try:
    m = importlib.import_module("cloudinit.sources.DataSourceOCI")
    print("IMPORT_OK DataSourceOCI:", m)
except Exception as e:
    print("IMPORT_FAIL (%s):" % type(e).__name__)
    traceback.print_exc()
PYEOF
echo "===== cloud-init log datasource errors ====="
grep -rniE "DataSourceOCI|ImportError|ModuleNotFoundError|Could not import" /var/log/cloud-init*.log 2>/dev/null | tail -40
echo "===== cloudinit/sources listing ====="
find /usr/lib/python3/dist-packages/cloudinit/sources/ -maxdepth 1 -printf "%f\n" 2>/dev/null | head -40
echo "===== pip-freeze candidates relevant to OCI/cloud ====="
dpkg -l 2>/dev/null | grep -iE "cloud|python3-(attr|netaddr|requests|cryptography|yaml|jsonschema|oauthlib|oauth|six)" | awk '{print $2,$3}'
echo "===== OCI-DATASOURCE-DIAG END ====="
