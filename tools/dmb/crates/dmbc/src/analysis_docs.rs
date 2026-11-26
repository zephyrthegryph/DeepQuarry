//! Doc comments for the declaration feed (`analysis_tree`): dmbc's expanded text carries no comments, so a declaration's docs are read
//! from its source file, the way dreammaker's lexer and tree parser attach them.
//!
//! dreammaker turns `///` and `/** */` into doc tokens that the next tree entry takes (`following_doc_comment`), and `//!` / `/*! */`
//! after an entry's header on its line into docs of that entry (`enclosing_doc_comment`). Ordinary comments and blank lines are no
//! tokens, so they leave pending docs in place; any other line takes them (a declaration) or drops them (code, a directive). The index
//! maps each source line that starts a declaration to the docs it would get: the pending following docs, then the enclosing ones on
//! its own line.
use dreammaker::docs::{CommentKind, DocCollection, DocComment, DocTarget};
use std::collections::HashMap;

/// Docs by (path, 1-based line), read on first use of each file.
#[derive(Default)]
pub struct DocIndex {
    files: HashMap<String, HashMap<u32, DocCollection>>,
}

impl DocIndex {
    pub fn docs(&mut self, path: &str, line: u32) -> DocCollection {
        let lines = self.files.entry(path.to_owned()).or_insert_with(|| match std::fs::read(path) {
            Ok(bytes) => index_text(&String::from_utf8_lossy(&bytes)),
            Err(_) => HashMap::new(),
        });
        // One line's docs go to the first declaration read from it: a macro that expands to several (`DECLARE_SHARED_CACHE`) documents
        // only its first, as dreammaker's parser hands the doc tokens to the next entry once.
        lines.remove(&line).unwrap_or_default()
    }
}

fn comment(kind: CommentKind, target: DocTarget, text: &str) -> DocComment {
    let mut c = DocComment::new(kind, target);
    c.text = text.to_owned();
    c
}

/// The doc comments of one file's lines.
pub fn index_text(text: &str) -> HashMap<u32, DocCollection> {
    let mut out: HashMap<u32, DocCollection> = HashMap::new();
    let mut pending: Vec<DocComment> = Vec::new();
    let lines: Vec<&str> = text.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l)).collect();
    let mut i = 0usize;
    while i < lines.len() {
        let line = lines[i];
        let trimmed = line.trim_start();
        let number = i as u32 + 1;
        i += 1;
        if trimmed.is_empty() {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("///") {
            pending.push(comment(CommentKind::Line, DocTarget::FollowingItem, rest));
            continue;
        }
        if trimmed.starts_with("//") {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("/*") {
            // A block comment: the text from after `/*` (the `*` of `/**` included, as the lexer keeps it) to before `*/`.
            let mut body = String::from(rest);
            let mut end = body.find("*/");
            while end.is_none() && i < lines.len() {
                body.push('\n');
                body.push_str(lines[i]);
                i += 1;
                end = body.find("*/");
            }
            let Some(end) = end else { break };
            let after = body[end + 2..].trim();
            let inner = &body[..end];
            // `/*! */` on a line of its own documents the block it is in (a type's docs, not compared), so only `/**` is kept.
            if inner.starts_with('*') {
                pending.push(comment(CommentKind::Block, DocTarget::FollowingItem, inner));
            }
            if after.is_empty() || after.starts_with("//") {
                continue;
            }
            // Code after the comment on its last line: treat that line as the entry.
            let number = i as u32;
            take(&mut out, &mut pending, number, after);
            continue;
        }
        if trimmed.starts_with('#') {
            pending.clear();
            continue;
        }
        take(&mut out, &mut pending, number, trimmed);
    }
    out
}

/// A code line: it takes the pending docs, then the `//!` (or `/*! */`) docs after its header.
fn take(out: &mut HashMap<u32, DocCollection>, pending: &mut Vec<DocComment>, number: u32, code: &str) {
    let mut docs = DocCollection::default();
    for c in pending.drain(..) {
        docs.push(c);
    }
    if let Some(index) = line_comment_start(code) {
        let rest = &code[index..];
        if let Some(text) = rest.strip_prefix("//!") {
            docs.push(comment(CommentKind::Line, DocTarget::EnclosingItem, text));
        } else if let Some(text) = rest.strip_prefix("///") {
            // A trailing `///` documents the next entry.
            pending.push(comment(CommentKind::Line, DocTarget::FollowingItem, text));
        }
    }
    if !docs.is_empty() {
        out.insert(number, docs);
    }
}

/// Where a `//` comment starts on a code line, outside strings.
fn line_comment_start(code: &str) -> Option<usize> {
    let bytes = code.as_bytes();
    let mut quote: Option<u8> = None;
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        match quote {
            Some(q) => {
                if b == b'\\' {
                    i += 1;
                } else if b == q {
                    quote = None;
                }
            }
            None => {
                if b == b'"' || b == b'\'' {
                    quote = Some(b);
                } else if b == b'/' && bytes.get(i + 1) == Some(&b'/') {
                    return Some(i);
                }
            }
        }
        i += 1;
    }
    None
}
