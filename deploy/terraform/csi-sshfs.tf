locals {
  csi-sshfs_image_tag = "latest"
  csi-node-driver-registrar_image_tag = "v2.1.0" # https://github.com/kubernetes-csi/node-driver-registrar/releases
  csi-attacher_image_tag = "v3.1.0" # https://github.com/kubernetes-csi/external-attacher/releases
  on_rke = true
  kubeletdir = local.on_rke ? "/opt/rke/var/lib/kubelet" : "/var/lib/kubelet"
  controller_name = "csi-controller-sshfs"
  nodeplugin_name = "csi-nodeplugin-sshfs"
  driver_name = "csi-sshfs" # TODO change to url format.
  log_level = 5
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
  metadata {
    name = local.controller_name
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "external_controller_sshfs" {
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
}

resource "kubernetes_cluster_role_binding" "csi_attacher_role_sshfs" {
  metadata {name = "csi-attacher-role-sshfs"}
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.csi_controller_sshfs.metadata[0].name
    namespace = kubernetes_service_account.csi_controller_sshfs.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = kubernetes_cluster_role.external_controller_sshfs.metadata[0].name
  }
}

resource "kubernetes_stateful_set" "csi_controller_sshfs" {
  metadata {
    name = local.controller_name
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
  spec {
    replicas = 1
    selector {match_labels = {app = local.controller_name}}
    template {
      metadata {labels = {app = local.controller_name}}
      spec {
        volume {
          name = "socket-dir"
          empty_dir {}
        }
        container {
          name = "csi-attacher"
          image = "k8s.gcr.io/sig-storage/csi-attacher:${local.csi-attacher_image_tag}"
          args = [
            "--v=${local.log_level}",
            "--csi-address=$(ADDRESS)",
          ]
          env {
            name = "ADDRESS"
            value = "/csi/csi.sock"
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/csi"
          }
          image_pull_policy = "Always"
        }
        container {
          name = "sshfs"
          image = "patricol/csi-sshfs:${local.csi-sshfs_image_tag}"
          args = ["--nodeid=$(NODE_ID)", "--endpoint=$(CSI_ENDPOINT)"]
          env {
            name = "NODE_ID"
            value_from {
              field_ref {field_path = "spec.nodeName"}
            }
          }
          env {
            name = "CSI_ENDPOINT"
            value = "unix://plugin/csi.sock"
          }
          volume_mount {
            name = "socket-dir"
            mount_path = "/plugin"
          }
          image_pull_policy = "Always"
        }
        service_account_name = kubernetes_service_account.csi_controller_sshfs.metadata[0].name
      }
    }
    service_name = local.controller_name
  }
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
  }
  spec {
    selector {match_labels = {app = local.nodeplugin_name}}
    template {
      metadata {labels = {app = local.nodeplugin_name}}
      spec {
        volume {
          name = "plugin-dir"
          host_path {
            path = "${local.kubeletdir}/plugins/${local.driver_name}"
            type = "DirectoryOrCreate"
          }
        }
        volume {
          name = "pods-mount-dir"
          host_path {
            path = "${local.kubeletdir}/pods"
            type = "Directory"
          }
        }
        volume {
          name = "registration-dir"
          host_path {
            path = "${local.kubeletdir}/plugins_registry"
            type = "DirectoryOrCreate"
          }
        }
        container {
          name = "node-driver-registrar"
          image = "k8s.gcr.io/sig-storage/csi-node-driver-registrar:${local.csi-node-driver-registrar_image_tag}"
          args = [
            "--v=${local.log_level}",
            "--http-endpoint=:8080",
            "--csi-address=/plugin/csi.sock",
            "--kubelet-registration-path=${local.kubeletdir}/plugins/${local.driver_name}/csi.sock",
          ]
          port {
            container_port = 8080
            name = "http"
          }
          liveness_probe {
            initial_delay_seconds = 5
            timeout_seconds = 5
            http_get {
              path = "/healthz"
              port = "http"
            }
          }
          env {
            name = "KUBE_NODE_NAME"
            value_from {
              field_ref {field_path = "spec.nodeName"}
            }
          }
          volume_mount {
            name = "plugin-dir"
            mount_path = "/plugin"
          }
          volume_mount {
            name = "registration-dir"
            mount_path = "/registration"
          }
          lifecycle {
            pre_stop {
              exec {command = ["/bin/sh", "-c", "rm -rf /registration/${local.driver_name} /registration/${local.driver_name}-reg.sock"]} # TODO why?
            }
          }
        }
        container {
          name = "sshfs"
          image = "patricol/csi-sshfs:${local.csi-sshfs_image_tag}"
          args = ["--nodeid=$(NODE_ID)", "--endpoint=$(CSI_ENDPOINT)"]
          env {
            name = "NODE_ID"
            value_from {
              field_ref {field_path = "spec.nodeName"}
            }
          }
          env {
            name = "CSI_ENDPOINT"
            value = "unix://plugin/csi.sock"
          }
          volume_mount {
            name = "plugin-dir"
            mount_path = "/plugin"
          }
          volume_mount {
            name = "pods-mount-dir"
            mount_path = "${local.kubeletdir}/pods"
            mount_propagation = "Bidirectional"
          }
          image_pull_policy = "Always"
          security_context {
            capabilities {add = ["SYS_ADMIN"]}
            privileged = true
            allow_privilege_escalation = true
          }
        }
        service_account_name = kubernetes_service_account.csi_nodeplugin_sshfs.metadata[0].name
        host_network = true
      }
    }
  }
}

resource "kubernetes_csi_driver" "sshfs" {
  metadata {name = local.driver_name}
  spec {
    attach_required = true # TODO check
    pod_info_on_mount = false # TODO check
    volume_lifecycle_modes = [
      "Persistent",
#      "Ephemeral", # TODO check if supported
    ]
  }
}

output "sshfs_csi_driver" {
  value = kubernetes_csi_driver.sshfs.metadata[0].name
}

output "sshfs_storage_class" {
  value = kubernetes_storage_class.sshfs.metadata[0].name
}
