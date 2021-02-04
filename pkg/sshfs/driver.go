package sshfs

import (
	"fmt"
	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc"
	"k8s.io/klog"
	"net"
	"os"
	"strings"
)

func NewDriverInstance(nodeID string, endpoint string) *DriverInstance {
	klog.Infof("Starting new %s driver in version %s built %s", driverName, Version, BuildTime)

	//     csiDriver.AddVolumeCapabilityAccessModes([]csi.VolumeCapability_AccessMode_Mode{csi.VolumeCapability_AccessMode_MULTI_NODE_MULTI_WRITER}) \\ TODO

	return &DriverInstance{
		csiDriverName: driverName,
		version:       Version,
		nodeID:        nodeID,
		endpoint:      endpoint,
	}
}

type DriverInstance struct {
	csiDriverName string
	version       string
	nodeID        string
	endpoint      string
	//     cap   []*csi.VolumeCapability_AccessMode
}

const (
	driverName = "csi-sshfs"

//     driverName = "co.p4t.csi.sshfs"
)

var (
	Version   = "latest"
	BuildTime = "1970-01-01 00:00:00"
)

func (di *DriverInstance) Run() { // TODO make this non-blocking again? non-blocking might be the issue?
	srv := grpc.NewServer(grpc.UnaryInterceptor(logGRPC))
	csi.RegisterIdentityServer(srv, NewIdentityServer(*di))
	//     csi.RegisterControllerServer(srv, NewControllerServer(*di))
	csi.RegisterNodeServer(srv, NewNodeServer(*di))

	proto, addr, err := ParseEndpoint(di.endpoint)
	if err != nil {
		klog.Fatal(err.Error())
	}
	if proto == "unix" {
		if err := os.Remove(addr); err != nil && !os.IsNotExist(err) {
			klog.Fatalf("Failed to remove %s, error: %s", addr, err.Error()) // should this return?
		}
	}
	listener, err := net.Listen(proto, addr)
	if err != nil {
		fmt.Errorf("failed to listen: %v", err) // TODO this should return.
	}

	klog.Infof("Listening for connections on address: %#v", listener.Addr())
	srv.Serve(listener)
}

func ParseEndpoint(endpoint string) (string, string, error) { // TODO move to utils?
	if strings.HasPrefix(strings.ToLower(endpoint), "unix://") || strings.HasPrefix(strings.ToLower(endpoint), "tcp://") {
		s := strings.SplitN(endpoint, "://", 2)
		protocol := s[0]
		address := s[1]
		if address != "" {
			if protocol == "unix" {
				address = "/" + address
			}
			return protocol, address, nil
		}
	}
	return "", "", fmt.Errorf("invalid endpoint: %v", endpoint)
}
