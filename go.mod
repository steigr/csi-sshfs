module github.com/steigr/csi-sshfs

go 1.21

require (
	github.com/container-storage-interface/spec v1.9.0
	github.com/kubernetes-csi/csi-lib-utils v0.17.0
	github.com/spf13/cobra v1.8.0
	google.golang.org/grpc v1.60.1
	k8s.io/api v0.29.0
	k8s.io/apimachinery v0.29.0
	k8s.io/client-go v0.29.0
	k8s.io/klog/v2 v2.120.0
	k8s.io/mount-utils v0.29.0
)

require (
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/emicklei/go-restful/v3 v3.11.2 // indirect
	github.com/go-logr/logr v1.4.1 // indirect
	github.com/go-openapi/jsonpointer v0.20.2 // indirect
	github.com/go-openapi/jsonreference v0.20.4 // indirect
	github.com/go-openapi/swag v0.22.7 // indirect
	github.com/gogo/protobuf v1.3.2 // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/google/gnostic-models v0.6.8 // indirect
	github.com/google/gofuzz v1.2.0 // indirect
	github.com/google/uuid v1.5.0 // indirect
	github.com/googleapis/gnostic v0.5.5 // indirect
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/josharian/intern v1.0.0 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/mailru/easyjson v0.7.7 // indirect
	github.com/moby/sys/mountinfo v0.7.1 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.2 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/spf13/pflag v1.0.5 // indirect
	golang.org/x/crypto v0.18.0 // indirect
	golang.org/x/net v0.20.0 // indirect
	golang.org/x/oauth2 v0.16.0 // indirect
	golang.org/x/sys v0.16.0 // indirect
	golang.org/x/term v0.16.0 // indirect
	golang.org/x/text v0.14.0 // indirect
	golang.org/x/time v0.5.0 // indirect
	google.golang.org/appengine v1.6.8 // indirect
	google.golang.org/genproto v0.0.0-20240102182953-50ed04b92917 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20240108191215-35c7eff3a6b1 // indirect
	google.golang.org/protobuf v1.32.0 // indirect
	gopkg.in/inf.v0 v0.9.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
	k8s.io/kube-openapi v0.0.0-20240105020646-a37d4de58910 // indirect
	k8s.io/utils v0.0.0-20240102154912-e7106e64919e // indirect
	sigs.k8s.io/json v0.0.0-20221116044647-bc3834ca7abd // indirect
	sigs.k8s.io/structured-merge-diff/v4 v4.4.1 // indirect
	sigs.k8s.io/yaml v1.4.0 // indirect
)

//replace k8s.io/api => k8s.io/api v0.20.2
//
//replace k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.20.2
//
//replace k8s.io/apimachinery => k8s.io/apimachinery v0.21.0-alpha.0
//
//replace k8s.io/apiserver => k8s.io/apiserver v0.20.2
//
//replace k8s.io/cli-runtime => k8s.io/cli-runtime v0.20.2
//
//replace k8s.io/client-go => k8s.io/client-go v0.20.2
//
//replace k8s.io/cloud-provider => k8s.io/cloud-provider v0.20.2
//
//replace k8s.io/cluster-bootstrap => k8s.io/cluster-bootstrap v0.20.2
//
//replace k8s.io/code-generator => k8s.io/code-generator v0.20.3-rc.0
//
//replace k8s.io/component-base => k8s.io/component-base v0.20.2
//
//replace k8s.io/component-helpers => k8s.io/component-helpers v0.20.2
//
//replace k8s.io/controller-manager => k8s.io/controller-manager v0.20.2
//
//replace k8s.io/cri-api => k8s.io/cri-api v0.20.3-rc.0
//
//replace k8s.io/csi-translation-lib => k8s.io/csi-translation-lib v0.20.2
//
//replace k8s.io/kube-aggregator => k8s.io/kube-aggregator v0.20.2
//
//replace k8s.io/kube-controller-manager => k8s.io/kube-controller-manager v0.20.2
//
//replace k8s.io/kube-proxy => k8s.io/kube-proxy v0.20.2
//
//replace k8s.io/kube-scheduler => k8s.io/kube-scheduler v0.20.2
//
//replace k8s.io/kubectl => k8s.io/kubectl v0.20.2
//
//replace k8s.io/kubelet => k8s.io/kubelet v0.20.2
//
//replace k8s.io/legacy-cloud-providers => k8s.io/legacy-cloud-providers v0.20.2
//
//replace k8s.io/metrics => k8s.io/metrics v0.20.2
//
//replace k8s.io/mount-utils => k8s.io/mount-utils v0.20.3-rc.0
//
//replace k8s.io/sample-apiserver => k8s.io/sample-apiserver v0.20.2
//
//replace k8s.io/sample-cli-plugin => k8s.io/sample-cli-plugin v0.20.2
//
//replace k8s.io/sample-controller => k8s.io/sample-controller v0.20.2
