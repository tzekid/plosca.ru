use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use brotli::CompressorWriter;
use flate2::write::GzEncoder;
use flate2::Compression;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

const STATIC_DIR: &str = "static";

fn main() {
    println!("cargo:rerun-if-changed={STATIC_DIR}");

    let manifest_dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let static_dir = manifest_dir.join(STATIC_DIR);
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));
    let generated_dir = out_dir.join("generated_assets");

    fs::create_dir_all(&generated_dir).expect("generated asset dir");

    let sources = collect_sources(&static_dir);
    let route_map = build_route_map(&sources);
    let mut assets = build_assets(&sources, &route_map, &generated_dir);
    assets.sort_by(|left, right| left.request_path.cmp(&right.request_path));

    let mut output = String::new();
    output.push_str("pub struct AssetVariant {\n");
    output.push_str("    pub body: &'static [u8],\n");
    output.push_str("    pub etag: &'static str,\n");
    output.push_str("    pub content_encoding: Option<&'static str>,\n");
    output.push_str("}\n\n");
    output.push_str("pub struct GeneratedAsset {\n");
    output.push_str("    pub path: &'static str,\n");
    output.push_str("    pub content_type: &'static str,\n");
    output.push_str("    pub cache_control: &'static str,\n");
    output.push_str("    pub raw: AssetVariant,\n");
    output.push_str("    pub gzip: Option<AssetVariant>,\n");
    output.push_str("    pub br: Option<AssetVariant>,\n");
    output.push_str("}\n\n");
    output.push_str("pub static ASSETS: &[GeneratedAsset] = &[\n");

    for asset in &assets {
        let gzip_include = asset
            .gzip_path
            .as_ref()
            .map(|path| variant_include(path, &asset.gzip_etag, Some("gzip")))
            .unwrap_or_else(|| "None".to_string());
        let br_include = asset
            .br_path
            .as_ref()
            .map(|path| variant_include(path, &asset.br_etag, Some("br")))
            .unwrap_or_else(|| "None".to_string());

        let _ = writeln!(
            output,
            "    GeneratedAsset {{\n        path: {:?},\n        content_type: {:?},\n        cache_control: {:?},\n        raw: AssetVariant {{\n            body: include_bytes!({:?}),\n            etag: {:?},\n            content_encoding: None,\n        }},\n        gzip: {},\n        br: {},\n    }},",
            asset.request_path,
            asset.content_type,
            asset.cache_control,
            asset.body_path.to_string_lossy(),
            asset.raw_etag,
            gzip_include,
            br_include,
        );
    }

    output.push_str("];\n");
    fs::write(out_dir.join("asset_manifest.rs"), output).expect("write asset manifest");
    println!(
        "cargo:rustc-env=ASSET_MANIFEST_RS={}",
        out_dir.join("asset_manifest.rs").display()
    );
}

fn collect_sources(static_dir: &Path) -> Vec<SourceAsset> {
    let mut sources = WalkDir::new(static_dir)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter_map(|entry| {
            let path = entry.into_path();
            let relative_path = path
                .strip_prefix(static_dir)
                .ok()?
                .to_string_lossy()
                .replace('\\', "/");

            let kind = classify_asset(&relative_path)?;
            let body = fs::read(&path).expect("read source asset");

            Some(SourceAsset {
                relative_path,
                kind,
                body,
            })
        })
        .collect::<Vec<_>>();

    sources.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    sources
}

fn build_route_map(sources: &[SourceAsset]) -> BTreeMap<String, String> {
    let mut route_map = BTreeMap::new();

    for source in sources {
        match source.kind {
            AssetKind::Html | AssetKind::Stable => {
                route_map.insert(source.relative_path.clone(), source.relative_path.clone());
            }
            AssetKind::HashedBinary => {
                route_map.insert(
                    source.relative_path.clone(),
                    hashed_request_path(&source.relative_path, &source.body),
                );
            }
            AssetKind::Css | AssetKind::Manifest => {}
        }
    }

    for source in sources {
        if matches!(source.kind, AssetKind::Css) {
            let transformed = transform_css(&String::from_utf8_lossy(&source.body), &route_map);
            route_map.insert(
                source.relative_path.clone(),
                hashed_request_path(&source.relative_path, transformed.as_bytes()),
            );
        }
    }

    for source in sources {
        if matches!(source.kind, AssetKind::Manifest) {
            let transformed =
                transform_manifest(&String::from_utf8_lossy(&source.body), &route_map);
            route_map.insert(
                source.relative_path.clone(),
                hashed_request_path(&source.relative_path, transformed.as_bytes()),
            );
        }
    }

    route_map
}

fn build_assets(
    sources: &[SourceAsset],
    route_map: &BTreeMap<String, String>,
    generated_dir: &Path,
) -> Vec<AssetBuildRecord> {
    let mut assets = Vec::new();

    for source in sources {
        let request_path = route_map
            .get(&source.relative_path)
            .expect("route should exist")
            .clone();

        let body = match source.kind {
            AssetKind::Html => {
                transform_html(&String::from_utf8_lossy(&source.body), route_map).into_bytes()
            }
            AssetKind::Css => {
                transform_css(&String::from_utf8_lossy(&source.body), route_map).into_bytes()
            }
            AssetKind::Manifest => {
                transform_manifest(&String::from_utf8_lossy(&source.body), route_map).into_bytes()
            }
            AssetKind::Stable | AssetKind::HashedBinary => source.body.clone(),
        };

        let body_path = generated_dir.join(sanitized_output_name(&request_path));
        fs::write(&body_path, &body).expect("write generated asset");

        let cache_control = cache_control_for(&request_path, source.kind.is_hashed());
        let content_type = content_type_for(&request_path);
        let raw_etag = etag_for(&body);

        let (gzip_path, gzip_etag, br_path, br_etag) =
            if should_compress(&request_path, &content_type, body.len()) {
                let gzip_body = gzip_compress(&body);
                let gzip_path =
                    generated_dir.join(format!("{}.gz", sanitized_output_name(&request_path)));
                fs::write(&gzip_path, &gzip_body).expect("write gzip asset");

                let br_body = brotli_compress(&body);
                let br_path =
                    generated_dir.join(format!("{}.br", sanitized_output_name(&request_path)));
                fs::write(&br_path, &br_body).expect("write br asset");

                (
                    Some(gzip_path),
                    Some(etag_for(&gzip_body)),
                    Some(br_path),
                    Some(etag_for(&br_body)),
                )
            } else {
                (None, None, None, None)
            };

        assets.push(AssetBuildRecord {
            request_path,
            body_path,
            content_type,
            cache_control,
            raw_etag,
            gzip_path,
            gzip_etag,
            br_path,
            br_etag,
        });
    }

    assets
}

fn classify_asset(relative_path: &str) -> Option<AssetKind> {
    if relative_path.starts_with('.')
        || relative_path.ends_with(".fiber.gz")
        || relative_path == "style.20250817.min.css"
        || relative_path == "pandoc.css"
    {
        return None;
    }

    let extension = Path::new(relative_path)
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.to_ascii_lowercase());

    match extension.as_deref() {
        Some("html") => Some(AssetKind::Html),
        Some("css") => Some(AssetKind::Css),
        Some("webmanifest") => Some(AssetKind::Manifest),
        Some("pdf") | Some("txt") | Some("xml") => Some(AssetKind::Stable),
        Some("png")
        | Some("jpg")
        | Some("jpeg")
        | Some("gif")
        | Some("svg")
        | Some("webp")
        | Some("ico")
        | Some("woff")
        | Some("woff2") => Some(AssetKind::HashedBinary),
        _ => Some(AssetKind::Stable),
    }
}

fn hashed_request_path(relative_path: &str, body: &[u8]) -> String {
    let path = Path::new(relative_path);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("asset");
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("bin");
    let stem = stem
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>();
    let digest = Sha256::digest(body);
    let hash = digest[..8].iter().fold(String::new(), |mut out, byte| {
        let _ = write!(out, "{byte:02x}");
        out
    });
    format!("assets/{stem}.{hash}.{ext}")
}

fn transform_html(source: &str, route_map: &BTreeMap<String, String>) -> String {
    let mut html = source.replace(
        r#"<meta http-equiv="X-UA-Compatible" content="ie=edge" />"#,
        "",
    );

    html = remove_tag_blocks(&html, "style", |_| true);
    html = remove_tag_blocks(&html, "script", |chunk| !script_start_tag_has_src(chunk));
    html = remove_void_tags(&html, "link", |chunk| {
        chunk.contains(r#"rel="preload""#) && !chunk.contains(r#"as="font""#)
    });
    html = remove_html_comments(&html);
    let html = strip_inline_style_attributes(&html);
    rewrite_root_references(&html, route_map)
}

fn transform_manifest(source: &str, route_map: &BTreeMap<String, String>) -> String {
    rewrite_root_references(source, route_map)
}

fn transform_css(source: &str, route_map: &BTreeMap<String, String>) -> String {
    let without_comments = strip_css_comments(source);
    rewrite_css_references(&without_comments, route_map)
}

fn rewrite_root_references(source: &str, route_map: &BTreeMap<String, String>) -> String {
    let mut out = source.to_string();
    for (old, new) in route_map {
        if old == new {
            continue;
        }
        out = out.replace(&format!("/{old}"), &format!("/{new}"));
    }
    out
}

fn rewrite_css_references(source: &str, route_map: &BTreeMap<String, String>) -> String {
    let mut css = source.to_string();

    for (old, new) in route_map {
        if old == new {
            continue;
        }
        for from in [
            format!("url(./{old})"),
            format!("url(\"./{old}\")"),
            format!("url('./{old}')"),
            format!("url({old})"),
            format!("url(\"{old}\")"),
            format!("url('{old}')"),
        ] {
            css = css.replace(&from, &format!("url(\"/{new}\")"));
        }
    }

    css
}

fn remove_tag_blocks(source: &str, tag: &str, predicate: impl Fn(&str) -> bool) -> String {
    let start_marker = format!("<{tag}");
    let end_marker = format!("</{tag}>");
    let mut out = String::new();
    let mut cursor = 0;

    while let Some(relative_start) = source[cursor..].find(&start_marker) {
        let start = cursor + relative_start;
        out.push_str(&source[cursor..start]);

        let remaining = &source[start..];
        let Some(relative_end) = remaining.find(&end_marker) else {
            out.push_str(remaining);
            return out;
        };
        let end = start + relative_end + end_marker.len();
        let chunk = &source[start..end];

        if !predicate(chunk) {
            out.push_str(chunk);
        }

        cursor = end;
    }

    out.push_str(&source[cursor..]);
    out
}

fn remove_void_tags(source: &str, tag: &str, predicate: impl Fn(&str) -> bool) -> String {
    let start_marker = format!("<{tag}");
    let mut out = String::new();
    let mut cursor = 0;

    while let Some(relative_start) = source[cursor..].find(&start_marker) {
        let start = cursor + relative_start;
        out.push_str(&source[cursor..start]);

        let remaining = &source[start..];
        let Some(relative_end) = remaining.find('>') else {
            out.push_str(remaining);
            return out;
        };
        let end = start + relative_end + 1;
        let chunk = &source[start..end];

        if !predicate(chunk) {
            out.push_str(chunk);
        }

        cursor = end;
    }

    out.push_str(&source[cursor..]);
    out
}

fn remove_html_comments(source: &str) -> String {
    let mut out = String::new();
    let mut cursor = 0;

    while let Some(relative_start) = source[cursor..].find("<!--") {
        let start = cursor + relative_start;
        out.push_str(&source[cursor..start]);

        let remaining = &source[start + 4..];
        let Some(relative_end) = remaining.find("-->") else {
            return out;
        };
        cursor = start + 4 + relative_end + 3;
    }

    out.push_str(&source[cursor..]);
    out
}

fn script_start_tag_has_src(chunk: &str) -> bool {
    let Some(end) = chunk.find('>') else {
        return false;
    };
    chunk[..end].contains("src=")
}

fn strip_inline_style_attributes(source: &str) -> String {
    let bytes = source.as_bytes();
    let mut out = Vec::with_capacity(source.len());
    let mut cursor = 0;
    let mut in_tag = false;

    while cursor < bytes.len() {
        if !in_tag {
            if bytes[cursor] == b'<' {
                in_tag = true;
            }
            out.push(bytes[cursor]);
            cursor += 1;
            continue;
        }

        if bytes[cursor] == b'>' {
            in_tag = false;
            out.push(b'>');
            cursor += 1;
            continue;
        }

        if bytes[cursor..].starts_with(b"style=\"") || bytes[cursor..].starts_with(b"style='") {
            let quote = bytes[cursor + "style=".len()];
            cursor += "style=".len() + 1;
            while cursor < bytes.len() && bytes[cursor] != quote {
                cursor += 1;
            }
            if cursor < bytes.len() {
                cursor += 1;
            }
            continue;
        }

        out.push(bytes[cursor]);
        cursor += 1;
    }

    String::from_utf8(out).expect("html transform should preserve utf8")
}

fn strip_css_comments(source: &str) -> String {
    let mut out = String::new();
    let mut cursor = 0;

    while let Some(relative_start) = source[cursor..].find("/*") {
        let start = cursor + relative_start;
        out.push_str(&source[cursor..start]);

        let remaining = &source[start + 2..];
        let Some(relative_end) = remaining.find("*/") else {
            return out;
        };
        cursor = start + 2 + relative_end + 2;
    }

    out.push_str(&source[cursor..]);
    out
}


fn content_type_for(path: &str) -> String {
    let guessed = mime_guess::from_path(path).first_or_octet_stream();
    let essence = guessed.essence_str();
    if needs_charset(essence) {
        format!("{essence}; charset=utf-8")
    } else {
        essence.to_string()
    }
}

fn needs_charset(content_type: &str) -> bool {
    content_type.starts_with("text/")
        || matches!(
            content_type,
            "application/javascript"
                | "application/json"
                | "application/manifest+json"
                | "application/xml"
                | "image/svg+xml"
        )
}

fn cache_control_for(path: &str, hashed: bool) -> &'static str {
    if hashed {
        return "public, max-age=31536000, immutable";
    }

    match Path::new(path)
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| value.to_ascii_lowercase())
        .as_deref()
    {
        Some("html") | Some("pdf") | Some("txt") | Some("xml") => {
            "public, max-age=0, must-revalidate"
        }
        _ => "public, max-age=3600",
    }
}

fn should_compress(path: &str, content_type: &str, body_len: usize) -> bool {
    if body_len < 1024 {
        return false;
    }

    matches!(
        Path::new(path)
            .extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .as_deref(),
        Some("html")
            | Some("css")
            | Some("js")
            | Some("txt")
            | Some("xml")
            | Some("svg")
            | Some("webmanifest")
    ) || content_type.starts_with("text/")
}

fn gzip_compress(body: &[u8]) -> Vec<u8> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::best());
    encoder.write_all(body).expect("write gzip body");
    encoder.finish().expect("finish gzip")
}

fn brotli_compress(body: &[u8]) -> Vec<u8> {
    let mut writer = CompressorWriter::new(Vec::new(), 4096, 11, 22);
    writer.write_all(body).expect("write brotli body");
    writer.into_inner()
}

fn etag_for(body: &[u8]) -> String {
    let digest = Sha256::digest(body);
    let mut hex = String::new();
    for byte in digest.iter().take(16) {
        let _ = write!(hex, "{byte:02x}");
    }
    format!("\"{hex}\"")
}

fn variant_include(path: &Path, etag: &Option<String>, encoding: Option<&'static str>) -> String {
    format!(
        "Some(AssetVariant {{ body: include_bytes!({:?}), etag: {:?}, content_encoding: {:?} }})",
        path.to_string_lossy(),
        etag.as_deref().expect("etag"),
        encoding
    )
}

fn sanitized_output_name(request_path: &str) -> String {
    request_path
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '-') {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

#[derive(Clone, Copy, Debug)]
enum AssetKind {
    Html,
    Css,
    Manifest,
    Stable,
    HashedBinary,
}

impl AssetKind {
    fn is_hashed(self) -> bool {
        matches!(self, Self::Css | Self::Manifest | Self::HashedBinary)
    }
}

struct SourceAsset {
    relative_path: String,
    kind: AssetKind,
    body: Vec<u8>,
}

struct AssetBuildRecord {
    request_path: String,
    body_path: PathBuf,
    content_type: String,
    cache_control: &'static str,
    raw_etag: String,
    gzip_path: Option<PathBuf>,
    gzip_etag: Option<String>,
    br_path: Option<PathBuf>,
    br_etag: Option<String>,
}
