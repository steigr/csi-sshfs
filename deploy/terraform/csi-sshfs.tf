locals {
  debug_mode = false
  csi-sshfs_image_tag = local.debug_mode ? "debug" : "latest"
  csi-node-driver-registrar_image_tag = "v2.1.0" # https://github.com/kubernetes-csi/node-driver-registrar/releases
  csi-attacher_image_tag = "v3.1.0" # https://github.com/kubernetes-csi/external-attacher/releases
  csi-provisioner_image_tag = "v2.1.0" # https://github.com/kubernetes-csi/external-provisioner/releases
  on_rke = true
  kubeletdir = local.on_rke ? "/opt/rke/var/lib/kubelet" : "/var/lib/kubelet"
  controller_name = "csi-controller-sshfs"
  nodeplugin_name = "csi-nodeplugin-sshfs"
  driver_name = "co.p4t.csi.sshfs"
  log_level = 3
  debug_socket = false
  enable_controller = true
}

resource "kubernetes_namespace" "csi_sshfs" {
  metadata {name = "csi-sshfs"}
  lifecycle {ignore_changes = [metadata[0]]} # Rancher adds some annotations. TODO avoid ignoring if not on rke.
}

resource "kubernetes_storage_class" "sshfs" {
  metadata {
    name = "sshfs"
#    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
}

resource "kubernetes_service_account" "csi_controller_sshfs" {
  count = local.enable_controller ? 1 : 0

  metadata {
    name = local.controller_name
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "external_controller_sshfs" {
  count = local.enable_controller ? 1 : 0

  metadata {name = "external-controller-sshfs"}
  rule {
    verbs = ["get", "list", "watch", "update"]
    api_groups = [""]
    resources = ["persistentvolumes"]
  }
  rule {
    verbs = ["get", "list", "watch"]
    api_groups = [""]
    resources = ["nodes"]
  }
  rule {
    verbs = ["get", "list", "watch"]
    api_groups = ["csi.storage.k8s.io"]
    resources = ["csinodeinfos"]
  }
  rule {
    verbs = ["get", "list", "watch", "update"]
    api_groups = ["storage.k8s.io"]
    resources = ["volumeattachments"]
  }
  rule {
    verbs = ["patch"]
    api_groups = ["storage.k8s.io"]
    resources = ["volumeattachments/status"]
  }
  rule {
    verbs = ["get", "create", "update"]
    api_groups = ["coordination.k8s.io"]
    resources = ["leases"]
  }
  rule {
    verbs = ["list", "watch"]
    api_groups = ["storage.k8s.io"]
    resources = ["csinodes", "storageclasses"]
  }
  rule {
    verbs = ["list", "watch"]
    api_groups = [""]
    resources = ["persistentvolumeclaims"]
  }
  rule {
    verbs = ["create"]
    api_groups = [""]
    resources = ["events"]
  }
}

resource "kubernetes_cluster_role_binding" "csi_attacher_role_sshfs" {
  count = local.enable_controller ? 1 : 0

  metadata {name = "csi-attacher-role-sshfs"}
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.csi_controller_sshfs[0].metadata[0].name
    namespace = kubernetes_service_account.csi_controller_sshfs[0].metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = kubernetes_cluster_role.external_controller_sshfs[0].metadata[0].name
  }
}

resource "kubernetes_deployment" "csi_controller_sshfs" {
  count = local.enable_controller ? 1 : 0

  metadata {
    name = local.controller_name
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
    annotations = {"field.cattle.io/publicEndpoints": ""} # Rancher updates this automatically; but if we don't create it ourselves then lifecycle.ignore_changes won't work.
  }
  spec {
    replicas = 2
    selector {match_labels = {app = local.controller_name}}
    template {
      metadata {labels = {
        app = local.controller_name
        log_group = "csi-sshfs"
      }}
      spec {
        priority_class_name = "system-cluster-critical"
        toleration {
          key = "node-role.kubernetes.io/master"
          operator = "Equal"
          value = "true"
          effect = "NoSchedule"
        }
        service_account_name = kubernetes_service_account.csi_controller_sshfs[0].metadata[0].name
        volume {
          name = "socket-dir"
          empty_dir {medium = "Memory"}
        }
        container {
          name = "csi-provisioner"
          image = "k8s.gcr.io/sig-storage/csi-provisioner:${local.csi-provisioner_image_tag}"
          args = [
            "-v=${local.log_level}",
            "--csi-address=$(ADDRESS)",
            "--leader-election",
            "--leader-election-namespace=${kubernetes_namespace.csi_sshfs.metadata[0].name}",
            "--extra-create-metadata",
          ]
          env {
            name = "ADDRESS"
            value = "/csi/csi-provisioner.sock"
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/csi"
          }
        }
        container {
          name = "csi-attacher"
          image = "k8s.gcr.io/sig-storage/csi-attacher:${local.csi-attacher_image_tag}"
          args = [
            "-v=${local.log_level}",
            "--csi-address=$(ADDRESS)",
#            "--resync=60s", # TODO this crutch may help
            "--leader-election",
            "--leader-election-namespace=${kubernetes_namespace.csi_sshfs.metadata[0].name}",
          ]
          env {
            name = "ADDRESS"
            value = "/csi/csi-provisioner.sock"
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/csi"
          }
        }
        container {
          name = "sshfs"
          image = "patricol/csi-sshfs:${local.csi-sshfs_image_tag}"
          image_pull_policy = "Always"
          args = [
            "-v=${local.log_level}",
            "--nodeid=$(NODE_ID)",
            "--endpoint=$(CSI_ENDPOINT)",
            "--csi-driver-name=${local.driver_name}",
          ]
          env { # TODO maybe needed? used in csi-cephfs plugin
            name = "POD_IP"
            value_from {
              field_ref {field_path = "status.podIP"}
            }
          }
          env {
            name = "NODE_ID"
            value_from {
              field_ref {field_path = "spec.nodeName"}
            }
          }
          env {
            name = "CSI_ENDPOINT"
            value = local.debug_mode && local.debug_socket ? "tcp://0.0.0.0:10000" : "unix://csi/csi-provisioner.sock"
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/csi"
          }
          dynamic "port" {
            for_each = local.debug_mode ? [1] : []
            content {
              container_port = 40000
#              host_port = 40000 # TODO why does terraform want to re-add only this one?
              name = "debug"
            }
          }
          dynamic "port" {
            for_each = local.debug_mode && local.debug_socket ? [1] : []
            content {
              container_port = 10000
              name = "csi-socket"
            }
          }
          security_context {
            privileged = true
            capabilities {add = local.debug_mode ? ["SYS_ADMIN", "SYS_PTRACE"] : ["SYS_ADMIN"]}
          }
        }
      }
    }
  }
  lifecycle {ignore_changes = [metadata[0].annotations["field.cattle.io/publicEndpoints"]]}
}

resource "kubernetes_service_account" "csi_nodeplugin_sshfs" {
  metadata {
    name = local.nodeplugin_name
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "csi_nodeplugin_sshfs" {
  metadata {name = local.nodeplugin_name}
  rule {
    verbs = ["get", "list", "watch", "update"]
    api_groups = [""]
    resources = ["persistentvolumes"]
  }
  rule {
    verbs = ["get", "list"]
    api_groups = [""]
    resources = ["secrets", "secret"]
  }
  rule {
    verbs = ["get", "list", "watch", "update"]
    api_groups = [""]
    resources = ["nodes"]
  }
  rule {
    verbs = ["get", "list", "watch", "update"]
    api_groups = ["storage.k8s.io"]
    resources = ["volumeattachments"]
  }
  rule {
    verbs = ["get", "list", "watch", "create", "update", "patch"]
    api_groups = [""]
    resources = ["events"]
  }
}

resource "kubernetes_cluster_role_binding" "csi_nodeplugin_sshfs" {
  metadata {name = local.nodeplugin_name}
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.csi_nodeplugin_sshfs.metadata[0].name
    namespace = kubernetes_service_account.csi_nodeplugin_sshfs.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = kubernetes_cluster_role.csi_nodeplugin_sshfs.metadata[0].name
  }
}

resource "kubernetes_daemonset" "csi_nodeplugin_sshfs" {
  metadata {
    name = local.nodeplugin_name
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
    annotations = {"field.cattle.io/publicEndpoints": ""} # Rancher updates this automatically; but if we don't create it ourselves then lifecycle.ignore_changes won't work.
  }
  spec {
    selector {match_labels = {app = local.nodeplugin_name}}
    template {
      metadata {labels = {
        app = local.nodeplugin_name
        log_group = "csi-sshfs"
      }}
      spec {
        service_account_name = kubernetes_service_account.csi_nodeplugin_sshfs.metadata[0].name
        host_network = true
        dns_policy = "ClusterFirstWithHostNet" # to use e.g. Rook orchestrated cluster, and mons' FQDN is resolved through k8s service, set dns policy to cluster first
        volume {
          name = "socket-dir"
          host_path {
            path = "${local.kubeletdir}/plugins/${local.driver_name}/"
            type = "DirectoryOrCreate"
          }
        }
        volume {
          name = "registration-dir"
          host_path {
            path = "${local.kubeletdir}/plugins_registry/"
            type = "Directory"
          }
        }
        volume {
          name = "mountpoint-dir"
          host_path {
            path = "${local.kubeletdir}/pods"
            type = "DirectoryOrCreate"
          }
        }
        volume {
          name = "plugin-dir"
          host_path {
            path = "${local.kubeletdir}/plugins"
            type = "Directory"
          }
        }
        container {
          name = "node-driver-registrar"
          image = "k8s.gcr.io/sig-storage/csi-node-driver-registrar:${local.csi-node-driver-registrar_image_tag}"
          args = [
            "-v=${local.log_level}",
#            "--http-endpoint=:8080",
            "--csi-address=/csi/csi.sock",
            "--kubelet-registration-path=${local.kubeletdir}/plugins/${local.driver_name}/csi.sock",
          ]
#          port {
#            container_port = 8080
#            name = "http"
#          }
#          liveness_probe {
#            initial_delay_seconds = 5
#            timeout_seconds = 5
#            http_get {
#              path = "/healthz"
#              port = "http"
#            }
#          }
          env {
            name = "KUBE_NODE_NAME"
            value_from {
              field_ref {field_path = "spec.nodeName"}
            }
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/csi"
          }
          volume_mount {
            name = "registration-dir"
            mount_path = "/registration"
          }
          security_context {
            privileged = true # This is necessary only for systems with SELinux, where non-privileged sidecar containers cannot access unix domain socket created by privileged CSI driver container
          }
        }
        container {
          name = "sshfs"
          image = "patricol/csi-sshfs:${local.csi-sshfs_image_tag}"
          image_pull_policy = "Always"
          args = compact([
            "-v=${local.log_level}",
            "--nodeid=$(NODE_ID)",
            "--endpoint=$(CSI_ENDPOINT)",
            "--csi-driver-name=${local.driver_name}",
            local.enable_controller ? "" : "--disable-controller-support"
          ])
          env { # TODO maybe needed? used in csi-cephfs plugin
            name = "POD_IP"
            value_from {
              field_ref {field_path = "status.podIP"}
            }
          }
          env {
            name = "NODE_ID"
            value_from {
              field_ref {field_path = "spec.nodeName"}
            }
          }
          env {
            name = "CSI_ENDPOINT"
            value = local.debug_mode && local.debug_socket ? "tcp://0.0.0.0:10000" : "unix://csi/csi.sock"
          }
          dynamic "port" {
            for_each = local.debug_mode ? [1] : []
            content {
              container_port = 40000
              name = "debug"
            }
          }
          dynamic "port" {
            for_each = local.debug_mode && local.debug_socket ? [1] : []
            content {
              container_port = 10000
              name = "csi-socket"
            }
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/csi"
          }
          volume_mount {
            name = "mountpoint-dir"
            mount_path = "${local.kubeletdir}/pods"
            mount_propagation = "Bidirectional"
          }
          volume_mount {
            name = "plugin-dir"
            mount_path = "${local.kubeletdir}/plugins"
            mount_propagation = "Bidirectional" # Maybe?
          }
          security_context {
            capabilities {add = local.debug_mode ? ["SYS_ADMIN", "SYS_PTRACE"] : ["SYS_ADMIN"]}
            privileged = true
            allow_privilege_escalation = true
          }
        }
      }
    }
  }
  lifecycle {ignore_changes = [metadata[0].annotations["field.cattle.io/publicEndpoints"]]}
}

resource "kubernetes_service" "nodeplugin-debug" {
  count = local.debug_mode ? 1 : 0

  metadata {
    name = "${local.nodeplugin_name}-debug"
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
    annotations = {"field.cattle.io/publicEndpoints": ""} # Rancher updates this automatically; but if we don't create it ourselves then lifecycle.ignore_changes won't work.
  }
  spec {
    selector = {app = kubernetes_daemonset.csi_nodeplugin_sshfs.spec[0].template[0].metadata[0].labels.app}
    type = "NodePort"
    port {
      port = 40000
      target_port = "debug"
      node_port = 31040
      name = "debug"
    }
    dynamic "port" {
      for_each = local.debug_socket ? [1] : []
      content {
        port = 10000
        target_port = "csi-socket"
        node_port = 31010
        name = "csi-socket"
      }
    }
  }
  lifecycle {ignore_changes = [metadata[0].annotations["field.cattle.io/publicEndpoints"]]}
}

resource "kubernetes_service" "controller-debug" {
  count = local.debug_mode && local.enable_controller ? 1 : 0

  metadata {
    name = "${local.controller_name}-debug"
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
    annotations = {"field.cattle.io/publicEndpoints": ""} # Rancher updates this automatically; but if we don't create it ourselves then lifecycle.ignore_changes won't work.
  }
  spec {
    selector = {app = kubernetes_deployment.csi_controller_sshfs[0].spec[0].template[0].metadata[0].labels.app}
    type = "NodePort"
    port {
      port = 40000
      target_port = "debug"
      node_port = 31041
      name = "debug"
    }
    dynamic "port" {
      for_each = local.debug_socket ? [1] : []
      content {
        port = 10000
        target_port = "csi-socket"
        node_port = 31011
        name = "csi-socket"
      }
    }
  }
  lifecycle {ignore_changes = [metadata[0].annotations["field.cattle.io/publicEndpoints"]]}
}

resource "kubernetes_csi_driver" "sshfs" {
  metadata {name = local.driver_name}
  spec {
    attach_required = false # TODO probably? IDK.
    pod_info_on_mount = false # TODO probably? IDK.
    volume_lifecycle_modes = [
      "Persistent",
#      "Ephemeral", # TODO add support
    ]
  }
}

output "sshfs_csi_driver" {
  value = kubernetes_csi_driver.sshfs.metadata[0].name
}

output "sshfs_storage_class" {
  value = kubernetes_storage_class.sshfs.metadata[0].name
}
