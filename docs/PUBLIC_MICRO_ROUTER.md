# Public Micro router rollout

The router is deployed in place with `scripts/configure-bastion-router.sh`.
Do not change bastion cloud-init metadata merely to install Tailscale: OCI
replaces the VM for metadata changes, removing the SSH recovery path and
changing the private address used by the private Micro's SSH firewall.

1. Review and apply the existing Deploy workflow with only the bastion and
   its two security lists targeted. Reject any instance replacement. Keep
   the reserved public IP resource unchanged.
2. Copy the committed script to `/usr/local/sbin/configure-bastion-router`
   with root ownership and mode 0700. Obtain the existing Tailscale auth key
   through the approved secret channel into a root-only temporary file.
   Never place it in logs, command-line literals, or source control.
3. Run `sudo /usr/local/sbin/configure-bastion-router "$TALOS_CIDR" "$KEY_FILE"`.
   This installs Tailscale and forwarding but does not advertise a route.
   Delete the temporary key after the command exits. Existing joined nodes
   do not need a key file.
4. Verify direct peer transport from Omni, the live OCI source/destination
   check exemption, and TCP/TLS from the bastion to the private API.
5. Activate with
   `sudo /usr/local/sbin/configure-bastion-router "$TALOS_CIDR" '' true`.
   Verify the selected route and real API operations immediately. If the
   new path fails, withdraw only the new advertisement with
   `sudo tailscale set --advertise-routes=`. Keep old routers until proof.
6. Retire old advertisements and proxy ownership only after end-to-end proof.

The guest keeps identity and preferences in `/var/lib/tailscale`, forwarding
in `/etc/sysctl.d/99-tailscale-router.conf`, and the transport firewall rule
in UFW. These survive ordinary reboot. A future VM replacement must explicitly
repeat this staged rollout; cloud-init alone does not activate the router.
Private network values belong in encrypted configuration or the private
execution record, not this document.
