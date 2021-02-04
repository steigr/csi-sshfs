package sshfs

import (
	"context"
	"fmt"
	"k8s.io/klog/v2"
	"strings"

	"github.com/kubernetes-csi/csi-lib-utils/protosanitizer"
	"google.golang.org/grpc"
)

func logGRPC(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	klog.V(3).Infof("GRPC call: %s", info.FullMethod)
	klog.V(5).Infof("GRPC request: %s", protosanitizer.StripSecrets(req))
	resp, err := handler(ctx, req)
	if err != nil {
		klog.Errorf("GRPC error: %v", err)
	} else {
		klog.V(5).Infof("GRPC response: %s", protosanitizer.StripSecrets(resp))
	}
	return resp, err
}

func ParseEndpoint(endpoint string) (string, string, error) {
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
