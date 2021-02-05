package main

import (
	"flag"
	"fmt"
	"github.com/Patricol/csi-sshfs/pkg/sshfs"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"k8s.io/klog/v2"
)

var (
	endpoint                          string
	nodeID                            string
	runWithNoControllerServiceSupport bool
	driverName                        = "co.p4t.csi.sshfs" // TODO use this downstream

	rootCmd = &cobra.Command{
		Use:   "csi-sshfs",
		Short: "CSI based SSHFS driver",
		Run: func(cmd *cobra.Command, args []string) {
			sshfs.NewDriverInstance(nodeID, endpoint).Run()
		},
	}
)

func init() {
	rootCmd.Flags().SortFlags = false

	rootCmd.Flags().StringVar(&nodeID, "nodeid", "", "node id")
	rootCmd.MarkFlagRequired("nodeid")

	rootCmd.Flags().StringVar(&endpoint, "endpoint", "", "CSI endpoint")
	rootCmd.MarkFlagRequired("endpoint")

	rootCmd.AddCommand(VersionCmd())

	klog.InitFlags(nil)
	flag.Parse()
	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)
}

func main() {
	//	rootCmd.ParseFlags(os.Args[1:])
	if err := rootCmd.Execute(); err != nil {
		klog.Fatalf("root cmd execute failed, err=%v", err)
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
