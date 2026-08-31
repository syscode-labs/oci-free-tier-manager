#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../tofu/oci"
tofu init -backend=false
tofu validate
