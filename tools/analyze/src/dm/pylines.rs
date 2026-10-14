//! Python's `str.splitlines()` and the ALLOW question over such a line list, for lints whose Python
//! read files with `read().splitlines()` instead of `split("\n")` (`init_lint`).
//!
//! `splitlines()` also breaks on `\v`, `\f`, `\x1c`..`\x1e`, NEL (`\x85`), U+2028 and U+2029 and has
//! no final empty line, so its line numbers drift from the `split("\n")` view every other lint (and
//! `Tree::site_text`) uses once a file holds one of them. The tree's text is already
//! universal-newline (`\r` never occurs).

use crate::allow;
use crate::lint::{AllowUse, Sink};
use crate::tree::SourceFile;
use crate::util::py_lstrip;

/// `text.splitlines()`.
pub fn py_splitlines(text: &str) -> Vec<&str> {
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

/// `allow_annotations.allowed(lines, number, lint)` over an arbitrary line list: the annotation is on
/// line `number` (1-based) itself or on a comment-only line directly above it. Records the use.
pub fn allowed_in(out: &mut Sink, f: &SourceFile, lines: &[&str], number: usize, lint: &str) -> bool {
    let keeps = |line: &str| -> Option<Option<String>> {
        match allow::parse(line) {
            Some(a) if !a.reason.is_empty() && a.names.contains(lint) => Some(a.codes.get(lint).cloned()),
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
            let u = AllowUse { rel: f.rel.clone(), line: at as u32, name: lint.to_string(), code: code.unwrap_or_default() };
            if !out.allow_used.contains(&u) {
                out.allow_used.push(u);
            }
            true
        }
        None => false,
    }
}

/// [`allowed_in`] for code that runs inside an `incr` closure: the use is recorded through
/// `sys::replay_recorded` (the thread's recorded set) instead of into a `Sink`, so the cache captures
/// it with the result and replays it on a hit.
pub fn allowed_in_recorded(f: &SourceFile, lines: &[&str], number: usize, lint: &str) -> bool {
    let mut sink = Sink::new();
    let kept = allowed_in(&mut sink, f, lines, number, lint);
    if !sink.allow_used.is_empty() {
        crate::dm::sys::replay_recorded(sink.allow_used);
    }
    kept
}

/// Runs `run` (which may record ALLOW uses through `sys::kept_recorded` / [`allowed_in_recorded`],
/// directly or through `incr` caches that replay them) and moves what it recorded into `out`.
pub fn recorded_into<T>(out: &mut Sink, run: impl FnOnce() -> T) -> T {
    let before = crate::dm::sys::take_recorded();
    let result = run();
    for u in crate::dm::sys::take_recorded() {
        if !out.allow_used.contains(&u) {
            out.allow_used.push(u);
        }
    }
    crate::dm::sys::restore_recorded(before);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitlines_matches_python() {
        assert_eq!(py_splitlines("a\nb\n"), ["a", "b"]);
        assert_eq!(py_splitlines("a\n\nb"), ["a", "", "b"]);
        assert_eq!(py_splitlines(""), Vec::<&str>::new());
        assert_eq!(py_splitlines("a\u{0c}b\u{1c}c\u{85}d\u{2028}e"), ["a", "b", "c", "d", "e"]);
        assert_eq!(py_splitlines("\n"), [""]);
    }

    #[test]
    fn allowed_in_reads_the_given_lines() {
        let f = SourceFile::from_text("code/a.dm", "x\n");
        let lines = ["// ALLOW(init): a kept line for the test", "range(1)", "range(2) // ALLOW(init): kept on the line", "range(3)"];
        let mut out = Sink::new();
        assert!(allowed_in(&mut out, &f, &lines, 2, "init"));
        assert!(allowed_in(&mut out, &f, &lines, 3, "init"));
        assert!(!allowed_in(&mut out, &f, &lines, 4, "init"));
        assert!(!allowed_in(&mut out, &f, &lines, 2, "other"));
        assert_eq!(out.allow_used.len(), 2);
    }
}
