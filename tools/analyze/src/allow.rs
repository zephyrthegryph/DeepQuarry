//! `// ALLOW(lint[, lint]): reason`, the one justified-keep annotation (ported once from
//! `tools/ci/allow_annotations.py`).
//!
//! A site is kept by an annotation on its own line, or on a comment-only line directly above it.
//! Inside a multi-line macro the block form `/* ALLOW(x): reason */` works the same. The reason
//! after the colon is required: an annotation with no reason keeps nothing.
//!
//! A name may carry a reason code, `ALLOW(scheduler/BLOCKING_IO): world.Export() blocks`. The code
//! is part of the annotation, not of the lint name: it keeps a site for `scheduler` exactly as the
//! bare form does, is recorded when used, and is checked against the lint's `reason_codes` list in
//! `tools/ci/lint_scopes.toml` when that list exists.

use std::collections::{BTreeMap, BTreeSet};

use crate::pat;
use crate::tree::SourceFile;
use crate::util;

/// A parsed annotation. `names` are the lint names (without codes); `codes` maps a lint to the code
/// written after its `/`; `reason` is "" when the colon or the text is missing.
#[derive(Debug, Clone, PartialEq)]
pub struct Allow {
    pub names: BTreeSet<String>,
    pub codes: BTreeMap<String, String>,
    pub reason: String,
    pub has_colon: bool,
}

/// The annotation on `line`, if any (`allow_annotations.parse`).
pub fn parse(line: &str) -> Option<Allow> {
    if !line.contains("ALLOW(") {
        return None;
    }
    let c = pat!(r"(?://+|/\*)\s*ALLOW\(\s*([\w\s,/]*?)\s*\)\s*(:?)\s*(.*?)\s*(?:\*/.*)?$").captures(line)?;
    let mut names = BTreeSet::new();
    let mut codes = BTreeMap::new();
    for entry in c.s(1).split(',') {
        let entry = util::py_strip(entry);
        if entry.is_empty() {
            continue;
        }
        match entry.split_once('/') {
            Some((lint, code)) => {
                let (lint, code) = (util::py_strip(lint), util::py_strip(code));
                if !lint.is_empty() {
                    names.insert(lint.to_string());
                    if !code.is_empty() {
                        codes.insert(lint.to_string(), code.to_string());
                    }
                }
            }
            None => {
                names.insert(entry.to_string());
            }
        }
    }
    let has_colon = !c.s(2).is_empty();
    let reason = if has_colon { c.s(3).to_string() } else { String::new() };
    Some(Allow { names, codes, reason, has_colon })
}

/// Names an annotation keeps: only when it has a reason (`allow_annotations.names_on`).
pub fn names_on(line: &str) -> BTreeSet<String> {
    match parse(line) {
        Some(a) if !a.reason.is_empty() => a.names,
        _ => BTreeSet::new(),
    }
}

/// Where an annotation that keeps a site was found, and the reason code it gave for the lint.
#[derive(Debug, Clone, PartialEq)]
pub struct Kept {
    pub line: usize,
    pub code: Option<String>,
}

fn keeps(line: &str, lint: &str) -> Option<Option<String>> {
    match parse(line) {
        Some(a) if !a.reason.is_empty() && a.names.contains(lint) => Some(a.codes.get(lint).cloned()),
        _ => None,
    }
}

/// Whether 1-based line `number` of `file` is kept for `lint`: the annotation is on the line
/// itself, or on a comment-only line directly above it.
pub fn kept(file: &SourceFile, number: usize, lint: &str) -> Option<Kept> {
    let raw = file.raw();
    if number >= 1 && number <= raw.num_lines() {
        if let Some(code) = keeps(raw.line(number), lint) {
            return Some(Kept { line: number, code });
        }
    }
    if number >= 2 {
        let above = raw.line(number - 1);
        if util::py_lstrip(above).starts_with("//") {
            if let Some(code) = keeps(above, lint) {
                return Some(Kept { line: number - 1, code });
            }
        }
    }
    None
}

/// The annotation's line number only (`kept(..).map(|k| k.line)`).
pub fn kept_by(file: &SourceFile, number: usize, lint: &str) -> Option<usize> {
    kept(file, number, lint).map(|k| k.line)
}

/// Same-line only (`allowed_here`): for a lint that reads a neighbouring line itself.
pub fn kept_here(file: &SourceFile, number: usize, lint: &str) -> Option<Kept> {
    let raw = file.raw();
    if number >= 1 && number <= raw.num_lines() {
        if let Some(code) = keeps(raw.line(number), lint) {
            return Some(Kept { line: number, code });
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_line_and_block_forms() {
        let a = parse("spawn(0) // ALLOW(scheduler): world.Export() blocks").unwrap();
        assert!(a.names.contains("scheduler"));
        assert_eq!(a.reason, "world.Export() blocks");
        let b = parse("#define X /* ALLOW(a, b): macro body */ \\").unwrap();
        assert_eq!(b.names.len(), 2);
        assert_eq!(b.reason, "macro body");
        let c = parse("x // ALLOW(scheduler)").unwrap();
        assert_eq!(c.reason, "");
        assert!(names_on("x // ALLOW(scheduler)").is_empty());
        assert!(parse("nothing here").is_none());
    }

    #[test]
    fn reason_codes_ride_on_the_name() {
        let a = parse("spawn(0) // ALLOW(scheduler/BLOCKING_IO, cache): the export blocks").unwrap();
        assert_eq!(a.names.iter().cloned().collect::<Vec<_>>(), vec!["cache", "scheduler"]);
        assert_eq!(a.codes.get("scheduler").map(|s| s.as_str()), Some("BLOCKING_IO"));
        assert!(a.codes.get("cache").is_none());
        let f = SourceFile::from_text("code/a.dm", "spawn(0) // ALLOW(scheduler/BLOCKING_IO): the export blocks\n");
        assert_eq!(kept(&f, 1, "scheduler"), Some(Kept { line: 1, code: Some("BLOCKING_IO".to_string()) }));
        assert_eq!(kept(&f, 1, "cache"), None);
    }

    #[test]
    fn comment_line_above_keeps_next_line() {
        let f = SourceFile::from_text("code/a.dm", "// ALLOW(lifecycle): the sweep deletes every mob\nqdel(M)\nqdel(N)\n");
        assert_eq!(kept_by(&f, 2, "lifecycle"), Some(1));
        assert_eq!(kept_by(&f, 3, "lifecycle"), None);
        assert_eq!(kept_by(&f, 2, "other"), None);
    }
}
