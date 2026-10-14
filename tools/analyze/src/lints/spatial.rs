//! Port of `tools/ci/spatial_lint.py`: raw reads of `contents` / `loc` (roadmap C11,
//! doc/rewrite/containment.md section 2a).
//!
//! `containment` catches raw writes; this catches raw reads that should go through the ledger read
//! API or the spatial API. Four patterns, each its own rule: an explicit `in X.contents` loop, an
//! implicit loop over `src` / `loc` / `T` / ..., `contents.len` / `length(contents)`, and a
//! `locate(...) in` over a raw list. An outright ban: a site that is right as it is carries
//! `// ALLOW(spatial): <reason>`.
//!
//! Quirks kept: the files that implement the ledger and spatial API (`api_prefixes` / `api_files`
//! in `[lint.spatial.lists]`) are scanned all the same and only their sites dropped, so an
//! ALLOW annotation there still records as used; the ALLOW question is asked once per line and only
//! for a line that has a site; the message is the match text, stripped.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{py_strip, starts_with_any};

const HINT: &str = "use contents_of()/FOR_CONTENTS/is_inside()/locate_within()/contents_count()/locate_in_list() or the ledger read API (doc/rewrite/containment.md section 2a); a justified keep takes `// ALLOW(spatial): <reason>`";

static META: Meta = Meta {
    name: "spatial",
    group: "",
    label: "spatial",
    legacy: "tools/ci/spatial_lint.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "contents_loop", hint: HINT },
        RuleMeta { name: "implicit_loop", hint: HINT },
        RuleMeta { name: "contents_len", hint: HINT },
        RuleMeta { name: "locate_in", hint: HINT },
    ],
    allow: &["spatial"],
    lists: &["api_prefixes", "api_files"],
};

const IMPLICIT_IDENTS: &str = r"(?:src|loc|T|H|M|A|AM|holder|container)";

struct Spatial {
    /// `(rule, pattern)`, in the Python's PATTERNS order.
    patterns: Vec<(&'static str, Pat)>,
}

impl Spatial {
    fn new() -> Spatial {
        Spatial {
            patterns: vec![
                ("contents_loop", Pat::new(r"\bin\s+[\w.:]*\.contents\b")),
                ("implicit_loop", Pat::new(&format!(r"\bin\s+{}\s*\)", IMPLICIT_IDENTS))),
                ("contents_len", Pat::new(r"\bcontents\s*\.\s*len\b|\blength\s*\(\s*contents\s*\)")),
                // The negative lookahead excludes the correct idiom: `locate(X) in slot_contents(...)`
                // (or any other ledger/spatial read call) is a locate over a list the approved API
                // already returned.
                (
                    "locate_in",
                    Pat::new(
                        r"\blocate\s*\([^()]*\)\s*in\s+(?!(?:[\w.]+\.)?(?:slot_contents|latent_entries|latent_materialize_all|get_all_contents|turf_contents_of_type|area_contents_of_type|contents_property|contents_of)\s*\()",
                    ),
                ),
            ],
        }
    }
}

impl Lint for Spatial {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        // Files that implement the ledger/spatial API touch raw contents/loc/locate freely: scanned,
        // never counted.
        let is_api = cx.list("api_files").iter().any(|a| *a == f.rel) || starts_with_any(&f.rel, cx.list("api_prefixes"));
        for (number, line) in f.code().numbered() {
            let mut found: Vec<(&str, String)> = Vec::new();
            for (rule, pat) in &self.patterns {
                // Every pattern needs one of these words (a cheap guard before the regex runs).
                let needed = match *rule {
                    "locate_in" => "locate",
                    "contents_loop" | "contents_len" => "contents",
                    _ => "in",
                };
                if !line.contains(needed) {
                    continue;
                }
                for m in pat.find_iter(line) {
                    found.push((rule, py_strip(m.as_str()).to_string()));
                }
            }
            // Asked only about a line that would otherwise count.
            if found.is_empty() || out.allowed(f, number, "spatial") || is_api {
                continue;
            }
            for (rule, snippet) in found {
                out.site_msg(rule, number, snippet);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/spatial_lint.py"],
            old_raw: &[&["tools/ci/spatial_lint.py", "--report"]],
            blank: &[],
            // `file:line: kind: text`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Spatial::new());
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scopes::LintScope;
    use crate::tree::Tree;

    fn scan(rel: &str, text: &str) -> Sink {
        let mut scope = LintScope::default();
        scope.lists.insert("api_prefixes".to_string(), vec!["code/datums/containment/".to_string()]);
        scope.lists.insert("api_files".to_string(), vec!["code/__defines/containment.dm".to_string()]);
        let tree = Tree::from_files(vec![]);
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text(rel, text);
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        Spatial::new().scan_file(&cx, &f, &mut out);
        out
    }

    const TEXT: &str = "for(var/I in X.contents) // ALLOW(spatial): the API walks the raw list on purpose\nfor(var/I in X.contents)\nvar/x = 1 // ALLOW(spatial): nothing on this line is a raw read\n";

    #[test]
    fn api_files_drop_their_sites_but_record_the_allow() {
        for rel in ["code/datums/containment/api.dm", "code/__defines/containment.dm"] {
            let out = scan(rel, TEXT);
            assert!(out.sites.is_empty(), "{}: {:?}", rel, out.sites);
            assert_eq!(out.allow_used.len(), 1, "{}: {:?}", rel, out.allow_used);
            assert_eq!(out.allow_used[0].line, 1);
        }
    }

    #[test]
    fn other_files_count_the_unkept_site_and_record_the_allow() {
        let out = scan("code/modules/x.dm", TEXT);
        assert_eq!(out.sites.len(), 1);
        assert_eq!((out.sites[0].rule.as_str(), out.sites[0].line), ("contents_loop", 2));
        assert_eq!(out.allow_used.len(), 1);
    }
}
