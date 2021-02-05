package main

import (
	"flag"
	"fmt"
	"github.com/Patricol/csi-sshfs/pkg/sshfs"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"k8s.io/klog/v2"
	"os"
)

var (
	endpoint                          string
	nodeID                            string
	driverName                        string
	runWithNoControllerServiceSupport bool

	rootCmd = &cobra.Command{
		Use:   "csi-sshfs",
		Short: "CSI based SSHFS driver",
		Run: func(cmd *cobra.Command, args []string) {
			sshfs.NewDriverInstance(endpoint, nodeID, driverName, runWithNoControllerServiceSupport).Run()
		},
	}
)

func init() {
	rootCmd.Flags().SortFlags = false

	rootCmd.Flags().StringVar(&endpoint, "endpoint", "", "CSI endpoint")
	rootCmd.Flags().StringVar(&nodeID, "nodeid", "", "node id")
	rootCmd.Flags().StringVar(&endpoint, "csi-driver-name", "co.p4t.csi.sshfs", "csi-driver name this will report")
	rootCmd.Flags().BoolVar(&runWithNoControllerServiceSupport, "disable-controller-support", false, "only enable if no controller pod will exist")

	rootCmd.AddCommand(VersionCmd())

	klog.InitFlags(nil)
	flag.Parse()
	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)
}

func main() {
	if err := rootCmd.MarkFlagRequired("endpoint"); err != nil {
		klog.Fatalf("requiring --endpoint: %s", err)
	}
	if err := rootCmd.MarkFlagRequired("nodeid"); err != nil {
		klog.Fatalf("requiring --nodeid: %s", err)
	}
	if err := rootCmd.ParseFlags(os.Args[1:]); err != nil {
		klog.Fatalf("parsing flags: %s", err)
	}
	if err := rootCmd.Execute(); err != nil {
		klog.Exitf("root cmd execute failed, err=%v", err)
	}
}

func VersionCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "version",
		Short: "Get name/version/build of this plugin",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("Plugin Name: %s\n", driverName)
			fmt.Printf("Version:     %s\n", sshfs.Version)
			fmt.Printf("Build Time:  %s\n", sshfs.BuildTime)
		},
	}
	cmd.Flags().SortFlags = false
	cmd.ResetFlags()
	return cmd
}
