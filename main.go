package main

import (
    "bytes"
    "context"
    "flag"
    "io"
    "log"
    "net"
    "os"
    "path"
    "path/filepath"
    "strconv"
    "strings"

    "github.com/gofiber/fiber/v2"
    "github.com/a-h/templ"
)

const staticFolder = "static_old"

func main() {
    port := resolvePort()

    app := fiber.New(fiber.Config{
        ServerHeader:          "plosca",
        DisableStartupMessage: false,
    })

    // Single catch-all route that mirrors the Zig path logic.
    app.All("/*", func(c *fiber.Ctx) error {
        method := c.Method()
        // Only serve GET/HEAD for static files
        if method != fiber.MethodGet && method != fiber.MethodHead {
            return c.SendStatus(fiber.StatusMethodNotAllowed)
        }

        reqPath := c.Path()
        full, ok := resolveStaticFile(staticFolder, reqPath)
        if ok {
            if method == fiber.MethodHead {
                // Set type and return headers only.
                if ext := strings.TrimPrefix(strings.ToLower(filepath.Ext(full)), "."); ext != "" {
                    c.Type(ext)
                }
                return c.SendStatus(fiber.StatusOK)
            }
            return c.SendFile(full, true)
        }

        // Try a static 404.html first
        notFoundFile := filepath.Join(staticFolder, "404.html")
        if fi, err := os.Stat(notFoundFile); err == nil && !fi.IsDir() {
            c.Set(fiber.HeaderContentType, "text/html; charset=utf-8")
            if method == fiber.MethodHead {
                return c.Status(fiber.StatusNotFound).Send(nil)
            }
            return c.Status(fiber.StatusNotFound).SendFile(notFoundFile, true)
        }

        // Fallback to a minimal templ-rendered 404 page.
        if method == fiber.MethodHead {
            return c.Status(fiber.StatusNotFound).Send(nil)
        }
        return renderNotFound(c, reqPath)
    })

    // Listen on 0.0.0.0 to allow container/VM access.
    addr := net.JoinHostPort("0.0.0.0", strconv.Itoa(port))
    abs, _ := filepath.Abs(".")
    log.Printf("Serving %s from %s on %s\n", staticFolder, abs, addr)
    if err := app.Listen(addr); err != nil {
        log.Fatal(err)
    }
}

// resolvePort returns the port, preferring the PORT environment variable.
// Falls back to --port/-p flag and then 9327.
func resolvePort() int {
    const def = 9327

    // Prefer PORT env var
    if v, ok := os.LookupEnv("PORT"); ok {
        if p, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && p > 0 && p < 65536 {
            return p
        }
    }

    // Allow overriding via CLI: --port 3000 or -p 3000
    var portFlag int
    var short int
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

// resolveStaticFile implements the Zig logic:
// - Normalizes the request path into a file under staticFolder
// - Adds ".html" when the path has no '.' (treat as a logical page)
// - Defaults "/" and "" to "index.html"
// - Ensures the final file is within the static folder and exists
func resolveStaticFile(baseDir, reqPath string) (string, bool) {
    p := strings.TrimSpace(reqPath)
    if p == "" || p == "/" {
        p = "/index.html"
    } else {
        // Clean and ensure leading slash for path.Clean to treat it as absolute
        p = path.Clean("/" + p)
        if !strings.ContainsRune(p, '.') {
            p += ".html"
        }
    }

    rel := strings.TrimPrefix(p, "/")
    // Join using OS separators; then validate it's inside baseDir.
    full := filepath.Join(baseDir, rel)
    if !withinBase(baseDir, full) {
        return "", false
    }
    fi, err := os.Stat(full)
    if err != nil || fi.IsDir() {
        return "", false
    }
    return full, true
}

func withinBase(base, target string) bool {
    baseAbs, err1 := filepath.Abs(base)
    targetAbs, err2 := filepath.Abs(target)
    if err1 != nil || err2 != nil {
        return false
    }
    rel, err := filepath.Rel(baseAbs, targetAbs)
    if err != nil {
        return false
    }
    return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func renderNotFound(c *fiber.Ctx, requestPath string) error {
    // Minimal templ component usage to keep things simple and imperative.
    page := NotFoundPage{Path: requestPath}
    var buf bytes.Buffer
    // Use the request context if available, otherwise background.
    var ctx context.Context = c.UserContext()
    if ctx == nil {
        ctx = context.Background()
    }
    if err := page.Render(ctx, &buf); err != nil {
        return c.Status(fiber.StatusInternalServerError).SendString("render error")
    }
    c.Set(fiber.HeaderContentType, "text/html; charset=utf-8")
    return c.Status(fiber.StatusNotFound).Send(buf.Bytes())
}

// NotFoundPage is a tiny templ component implemented imperatively.
// This keeps templ in place without adding codegen complexity yet.
type NotFoundPage struct {
    Path string
}

// Ensure NotFoundPage satisfies templ.Component.
var _ templ.Component = NotFoundPage{}

func (n NotFoundPage) Render(ctx context.Context, w io.Writer) error {
    // fiber.ResponseWriter implements io.Writer; keep output minimal.
    // Write out a tiny HTML document.
    _, err := w.Write([]byte("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>404 Not Found</title><style>html,body{height:100%;margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,\"Helvetica Neue\",Arial,sans-serif;background:#0b1020;color:#e7e9ee}main{min-height:100%;display:grid;place-items:center}section{padding:2rem;text-align:center}code{background:#121733;padding:.2rem .4rem;border-radius:.25rem;color:#9fd4ff}</style></head><body><main><section><h1>404 — Not Found</h1><p>No page for <code>" + htmlEscape(n.Path) + "</code>.</p><p><a href=\"/\" style=\"color:#9fd4ff;text-decoration:none\">Back to home</a></p></section></main></body></html>"))
    return err
}

// htmlEscape is a tiny helper to avoid injecting raw paths into HTML.
func htmlEscape(s string) string {
    s = strings.ReplaceAll(s, "&", "&amp;")
    s = strings.ReplaceAll(s, "<", "&lt;")
    s = strings.ReplaceAll(s, ">", "&gt;")
    s = strings.ReplaceAll(s, "\"", "&quot;")
    s = strings.ReplaceAll(s, "'", "&#39;")
    return s
}
