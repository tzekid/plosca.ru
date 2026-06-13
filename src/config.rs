use std::env;
use std::time::Duration;

use clap::{Parser, Subcommand};

#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub host: String,
    pub port: u16,
    pub shutdown_timeout: Duration,
    pub hsts_max_age: Option<u64>,
    pub metrics_enabled: bool,
}

#[derive(Debug, Clone, Parser)]
#[command(name = "webapp", version, about = "plosca.ru axum server")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
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

    #[arg(long, default_value_t = 5)]
    pub shutdown_timeout_seconds: u64,

    #[arg(long)]
    pub hsts_max_age: Option<u64>,

    #[arg(long, default_value_t = false)]
    pub enable_metrics: bool,
}

impl RuntimeConfig {
    pub fn from_cli(cli: Cli) -> Self {
        let Commands::Serve(serve) = cli.command;

        let env_port = env::var("PORT")
            .ok()
            .and_then(|value| value.parse::<u16>().ok());
        let port = serve.port.or(env_port).unwrap_or(9327);

        Self {
            host: serve.host,
            port,
            shutdown_timeout: Duration::from_secs(serve.shutdown_timeout_seconds),
            hsts_max_age: serve.hsts_max_age,
            metrics_enabled: serve.enable_metrics,
        }
    }

    pub fn for_tests() -> Self {
        Self {
            host: "127.0.0.1".to_string(),
            port: 9327,
            shutdown_timeout: Duration::from_secs(1),
            hsts_max_age: None,
            metrics_enabled: true,
        }
    }
}

pub fn load() -> RuntimeConfig {
    let cli = Cli::parse();
    RuntimeConfig::from_cli(cli)
}
