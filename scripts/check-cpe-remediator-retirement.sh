#!/usr/bin/env bash
set -euo pipefail

compartment_id=$(jq -r '.compartment_id' < /dev/stdin)
functions=$(oci fn function list --compartment-id "$compartment_id" --all --output json)
schedules=$(oci resource-scheduler schedule list --compartment-id "$compartment_id" --all --output json)

if jq -e '[.data[] | select(."display-name" == "cpe-auto-recreate" and ."lifecycle-state" != "DELETED")] | length == 0' <<< "$functions" >/dev/null && \
  jq -e '[.data[] | select(."display-name" == "cpe-auto-recreate-schedule" and ."lifecycle-state" != "DELETED")] | length == 0' <<< "$schedules" >/dev/null; then
  printf '{"retired":"true"}\n'
else
  printf '{"retired":"false"}\n'
fi
