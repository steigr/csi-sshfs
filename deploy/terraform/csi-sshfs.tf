locals {
  on_rke = true
  kubeletdir = local.on_rke ? "/opt/rke/var/lib/kubelet" : "/var/lib/kubelet"
}

resource "kubernetes_namespace" "csi_sshfs" {
  metadata {
    name = "csi-sshfs"
  }
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
    name = "csi-controller-sshfs"
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "external_controller_sshfs" {
  metadata {
    name = "external-controller-sshfs"
  }

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
  metadata {
    name = "csi-attacher-role-sshfs"
  }

  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.csi_controller_sshfs.metadata[0].name
    namespace = kubernetes_service_account.csi_controller_sshfs.metadata[0].namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = "external-controller-sshfs"
  }
}

resource "kubernetes_stateful_set" "csi_controller_sshfs" {
  metadata {
    name = "csi-controller-sshfs"
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "csi-controller-sshfs"
      }
    }

    template {
      metadata {
        labels = {
          app = "csi-controller-sshfs"
        }
      }

      spec {
        volume {
          name = "socket-dir"
        }

        container {
          name = "csi-attacher"
          image = "quay.io/k8scsi/csi-attacher:v1.0.1" # TODO pin version
          args = ["--v=5", "--csi-address=$(ADDRESS)"]

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
          image = "patricol/csi-sshfs:latest" # TODO pin version
          args = ["--nodeid=$(NODE_ID)", "--endpoint=$(CSI_ENDPOINT)"]

          env {
            name = "NODE_ID"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
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
        automount_service_account_token = true
      }
    }

    service_name = "csi-controller-sshfs"
  }
}

resource "kubernetes_service_account" "csi_nodeplugin_sshfs" {
  metadata {
    name = "csi-nodeplugin-sshfs"
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "csi_nodeplugin_sshfs" {
  metadata {
    name = "csi-nodeplugin-sshfs"
  }

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
  metadata {
    name = "csi-nodeplugin-sshfs"
  }

  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.csi_nodeplugin_sshfs.metadata[0].name
    namespace = kubernetes_service_account.csi_nodeplugin_sshfs.metadata[0].namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = "csi-nodeplugin-sshfs"
  }
}

resource "kubernetes_daemonset" "csi_nodeplugin_sshfs" {
  metadata {
    name = "csi-nodeplugin-sshfs"
    namespace = kubernetes_namespace.csi_sshfs.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "csi-nodeplugin-sshfs"
      }
    }

    template {
      metadata {
        labels = {
          app = "csi-nodeplugin-sshfs"
        }
      }

      spec {
        volume {
          name = "plugin-dir"

          host_path {
            path = "${local.kubeletdir}/plugins/csi-sshfs"
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
          image = "quay.io/k8scsi/csi-node-driver-registrar:v1.0.2" # TODO bump? https://kubernetes-csi.github.io/docs/node-driver-registrar.html
          args = ["--v=5", "--csi-address=/plugin/csi.sock", "--kubelet-registration-path=${local.kubeletdir}/plugins/csi-sshfs/csi.sock"]

          env {
            name = "KUBE_NODE_NAME"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
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
              exec {
                command = ["/bin/sh", "-c", "rm -rf /registration/csi-sshfs /registration/csi-sshfs-reg.sock"]
              }
            }
          }
        }

        container {
          name = "sshfs"
          image = "patricol/csi-sshfs:latest" # TODO pin version
          args = ["--nodeid=$(NODE_ID)", "--endpoint=$(CSI_ENDPOINT)"]

          env {
            name = "NODE_ID"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
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
            capabilities {
              add = ["SYS_ADMIN"]
            }

            privileged = true
            allow_privilege_escalation = true
          }
        }

        service_account_name = "csi-nodeplugin-sshfs"
        automount_service_account_token = true
        host_network = true
      }
    }
  }
}

resource "kubernetes_manifest" "csidriver" {
  provider = kubernetes-alpha
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind = "CSIDriver"
    metadata = {
      name = "csi-sshfs" #change to url format.
    }
    spec = {
#      attachRequired = false # TODO check
      volumeLifecycleModes = [
        "Persistent",
#        "Ephemeral", # TODO check if supported
      ]
    }
  }
}

# TODO test, then update containers and minimize config. and build the containers myself
