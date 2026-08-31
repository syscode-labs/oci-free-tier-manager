package cperemediator

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestRunDoesNothingWhenDNSMatchesCurrentCPE(t *testing.T) {
	t.Parallel()

	network := &fakeNetwork{
		cpe:   CPE{ID: "cpe-old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
		ipsec: IPSecConnection{ID: "ipsec-old", DisplayName: "home-openwrt-ipsec", LifecycleState: "AVAILABLE"},
	}
	vault := &fakeVault{state: State{}}
	reconciler := New(Config{
		CompartmentID: "compartment",
		DDNSHostname:  "home.example.com",
	}, fakeDNS{ip: "203.0.113.10"}, network, vault)

	result, err := reconciler.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if result.Action != ActionNoop {
		t.Fatalf("Run() action = %q, want %q", result.Action, ActionNoop)
	}
	if network.mutations != 0 {
		t.Fatalf("network mutations = %d, want 0", network.mutations)
	}
	if vault.writes != 0 {
		t.Fatalf("vault writes = %d, want 0", vault.writes)
	}
}

func TestRunConfiguresAvailableReplacementTunnels(t *testing.T) {
	t.Parallel()
	vault := &fakeVault{state: State{Phase: phase(PhaseCPEIPSecCreated), NewIPSecID: "new"}}
	network := &fakeNetwork{ipsecLookup: IPSecConnection{LifecycleState: "AVAILABLE"}, tunnels: []Tunnel{{ID: "one"}, {ID: "two"}}, tunnelDetails: map[string]Tunnel{"one": {ID: "one", VPNIP: "192.0.2.1"}, "two": {ID: "two", VPNIP: "192.0.2.2"}}, secrets: map[string]string{"one": "psk1", "two": "psk2"}}
	result, err := New(Config{SecretID: "secret"}, fakeDNS{}, network, vault).Run(context.Background())
	if err != nil || result.Action != ActionTunnelsConfigured || *vault.state.Phase != PhaseTunnelsConfigured || network.mutations != 2 {
		t.Fatalf("result/state/mutations = %#v/%#v/%d, err = %v", result, vault.state, network.mutations, err)
	}
}

func TestRunDoesNotAdvanceWithIncompleteTunnels(t *testing.T) {
	for _, test := range []struct {
		name    string
		tunnels []Tunnel
		secrets map[string]string
		details map[string]Tunnel
	}{
		{"zero", nil, nil, nil},
		{"one", []Tunnel{{ID: "one"}}, map[string]string{"one": "psk"}, map[string]Tunnel{"one": {ID: "one", VPNIP: "192.0.2.1"}}},
		{"missing-secret", []Tunnel{{ID: "one"}, {ID: "two"}}, map[string]string{"one": "psk", "two": ""}, map[string]Tunnel{"one": {ID: "one", VPNIP: "192.0.2.1"}, "two": {ID: "two", VPNIP: "192.0.2.2"}}},
		{"duplicate-id", []Tunnel{{ID: "one"}, {ID: "one"}}, map[string]string{"one": "psk"}, map[string]Tunnel{"one": {ID: "one", VPNIP: "192.0.2.1"}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			vault := &fakeVault{state: State{Phase: phase(PhaseCPEIPSecCreated), NewIPSecID: "new"}}
			network := &fakeNetwork{ipsecLookup: IPSecConnection{LifecycleState: "AVAILABLE"}, tunnels: test.tunnels, tunnelDetails: test.details, secrets: test.secrets} // pragma: allowlist secret
			if _, err := New(Config{SecretID: "test-vault-id"}, fakeDNS{}, network, vault).Run(context.Background()); err == nil {                                        // pragma: allowlist secret
				t.Fatal("incomplete tunnels did not fail")
			}
			if vault.state.Phase == nil || *vault.state.Phase != PhaseCPEIPSecCreated || vault.writes != 0 {
				t.Fatalf("incomplete tunnels advanced state: %#v writes=%d", vault.state, vault.writes)
			}
		})
	}
}

func TestRunRequestsOldIPSecDelete(t *testing.T) {
	t.Parallel()
	vault := &fakeVault{state: State{Phase: phase(PhaseTunnelsConfigured), NewIPSecID: "new", OldIPSecID: "old"}}
	network := &fakeNetwork{
		tunnels:       []Tunnel{{ID: "one"}, {ID: "two"}},
		tunnelDetails: map[string]Tunnel{"one": {ID: "one", Status: "UP"}, "two": {ID: "two", Status: "UP"}},
	}
	result, err := New(Config{SecretID: "secret"}, fakeDNS{}, network, vault).Run(context.Background())
	if err != nil || result.Action != ActionOldIPSecDeleting || *vault.state.Phase != PhaseOldIPSecDeleting || network.mutations != 1 {
		t.Fatalf("result/state/mutations = %#v/%#v/%d, err = %v", result, vault.state, network.mutations, err)
	}
}

func TestRunWaitsForReplacementTunnelAcknowledgementBeforeOldIPSecDelete(t *testing.T) {

	for _, test := range []struct {
		name    string
		details map[string]Tunnel
		err     error
		want    string
	}{
		{"down", map[string]Tunnel{"one": {ID: "one", Status: "UP"}, "two": {ID: "two", Status: "DOWN"}}, nil, ActionWaiting},
		{"missing-status", map[string]Tunnel{"one": {ID: "one", Status: "UP"}, "two": {ID: "two"}}, nil, ActionWaiting},
		{"unavailable", nil, ErrNotFound, ActionWaiting},
		{"up", map[string]Tunnel{"one": {ID: "one", Status: "UP"}, "two": {ID: "two", Status: "UP"}}, nil, ActionOldIPSecDeleting},
	} {
		t.Run(test.name, func(t *testing.T) {
			vault := &fakeVault{state: State{Phase: phase(PhaseTunnelsConfigured), NewIPSecID: "new", OldIPSecID: "old"}}
			network := &fakeNetwork{tunnels: []Tunnel{{ID: "one"}, {ID: "two"}}, tunnelDetails: test.details, getTunnelErr: test.err}

			result, err := New(Config{SecretID: "secret"}, fakeDNS{}, network, vault).Run(context.Background())
			if err != nil || result.Action != test.want {
				t.Fatalf("Run() result/error = %#v/%v, want action %q", result, err, test.want)
			}
			if test.want == ActionWaiting && (network.mutations != 0 || vault.writes != 0 || *vault.state.Phase != PhaseTunnelsConfigured) {
				t.Fatalf("unacknowledged replacement mutated state: mutations=%d writes=%d state=%#v", network.mutations, vault.writes, vault.state)
			}
		})
	}
}

func TestRunAdvancesAfterOldIPSecWasDeletedBeforeVaultCheckpoint(t *testing.T) {
	vault := &fakeVault{state: State{Phase: phase(PhaseTunnelsConfigured), NewIPSecID: "new", OldIPSecID: "old"}, writeErrs: []error{errors.New("checkpoint failed")}}
	network := &fakeNetwork{
		tunnels:         []Tunnel{{ID: "one"}, {ID: "two"}},
		tunnelDetails:   map[string]Tunnel{"one": {ID: "one", Status: "UP"}, "two": {ID: "two", Status: "UP"}},
		deleteIPSecErrs: []error{nil, ErrNotFound},
	}
	reconciler := New(Config{SecretID: "secret"}, fakeDNS{}, network, vault)
	if _, err := reconciler.Run(context.Background()); err == nil {
		t.Fatal("checkpoint failure did not propagate")
	}
	result, err := reconciler.Run(context.Background())
	if err != nil || result.Action != ActionOldIPSecDeleting || vault.state.Phase == nil || *vault.state.Phase != PhaseOldIPSecDeleting {
		t.Fatalf("retry did not adopt deleted IPSec: result=%#v state=%#v err=%v", result, vault.state, err)
	}
}

func TestRunFinishesWhenOldIPSecIsGone(t *testing.T) {
	t.Parallel()
	vault := &fakeVault{state: State{Phase: phase(PhaseOldIPSecDeleting), OldIPSecID: "old", OldCPEID: "old-cpe", NewCPEID: "new-cpe", NewIPSecID: "new-ipsec", Tunnel1IP: phase("192.0.2.1"), Tunnel1PSK: phase("psk")}}
	network := &fakeNetwork{ipsecErr: ErrNotFound}
	result, err := New(Config{SecretID: "secret", Now: func() string { return "2026-08-17T00:00:00Z" }}, fakeDNS{}, network, vault).Run(context.Background())
	encoded, marshalErr := json.Marshal(vault.state)
	if err != nil || marshalErr != nil || result.Action != ActionRecreated || vault.state.Phase != nil || string(encoded) == "" || vault.state.UpdatedAt == nil || *vault.state.UpdatedAt != "2026-08-17T00:00:00Z" || network.mutations != 1 {
		t.Fatalf("result/state/mutations = %#v/%#v/%d, err = %v", result, vault.state, network.mutations, err)
	}
	if !strings.Contains(string(encoded), `"phase":null`) {
		t.Fatalf("final state JSON = %s, want phase null", encoded)
	}
}

func TestRunFinishesAfterOldCPEWasDeletedBeforeVaultCheckpoint(t *testing.T) {
	vault := &fakeVault{state: State{Phase: phase(PhaseOldIPSecDeleting), OldIPSecID: "old", OldCPEID: "old-cpe"}, writeErrs: []error{errors.New("checkpoint failed")}}
	network := &fakeNetwork{ipsecErr: ErrNotFound, deleteCPEErrs: []error{nil, ErrNotFound}}
	reconciler := New(Config{SecretID: "secret"}, fakeDNS{}, network, vault)
	if _, err := reconciler.Run(context.Background()); err == nil {
		t.Fatal("checkpoint failure did not propagate")
	}
	result, err := reconciler.Run(context.Background())
	if err != nil || result.Action != ActionRecreated || vault.state.Phase != nil {
		t.Fatalf("retry did not adopt deleted CPE: result=%#v state=%#v err=%v", result, vault.state, err)
	}
}

func TestRunStartsRecreateWhenDNSDiffers(t *testing.T) {
	t.Parallel()

	network := &fakeNetwork{
		cpe:          CPE{ID: "cpe-old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
		ipsec:        IPSecConnection{ID: "ipsec-old", DisplayName: "home-openwrt-ipsec"},
		createdCPE:   CPE{ID: "cpe-new"},
		createdIPSec: IPSecConnection{ID: "ipsec-new"},
	}
	vault := &fakeVault{state: State{}}
	reconciler := New(Config{
		CompartmentID:      "compartment",
		DDNSHostname:       "home.example.com",
		SecretID:           "test-vault-id", // pragma: allowlist secret
		CPELocalIdentifier: "198.51.100.9",
		DRGID:              "drg",
		StaticRouteCIDRs:   []string{"10.0.0.0/24"},
	}, fakeDNS{ip: "203.0.113.11"}, network, vault)

	result, err := reconciler.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if result.Action != ActionCPECreated {
		t.Fatalf("Run() action = %q, want %q", result.Action, ActionCPECreated)
	}
	if vault.state.Phase == nil || *vault.state.Phase != PhaseCPECreated {
		t.Fatalf("persisted phase = %#v, want %q", vault.state.Phase, PhaseCPECreated)
	}
	if vault.state.NewCPEID != "cpe-new" || vault.state.NewIPSecID != "" {
		t.Fatalf("persisted CPE-first state = %#v", vault.state)
	}
	if vault.state.OldIPSecID != "ipsec-old" {
		t.Fatalf("persisted old IPSec ID = %q, want discovered ID", vault.state.OldIPSecID)
	}
	if network.createIPSecCalls != 0 {
		t.Fatalf("IPSec creates in CPE phase = %d, want 0", network.createIPSecCalls)
	}
	encoded, marshalErr := json.Marshal(vault.state)
	if marshalErr != nil {
		t.Fatalf("marshal initial state: %v", marshalErr)
	}
	for _, field := range []string{`"tunnel1_ip":null`, `"tunnel1_psk":null`, `"tunnel2_ip":null`, `"tunnel2_psk":null`, `"updated_at":null`} {
		if !strings.Contains(string(encoded), field) {
			t.Fatalf("initial state JSON = %s, missing %s", encoded, field)
		}
	}
	if network.mutations != 1 || vault.writes != 1 {
		t.Fatalf("mutations/writes = %d/%d, want 1/1", network.mutations, vault.writes)
	}
}

func TestRunRecoversFromIPSecCreationFailureWithoutCreatingAnotherCPE(t *testing.T) {
	ctx := context.Background()
	network := &fakeNetwork{
		cpe:            CPE{ID: "cpe-old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
		ipsec:          IPSecConnection{ID: "ipsec-old", DisplayName: "home-openwrt-ipsec"},
		createdCPE:     CPE{ID: "cpe-new"},
		createdIPSec:   IPSecConnection{ID: "ipsec-new"},
		createIPSecErr: errors.New("IPSec create failed"),
	}
	vault := &fakeVault{state: State{}}
	reconciler := New(Config{CompartmentID: "compartment", DDNSHostname: "home.example.com", SecretID: "secret", DRGID: "drg"}, fakeDNS{ip: "203.0.113.11"}, network, vault)

	result, err := reconciler.Run(ctx)
	if err != nil || result.Action != "cpe_created" || vault.state.Phase == nil || *vault.state.Phase != "cpe_created" || vault.state.NewCPEID != "cpe-new" {
		t.Fatalf("first run result/state = %#v/%#v, err = %v", result, vault.state, err)
	}
	if network.createCPECalls != 1 || network.createIPSecCalls != 0 {
		t.Fatalf("first run creates = cpe:%d ipsec:%d, want 1/0", network.createCPECalls, network.createIPSecCalls)
	}

	if _, err := reconciler.Run(ctx); err == nil {
		t.Fatal("IPSec creation failure did not propagate")
	}
	if vault.state.Phase == nil || *vault.state.Phase != "cpe_created" || network.createCPECalls != 1 || network.createIPSecCalls != 1 {
		t.Fatalf("failed IPSec run lost recovery state or recreated CPE: state=%#v cpe:%d ipsec:%d", vault.state, network.createCPECalls, network.createIPSecCalls)
	}

	network.createIPSecErr = nil
	result, err = reconciler.Run(ctx)
	if err != nil || result.Action != ActionRecreateStarted || vault.state.Phase == nil || *vault.state.Phase != PhaseCPEIPSecCreated {
		t.Fatalf("recovery result/state = %#v/%#v, err = %v", result, vault.state, err)
	}
	if network.createCPECalls != 1 || network.createIPSecCalls != 2 {
		t.Fatalf("recovery creates = cpe:%d ipsec:%d, want 1/2", network.createCPECalls, network.createIPSecCalls)
	}
}

func TestRunPreservesReplacementCPEWhenInitialStateWriteFails(t *testing.T) {
	network := &fakeNetwork{
		cpe:        CPE{ID: "cpe-old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
		ipsec:      IPSecConnection{ID: "ipsec-old", DisplayName: "home-openwrt-ipsec"},
		createdCPE: CPE{ID: "cpe-new"},
	}
	vault := &fakeVault{writeErr: errors.New("Vault write failed")}
	_, err := New(Config{CompartmentID: "compartment", DDNSHostname: "home.example.com", SecretID: "secret"}, fakeDNS{ip: "203.0.113.11"}, network, vault).Run(context.Background())
	if err == nil {
		t.Fatal("initial Vault write failure did not propagate")
	}
	if network.deletedCPEID != "" || network.createIPSecCalls != 0 {
		t.Fatalf("initial write failure deleted an ambiguously persisted CPE: deleted=%q ipsec creates=%d", network.deletedCPEID, network.createIPSecCalls)
	}
}

func TestRunRecoversAmbiguousInitialCheckpointWithoutSecondCPECreate(t *testing.T) {
	network := &fakeNetwork{
		cpe:                   CPE{ID: "old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
		ipsec:                 IPSecConnection{ID: "old-ipsec", DisplayName: "home-openwrt-ipsec"},
		createdCPE:            CPE{ID: "new", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.11"},
		adoptedCPEByIP:        CPE{ID: "new", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.11"},
		findCPEByIPFirstMiss:  true,
		findCPEErrAfterCreate: errors.New("expected exactly one CPE named home-openwrt-cpe, found 2"),
	}
	vault := &fakeVault{writeErrs: []error{errors.New("timeout after commit")}}
	r := New(Config{CompartmentID: "c", DDNSHostname: "host", SecretID: "secret"}, fakeDNS{ip: "203.0.113.11"}, network, vault)
	if _, err := r.Run(context.Background()); err == nil {
		t.Fatal("initial checkpoint failure did not propagate")
	}

	result, err := r.Run(context.Background())
	if err != nil || result.Action != ActionCPECreated || vault.state.NewCPEID != "new" || vault.state.OldCPEID != "old" || network.createCPECalls != 1 {
		t.Fatalf("recovery=%#v state=%#v creates=%d err=%v", result, vault.state, network.createCPECalls, err)
	}
}

func TestRunRejectsAmbiguousInitialCheckpointRecoveryWithoutExactlyOneOldCPE(t *testing.T) {
	for _, oldCPEErr := range []error{ErrNotFound, errors.New("expected exactly one CPE named home-openwrt-cpe other than IP 203.0.113.11, found 2")} {
		network := &fakeNetwork{
			cpe:                  CPE{ID: "old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
			adoptedCPEByIP:       CPE{ID: "new", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.11"},
			oldCPEOtherThanIPErr: oldCPEErr,
			createCPECalls:       1,
			findCPEByIPFirstMiss: false,
		}
		vault := &fakeVault{}
		_, err := New(Config{CompartmentID: "c", DDNSHostname: "host", SecretID: "secret"}, fakeDNS{ip: "203.0.113.11"}, network, vault).Run(context.Background())
		if err == nil || network.createCPECalls != 1 || vault.writes != 0 {
			t.Fatalf("recovery err=%v creates=%d writes=%d", err, network.createCPECalls, vault.writes)
		}
	}
}

func TestRunAdoptsCPECreatedBeforeAmbiguousCreateError(t *testing.T) {
	network := &fakeNetwork{
		cpe:                  CPE{ID: "old", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.10"},
		ipsec:                IPSecConnection{ID: "old-ipsec", DisplayName: "home-openwrt-ipsec"},
		createCPEErr:         errors.New("timeout"),
		adoptedCPEByIP:       CPE{ID: "new", DisplayName: "home-openwrt-cpe", IPAddress: "203.0.113.11"},
		findCPEByIPFirstMiss: true,
	}
	vault := &fakeVault{}
	result, err := New(Config{CompartmentID: "c", DDNSHostname: "host", SecretID: "secret"}, fakeDNS{ip: "203.0.113.11"}, network, vault).Run(context.Background())
	if err != nil || result.Action != ActionCPECreated || vault.state.NewCPEID != "new" || network.createCPECalls != 1 || network.findCPEByIPCalls != 2 {
		t.Fatalf("ambiguous CPE create was not adopted: result=%#v state=%#v creates=%d discovers=%d err=%v", result, vault.state, network.createCPECalls, network.findCPEByIPCalls, err)
	}
}

func TestRunAdoptsIPSecCreatedBeforeAmbiguousCreateError(t *testing.T) {
	vault := &fakeVault{state: State{Phase: phase(PhaseCPECreated), NewCPEID: "new"}}
	network := &fakeNetwork{createIPSecErr: errors.New("timeout"), adoptedIPSecByCPE: IPSecConnection{ID: "new-ipsec", DisplayName: "home-openwrt-ipsec"}}
	result, err := New(Config{CompartmentID: "c", SecretID: "secret"}, fakeDNS{}, network, vault).Run(context.Background())
	if err != nil || result.Action != ActionRecreateStarted || vault.state.NewIPSecID != "new-ipsec" || network.createIPSecCalls != 1 || network.findIPSecByCPECalls != 1 {
		t.Fatalf("ambiguous IPSec create was not adopted: result=%#v state=%#v creates=%d discovers=%d err=%v", result, vault.state, network.createIPSecCalls, network.findIPSecByCPECalls, err)
	}
}

func TestRunWaitsForReplacementIPSecToBecomeAvailable(t *testing.T) {
	t.Parallel()

	vault := &fakeVault{state: State{Phase: phase(PhaseCPEIPSecCreated), NewIPSecID: "ipsec-new"}}
	reconciler := New(Config{SecretID: "test-vault-id"}, fakeDNS{}, &fakeNetwork{ // pragma: allowlist secret
		ipsecLookup: IPSecConnection{ID: "ipsec-new", LifecycleState: "PROVISIONING"},
	}, vault)

	result, err := reconciler.Run(context.Background())
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if result.Action != ActionWaiting {
		t.Fatalf("Run() action = %q, want %q", result.Action, ActionWaiting)
	}
	if vault.writes != 0 {
		t.Fatalf("vault writes = %d, want 0", vault.writes)
	}
}

func TestRunUsesConfiguredNamesAndRejectsUnknownPhase(t *testing.T) {
	network := &fakeNetwork{cpe: CPE{DisplayName: "custom-cpe", IPAddress: "203.0.113.1"}, ipsec: IPSecConnection{ID: "old", DisplayName: "custom-ipsec"}}
	_, err := New(Config{CompartmentID: "c", DDNSHostname: "host", CPEDisplayName: "custom-cpe", IPSecDisplayName: "custom-ipsec"}, fakeDNS{ip: "203.0.113.1"}, network, &fakeVault{}).Run(context.Background())
	if err != nil || network.cpeName != "custom-cpe" || network.ipsecName != "custom-ipsec" {
		t.Fatalf("custom names not used: cpe=%q ipsec=%q err=%v", network.cpeName, network.ipsecName, err)
	}
	_, err = New(Config{}, fakeDNS{}, network, &fakeVault{state: State{Phase: phase("unexpected")}}).Run(context.Background())
	if err == nil {
		t.Fatal("unknown phase did not fail")
	}
}

type fakeDNS struct{ ip string }

func (f fakeDNS) Resolve(context.Context, string) (string, error) { return f.ip, nil }

type fakeVault struct {
	state     State
	writes    int
	writeErr  error
	writeErrs []error
}

func (f *fakeVault) Read(context.Context, string) (State, error) { return f.state, nil }

func (f *fakeVault) Write(_ context.Context, _ string, state State) error {
	f.writes++
	if len(f.writeErrs) > 0 {
		err := f.writeErrs[0]
		f.writeErrs = f.writeErrs[1:]
		if err != nil {
			return err
		}
	}
	if f.writeErr != nil {
		return f.writeErr
	}
	f.state = state
	return nil
}

type fakeNetwork struct {
	cpe                   CPE
	ipsec                 IPSecConnection
	createdCPE            CPE
	createdIPSec          IPSecConnection
	ipsecLookup           IPSecConnection
	ipsecErr              error
	tunnels               []Tunnel
	tunnelDetails         map[string]Tunnel
	getTunnelErr          error
	secrets               map[string]string
	mutations             int
	createCPECalls        int
	createIPSecCalls      int
	createIPSecErr        error
	createCPEErr          error
	adoptedCPEByIP        CPE
	oldCPEOtherThanIP     CPE
	oldCPEOtherThanIPErr  error
	adoptedIPSecByCPE     IPSecConnection
	findCPEErrAfterCreate error
	findCPEByIPCalls      int
	findCPEByIPFirstMiss  bool
	findIPSecByCPECalls   int
	deleteIPSecErrs       []error
	deleteCPEErrs         []error
	deletedCPEID          string
	ipsecRequest          CreateIPSecRequest
	cpeName               string
	ipsecName             string
}

func (f *fakeNetwork) FindCPE(_ context.Context, _ string, name string) (CPE, error) {
	f.cpeName = name
	if f.createCPECalls > 0 && f.findCPEErrAfterCreate != nil {
		return CPE{}, f.findCPEErrAfterCreate
	}
	return f.cpe, nil
}
func (f *fakeNetwork) FindCPEByIP(context.Context, string, string, string) (CPE, error) {
	f.findCPEByIPCalls++
	if f.findCPEByIPFirstMiss && f.findCPEByIPCalls == 1 {
		return CPE{}, ErrNotFound
	}
	if f.adoptedCPEByIP.ID == "" || (f.createCPECalls == 0 && f.createCPEErr == nil) {
		return CPE{}, ErrNotFound
	}
	return f.adoptedCPEByIP, nil
}
func (f *fakeNetwork) FindCPEOtherThanIP(context.Context, string, string, string) (CPE, error) {
	if f.oldCPEOtherThanIPErr != nil {
		return CPE{}, f.oldCPEOtherThanIPErr
	}
	if f.oldCPEOtherThanIP.ID != "" {
		return f.oldCPEOtherThanIP, nil
	}
	if f.adoptedCPEByIP.ID != "" && (f.createCPECalls > 0 || f.createCPEErr != nil) {
		return f.cpe, nil
	}
	return CPE{}, ErrNotFound
}

func (f *fakeNetwork) FindIPSec(_ context.Context, _ string, name string) (IPSecConnection, error) {
	f.ipsecName = name
	return f.ipsec, nil
}
func (f *fakeNetwork) FindIPSecByCPE(context.Context, string, string, string) (IPSecConnection, error) {
	f.findIPSecByCPECalls++
	if f.adoptedIPSecByCPE.ID == "" {
		return IPSecConnection{}, ErrNotFound
	}
	return f.adoptedIPSecByCPE, nil
}

func (f *fakeNetwork) CreateCPE(context.Context, CreateCPERequest) (CPE, error) {
	f.mutations++
	f.createCPECalls++
	return f.createdCPE, f.createCPEErr
}

func (f *fakeNetwork) CreateIPSec(_ context.Context, request CreateIPSecRequest) (IPSecConnection, error) {
	f.ipsecRequest = request
	f.mutations++
	f.createIPSecCalls++
	return f.createdIPSec, f.createIPSecErr
}

func (f *fakeNetwork) GetIPSec(context.Context, string) (IPSecConnection, error) {
	return f.ipsecLookup, f.ipsecErr
}
func (f *fakeNetwork) ListTunnels(context.Context, string) ([]Tunnel, error) { return f.tunnels, nil }
func (f *fakeNetwork) UpdateTunnel(context.Context, string, string) error    { f.mutations++; return nil }
func (f *fakeNetwork) TunnelSecret(_ context.Context, _, id string) (string, error) {
	return f.secrets[id], nil
}
func (f *fakeNetwork) GetTunnel(_ context.Context, _, id string) (Tunnel, error) {
	return f.tunnelDetails[id], f.getTunnelErr
}
func (f *fakeNetwork) DeleteIPSec(context.Context, string) error {
	f.mutations++
	if len(f.deleteIPSecErrs) == 0 {
		return nil
	}
	err := f.deleteIPSecErrs[0]
	f.deleteIPSecErrs = f.deleteIPSecErrs[1:]
	return err
}
func (f *fakeNetwork) DeleteCPE(_ context.Context, id string) error {
	f.mutations++
	f.deletedCPEID = id
	if len(f.deleteCPEErrs) == 0 {
		return nil
	}
	err := f.deleteCPEErrs[0]
	f.deleteCPEErrs = f.deleteCPEErrs[1:]
	return err
}

func phase(value string) *string { return &value }
