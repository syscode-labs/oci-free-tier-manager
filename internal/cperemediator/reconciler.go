package cperemediator

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"time"
)

const (
	ActionNoop              = "no-op"
	ActionCPECreated        = "cpe_created"
	ActionRecreateStarted   = "recreate_started"
	ActionWaiting           = "waiting"
	ActionTunnelsConfigured = "tunnels_configured"
	ActionOldIPSecDeleting  = "old_ipsec_deleting"
	ActionRecreated         = "recreated"
	PhaseCPECreated         = "cpe_created"
	PhaseCPEIPSecCreated    = "cpe_ipsec_created"
	PhaseTunnelsConfigured  = "tunnels_configured"
	PhaseOldIPSecDeleting   = "old_ipsec_deleting"
)

var ErrNotFound = errors.New("not found")

type Config struct {
	CompartmentID      string
	DDNSHostname       string
	SecretID           string
	CPELocalIdentifier string
	DRGID              string
	StaticRouteCIDRs   []string
	CPEDisplayName     string
	IPSecDisplayName   string
	Now                func() string
}

type State struct {
	Phase       *string `json:"phase"`
	NewCPEID    string  `json:"new_cpe_id,omitempty"`
	NewIPSecID  string  `json:"new_ipsec_id,omitempty"`
	OldCPEID    string  `json:"old_cpe_id,omitempty"`
	OldIPSecID  string  `json:"old_ipsec_id,omitempty"`
	NewPublicIP string  `json:"new_public_ip,omitempty"`
	Tunnel1IP   *string `json:"tunnel1_ip"`
	Tunnel1PSK  *string `json:"tunnel1_psk"`
	Tunnel2IP   *string `json:"tunnel2_ip"`
	Tunnel2PSK  *string `json:"tunnel2_psk"`
	UpdatedAt   *string `json:"updated_at"`
}

type CPE struct {
	ID          string
	DisplayName string
	IPAddress   string
}

type IPSecConnection struct {
	ID             string
	DisplayName    string
	LifecycleState string
}

type CreateCPERequest struct {
	CompartmentID string
	DisplayName   string
	IPAddress     string
	RetryToken    string
}

type CreateIPSecRequest struct {
	CompartmentID      string
	CPEID              string
	DRGID              string
	DisplayName        string
	StaticRouteCIDRs   []string
	CPELocalIdentifier string
	RetryToken         string
}

type Tunnel struct {
	ID     string
	VPNIP  string
	Status string
}

type DNS interface {
	Resolve(ctx context.Context, hostname string) (string, error)
}

type Network interface {
	FindCPE(ctx context.Context, compartmentID, displayName string) (CPE, error)
	FindCPEByIP(ctx context.Context, compartmentID, displayName, ipAddress string) (CPE, error)
	FindCPEOtherThanIP(ctx context.Context, compartmentID, displayName, ipAddress string) (CPE, error)
	FindIPSec(ctx context.Context, compartmentID, displayName string) (IPSecConnection, error)
	FindIPSecByCPE(ctx context.Context, compartmentID, displayName, cpeID string) (IPSecConnection, error)
	CreateCPE(ctx context.Context, request CreateCPERequest) (CPE, error)
	CreateIPSec(ctx context.Context, request CreateIPSecRequest) (IPSecConnection, error)
	GetIPSec(ctx context.Context, id string) (IPSecConnection, error)
	ListTunnels(ctx context.Context, ipsecID string) ([]Tunnel, error)
	UpdateTunnel(ctx context.Context, ipsecID, tunnelID string) error
	TunnelSecret(ctx context.Context, ipsecID, tunnelID string) (string, error)
	GetTunnel(ctx context.Context, ipsecID, tunnelID string) (Tunnel, error)
	DeleteIPSec(ctx context.Context, id string) error
	DeleteCPE(ctx context.Context, id string) error
}

type Vault interface {
	Read(ctx context.Context, secretID string) (State, error)
	Write(ctx context.Context, secretID string, state State) error
}

type Result struct {
	Action string
}

type Reconciler struct {
	config  Config
	dns     DNS
	network Network
	vault   Vault
}

func New(config Config, dns DNS, network Network, vault Vault) Reconciler {
	return Reconciler{config: config, dns: dns, network: network, vault: vault}
}

func (r Reconciler) Run(ctx context.Context) (Result, error) {
	state, err := r.vault.Read(ctx, r.config.SecretID)
	if err != nil {
		return Result{}, err
	}
	if state.Phase != nil {
		switch *state.Phase {
		case PhaseCPECreated:
			request := CreateIPSecRequest{
				CompartmentID:      r.config.CompartmentID,
				CPEID:              state.NewCPEID,
				DRGID:              r.config.DRGID,
				DisplayName:        r.ipsecDisplayName(),
				StaticRouteCIDRs:   r.config.StaticRouteCIDRs,
				CPELocalIdentifier: r.config.CPELocalIdentifier,
				RetryToken:         operationToken("ipsec", r.config.CompartmentID, state.NewCPEID, r.config.DRGID, r.ipsecDisplayName()),
			}
			newIPSec, err := r.network.CreateIPSec(ctx, request)
			if err != nil {
				newIPSec, err = r.findIPSecByCPE(ctx, request.DisplayName, state.NewCPEID)
				if err != nil {
					return Result{}, err
				}
			}
			state.NewIPSecID = newIPSec.ID
			state.Phase = stringPtr(PhaseCPEIPSecCreated)
			if err := r.vault.Write(ctx, r.config.SecretID, state); err != nil {
				return Result{}, err
			}
			return Result{Action: ActionRecreateStarted}, nil
		case PhaseCPEIPSecCreated:
			ipsec, err := r.network.GetIPSec(ctx, state.NewIPSecID)
			if err != nil {
				return Result{}, err
			}
			if ipsec.LifecycleState != "AVAILABLE" {
				return Result{Action: ActionWaiting}, nil
			}
			tunnels, err := r.network.ListTunnels(ctx, state.NewIPSecID)
			if err != nil {
				return Result{}, err
			}
			if len(tunnels) != 2 || tunnels[0].ID == "" || tunnels[1].ID == "" || tunnels[0].ID == tunnels[1].ID {
				return Result{}, fmt.Errorf("expected exactly two identified IPSec tunnels, got %d", len(tunnels))
			}
			for i, tunnel := range tunnels {
				if err := r.network.UpdateTunnel(ctx, state.NewIPSecID, tunnel.ID); err != nil {
					return Result{}, err
				}
				psk, err := r.network.TunnelSecret(ctx, state.NewIPSecID, tunnel.ID)
				if err != nil {
					return Result{}, err
				}
				if psk == "" {
					return Result{}, fmt.Errorf("IPSec tunnel %q returned an empty shared secret", tunnel.ID)
				}
				refreshed, err := r.network.GetTunnel(ctx, state.NewIPSecID, tunnel.ID)
				if err != nil {
					return Result{}, err
				}
				if refreshed.ID == "" || refreshed.VPNIP == "" {
					return Result{}, fmt.Errorf("IPSec tunnel %q is missing its ID or VPN IP", tunnel.ID)
				}
				if i == 0 {
					state.Tunnel1IP, state.Tunnel1PSK = stringPtr(refreshed.VPNIP), stringPtr(psk)
				}
				if i == 1 {
					state.Tunnel2IP, state.Tunnel2PSK = stringPtr(refreshed.VPNIP), stringPtr(psk)
				}
			}
			state.Phase = stringPtr(PhaseTunnelsConfigured)
			if err := r.vault.Write(ctx, r.config.SecretID, state); err != nil {
				return Result{}, err
			}
			return Result{Action: ActionTunnelsConfigured}, nil
		case PhaseTunnelsConfigured:
			tunnels, err := r.network.ListTunnels(ctx, state.NewIPSecID)
			if err != nil || len(tunnels) != 2 {
				return Result{Action: ActionWaiting}, nil
			}
			for _, tunnel := range tunnels {
				current, err := r.network.GetTunnel(ctx, state.NewIPSecID, tunnel.ID)
				if err != nil || current.Status != "UP" {
					return Result{Action: ActionWaiting}, nil
				}
			}
			if err := r.network.DeleteIPSec(ctx, state.OldIPSecID); err != nil && !errors.Is(err, ErrNotFound) {
				return Result{}, err
			}
			state.Phase = stringPtr(PhaseOldIPSecDeleting)
			if err := r.vault.Write(ctx, r.config.SecretID, state); err != nil {
				return Result{}, err
			}
			return Result{Action: ActionOldIPSecDeleting}, nil
		case PhaseOldIPSecDeleting:
			old, err := r.network.GetIPSec(ctx, state.OldIPSecID)
			if err != nil && !errors.Is(err, ErrNotFound) {
				return Result{}, err
			}
			if err == nil && old.LifecycleState != "TERMINATED" {
				return Result{Action: ActionWaiting}, nil
			}
			if err := r.network.DeleteCPE(ctx, state.OldCPEID); err != nil && !errors.Is(err, ErrNotFound) {
				return Result{}, err
			}
			state.Phase = nil
			if r.config.Now != nil {
				state.UpdatedAt = stringPtr(r.config.Now())
			} else {
				state.UpdatedAt = stringPtr(time.Now().UTC().Format(time.RFC3339))
			}
			state.OldCPEID, state.OldIPSecID, state.NewPublicIP = "", "", ""
			if err := r.vault.Write(ctx, r.config.SecretID, state); err != nil {
				return Result{}, err
			}
			return Result{Action: ActionRecreated}, nil
		default:
			return Result{}, fmt.Errorf("unknown persisted phase %q", *state.Phase)
		}
	}

	cpeName := r.config.CPEDisplayName
	if cpeName == "" {
		cpeName = "home-openwrt-cpe"
	}
	ipsecName := r.ipsecDisplayName()
	dnsIP, err := r.dns.Resolve(ctx, r.config.DDNSHostname)
	if err != nil {
		return Result{}, err
	}
	if replacement, err := r.network.FindCPEByIP(ctx, r.config.CompartmentID, cpeName, dnsIP); err == nil {
		oldCPE, err := r.network.FindCPEOtherThanIP(ctx, r.config.CompartmentID, cpeName, dnsIP)
		if err == nil {
			oldIPSec, err := r.network.FindIPSec(ctx, r.config.CompartmentID, ipsecName)
			if err != nil {
				return Result{}, err
			}
			next := State{Phase: stringPtr(PhaseCPECreated), NewCPEID: replacement.ID, OldCPEID: oldCPE.ID, OldIPSecID: oldIPSec.ID, NewPublicIP: dnsIP}
			if err := r.vault.Write(ctx, r.config.SecretID, next); err != nil {
				return Result{}, err
			}
			return Result{Action: ActionCPECreated}, nil
		}
		if !errors.Is(err, ErrNotFound) {
			return Result{}, err
		}
		cpe, err := r.network.FindCPE(ctx, r.config.CompartmentID, cpeName)
		if err != nil {
			return Result{}, err
		}
		if cpe.ID == replacement.ID {
			return Result{Action: ActionNoop}, nil
		}
		return Result{}, fmt.Errorf("found CPE %q at replacement IP %q but no unique old CPE", replacement.ID, dnsIP)
	} else if !errors.Is(err, ErrNotFound) {
		return Result{}, err
	}
	cpe, err := r.network.FindCPE(ctx, r.config.CompartmentID, cpeName)
	if err != nil {
		return Result{}, err
	}
	oldIPSec, err := r.network.FindIPSec(ctx, r.config.CompartmentID, ipsecName)
	if err != nil {
		return Result{}, err
	}
	if dnsIP == cpe.IPAddress {
		return Result{Action: ActionNoop}, nil
	}
	cpeRequest := CreateCPERequest{
		CompartmentID: r.config.CompartmentID,
		DisplayName:   cpe.DisplayName,
		IPAddress:     dnsIP,
		RetryToken:    operationToken("cpe", r.config.CompartmentID, cpe.DisplayName, dnsIP),
	}
	newCPE, err := r.network.CreateCPE(ctx, cpeRequest)
	if err != nil {
		newCPE, err = r.findCPEByIP(ctx, cpeRequest.DisplayName, dnsIP)
		if err != nil {
			return Result{}, err
		}
	}
	next := State{
		Phase:       stringPtr(PhaseCPECreated),
		NewCPEID:    newCPE.ID,
		OldCPEID:    cpe.ID,
		OldIPSecID:  oldIPSec.ID,
		NewPublicIP: dnsIP,
	}
	if err := r.vault.Write(ctx, r.config.SecretID, next); err != nil {
		return Result{}, err
	}
	return Result{Action: ActionCPECreated}, nil
}

func (r Reconciler) ipsecDisplayName() string {
	if r.config.IPSecDisplayName != "" {
		return r.config.IPSecDisplayName
	}
	return "home-openwrt-ipsec"
}

func (r Reconciler) findCPEByIP(ctx context.Context, name, ipAddress string) (CPE, error) {
	var cpe CPE
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		cpe, err = r.network.FindCPEByIP(ctx, r.config.CompartmentID, name, ipAddress)
		if err == nil {
			return cpe, nil
		}
		time.Sleep(time.Duration(attempt+1) * 100 * time.Millisecond)
	}
	return CPE{}, err
}

func (r Reconciler) findIPSecByCPE(ctx context.Context, name, cpeID string) (IPSecConnection, error) {
	var ipsec IPSecConnection
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		ipsec, err = r.network.FindIPSecByCPE(ctx, r.config.CompartmentID, name, cpeID)
		if err == nil {
			return ipsec, nil
		}
		time.Sleep(time.Duration(attempt+1) * 100 * time.Millisecond)
	}
	return IPSecConnection{}, err
}

func operationToken(parts ...string) string {
	hash := sha256.Sum256([]byte(fmt.Sprintf("%q", parts)))
	return fmt.Sprintf("%x", hash[:])
}

func stringPtr(value string) *string { return &value }
