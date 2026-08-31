package ociadapter

import (
	"context"
	"errors"
	"testing"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/syscode-labs/oci-free-tier-manager/internal/cperemediator"
)

func TestDNSResolveSelectsIPv4AndRejectsIPv6Only(t *testing.T) {
	original := lookupHost
	t.Cleanup(func() { lookupHost = original })
	lookupHost = func(context.Context, string) ([]string, error) { return []string{"2001:db8::1", "203.0.113.9"}, nil }
	ip, err := (DNS{}).Resolve(context.Background(), "example.test")
	if err != nil || ip != "203.0.113.9" {
		t.Fatalf("ip=%q err=%v", ip, err)
	}
	lookupHost = func(context.Context, string) ([]string, error) { return []string{"2001:db8::1"}, nil }
	if _, err := (DNS{}).Resolve(context.Background(), "example.test"); err == nil {
		t.Fatal("IPv6-only response succeeded")
	}
}

func TestVaultStateBase64RoundTripPreservesNullSchema(t *testing.T) {
	encoded, err := encodeState(cperemediator.State{})
	if err != nil {
		t.Fatal(err)
	}
	state, err := decodeState(encoded)
	if err != nil || state.Phase != nil || state.Tunnel1IP != nil || state.UpdatedAt != nil {
		t.Fatalf("state=%#v err=%v", state, err)
	}
}

func TestExactLookupsRejectZeroAndDuplicates(t *testing.T) {
	if _, err := selectCPE(nil, "name"); err == nil {
		t.Fatal("zero CPE matches succeeded")
	}
	if _, err := selectCPE([]core.Cpe{{DisplayName: common.String("name")}, {DisplayName: common.String("name")}}, "name"); err == nil {
		t.Fatal("duplicate CPE matches succeeded")
	}
	if _, err := selectCPEByIP(nil, "name", "203.0.113.11"); !errors.Is(err, cperemediator.ErrNotFound) {
		t.Fatalf("zero CPE-by-IP matches err = %v, want ErrNotFound", err)
	}
	if _, err := selectCPEByIP([]core.Cpe{{DisplayName: common.String("name"), IpAddress: common.String("203.0.113.11")}, {DisplayName: common.String("name"), IpAddress: common.String("203.0.113.11")}}, "name", "203.0.113.11"); err == nil {
		t.Fatal("duplicate CPE-by-IP matches succeeded")
	}
	if _, err := selectIPSec([]core.IpSecConnection{{DisplayName: common.String("name"), LifecycleState: core.IpSecConnectionLifecycleStateAvailable}, {DisplayName: common.String("name"), LifecycleState: core.IpSecConnectionLifecycleStateAvailable}}, "name"); err == nil {
		t.Fatal("duplicate IPSec matches succeeded")
	}
}
