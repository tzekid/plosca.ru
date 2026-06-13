use axum::body::{to_bytes, Body};
use http::{header, Request, StatusCode};
use tower::ServiceExt;

use ploscaru::config::RuntimeConfig;

async fn app() -> axum::Router {
    let cfg = RuntimeConfig::for_tests();
    ploscaru::routes::build(&cfg)
        .await
        .expect("app should build")
}

async fn app_without_metrics() -> axum::Router {
    let mut cfg = RuntimeConfig::for_tests();
    cfg.metrics_enabled = false;
    ploscaru::routes::build(&cfg)
        .await
        .expect("app should build")
}

#[tokio::test]
async fn health_and_ready_routes_work() {
    let app = app().await;

    for path in ["/healthz", "/readyz"] {
        let req = Request::builder()
            .method("GET")
            .uri(path)
            .body(Body::empty())
            .expect("request should build");

        let resp = app
            .clone()
            .oneshot(req)
            .await
            .expect("response should be available");
        assert_eq!(resp.status(), StatusCode::OK);
    }
}

#[tokio::test]
async fn head_response_has_no_body() {
    let app = app().await;
    let req = Request::builder()
        .method("HEAD")
        .uri("/healthz")
        .body(Body::empty())
        .expect("request should build");

    let resp = app
        .oneshot(req)
        .await
        .expect("response should be available");
    assert_eq!(resp.status(), StatusCode::OK);

    let body = to_bytes(resp.into_body(), usize::MAX)
        .await
        .expect("body should read");
    assert!(body.is_empty(), "head response body should be empty");
}

#[tokio::test]
async fn static_routes_still_work() {
    let app = app().await;

    for (path, expected) in [
        ("/", StatusCode::OK),
        ("/about", StatusCode::OK),
        ("/does-not-exist", StatusCode::NOT_FOUND),
    ] {
        let req = Request::builder()
            .method("GET")
            .uri(path)
            .body(Body::empty())
            .expect("request should build");
        let resp = app
            .clone()
            .oneshot(req)
            .await
            .expect("response should be available");
        assert_eq!(resp.status(), expected, "unexpected status for {path}");
    }
}

#[tokio::test]
async fn missing_page_returns_html_404() {
    let app = app().await;
    let req = Request::builder()
        .method("GET")
        .uri("/missing-page")
        .body(Body::empty())
        .expect("request should build");
    let resp = app
        .oneshot(req)
        .await
        .expect("response should be available");
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    let content_type = resp
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    assert!(
        content_type.starts_with("text/html"),
        "expected html content type, got {content_type}"
    );
}

#[tokio::test]
async fn etag_works_with_conditional_gets() {
    let app = app().await;
    let first_resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/about")
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");
    let etag = first_resp
        .headers()
        .get(header::ETAG)
        .and_then(|value| value.to_str().ok())
        .expect("etag should exist")
        .to_string();

    let second_resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/about")
                .header(header::IF_NONE_MATCH, etag)
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");
    assert_eq!(second_resp.status(), StatusCode::NOT_MODIFIED);
}

#[tokio::test]
async fn accepts_compressed_assets() {
    let app = app().await;
    let root = fetch_text(&app, "/").await;
    let stylesheet = extract_stylesheet_path(&root);
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&stylesheet)
                .header(header::ACCEPT_ENCODING, "br, gzip")
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");

    assert_eq!(resp.status(), StatusCode::OK);
    let content_encoding = resp
        .headers()
        .get(header::CONTENT_ENCODING)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    assert_eq!(content_encoding, "br");
}

#[tokio::test]
async fn unsupported_method_returns_405() {
    let app = app().await;
    let req = Request::builder()
        .method("POST")
        .uri("/about")
        .body(Body::empty())
        .expect("request should build");

    let resp = app
        .oneshot(req)
        .await
        .expect("response should be available");
    assert_eq!(resp.status(), StatusCode::METHOD_NOT_ALLOWED);
}

#[tokio::test]
async fn security_headers_are_present() {
    let app = app().await;
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/")
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");

    for header_name in [
        "content-security-policy",
        "x-frame-options",
        "x-content-type-options",
        "permissions-policy",
        "cross-origin-resource-policy",
    ] {
        assert!(
            resp.headers().contains_key(header_name),
            "missing header {header_name}"
        );
    }
}

#[tokio::test]
async fn metrics_endpoint_exposes_prometheus_text() {
    let app = app().await;
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/metrics")
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");
    assert_eq!(resp.status(), StatusCode::OK);

    let body = to_bytes(resp.into_body(), usize::MAX)
        .await
        .expect("body should read");
    let body = String::from_utf8(body.to_vec()).expect("metrics should be utf8");
    assert!(body.contains("http_requests_total"));
    assert!(body.contains("process_resident_memory_bytes"));
}

#[tokio::test]
async fn metrics_endpoint_is_disabled_by_default() {
    let app = app_without_metrics().await;
    let resp = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/metrics")
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn home_page_uses_hashed_assets_and_has_no_inline_payloads() {
    let app = app().await;
    let body = fetch_text(&app, "/").await;
    assert!(body.contains("rel=\"stylesheet\""));
    assert!(body.contains("/assets/style."));
    assert!(!body.contains("<style"));
    assert!(!body.contains("plausible"));
    assert!(!body.contains("rel=\"preload\""));
}

async fn fetch_text(app: &axum::Router, path: &str) -> String {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(path)
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("response should be available");
    let body = to_bytes(resp.into_body(), usize::MAX)
        .await
        .expect("body should read");
    String::from_utf8(body.to_vec()).expect("body should be utf8")
}

fn extract_stylesheet_path(html: &str) -> String {
    let marker = "rel=\"stylesheet\" href=\"";
    let start = html.find(marker).expect("stylesheet link should exist") + marker.len();
    let remaining = &html[start..];
    let end = remaining
        .find('"')
        .expect("stylesheet href should terminate");
    remaining[..end].to_string()
}
