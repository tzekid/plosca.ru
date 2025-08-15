// nob — a tiny, Go-native task runner inspired by tsoding's nob.h
//
// Why: keep build/run logic in the project language without Makefiles.
//
// Usage examples:
//   go run ./cmd/nob run --port 9327
//   go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp
//
// Defaults are defined below; tweak them to fit your workflow.
package main

import (
    "errors"
    "flag"
    "fmt"
    "os"
    "os/exec"
    "runtime"
    "strings"
    "time"
)

// Default knobs — adjust as you like
var (
    defaultPort     = 9327
    defaultOutput   = "webapp"
    defaultLdflags  = "-s -w"
    defaultGOOS     = runtime.GOOS
    defaultGOARCH   = runtime.GOARCH
    defaultCGO      = "0" // "0" or "1"
)

func main() {
    if len(os.Args) < 2 {
        usage()
        os.Exit(2)
    }

    cmd := os.Args[1]
    switch cmd {
    case "run":
        runCmd := flag.NewFlagSet("run", flag.ExitOnError)
        port := runCmd.Int("port", defaultPort, "Port to forward via PORT env")
        runCmd.IntVar(port, "p", defaultPort, "Port to forward via PORT env (short)")
        runCmd.Parse(os.Args[2:])
        nobRun(*port)
    case "build":
        buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
        out := buildCmd.String("output", defaultOutput, "Output binary name")
        ld := buildCmd.String("ldflags", defaultLdflags, "go build -ldflags value")
        goos := buildCmd.String("os", defaultGOOS, "GOOS target (empty for host)")
        goarch := buildCmd.String("arch", defaultGOARCH, "GOARCH target (empty for host)")
        cgo := buildCmd.String("cgo", defaultCGO, "CGO_ENABLED: 0 or 1")
        buildCmd.Parse(os.Args[2:])
        nobBuild(*out, *ld, *goos, *goarch, *cgo)
    case "help", "-h", "--help":
        usage()
    default:
        fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", cmd)
        usage()
        os.Exit(2)
    }
}

func usage() {
    fmt.Print(`nob — minimal Go task runner

Commands
  run   : run the app with PORT env
  build : compile the app with preset flags

Examples
  go run ./cmd/nob run --port 9327
  go run ./cmd/nob build --os linux --arch amd64 --cgo 0 --output webapp

`)
}

func nobRun(port int) {
    env := append(os.Environ(), fmt.Sprintf("PORT=%d", port))
    cmd := exec.Command("go", "run", ".")
    cmd.Env = env
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.Stdin = os.Stdin
    fmt.Printf("[nob] running: PORT=%d go run .\n", port)
    if err := cmd.Run(); err != nil {
        os.Exit(exitCode(err))
    }
}

func nobBuild(output, ldflags, goos, goarch, cgo string) {
    // Compose environment for go build
    env := os.Environ()
    add := func(k, v string) { if strings.TrimSpace(v) != "" { env = append(env, k+"="+v) } }
    add("CGO_ENABLED", cgo)
    add("GOOS", goos)
    add("GOARCH", goarch)

    // Build command
    args := []string{"build", "-ldflags", ldflags, "-o", output, "."}
    cmd := exec.Command("go", args...)
    cmd.Env = env
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.Stdin = os.Stdin
    fmt.Printf("[nob] building: CGO_ENABLED=%s GOOS=%s GOARCH=%s go %s\n", cgo, goos, goarch, strings.Join(args, " "))
    if err := cmd.Run(); err != nil {
        os.Exit(exitCode(err))
    }

    // Optional: stamp build time
    fmt.Printf("[nob] built %s at %s\n", output, time.Now().Format(time.RFC3339))
}

func exitCode(err error) int {
    var ee *exec.ExitError
    if errors.As(err, &ee) {
        if ee.ProcessState != nil {
            return ee.ProcessState.ExitCode()
        }
    }
    return 1
}
