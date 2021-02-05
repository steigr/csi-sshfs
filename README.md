# Container Storage Interface Driver for SSHFS

**Warning: This is only a proof of concept and is not actively maintained. It should not be used in production environments!**

This repository contains a CSI driver for SSHFS.

This fork has been revamped and rewritten, though the `deploy/kubernetes{,-debug}` folders weren't updated, and their contents will definitely fail on recent versions of kubernetes.

The `deploy/terraform` folder can be used as a guide to the proper new deployment structure.

NOTE: The `volumeHandle` described below must be unique per `PersistentVolume`. I rewrote this entire project in search of a bug that ended up being caused by my multiple identical `volumeHandle`s. F.

Also expect to have file ownership/permissions weirdness, SSHFS doesn't handle that for you.

## Usage

Deploy the whole directory `deploy/kubernetes`.
This installs the csi controller and node plugin and a appropriate storage class for the csi driver.
```bash
kubectl apply -f deploy/kubernetes
```

To use the csi driver create a persistent volume and persistent volume claim like the example one:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-sshfs
  labels:
    name: data-sshfs
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 100Gi
  storageClassName: sshfs
  csi:
    driver: csi-sshfs
    volumeHandle: data-id
    volumeAttributes:
      server: "<HOSTNAME|IP>"
      port: "22"
      share: "<PATH_TO_SHARE>"
      privateKey: "<NAMESPACE>/<SECRET_NAME>"
      user: "<SSH_CONNECT_USERNAME>"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-sshfs
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: sshfs
  selector:
    matchLabels:
      name: data-sshfs
```

Then mount the volume into a pod:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx 
spec:
  containers:
  - image: maersk/nginx
    imagePullPolicy: Always
    name: nginx
    ports:
    - containerPort: 80
      protocol: TCP
    volumeMounts:
      - mountPath: /var/www
        name: data-sshfs
  volumes:
  - name: data-sshfs
    persistentVolumeClaim:
      claimName: data-sshfs
```

```
TODO:
add more things from the spec: https://github.com/container-storage-interface/spec/releases
Ensure everything is idempotent. check first if things exist before creating?
figure out what capabilities to report

plan adding controller support for making new volumes in subfolders
https://github.com/kubernetes-csi/csi-driver-nfs/issues/70#issuecomment-714845727
https://github.com/kubernetes-csi/livenessprobe
https://github.com/kubernetes-csi/external-snapshotter
https://github.com/kubernetes-csi/external-resizer
https://github.com/kubernetes-csi/external-health-monitor

get klog args out of "csi-sshfs help version" and "csi-sshfs help help"

https://kubernetes.io/blog/2020/12/18/kubernetes-1.20-pod-impersonation-short-lived-volumes-in-csi/
https://kubernetes.io/blog/2020/01/08/testing-of-csi-drivers/
https://kubernetes.io/blog/2020/01/21/csi-ephemeral-inline-volumes/
```