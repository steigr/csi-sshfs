package sshfs

import (
	"context"
	"github.com/container-storage-interface/spec/lib/go/csi"
)

func NewIdentityServer(driverInstance DriverInstance) *IdentityServer {
	return &IdentityServer{
		Driver: &driverInstance,
	}
}

type IdentityServer struct {
	Driver *DriverInstance
}

func (ids *IdentityServer) GetPluginInfo(ctx context.Context, request *csi.GetPluginInfoRequest) (*csi.GetPluginInfoResponse, error) {
	return &csi.GetPluginInfoResponse{
		Name:          ids.Driver.csiDriverName,
		VendorVersion: ids.Driver.version,
	}, nil
}

func (ids *IdentityServer) GetPluginCapabilities(ctx context.Context, request *csi.GetPluginCapabilitiesRequest) (*csi.GetPluginCapabilitiesResponse, error) {
	return &csi.GetPluginCapabilitiesResponse{Capabilities: ids.Driver.capPlugin}, nil
}

func (ids *IdentityServer) Probe(ctx context.Context, request *csi.ProbeRequest) (*csi.ProbeResponse, error) {
	return &csi.ProbeResponse{}, nil
}
