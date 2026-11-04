# Preservation-only CPE reconciliation preparation

PR129 must not be applied as an IAM-only repair against the old image. Source
publication is not image deployment: the live Function image remains unchanged.
Do not enable invocation, change IAM, invoke, or deploy until separately approved.

The replacement handler is intentionally read-only, including on drift. It has
no resource-create/update/delete or Vault-write path, and refuses all legacy
in-progress phases. A validated proposal stays in memory; responses contain no
PSKs, endpoints, or OCIDs. No replacement is automatically executed.

## Prepared invariants

- Current Vault tunnel slots must match exactly two distinct existing OCI tunnel
  endpoints. Both current OCI shared secrets must equal their respective Vault
  values. List order is irrelevant; mismatches fail closed.
- SDK `CreateIPSecConnectionTunnelDetails.shared_secret` carries each existing
  PSK; no random keys or rotation. Explicit slot display names preserve logical
  association. Future execution must read back unique replacement slot names,
  endpoint/PSK pairs, and exact equality before delivering anything privately.
- The proposal copies existing static routes, DRG, CPE identifier/type and both
  actual phase-one/phase-two configurations rather than regenerating defaults.
- Existing CPE, IPsec, route tables and Vault content remain untouched. Repeated
  preparation makes no mutations and cannot allocate duplicate resources.

## Approval boundary / not yet implemented

No cloud resources, billable capacity, or free-tier quota are allocated by this
code. Before a replacement is authorized, verify quota/cost for simultaneous old
and new connections and inspect the **release-controller-owned** delivery route.
No private delivery endpoint is asserted or configured in this public repository.
The exact private endpoint and owner route remain an external approval prerequisite.

The next proposed operation is a separately approved create-only replacement CPE
and IPsec connection, retaining the old pair and supplying both preserved keys
at creation. That execution path is deliberately absent here: it needs durable
retry-safe resource identity, exact private equality/crypto/routes read-back,
and an approved authenticated private router peer-endpoint delivery route before
implementation or execution. Never infer those gates from lifecycle AVAILABLE.
Never overwrite the current Vault document with intermediate state. Never delete
old resources, including after a successful tunnel health check, under this PR.

Tests use synthetic secrets/documentation addresses and real SDK model classes:

```sh
python -m unittest scripts.tests.test_cpe_preservation scripts.tests.test_cpe_scheduler_identity -v
```
