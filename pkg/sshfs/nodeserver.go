package sshfs

import (
    "fmt"
    "k8s.io/klog"
    "io/ioutil"
    "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "os"
    "os/exec"
    "strings"
    "context"

    "github.com/container-storage-interface/spec/lib/go/csi"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    "k8s.io/mount-utils"
)

type NodeServer struct {
    Driver *CSIDriver
    mounts map[string]*mountPoint
}

type mountPoint struct {
    VolumeId     string
    MountPath    string
    IdentityFile string
}

func (ns *NodeServer) NodeGetInfo(ctx context.Context, req *csi.NodeGetInfoRequest) (*csi.NodeGetInfoResponse, error) {
    klog.V(5).Infof("Using default NodeGetInfo")

    return &csi.NodeGetInfoResponse{
        NodeId: ns.Driver.nodeID,
    }, nil
}

func (ns *NodeServer) NodeGetCapabilities(ctx context.Context, req *csi.NodeGetCapabilitiesRequest) (*csi.NodeGetCapabilitiesResponse, error) {
    klog.V(5).Infof("Using default NodeGetCapabilities")

    return &csi.NodeGetCapabilitiesResponse{
        Capabilities: []*csi.NodeServiceCapability{
            {
                Type: &csi.NodeServiceCapability_Rpc{
                    Rpc: &csi.NodeServiceCapability_RPC{
                        Type: csi.NodeServiceCapability_RPC_UNKNOWN,
                    },
                },
            },
        },
    }, nil
}

func (ns *NodeServer) NodePublishVolume(ctx context.Context, req *csi.NodePublishVolumeRequest) (*csi.NodePublishVolumeResponse, error) {
    targetPath := req.GetTargetPath()
    notMnt, e := mount.New("").IsLikelyNotMountPoint(targetPath)
    if e != nil {
        if os.IsNotExist(e) {
            if err := os.MkdirAll(targetPath, 0750); err != nil {
                return nil, status.Error(codes.Internal, err.Error())
            }
            notMnt = true
        } else {
            return nil, status.Error(codes.Internal, e.Error())
        }
    }

    if !notMnt {
        return &csi.NodePublishVolumeResponse{}, nil
    }

    mountOptions := req.GetVolumeCapability().GetMount().GetMountFlags()
    if req.GetReadonly() {
        mountOptions = append(mountOptions, "ro")
    }
    if e := validateVolumeContext(req); e != nil {
        return nil, e
    }

    server := req.GetVolumeContext()["server"]
    port := req.GetVolumeContext()["port"]
    if len(port) == 0 {
        port = "22"
    }

    user := req.GetVolumeContext()["user"]
    ep := req.GetVolumeContext()["share"]
    privateKey := req.GetVolumeContext()["privateKey"]
    sshOpts := req.GetVolumeContext()["sshOpts"]

    secret, e := getPublicKeySecret(privateKey)
    if e != nil {
        return nil, e
    }
    privateKeyPath, e := writePrivateKey(secret)
    if e != nil {
        return nil, e
    }

    e = Mount(user, server, port, ep, targetPath, privateKeyPath, sshOpts)
    if e != nil {
        if os.IsPermission(e) {
            return nil, status.Error(codes.PermissionDenied, e.Error())
        }
        if strings.Contains(e.Error(), "invalid argument") {
            return nil, status.Error(codes.InvalidArgument, e.Error())
        }
        return nil, status.Error(codes.Internal, e.Error())
    }
    ns.mounts[req.VolumeId] = &mountPoint{IdentityFile: privateKeyPath, MountPath: targetPath, VolumeId: req.VolumeId}
    return &csi.NodePublishVolumeResponse{}, nil
}

func (ns *NodeServer) NodeUnpublishVolume(ctx context.Context, req *csi.NodeUnpublishVolumeRequest) (*csi.NodeUnpublishVolumeResponse, error) {
    targetPath := req.GetTargetPath()
    notMnt, err := mount.New("").IsLikelyNotMountPoint(targetPath)

    if err != nil {
        if pathError, ok := err.(*os.PathError); ok {
        // From the docs: [The NodeUnpublishVolume] operation MUST be idempotent. If this RPC failed, or the CO does not know if it failed or not, it can choose to call NodeUnpublishVolume again.
        // Same for publishing actually.
            klog.Infof("Volume may already be gone, %s: %s", (*pathError).Err.Error(), (*pathError).Path)
        } else {
            return nil, status.Error(codes.Internal, err.Error())
        }
    }
    if notMnt {
        klog.Infof("Volume not mounted")
    }
// https://github.com/kubernetes/kubernetes/blob/v1.13.12/pkg/volume/util/util.go#L132
    err = mount.CleanupMountPoint(req.GetTargetPath(), mount.New(""), false)
    if err != nil {
        return nil, status.Error(codes.Internal, err.Error())
    }
    if point, ok := ns.mounts[req.VolumeId]; ok {
        err := os.Remove(point.IdentityFile)
        if err != nil {
            return nil, status.Error(codes.Internal, err.Error())
        }
        delete(ns.mounts, point.VolumeId)
        klog.Infof("successfully unmount volume: %s", point)
    }

    return &csi.NodeUnpublishVolumeResponse{}, nil
}

func (ns *NodeServer) NodeGetVolumeStats(ctx context.Context, in *csi.NodeGetVolumeStatsRequest) (*csi.NodeGetVolumeStatsResponse, error) {
    klog.V(5).Infof("Called Unimplemented NodeGetVolumeStats")
    return nil, status.Error(codes.Unimplemented, "")
}

func (ns *NodeServer) NodeExpandVolume(ctx context.Context, in *csi.NodeExpandVolumeRequest) (*csi.NodeExpandVolumeResponse, error) {
    klog.V(5).Infof("Called Unimplemented NodeExpandVolume")
    return nil, status.Error(codes.Unimplemented, "")
}

func (ns *NodeServer) NodeUnstageVolume(ctx context.Context, req *csi.NodeUnstageVolumeRequest) (*csi.NodeUnstageVolumeResponse, error) {
    return &csi.NodeUnstageVolumeResponse{}, nil
}

func (ns *NodeServer) NodeStageVolume(ctx context.Context, req *csi.NodeStageVolumeRequest) (*csi.NodeStageVolumeResponse, error) {
    return &csi.NodeStageVolumeResponse{}, nil
}

func validateVolumeContext(req *csi.NodePublishVolumeRequest) error {
    if _, ok := req.GetVolumeContext()["server"]; !ok {
        return status.Errorf(codes.InvalidArgument, "missing volume context value: server")
    }
    if _, ok := req.GetVolumeContext()["user"]; !ok {
        return status.Errorf(codes.InvalidArgument, "missing volume context value: user")
    }
    if _, ok := req.GetVolumeContext()["share"]; !ok {
        return status.Errorf(codes.InvalidArgument, "missing volume context value: share")
    }
    if _, ok := req.GetVolumeContext()["privateKey"]; !ok {
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

    // create target, os.Mkdirall is noop if it exists
    err := os.MkdirAll(target, 0750)
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
