use axum::http::{header, HeaderMap};
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct NotFoundJson {
    pub error: &'static str,
}

pub fn prefers_html(headers: &HeaderMap) -> bool {
    let accept = headers
        .get(header::ACCEPT)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .to_ascii_lowercase();

    accept.contains("text/html") || accept.contains("application/xhtml+xml")
}
