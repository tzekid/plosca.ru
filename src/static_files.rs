use std::cmp::Ordering;
use std::path::{Component, Path};

use axum::http::{header, HeaderMap};

mod generated {
    include!(env!("ASSET_MANIFEST_RS"));
}

#[derive(Debug, Clone)]
pub struct AssetPayload {
    pub body: &'static [u8],
    pub content_type: &'static str,
    pub cache_control: &'static str,
    pub etag: &'static str,
    pub content_encoding: Option<&'static str>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct AssetStore;

impl AssetStore {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve_request_path(
        &self,
        request_path: &str,
        headers: &HeaderMap,
    ) -> Option<AssetPayload> {
        let normalized = normalize_request_path(request_path)?;
        let preference = preferred_encoding(headers);

        if let Some(asset) = find_asset(&normalized) {
            return Some(select_variant(asset, preference));
        }

        let basename = normalized.rsplit('/').next().unwrap_or(&normalized);
        if !basename.contains('.') {
            let html_candidate = format!("{normalized}.html");
            if let Some(asset) = find_asset(&html_candidate) {
                return Some(select_variant(asset, preference));
            }

            let index_candidate = format!("{normalized}/index.html");
            if let Some(asset) = find_asset(&index_candidate) {
                return Some(select_variant(asset, preference));
            }
        }

        None
    }

    pub fn not_found(&self, headers: &HeaderMap) -> Option<AssetPayload> {
        let asset = find_asset("404.html")?;
        Some(select_variant(asset, preferred_encoding(headers)))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum EncodingPreference {
    Br,
    Gzip,
    Identity,
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
                components.pop()?;
            }
            Component::RootDir | Component::Prefix(_) => {}
        }
    }

    Some(components.join("/"))
}

pub fn matches_if_none_match(headers: &HeaderMap, etag: &str) -> bool {
    headers
        .get(header::IF_NONE_MATCH)
        .and_then(|value| value.to_str().ok())
        .map(|value| {
            value
                .split(',')
                .map(str::trim)
                .any(|candidate| candidate == "*" || candidate == etag)
        })
        .unwrap_or(false)
}

fn find_asset(path: &str) -> Option<&'static generated::GeneratedAsset> {
    generated::ASSETS
        .binary_search_by_key(&path, |asset| asset.path)
        .ok()
        .map(|index| &generated::ASSETS[index])
}

fn select_variant(
    asset: &'static generated::GeneratedAsset,
    preference: EncodingPreference,
) -> AssetPayload {
    let variant = match preference {
        EncodingPreference::Br => asset
            .br
            .as_ref()
            .or(asset.gzip.as_ref())
            .unwrap_or(&asset.raw),
        EncodingPreference::Gzip => asset
            .gzip
            .as_ref()
            .or(asset.br.as_ref())
            .unwrap_or(&asset.raw),
        EncodingPreference::Identity => &asset.raw,
    };

    AssetPayload {
        body: variant.body,
        content_type: asset.content_type,
        cache_control: asset.cache_control,
        etag: variant.etag,
        content_encoding: variant.content_encoding,
    }
}

fn preferred_encoding(headers: &HeaderMap) -> EncodingPreference {
    let Some(raw) = headers
        .get(header::ACCEPT_ENCODING)
        .and_then(|value| value.to_str().ok())
    else {
        return EncodingPreference::Identity;
    };

    let mut br = 0.0_f32;
    let mut gzip = 0.0_f32;
    let mut identity = 1.0_f32;
    let mut wildcard = None::<f32>;

    for item in raw
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
    {
        let mut parts = item.split(';').map(str::trim);
        let coding = parts.next().unwrap_or_default();
        let mut quality = 1.0_f32;

        for part in parts {
            if let Some(value) = part.strip_prefix("q=") {
                quality = value.parse::<f32>().unwrap_or(0.0);
            }
        }

        match coding {
            "br" => br = quality,
            "gzip" => gzip = quality,
            "identity" => identity = quality,
            "*" => wildcard = Some(quality),
            _ => {}
        }
    }

    if br == 0.0 {
        br = wildcard.unwrap_or(0.0);
    }
    if gzip == 0.0 {
        gzip = wildcard.unwrap_or(0.0);
    }

    let mut choices = [
        (EncodingPreference::Br, br),
        (EncodingPreference::Gzip, gzip),
        (EncodingPreference::Identity, identity),
    ];
    choices.sort_by(|left, right| compare_quality(*left, *right));
    choices[0].0
}

fn compare_quality(left: (EncodingPreference, f32), right: (EncodingPreference, f32)) -> Ordering {
    right
        .1
        .partial_cmp(&left.1)
        .unwrap_or(Ordering::Equal)
        .then_with(|| priority(right.0).cmp(&priority(left.0)))
}

fn priority(encoding: EncodingPreference) -> u8 {
    match encoding {
        EncodingPreference::Br => 3,
        EncodingPreference::Gzip => 2,
        EncodingPreference::Identity => 1,
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

    #[test]
    fn prefer_brotli_over_gzip() {
        let mut headers = HeaderMap::new();
        headers.insert(header::ACCEPT_ENCODING, "gzip, br".parse().unwrap());
        assert_eq!(preferred_encoding(&headers), EncodingPreference::Br);
    }

    #[test]
    fn if_none_match_matches_exact_etag() {
        let mut headers = HeaderMap::new();
        headers.insert(header::IF_NONE_MATCH, "\"abc\", \"def\"".parse().unwrap());
        assert!(matches_if_none_match(&headers, "\"def\""));
    }
}
