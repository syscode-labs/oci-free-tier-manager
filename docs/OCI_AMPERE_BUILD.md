## OCI Ampere image builds on free tier (ephemeral)

Goal: build packer images on ARM64 without consuming the production free-tier A1 capacity.

### Approach
- Use the Packer `oracle-oci` builder (`packer/oci-ampere-base.pkr.hcl`) to launch a **temporary VM.Standard.A1.Flex** builder in another tenancy (or any tenancy that still has free-tier A1 headroom).
- Build runs from GitHub Actions (`.github/workflows/packer-oci-ampere.yml`) and only uses the builder tenancy for the duration of the job. The instance is destroyed automatically; only the custom image remains.
- You can point the upload/usage of the produced image back to the main tenancy via Object Storage copy/import, or keep it in the builder tenancy if you prefer to deploy from there.

### Required secrets (in the builder tenancy)
- `OCI_TENANCY_OCID`
- `OCI_USER_OCID`
- `OCI_FINGERPRINT`
- `OCI_API_PRIVATE_KEY` (PEM contents)
- `OCI_COMPARTMENT_OCID`
- `OCI_REGION` (e.g. `uk-london-1`)
- `OCI_AVAILABILITY_DOMAIN` (e.g. `kIdk:UK-LONDON-1-AD-1`)
- `OCI_SUBNET_OCID` (subnet with outbound internet; set workflow input `assign_public_ip=false` if NAT is present)
- `OCI_BASE_IMAGE_OCID` (Debian 12 ARM64 image for that region)
- `OCI_SSH_USERNAME` (e.g. `debian`)
- `OCI_SSH_PUBLIC_KEY`
- `OCI_SSH_PRIVATE_KEY`
- Optional: `TAILSCALE_AUTH_KEY`

### Running the workflow
1. Trigger **“Packer OCI Ampere (Always Free)”** manually in GitHub Actions.
2. Optionally set `image_name_prefix` and `assign_public_ip`.
3. Packer launches an A1.Flex builder, provisions the image, and creates a custom image named `<prefix>-YYYYMMDDhhmmss`.
4. Logs are uploaded as an artifact; the builder instance is torn down automatically by Packer.

### Notes
- This keeps production A1 capacity untouched; use a separate tenancy purely for builds if the main one is already at capacity.
- The resulting custom image stays in the builder compartment; copy/import it to the production tenancy if needed (Object Storage copy + custom image import).
- If the region is capacity-constrained, try another region in the builder tenancy; only the image import step needs to target the production region.

---

## AWS alternate path (Graviton, free-tier credits)

When OCI free-tier Ampere is fully consumed, build the image on AWS Graviton using free-tier t4g.micro credits and copy it back to OCI if needed.

### Workflow
- Manual workflow: `.github/workflows/packer-aws-arm.yml`
- Template: `packer/aws-arm-base.pkr.hcl` (amazon-ebs builder, ARM64)
- Resources: ephemeral t4g.micro (1 vCPU, 1 GiB) with 10 GB gp3 root; builder is terminated by Packer after AMI creation.

### Required AWS secrets
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (e.g. `eu-west-1`)
- `AWS_SOURCE_AMI` (Debian 12 ARM64 AMI for that region)
- `AWS_SSH_USERNAME` (Debian AMIs use `admin`)
- `AWS_SSH_KEYPAIR_NAME` (existing EC2 key pair)
- `AWS_SSH_PRIVATE_KEY` (PEM matching the key pair)
- Optional: `AWS_SUBNET_ID` (public subnet if no NAT), `TAILSCALE_AUTH_KEY`

### Enabling a fresh AWS account (scriptable)
Create a minimal IAM user with programmatic access for Packer:

```bash
AWS_PROFILE=org-new-account
AWS_REGION=eu-west-1
USER_NAME=packer-graviton
POLICY_NAME=packer-graviton-inline

# Create user and access keys
aws iam create-user --user-name "$USER_NAME"
ACCESS_KEYS=$(aws iam create-access-key --user-name "$USER_NAME")
echo "$ACCESS_KEYS" | jq -r '.AccessKey.AccessKeyId, .AccessKey.SecretAccessKey'

# Attach least-privilege inline policy
cat > /tmp/packer-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateTags",
        "ec2:CreateImage",
        "ec2:DeregisterImage",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:Describe*",
        "ec2:ImportKeyPair",
        "ec2:DeleteKeyPair"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name "$USER_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document file:///tmp/packer-policy.json

# Import SSH key pair for the builder (reuse your existing public key)
aws ec2 import-key-pair \
  --key-name "$USER_NAME-key" \
  --public-key-material "$(cat ~/.ssh/id_rsa.pub)"
```

Store the outputs in GitHub secrets:
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from create-access-key)
- `AWS_REGION`
- `AWS_SSH_KEYPAIR_NAME` (e.g. `packer-graviton-key`)
- `AWS_SSH_PRIVATE_KEY` (matching the imported public key)
- `AWS_SOURCE_AMI` (region-specific Debian 12 ARM64 AMI)
- `AWS_SSH_USERNAME` (usually `admin`)

### Running the AWS workflow
1. Trigger **“Packer AWS ARM (Graviton)”** workflow.
2. Optionally set `ami_name_prefix`, `instance_type` (default `t4g.micro`), and `associate_public_ip`.
3. Packer launches a Graviton builder, hardens Debian, and outputs an AMI ID. The builder is terminated automatically.

---

## Validation (both OCI and AWS builds)

Packer now runs [goss](https://goss.rocks) inside the builder before creating the image:
- Shared test file: `packer/goss/base.goss.yaml`
- Runner: `packer/scripts/run-goss.sh` (downloads the right arch binary)
- Checks: SSH + qemu-guest-agent + fail2ban + tailscale enabled, hardened sshd config, iptables rules present.
If goss fails, the build fails and no image is produced.

---

## Copying images from build tenancy/account to production

### Automated (OCI → OCI)
- Workflow: `.github/workflows/oci-image-copy.yml` (manual trigger)
- Inputs: `source_image_ocid`, `dest_image_name`, `object_name`, `expires_in_hours`
- Secrets required:
  - Build tenancy: `BUILD_OCI_TENANCY_OCID`, `BUILD_OCI_USER_OCID`, `BUILD_OCI_FINGERPRINT`, `BUILD_OCI_API_PRIVATE_KEY`, `BUILD_OCI_REGION`, `BUILD_OCI_BUCKET`, `BUILD_OCI_NAMESPACE`
  - Prod tenancy: `PROD_OCI_TENANCY_OCID`, `PROD_OCI_USER_OCID`, `PROD_OCI_FINGERPRINT`, `PROD_OCI_API_PRIVATE_KEY`, `PROD_OCI_REGION`, `PROD_OCI_COMPARTMENT_OCID`
- Flow: export custom image to Object Storage in build tenancy → create PAR → import into prod → cleanup PAR/object.

### Manual runbook (add secrets first)
- OCI → OCI:
  1. Export image to Object Storage in build tenancy.
  2. Create PAR with read access.
  3. Import from PAR URL into prod compartment.
  4. Delete PAR and exported object.
- AWS → OCI:
  1. Export AMI to S3 and generate presigned URL.
  2. Import in OCI via `image import from-object-uri`.
  3. Delete presigned object/S3 artifact.

### Notes
- Keep images small (<20 GB) to fit the free-tier limits.
- Prefer building in a region near production for faster imports.

---

## Git workflow (required when editing these files)
- Use a feature branch (branch protection on `main`): `git checkout -b feat/<name>`.
- Conventional commits (e.g., `chore: automate oci image copy`) with a brief body if needed.
- Run relevant checks before committing (Packer files: at least `packer fmt -check` and rerun the targeted workflow in CI).
- Do not force-push to `main`; open a PR and let CI pass before merge.
- Tooling: enter the devbox/Nix shell for Packer (already provided there); do not attempt to add another Packer derivation to the flake.
