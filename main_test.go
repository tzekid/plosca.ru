package main

import (
	"encoding/json"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
)

var mbRegex = regexp.MustCompile(`^\d+(\.\d{2}) MB$`)

func mustEmbeddedFS(t *testing.T) fs.FS {
	t.Helper()

	sub, err := fs.Sub(embeddedFiles, staticFolder)
	if err != nil {
		t.Fatalf("failed to load embedded fs: %v", err)
	}
	return sub
}

func TestStatsGetEndpointEmbeddedAndDisk(t *testing.T) {
	tests := []struct {
		name        string
		useEmbedded bool
	}{
		{name: "embedded", useEmbedded: true},
		{name: "disk", useEmbedded: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var efs fs.FS
			if tt.useEmbedded {
				efs = mustEmbeddedFS(t)
			}

			app := newApp(tt.useEmbedded, efs)
			req := httptest.NewRequest(http.MethodGet, "/stats", nil)
			resp, err := app.Test(req, -1)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				t.Fatalf("unexpected status: got %d want %d", resp.StatusCode, http.StatusOK)
			}
			if got := resp.Header.Get("Cache-Control"); got != "no-store" {
				t.Fatalf("unexpected cache-control: got %q want %q", got, "no-store")
			}

			var payload statsResponse
			if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
				t.Fatalf("failed to decode json: %v", err)
			}

			if payload.Runtime != "go/fiber" {
				t.Fatalf("unexpected runtime: got %q want %q", payload.Runtime, "go/fiber")
			}
			if !mbRegex.MatchString(payload.Memory.RSS) {
				t.Fatalf("rss format mismatch: %q", payload.Memory.RSS)
			}
			if !mbRegex.MatchString(payload.Memory.HeapUsed) {
				t.Fatalf("heap_used format mismatch: %q", payload.Memory.HeapUsed)
			}
			if !mbRegex.MatchString(payload.Memory.HeapTotal) {
				t.Fatalf("heap_total format mismatch: %q", payload.Memory.HeapTotal)
			}
		})
	}
}

func TestStatsHeadEndpoint(t *testing.T) {
	app := newApp(true, mustEmbeddedFS(t))
	req := httptest.NewRequest(http.MethodHead, "/stats", nil)
	resp, err := app.Test(req, -1)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("unexpected status: got %d want %d", resp.StatusCode, http.StatusOK)
	}
	if got := resp.Header.Get("Cache-Control"); got != "no-store" {
		t.Fatalf("unexpected cache-control: got %q want %q", got, "no-store")
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("failed to read response body: %v", err)
	}
	if len(body) != 0 {
		t.Fatalf("expected empty body for HEAD, got %d bytes", len(body))
	}
}

func TestStaticRouteRegression(t *testing.T) {
	app := newApp(true, mustEmbeddedFS(t))

	cases := []struct {
		path       string
		wantStatus int
	}{
		{path: "/", wantStatus: http.StatusOK},
		{path: "/about", wantStatus: http.StatusOK},
		{path: "/does-not-exist", wantStatus: http.StatusNotFound},
	}

	for _, tc := range cases {
		t.Run(tc.path, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tc.path, nil)
			resp, err := app.Test(req, -1)
			if err != nil {
				t.Fatalf("request failed: %v", err)
			}
			defer resp.Body.Close()

			if resp.StatusCode != tc.wantStatus {
				t.Fatalf("unexpected status for %s: got %d want %d", tc.path, resp.StatusCode, tc.wantStatus)
			}
		})
	}
}
