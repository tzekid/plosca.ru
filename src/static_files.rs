use std::ffi::OsStr;
use std::path::{Component, Path, PathBuf};

use anyhow::Context;
use bytes::Bytes;
use include_dir::{include_dir, Dir};
use mime_guess::MimeGuess;
use tokio::fs;
use tracing::warn;

use crate::config::AssetMode;

static EMBEDDED_STATIC: Dir<'static> = include_dir!("$CARGO_MANIFEST_DIR/static_old");

#[derive(Debug, Clone)]
pub enum AssetBackend {
    Embedded,
    Disk {
        root: PathBuf,
        canonical_root: Option<PathBuf>,
    },
}

#[derive(Debug, Clone)]
pub struct AssetPayload {
    pub body: Bytes,
    pub content_type: String,
    pub cache_control: Option<String>,
}

impl AssetBackend {
    pub async fn new(mode: AssetMode, static_dir: PathBuf) -> anyhow::Result<Self> {
        match mode {
            AssetMode::Embedded => Ok(Self::Embedded),
            AssetMode::Disk => {
                let canonical_root = match fs::canonicalize(&static_dir).await {
                    Ok(path) => Some(path),
                    Err(err) => {
                        warn!(
                            static_dir = %static_dir.display(),
                            error = %err,
                            "static directory is not available; disk mode will return 404"
                        );
                        None
                    }
                };
                Ok(Self::Disk {
                    root: static_dir,
                    canonical_root,
                })
            }
        }
    }

    pub async fn resolve_request_path(&self, request_path: &str) -> Option<AssetPayload> {
        let normalized = normalize_request_path(request_path)?;
        for candidate in candidate_paths(&normalized) {
            if let Some(asset) = self.load_candidate(&candidate).await {
                return Some(asset);
            }
        }
        None
    }

    pub async fn load_not_found_html(&self) -> Option<AssetPayload> {
        self.load_candidate("404.html").await
    }

    async fn load_candidate(&self, rel_path: &str) -> Option<AssetPayload> {
        let rel_path = sanitize_relative_path(rel_path)?;

        match self {
            AssetBackend::Embedded => {
                let file = EMBEDDED_STATIC.get_file(&rel_path)?;
                let body = Bytes::copy_from_slice(file.contents());
                Some(AssetPayload {
                    content_type: content_type_for(&rel_path),
                    cache_control: cache_control_for(&rel_path).map(ToString::to_string),
                    body,
                })
            }
            AssetBackend::Disk {
                root,
                canonical_root,
            } => {
                let canonical_root = canonical_root.as_ref()?;
                let candidate = root.join(Path::new(&rel_path));

                let metadata = fs::metadata(&candidate).await.ok()?;
                if !metadata.is_file() {
                    return None;
                }

                let canonical_target = fs::canonicalize(&candidate).await.ok()?;
                if !canonical_target.starts_with(canonical_root) {
                    warn!(
                        candidate = %candidate.display(),
                        resolved = %canonical_target.display(),
                        "blocked candidate outside static root"
                    );
                    return None;
                }

                let body = fs::read(&canonical_target)
                    .await
                    .with_context(|| format!("failed reading {}", canonical_target.display()))
                    .ok()?;

                Some(AssetPayload {
                    content_type: content_type_for(&rel_path),
                    cache_control: cache_control_for(&rel_path).map(ToString::to_string),
                    body: Bytes::from(body),
                })
            }
        }
    }
}

pub fn normalize_request_path(request_path: &str) -> Option<String> {
    let trimmed = request_path.trim();
    if trimmed.is_empty() || trimmed == "/" {
        return Some("index.html".to_string());
    }

    let stripped = trimmed.trim_start_matches('/');
    let cleaned = sanitize_relative_path(stripped)?;

    if cleaned.is_empty() {
        Some("index.html".to_string())
    } else {
        Some(cleaned)
    }
}

pub fn candidate_paths(normalized_path: &str) -> Vec<String> {
    let mut out = vec![normalized_path.to_string()];
    let basename = normalized_path
        .rsplit('/')
        .next()
        .unwrap_or(normalized_path);

    if !basename.contains('.') {
        out.push(format!("{normalized_path}.html"));
        out.push(format!("{normalized_path}/index.html"));
    }

    out
}

fn sanitize_relative_path(raw: &str) -> Option<String> {
    let mut components = Vec::<String>::new();

    for component in Path::new(raw).components() {
        match component {
            Component::Normal(value) => {
                let part = value.to_string_lossy();
                if part.is_empty() {
                    continue;
                }
                components.push(part.into_owned());
            }
            Component::CurDir => {}
            Component::ParentDir => {
                if components.pop().is_none() {
                    return None;
                }
            }
            Component::RootDir | Component::Prefix(_) => {}
        }
    }

    Some(components.join("/"))
}

fn content_type_for(path: &str) -> String {
    let guess = MimeGuess::from_path(path).first_or_octet_stream();
    guess.essence_str().to_string()
}

fn cache_control_for(path: &str) -> Option<&'static str> {
    let ext = Path::new(path)
        .extension()
        .and_then(OsStr::to_str)
        .map(|v| v.to_ascii_lowercase());

    match ext.as_deref() {
        Some("woff") | Some("woff2") | Some("png") | Some("jpg") | Some("jpeg") | Some("gif")
        | Some("svg") | Some("webp") => Some("public, max-age=31536000, immutable"),
        Some("css") => Some("public, max-age=31536000, immutable"),
        Some("js") => Some("public, max-age=86400"),
        Some("html") => Some("public, max-age=0, must-revalidate, stale-while-revalidate=30"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_root_to_index() {
        assert_eq!(normalize_request_path("/"), Some("index.html".to_string()));
    }

    #[test]
    fn normalize_extensionless_path() {
        assert_eq!(normalize_request_path("/about"), Some("about".to_string()));
    }

    #[test]
    fn normalize_rejects_parent_escape() {
        assert_eq!(normalize_request_path("../../etc/passwd"), None);
    }

    #[test]
    fn candidate_chain_for_extensionless() {
        let got = candidate_paths("about");
        assert_eq!(got, vec!["about", "about.html", "about/index.html"]);
    }

    #[test]
    fn candidate_chain_for_file_with_extension() {
        let got = candidate_paths("style.css");
        assert_eq!(got, vec!["style.css"]);
    }
}
