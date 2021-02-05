package sshfs

import (
	"fmt"
	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc"
	"k8s.io/klog/v2"
	"net"
	"os"
)

func NewDriverInstance(nodeID string, endpoint string) *DriverInstance {
	klog.Infof("Starting new %s driver in version %s built %s", driverName, Version, BuildTime)
	var vc []*csi.VolumeCapability_AccessMode
	vc = append(vc, &csi.VolumeCapability_AccessMode{Mode: csi.VolumeCapability_AccessMode_MULTI_NODE_MULTI_WRITER})

	return &DriverInstance{
		csiDriverName: driverName,
		version:       Version,
		nodeID:        nodeID,
		endpoint:      endpoint,
		capPlugin:     capPlugin,
		capController: capController,
		capNode:       capNode,
		capVolume:     capVolume,
	}
}

type DriverInstance struct {
	csiDriverName string
	version       string
	nodeID        string
	endpoint      string
	capPlugin     []*csi.PluginCapability
	capController []*csi.ControllerServiceCapability
	capNode       []*csi.NodeServiceCapability
	capVolume     []*csi.VolumeCapability_AccessMode // TODO where is this used?
}

var (
	Version   = "0.2.0"
	BuildTime = "1970-01-01 00:00:00"
)

func (di *DriverInstance) Run() { // TODO make this non-blocking again? non-blocking might be the issue?
	srv := grpc.NewServer(grpc.UnaryInterceptor(logGRPC))
	csi.RegisterIdentityServer(srv, NewIdentityServer(*di))
	csi.RegisterControllerServer(srv, NewControllerServer(*di))
	csi.RegisterNodeServer(srv, NewNodeServer(*di))

	proto, addr, err := ParseEndpoint(di.endpoint)
	if err != nil {
		klog.Fatal(err.Error())
	}
	if proto == "unix" {
		if err := os.Remove(addr); err != nil && !os.IsNotExist(err) {
			klog.Fatalf("Failed to remove %s, error: %s", addr, err.Error())
		}
	}
	listener, err := net.Listen(proto, addr)
	if err != nil {
		fmt.Errorf("failed to listen: %v", err) // TODO this should return.
	}

	klog.Infof("Listening for connections on address: %#v", listener.Addr())
	srv.Serve(listener)
}
