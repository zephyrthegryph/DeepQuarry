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
    files: HashMap<String, FileDocs>,
    /// The file the preprocessor reads before each one (`with_order`): docs pending at the end of a file go to the first entry of
    /// the next, as dreammaker's token stream runs on across an include.
    previous: HashMap<String, String>,
}

/// One file's docs: by line, and those still pending at its end.
#[derive(Default)]
struct FileDocs {
    lines: HashMap<u32, DocCollection>,
    first: Option<u32>,
    tail: Vec<DocComment>,
}

impl DocIndex {
    /// An index that carries pending docs across files read in `order` (the include order).
    pub fn with_order(order: impl IntoIterator<Item = String>) -> Self {
        let mut previous = HashMap::new();
        let mut last: Option<String> = None;
        for path in order {
            if last.as_deref() == Some(path.as_str()) {
                continue;
            }
            if let Some(last) = last.replace(path.clone()) {
                previous.entry(path).or_insert(last);
            }
        }
        Self { files: HashMap::new(), previous }
    }

    fn load(&mut self, path: &str) {
        if self.files.contains_key(path) {
            return;
        }
        let (lines, first, tail) = match std::fs::read(path) {
            Ok(bytes) => index_file(&String::from_utf8_lossy(&bytes)),
            Err(_) => Default::default(),
        };
        // The docs left at the end of the files before this one (back to the last one with an entry) go to its first entry.
        let mut carried: Vec<DocComment> = Vec::new();
        let mut at = self.previous.get(path).cloned();
        let mut chain = Vec::new();
        while let Some(p) = at {
            if chain.contains(&p) || chain.len() > 64 {
                break;
            }
            chain.push(p.clone());
            match self.files.get(&p) {
                Some(f) => {
                    carried.splice(0..0, f.tail.iter().cloned());
                    break;
                }
                None => {
                    // Not read yet: its own text decides (a file with an entry ends the chain).
                    let (_, first, tail) = std::fs::read(&p).map(|b| index_file(&String::from_utf8_lossy(&b))).unwrap_or_default();
                    carried.splice(0..0, tail);
                    if first.is_some() {
                        break;
                    }
                    at = self.previous.get(&p).cloned();
                }
            }
        }
        let mut f = FileDocs { lines, first, tail };
        if !carried.is_empty() {
            match f.first {
                Some(line) => {
                    let mut docs = DocCollection::default();
                    for c in carried {
                        docs.push(c);
                    }
                    if let Some(own) = f.lines.remove(&line) {
                        for c in own {
                            docs.push(c);
                        }
                    }
                    f.lines.insert(line, docs);
                }
                None => f.tail.splice(0..0, carried).for_each(drop),
            }
        }
        self.files.insert(path.to_owned(), f);
    }

    pub fn docs(&mut self, path: &str, line: u32) -> DocCollection {
        self.load(path);
        let lines = &mut self.files.get_mut(path).expect("loaded").lines;
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
    index_file(text).0
}

/// The doc comments of one file's lines, its first entry line, and the docs still pending at its end.
fn index_file(text: &str) -> (HashMap<u32, DocCollection>, Option<u32>, Vec<DocComment>) {
    let mut out: HashMap<u32, DocCollection> = HashMap::new();
    let mut first: Option<u32> = None;
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
            first.get_or_insert(number);
            take(&mut out, &mut pending, number, after);
            continue;
        }
        if let Some(directive) = trimmed.strip_prefix('#') {
            // A `#define` takes the pending docs (dreammaker's preprocessor gives them to the macro); any other directive emits no
            // token and leaves them for the next entry.
            if directive.trim_start().starts_with("define") {
                pending.clear();
            }
            continue;
        }
        first.get_or_insert(number);
        take(&mut out, &mut pending, number, trimmed);
    }
    (out, first, pending)
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
