use std::env;
use std::path::PathBuf;
use std::time::Duration;

use clap::{Parser, Subcommand, ValueEnum};

#[derive(Debug, Clone, Copy, ValueEnum, Eq, PartialEq)]
pub enum AssetMode {
    Embedded,
    Disk,
}

#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub host: String,
    pub port: u16,
    pub asset_mode: AssetMode,
    pub static_dir: PathBuf,
    pub shutdown_timeout: Duration,
}

#[derive(Debug, Clone, Parser)]
#[command(name = "webapp", version, about = "plosca.ru axum server")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,

    #[command(flatten)]
    pub serve: ServeArgs,
}

#[derive(Debug, Clone, Subcommand)]
pub enum Commands {
    Serve(ServeArgs),
}

#[derive(Debug, Clone, clap::Args)]
pub struct ServeArgs {
    #[arg(long)]
    pub port: Option<u16>,

    #[arg(long, default_value = "0.0.0.0")]
    pub host: String,

    #[arg(long, value_enum, default_value_t = AssetMode::Embedded)]
    pub assets: AssetMode,

    #[arg(long, default_value = "static_old")]
    pub static_dir: PathBuf,

    #[arg(long, default_value_t = 5)]
    pub shutdown_timeout_seconds: u64,

    #[arg(long, default_value_t = false)]
    pub use_disk: bool,
}

impl RuntimeConfig {
    pub fn from_cli(cli: Cli) -> Self {
        let serve = match cli.command {
            Some(Commands::Serve(args)) => args,
            None => cli.serve,
        };

        let env_port = env::var("PORT")
            .ok()
            .and_then(|value| value.parse::<u16>().ok());
        let port = serve.port.or(env_port).unwrap_or(9327);

        let asset_mode = if serve.use_disk {
            AssetMode::Disk
        } else {
            serve.assets
        };

        Self {
            host: serve.host,
            port,
            asset_mode,
            static_dir: serve.static_dir,
            shutdown_timeout: Duration::from_secs(serve.shutdown_timeout_seconds),
        }
    }

    pub fn for_tests(asset_mode: AssetMode, static_dir: PathBuf) -> Self {
        Self {
            host: "127.0.0.1".to_string(),
            port: 9327,
            asset_mode,
            static_dir,
            shutdown_timeout: Duration::from_secs(1),
        }
    }
}

pub fn load() -> RuntimeConfig {
    let cli = Cli::parse();
    RuntimeConfig::from_cli(cli)
}
