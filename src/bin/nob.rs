use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Parser, Subcommand};

const DEFAULT_PORT: u16 = 9327;
const DEFAULT_OUTPUT: &str = "webapp";
const DEFAULT_SERVICE: &str = "tzekid_website.service";

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
    Build(BuildArgs),
    Docker(DockerArgs),
    #[command(name = "restart-nohup")]
    RestartNohup(RestartNohupArgs),
    #[command(name = "pbr")]
    PullBuildRestart,
    SelfBuild(SelfBuildArgs),
}

#[derive(Debug, Args)]
struct RunArgs {
    #[arg(long, default_value_t = DEFAULT_PORT)]
    port: u16,
}

#[derive(Debug, Args)]
struct BuildArgs {
    #[arg(long, default_value = DEFAULT_OUTPUT)]
    output: String,

    #[arg(long)]
    target: Option<String>,
}

#[derive(Debug, Args)]
struct DockerArgs {
    #[arg(long, default_value = "tzekid/plosca.ru")]
    repo: String,

    #[arg(long, default_value = "latest")]
    tag: String,

    #[arg(long, default_value = "linux/amd64")]
    platform: String,

    #[arg(long, default_value_t = false)]
    push: bool,
}

#[derive(Debug, Args)]
struct RestartNohupArgs {
    #[arg(long, default_value = DEFAULT_OUTPUT)]
    output: String,

    #[arg(long)]
    bin: Option<PathBuf>,

    #[arg(long, default_value = "webapp.log")]
    log: PathBuf,

    #[arg(long, default_value_t = false)]
    pull: bool,

    #[arg(long, default_value_t = false)]
    append: bool,
}

#[derive(Debug, Args)]
struct SelfBuildArgs {
    #[arg(long, default_value = "nob.bin")]
    output: PathBuf,
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
        Some(Commands::Build(args)) => {
            build_webapp(&args.output, args.target.as_deref())?;
            println!("[nob] built {}", args.output);
            Ok(())
        }
        Some(Commands::Docker(args)) => docker_build(args),
        Some(Commands::RestartNohup(args)) => restart_nohup(args),
        Some(Commands::PullBuildRestart) => pull_build_restart(&cli.service),
        Some(Commands::SelfBuild(args)) => self_build(args),
    }
}

fn run_webapp(args: RunArgs) -> Result<()> {
    let mut cmd = Command::new("cargo");
    cmd.args(["run", "--release", "--bin", "webapp", "--"])
        .arg("--port")
        .arg(args.port.to_string())
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    run_status(&mut cmd)
}

fn build_webapp(output: &str, target: Option<&str>) -> Result<PathBuf> {
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

    let output_path = root.join(output);
    if output_path != built {
        fs::copy(&built, &output_path).with_context(|| {
            format!(
                "failed to copy built webapp from {} to {}",
                built.display(),
                output_path.display()
            )
        })?;
        make_executable(&output_path)?;
    }

    Ok(output_path)
}

fn docker_build(args: DockerArgs) -> Result<()> {
    let image = format!("{}:{}", args.repo, args.tag);

    let mut docker = Command::new("docker");
    docker
        .args(["build", "--platform", &args.platform, "-t", &image, "."])
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    run_status(&mut docker)?;

    if args.push {
        let mut push = Command::new("docker");
        push.args(["push", &image])
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
        run_status(&mut push)?;
    }

    Ok(())
}

fn restart_nohup(args: RestartNohupArgs) -> Result<()> {
    if args.pull {
        git_pull()?;
    }

    let built = build_webapp(&args.output, None)?;
    let run_path = match args.bin {
        Some(path) if path.is_absolute() => path,
        Some(path) => repo_root()?.join(path),
        None => built,
    };

    let binary_name = run_path
        .file_name()
        .and_then(OsStr::to_str)
        .ok_or_else(|| anyhow!("invalid binary path {}", run_path.display()))?;

    let _ = Command::new("pkill").args(["-x", binary_name]).status();
    let _ = Command::new("pkill")
        .args(["-f", &run_path.display().to_string()])
        .status();

    thread::sleep(Duration::from_millis(300));

    let log_path = if args.log.is_absolute() {
        args.log
    } else {
        repo_root()?.join(args.log)
    };

    if let Some(parent) = log_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create log directory {}", parent.display()))?;
    }

    let file = if args.append {
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

    println!(
        "[nob] starting with nohup: {} > {} 2>&1 &",
        run_path.display(),
        log_path.display()
    );

    let mut cmd = Command::new("nohup");
    cmd.arg(&run_path)
        .stdout(Stdio::from(file.try_clone()?))
        .stderr(Stdio::from(file))
        .stdin(Stdio::null())
        .envs(env::vars());

    let child = cmd
        .spawn()
        .with_context(|| format!("failed to start {}", run_path.display()))?;

    println!("[nob] started PID {}", child.id());
    Ok(())
}

fn pull_build_restart(service: &str) -> Result<()> {
    git_pull()?;
    let _ = build_webapp(DEFAULT_OUTPUT, None)?;

    let mut restart = Command::new("sudo");
    restart
        .args(["systemctl", "restart", service])
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    run_status(&mut restart)
}

fn self_build(args: SelfBuildArgs) -> Result<()> {
    let root = repo_root()?;

    let mut cargo = Command::new("cargo");
    cargo
        .args(["build", "--release", "--bin", "nob"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    run_status(&mut cargo)?;

    let built = root.join("target").join("release").join("nob");
    if !built.exists() {
        bail!("built nob binary not found at {}", built.display());
    }

    let output = if args.output.is_absolute() {
        args.output
    } else {
        root.join(args.output)
    };

    fs::copy(&built, &output).with_context(|| {
        format!(
            "failed to copy built nob from {} to {}",
            built.display(),
            output.display()
        )
    })?;
    make_executable(&output)?;

    println!("[nob] self binary refreshed at {}", output.display());
    Ok(())
}

fn git_pull() -> Result<()> {
    let mut pull = Command::new("git");
    pull.arg("pull")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    run_status(&mut pull)
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
  build          Build release webapp and copy to ./webapp\n\
  docker         Build docker image (linux/amd64 by default)\n\
  restart-nohup  Build and relaunch app via nohup\n\
  pbr            git pull + build + sudo systemctl restart service\n\
  self-build     Build nob binary and copy to a local output path\n\
  help           Show this message\n\
\nExamples:\n\
  ./nob run --port 9327\n\
  ./nob build --output webapp\n\
  ./nob restart-nohup --pull --log webapp.log\n\
  ./nob pbr --service tzekid_website.service\n"
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_restart_nohup_command() {
        let cli = Cli::try_parse_from(["nob", "restart-nohup", "--pull", "--log", "webapp.log"])
            .expect("cli parse should succeed");

        match cli.command.expect("command should exist") {
            Commands::RestartNohup(args) => {
                assert!(args.pull);
                assert_eq!(args.log, PathBuf::from("webapp.log"));
            }
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn parse_pbr_with_service() {
        let cli = Cli::try_parse_from(["nob", "--service", "custom.service", "pbr"])
            .expect("cli parse should succeed");

        assert_eq!(cli.service, "custom.service");
        matches!(cli.command, Some(Commands::PullBuildRestart));
    }
}
