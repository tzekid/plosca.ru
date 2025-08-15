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

	app := fiber.New(fiber.Config{
		ServerHeader:          "ploscaru",
		DisableStartupMessage: false,
	})

	// Serve GET and HEAD with simple path normalization and .html fallback.
	h := func(c *fiber.Ctx) error {
		p := strings.TrimSpace(c.Path())
		if p == "" || p == "/" {
			p = "/index.html"
		} else {
			p = path.Clean("/" + p)
		}
		rel := strings.TrimPrefix(p, "/")
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

	app.Get("/*", h)
	app.Head("/*", h)

	addr := net.JoinHostPort("0.0.0.0", strconv.Itoa(port))
	abs, _ := filepath.Abs(".")
	log.Printf("Serving %s from %s on %s\n", staticFolder, abs, addr)
	if err := app.Listen(addr); err != nil {
		log.Fatal(err)
	}
}

// resolvePort prefers PORT env var, then --port/-p flags, else 9327.
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

// safeFile checks that the target exists, is a file, and remains within base.
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
