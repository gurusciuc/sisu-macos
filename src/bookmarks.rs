use html5gum::{Token, Tokenizer};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

pub const LIMIT: usize = 10_000;
pub const MAX_BYTES: usize = 8 * 1024 * 1024;
#[derive(Clone, Serialize, Deserialize)]
pub struct Bookmark {
    pub title: String,
    pub url: String,
    pub folders: Vec<String>,
}
impl Bookmark {
    pub fn new(title: &str, address: &str) -> Option<Self> {
        if address.len() > 8192 {
            return None;
        }
        let u = url::Url::parse(address.trim()).ok()?;
        if !matches!(u.scheme(), "https" | "http")
            || u.host().is_none()
            || !u.username().is_empty()
            || u.password().is_some()
        {
            return None;
        }
        let title = if title.trim().is_empty() {
            u.host_str()?
        } else {
            title.trim()
        };
        Some(Self {
            title: title
                .chars()
                .filter(|c| !c.is_control())
                .take(256)
                .collect(),
            url: u.to_string(),
            folders: vec![],
        })
    }
}
#[derive(Default)]
pub struct Report {
    pub added: usize,
    pub duplicates: usize,
    pub skipped: usize,
}
pub fn merge_export(existing: &mut Vec<Bookmark>, input: &[u8]) -> Result<Report, String> {
    if input.len() > MAX_BYTES {
        return Err("Choose an export smaller than 8 MiB.".into());
    }
    let source = std::str::from_utf8(input).map_err(|_| "Choose a UTF-8 bookmarks HTML export.")?;
    let mut found_list = false;
    let mut stack: Vec<String> = vec![];
    let mut folder = String::new();
    let mut text = String::new();
    let mut href = None;
    let mut in_title = false;
    let mut added = vec![];
    let mut seen: HashSet<String> = existing.iter().map(|b| b.url.clone()).collect();
    let mut counts = Report::default();
    for token in Tokenizer::new(source).flatten() {
        match token {
            Token::StartTag(t) if t.name == b"dl" => {
                found_list = true;
                if stack.len() >= 32 {
                    return Err("Bookmark folders exceed 32 levels.".into());
                }
                stack.push(std::mem::take(&mut folder));
            }
            Token::EndTag(t) if t.name == b"dl" => {
                stack.pop();
                folder.clear();
            }
            Token::StartTag(t) if t.name == b"h3" => {
                text.clear();
                in_title = true;
            }
            Token::EndTag(t) if t.name == b"h3" => {
                folder = text
                    .trim()
                    .chars()
                    .filter(|c| !c.is_control())
                    .take(160)
                    .collect();
                in_title = false;
            }
            Token::StartTag(t) if t.name == b"a" => {
                text.clear();
                href = t
                    .attributes
                    .get(b"href".as_slice())
                    .map(|v| String::from_utf8_lossy(&v.value).into_owned());
            }
            Token::String(s) if (in_title || href.is_some()) && text.len() < 1024 => {
                text.extend(String::from_utf8_lossy(&s.value).chars().take(256));
            }
            Token::EndTag(t) if t.name == b"a" => {
                if let Some(mut b) = href.take().and_then(|u| Bookmark::new(&text, &u)) {
                    if !seen.insert(b.url.clone()) {
                        counts.duplicates += 1;
                        continue;
                    }
                    if seen.len() > LIMIT {
                        return Err("The combined library exceeds 10,000 bookmarks.".into());
                    }
                    b.folders = stack.iter().filter(|s| !s.is_empty()).cloned().collect();
                    added.push(b);
                    counts.added += 1;
                } else {
                    counts.skipped += 1;
                }
            }
            _ => {}
        }
    }
    if !found_list {
        return Err("Choose a bookmarks HTML export from Brave, Chrome, or Firefox.".into());
    }
    existing.extend(added);
    Ok(counts)
}
