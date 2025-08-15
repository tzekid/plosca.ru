// plosca.ru — tiny static site server
//
// This app serves files from the local "static_old" directory using Fiber.
// It keeps behavior beginner-friendly:
//   - Requests without an extension map to the same path with ".html" appended
//     (e.g., GET /about -> static_old/about.html).
//   - GET and HEAD are supported; everything else returns 405.
//   - 404s return static_old/404.html if present, otherwise a plain 404 status.
//
// Run: `go run .` (default port 9327) or `PORT=9327 go run .`.
// Docker: `docker compose up --build` then open http://localhost:9327
package main

import (
	"flag"
	"log"
	"net"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

const staticFolder = "static_old"

func main() {
	port := resolvePort()

	// Minimal Fiber instance; server header is just for easy identification.
	app := fiber.New(fiber.Config{
		ServerHeader:          "ploscaru",
		DisableStartupMessage: false,
	})

	// Core handler used by both GET and HEAD.
	// - Cleans the request path
	// - Tries the exact file, then ".html" if no extension is present
	// - Falls back to 404.html or a plain 404
	h := func(c *fiber.Ctx) error {
		p := strings.TrimSpace(c.Path())
		if p == "" || p == "/" {
			p = "/index.html"
		} else {
			// Ensure a clean, absolute-style path for consistent joining below.
			p = path.Clean("/" + p)
		}
		rel := strings.TrimPrefix(p, "/")
		// Candidate files to try in order.
		try := []string{filepath.Join(staticFolder, rel)}
		if !strings.ContainsRune(filepath.Base(rel), '.') {
			try = append(try, filepath.Join(staticFolder, rel+".html"))
		}
		for _, full := range try {
			if safeFile(staticFolder, full) {
				return c.SendFile(full, true)
			}
		}

		// 404: serve static 404.html if present; else plain status.
		notFound := filepath.Join(staticFolder, "404.html")
		if safeFile(staticFolder, notFound) {
			return c.Status(fiber.StatusNotFound).SendFile(notFound, true)
		}
		return c.SendStatus(fiber.StatusNotFound)
	}

	// Only serve static content for GET/HEAD. Other methods return 405 by default.
	app.Get("/*", h)
	app.Head("/*", h)

	// Listen on all interfaces for container/VM friendliness.
	addr := net.JoinHostPort("0.0.0.0", strconv.Itoa(port))
	abs, _ := filepath.Abs(".")
	log.Printf("Serving %s from %s on %s\n", staticFolder, abs, addr)
	if err := app.Listen(addr); err != nil {
		log.Fatal(err)
	}
}

// resolvePort determines the HTTP port.
// Order of precedence:
// 1) PORT environment variable
// 2) --port / -p command-line flags
// 3) default 9327
func resolvePort() int {
	const def = 9327
	if v, ok := os.LookupEnv("PORT"); ok {
		if p, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && p > 0 && p < 65536 {
			return p
		}
	}
	var portFlag, short int
	flag.IntVar(&portFlag, "port", 0, "Port to listen on")
	flag.IntVar(&short, "p", 0, "Port to listen on (short)")
	flag.Parse()
	if portFlag > 0 && portFlag < 65536 {
		return portFlag
	}
	if short > 0 && short < 65536 {
		return short
	}
	return def
}

// safeFile returns true if target exists, is a file, and lives under base.
// This prevents directory traversal from escaping the static folder.
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
