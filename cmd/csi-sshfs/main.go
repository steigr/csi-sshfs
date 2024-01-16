package main

import (
	"flag"
	"fmt"
	"github.com/spf13/cobra"
	"github.com/steigr/csi-sshfs/pkg/sshfs"
	"k8s.io/klog/v2"
)

var (
	endpoint                          = ""
	nodeID                            = ""
	driverName                        = "csi.sshfs.io"
	runWithNoControllerServiceSupport = false

	rootCmd = &cobra.Command{
		Use:   "csi-sshfs",
		Short: "CSI based SSHFS driver",
	}
)

func init() {
	rootCmd.Flags().SortFlags = false
	rootCmd.AddCommand(RunCmd())
	rootCmd.AddCommand(VersionCmd())
}

func main() {
	flag.Parse()
	if err := rootCmd.Execute(); err != nil {
		klog.Exitf("root cmd execute failed, err=%v", err)
	}
}

func RunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Run the plugin",
		Run: func(cmd *cobra.Command, args []string) {
			if err := sshfs.NewDriverInstance(endpoint, nodeID, driverName, runWithNoControllerServiceSupport).Run(); err != nil {
				klog.Fatalf("failed to run driver: %s", err)
			}
		},
	}
	cmd.Flags().SortFlags = false
	cmd.Flags().StringVar(&endpoint, "endpoint", endpoint, "CSI endpoint")
	cmd.Flags().StringVar(&nodeID, "nodeid", nodeID, "node id")
	cmd.Flags().StringVar(&driverName, "csi-driver-name", driverName, "csi-driver name this will report")
	cmd.Flags().BoolVar(&runWithNoControllerServiceSupport, "disable-controller-support", runWithNoControllerServiceSupport, "only enable if no controller pod will exist")
	if err := cmd.MarkFlagRequired("endpoint"); err != nil {
		klog.Fatalf("requiring --endpoint: %s", err)
	}
	if err := cmd.MarkFlagRequired("nodeid"); err != nil {
		klog.Fatalf("requiring --nodeid: %s", err)
	}
	klog.InitFlags(nil)
	cmd.Flags().AddGoFlagSet(flag.CommandLine)
	return cmd
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
