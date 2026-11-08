package cmd

import "github.com/spf13/cobra"

// Overwritten by -ldflags when a release binary is built.
var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print build information as JSON",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		return writeJSON(cmd.OutOrStdout(), map[string]string{
			"version": version,
			"commit":  commit,
			"date":    date,
		})
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
