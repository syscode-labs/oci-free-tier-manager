package main

import (
	"context"
	"testing"

	"github.com/syscode-labs/oci-free-tier-manager/internal/cperemediator"
)

func TestRunExecutesReconcilerWithSuppliedAdapters(t *testing.T) {
	vault := &commandVault{}
	result, err := run(context.Background(), cperemediator.Config{CompartmentID: "compartment", DDNSHostname: "home.example", SecretID: "secret"}, commandDNS{}, commandNetwork{}, vault)
	if err != nil || result.Action != cperemediator.ActionNoop || vault.reads != 1 {
		t.Fatalf("result=%#v reads=%d err=%v", result, vault.reads, err)
	}
}

func TestConfigFromEnvUsesOptionalCustomNames(t *testing.T) {
	for key, value := range map[string]string{"COMPARTMENT_ID": "c", "DDNS_HOSTNAME": "h", "CPE_LOCAL_IDENTIFIER": "i", "DRG_ID": "d", "STATIC_ROUTE_CIDRS_JSON": "[]", "SECRET_ID": "s", "CPE_DISPLAY_NAME": "custom-cpe", "IPSEC_DISPLAY_NAME": "custom-ipsec"} {
		t.Setenv(key, value)
	}
	config, err := configFromEnv()
	if err != nil || config.CPEDisplayName != "custom-cpe" || config.IPSecDisplayName != "custom-ipsec" {
		t.Fatalf("config=%#v err=%v", config, err)
	}
}

type commandDNS struct{}

func (commandDNS) Resolve(context.Context, string) (string, error) { return "203.0.113.1", nil }

type commandNetwork struct{}

func (commandNetwork) FindCPE(context.Context, string, string) (cperemediator.CPE, error) {
	return cperemediator.CPE{IPAddress: "203.0.113.1"}, nil
}
func (commandNetwork) FindCPEByIP(context.Context, string, string, string) (cperemediator.CPE, error) {
	return cperemediator.CPE{}, cperemediator.ErrNotFound
}
func (commandNetwork) FindCPEOtherThanIP(context.Context, string, string, string) (cperemediator.CPE, error) {
	return cperemediator.CPE{}, cperemediator.ErrNotFound
}
func (commandNetwork) FindIPSec(context.Context, string, string) (cperemediator.IPSecConnection, error) {
	return cperemediator.IPSecConnection{}, nil
}
func (commandNetwork) FindIPSecByCPE(context.Context, string, string, string) (cperemediator.IPSecConnection, error) {
	panic("unexpected")
}
func (commandNetwork) CreateCPE(context.Context, cperemediator.CreateCPERequest) (cperemediator.CPE, error) {
	panic("unexpected")
}
func (commandNetwork) CreateIPSec(context.Context, cperemediator.CreateIPSecRequest) (cperemediator.IPSecConnection, error) {
	panic("unexpected")
}
func (commandNetwork) GetIPSec(context.Context, string) (cperemediator.IPSecConnection, error) {
	panic("unexpected")
}
func (commandNetwork) ListTunnels(context.Context, string) ([]cperemediator.Tunnel, error) {
	panic("unexpected")
}
func (commandNetwork) UpdateTunnel(context.Context, string, string) error { panic("unexpected") }
func (commandNetwork) TunnelSecret(context.Context, string, string) (string, error) {
	panic("unexpected")
}
func (commandNetwork) GetTunnel(context.Context, string, string) (cperemediator.Tunnel, error) {
	panic("unexpected")
}
func (commandNetwork) DeleteIPSec(context.Context, string) error { panic("unexpected") }
func (commandNetwork) DeleteCPE(context.Context, string) error   { panic("unexpected") }

type commandVault struct{ reads int }

func (v *commandVault) Read(context.Context, string) (cperemediator.State, error) {
	v.reads++
	return cperemediator.State{}, nil
}
func (*commandVault) Write(context.Context, string, cperemediator.State) error { return nil }
