use std::path::PathBuf;

use axum::body::{to_bytes, Body};
use http::{header, Request, StatusCode};
use regex::Regex;
use tower::ServiceExt;

use ploscaru::config::{AssetMode, RuntimeConfig};

fn static_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("static_old")
}

async fn app(mode: AssetMode) -> axum::Router {
    let cfg = RuntimeConfig::for_tests(mode, static_dir());
    ploscaru::routes::build(&cfg)
        .await
        .expect("app should build")
}

#[tokio::test]
async fn stats_get_embed_and_disk() {
    let re = Regex::new(r"^\d+(\.\d{2}) MB$").expect("regex should compile");

    for mode in [AssetMode::Embedded, AssetMode::Disk] {
        let app = app(mode).await;
        let req = Request::builder()
            .method("GET")
            .uri("/stats")
            .body(Body::empty())
            .expect("request should build");

        let resp = app
            .oneshot(req)
            .await
            .expect("response should be available");
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers()
                .get(header::CACHE_CONTROL)
                .and_then(|v| v.to_str().ok()),
            Some("no-store")
        );

        let body = to_bytes(resp.into_body(), usize::MAX)
            .await
            .expect("body should read");
        let json: serde_json::Value =
            serde_json::from_slice(&body).expect("json parse should work");

        assert_eq!(json["runtime"], "rust/axum");
        assert!(
            re.is_match(
                json["memory"]["rss"]
                    .as_str()
                    .expect("rss should be string")
            ),
            "rss format mismatch: {}",
            json["memory"]["rss"]
        );
        assert!(
            re.is_match(
                json["memory"]["heap_used"]
                    .as_str()
                    .expect("heap_used should be string")
            ),
            "heap_used format mismatch: {}",
            json["memory"]["heap_used"]
        );
        assert!(
            re.is_match(
                json["memory"]["heap_total"]
                    .as_str()
                    .expect("heap_total should be string")
            ),
            "heap_total format mismatch: {}",
            json["memory"]["heap_total"]
        );
    }
}

#[tokio::test]
async fn stats_head_returns_empty_body() {
    let app = app(AssetMode::Embedded).await;
    let req = Request::builder()
        .method("HEAD")
        .uri("/stats")
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
    let app = app(AssetMode::Embedded).await;

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
async fn disk_mode_static_routes_work() {
    let app = app(AssetMode::Disk).await;
    let req = Request::builder()
        .method("GET")
        .uri("/about")
        .body(Body::empty())
        .expect("request should build");
    let resp = app
        .oneshot(req)
        .await
        .expect("response should be available");
    assert_eq!(resp.status(), StatusCode::OK);
}

#[tokio::test]
async fn not_found_accept_html_uses_html_page() {
    let app = app(AssetMode::Embedded).await;
    let req = Request::builder()
        .method("GET")
        .uri("/missing-page")
        .header(header::ACCEPT, "text/html")
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
async fn not_found_accept_json_returns_json() {
    let app = app(AssetMode::Embedded).await;

    for accept in ["application/json", "*/*"] {
        let req = Request::builder()
            .method("GET")
            .uri("/missing-page")
            .header(header::ACCEPT, accept)
            .body(Body::empty())
            .expect("request should build");

        let resp = app
            .clone()
            .oneshot(req)
            .await
            .expect("response should be available");
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);

        let body = to_bytes(resp.into_body(), usize::MAX)
            .await
            .expect("body should read");
        let json: serde_json::Value =
            serde_json::from_slice(&body).expect("json parse should work");
        assert_eq!(json["error"], "not_found");
    }
}

#[tokio::test]
async fn unsupported_method_returns_405() {
    let app = app(AssetMode::Embedded).await;
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
