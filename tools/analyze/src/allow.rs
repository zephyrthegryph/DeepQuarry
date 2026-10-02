//! `// ALLOW(lint[, lint]): reason`, the one justified-keep annotation (ported once from
//! `tools/ci/allow_annotations.py`).
//!
//! A site is kept by an annotation on its own line, or on a comment-only line directly above it.
//! Inside a multi-line macro the block form `/* ALLOW(x): reason */` works the same. The reason
//! after the colon is required: an annotation with no reason keeps nothing.

use std::collections::BTreeSet;

use crate::pat;
use crate::tree::SourceFile;
use crate::util;

/// A parsed annotation: the lint names, and the reason ("" when the colon or the text is missing).
#[derive(Debug, Clone, PartialEq)]
pub struct Allow {
    pub names: BTreeSet<String>,
    pub reason: String,
    pub has_colon: bool,
}

/// The annotation on `line`, if any (`allow_annotations.parse`).
pub fn parse(line: &str) -> Option<Allow> {
    if !line.contains("ALLOW(") {
        return None;
    }
    let c = pat!(r"(?://+|/\*)\s*ALLOW\(\s*([\w\s,]*?)\s*\)\s*(:?)\s*(.*?)\s*(?:\*/.*)?$").captures(line)?;
    let names: BTreeSet<String> = c.s(1).split(',').map(|n| util::py_strip(n).to_string()).filter(|n| !n.is_empty()).collect();
    let has_colon = !c.s(2).is_empty();
    let reason = if has_colon { c.s(3).to_string() } else { String::new() };
    Some(Allow { names, reason, has_colon })
}

/// Names an annotation keeps: only when it has a reason (`allow_annotations.names_on`).
pub fn names_on(line: &str) -> BTreeSet<String> {
    match parse(line) {
        Some(a) if !a.reason.is_empty() => a.names,
        _ => BTreeSet::new(),
    }
}

/// Whether 1-based line `number` of `file` is kept for `lint`. Returns the annotation's line
/// number when it is (the usage the unused-ALLOW check records).
pub fn kept_by(file: &SourceFile, number: usize, lint: &str) -> Option<usize> {
    let raw = file.raw();
    if number >= 1 && number <= raw.num_lines() && names_on(raw.line(number)).contains(lint) {
        return Some(number);
    }
    if number >= 2 {
        let above = raw.line(number - 1);
        if util::py_lstrip(above).starts_with("//") && names_on(above).contains(lint) {
            return Some(number - 1);
        }
    }
    None
}

/// Same-line only (`allowed_here`): for a lint that reads a neighbouring line itself.
pub fn kept_here(file: &SourceFile, number: usize, lint: &str) -> Option<usize> {
    let raw = file.raw();
    if number >= 1 && number <= raw.num_lines() && names_on(raw.line(number)).contains(lint) {
        return Some(number);
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
    fn comment_line_above_keeps_next_line() {
        let f = SourceFile::from_text("code/a.dm", "// ALLOW(lifecycle): the sweep deletes every mob\nqdel(M)\nqdel(N)\n");
        assert_eq!(kept_by(&f, 2, "lifecycle"), Some(1));
        assert_eq!(kept_by(&f, 3, "lifecycle"), None);
        assert_eq!(kept_by(&f, 2, "other"), None);
    }
}
