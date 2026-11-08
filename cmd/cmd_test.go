package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func execCLI(t *testing.T, args ...string) (string, error) {
	t.Helper()
	flags = globalFlags{}
	out := new(bytes.Buffer)
	errBuf := new(bytes.Buffer)
	rootCmd.SetOut(out)
	rootCmd.SetErr(errBuf)
	rootCmd.SetArgs(args)
	err := rootCmd.ExecuteContext(context.Background())
	return out.String(), err
}

func TestSearchCommand(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/search" {
			http.NotFound(w, r)
			return
		}
		_, _ = io.WriteString(w, `
<a class="box" href="/v/abc123">
  <div class="video-title"><strong>SSNI-678</strong> Office Lady</div>
</a>`)
	}))
	t.Cleanup(srv.Close)
	t.Setenv("JAVDB_BASE_URL", srv.URL)
	t.Setenv("SOCKS5_PROXY", "")
	t.Setenv("JAVDB_COOKIES", "")
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())

	out, err := execCLI(t, "search", "SSNI-678")
	if err != nil {
		t.Fatal(err)
	}
	var res struct {
		Query  string `json:"query"`
		Total  int    `json:"total"`
		Movies []struct {
			Code string `json:"code"`
		} `json:"movies"`
	}
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("json %v: %s", err, out)
	}
	if res.Query != "SSNI-678" || res.Total != 1 || res.Movies[0].Code != "SSNI-678" {
		t.Fatalf("%s", out)
	}
}

func TestRankingsCommandRejectsInvalidPeriod(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("JAVDB_BASE_URL", "http://127.0.0.1:1")
	t.Setenv("SOCKS5_PROXY", "")
	_, err := execCLI(t, "rankings", "-p", "yearly")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestVersionCommand(t *testing.T) {
	out, err := execCLI(t, "version")
	if err != nil {
		t.Fatal(err)
	}
	var res map[string]string
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("json %v: %s", err, out)
	}
	if res["version"] != "dev" || res["commit"] != "none" || res["date"] != "unknown" {
		t.Fatalf("%s", out)
	}
}

func TestConfigPathCommand(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	out, err := execCLI(t, "config", "path")
	if err != nil {
		t.Fatal(err)
	}
	var res map[string]string
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatal(err)
	}
	if res["path"] == "" {
		t.Fatalf("%s", out)
	}
}

func TestConfigSetAndGet(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	if _, err := execCLI(t, "config", "set", "locale", "en"); err != nil {
		t.Fatal(err)
	}
	out, err := execCLI(t, "config", "get", "locale")
	if err != nil {
		t.Fatal(err)
	}
	var res map[string]string
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatal(err)
	}
	if res["value"] != "en" {
		t.Fatalf("%s", out)
	}
}
