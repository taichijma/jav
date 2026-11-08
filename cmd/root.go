package cmd

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/spf13/cobra"
	"github.com/taichi/javcli/pkg/config"
	"github.com/taichi/javcli/pkg/javdb"
)

type ctxKey int

const clientKey ctxKey = 1

type globalFlags struct {
	proxy   string
	cookies string
	locale  string
}

var flags globalFlags

var rootCmd = &cobra.Command{
	Use:           "javcli",
	Short:         "JavDB CLI",
	Long:          `javcli is a CLI for searching and browsing the JavDB database. Output is always JSON.`,
	SilenceUsage:  true,
	SilenceErrors: true,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if cmd.Name() == "version" {
			return nil
		}
		cfg, err := config.Load()
		if err != nil {
			return err
		}
		client := javdb.New(clientOptions(cfg)...)
		cmd.SetContext(context.WithValue(cmd.Context(), clientKey, client))
		return nil
	},
}

func clientOptions(cfg *config.Config) []javdb.Option {
	if cfg == nil {
		cfg = &config.Config{}
	}
	opts := []javdb.Option{
		javdb.WithCookies(firstNonEmpty(flags.cookies, os.Getenv("JAVDB_COOKIES"), cfg.Cookies)),
		javdb.WithLocale(firstNonEmpty(flags.locale, os.Getenv("JAVDB_LOCALE"), cfg.Locale)),
		javdb.WithProxy(firstNonEmpty(flags.proxy, os.Getenv("SOCKS5_PROXY"), cfg.Proxy)),
	}
	if base := os.Getenv("JAVDB_BASE_URL"); base != "" {
		opts = append(opts, javdb.WithBaseURL(base))
	}
	if envTruthy(os.Getenv("JAVDB_TLS_INSECURE")) {
		opts = append(opts, javdb.WithTLSInsecure(true))
	}
	return opts
}

func clientFrom(cmd *cobra.Command) *javdb.Client {
	if c, ok := cmd.Context().Value(clientKey).(*javdb.Client); ok && c != nil {
		return c
	}
	return javdb.New(clientOptions(nil)...)
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func envTruthy(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func Execute() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := rootCmd.ExecuteContext(ctx); err != nil {
		_ = writeErrorJSON(os.Stdout, err)
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&flags.proxy, "proxy", "", "SOCKS5 proxy (host:port or socks5://user:pass@host:port)")
	rootCmd.PersistentFlags().StringVar(&flags.cookies, "cookies", "", "JavDB session cookies")
	rootCmd.PersistentFlags().StringVar(&flags.locale, "locale", "", "UI locale (default zh)")
}
