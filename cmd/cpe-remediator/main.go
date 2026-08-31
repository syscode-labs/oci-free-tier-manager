package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"

	"github.com/syscode-labs/oci-free-tier-manager/internal/cperemediator"
	"github.com/syscode-labs/oci-free-tier-manager/internal/ociadapter"
)

func main() {
	config, err := configFromEnv()
	if err != nil {
		slog.Error("invalid remediator configuration", "error", err)
		os.Exit(1)
	}
	clients, err := ociadapter.NewInstancePrincipalClients()
	if err != nil {
		slog.Error("initialize OCI instance-principal clients", "error", err)
		os.Exit(1)
	}
	dns, network, vault := ociadapter.NewAdapters(clients)
	result, err := run(context.Background(), config, dns, network, vault)
	if err != nil {
		slog.Error("CPE remediation failed", "error", err)
		os.Exit(1)
	}
	slog.Info("CPE remediation completed", "action", result.Action)
}

func run(ctx context.Context, config cperemediator.Config, dns cperemediator.DNS, network cperemediator.Network, vault cperemediator.Vault) (cperemediator.Result, error) {
	return cperemediator.New(config, dns, network, vault).Run(ctx)
}

func configFromEnv() (cperemediator.Config, error) {
	read := func(name string) (string, error) {
		value := os.Getenv(name)
		if value == "" {
			return "", fmt.Errorf("%s is required", name)
		}
		return value, nil
	}
	compartmentID, err := read("COMPARTMENT_ID")
	if err != nil {
		return cperemediator.Config{}, err
	}
	hostname, err := read("DDNS_HOSTNAME")
	if err != nil {
		return cperemediator.Config{}, err
	}
	identifier, err := read("CPE_LOCAL_IDENTIFIER")
	if err != nil {
		return cperemediator.Config{}, err
	}
	drgID, err := read("DRG_ID")
	if err != nil {
		return cperemediator.Config{}, err
	}
	secretID, err := read("SECRET_ID")
	if err != nil {
		return cperemediator.Config{}, err
	}
	routesJSON, err := read("STATIC_ROUTE_CIDRS_JSON")
	if err != nil {
		return cperemediator.Config{}, err
	}
	var routes []string
	if err := json.Unmarshal([]byte(routesJSON), &routes); err != nil {
		return cperemediator.Config{}, fmt.Errorf("STATIC_ROUTE_CIDRS_JSON: %w", err)
	}
	return cperemediator.Config{CompartmentID: compartmentID, DDNSHostname: hostname, CPELocalIdentifier: identifier, DRGID: drgID, StaticRouteCIDRs: routes, SecretID: secretID, CPEDisplayName: envOrDefault("CPE_DISPLAY_NAME", "home-openwrt-cpe"), IPSecDisplayName: envOrDefault("IPSEC_DISPLAY_NAME", "home-openwrt-ipsec")}, nil
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
