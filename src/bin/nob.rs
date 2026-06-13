use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Parser, Subcommand};
use sha2::{Digest, Sha256};

const DEFAULT_PORT: u16 = 9327;
const DEFAULT_SERVICE: &str = "tzekid_website.service";
const DEFAULT_PACKAGE_DIR: &str = "dist";
const DEFAULT_LOG: &str = "webapp.log";
const DEFAULT_PID_FILE: &str = "webapp.pid";
const DEFAULT_OUTPUT: &str = "webapp";

#[derive(Debug, Parser)]
#[command(name = "nob", about = "Rust task runner for plosca.ru")]
struct Cli {
    #[arg(long, short = 's', global = true, default_value = DEFAULT_SERVICE)]
    service: String,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Debug, Subcommand)]
enum Commands {
    Run(RunArgs),
    Check,
    Build(BuildArgs),
    Package(PackageArgs),
    Daemon(DaemonArgs),
    Service(ServiceArgs),
    #[command(name = "print-unit")]
    PrintUnit(PrintUnitArgs),
}

#[derive(Debug, Args)]
struct RunArgs {
    #[arg(long, default_value_t = DEFAULT_PORT)]
    port: u16,
}

#[derive(Debug, Args)]
struct BuildArgs {
    #[arg(long)]
    target: Option<String>,
}

#[derive(Debug, Args)]
struct PackageArgs {
    #[arg(long)]
    target: Option<String>,

    #[arg(long, default_value = DEFAULT_PACKAGE_DIR)]
    output_dir: PathBuf,
}

#[derive(Debug, Args)]
struct DaemonArgs {
    #[command(subcommand)]
    command: DaemonCommand,
}

#[derive(Debug, Subcommand)]
enum DaemonCommand {
    Start(DaemonStartArgs),
    Stop(DaemonStopArgs),
    Restart(DaemonStartArgs),
    Status(DaemonStatusArgs),
    Logs(DaemonLogsArgs),
}

#[derive(Debug, Args, Clone)]
struct DaemonStartArgs {
    #[arg(long, default_value_t = DEFAULT_PORT)]
    port: u16,

    #[arg(long, default_value = DEFAULT_OUTPUT)]
    output: PathBuf,

    #[arg(long, default_value = DEFAULT_LOG)]
    log: PathBuf,

    #[arg(long, default_value = DEFAULT_PID_FILE)]
    pid_file: PathBuf,

    #[arg(long, default_value_t = false)]
    append: bool,

    #[arg(long, default_value_t = false)]
    build: bool,

    #[arg(long)]
    target: Option<String>,
}

#[derive(Debug, Args)]
struct DaemonStopArgs {
    #[arg(long, default_value = DEFAULT_PID_FILE)]
    pid_file: PathBuf,

    #[arg(long, default_value_t = false)]
    force: bool,
}

#[derive(Debug, Args)]
struct DaemonStatusArgs {
    #[arg(long, default_value = DEFAULT_PID_FILE)]
    pid_file: PathBuf,
}

#[derive(Debug, Args)]
struct DaemonLogsArgs {
    #[arg(long, default_value = DEFAULT_LOG)]
    log: PathBuf,

    #[arg(long, default_value_t = 200)]
    lines: u32,

    #[arg(long, default_value_t = false)]
    follow: bool,
}

#[derive(Debug, Args)]
struct ServiceArgs {
    #[command(subcommand)]
    command: ServiceCommand,
}

#[derive(Debug, Subcommand)]
enum ServiceCommand {
    Restart,
    Status,
    Logs(ServiceLogsArgs),
}

#[derive(Debug, Args)]
struct ServiceLogsArgs {
    #[arg(long, default_value_t = 200)]
    lines: u32,

    #[arg(long, default_value_t = false)]
    follow: bool,
}

#[derive(Debug, Args)]
struct PrintUnitArgs {
    #[arg(long, default_value = "/opt/plosca.ru/webapp")]
    exec_path: PathBuf,

    #[arg(long, default_value = "/opt/plosca.ru")]
    working_directory: PathBuf,

    #[arg(long, default_value = "www-data")]
    user: String,

    #[arg(long, default_value_t = DEFAULT_PORT)]
    port: u16,
}

fn main() {
    if let Err(err) = real_main() {
        eprintln!("[nob] error: {err:#}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        None => {
            print_help();
            Ok(())
        }
        Some(Commands::Run(args)) => run_webapp(args),
        Some(Commands::Check) => check_repo(),
        Some(Commands::Build(args)) => build_command(args),
        Some(Commands::Package(args)) => package_webapp(args),
        Some(Commands::Daemon(args)) => daemon_command(args),
        Some(Commands::Service(args)) => service_command(&cli.service, args),
        Some(Commands::PrintUnit(args)) => {
            print_unit(&cli.service, args);
            Ok(())
        }
    }
}

fn run_webapp(args: RunArgs) -> Result<()> {
    let mut cmd = Command::new("cargo");
    cmd.args(["run", "--release", "--bin", "webapp", "--"])
        .arg("serve")
        .arg("--port")
        .arg(args.port.to_string())
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    run_status(&mut cmd)
}

fn check_repo() -> Result<()> {
    for args in [
        &["fmt", "--check"][..],
        &["clippy", "--all-targets", "--", "-D", "warnings"][..],
        &["test"][..],
    ] {
        let mut cargo = Command::new("cargo");
        cargo
            .args(args)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
        run_status(&mut cargo)?;
    }
    Ok(())
}

fn build_command(args: BuildArgs) -> Result<()> {
    let built = build_webapp(args.target.as_deref())?;
    println!("[nob] built {}", built.display());
    Ok(())
}

fn build_webapp(target: Option<&str>) -> Result<PathBuf> {
    let mut cargo = Command::new("cargo");
    cargo.args(["build", "--release", "--bin", "webapp"]);
    if let Some(target) = target {
        cargo.arg("--target").arg(target);
    }
    cargo
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    run_status(&mut cargo)?;

    let root = repo_root()?;
    let built = match target {
        Some(triple) => root
            .join("target")
            .join(triple)
            .join("release")
            .join("webapp"),
        None => root.join("target").join("release").join("webapp"),
    };

    if !built.exists() {
        bail!("built artifact not found at {}", built.display());
    }

    Ok(built)
}

fn package_webapp(args: PackageArgs) -> Result<()> {
    let built = build_webapp(args.target.as_deref())?;
    let root = repo_root()?;
    let git_sha = git_short_sha().unwrap_or_else(|_| "unknown".to_string());
    let output_dir = if args.output_dir.is_absolute() {
        args.output_dir
    } else {
        root.join(args.output_dir)
    };
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let target_suffix = args
        .target
        .as_deref()
        .unwrap_or(env::consts::ARCH)
        .replace('/', "-");
    let artifact_name = format!("webapp-{git_sha}-{target_suffix}");
    let artifact_path = output_dir.join(&artifact_name);

    fs::copy(&built, &artifact_path).with_context(|| {
        format!(
            "failed to copy built webapp from {} to {}",
            built.display(),
            artifact_path.display()
        )
    })?;
    make_executable(&artifact_path)?;

    let checksum = sha256_file(&artifact_path)?;
    let checksum_path = output_dir.join(format!("{artifact_name}.sha256"));
    fs::write(&checksum_path, format!("{checksum}  {artifact_name}\n"))
        .with_context(|| format!("failed to write {}", checksum_path.display()))?;

    println!(
        "[nob] packaged {} and {}",
        artifact_path.display(),
        checksum_path.display()
    );
    Ok(())
}

fn daemon_command(args: DaemonArgs) -> Result<()> {
    match args.command {
        DaemonCommand::Start(args) => daemon_start(args, false),
        DaemonCommand::Restart(args) => daemon_start(args, true),
        DaemonCommand::Stop(args) => daemon_stop(args),
        DaemonCommand::Status(args) => daemon_status(args),
        DaemonCommand::Logs(args) => daemon_logs(args),
    }
}

fn daemon_start(args: DaemonStartArgs, restart: bool) -> Result<()> {
    let root = repo_root()?;
    let pid_path = resolve_repo_path(&root, &args.pid_file);
    let log_path = resolve_repo_path(&root, &args.log);
    let run_path = resolve_repo_path(&root, &args.output);

    if restart {
        let _ = stop_pid_file(&pid_path, false);
    } else if let Some(pid) = read_live_pid(&pid_path)? {
        bail!(
            "background webapp already running with pid {pid}; use `nob daemon restart` or `nob daemon stop`"
        );
    }

    if args.build {
        let built = build_webapp(args.target.as_deref())?;
        install_binary(&built, &run_path)?;
    } else if !run_path.exists() {
        bail!(
            "binary not found at {}; use `--build` or run `nob build` first",
            run_path.display()
        );
    }

    if let Some(parent) = log_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create log directory {}", parent.display()))?;
    }
    if let Some(parent) = pid_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create pid directory {}", parent.display()))?;
    }

    let log_file = if args.append {
        fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .with_context(|| format!("failed to open {}", log_path.display()))?
    } else {
        fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&log_path)
            .with_context(|| format!("failed to open {}", log_path.display()))?
    };

    let mut cmd = Command::new(&run_path);
    cmd.arg("serve")
        .arg("--port")
        .arg(args.port.to_string())
        .stdout(Stdio::from(log_file.try_clone()?))
        .stderr(Stdio::from(log_file))
        .stdin(Stdio::null())
        .current_dir(&root)
        .envs(env::vars());
    detach_command(&mut cmd);

    println!(
        "[nob] starting background webapp: {} serve --port {}",
        run_path.display(),
        args.port
    );
    let child = cmd
        .spawn()
        .with_context(|| format!("failed to start {}", run_path.display()))?;
    let pid = child.id();

    thread::sleep(Duration::from_millis(500));
    if !process_exists(pid) {
        let _ = fs::remove_file(&pid_path);
        bail!(
            "background webapp exited immediately; inspect {}",
            log_path.display()
        );
    }

    if let Err(err) = smoke_check_server(args.port) {
        let _ = stop_process(pid);
        let _ = fs::remove_file(&pid_path);
        return Err(err.context(format!(
            "background webapp failed smoke checks after start; inspect {}",
            log_path.display()
        )));
    }

    fs::write(&pid_path, format!("{pid}\n"))
        .with_context(|| format!("failed to write pid file {}", pid_path.display()))?;

    println!(
        "[nob] started pid {} with pid file {} and log {}",
        pid,
        pid_path.display(),
        log_path.display()
    );
    Ok(())
}

#[cfg(unix)]
fn detach_command(cmd: &mut Command) {
    use std::os::unix::process::CommandExt;

    unsafe {
        cmd.pre_exec(|| {
            if libc::setsid() == -1 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
}

#[cfg(not(unix))]
fn detach_command(_cmd: &mut Command) {}

fn smoke_check_server(port: u16) -> Result<()> {
    wait_for_http_body(port, "/healthz", |body| body.trim() == "ok")?;
    wait_for_http_body(port, "/", |body| {
        body.contains("/assets/style.") && body.contains(".woff2")
    })?;
    Ok(())
}

fn wait_for_http_body(port: u16, path: &str, predicate: impl Fn(&str) -> bool) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut last_observation = None::<String>;

    while Instant::now() < deadline {
        match curl_get(port, path) {
            Ok(body) if predicate(&body) => return Ok(body),
            Ok(body) => {
                last_observation = Some(
                    body
                        .lines()
                        .next()
                        .unwrap_or("empty body")
                        .to_string(),
                );
            }
            Err(err) => last_observation = Some(err.to_string()),
        }
        thread::sleep(Duration::from_millis(250));
    }

    bail!(
        "smoke check for {} on port {} did not succeed: {}",
        path,
        port,
        last_observation.unwrap_or_else(|| "no response observed".to_string())
    )
}

fn curl_get(port: u16, path: &str) -> Result<String> {
    let output = Command::new("curl")
        .arg("-fsS")
        .arg(format!("http://127.0.0.1:{port}{path}"))
        .output()
        .with_context(|| format!("failed to run curl for {path}"))?;

    if !output.status.success() {
        bail!("curl exited with status {} for {}", output.status, path);
    }

    String::from_utf8(output.stdout).context("curl output should be valid utf-8")
}

fn stop_process(pid: u32) -> Result<()> {
    let status = Command::new("kill")
        .arg("-TERM")
        .arg(pid.to_string())
        .status()
        .context("failed to run kill")?;
    if status.success() {
        Ok(())
    } else {
        bail!("failed to stop pid {}", pid);
    }
}

fn daemon_stop(args: DaemonStopArgs) -> Result<()> {
    let root = repo_root()?;
    let pid_path = resolve_repo_path(&root, &args.pid_file);
    stop_pid_file(&pid_path, args.force)
}

fn daemon_status(args: DaemonStatusArgs) -> Result<()> {
    let root = repo_root()?;
    let pid_path = resolve_repo_path(&root, &args.pid_file);
    match read_pid(&pid_path)? {
        Some(pid) if process_exists(pid) => {
            println!(
                "[nob] running with pid {} (pid file {})",
                pid,
                pid_path.display()
            );
            Ok(())
        }
        Some(pid) => {
            println!(
                "[nob] stale pid file {} points to dead pid {}",
                pid_path.display(),
                pid
            );
            Ok(())
        }
        None => {
            println!("[nob] not running (no pid file at {})", pid_path.display());
            Ok(())
        }
    }
}

fn daemon_logs(args: DaemonLogsArgs) -> Result<()> {
    let root = repo_root()?;
    let log_path = resolve_repo_path(&root, &args.log);
    let mut cmd = Command::new("tail");
    cmd.arg("-n").arg(args.lines.to_string());
    if args.follow {
        cmd.arg("-f");
    }
    cmd.arg(&log_path)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    run_status(&mut cmd)
}

fn service_command(service: &str, args: ServiceArgs) -> Result<()> {
    match args.command {
        ServiceCommand::Restart => {
            let mut cmd = Command::new("sudo");
            cmd.args(["systemctl", "restart", service])
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
            run_status(&mut cmd)
        }
        ServiceCommand::Status => {
            let mut cmd = Command::new("systemctl");
            cmd.args(["status", service])
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
            run_status(&mut cmd)
        }
        ServiceCommand::Logs(args) => {
            let mut cmd = Command::new("journalctl");
            cmd.arg("-u")
                .arg(service)
                .arg("-n")
                .arg(args.lines.to_string());
            if args.follow {
                cmd.arg("-f");
            }
            cmd.stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
            run_status(&mut cmd)
        }
    }
}

fn print_unit(service: &str, args: PrintUnitArgs) {
    println!(
        "[Unit]
Description={service}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={}
WorkingDirectory={}
ExecStart={} serve --port {}
Restart=on-failure
RestartSec=3
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target",
        args.user,
        args.working_directory.display(),
        args.exec_path.display(),
        args.port
    );
}

fn git_short_sha() -> Result<String> {
    let output = Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .context("failed to run git rev-parse")?;
    if !output.status.success() {
        bail!("git rev-parse --short HEAD failed");
    }
    String::from_utf8(output.stdout)
        .map(|value| value.trim().to_string())
        .context("invalid utf8 in git sha")
}

fn sha256_file(path: &Path) -> Result<String> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    let digest = Sha256::digest(bytes);
    Ok(format!("{digest:x}"))
}

fn run_status(cmd: &mut Command) -> Result<()> {
    println!("[nob] running: {:?}", cmd);
    let status = cmd.status().context("failed to spawn command")?;
    if status.success() {
        Ok(())
    } else {
        Err(anyhow!("command exited with status {status}"))
    }
}

fn repo_root() -> Result<PathBuf> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .context("failed to run git rev-parse")?;

    if !output.status.success() {
        bail!("could not determine git repository root");
    }

    let root = String::from_utf8(output.stdout).context("invalid utf8 in git root output")?;
    Ok(PathBuf::from(root.trim()))
}

fn make_executable(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        let mut perms = fs::metadata(path)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(path, perms)?;
    }

    #[cfg(not(unix))]
    {
        let _ = path;
    }

    Ok(())
}

fn print_help() {
    println!(
        "nob — plosca.ru task runner\n\
\nCommands:\n\
  run            Run webapp with a chosen port\n\
  check          Run fmt, clippy, and tests\n\
  build          Build release webapp\n\
  package        Produce a versioned release artifact and checksum\n\
  daemon         Manage a background webapp process via pid/log files\n\
  service        Run systemd service operations\n\
  print-unit     Print a systemd unit template\n\
  help           Show this message\n\
\nExamples:\n\
  ./nob run --port 9327\n\
  ./nob check\n\
  ./nob build\n\
  ./nob package\n\
  ./nob daemon restart --build --port 9327\n\
  ./nob daemon logs --follow\n\
  ./nob service restart --service tzekid_website.service\n"
    );
}

fn resolve_repo_path(root: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        root.join(path)
    }
}

fn install_binary(source: &Path, dest: &Path) -> Result<()> {
    if source == dest {
        return Ok(());
    }
    fs::copy(source, dest).with_context(|| {
        format!(
            "failed to copy built webapp from {} to {}",
            source.display(),
            dest.display()
        )
    })?;
    make_executable(dest)
}

fn read_live_pid(pid_path: &Path) -> Result<Option<u32>> {
    Ok(read_pid(pid_path)?.filter(|pid| process_exists(*pid)))
}

fn read_pid(pid_path: &Path) -> Result<Option<u32>> {
    if !pid_path.exists() {
        return Ok(None);
    }

    let raw = fs::read_to_string(pid_path)
        .with_context(|| format!("failed to read pid file {}", pid_path.display()))?;
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let pid = trimmed
        .parse::<u32>()
        .with_context(|| format!("invalid pid in {}", pid_path.display()))?;
    Ok(Some(pid))
}

fn stop_pid_file(pid_path: &Path, force: bool) -> Result<()> {
    match read_pid(pid_path)? {
        Some(pid) if process_exists(pid) => {
            let signal = if force { "-KILL" } else { "-TERM" };
            let status = Command::new("kill")
                .arg(signal)
                .arg(pid.to_string())
                .status()
                .context("failed to run kill")?;
            if !status.success() {
                bail!("failed to stop pid {}", pid);
            }

            for _ in 0..20 {
                if !process_exists(pid) {
                    let _ = fs::remove_file(pid_path);
                    println!("[nob] stopped pid {}", pid);
                    return Ok(());
                }
                thread::sleep(Duration::from_millis(100));
            }

            if force {
                bail!("pid {} is still alive after SIGKILL", pid);
            }

            let kill_status = Command::new("kill")
                .arg("-KILL")
                .arg(pid.to_string())
                .status()
                .context("failed to run kill -KILL")?;
            if !kill_status.success() {
                bail!("failed to SIGKILL pid {}", pid);
            }
            let _ = fs::remove_file(pid_path);
            println!("[nob] force-stopped pid {}", pid);
            Ok(())
        }
        Some(pid) => {
            let _ = fs::remove_file(pid_path);
            println!("[nob] removed stale pid file for dead pid {}", pid);
            Ok(())
        }
        None => {
            println!("[nob] not running");
            Ok(())
        }
    }
}

fn process_exists(pid: u32) -> bool {
    Command::new("kill")
        .arg("-0")
        .arg(pid.to_string())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_daemon_restart_command() {
        let cli = Cli::try_parse_from(["nob", "daemon", "restart", "--build", "--port", "9000"])
            .expect("cli parse should succeed");

        match cli.command.expect("command should exist") {
            Commands::Daemon(args) => match args.command {
                DaemonCommand::Restart(restart) => {
                    assert!(restart.build);
                    assert_eq!(restart.port, 9000);
                }
                other => panic!("unexpected daemon command: {other:?}"),
            },
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn parse_daemon_logs_command() {
        let cli = Cli::try_parse_from(["nob", "daemon", "logs", "--lines", "50", "--follow"])
            .expect("cli parse should succeed");

        match cli.command.expect("command should exist") {
            Commands::Daemon(args) => match args.command {
                DaemonCommand::Logs(logs) => {
                    assert_eq!(logs.lines, 50);
                    assert!(logs.follow);
                }
                other => panic!("unexpected daemon command: {other:?}"),
            },
            other => panic!("unexpected command: {other:?}"),
        }
    }
}
