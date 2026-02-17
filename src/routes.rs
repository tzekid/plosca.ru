use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, Request, Response, StatusCode};
use axum::middleware::{self, Next};
use axum::routing::get;
use axum::{Json, Router};
use tower_http::trace::TraceLayer;

use crate::config::RuntimeConfig;
use crate::error_response::{prefers_html, NotFoundJson};
use crate::static_files::{AssetBackend, AssetPayload};

#[derive(Clone)]
pub struct AppState {
    assets: Arc<AssetBackend>,
}

pub async fn build(config: &RuntimeConfig) -> anyhow::Result<Router> {
    let assets = AssetBackend::new(config.asset_mode, config.static_dir.clone()).await?;
    let state = AppState {
        assets: Arc::new(assets),
    };

    let router = Router::new()
        .route("/stats", get(stats_get).head(stats_head))
        .route("/", get(static_root_get).head(static_root_head))
        .route("/{*path}", get(static_get).head(static_head))
        .layer(TraceLayer::new_for_http())
        .layer(middleware::from_fn(security_headers_middleware))
        .with_state(state);

    Ok(router)
}

async fn security_headers_middleware(req: Request<Body>, next: Next) -> Response<Body> {
    let mut response = next.run(req).await;
    response.headers_mut().insert(
        "x-content-type-options",
        "nosniff".parse().expect("static header value"),
    );
    response.headers_mut().insert(
        "referrer-policy",
        "no-referrer-when-downgrade"
            .parse()
            .expect("static header value"),
    );
    response
}

async fn stats_get() -> Response<Body> {
    stats_response(false)
}

async fn stats_head() -> Response<Body> {
    stats_response(true)
}

fn stats_response(head_only: bool) -> Response<Body> {
    let payload = crate::stats::collect();
    let json = serde_json::to_vec(&payload).expect("stats serialization should not fail");

    let builder = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::CACHE_CONTROL, "no-store")
        .header(header::CONTENT_LENGTH, json.len().to_string());

    if head_only {
        builder
            .body(Body::empty())
            .expect("response build should not fail")
    } else {
        builder
            .body(Body::from(json))
            .expect("response build should not fail")
    }
}

async fn static_get(
    Path(path): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Response<Body> {
    static_response(path, &state, &headers, false).await
}

async fn static_root_get(State(state): State<AppState>, headers: HeaderMap) -> Response<Body> {
    static_response(String::new(), &state, &headers, false).await
}

async fn static_root_head(State(state): State<AppState>, headers: HeaderMap) -> Response<Body> {
    static_response(String::new(), &state, &headers, true).await
}

async fn static_head(
    Path(path): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Response<Body> {
    static_response(path, &state, &headers, true).await
}

async fn static_response(
    path: String,
    state: &AppState,
    headers: &HeaderMap,
    head_only: bool,
) -> Response<Body> {
    let request_path = if path.is_empty() {
        "/".to_string()
    } else {
        format!("/{path}")
    };

    if let Some(asset) = state.assets.resolve_request_path(&request_path).await {
        return asset_response(StatusCode::OK, asset, head_only);
    }

    if prefers_html(headers) {
        if let Some(not_found) = state.assets.load_not_found_html().await {
            return asset_response(StatusCode::NOT_FOUND, not_found, head_only);
        }
    }

    json_not_found_response(head_only)
}

fn asset_response(status: StatusCode, payload: AssetPayload, head_only: bool) -> Response<Body> {
    let mut builder = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, payload.content_type)
        .header(header::CONTENT_LENGTH, payload.body.len().to_string());

    if let Some(cache_control) = payload.cache_control {
        builder = builder.header(header::CACHE_CONTROL, cache_control);
    }

    if head_only {
        builder
            .body(Body::empty())
            .expect("response build should not fail")
    } else {
        builder
            .body(Body::from(payload.body))
            .expect("response build should not fail")
    }
}

fn json_not_found_response(head_only: bool) -> Response<Body> {
    let payload = Json(NotFoundJson { error: "not_found" });
    let json = serde_json::to_vec(&payload.0).expect("json serialization should not fail");

    let builder = Response::builder()
        .status(StatusCode::NOT_FOUND)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::CONTENT_LENGTH, json.len().to_string());

    if head_only {
        builder
            .body(Body::empty())
            .expect("response build should not fail")
    } else {
        builder
            .body(Body::from(json))
            .expect("response build should not fail")
    }
}
