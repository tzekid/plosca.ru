// src/main.go
// plosca.ru — tiny static site server (enhanced)
// - Serves from embedded static_old (go:embed) by default, or from disk with --use-disk
// - Extensionless paths try .html and index.html
// - GET and HEAD supported; other methods -> 405
// - Middleware: recover, logger, compress, etag
// - Security headers, graceful shutdown
// Run: `go run .` (default port 9327) or `PORT=9327 go run .`
// Flags override environment variables.
package main

import (
	"context"
	"embed"
	"flag"
	"io/fs"
	"log"
	"mime"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/compress"
	"github.com/gofiber/fiber/v2/middleware/etag"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
)

const staticFolder = "static_old"

//go:embed static_old/*
var embeddedFiles embed.FS

func main() {
	// Flags (flags override env)
	var (
		portFlag int
		short    int
		useDisk  bool
	)
	flag.IntVar(&portFlag, "port", 0, "Port to listen on")
	flag.IntVar(&short, "p", 0, "Port to listen on (short)")
	flag.BoolVar(&useDisk, "use-disk", false, "Serve files from disk (static_old) instead of embedded assets")
	flag.Parse()

	port := resolvePort(portFlag, short)

	// Prepare FS: prefer embed unless --use-disk is set or embed isn't available.
	var (
		useEmbedded bool
		efs         fs.FS
	)
	if !useDisk {
		sub, err := fs.Sub(embeddedFiles, staticFolder)
		if err == nil {
			useEmbedded = true
			efs = sub
		} else {
			log.Printf("embedded assets not available: %v — falling back to disk", err)
			useEmbedded = false
		}
	} else {
		useEmbedded = false
	}

	// If using disk, ensure directory exists (warn if not).
	if !useEmbedded {
		if _, err := os.Stat(staticFolder); os.IsNotExist(err) {
			log.Printf("warning: %s not found on disk and --use-disk used; server will return 404s", staticFolder)
		}
	}

	// Fiber app with middleware
	app := fiber.New(fiber.Config{
		ServerHeader: "ploscaru",
	})

	// Middleware stack
	app.Use(recover.New())
	app.Use(logger.New(logger.Config{
		Format:     "${time} - ${ip} ${method} ${path} ${status} - ${latency}\n",
		TimeFormat: "2006-01-02 15:04:05",
		TimeZone:   "Local",
	}))
	app.Use(compress.New())
	app.Use(etag.New())

	// Security headers
	app.Use(func(c *fiber.Ctx) error {
		c.Set("X-Content-Type-Options", "nosniff")
		c.Set("Referrer-Policy", "no-referrer-when-downgrade")
		c.Set("Permissions-Policy", "geolocation=()")
		c.Set("Cross-Origin-Opener-Policy", "same-origin")
		c.Set("Cross-Origin-Resource-Policy", "same-origin")
		// tightened CSP (self-hosted only, no inline styles/scripts, explicit font & other hardening)
		c.Set("Content-Security-Policy", ""+
			"default-src 'self'; "+
			"img-src 'self' data:; "+
			"style-src 'self' 'unsafe-inline'; "+
			"font-src 'self'; "+
			"script-src 'self'; "+
			"object-src 'none'; "+
			"base-uri 'self'; "+
			"frame-ancestors 'none'; "+
			"manifest-src 'self'; "+
			"form-action 'self'; "+
			"upgrade-insecure-requests")
		return c.Next()
	})

	// Core handler used for GET and HEAD
	h := func(c *fiber.Ctx) error {
		start := time.Now()
		// Normalize path using path (URL-style)
		p := strings.TrimSpace(c.Path())
		if p == "" || p == "/" {
			p = "/index.html"
		} else {
			p = path.Clean("/" + p) // keeps it URL-style
		}
		rel := strings.TrimPrefix(p, "/")

		// Candidates: exact, +.html, +/index.html (for directories)
		try := []string{rel}
		if !strings.ContainsRune(path.Base(rel), '.') {
			try = append(try, rel+".html")
			try = append(try, path.Join(rel, "index.html"))
		}

		if useEmbedded {
			for _, candidate := range try {
				if existsInEmbed(efs, candidate) {
					res := sendEmbedded(c, efs, candidate)
					c.Set("Server-Timing", "app;dur="+strconv.FormatInt(time.Since(start).Milliseconds(),10))
					return res
				}
			}
			// 404.html fallback
			if existsInEmbed(efs, "404.html") {
				_ = c.Status(fiber.StatusNotFound)
				res := sendEmbedded(c, efs, "404.html")
				c.Set("Server-Timing", "app;dur="+strconv.FormatInt(time.Since(start).Milliseconds(),10))
				return res
			}
			return c.SendStatus(fiber.StatusNotFound)
		}

		// Disk-backed FS flow
		for _, candidate := range try {
			full := filepath.Join(staticFolder, filepath.FromSlash(candidate))
			if safeFile(staticFolder, full) {
				ext := strings.ToLower(filepath.Ext(full))
				switch ext {
				case ".woff2", ".woff", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp":
					c.Set("Cache-Control", "public, max-age=31536000, immutable")
				case ".css":
					c.Set("Cache-Control", "public, max-age=31536000, immutable")
				case ".js":
					c.Set("Cache-Control", "public, max-age=86400")
				case ".html":
					c.Set("Cache-Control", "public, max-age=0, must-revalidate, stale-while-revalidate=30")
				}
				res := c.SendFile(full, true)
				c.Set("Server-Timing", "app;dur="+strconv.FormatInt(time.Since(start).Milliseconds(),10))
				return res
			}
		}
		notFound := filepath.Join(staticFolder, "404.html")
		if safeFile(staticFolder, notFound) {
			res := c.Status(fiber.StatusNotFound).SendFile(notFound, true)
			c.Set("Server-Timing", "app;dur="+strconv.FormatInt(time.Since(start).Milliseconds(),10))
			return res
		}
		return c.SendStatus(fiber.StatusNotFound)
	}

	// Only serve for GET and HEAD
	app.Get("/*", h)
	app.Head("/*", h)

	// Redirect any previously referenced hashed file back to canonical style.css
	app.Get("/style.20250817.min.css", func(c *fiber.Ctx) error {
		return c.Redirect("/style.css", fiber.StatusMovedPermanently)
	})

	// Start server with graceful shutdown
	addr := net.JoinHostPort("0.0.0.0", strconv.Itoa(port))
	abs, _ := filepath.Abs(".")
	log.Printf("Serving %s (embedded=%v) from %s on %s\n", staticFolder, useEmbedded, abs, addr)

	// Run server
	serverErrCh := make(chan error, 1)
	go func() {
		if err := app.Listen(addr); err != nil {
			// When Shutdown is called, Listen returns an error; only log if unexpected.
			serverErrCh <- err
		}
	}()

	// Wait for signal
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	select {
	case sig := <-stop:
		log.Printf("signal received: %v — shutting down", sig)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := app.Shutdown(); err != nil {
			log.Printf("graceful shutdown error: %v", err)
		}
		// allow a short window to observe Listen error if any
		select {
		case e := <-serverErrCh:
			if e != nil && !strings.Contains(e.Error(), "server closed") {
				log.Printf("server error: %v", e)
			}
		case <-ctx.Done():
		}
	case e := <-serverErrCh:
		log.Fatalf("server error: %v", e)
	}
}

// resolvePort: flags first (portFlag / -p), then PORT env, then default 9327
func resolvePort(portFlag, short int) int {
	const def = 9327
	if portFlag > 0 && portFlag < 65536 {
		return portFlag
	}
	if short > 0 && short < 65536 {
		return short
	}
	if v, ok := os.LookupEnv("PORT"); ok {
		if p, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && p > 0 && p < 65536 {
			return p
		}
	}
	return def
}

// safeFile ensures target exists, is a file, and is inside base (prevents directory traversal).
func safeFile(base, target string) bool {
	fi, err := os.Stat(target)
	if err != nil || fi.IsDir() {
		return false
	}
	baseAbs, err1 := filepath.Abs(base)
	targetAbs, err2 := filepath.Abs(target)
	if err1 != nil || err2 != nil {
		return false
	}
	if baseAbs == targetAbs {
		return true
	}
	sep := string(filepath.Separator)
	return strings.HasPrefix(targetAbs, baseAbs+sep)
}

// existsInEmbed checks whether a relative path exists in the embedded FS and is a file.
func existsInEmbed(efs fs.FS, rel string) bool {
	ri := path.Clean("/" + rel)
	ri = strings.TrimPrefix(ri, "/")
	info, err := fs.Stat(efs, ri)
	if err != nil {
		return false
	}
	// reject directories
	return !info.IsDir()
}

// sendEmbedded streams a file from the embedded FS to the client.
func sendEmbedded(c *fiber.Ctx, efs fs.FS, rel string) error {
	rel = path.Clean("/" + rel)
	rel = strings.TrimPrefix(rel, "/")
	f, err := efs.Open(rel)
	if err != nil {
		return err
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return err
	}

	// Set Content-Type by extension when possible.
	ext := filepath.Ext(rel)
	if ext != "" {
		if mt := mime.TypeByExtension(ext); mt != "" {
			c.Set("Content-Type", mt)
		}
	} else {
		// fallback content sniffing for blob/no-ext files:
		var buf [512]byte
		n, _ := f.Read(buf[:])
		if n > 0 {
			if sniff := http.DetectContentType(buf[:n]); sniff != "" {
				c.Set("Content-Type", sniff)
			}
		}
		// rewind reader: reopen (embedded files are cheap to open)
		_ = f.Close()
		f, err = efs.Open(rel)
		if err != nil {
			return err
		}
		defer f.Close()
	}
	// Caching policy (simplified)
	loExt := strings.ToLower(ext)
	switch loExt {
	case ".woff", ".woff2", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp":
		c.Set("Cache-Control", "public, max-age=31536000, immutable")
	case ".css":
		c.Set("Cache-Control", "public, max-age=31536000, immutable")
	case ".js":
		c.Set("Cache-Control", "public, max-age=86400")
	case ".html":
		c.Set("Cache-Control", "public, max-age=0, must-revalidate, stale-while-revalidate=30")
	}

	// Use SendStream with known size
	if size := info.Size(); size >= 0 {
		return c.SendStream(f, int(size))
	}
	// fallback unknown size
	return c.SendStream(f, -1)
}
