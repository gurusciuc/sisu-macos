// SPDX-License-Identifier: Apache-2.0
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

pub const MAX_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_COOKIES: usize = 1_000;

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SameSite {
    Unspecified,
    None,
    Lax,
    Strict,
}
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CookieRecord {
    pub name: String,
    pub value: String,
    pub host: String,
    pub path: String,
    pub secure: bool,
    pub http_only: bool,
    pub host_only: bool,
    pub expires: Option<i64>,
    pub same_site: SameSite,
}
#[derive(Serialize)]
pub struct CookieExport {
    pub cookies: Vec<CookieRecord>,
    pub expired: usize,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExportCookie {
    name: String,
    value: String,
    domain: String,
    #[serde(default = "root_path")]
    path: String,
    #[serde(default)]
    secure: bool,
    #[serde(default, alias = "httponly")]
    http_only: bool,
    host_only: Option<bool>,
    #[serde(default)]
    session: bool,
    expiration_date: Option<f64>,
    same_site: Option<String>,
    partition_key: Option<serde_json::Value>,
    #[serde(default)]
    partitioned: bool,
    first_party_domain: Option<String>,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum ExportFile {
    Array(Vec<ExportCookie>),
    Object { cookies: Vec<ExportCookie> },
}
fn root_path() -> String {
    "/".into()
}

/// Validate the whole file before callers write anything to a profile.
/// Scoped/partitioned records require an engine API that preserves their scope.
pub fn parse_export(bytes: &[u8], now: i64) -> Result<CookieExport, String> {
    if bytes.len() > MAX_BYTES {
        return Err("The cookie export exceeds 8 MiB.".into());
    }
    let source: ExportFile = serde_json::from_slice(bytes)
        .map_err(|_| "Choose a cookies JSON export containing name, value and domain fields.")?;
    let input = match source {
        ExportFile::Array(rows) | ExportFile::Object { cookies: rows } => rows,
    };
    if input.len() > MAX_COOKIES {
        return Err("The cookie export exceeds 1,000 records.".into());
    }
    let mut output = CookieExport {
        cookies: vec![],
        expired: 0,
    };
    let mut seen = HashSet::new();
    for row in input {
        if row.partitioned
            || row.partition_key.is_some()
            || row
                .first_party_domain
                .as_ref()
                .is_some_and(|d| !d.is_empty())
        {
            return Err(
                "Partitioned cookies require a scope-preserving importer. No cookies were changed."
                    .into(),
            );
        }
        if row.name.is_empty()
            || row
                .name
                .bytes()
                .any(|c| c <= 32 || c >= 127 || b"()<>@,;:\\\"/[]?={}".contains(&c))
            || row.value.bytes().any(|c| c < 32 || c == 127 || c == b';')
            || !row.path.starts_with('/')
            || row.path.contains(';')
            || row.path.chars().any(char::is_control)
            || row.name.len() + row.value.len() + row.domain.len() + row.path.len() > 4096
        {
            return Err(
                "A cookie contains invalid attributes or exceeds 4 KiB. No cookies were changed."
                    .into(),
            );
        }
        let domain = row.domain.trim_start_matches('.');
        let address = url::Url::parse(&format!("https://{domain}/"))
            .map_err(|_| "A cookie has an invalid domain.")?;
        if row.domain.starts_with("..")
            || domain.is_empty()
            || address.host_str().is_none()
            || !address.username().is_empty()
            || address.password().is_some()
            || address.port().is_some()
            || address.path() != "/"
            || address.query().is_some()
            || address.fragment().is_some()
            || domain.contains(['/', '?', '#', '@'])
        {
            return Err("A cookie has an invalid domain. No cookies were changed.".into());
        }
        let host = address.host_str().unwrap().to_owned();
        let host_only = row.host_only.unwrap_or(!row.domain.starts_with('.'));
        if !host_only
            && (host.ends_with('.')
                || host.parse::<std::net::IpAddr>().is_ok()
                || host.starts_with('[')
                || psl::domain_str(&host).is_none())
        {
            return Err("A domain cookie has an invalid or public suffix scope.".into());
        }
        let same_site = match row.same_site.as_deref().unwrap_or("unspecified") {
            "unspecified" => SameSite::Unspecified,
            "none" | "no_restriction" => SameSite::None,
            "lax" => SameSite::Lax,
            "strict" => SameSite::Strict,
            _ => return Err("A cookie has an unsupported SameSite attribute.".into()),
        };
        if (same_site == SameSite::None || row.name.starts_with("__Secure-")) && !row.secure {
            return Err(
                "A secure cookie attribute is inconsistent. No cookies were changed.".into(),
            );
        }
        if row.name.starts_with("__Host-") && (!row.secure || !host_only || row.path != "/") {
            return Err("A __Host- cookie has an invalid scope. No cookies were changed.".into());
        }
        let expires = if row.session {
            None
        } else {
            row.expiration_date
                .map(|value| {
                    if !value.is_finite() || !(0.0..=253_402_300_799.0).contains(&value) {
                        return Err("A cookie has an invalid expiry date.");
                    }
                    Ok(value.floor() as i64)
                })
                .transpose()
                .map_err(str::to_owned)?
        };
        if expires.is_some_and(|expiry| expiry <= now) {
            output.expired += 1;
            continue;
        }
        if !seen.insert((host.clone(), host_only, row.path.clone(), row.name.clone())) {
            return Err(
                "Duplicate cookie keys appear in the export. No cookies were changed.".into(),
            );
        }
        output.cookies.push(CookieRecord {
            name: row.name,
            value: row.value,
            host,
            path: row.path,
            secure: row.secure,
            http_only: row.http_only,
            host_only,
            expires,
            same_site,
        });
    }
    Ok(output)
}
