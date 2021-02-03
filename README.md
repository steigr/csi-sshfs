# Container Storage Interface Driver for SSHFS

**Warning: This is only a proof of concept and is not actively maintained. It should not be used in production environments!**

This repository contains the CSI driver for SSHFS. It allows to mount directories using a ssh connection.

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
# kubectl -n csi-sshfs rollout restart daemonset.apps/csi-nodeplugin-sshfs daemonset.apps/csi-controller-sshfs
# kubectl -n csi-sshfs logs -llog_group=csi-sshfs -f --all-containers --prefix --tail=-1
# dlv connect 192.168.8.41:31041
# dlv connect 192.168.8.41:31040
# kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set debug; done
# kubectl -n cattle-system logs -lapp=rancher -f --all-containers --prefix --tail=-1
# kubectl -n cattle-system get pods -l app=cattle-agent --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set debug; done
# kubectl -n cattle-system get pods -l app=cattle-cluster-agent --no-headers -o custom-columns=name:.metadata.name | while read rancherpod; do kubectl -n cattle-system exec $rancherpod -c rancher -- loglevel --set debug; done
# kubectl -n cattle-system logs -lapp=cattle-agent -f --all-containers --prefix --tail=-1
# kubectl -n cattle-system logs -lapp=cattle-cluster-agent -f --all-containers --prefix --tail=-1

# utils call happens before the volume creation is given; maybe library is too old? check it out.
# grpc types are probably wrong. single vs list. got a double once.
# kk it's like 100% the go packages being pinned.
# TODO replace glog with klog https://pkg.go.dev/k8s.io/klog
```