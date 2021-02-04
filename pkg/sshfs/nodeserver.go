package sshfs

import (
	"context"
	"fmt"
	"io/ioutil"
	"k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/klog/v2"
	"os"
	"os/exec"
	"strings"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"k8s.io/mount-utils"
)

func NewNodeServer(driverInstance DriverInstance) *NodeServer {
	return &NodeServer{
		Driver: &driverInstance,
		mounts: map[string]*mountPoint{},
	}
}

type NodeServer struct {
	Driver *DriverInstance
	mounts map[string]*mountPoint
}

type mountPoint struct {
	VolumeId     string
	MountPath    string
	IdentityFile string
}

func (ns *NodeServer) NodeGetInfo(ctx context.Context, request *csi.NodeGetInfoRequest) (*csi.NodeGetInfoResponse, error) {
	return &csi.NodeGetInfoResponse{
		NodeId: ns.Driver.nodeID,
	}, nil
}

func (ns *NodeServer) NodeGetCapabilities(ctx context.Context, request *csi.NodeGetCapabilitiesRequest) (*csi.NodeGetCapabilitiesResponse, error) {
	return &csi.NodeGetCapabilitiesResponse{
		Capabilities: []*csi.NodeServiceCapability{
			{Type: &csi.NodeServiceCapability_Rpc{Rpc: &csi.NodeServiceCapability_RPC{Type: csi.NodeServiceCapability_RPC_UNKNOWN}}},
		},
	}, nil
}

func (ns *NodeServer) NodePublishVolume(ctx context.Context, request *csi.NodePublishVolumeRequest) (*csi.NodePublishVolumeResponse, error) {
	if request.GetVolumeCapability() == nil {
		return nil, status.Error(codes.InvalidArgument, "Volume capability missing in request")
	}
	volumeID := request.GetVolumeId()
	if len(volumeID) == 0 {
		return nil, status.Error(codes.InvalidArgument, "Volume ID missing in request")
	}
	targetPath := request.GetTargetPath()
	if len(targetPath) == 0 {
		return nil, status.Error(codes.InvalidArgument, "Target path missing in request")
	}

	notMnt, err := mount.New("").IsLikelyNotMountPoint(targetPath) // TODO maybe me not reusing these is an issue?
	if err != nil {
		if os.IsNotExist(err) {
			if err := os.MkdirAll(targetPath, 0750); err != nil {
				return nil, status.Error(codes.Internal, err.Error())
			}
			notMnt = true
		} else {
			return nil, status.Error(codes.Internal, err.Error())
		}
	}
	if !notMnt {
		return &csi.NodePublishVolumeResponse{}, nil
	}

	mountOptions := request.GetVolumeCapability().GetMount().GetMountFlags()
	if request.GetReadonly() {
		mountOptions = append(mountOptions, "ro")
	}
	if err = validateVolumeContext(request); err != nil {
		return nil, err
	}

	server := request.GetVolumeContext()["server"]
	port := request.GetVolumeContext()["port"]
	if len(port) == 0 {
		port = "22"
	}

	user := request.GetVolumeContext()["user"]
	ep := request.GetVolumeContext()["share"]
	privateKey := request.GetVolumeContext()["privateKey"]
	sshOpts := request.GetVolumeContext()["sshOpts"]

	secret, err := getPublicKeySecret(privateKey)
	if err != nil {
		return nil, err
	}
	privateKeyPath, err := writePrivateKey(secret)
	if err != nil {
		return nil, err
	}

	err = Mount(user, server, port, ep, targetPath, privateKeyPath, sshOpts)
	if err != nil {
		if os.IsPermission(err) {
			return nil, status.Error(codes.PermissionDenied, err.Error())
		}
		if strings.Contains(err.Error(), "invalid argument") {
			return nil, status.Error(codes.InvalidArgument, err.Error())
		}
		return nil, status.Error(codes.Internal, err.Error())
	}
	ns.mounts[request.VolumeId] = &mountPoint{IdentityFile: privateKeyPath, MountPath: targetPath, VolumeId: request.VolumeId}
	return &csi.NodePublishVolumeResponse{}, nil
}

func (ns *NodeServer) NodeUnpublishVolume(ctx context.Context, request *csi.NodeUnpublishVolumeRequest) (*csi.NodeUnpublishVolumeResponse, error) {
	volumeID := request.GetVolumeId()
	if len(volumeID) == 0 {
		return nil, status.Error(codes.InvalidArgument, "Volume ID missing in request")
	}
	targetPath := request.GetTargetPath()
	if len(targetPath) == 0 {
		return nil, status.Error(codes.InvalidArgument, "Target path missing in request")
	}
	notMnt, err := mount.New("").IsLikelyNotMountPoint(targetPath) // TODO same here

	if err != nil {
		if pathError, ok := err.(*os.PathError); ok {
			// From the docs: [The NodeUnpublishVolume] operation MUST be idempotent. If this RPC failed, or the CO does not know if it failed or not, it can choose to call NodeUnpublishVolume again.
			// Same for publishing actually.
			klog.Infof("Volume may already be gone, %s: %s", err.Error(), (*pathError).Path)
		} else {
			return nil, status.Error(codes.Internal, err.Error())
		}
	}
	if notMnt {
		klog.Infof("Volume not mounted")
	}
	// https://github.com/kubernetes/kubernetes/blob/v1.13.12/pkg/volume/util/util.go#L132
	err = mount.CleanupMountPoint(request.GetTargetPath(), mount.New(""), false)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	if point, ok := ns.mounts[request.VolumeId]; ok {
		err := os.Remove(point.IdentityFile)
		if err != nil {
			return nil, status.Error(codes.Internal, err.Error())
		}
		delete(ns.mounts, point.VolumeId)
		klog.Infof("successfully unmount volume: %s", point)
	}

	return &csi.NodeUnpublishVolumeResponse{}, nil
}

func (ns *NodeServer) NodeGetVolumeStats(ctx context.Context, request *csi.NodeGetVolumeStatsRequest) (*csi.NodeGetVolumeStatsResponse, error) {
	return nil, status.Error(codes.Unimplemented, "")
}

func (ns *NodeServer) NodeExpandVolume(ctx context.Context, request *csi.NodeExpandVolumeRequest) (*csi.NodeExpandVolumeResponse, error) {
	return nil, status.Error(codes.Unimplemented, "")
}

func (ns *NodeServer) NodeUnstageVolume(ctx context.Context, request *csi.NodeUnstageVolumeRequest) (*csi.NodeUnstageVolumeResponse, error) {
	return &csi.NodeUnstageVolumeResponse{}, nil
}

func (ns *NodeServer) NodeStageVolume(ctx context.Context, request *csi.NodeStageVolumeRequest) (*csi.NodeStageVolumeResponse, error) {
	return &csi.NodeStageVolumeResponse{}, nil
}

func validateVolumeContext(request *csi.NodePublishVolumeRequest) error {
	if _, ok := request.GetVolumeContext()["server"]; !ok {
		return status.Errorf(codes.InvalidArgument, "missing volume context value: server")
	}
	if _, ok := request.GetVolumeContext()["user"]; !ok {
		return status.Errorf(codes.InvalidArgument, "missing volume context value: user")
	}
	if _, ok := request.GetVolumeContext()["share"]; !ok {
		return status.Errorf(codes.InvalidArgument, "missing volume context value: share")
	}
	if _, ok := request.GetVolumeContext()["privateKey"]; !ok {
		return status.Errorf(codes.InvalidArgument, "missing volume context value: privateKey")
	}
	return nil
}

func getPublicKeySecret(secretName string) (*v1.Secret, error) {
	namespaceAndSecret := strings.SplitN(secretName, "/", 2)
	namespace := namespaceAndSecret[0]
	name := namespaceAndSecret[1]

	clientset, e := GetK8sClient()
	if e != nil {
		return nil, status.Errorf(codes.Internal, "can not create kubernetes client: %s", e)
	}

	ctx := context.TODO() // TODO not sure what kind of context to use
	secret, e := clientset.CoreV1().Secrets(namespace).Get(ctx, name, metav1.GetOptions{})

	if e != nil {
		return nil, status.Errorf(codes.Internal, "can not get secret %s: %s", secretName, e)
	}

	if secret.Type != v1.SecretTypeSSHAuth {
		return nil, status.Errorf(codes.InvalidArgument, "type of secret %s is not %s", secretName, v1.SecretTypeSSHAuth)
	}
	return secret, nil
}

func writePrivateKey(secret *v1.Secret) (string, error) {
	f, e := ioutil.TempFile("", "pk-*")
	defer f.Close()
	if e != nil {
		return "", status.Errorf(codes.Internal, "can not create tmp file for pk: %s", e)
	}

	_, e = f.Write(secret.Data[v1.SSHAuthPrivateKey])
	if e != nil {
		return "", status.Errorf(codes.Internal, "can not create tmp file for pk: %s", e)
	}
	e = f.Chmod(0600)
	if e != nil {
		return "", status.Errorf(codes.Internal, "can not change rights for pk: %s", e)
	}
	return f.Name(), nil
}

func Mount(user string, host string, port string, dir string, target string, privateKey string, sshOpts string) error {
	mountCmd := "sshfs"
	mountArgs := []string{}

	source := fmt.Sprintf("%s@%s:%s", user, host, dir)
	mountArgs = append(
		mountArgs,
		source,
		target,
		"-o", "port="+port,
		"-o", "IdentityFile="+privateKey,
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "UserKnownHostsFile=/dev/null",
	)

	if len(sshOpts) > 0 {
		mountArgs = append(mountArgs, "-o", sshOpts)
	}

	err := os.MkdirAll(target, 0750) // create target, noop if it exists
	if err != nil {
		return err
	}

	klog.Infof("executing mount command cmd=%s, args=%s", mountCmd, mountArgs)

	out, err := exec.Command(mountCmd, mountArgs...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("mounting failed: %v cmd: '%s %s' output: %q",
			err, mountCmd, strings.Join(mountArgs, " "), string(out))
	}

	return nil
}
