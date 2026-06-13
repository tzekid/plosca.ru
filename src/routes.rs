use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, Request, Response, StatusCode};
use axum::middleware::{self, Next};
use axum::routing::get;
use axum::Router;

use crate::config::RuntimeConfig;
use crate::metrics::AppMetrics;
use crate::static_files::{matches_if_none_match, AssetPayload, AssetStore};

#[derive(Clone)]
pub struct AppState {
    assets: AssetStore,
    metrics: AppMetrics,
    hsts_max_age: Option<u64>,
}

pub async fn build(config: &RuntimeConfig) -> anyhow::Result<Router> {
    let state = AppState {
        assets: AssetStore::new(),
        metrics: AppMetrics::new(),
        hsts_max_age: config.hsts_max_age,
    };

    let mut router = Router::new()
        .route("/healthz", get(health_get).head(health_head))
        .route("/readyz", get(ready_get).head(ready_head))
        .route("/", get(static_root_get).head(static_root_head))
        .route("/{*path}", get(static_get).head(static_head))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            security_headers_middleware,
        ));

    if config.metrics_enabled {
        router = router
            .route("/metrics", get(metrics_get).head(metrics_head))
            .layer(middleware::from_fn_with_state(
                state.clone(),
                request_metrics_middleware,
            ));
    }

    Ok(router.with_state(state))
}

async fn security_headers_middleware(
    State(state): State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response<Body> {
    let mut response = next.run(req).await;
    response.headers_mut().insert(
        "content-security-policy",
        "default-src 'self'; base-uri 'none'; font-src 'self'; img-src 'self' data:; script-src 'self' https://plausible.plosca.ru; style-src 'self'; connect-src 'self' https://plausible.plosca.ru; object-src 'none'; frame-ancestors 'none'; form-action 'self'; manifest-src 'self'; upgrade-insecure-requests"
            .parse()
            .expect("static header value"),
    );
    response.headers_mut().insert(
        "x-frame-options",
        "DENY".parse().expect("static header value"),
    );
    response.headers_mut().insert(
        "x-content-type-options",
        "nosniff".parse().expect("static header value"),
    );
    response.headers_mut().insert(
        "referrer-policy",
        "strict-origin-when-cross-origin"
            .parse()
            .expect("static header value"),
    );
    response.headers_mut().insert(
        "permissions-policy",
        "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
            .parse()
            .expect("static header value"),
    );
    response.headers_mut().insert(
        "cross-origin-resource-policy",
        "same-origin".parse().expect("static header value"),
    );
    if let Some(max_age) = state.hsts_max_age {
        response.headers_mut().insert(
            "strict-transport-security",
            format!("max-age={max_age}; includeSubDomains")
                .parse()
                .expect("valid hsts header"),
        );
    }
    response
}

async fn request_metrics_middleware(
    State(state): State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response<Body> {
    state.metrics.track_start();
    let started = std::time::Instant::now();
    let response = next.run(req).await;
    state
        .metrics
        .track_finish(response.status(), started.elapsed());
    response
}

async fn health_get() -> Response<Body> {
    text_response(StatusCode::OK, "ok", false, Some("no-store"))
}

async fn health_head() -> Response<Body> {
    text_response(StatusCode::OK, "ok", true, Some("no-store"))
}

async fn ready_get() -> Response<Body> {
    text_response(StatusCode::OK, "ready", false, Some("no-store"))
}

async fn ready_head() -> Response<Body> {
    text_response(StatusCode::OK, "ready", true, Some("no-store"))
}

async fn metrics_get(State(state): State<AppState>) -> Response<Body> {
    metrics_response(&state, false)
}

async fn metrics_head(State(state): State<AppState>) -> Response<Body> {
    metrics_response(&state, true)
}

fn metrics_response(state: &AppState, head_only: bool) -> Response<Body> {
    let body = state.metrics.render();
    response_with_owned_body(
        StatusCode::OK,
        head_only,
        body.into_bytes(),
        "text/plain; version=0.0.4; charset=utf-8",
        Some("no-store"),
        None,
        None,
    )
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
    let request_path = if path.is_empty() { "/" } else { &path };

    if let Some(asset) = state.assets.resolve_request_path(request_path, headers) {
        if matches_if_none_match(headers, asset.etag) {
            return not_modified_response(asset);
        }
        return asset_response(StatusCode::OK, asset, head_only);
    }

    if let Some(not_found) = state.assets.not_found(headers) {
        if matches_if_none_match(headers, not_found.etag) {
            return not_modified_response(not_found);
        }
        return asset_response(StatusCode::NOT_FOUND, not_found, head_only);
    }

    text_response(
        StatusCode::NOT_FOUND,
        "not found",
        head_only,
        Some("no-store"),
    )
}

fn asset_response(status: StatusCode, payload: AssetPayload, head_only: bool) -> Response<Body> {
    response_with_static_body(
        status,
        head_only,
        payload.body,
        payload.content_type,
        Some(payload.cache_control),
        Some(payload.etag),
        payload.content_encoding,
    )
}

fn not_modified_response(payload: AssetPayload) -> Response<Body> {
    let mut builder = Response::builder()
        .status(StatusCode::NOT_MODIFIED)
        .header(header::ETAG, payload.etag)
        .header(header::CACHE_CONTROL, payload.cache_control)
        .header(header::VARY, "Accept-Encoding");

    if let Some(content_encoding) = payload.content_encoding {
        builder = builder.header(header::CONTENT_ENCODING, content_encoding);
    }

    builder
        .body(Body::empty())
        .expect("response build should not fail")
}

fn text_response(
    status: StatusCode,
    body: &'static str,
    head_only: bool,
    cache_control: Option<&'static str>,
) -> Response<Body> {
    response_with_static_body(
        status,
        head_only,
        body.as_bytes(),
        "text/plain; charset=utf-8",
        cache_control,
        None,
        None,
    )
}

fn response_with_static_body(
    status: StatusCode,
    head_only: bool,
    body: &'static [u8],
    content_type: &str,
    cache_control: Option<&str>,
    etag: Option<&str>,
    content_encoding: Option<&str>,
) -> Response<Body> {
    build_response(
        status,
        head_only,
        body.len(),
        content_type,
        cache_control,
        etag,
        content_encoding,
    )
    .body(if head_only {
        Body::empty()
    } else {
        Body::from(body)
    })
    .expect("response build should not fail")
}

fn response_with_owned_body(
    status: StatusCode,
    head_only: bool,
    body: Vec<u8>,
    content_type: &str,
    cache_control: Option<&str>,
    etag: Option<&str>,
    content_encoding: Option<&str>,
) -> Response<Body> {
    build_response(
        status,
        head_only,
        body.len(),
        content_type,
        cache_control,
        etag,
        content_encoding,
    )
    .body(if head_only {
        Body::empty()
    } else {
        Body::from(body)
    })
    .expect("response build should not fail")
}

fn build_response(
    status: StatusCode,
    _head_only: bool,
    body_len: usize,
    content_type: &str,
    cache_control: Option<&str>,
    etag: Option<&str>,
    content_encoding: Option<&str>,
) -> axum::http::response::Builder {
    let mut builder = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_LENGTH, body_len.to_string());

    if let Some(cache_control) = cache_control {
        builder = builder.header(header::CACHE_CONTROL, cache_control);
    }
    if let Some(etag) = etag {
        builder = builder.header(header::ETAG, etag);
    }
    if content_encoding.is_some() {
        builder = builder.header(header::VARY, "Accept-Encoding");
    }
    if let Some(content_encoding) = content_encoding {
        builder = builder.header(header::CONTENT_ENCODING, content_encoding);
    }
    builder
}
