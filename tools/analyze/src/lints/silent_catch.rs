//! Port of `tools/ci/silent_catch_lint.py`: a `catch` block must not swallow its exception
//! (doc/rewrite/object_model_core.md, lifecycle diagnostics).
//!
//! Every `catch` block must report (`dq_report_caught` / `report_caught`), rethrow (`throw`), trace
//! (`stack_trace` / `CRASH` / `world.Error`) or, outside the strict dirs only, log (`log_*(`, `Fail(`,
//! `TEST_FAIL`). The strict dirs (`strict_dirs` in `[lint.silent_catch.lists]`: the OM core, lifecycle,
//! the controllers, the error handler) accept only the first three. `// ALLOW(silent_catch): reason`
//! on the catch line, the line above it, or the first line of its block keeps one.
//!
//! Quirks kept: the Python walked `code/` and `maps/` with `os.walk` (dot-files and dot-directories
//! included: `hidden: true`) over the RAW lines; it has its own comment stripper (it knows both quote
//! kinds and backslash escapes, but not block comments, so a `catch` inside `/* */` counts); the block of
//! a catch is every following line indented deeper than it (tabs count as 4 columns, blank lines
//! skipped, the comment-stripping applied again to each); the inline text after `catch(...)` is
//! stripped twice (once with the line, once as a body line); the ALLOW question is asked only for a
//! catch that would otherwise be flagged, the same-line-only form second and only when the first said
//! no, so an annotation on a catch that reports is seen as unused.

use std::borrow::Cow;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::{Select, SourceFile};
use crate::util::{is_py_space, py_strip, starts_with_any};

static META: Meta = Meta {
    name: "silent_catch",
    group: "",
    label: "silent_catch",
    legacy: "tools/ci/silent_catch_lint.py",
    // os.walk over code/ and maps/: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm"), ("maps", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "silent_catch",
        hint: "use dq_report_caught(e, \"context\") or annotate `// ALLOW(silent_catch): reason`",
    }],
    allow: &["silent_catch"],
    lists: &["strict_dirs"],
};

const STRICT_OK: &str = r"\b(?:dq_)?report_caught\s*\(|\bthrow\b|\bstack_trace\s*\(|\bCRASH\s*\(|\bworld\.Error\s*\(";

struct SilentCatch {
    strict_ok: Pat,
    loose_ok: Pat,
}

/// `indent_width`: `len(s.expandtabs(4)) - len(s.expandtabs(4).lstrip())`, i.e. the columns of the
/// leading whitespace with tabs going to the next multiple of 4.
fn indent_width(s: &str) -> usize {
    let (mut width, mut col) = (0, 0);
    for c in s.chars() {
        if !is_py_space(c) {
            break;
        }
        match c {
            '\t' => {
                let n = 4 - col % 4;
                width += n;
                col += n;
            }
            '\n' | '\r' => {
                width += 1;
                col = 0;
            }
            _ => {
                width += 1;
                col += 1;
            }
        }
    }
    width
}

/// `strip_comment`: drops a trailing `//` comment outside quotes (either kind; a backslash escapes
/// the next character inside one).
fn strip_comment(line: &str) -> Cow<'_, str> {
    if !line.contains("//") {
        return Cow::Borrowed(line); // nothing to cut: the loop below would copy the line
    }
    let chars: Vec<char> = line.chars().collect();
    let mut out = String::new();
    let mut in_str: Option<char> = None;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if let Some(quote) = in_str {
            if c == '\\' {
                out.push(c);
                if let Some(&next) = chars.get(i + 1) {
                    out.push(next);
                }
                i += 2;
                continue;
            }
            if c == quote {
                in_str = None;
            }
        } else if c == '"' || c == '\'' {
            in_str = Some(c);
        } else if c == '/' && chars.get(i + 1) == Some(&'/') {
            break;
        }
        out.push(c);
        i += 1;
    }
    Cow::Owned(out)
}

impl Lint for SilentCatch {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if !f.text().contains("catch") {
            return;
        }
        let lines = f.raw().lines_vec();
        let strict = starts_with_any(&f.rel, cx.list("strict_dirs"));
        let ok_re = if strict { &self.strict_ok } else { &self.loose_ok };
        for i in 0..lines.len() {
            if !lines[i].contains("catch") {
                continue;
            }
            let code = strip_comment(lines[i]);
            let Some(m) = pat_match!(r"^(\s*)catch\b\s*(\([^)]*\))?\s*(.*)$").captures(&code) else { continue };
            let base = indent_width(m.s(1));
            let inline = py_strip(m.s(3));
            let mut body: Vec<&str> = if inline.is_empty() { Vec::new() } else { vec![inline] };
            let mut j = i + 1;
            while j < lines.len() {
                let next = lines[j];
                if py_strip(next).is_empty() {
                    j += 1;
                    continue;
                }
                if indent_width(next) <= base {
                    break;
                }
                body.push(next);
                j += 1;
            }
            let text = body.iter().map(|b| strip_comment(b)).collect::<Vec<_>>().join("\n");
            if ok_re.is_match(&text) {
                continue;
            }
            // The one ALLOW system: the catch line or a comment line above it; a catch also takes the
            // annotation on the first line of its body. Asked only for a catch that would otherwise be
            // flagged, so an annotation on one that reports is seen as unused.
            if out.allowed(f, i + 1, "silent_catch") || out.allowed_here(f, i + 2, "silent_catch") {
                continue;
            }
            let why = if strict { "strict dir: report/rethrow/trace required" } else { "no log/report/rethrow" };
            out.site_msg("silent_catch", i + 1, format!("silent catch ({})", why));
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/silent_catch_lint.py"],
            old_raw: &[],
            blank: &[],
            // `file:line: silent catch (...)`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SilentCatch {
        strict_ok: Pat::new(STRICT_OK),
        loose_ok: Pat::new(&format!(r"{}|\blog_\w+\s*\(|\bFail\s*\(|\bTEST_FAIL\b", STRICT_OK)),
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn indent_counts_tabs_to_the_next_multiple_of_four() {
        assert_eq!(indent_width("\tx"), 4);
        assert_eq!(indent_width("  \tx"), 4);
        assert_eq!(indent_width("     \tx"), 8);
        assert_eq!(indent_width("\t\tx"), 8);
        assert_eq!(indent_width("x\t"), 0);
        assert_eq!(indent_width(""), 0);
        assert_eq!(indent_width("   "), 3);
    }

    #[test]
    fn comment_stripper_knows_both_quotes_and_escapes() {
        assert_eq!(strip_comment("a // b"), "a ");
        assert_eq!(strip_comment("a \"// b\" // c"), "a \"// b\" ");
        assert_eq!(strip_comment("a '// b' // c"), "a '// b' ");
        assert_eq!(strip_comment("a \"x\\\" // y\" // c"), "a \"x\\\" // y\" ");
        assert_eq!(strip_comment("no comment"), "no comment");
    }

    fn scan(text: &str) -> Sink {
        let tree = crate::tree::Tree::from_files(vec![]);
        let mut scope = crate::scopes::LintScope::default();
        scope.lists.insert("strict_dirs".to_string(), vec!["code/controllers/".to_string()]);
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
    fn allow_on_a_catch_that_reports_is_not_recorded() {
        let out = scan("catch(e) // ALLOW(silent_catch): reports so this annotation keeps nothing\n\treport_caught(e, \"x\")\n");
        assert!(out.sites.is_empty());
        assert!(out.allow_used.is_empty(), "{:?}", out.allow_used);
    }

    #[test]
    fn allow_here_is_tried_only_after_allowed_says_no() {
        let out = scan("catch(e) // ALLOW(silent_catch): the catch line itself carries the reason\n\t// ALLOW(silent_catch): and so does the first body line\n\tpass()\n");
        assert!(out.sites.is_empty());
        assert_eq!(out.allow_used.len(), 1, "{:?}", out.allow_used);
        assert_eq!(out.allow_used[0].line, 1);
    }
}
