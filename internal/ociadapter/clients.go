package ociadapter

import (
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/oracle/oci-go-sdk/v65/secrets"
	"github.com/oracle/oci-go-sdk/v65/vault"
)

// Clients are authenticated exclusively as the instance principal.
type Clients struct {
	Network core.VirtualNetworkClient
	Secrets secrets.SecretsClient
	Vault   vault.VaultsClient
}

func NewInstancePrincipalClients() (Clients, error) {
	provider, err := auth.InstancePrincipalConfigurationProvider()
	if err != nil {
		return Clients{}, err
	}
	network, err := core.NewVirtualNetworkClientWithConfigurationProvider(provider)
	if err != nil {
		return Clients{}, err
	}
	secretsClient, err := secrets.NewSecretsClientWithConfigurationProvider(provider)
	if err != nil {
		return Clients{}, err
	}
	vaultClient, err := vault.NewVaultsClientWithConfigurationProvider(provider)
	if err != nil {
		return Clients{}, err
	}
	return Clients{Network: network, Secrets: secretsClient, Vault: vaultClient}, nil // pragma: allowlist secret
}
