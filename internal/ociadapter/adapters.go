package ociadapter

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/oracle/oci-go-sdk/v65/secrets"
	"github.com/oracle/oci-go-sdk/v65/vault"
	"github.com/syscode-labs/oci-free-tier-manager/internal/cperemediator"
)

type DNS struct{}

var lookupHost = net.DefaultResolver.LookupHost

func (DNS) Resolve(ctx context.Context, hostname string) (string, error) {
	addresses, err := lookupHost(ctx, hostname)
	if err != nil {
		return "", err
	}
	for _, address := range addresses {
		if parsed := net.ParseIP(address); parsed != nil && parsed.To4() != nil {
			return parsed.String(), nil
		}
	}
	return "", fmt.Errorf("DNS returned no IPv4 address for %q", hostname)
}

type Network struct{ client core.VirtualNetworkClient }
type Vault struct {
	secrets secrets.SecretsClient
	vault   vault.VaultsClient
}

func NewAdapters(clients Clients) (cperemediator.DNS, cperemediator.Network, cperemediator.Vault) {
	return DNS{}, Network{client: clients.Network}, Vault{secrets: clients.Secrets, vault: clients.Vault} // pragma: allowlist secret
}

func (n Network) FindCPE(ctx context.Context, compartment, name string) (cperemediator.CPE, error) {
	r, e := n.client.ListCpes(ctx, core.ListCpesRequest{CompartmentId: common.String(compartment)})
	if e != nil {
		return cperemediator.CPE{}, e
	}
	return selectCPE(r.Items, name)
}
func (n Network) FindCPEByIP(ctx context.Context, compartment, name, ipAddress string) (cperemediator.CPE, error) {
	r, e := n.client.ListCpes(ctx, core.ListCpesRequest{CompartmentId: common.String(compartment)})
	if e != nil {
		return cperemediator.CPE{}, e
	}
	return selectCPEByIP(r.Items, name, ipAddress)
}
func (n Network) FindCPEOtherThanIP(ctx context.Context, compartment, name, ipAddress string) (cperemediator.CPE, error) {
	r, e := n.client.ListCpes(ctx, core.ListCpesRequest{CompartmentId: common.String(compartment)})
	if e != nil {
		return cperemediator.CPE{}, e
	}
	return selectCPEOtherThanIP(r.Items, name, ipAddress)
}
func (n Network) FindIPSec(ctx context.Context, compartment, name string) (cperemediator.IPSecConnection, error) {
	r, e := n.client.ListIPSecConnections(ctx, core.ListIPSecConnectionsRequest{CompartmentId: common.String(compartment)})
	if e != nil {
		return cperemediator.IPSecConnection{}, e
	}
	return selectIPSec(r.Items, name)
}
func (n Network) FindIPSecByCPE(ctx context.Context, compartment, name, cpeID string) (cperemediator.IPSecConnection, error) {
	r, e := n.client.ListIPSecConnections(ctx, core.ListIPSecConnectionsRequest{CompartmentId: common.String(compartment)})
	if e != nil {
		return cperemediator.IPSecConnection{}, e
	}
	return selectIPSecByCPE(r.Items, name, cpeID)
}
func (n Network) CreateCPE(ctx context.Context, q cperemediator.CreateCPERequest) (cperemediator.CPE, error) {
	r, e := n.client.CreateCpe(ctx, core.CreateCpeRequest{OpcRetryToken: common.String(q.RetryToken), CreateCpeDetails: core.CreateCpeDetails{CompartmentId: common.String(q.CompartmentID), DisplayName: common.String(q.DisplayName), IpAddress: common.String(q.IPAddress)}})
	return cperemediator.CPE{ID: stringValue(r.Id), DisplayName: stringValue(r.DisplayName), IPAddress: stringValue(r.IpAddress)}, e
}
func (n Network) CreateIPSec(ctx context.Context, q cperemediator.CreateIPSecRequest) (cperemediator.IPSecConnection, error) {
	r, e := n.client.CreateIPSecConnection(ctx, core.CreateIPSecConnectionRequest{OpcRetryToken: common.String(q.RetryToken), CreateIpSecConnectionDetails: core.CreateIpSecConnectionDetails{CompartmentId: common.String(q.CompartmentID), CpeId: common.String(q.CPEID), DrgId: common.String(q.DRGID), DisplayName: common.String(q.DisplayName), StaticRoutes: q.StaticRouteCIDRs, CpeLocalIdentifier: common.String(q.CPELocalIdentifier), CpeLocalIdentifierType: core.CreateIpSecConnectionDetailsCpeLocalIdentifierTypeIpAddress}})
	return cperemediator.IPSecConnection{ID: stringValue(r.Id), DisplayName: stringValue(r.DisplayName), LifecycleState: string(r.LifecycleState)}, e
}
func (n Network) GetIPSec(ctx context.Context, id string) (cperemediator.IPSecConnection, error) {
	r, e := n.client.GetIPSecConnection(ctx, core.GetIPSecConnectionRequest{IpscId: common.String(id)})
	if e != nil {
		return cperemediator.IPSecConnection{}, mapNotFound(e)
	}
	return cperemediator.IPSecConnection{ID: stringValue(r.Id), DisplayName: stringValue(r.DisplayName), LifecycleState: string(r.LifecycleState)}, nil
}
func (n Network) ListTunnels(ctx context.Context, id string) ([]cperemediator.Tunnel, error) {
	r, e := n.client.ListIPSecConnectionTunnels(ctx, core.ListIPSecConnectionTunnelsRequest{IpscId: common.String(id)})
	if e != nil {
		return nil, e
	}
	out := make([]cperemediator.Tunnel, len(r.Items))
	for i, v := range r.Items {
		out[i] = cperemediator.Tunnel{ID: stringValue(v.Id)}
	}
	return out, nil
}
func (n Network) UpdateTunnel(ctx context.Context, id, tunnel string) error {
	_, e := n.client.UpdateIPSecConnectionTunnel(ctx, core.UpdateIPSecConnectionTunnelRequest{IpscId: common.String(id), TunnelId: common.String(tunnel), UpdateIpSecConnectionTunnelDetails: core.UpdateIpSecConnectionTunnelDetails{Routing: core.UpdateIpSecConnectionTunnelDetailsRoutingStatic, IkeVersion: core.UpdateIpSecConnectionTunnelDetailsIkeVersionV2, PhaseOneConfig: &core.PhaseOneConfigDetails{IsCustomPhaseOneConfig: common.Bool(true), EncryptionAlgorithm: core.PhaseOneConfigDetailsEncryptionAlgorithm256Cbc, AuthenticationAlgorithm: core.PhaseOneConfigDetailsAuthenticationAlgorithmSha2384, DiffieHelmanGroup: core.PhaseOneConfigDetailsDiffieHelmanGroupGroup14}, PhaseTwoConfig: &core.PhaseTwoConfigDetails{IsCustomPhaseTwoConfig: common.Bool(true), EncryptionAlgorithm: core.PhaseTwoConfigDetailsEncryptionAlgorithm256Cbc, AuthenticationAlgorithm: core.PhaseTwoConfigDetailsAuthenticationAlgorithmSha2256128, IsPfsEnabled: common.Bool(true), PfsDhGroup: core.PhaseTwoConfigDetailsPfsDhGroupGroup5}}})
	return e
}
func (n Network) TunnelSecret(ctx context.Context, id, tunnel string) (string, error) {
	r, e := n.client.GetIPSecConnectionTunnelSharedSecret(ctx, core.GetIPSecConnectionTunnelSharedSecretRequest{IpscId: common.String(id), TunnelId: common.String(tunnel)})
	return stringValue(r.SharedSecret), e
}
func (n Network) GetTunnel(ctx context.Context, id, tunnel string) (cperemediator.Tunnel, error) {
	r, e := n.client.GetIPSecConnectionTunnel(ctx, core.GetIPSecConnectionTunnelRequest{IpscId: common.String(id), TunnelId: common.String(tunnel)})
	return cperemediator.Tunnel{ID: stringValue(r.Id), VPNIP: stringValue(r.VpnIp), Status: string(r.Status)}, e
}
func (n Network) DeleteIPSec(ctx context.Context, id string) error {
	_, e := n.client.DeleteIPSecConnection(ctx, core.DeleteIPSecConnectionRequest{IpscId: common.String(id)})
	return mapNotFound(e)
}
func (n Network) DeleteCPE(ctx context.Context, id string) error {
	_, e := n.client.DeleteCpe(ctx, core.DeleteCpeRequest{CpeId: common.String(id)})
	return mapNotFound(e)
}
func (v Vault) Read(ctx context.Context, id string) (cperemediator.State, error) {
	r, e := v.secrets.GetSecretBundle(ctx, secrets.GetSecretBundleRequest{SecretId: common.String(id)})
	if e != nil {
		return cperemediator.State{}, e
	}
	content := r.SecretBundleContent.(secrets.Base64SecretBundleContentDetails)
	return decodeState(stringValue(content.Content))
}
func (v Vault) Write(ctx context.Context, id string, s cperemediator.State) error {
	encoded, e := encodeState(s)
	if e != nil {
		return e
	}
	_, e = v.vault.UpdateSecret(ctx, vault.UpdateSecretRequest{SecretId: common.String(id), UpdateSecretDetails: vault.UpdateSecretDetails{SecretContent: vault.Base64SecretContentDetails{Content: common.String(encoded)}}})
	return e
}
func encodeState(state cperemediator.State) (string, error) {
	raw, err := json.Marshal(state)
	return base64.StdEncoding.EncodeToString(raw), err
}
func decodeState(encoded string) (cperemediator.State, error) {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return cperemediator.State{}, err
	}
	var state cperemediator.State
	err = json.Unmarshal(raw, &state)
	return state, err
}
func mapNotFound(err error) error {
	var service common.ServiceError
	if errors.As(err, &service) && service.GetHTTPStatusCode() == 404 {
		return cperemediator.ErrNotFound
	}
	return err
}
func stringValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func selectCPE(items []core.Cpe, name string) (cperemediator.CPE, error) {
	matches := make([]core.Cpe, 0, 1)
	for _, item := range items {
		if stringValue(item.DisplayName) == name {
			matches = append(matches, item)
		}
	}
	if len(matches) != 1 {
		return cperemediator.CPE{}, fmt.Errorf("expected exactly one CPE named %q, found %d", name, len(matches))
	}
	item := matches[0]
	return cperemediator.CPE{ID: stringValue(item.Id), DisplayName: stringValue(item.DisplayName), IPAddress: stringValue(item.IpAddress)}, nil
}
func selectCPEByIP(items []core.Cpe, name, ipAddress string) (cperemediator.CPE, error) {
	matches := make([]core.Cpe, 0, 1)
	for _, item := range items {
		if stringValue(item.DisplayName) == name && stringValue(item.IpAddress) == ipAddress {
			matches = append(matches, item)
		}
	}
	if len(matches) == 0 {
		return cperemediator.CPE{}, cperemediator.ErrNotFound
	}
	if len(matches) != 1 {
		return cperemediator.CPE{}, fmt.Errorf("expected exactly one CPE named %q with IP %q, found %d", name, ipAddress, len(matches))
	}
	item := matches[0]
	return cperemediator.CPE{ID: stringValue(item.Id), DisplayName: stringValue(item.DisplayName), IPAddress: stringValue(item.IpAddress)}, nil
}
func selectCPEOtherThanIP(items []core.Cpe, name, ipAddress string) (cperemediator.CPE, error) {
	matches := make([]core.Cpe, 0, 1)
	for _, item := range items {
		if stringValue(item.DisplayName) == name && stringValue(item.IpAddress) != ipAddress {
			matches = append(matches, item)
		}
	}
	if len(matches) == 0 {
		return cperemediator.CPE{}, cperemediator.ErrNotFound
	}
	if len(matches) != 1 {
		return cperemediator.CPE{}, fmt.Errorf("expected exactly one CPE named %q other than IP %q, found %d", name, ipAddress, len(matches))
	}
	item := matches[0]
	return cperemediator.CPE{ID: stringValue(item.Id), DisplayName: stringValue(item.DisplayName), IPAddress: stringValue(item.IpAddress)}, nil
}
func selectIPSec(items []core.IpSecConnection, name string) (cperemediator.IPSecConnection, error) {
	matches := make([]core.IpSecConnection, 0, 1)
	for _, item := range items {
		if stringValue(item.DisplayName) == name && item.LifecycleState == core.IpSecConnectionLifecycleStateAvailable {
			matches = append(matches, item)
		}
	}
	if len(matches) != 1 {
		return cperemediator.IPSecConnection{}, fmt.Errorf("expected exactly one available IPSec named %q, found %d", name, len(matches))
	}
	item := matches[0]
	return cperemediator.IPSecConnection{ID: stringValue(item.Id), DisplayName: stringValue(item.DisplayName), LifecycleState: string(item.LifecycleState)}, nil
}
func selectIPSecByCPE(items []core.IpSecConnection, name, cpeID string) (cperemediator.IPSecConnection, error) {
	matches := make([]core.IpSecConnection, 0, 1)
	for _, item := range items {
		if stringValue(item.DisplayName) == name && stringValue(item.CpeId) == cpeID {
			matches = append(matches, item)
		}
	}
	if len(matches) != 1 {
		return cperemediator.IPSecConnection{}, fmt.Errorf("expected exactly one IPSec connection named %q for CPE %q, found %d", name, cpeID, len(matches))
	}
	item := matches[0]
	return cperemediator.IPSecConnection{ID: stringValue(item.Id), DisplayName: stringValue(item.DisplayName), LifecycleState: string(item.LifecycleState)}, nil
}
