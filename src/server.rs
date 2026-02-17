use tokio::net::TcpListener;
use tokio::sync::oneshot;
use tracing::{error, info};

use crate::config::RuntimeConfig;

pub async fn run(config: RuntimeConfig) -> anyhow::Result<()> {
    let app = crate::routes::build(&config).await?;
    let addr = format!("{}:{}", config.host, config.port);
    let listener = TcpListener::bind(&addr).await?;

    info!(
        address = %addr,
        asset_mode = ?config.asset_mode,
        static_dir = %config.static_dir.display(),
        shutdown_timeout_seconds = config.shutdown_timeout.as_secs(),
        "starting webapp"
    );

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let server = axum::serve(listener, app).with_graceful_shutdown(async move {
        let _ = shutdown_rx.await;
    });

    let mut server_task = tokio::spawn(async move { server.await });

    tokio::select! {
        server_result = &mut server_task => {
            return server_result
                .map_err(anyhow::Error::from)?
                .map_err(anyhow::Error::from);
        }
        _ = wait_for_shutdown_signal() => {}
    }

    info!(
        shutdown_timeout_seconds = config.shutdown_timeout.as_secs(),
        "shutdown signal received"
    );

    let _ = shutdown_tx.send(());

    match tokio::time::timeout(config.shutdown_timeout, server_task).await {
        Ok(joined) => joined
            .map_err(anyhow::Error::from)?
            .map_err(anyhow::Error::from),
        Err(_) => Err(anyhow::anyhow!(
            "graceful shutdown timed out after {}s",
            config.shutdown_timeout.as_secs()
        )),
    }
}

async fn wait_for_shutdown_signal() {
    let ctrl_c = async {
        if let Err(err) = tokio::signal::ctrl_c().await {
            error!(error = %err, "failed to install Ctrl+C signal handler");
        }
    };

    #[cfg(unix)]
    let terminate = async {
        let mut signal = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("installing SIGTERM handler should succeed");
        signal.recv().await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
