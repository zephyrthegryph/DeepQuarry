//! `ref_text`: a stored `REF()` / `\ref[]` text names an entity by a string nothing clears or checks
//! (doc/rewrite/proposals/relations.md D9).
//!
//! A REF text may be built and resolved inside one request (a Topic href `?src=[REF(src)]`). It is never stored: a var, a list member or
//! key, a deferred argument holds a relation (possibly `weak = TRUE`) in content, or an `entity_handle()` token in data.
//!
//! Rules:
//! * `stored`: a `REF(...)` result assigned to a var, added to a list, or used as a list key.
//! * `ref_macro`: a `\ref[...]` text in code (hrefs are most of them; the rest are unclassified), a ratchet that only falls.
//!
//! Engine tables that key their own staleness by REF text are exempt by path (`[lint.ref_text] exempt_prefixes`), as are tests.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const H_STORED: &str = "do not store a REF() text: hold a relation (ref_one / ref_many, weak = TRUE when only a null check is needed) in content, or an entity_handle() token in data; \
build and resolve a REF text inside one request only. doc/rewrite/proposals/relations.md D9";
const H_MACRO: &str = "a \\ref[] text is built and resolved inside one request (a Topic href); anything that outlives the request holds a relation or an entity_handle() token. \
doc/rewrite/proposals/relations.md D9";

static META: Meta = Meta {
    name: "ref_text",
    group: "",
    label: "ref_text",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/ref_text_baseline.txt",
        header: &[
            "Stored REF() texts and \\ref[] macros (doc/rewrite/proposals/relations.md D9). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: after a sweep run `analyze baseline --update --lint ref_text`; it drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "stored", hint: H_STORED }, RuleMeta { name: "ref_macro", hint: H_MACRO }],
    allow: &[],
    lists: &[],
};

struct RefText {
    stored: Vec<Pat>,
    macro_: Pat,
}

impl RefText {
    fn new() -> RefText {
        RefText {
            stored: vec![
                // var = REF(x), var += REF(x), var |= REF(x), var/x = REF(x)
                Pat::new(r"(?<![=!<>])(?:\+|\||-)?=(?!=)\s*REF\("),
                // L[REF(x)] = ...
                Pat::new(r"\[\s*REF\([^\]]*\)\s*\]\s*(?:\+|\||-)?=(?!=)"),
                // LAZYADD(L, REF(x)) and the other list macros, L.Add(REF(x)), list(REF(x) = v)
                Pat::new(r"\b(?:LAZYADD|LAZYOR|LAZYSET|LAZYINITLIST)\s*\([^,()]+,\s*REF\("),
                Pat::new(r"\.(?:Add|Insert)\([^()]*\bREF\("),
                Pat::new(r"\blist\([^)]*\bREF\([^)]*\)\s*=[^=]"),
            ],
            macro_: Pat::new(r"\\ref\["),
        }
    }
}

impl Lint for RefText {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let code = f.code();
        let raw = f.raw();
        for (i, line) in code.lines().enumerate() {
            let n = i + 1;
            let t = line.trim_start();
            if t.starts_with('#') || t.is_empty() {
                continue;
            }
            if self.stored.iter().any(|p| p.is_match(line)) {
                out.site("stored", n);
                continue;
            }
            // \ref[ sits inside a string, which the code view blanks: look at the raw line, skipping comment lines.
            let r = raw.line(n);
            let rt = r.trim_start();
            if !rt.starts_with("//") && !rt.starts_with('*') && self.macro_.is_match(r) {
                out.site("ref_macro", n);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(RefText::new());
}
