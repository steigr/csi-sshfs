package sshfs

import (
	"context"
	"github.com/container-storage-interface/spec/lib/go/csi"
)

func NewIdentityServer(driverInstance DriverInstance) *IdentityServer {
	return &IdentityServer{
		instance: &driverInstance,
	}
}

type IdentityServer struct {
	instance *DriverInstance
}

// GetPluginInfo returns metadata of the plugin
func (ids *IdentityServer) GetPluginInfo(ctx context.Context, request *csi.GetPluginInfoRequest) (*csi.GetPluginInfoResponse, error) {
	return &csi.GetPluginInfoResponse{
		Name:          ids.instance.csiDriverName,
		VendorVersion: ids.instance.version,
	}, nil
}

// GetPluginCapabilities returns available capabilities of the plugin
func (ids *IdentityServer) GetPluginCapabilities(ctx context.Context, request *csi.GetPluginCapabilitiesRequest) (*csi.GetPluginCapabilitiesResponse, error) {
	return &csi.GetPluginCapabilitiesResponse{
		Capabilities: []*csi.PluginCapability{
			//{Type: &csi.PluginCapability_Service_{Service: &csi.PluginCapability_Service{Type: csi.PluginCapability_Service_CONTROLLER_SERVICE}}} // NOTE: don't report controller service if no controller
		},
	}, nil
}

// Probe returns the health and readiness of the plugin
func (ids *IdentityServer) Probe(ctx context.Context, request *csi.ProbeRequest) (*csi.ProbeResponse, error) {
	return &csi.ProbeResponse{}, nil
}
