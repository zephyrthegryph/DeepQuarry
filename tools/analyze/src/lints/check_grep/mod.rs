//! Port of `tools/ci/check_grep.sh`: about seventy `rg`/`grep` checks over `code/**/*.dm` and
//! `maps/**/*.dmm`, a few file checks (the TGM test, the pinned changelog example, `*.jsx`, the
//! example config), the `ambiguous` count ratchets, and `tools/TagMatcher/tag-matcher.py`.
//!
//! Every check is a [`framework::Part`], a few lines of data in `parts_*.rs` (the search and the
//! `grep -v` stages after it). One rule per part, named by the slug of the script's `part "..."`
//! title; a second check under the same title is `<slug>__<what>`. The count ratchets
//! (`admin_hits`, `fire_act`, `ex_act`, `atom_break`, `New`, `slot_flags`) are per-rule ceilings in
//! `[lint.check_grep.ceilings]`; the colour-macro count is `MACRO_COUNT` from `dependencies.sh`.
//! Path allowlists are `[lint.check_grep.lists]` in `tools/ci/lint_scopes.toml`.
//!
//! Quirks kept on purpose (do not fix them here):
//! * `wrongly offset APCs` is `grep A || grep B || grep C`: only the first alternative with a hit
//!   reports (group `apc`).
//! * a `$grep` rule drops a hit whose own line carries `ALLOW(check_grep): reason`; a plain `grep`
//!   rule never looks (see [`framework::Allow`]).
//! * the `.proc ref syntax` / `proc ref syntax` and `ambiguous bitwise or` parts are listed twice in
//!   the script with identical commands: one rule each.

mod framework;
mod parts_code_a;
mod parts_code_b;
mod parts_maps;
mod parts_pcre;
mod tags;

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::path::Path;

use md5::{Digest, Md5};

use crate::baseline::Mode;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, Run, RuleMeta, ScanKind, Sink, Site};
use crate::parity::{base_rule, Finding, ParseKind, Parity, COUNT_PATH, DME_PATH, SINGLE_FILE_PATH};
use crate::scopes::LintScope;
use crate::tree::{SourceFile, Tree};
use framework::*;

const RULE_SEEDS: &str = "r10_bindings_init_seeds_referenced_outside_a_var_edit";
const RULE_READERS: &str = "r10_bindings_no_member_var_caching_of_a_binding_read";
const RULE_DEFINES: &str = "thermal_constants_generated_not_redefined_h1";
const RULE_DME: &str = "test_map_included";
const RULE_CHANGELOG: &str = "changelog";
const RULE_JSX: &str = "typescript_react_files";
const RULE_TOAST: &str = "blocking_shell_toast_enabled_in_example_config";
const RULE_MACROS: &str = "color_macros";

const SEEDS_FILE: &str = "code/__defines/verdigris/_bindings_types.dm";
const BINDINGS_FILE: &str = "code/__defines/verdigris/_bindings.dm";
const CHANGELOG_EXAMPLE: &str = "html/changelogs/example.yml";
const CHANGELOG_MD5: &str = "0c56937110d88f750a32d9075ddaab8b";
const CONFIG_EXAMPLE: &str = "config/example/config.txt";

/// Every part, in the order of the script.
pub fn all_parts() -> Vec<Part> {
    let mut v = parts_maps::parts();
    v.extend(parts_code_a::parts());
    v.extend(parts_code_b::parts());
    v.extend(parts_pcre::parts());
    v
}

struct CheckGrep {
    /// The checks, as data; compiled (about 100 ms of regexes) only when a scan really runs, so a run that
    /// hits the cache never pays for them.
    parts: Vec<Part>,
    compiled: std::sync::OnceLock<Vec<Compiled>>,
    /// rule -> group (`a || b || c` alternatives)
    groups: BTreeMap<&'static str, &'static str>,
    /// `grep -R` over a single file operand prints no file name: parity only.
    single_file: Vec<&'static str>,
    meta: &'static Meta,
}

impl CheckGrep {
    fn new() -> CheckGrep {
        let parts = all_parts();
        let rules: Vec<RuleMeta> =
            parts.iter().map(|p| RuleMeta { name: p.rule, hint: Box::leak(p.hint().into_boxed_str()) }).collect();
        let mut keys: Vec<&'static str> = Vec::new();
        for p in &parts {
            for f in &p.flt {
                if let Flt::DropPaths(k) | Flt::KeepPaths(k) = f {
                    if !keys.contains(k) {
                        keys.push(k);
                    }
                }
            }
        }
        // read by the dynamic parts of scan_tree
        for k in ["verdigris_defines_allow", "bindings_file_allow"] {
            if !keys.contains(&k) {
                keys.push(k);
            }
        }
        let groups = parts.iter().filter(|p| !p.group.is_empty()).map(|p| (p.rule, p.group)).collect();
        let single_file = parts
            .iter()
            .filter(|p| matches!(p.files, Files::Under(paths, _) if paths.len() == 1 && paths[0].ends_with(".dm")))
            .map(|p| p.rule)
            .collect();
        let meta: &'static Meta = Box::leak(Box::new(Meta {
            name: "check_grep",
            group: "",
            label: "check_grep",
            legacy: "tools/ci/check_grep.sh",
            select: crate::tree::Select {
                roots: &[
                    ("code", "dm"),
                    ("code", "ts"),
                    ("code", "tsx"),
                    ("maps", "dmm"),
                    ("tgui/packages/tgui/interfaces", "dm"),
                    ("tgui/packages/tgui/interfaces", "ts"),
                    ("tgui/packages/tgui/interfaces", "tsx"),
                ],
                hidden: true,
            },
            scan: ScanKind::Both,
            policy: Policy::Custom,
            rules: Box::leak(rules.into_boxed_slice()),
            allow: &["check_grep"],
            lists: Box::leak(keys.into_boxed_slice()),
        }));
        CheckGrep { parts, compiled: std::sync::OnceLock::new(), groups, single_file, meta }
    }

    fn compiled(&self) -> &[Compiled] {
        self.compiled.get_or_init(|| self.parts.iter().map(|p| p.compile()).collect())
    }
}

// ---- tree-level checks ---------------------------------------------------------------------

/// `*.dme` at the repo root (the shell glob skips dot-files), sorted.
fn dme_files(root: &Path) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(root)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
                .filter_map(|e| e.file_name().into_string().ok())
                .filter(|n| n.ends_with(".dme") && !n.starts_with('.'))
                .collect()
        })
        .unwrap_or_default();
    v.sort();
    v
}

/// `tgui/**/*.jsx` by the shell glob (dot-entries skipped, links not followed), sorted.
fn jsx_files(root: &Path) -> Vec<String> {
    fn walk(dir: &Path, rel: &str, out: &mut Vec<String>) {
        let Ok(rd) = std::fs::read_dir(dir) else { return };
        for e in rd.filter_map(|e| e.ok()) {
            let Ok(name) = e.file_name().into_string() else { continue };
            if name.starts_with('.') {
                continue;
            }
            let Ok(t) = e.file_type() else { continue };
            let child = format!("{}/{}", rel, name);
            if t.is_dir() {
                walk(&e.path(), &child, out);
            } else if t.is_file() && name.ends_with(".jsx") {
                out.push(child);
            }
        }
    }
    let mut out = Vec::new();
    walk(&root.join("tgui"), "tgui", &mut out);
    out.sort();
    out
}

fn names_in(text: &str, pat: &str) -> Vec<String> {
    let rx = regex::Regex::new(pat).unwrap();
    rx.find_iter(text).map(|m| m.as_str().to_string()).collect()
}

/// `sort -u`.
fn unique(mut v: Vec<String>) -> Vec<String> {
    v.sort();
    v.dedup();
    v
}

/// The checks that read their names from the generated bindings (compiled per run).
fn dynamic_parts(cx: &Cx) -> Vec<Compiled> {
    let mut parts = Vec::new();
    if let Some(f) = cx.tree.get(SEEDS_FILE) {
        let text = f.text();
        let seeds: Vec<String> =
            unique(names_in(text, r"var/tmp/init_[A-Za-z0-9_]+").into_iter().map(|s| s.replace("var/tmp/", "")).collect());
        if !seeds.is_empty() {
            let alt = seeds.join("|");
            parts.push(
                Part::new(RULE_SEEDS, "", "", Files::Code, line(&format!(r"\b({})\b", alt)))
                    .allow(Allow::Strict)
                    .flt(vec![
                        Flt::DropPaths("verdigris_defines_allow"),
                        drop(r":\s*(//|/\*|\*)"),
                        drop(&format!(r"^[^:]+:\d+:\s*({})(\s*=\s*[^=].*)?\s*$", alt)),
                    ])
                    .compile(),
            );
        }
        let readers: Vec<String> = unique(
            names_in(text, r"proc/(get_[A-Za-z0-9_]+|[a-z][a-z0-9_]*_query_[A-Za-z0-9_]+)")
                .into_iter()
                .map(|s| s.replacen("proc/", "", 1))
                .collect(),
        );
        if !readers.is_empty() {
            let alt = readers.join("|");
            parts.push(
                Part::new(
                    RULE_READERS,
                    "",
                    "",
                    Files::Code,
                    line(&format!(r"^\s*(src\.)?[A-Za-z_][A-Za-z0-9_.]*\s*=\s*(vg_)?({})\(", alt)),
                )
                .allow(Allow::Strict)
                .flt(vec![drop(r"^[^:]+:\d+:\s*var/"), Flt::DropPaths("verdigris_defines_allow")])
                .compile(),
            );
        }
    }
    if let Some(f) = cx.tree.get(BINDINGS_FILE) {
        let rx = regex::Regex::new(r"^#define ([A-Z][A-Z0-9_]*) ").unwrap();
        let names: Vec<String> = f.text().split('\n').filter_map(|l| rx.captures(l).map(|c| c[1].to_string())).collect();
        if !names.is_empty() {
            parts.push(
                Part::new(
                    RULE_DEFINES,
                    "",
                    "",
                    Files::Code,
                    line(&format!(r"^[[:space:]]*#define[[:space:]]+({})\b", names.join("|"))),
                )
                .allow(Allow::Strict)
                .flt(vec![Flt::DropPaths("bindings_file_allow")])
                .compile(),
            );
        }
    }
    parts
}

fn strict_allowed(composite: &str) -> bool {
    static R: std::sync::LazyLock<Rx> =
        std::sync::LazyLock::new(|| Rx::new(r"ALLOW\([^)]*check_grep[^)]*\)[[:space:]]*:[[:space:]]*[^[:space:]]"));
    R.is_match(composite)
}

fn macro_count(root: &Path) -> i64 {
    let text = std::fs::read_to_string(root.join("dependencies.sh")).unwrap_or_default();
    regex::Regex::new(r"(?m)^export MACRO_COUNT=(\d+)")
        .unwrap()
        .captures(&text)
        .and_then(|c| c[1].parse().ok())
        .unwrap_or(0)
}

/// The ceiling of a counted rule: `[lint.check_grep.ceilings]`, or `MACRO_COUNT` for the colour macros.
fn ceiling_of(scope: &LintScope, root: &Path, rule: &str) -> Option<i64> {
    if rule == RULE_MACROS {
        return Some(macro_count(root));
    }
    scope.ceilings.get(rule).copied()
}

impl Lint for CheckGrep {
    fn meta(&self) -> &Meta {
        self.meta
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for c in self.compiled() {
            c.scan(cx, f, out);
        }
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let root = &cx.tree.root;
        // the checks whose pattern is read from the generated bindings
        let dynamic = dynamic_parts(cx);
        if !dynamic.is_empty() {
            // One file's findings depend on it and on the two bindings files the patterns are read from.
            let files = cx.all_files();
            let key = crate::incr::mix(&[
                cx.tree.get(SEEDS_FILE).map(|f| f.fkey).unwrap_or(0),
                cx.tree.get(BINDINGS_FILE).map(|f| f.fkey).unwrap_or(0),
            ]);
            let found = crate::dm::pylines::recorded_into(out, || {
                crate::incr::keyed("check_grep-dyn", key, &files, |f| {
                    let mut s = Sink::new();
                    s.cur = f.rel.clone();
                    for c in &dynamic {
                        c.scan(cx, f, &mut s);
                    }
                    crate::dm::sys::replay_recorded(s.allow_used);
                    s.sites.into_iter().map(|x| (x.rule, x.line, x.msg, x.key)).collect::<Vec<(String, u32, String, String)>>()
                })
            });
            for (f, sites) in files.iter().zip(found) {
                for (rule, line, msg, key) in sites {
                    out.sites.push(Site { rule, rel: f.rel.clone(), line, msg, key });
                }
            }
        }

        // `rg 'maps\\.*test.*' *.dme`
        let test_map = regex::Regex::new(r"maps\\.*test.*").unwrap();
        for dme in dme_files(root) {
            let text = String::from_utf8_lossy(&std::fs::read(root.join(&dme)).unwrap_or_default()).into_owned();
            for (i, l) in text.split('\n').enumerate() {
                if test_map.is_match(l) && !strict_allowed(&format!("{}:{}", dme, l)) {
                    out.site_in(RULE_DME, &dme, i + 1);
                }
            }
        }

        // `md5sum -c`: the example changelog is pinned
        match std::fs::read(root.join(CHANGELOG_EXAMPLE)) {
            Ok(bytes) => {
                let sum: String = Md5::digest(&bytes).iter().map(|b| format!("{:02x}", b)).collect();
                if sum != CHANGELOG_MD5 {
                    out.site_in_msg(RULE_CHANGELOG, CHANGELOG_EXAMPLE, 1, format!("md5 is {}, not {}", sum, CHANGELOG_MD5));
                }
            }
            Err(_) => out.site_in_msg(RULE_CHANGELOG, CHANGELOG_EXAMPLE, 1, "file is missing"),
        }

        // `ls -1 tgui/**/*.jsx`
        for rel in jsx_files(root) {
            out.site_in_msg(RULE_JSX, &rel, 1, "JSX file");
        }

        // `grep -Eq '^[[:space:]]*TOAST_NOTIFICATION_ON_INIT' config/example/config.txt`
        if let Ok(bytes) = std::fs::read(root.join(CONFIG_EXAMPLE)) {
            let text = String::from_utf8_lossy(&bytes);
            let toast = regex::Regex::new(r"^[[:space:]]*TOAST_NOTIFICATION_ON_INIT").unwrap();
            if let Some(i) = text.split('\n').position(|l| toast.is_match(l)) {
                out.site_in_msg(RULE_TOAST, CONFIG_EXAMPLE, i + 1, "TOAST_NOTIFICATION_ON_INIT is enabled");
            }
        }
    }

    fn extra_inputs(&self, tree: &Tree) -> Vec<String> {
        let mut v = dme_files(&tree.root);
        v.push(CHANGELOG_EXAMPLE.to_string());
        v.push(CONFIG_EXAMPLE.to_string());
        v.extend(jsx_files(&tree.root));
        v
    }

    fn finish(&self, cx: &Cx, run: &Run, text: &mut String) -> bool {
        let root = &cx.tree.root;
        let sites = first_hit_only(&self.groups, &run.sites);
        let hints: BTreeMap<&str, &str> = self.meta.rules.iter().map(|r| (r.name, r.hint)).collect();
        let mut failed = false;
        let mut by_rule: BTreeMap<&str, Vec<&Site>> = BTreeMap::new();
        for s in &sites {
            by_rule.entry(s.rule.as_str()).or_default().push(s);
        }
        for rm in self.meta.rules {
            let found = by_rule.get(rm.name).cloned().unwrap_or_default();
            let hint = hints.get(rm.name).copied().unwrap_or("");
            let body = |s: &Site| if s.msg.is_empty() { cx.tree.site_text(&s.rel, s.line as usize) } else { s.msg.clone() };
            match ceiling_of(cx.scope, root, rm.name) {
                Some(ceiling) => {
                    let count = found.len() as i64;
                    let status = if count > ceiling {
                        failed = true;
                        format!("FAIL (rose above its ceiling {})", ceiling)
                    } else if count < ceiling {
                        format!("below ceiling {}: lower it with `analyze baseline --update`", ceiling)
                    } else {
                        "ok".to_string()
                    };
                    let _ = writeln!(text, "check_grep {:<19} {:>6}  (ceiling {})  {}", rm.name, count, ceiling, status);
                    if count > ceiling {
                        for s in found.iter().take(60) {
                            let _ = writeln!(text, "{}:{}: [check_grep/{}] {} -- {}", s.rel, s.line, rm.name, body(s), hint);
                        }
                        if found.len() > 60 {
                            let _ = writeln!(text, "... and {} more", found.len() - 60);
                        }
                    }
                }
                None => {
                    for s in found {
                        failed = true;
                        let _ = writeln!(text, "{}:{}: [check_grep/{}] {} -- {}", s.rel, s.line, rm.name, body(s), hint);
                    }
                }
            }
        }
        failed
    }

    fn update_baseline(&self, cx: &Cx, run: &Run, mode: Mode) -> std::io::Result<String> {
        let path = cx.tree.root.join("tools").join("ci").join("lint_scopes.toml");
        let sites = first_hit_only(&self.groups, &run.sites);
        let mut note = String::new();
        for (rule, &ceiling) in cx.scope.ceilings.iter() {
            let count = sites.iter().filter(|s| s.rule == *rule).count() as i64;
            let new = match mode {
                Mode::Update => ceiling.min(count),
                Mode::Seed => count,
            };
            if new != ceiling {
                crate::scopes::write_ceiling(&path, "check_grep", rule, new)?;
                note.push_str(&format!(" ceiling {} {} -> {};", rule, ceiling, new));
            }
        }
        Ok(format!("check_grep: ceilings in tools/ci/lint_scopes.toml;{}", note))
    }

    fn parity_normalize(&self, root: &Path, scope: &LintScope, findings: Vec<Finding>) -> Vec<Finding> {
        // the old `a || b || c`
        let sites: Vec<Site> = findings
            .into_iter()
            .map(|f| Site { rule: f.rule, rel: f.rel, line: f.line, msg: String::new(), key: String::new() })
            .collect();
        let sites = first_hit_only(&self.groups, &sites);
        let mut out: Vec<Finding> = Vec::new();
        let mut counted: BTreeMap<String, i64> = BTreeMap::new();
        for s in sites {
            if ceiling_of(scope, root, &s.rule).is_some() {
                // the script prints only the number of a counted rule, and only above its limit
                *counted.entry(s.rule.clone()).or_default() += 1;
                continue;
            }
            let rel = if s.rule == RULE_DME {
                DME_PATH.to_string()
            } else if self.single_file.contains(&s.rule.as_str()) {
                SINGLE_FILE_PATH.to_string()
            } else {
                s.rel
            };
            out.push(Finding { rule: base_rule(&s.rule).to_string(), rel, line: s.line });
        }
        for (rule, n) in counted {
            let limit = ceiling_of(scope, root, &rule).unwrap_or(0);
            if n > limit {
                out.push(Finding { rule: base_rule(&rule).to_string(), rel: COUNT_PATH.to_string(), line: n as u32 });
            }
        }
        out.sort();
        out.dedup_by(|a, b| a.line > 0 && a == b);
        out
    }

    fn selftest(&self) -> Result<String, String> {
        let tree = Tree::from_files(vec![]);
        let scope = LintScope::default();
        let cx = Cx { tree: &tree, meta: self.meta, scope: &scope };
        let run = |rel: &str, text: &str| -> Vec<(String, usize)> {
            let f = SourceFile::from_text(rel, text);
            let mut out = Sink::new();
            out.cur = f.rel.clone();
            self.scan_file(&cx, &f, &mut out);
            out.sites.iter().map(|s| (s.rule.clone(), s.line as usize)).collect()
        };
        let got = run("code/a.dm", "/mob/proc/Life()\n  x\n\tisSynthetic(M) // ALLOW(check_grep): kept\n\tisSynthetic(M)\nno newline");
        let want = vec![
            ("life_no_life_procs".to_string(), 1usize),
            ("space_indentation".to_string(), 2),
            ("biology_no_issynthetic".to_string(), 4),
            ("trailing_newlines".to_string(), 5),
        ];
        let mut got = got;
        got.sort_by_key(|(_, l)| *l);
        if got != want {
            return Err(format!("unexpected sites {:?}", got));
        }
        Ok(String::new())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/check_grep.sh"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::CheckGrep,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

/// `a || b || c` of the script: keep only the sites of the first rule of each group that has any.
fn first_hit_only(groups: &BTreeMap<&'static str, &'static str>, sites: &[Site]) -> Vec<Site> {
    let mut order: Vec<(&str, &str)> = groups.iter().map(|(r, g)| (*r, *g)).collect();
    // alternatives run in the order the script lists them: the rule names sort that way
    // (`x`, `x__2`, `x__3`)
    order.sort();
    let mut winner: BTreeMap<&str, &str> = BTreeMap::new();
    for (rule, group) in order {
        if sites.iter().any(|s| s.rule == rule) {
            winner.entry(group).or_insert(rule);
        }
    }
    sites
        .iter()
        .filter(|s| match groups.get(s.rule.as_str()) {
            Some(g) => winner.get(g) == Some(&s.rule.as_str()),
            None => true,
        })
        .cloned()
        .collect()
}

pub fn register(reg: &mut Registry) {
    reg.add(CheckGrep::new());
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parity::slug;

    #[test]
    fn rule_names_follow_the_part_titles() {
        let parts = all_parts();
        let mut seen = std::collections::HashSet::new();
        for p in &parts {
            assert!(seen.insert(p.rule), "duplicate rule {}", p.rule);
            assert_eq!(base_rule(p.rule), slug(p.title), "rule {} vs title {:?}", p.rule, p.title);
        }
    }

    #[test]
    fn every_part_compiles_and_meta_lists_its_scope_keys() {
        let l = CheckGrep::new();
        assert!(l.meta.rules.len() >= 90);
        for k in ["call_ext_allow", "machinery_qdel_allow", "verdigris_defines_allow"] {
            assert!(l.meta.lists.contains(&k), "{}", k);
        }
    }

    #[test]
    fn first_hit_group_keeps_only_the_first_alternative() {
        let mut groups = BTreeMap::new();
        groups.insert("apc", "g");
        groups.insert("apc__2", "g");
        let site = |rule: &str| Site { rule: rule.into(), rel: "maps/a.dmm".into(), line: 1, msg: String::new(), key: String::new() };
        let sites = vec![site("apc__2"), site("other")];
        assert_eq!(first_hit_only(&groups, &sites).len(), 2);
        let sites = vec![site("apc__2"), site("apc"), site("other")];
        let kept: Vec<String> = first_hit_only(&groups, &sites).into_iter().map(|s| s.rule).collect();
        assert_eq!(kept, vec!["apc".to_string(), "other".to_string()]);
    }

    fn sites_of(rule: &str, rel: &str, text: &str) -> Vec<usize> {
        let l = CheckGrep::new();
        let tree = Tree::from_files(vec![]);
        let scope = LintScope::default();
        let cx = Cx { tree: &tree, meta: l.meta, scope: &scope };
        let f = SourceFile::from_text(rel, text);
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        l.scan_file(&cx, &f, &mut out);
        out.sites.iter().filter(|s| s.rule == rule).map(|s| s.line as usize).collect()
    }

    /// The three `grep -Pzo` alternatives of "wrongly offset APCs", on the text GNU grep 3.0 gave
    /// 3, 5 and 2 matches for (checked by hand with `grep -Pzo`, the shell script's own command).
    #[test]
    fn apc_alternatives_match_what_grep_pzo_matched() {
        let text = "/obj/structure/machinery/power/apc{\n\tpixel_x = 24\n\t},\n/obj/structure/machinery/power/apc/x{\n\tdir = 4;\n\tpixel_y = 100\n\t},\n/obj/structure/machinery/power/apc{\n\tpixel_y = 25\n\t},\n/obj/structure/machinery/power/apc{\n\tpixel_x = -26\n\t},\n/obj/structure/machinery/power/apc{\n\tpixel_x = 1234\n\t},\n/obj/structure/machinery/power/apc{\n\tpixel_x = 30\n\t},\n";
        assert_eq!(sites_of("wrongly_offset_apcs", "maps/a.dmm", text), vec![4, 14, 17]);
        assert_eq!(sites_of("wrongly_offset_apcs__2", "maps/a.dmm", text), vec![1, 4, 11, 14, 17]);
        assert_eq!(sites_of("wrongly_offset_apcs__3", "maps/a.dmm", text), vec![4, 14]);
    }

    #[test]
    fn multi_line_proc_argument_needs_an_unclosed_first_line() {
        let text = "/proc/a(x,\n\tvar/y)\n/proc/b(x) \n\tvar/y\n/proc/c(x, \\\n\tvar/z)\n";
        assert_eq!(sites_of("var_in_proc_args__multi_line", "code/a.dm", text), vec![1, 5]);
    }

    #[test]
    fn counted_rules_judge_by_ceiling() {
        let l = CheckGrep::new();
        let tree = Tree::from_files(vec![]);
        let mut scope = LintScope::default();
        scope.ceilings.insert("heat_ratchet_on_fire_act_overrides_h3".to_string(), 1);
        let cx = Cx { tree: &tree, meta: l.meta, scope: &scope };
        let site = |line: u32| Site {
            rule: "heat_ratchet_on_fire_act_overrides_h3".into(),
            rel: "code/a.dm".into(),
            line,
            msg: "x".into(),
            key: String::new(),
        };
        let mut text = String::new();
        assert!(!l.finish(&cx, &Run { sites: vec![site(1)], notes: vec![] }, &mut text), "{}", text);
        let mut text = String::new();
        assert!(l.finish(&cx, &Run { sites: vec![site(1), site(2)], notes: vec![] }, &mut text));
        assert!(text.contains("FAIL (rose above its ceiling 1)"), "{}", text);
        assert!(text.contains("code/a.dm:2: [check_grep/heat_ratchet_on_fire_act_overrides_h3]"), "{}", text);
    }

    #[test]
    fn file_checks_on_a_scratch_repo() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf();
        let dir = tempfile::tempdir().unwrap();
        let w = |rel: &str, text: &[u8]| {
            let p = dir.path().join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, text).unwrap();
        };
        // the pinned example changelog passes; any other text fails
        w(CHANGELOG_EXAMPLE, &std::fs::read(root.join(CHANGELOG_EXAMPLE)).unwrap());
        w("deepquarry.dme", b"#include \"maps\\southern_cross\\ok.dm\"\n#include \"maps\\virgo_minitest\\x.dm\"\n");
        w("config/example/config.txt", b"#TOAST_NOTIFICATION_ON_INIT\n");
        w("tgui/a/b.jsx", b"");
        w("tgui/.hidden/c.jsx", b"");
        let l = CheckGrep::new();
        let mut tree = Tree::from_files(vec![]);
        tree.root = dir.path().to_path_buf();
        let scope = LintScope::default();
        let cx = Cx { tree: &tree, meta: l.meta, scope: &scope };
        let mut out = Sink::new();
        l.scan_tree(&cx, &mut out);
        let got: Vec<(String, String, u32)> = out.sites.iter().map(|s| (s.rule.clone(), s.rel.clone(), s.line)).collect();
        assert_eq!(
            got,
            vec![
                (RULE_DME.to_string(), "deepquarry.dme".to_string(), 2),
                (RULE_JSX.to_string(), "tgui/a/b.jsx".to_string(), 1),
            ]
        );
        w(CHANGELOG_EXAMPLE, b"changed\n");
        w("config/example/config.txt", b"x\n  TOAST_NOTIFICATION_ON_INIT\n");
        let mut out = Sink::new();
        l.scan_tree(&cx, &mut out);
        let rules: Vec<&str> = out.sites.iter().map(|s| s.rule.as_str()).collect();
        assert!(rules.contains(&RULE_CHANGELOG) && rules.contains(&RULE_TOAST), "{:?}", rules);
        assert_eq!(l.extra_inputs(&tree), vec!["deepquarry.dme", CHANGELOG_EXAMPLE, CONFIG_EXAMPLE, "tgui/a/b.jsx"]);
    }

    #[test]
    fn selftest_passes() {
        assert_eq!(CheckGrep::new().selftest(), Ok(String::new()));
    }
}
