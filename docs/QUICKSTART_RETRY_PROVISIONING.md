# Quickstart: Dedicated Compartment + Retry Provisioning

This flow creates OCI Always Free resources in a dedicated compartment and retries VM launches until capacity is available.

## Why this flow

- Keeps free-tier experiments isolated in their own compartment and network.
- Uses the repository VM profile defaults from `tofu/oci/terraform.tfvars.example`.
- Handles common `Out of host capacity` failures automatically.

## Always Free limits used

- Ampere A1: up to 4 OCPUs and 24 GB RAM total
- Micro: up to 2 instances (`VM.Standard.E2.1.Micro`)
- Boot + block storage: 200 GB total
- Minimum boot volume per VM: 47 GB
- Ampere capacity can be temporarily unavailable; retry is expected

## Best-practice guardrails

- Dedicated compartment for blast-radius isolation
- Dedicated VCN/subnet/security list per deployment
- Strictly Always-Free shapes only (`VM.Standard.A1.Flex`, `VM.Standard.E2.1.Micro`)
- Reuse existing resources by name for idempotency
- Fail fast on non-capacity API errors

## Run

From repository root:

```bash
python3 scripts/provision_free_tier_retry.py \
  --profile gf78 \
  --compartment-name gf78-free-tier-dedicated \
  --retry-seconds 300
```

## Bounded test run

```bash
python3 scripts/provision_free_tier_retry.py \
  --profile gf78 \
  --compartment-name gf78-free-tier-dedicated \
  --retry-seconds 60 \
  --max-attempts 2
```

Exit codes:
- `0`: target VM profile reached
- `1`: hard failure (non-capacity error)
- `2`: retries exhausted (`--max-attempts` only)
