//! Port of `tools/ci/cache_lint.py`: shared caches go through `DECLARE_SHARED_CACHE`
//! (doc/rewrite/caching.md).
//!
//! A hand-rolled keyed cache (a `var/static/list/...cache...`, a global `GLOBAL_LIST_*(...cache...)` or
//! a top-level `var/list/...cache...`) has its own key format, no invalidation, no stats and no mutation
//! guard. Typecaches (names containing `typecache`) are not caches in this sense. A justified keep
//! carries `// ALLOW(cache): <reason>`. Ceiling 0: any site fails.
//!
//! Quirks kept: the Python used `Path.rglob` (dot-files and dot-directories included: `hidden: true`)
//! and `read_text(errors="ignore").splitlines()`, so a form feed, `\x0b`, `\x1c`-`\x1e`, NEL and the
//! Unicode line/paragraph separators also break lines, line numbers (and the ALLOW lookup) follow that,
//! and an invalid UTF-8 byte is dropped, not replaced; the patterns run on the text before the first
//! `//` (strings are not stripped, block comments are not handled); a line has at most one site, from
//! the first pattern that matches, and a match of a typecache or an ALLOW ends the line (so a second
//! cache on the same line is never seen).

use std::borrow::Cow;

use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{Select, SourceFile};
use crate::util::{before_slashes, py_lstrip, py_strip};

static META: Meta = Meta {
    name: "cache",
    group: "",
    label: "cache",
    legacy: "tools/ci/cache_lint.py",
    // Path.rglob: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "hand_rolled",
        hint: "use DECLARE_SHARED_CACHE / CACHED() (doc/rewrite/caching.md), or annotate a genuine exception with `// ALLOW(cache): <reason>`",
    }],
    allow: &["cache"],
    lists: &[],
};

struct Cache {
    patterns: Vec<Pat>,
}

/// `str.splitlines()` (no final empty line; `\r` never occurs: the tree text is universal-newline).
fn py_splitlines(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    for (i, c) in text.char_indices() {
        if matches!(c, '\n' | '\r' | '\u{0b}' | '\u{0c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}') {
            out.push(&text[start..i]);
            start = i + c.len_utf8();
        }
    }
    if start < text.len() {
        out.push(&text[start..]);
    }
    out
}

/// The file's text as `read_text(encoding="utf-8", errors="ignore")` gives it: invalid bytes dropped
/// (the tree's own text replaces them with U+FFFD, which is also a legal character, so the bytes are
/// read again when the text holds one).
fn text_ignoring_bad_bytes(f: &SourceFile) -> Cow<'_, str> {
    let text = f.text();
    if !text.contains('\u{FFFD}') {
        return Cow::Borrowed(text);
    }
    match std::fs::read(&f.abs) {
        Ok(bytes) => {
            let mut s = String::with_capacity(bytes.len());
            for chunk in bytes.utf8_chunks() {
                s.push_str(chunk.valid());
            }
            Cow::Owned(crate::util::universal_newlines(s))
        }
        Err(_) => Cow::Borrowed(text),
    }
}

/// `allowed(lines, number, "cache")` over the Python's own `splitlines` list.
fn allowed_in(out: &mut Sink, f: &SourceFile, lines: &[&str], number: usize) -> bool {
    let keeps = |line: &str| -> Option<Option<String>> {
        match crate::allow::parse(line) {
            Some(a) if !a.reason.is_empty() && a.names.contains("cache") => Some(a.codes.get("cache").cloned()),
            _ => None,
        }
    };
    let mut hit: Option<(usize, Option<String>)> = None;
    if number >= 1 && number <= lines.len() {
        if let Some(code) = keeps(lines[number - 1]) {
            hit = Some((number, code));
        }
    }
    if hit.is_none() && number >= 2 {
        let above = lines.get(number - 2).copied().unwrap_or("");
        if py_lstrip(above).starts_with("//") {
            if let Some(code) = keeps(above) {
                hit = Some((number - 1, code));
            }
        }
    }
    match hit {
        Some((at, code)) => {
            let u = AllowUse { rel: f.rel.clone(), line: at as u32, name: "cache".to_string(), code: code.unwrap_or_default() };
            if !out.allow_used.contains(&u) {
                out.allow_used.push(u);
            }
            true
        }
        None => false,
    }
}

/// A cheap guard: every pattern needs the word `cache`, in any case.
fn has_cache(s: &str) -> bool {
    s.as_bytes().windows(5).any(|w| w.eq_ignore_ascii_case(b"cache"))
}

impl Lint for Cache {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let text = text_ignoring_bad_bytes(f);
        let lines = py_splitlines(&text);
        for (idx, line) in lines.iter().enumerate() {
            let n = idx + 1;
            let code = before_slashes(line);
            if !has_cache(code) {
                continue;
            }
            for pat in &self.patterns {
                let Some(m) = pat.captures(code) else { continue };
                if m.s(1).to_lowercase().contains("typecache") {
                    break;
                }
                if allowed_in(out, f, &lines, n) {
                    break;
                }
                out.site_msg("hand_rolled", n, py_strip(line));
                break;
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/cache_lint.py"],
            old_raw: &[],
            blank: &[],
            // `  file:line text`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Cache {
        patterns: vec![
            Pat::new(r"(?i)\bvar/static/list/(\w*cache\w*)"),
            Pat::new(r"(?i)\bGLOBAL_LIST_(?:EMPTY|INIT|EMPTY_TYPED|INIT_TYPED)\(\s*(\w*cache\w*)"),
            Pat::new(r"(?i)^var/(?:global/)?list/(\w*cache\w*)"),
            Pat::new(r"(?i)\bvar/global/list/(\w*cache\w*)"),
        ],
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitlines_matches_python() {
        assert_eq!(py_splitlines("a\nb\n"), vec!["a", "b"]);
        assert_eq!(py_splitlines("a\x0bb\u{2028}c\u{85}d\x0ce"), vec!["a", "b", "c", "d", "e"]);
        assert_eq!(py_splitlines("\n\nx"), vec!["", "", "x"]);
        assert!(py_splitlines("").is_empty());
    }

    fn scan(text: &str) -> Sink {
        let tree = crate::tree::Tree::from_files(vec![]);
        let scope = crate::scopes::LintScope::default();
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text("code/modules/x.dm", text);
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        let mut reg = Registry::default();
        register(&mut reg);
        reg.lints[0].scan_file(&cx, &f, &mut out);
        out
    }

    #[test]
    fn allow_follows_the_splitlines_numbering() {
        // The form feed splits the first physical line in two: the ALLOW is its own line, the site the next.
        let out = scan("// ALLOW(cache): the typecache of this module is rebuilt on reload\x0cvar/list/a_cache\nvar/list/b_cache\n");
        assert_eq!(out.sites.len(), 1, "{:?}", out.sites);
        assert_eq!(out.sites[0].line, 3);
        assert_eq!(out.allow_used.len(), 1);
        assert_eq!(out.allow_used[0].line, 1);
    }

    #[test]
    fn a_typecache_match_hides_the_rest_of_the_line() {
        let out = scan("var/static/list/typecache_a = list() ; var/static/list/b_cache\nvar/static/list/b_cache; var/static/list/typecache_a\n");
        assert_eq!(out.sites.len(), 1);
        assert_eq!(out.sites[0].line, 2);
    }
}
