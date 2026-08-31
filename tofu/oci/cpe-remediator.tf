/*
 * Private delivery of the local CPE remediator binary.
 *
 * The source artifact is built by scripts/build-cpe-remediator.sh before
 * OpenTofu validation and planning. The bucket is deliberately private; the
 * bastion reads its one object through its instance principal.
 */

locals {
  cpe_remediator_artifact_path = abspath("${path.module}/../../artifacts/cpe-remediator")
  cpe_remediator_object_name   = "cpe-remediator-linux-amd64"
  cpe_remediator_sha256        = filesha256(local.cpe_remediator_artifact_path)
}

# A content-addressed trigger for the bastion lifecycle. OCI does not rerun
# cloud-init when instance metadata changes, so artifact updates and executor
# cutovers intentionally replace the bastion. Its reserved public IP is managed
# separately and is reassociated with the replacement after the interruption.
resource "terraform_data" "cpe_remediator_artifact" {
  input = {
    artifact_sha256     = local.vpn_enabled ? local.cpe_remediator_sha256 : "vpn-disabled"
    cpe_remediator_mode = var.cpe_remediator_mode
  }

  lifecycle {
    precondition {
      condition     = var.cpe_remediator_mode != "local-remediator" || data.external.cpe_remediator_retired[0].result.retired == "true"
      error_message = "local-remediator requires the named Function and scheduler to be absent; complete retire-function first."
    }
  }
}

data "external" "cpe_remediator_retired" {
  count   = var.cpe_remediator_mode == "local-remediator" ? 1 : 0
  program = ["bash", "${path.module}/../../scripts/check-cpe-remediator-retirement.sh"]

  query = {
    compartment_id = local.compartment_id
  }
}

resource "oci_objectstorage_bucket" "cpe_remediator" {
  count          = local.vpn_enabled ? 1 : 0
  compartment_id = local.compartment_id
  name           = "oci-lab-cpe-remediator"
  namespace      = data.oci_objectstorage_namespace.current.namespace
  access_type    = "NoPublicAccess"
}

resource "oci_objectstorage_object" "cpe_remediator" {
  count        = local.vpn_enabled ? 1 : 0
  bucket       = oci_objectstorage_bucket.cpe_remediator[0].name
  namespace    = data.oci_objectstorage_namespace.current.namespace
  object       = local.cpe_remediator_object_name
  source       = local.cpe_remediator_artifact_path
  content_type = "application/octet-stream"
}
