//! Port of `tools/ci/organ_slots_lint.py`: internal organs live only in keyed ledger slots
//! (doc/rewrite/archive/completion_plan.md 3.4).
//!
//! The mob-side caches `internal_organs` / `internal_organs_by_name` and the limb's
//! `internal_organs` are deleted. Ceiling 0: any use fails.
//!
//! Quirks kept: the Python used `Path.rglob`, so dot-files and dot-directories are scanned
//! (`hidden: true`); it split lines with `str.splitlines()`, which also breaks on `\x0b`, `\x0c`,
//! `\x1c`-`\x1e`, `\x85`, ` ` and ` `, so line numbers follow that; and a line that merely
//! contains the text `ALLOW(organ_slots)` is skipped (a substring test, not the `allowed()` helper:
//! no comment-line-above form, and any prefix of a comment counts).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::tree::{Select, SourceFile};
use crate::util::py_strip;

static META: Meta = Meta {
    name: "organ_slots",
    group: "",
    label: "organ_slots",
    legacy: "tools/ci/organ_slots_lint.py",
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "internal_organs",
        hint: "use organ_in(tag), INTERNAL_ORGANS(M) or limb.held_organs() (code/modules/body/parts/queries.dm)",
    }],
    allow: &["organ_slots"],
    lists: &[],
};

struct OrganSlots;

/// `str.splitlines()` (no trailing empty line; `\r\n` is one break).
fn py_splitlines(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut it = s.char_indices().peekable();
    while let Some((i, c)) = it.next() {
        let is_break = matches!(c, '\n' | '\r' | '\u{b}' | '\u{c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}');
        if !is_break {
            continue;
        }
        out.push(&s[start..i]);
        let mut end = i + c.len_utf8();
        if c == '\r' {
            if let Some(&(_, '\n')) = it.peek() {
                it.next();
                end += 1;
            }
        }
        start = end;
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out
}

impl Lint for OrganSlots {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (i, line) in py_splitlines(&f.raw().text).into_iter().enumerate() {
            if line.contains("ALLOW(organ_slots)") {
                continue;
            }
            if pat!(r"(?<![\w])internal_organs(_by_name)?\b").is_match(line) {
                out.site_msg("internal_organs", i + 1, py_strip(line));
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/organ_slots_lint.py"],
            old_raw: &[&["tools/ci/organ_slots_lint.py"]],
            blank: &[],
            parse: ParseKind::Indented,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(OrganSlots);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitlines_matches_python() {
        assert_eq!(py_splitlines("a\nb\n"), vec!["a", "b"]);
        assert_eq!(py_splitlines("a\x0bb\u{2028}c\r\nd"), vec!["a", "b", "c", "d"]);
        assert_eq!(py_splitlines("\n\nx"), vec!["", "", "x"]);
        assert!(py_splitlines("").is_empty());
    }
}
