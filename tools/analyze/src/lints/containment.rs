//! Port of `tools/ci/containment_lint.py`: raw writes to `loc` / `contents` (roadmap C1,
//! doc/rewrite/containment.md section 2).
//!
//! Every change of where a movable is goes through the ledger (`forceMove()` and the slot API). A raw
//! write skips it: `X.loc = Y` (and a bare `loc = Y` in a proc), `X.contents += Y` / `-= Y`,
//! `X.contents.Add(Y)` / `.Remove(Y)`. An outright ban (C11): any unannotated site fails, and a
//! site that must stay raw carries `// ALLOW(containment): <reason>`.
//!
//! The Python has no path exemption (it does not call `exempt_path()`): unit tests are scanned.
//!
//! Quirks kept: a `var/.../loc =` declaration is cut out of the line before either pattern runs
//! (which can join the text on either side of it); a `loc =` straight after `(` or `,` is a named
//! argument and skipped; every `contents` match on a line counts, but the ALLOW question is asked
//! once per line, and only for a line that has a site.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{py_rstrip, py_strip};

static META: Meta = Meta {
    name: "containment",
    group: "",
    label: "containment",
    legacy: "tools/ci/containment_lint.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "raw_writes",
        hint: "use forceMove(), moveToNullspace(), the slot API (code/datums/containment/api.dm) or image_anchor(); a justified keep takes `// ALLOW(containment): <reason>`",
    }],
    allow: &["containment"],
    lists: &[],
};

struct Containment {
    /// `loc =` not part of ==, !=, <=, >=, and not a longer name (oldloc, T.locs).
    loc_write: Pat,
    contents_write: Pat,
    /// Declarations and named arguments are not writes: `var/turf/loc = ...`.
    declaration: Pat,
}

impl Lint for Containment {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (number, line) in f.code().numbered() {
            // A declaration holds "loc", so this only skips lines nothing can match on.
            if !line.contains("loc") && !line.contains("contents") {
                continue;
            }
            let stripped;
            let line = if self.declaration.is_match(line) {
                stripped = self.declaration.replace_all(line, "");
                stripped.as_str()
            } else {
                line
            };
            let mut found = 0;
            for m in self.loc_write.find_iter(line) {
                let before = py_rstrip(&line[..m.start]);
                // A named argument inside a call: `(loc = x` or `, loc = x`.
                if before.ends_with('(') || before.ends_with(',') {
                    continue;
                }
                found += 1;
            }
            let contents: Vec<String> = self.contents_write.find_iter(line).iter().map(|m| py_strip(m.as_str()).to_string()).collect();
            // Asked only about a line that would otherwise count.
            if (found > 0 || !contents.is_empty()) && !out.allowed(f, number, "containment") {
                for _ in 0..found {
                    out.site_msg("raw_writes", number, "loc =");
                }
                for what in contents {
                    out.site_msg("raw_writes", number, what);
                }
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/containment_lint.py"],
            old_raw: &[&["tools/ci/containment_lint.py", "--report"]],
            blank: &[],
            // `file:line: what`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Containment {
        loc_write: Pat::new(r"(?<![\w])loc\s*=(?!=)"),
        contents_write: Pat::new(
            r"(?<![\w])contents\s*(?:\+=|-=|\|=|&=)|(?<![\w])contents\s*\.\s*(?:Add|Remove|Cut|Insert|Swap)\s*\(",
        ),
        declaration: Pat::new(r"var/(?:[\w/]+/)?loc\s*="),
    });
}
