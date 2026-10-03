//! Port of `tools/ci/instance_list_lint.py`: type-level list vars that allocate a list for every
//! instance (AGENTS.md section 3a).
//!
//! `var/list/foo = list()` (or `new/list`, `new()`, `list/foo[4]`) in a type body runs once per
//! instance at creation, so every instance gets its own list even if it never uses it. A declaration
//! that really is per-instance and non-empty carries `// ALLOW(instance_list): <reason>`; legacy ones
//! live in `tools/ci/instance_list_baseline.txt`. Singletons (`dm::singletons`) are exempt; unit
//! tests, benchmarks and the vendored TGS DMAPI are exempt by path (`[lint.instance_list]` in
//! `tools/ci/lint_scopes.toml`, the old `allow_annotations.exempt_path()`).
//!
//! Quirks kept from the Python:
//! * the scan is an `os.walk` of `code/` (dot-files and dot-directories included);
//! * a declaration is reported once per `type/var` name across the whole tree: `found.setdefault`
//!   keeps the first one in `os.walk` order (`dm::walk::walk_order`), and later ones are dropped, but
//!   the ALLOW question is still asked about each (an annotated first declaration does not hide a
//!   second, unannotated one);
//! * the sites are emitted sorted as the strings `"rel:line"` (so `:10` sorts before `:9`);
//! * indentation is counted in tabs only: a space-indented line is at depth 0, where it is read as a
//!   type header or a top-level proc;
//! * at depth 0 the shared-modifier test is a substring test on the modifier text
//!   (`var/staticky/list/x` counts as `static`), inside a type body it is an exact segment test;
//! * `GLOBAL_DATUM_INIT` singletons are never found (see `dm::singletons`): only the two root prefixes
//!   exempt a singleton.

use std::collections::{BTreeSet, HashMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::dm::ownership_index as oi;
use crate::dm::singletons::is_singleton;
use crate::dm::walk::walk_order;
use crate::incr;
use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::Parity;
use crate::pat::Pat;
use crate::tree::{Select, SourceFile};
use crate::{pat, pat_match};
use crate::util::{py_rstrip, py_strip};

const BASELINE: &str = "tools/ci/instance_list_baseline.txt";
const LINT: &str = "instance_list";
const SHARED_MODS: &[&str] = &["static", "global", "const"];

static META: Meta = Meta {
    name: "instance_list",
    group: "",
    label: "instance_list",
    legacy: "tools/ci/instance_list_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Per-instance list declarations not yet reasoned about (tools/ci/instance_list_lint.py).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: convert (AGENTS.md 3a) or give a real",
            "`// ALLOW(instance_list): <reason>`, then `python tools/ci/instance_list_lint.py --update`.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta {
        name: "instance_list",
        hint: "allocates a list per instance: use a static var or getter (constant table), a lazy list (usually empty) or a shared copy-on-write list (AGENTS.md 3a); if it really is per-instance and always filled, mark it `// ALLOW(instance_list): <reason>`",
    }],
    allow: &["instance_list"],
    lists: &[],
};

/// `var/[mods/]list/[typed/path/]name = list(...) | new/list(...) | new(...) | new`.
fn init_re() -> &'static Pat {
    pat_match!(
        r"^(?:var/)?((?:\w+/)*?)list/(?:\w+/)*?(\w+)\s*(?:=\s*(?:list\s*\(|alist\s*\(|new\s*/list|new\s*\(|new\s*$)|\[\s*\w+\s*\])"
    )
}

/// `strip_comment`: cut a `//` that is not inside a string (an escaped quote is skipped, as the
/// Python's `text[i - 1] != "\\"` does).
fn strip_comment(text: &str) -> &str {
    let mut in_str: Option<char> = None;
    let mut prev = '\0';
    for (i, ch) in text.char_indices() {
        if let Some(q) = in_str {
            if ch == q && prev != '\\' {
                in_str = None;
            }
        } else if ch == '"' || ch == '\'' {
            in_str = Some(ch);
        } else if text[i..].starts_with("//") {
            return py_rstrip(&text[..i]);
        }
        prev = ch;
    }
    py_rstrip(text)
}

/// `indent_of`: the number of leading tabs.
fn indent_of(line: &str) -> usize {
    line.len() - line.trim_start_matches('\t').len()
}

/// `scan_file`: `(type_path, var_name, line number)` of every per-instance list declaration.
fn scan_decls(f: &SourceFile) -> Vec<(String, String, usize)> {
    let mut found = Vec::new();
    let mut type_path: Option<String> = None;
    let mut in_proc = false;
    let mut proc_indent = 0usize;
    let mut var_block: Option<(usize, String)> = None; // (indent, modifiers) of an open `var` block
    let mut in_comment = false;
    for (number, raw) in f.raw().numbered() {
        let line = raw.trim_end_matches('\r');
        let stripped = py_strip(line);
        if in_comment {
            if stripped.contains("*/") {
                in_comment = false;
            }
            continue;
        }
        if stripped.starts_with("/*") && !stripped.contains("*/") {
            in_comment = true;
            continue;
        }
        if stripped.is_empty() || stripped.starts_with("//") || stripped.starts_with('#') {
            continue;
        }
        let depth = indent_of(line);
        let body = strip_comment(stripped);
        if depth == 0 {
            var_block = None;
            in_proc = false;
            type_path = None;
            if body.contains('(') {
                in_proc = true; // a top-level proc definition
                continue;
            }
            if !body.starts_with('/') {
                continue;
            }
            if let Some(m) = pat_match!(r"^(/[\w/]+?)/var/(.*)$").captures(body) {
                let candidate = format!("var/{}", m.s(2));
                if let Some(decl) = init_re().captures(&candidate) {
                    // A substring test on the modifier text, not a segment test.
                    if !SHARED_MODS.iter().any(|s| decl.s(1).contains(s)) {
                        found.push((m.s(1).to_string(), decl.s(2).to_string(), number));
                    }
                }
                continue;
            }
            type_path = Some(py_strip(body.trim_end_matches('{')).to_string());
            continue;
        }
        let Some(tp) = type_path.as_ref() else { continue };
        if in_proc {
            if depth > proc_indent {
                continue;
            }
            in_proc = false;
        }
        if let Some((d, _)) = &var_block {
            if depth <= *d {
                var_block = None;
            }
        }
        if var_block.is_none() && pat_match!(r"^(?:(?:proc|verb)/)?\w+\(.*\)\s*$").is_match(body) {
            in_proc = true;
            proc_indent = depth;
            continue;
        }
        if var_block.is_none() && pat_match!(r"^var(?:/(?:static|global|tmp|const))*$").is_match(body) {
            var_block = Some((depth, body[3..].trim_matches('/').to_string()));
            continue;
        }
        let candidate = if body.starts_with("var/") {
            body.to_string()
        } else if let Some((_, mods)) = &var_block {
            format!("var/{}{}{}", mods, if mods.is_empty() { "" } else { "/" }, body)
        } else {
            continue;
        };
        if let Some(decl) = init_re().captures(&candidate) {
            if !decl.s(1).split('/').any(|m| SHARED_MODS.contains(&m)) {
                found.push((tp.clone(), decl.s(2).to_string(), number));
            }
        }
    }
    found
}

/// One file's contribution: its per-instance list declarations and the `GLOBAL_DATUM_INIT` types
/// it creates.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    decls: Vec<(String, String, u32)>,
    globals: Vec<String>,
}

/// One file's declarations that survive the singleton and ALLOW questions.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Judged {
    decls: Vec<(String, String, u32)>,
    uses: Vec<AllowUse>,
}

fn facts_of(f: &SourceFile) -> Facts {
    let decls = scan_decls(f).into_iter().map(|(t, v, n)| (t, v, n as u32)).collect();
    let mut globals: Vec<String> = Vec::new();
    if f.rel.starts_with("code/") {
        let text = f.raw().text.as_str();
        if text.contains("GLOBAL_DATUM_INIT") {
            // The trailing `\x08` is the Python's literal backspace (see `dm::singletons`).
            for m in pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\x08").captures_iter(text) {
                globals.push(m.s(1).to_string());
            }
        }
    }
    globals.sort();
    globals.dedup();
    Facts { decls, globals }
}

struct InstanceList;

impl Lint for InstanceList {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let facts: Vec<Facts> = oi::sharded_facts("instance-list-facts", &all, facts_of);
        // `singleton_types`: the exact types a `GLOBAL_DATUM_INIT(...)` creates anywhere under `code/`
        // (never `/datum`); only the two root prefixes ever exempt one in practice (see its docs).
        let mut globals: BTreeSet<String> = BTreeSet::new();
        for x in &facts {
            globals.extend(x.globals.iter().cloned());
        }
        globals.remove("/datum");
        let globals: HashSet<String> = globals.into_iter().collect();
        let mut sorted: Vec<&String> = globals.iter().collect();
        sorted.sort();
        let key = incr::ctx_key(&sorted);
        let by_rel: HashMap<&str, &Facts> = all.iter().zip(facts.iter()).map(|(f, x)| (f.rel.as_str(), x)).collect();
        // `found.setdefault(f"{type_path}/{var_name}", f"{rel}:{number}")`, files in os.walk order.
        let files = walk_order(&cx.files());
        let judged: Vec<Judged> = oi::sharded_keyed("instance-list-judge", key, &files, |f| {
            let mut sink = Sink::new();
            let mut j = Judged::default();
            if let Some(x) = by_rel.get(f.rel.as_str()) {
                for (type_path, var_name, number) in &x.decls {
                    if is_singleton(type_path, &globals) || sink.allowed(f, *number as usize, LINT) {
                        continue;
                    }
                    j.decls.push((type_path.clone(), var_name.clone(), *number));
                }
            }
            j.uses = sink.allow_used;
            j
        });
        let mut seen: HashSet<String> = HashSet::new();
        let mut found: Vec<(String, &str, usize)> = Vec::new();
        for (f, j) in files.iter().zip(judged) {
            for u in j.uses {
                if !out.allow_used.contains(&u) {
                    out.allow_used.push(u);
                }
            }
            for (type_path, var_name, number) in j.decls {
                if seen.insert(format!("{}/{}", type_path, var_name)) {
                    found.push((format!("{}:{}", f.rel, number), f.rel.as_str(), number as usize));
                }
            }
        }
        // `sorted(found.values())`: the strings, not (file, number).
        found.sort_by(|a, b| a.0.cmp(&b.0));
        for (_, rel, number) in found {
            out.site_in(LINT, rel, number);
        }
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/instance_list_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/instance_list_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/instance_list_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(InstanceList);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decls(text: &str) -> Vec<(String, String, usize)> {
        scan_decls(&SourceFile::from_text("code/a.dm", text))
    }

    #[test]
    fn strip_comment_respects_strings() {
        assert_eq!(strip_comment("a = 1 // c"), "a = 1");
        assert_eq!(strip_comment("a = \"x//y\" // c"), "a = \"x//y\"");
        assert_eq!(strip_comment("a = \"x\\\"//y\""), "a = \"x\\\"//y\"");
        assert_eq!(strip_comment("a = 'x' // c  "), "a = 'x'");
        assert_eq!(strip_comment("no comment   "), "no comment");
    }

    #[test]
    fn reads_blocks_procs_and_depth_zero_paths() {
        let got = decls(
            "/obj/a\n\tvar/list/x = list()\n\tvar/static/list/y = list()\n\tvar\n\t\tlist/z = list()\n\t\tstatic/list/w = list()\n\tproc/p()\n\t\tvar/list/inproc = list()\n\tvar/list/after = new\n/obj/b/var/list/c = list()\n/obj/b/var/list/c2 = new\n/obj/b/var/list/c3[4]\n/obj/b/var/static/list/d = new\n/obj/b/var/staticky/list/e = new\n",
        );
        let names: Vec<String> = got.iter().map(|(t, n, l)| format!("{}/{}:{}", t, n, l)).collect();
        // A depth-0 declaration with parentheses is read as a top-level proc (quirk), and the
        // modifier test there is a substring test.
        assert_eq!(names, ["/obj/a/x:2", "/obj/a/z:5", "/obj/a/after:9", "/obj/b/c2:11", "/obj/b/c3:12"]);
    }

    #[test]
    fn spaces_do_not_indent_and_comments_hide() {
        assert!(decls("/obj/a\n var/list/x = list()\n").is_empty());
        assert!(decls("/obj/a\n\t/*\n\tvar/list/x = list()\n\t*/\n\t// var/list/y = list()\n").is_empty());
        assert_eq!(decls("/obj/a {\n\tvar/list/x = list()\n").len(), 1);
    }
}
