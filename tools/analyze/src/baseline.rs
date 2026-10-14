//! Ratchet baselines, ported once from `tools/ci/allow_annotations.py`: the fingerprint baseline
//! (`rule<TAB>file<TAB>normalized line text`, no line numbers, so unrelated edits don't disturb it)
//! and the count-ceiling baseline (`name count`). Files are read and written in exactly the old
//! format. `Update` only ever shrinks; `Seed` records every current site.

use std::collections::{BTreeMap, HashMap};
use std::fmt::Write as _;
use std::path::Path;

use crate::lint::Site;
use crate::tree::Tree;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// `--update`: drop sites that are gone, never add one.
    Update,
    /// `--seed`: record every current site (create a baseline).
    Seed,
    /// `--migrate`: rewrite each row that matches a current site (by line text, or already by identity) as that site's identity row.
    /// Never adds or drops a row: a row no site claims is written back as it was, so the counts of a migration are exact and the
    /// command can be re-run after a merge brought the baseline back to the line-text form.
    Migrate,
}

pub type Counter = HashMap<(String, String), i64>;

/// The fingerprint text a ratchet compares for `rule`. An `init_lines` site is the job a line does in an `Initialize()` body, not
/// its spelling: a write `x = v` and the call of its setter `set_x(v)` (`src.set_x(v)`) are the same site, so converting a write to
/// its setter (which the `tracked` lint requires) neither adds a site nor hides one. Every other rule compares the text as written.
pub fn canon_text(rule: &str, text: &str) -> String {
    if rule != "init_lines" {
        return text.to_string();
    }
    let t = text.trim();
    let t = t.strip_prefix("src.").unwrap_or(t);
    if let Some(rest) = t.strip_prefix("set_") {
        if let Some(open) = rest.find('(') {
            let name = &rest[..open];
            if !name.is_empty() && name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_') && rest.ends_with(')') {
                return format!("{} = {}", name, &rest[open + 1..rest.len() - 1]);
            }
        }
    }
    text.to_string()
}

/// `read_sites`: `{rule: Counter((file, text))}`.
pub fn read_sites(path: &Path) -> BTreeMap<String, Counter> {
    let mut base: BTreeMap<String, Counter> = BTreeMap::new();
    let Ok(text) = std::fs::read_to_string(path) else { return base };
    let text = crate::util::universal_newlines(text);
    for line in text.split('\n') {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.splitn(3, '\t');
        let (Some(rule), Some(file), Some(txt)) = (parts.next(), parts.next(), parts.next()) else { continue };
        *base.entry(rule.to_string()).or_default().entry((file.to_string(), canon_text(rule, txt))).or_insert(0) += 1;
    }
    base
}

/// A site with its fingerprint text.
pub struct Fp<'a> {
    pub site: &'a Site,
    /// The line text, for the report.
    pub text: String,
    /// What the ratchet compares and the baseline stores: `@owner::var` for a declaration site (retyping or re-commenting the
    /// declaration keeps it; renaming it or moving it to another owner makes a new site), else the canonical line text.
    pub fp: String,
}

/// Marks a declaration-identity fingerprint in a baseline row's third column.
pub const IDENT_MARK: &str = "@";

/// The compared fingerprint for `site` whose line reads `text`.
pub fn fp_of(site: &Site, text: &str) -> String {
    if site.ident.is_empty() {
        canon_text(&site.rule, text)
    } else {
        format!("{}{}", IDENT_MARK, site.ident)
    }
}

pub fn fingerprints<'a>(tree: &Tree, found: &[&'a Site]) -> Vec<Fp<'a>> {
    found
        .iter()
        .map(|s| {
            let text = tree.site_text(&s.rel, s.line as usize);
            let fp = fp_of(s, &text);
            Fp { site: s, text, fp }
        })
        .collect()
}

/// `write_sites`. `rules` lists the rules to write, in order; `by_rule` maps a rule to its sites.
/// Returns the number of rows written.
pub fn write_sites(
    path: &Path,
    header: &[&str],
    tree: &Tree,
    by_rule: &[(&str, Vec<&Site>)],
    rules: &[&str],
    mode: Mode,
) -> std::io::Result<usize> {
    let old = read_sites(path);
    let mut rows: Vec<String> = Vec::new();
    let lookup: HashMap<&str, &Vec<&Site>> = by_rule.iter().map(|(r, s)| (*r, s)).collect();
    let mut rule_list: Vec<&str> = rules.to_vec();
    if rule_list.is_empty() {
        let mut keys: Vec<&str> = by_rule.iter().map(|(r, _)| *r).collect();
        keys.sort();
        rule_list = keys;
    }
    for rule in rule_list {
        let mut budget: Counter = old.get(rule).cloned().unwrap_or_default();
        let empty: Vec<&Site> = Vec::new();
        let found = lookup.get(rule).copied().unwrap_or(&empty);
        // What `check_sites` accepts of this rule against the file as it is now: an update may never keep fewer rows than that.
        let accepted = {
            let mut b: Counter = old.get(rule).cloned().unwrap_or_default();
            let mut n = 0usize;
            for fp in fingerprints(tree, found) {
                match b.get_mut(&(fp.site.rel.clone(), fp.fp.clone())) {
                    Some(c) if *c > 0 => {
                        *c -= 1;
                        n += 1;
                    }
                    _ => {}
                }
            }
            n
        };
        let rows_before = rows.len();
        let mut fps: Vec<(String, u32, String, String)> =
            fingerprints(tree, found).into_iter().map(|f| (f.site.rel.clone(), f.site.line, f.text, f.fp)).collect();
        fps.sort();
        for (rel, _n, text, fp) in fps {
            if mode == Mode::Update || mode == Mode::Migrate {
                // A row still in the line-text form (written before declaration identities) is claimed by its line text, so the
                // first `--update` after the change rewrites it as an identity row without adding or dropping one.
                let ident_key = (rel.clone(), fp.clone());
                let legacy_key = (rel.clone(), canon_text(rule, &text));
                let key = if budget.get(&ident_key).copied().unwrap_or(0) > 0 { ident_key } else { legacy_key };
                let b = budget.entry(key).or_insert(0);
                if *b <= 0 {
                    continue;
                }
                *b -= 1;
            }
            rows.push(format!("{}	{}	{}", rule, rel, if fp.starts_with(IDENT_MARK) { &fp } else { &text }));
        }
        if mode != Mode::Seed && rows.len() - rows_before < accepted {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("baseline update for `{}` would keep {} rows but the check accepts {} sites: refusing to drop a row the check still matches", rule, rows.len() - rows_before, accepted),
            ));
        }
        if mode == Mode::Migrate {
            // Rows no current site claims stay as they were (a migration changes the form of a row, never the number of rows).
            let mut rest: Vec<(&(String, String), &i64)> = budget.iter().filter(|(_, n)| **n > 0).collect();
            rest.sort();
            for ((rel, txt), n) in rest {
                for _ in 0..*n {
                    rows.push(format!("{}	{}	{}", rule, rel, txt));
                }
            }
        }
    }
    let mut out = String::new();
    let mut lines: Vec<String> = header.iter().map(|h| format!("# {}", h)).collect();
    lines.extend(rows.iter().cloned());
    out.push_str(&lines.join("\n"));
    out.push('\n');
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    std::fs::write(path, out)?;
    Ok(rows.len())
}

/// The ratchet check against a fingerprint baseline (`check_sites`). Appends the report to `out`
/// and returns true on any new site.
pub fn check_sites(
    label: &str,
    tree: &Tree,
    by_rule: &[(&str, Vec<&Site>)],
    hints: &dyn Fn(&str) -> String,
    path: &Path,
    banned: &[&str],
    out: &mut String,
) -> bool {
    let base = read_sites(path);
    let mut failed = false;
    let mut new_lines: Vec<String> = Vec::new();
    for (rule, found) in by_rule {
        let mut budget: Counter = if banned.contains(rule) { Counter::new() } else { base.get(*rule).cloned().unwrap_or_default() };
        let known: i64 = budget.values().sum();
        let mut fresh: Vec<(String, u32, String)> = Vec::new();
        for fp in fingerprints(tree, found) {
            let key = (fp.site.rel.clone(), fp.fp.clone());
            match budget.get_mut(&key) {
                Some(b) if *b > 0 => *b -= 1,
                _ => fresh.push((fp.site.rel.clone(), fp.site.line, fp.text)),
            }
        }
        let gone: i64 = budget.values().filter(|v| **v > 0).sum();
        let status = if !fresh.is_empty() {
            failed = true;
            format!("FAIL ({} new site{})", fresh.len(), if fresh.len() == 1 { "" } else { "s" })
        } else if gone > 0 {
            format!("{} baselined site{} gone: shrink the baseline with --update", gone, if gone == 1 { "" } else { "s" })
        } else {
            "ok".to_string()
        };
        let _ = writeln!(out, "{} {:<19} {:>6}  (baseline {})  {}", label, rule, found.len(), known, status);
        let hint = hints(rule);
        for (rel, number, text) in fresh {
            let suffix = if hint.is_empty() { String::new() } else { format!(" -- {}", hint) };
            new_lines.push(format!("{}:{}: [{}/{}] {}{}", rel, number, label, rule, text, suffix));
        }
    }
    if !new_lines.is_empty() {
        let _ = writeln!(out, "{}: new sites (baselined legacy sites are not listed):", label);
        for l in new_lines {
            let _ = writeln!(out, "{}", l);
        }
        let _ = writeln!(
            out,
            "Fix each site, or keep a justified one with `// ALLOW(<lint>): <reason>` (tools/ci/allow_annotations.py). Baselines only shrink."
        );
    }
    failed
}

/// `read_baseline`: `{name: ceiling}` from `name count` lines.
pub fn read_ceilings(path: &Path) -> BTreeMap<String, i64> {
    let mut base = BTreeMap::new();
    let Ok(text) = std::fs::read_to_string(path) else { return base };
    for line in crate::util::universal_newlines(text).split('\n') {
        let line = line.split('#').next().unwrap_or("");
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let mut it = line.split_whitespace();
        if let (Some(name), Some(count)) = (it.next(), it.next()) {
            if let Ok(c) = count.parse::<i64>() {
                base.insert(name.to_string(), c);
            }
        }
    }
    base
}

/// `write_baseline`.
pub fn write_ceilings(path: &Path, header: &[&str], counts: &BTreeMap<String, i64>) -> std::io::Result<()> {
    let mut lines: Vec<String> = header.iter().map(|h| format!("# {}", h)).collect();
    for (name, count) in counts {
        lines.push(format!("{} {}", name, count));
    }
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    std::fs::write(path, lines.join("\n") + "\n")
}

/// Counts of sites per `Site::key`.
pub fn key_counts(sites: &[Site]) -> BTreeMap<String, i64> {
    let mut m = BTreeMap::new();
    for s in sites {
        *m.entry(s.key.clone()).or_insert(0) += 1;
    }
    m
}

/// The ceilings check: a key above (or missing from) the baseline fails. Prints the first five
/// sites of each failing key, then one summary line (`system_boundary_lint.main`).
pub fn check_ceilings(label: &str, sites: &[Site], rules: &[&str], path: &Path, out: &mut String) -> bool {
    let base = read_ceilings(path);
    let counts = key_counts(sites);
    let mut failed = false;
    for (key, count) in &counts {
        let ceiling = base.get(key).copied();
        if ceiling.is_none() || *count > ceiling.unwrap() {
            let c = ceiling.map(|c| c.to_string()).unwrap_or_else(|| "none".to_string());
            let _ = writeln!(out, "{}: FAIL {}: {} (ceiling {})", label, key, count, c);
            for s in sites.iter().filter(|s| &s.key == key).take(5) {
                let _ = writeln!(out, "    {}:{}: {}", s.rel, s.line, s.msg);
            }
            failed = true;
        }
    }
    let lowered = base.iter().filter(|(k, v)| counts.get(*k).copied().unwrap_or(0) < **v).count();
    let mut totals: Vec<String> = Vec::new();
    for r in rules {
        let n = sites.iter().filter(|s| s.rule == *r).count();
        totals.push(format!("{}={}", r, n));
    }
    let _ = writeln!(
        out,
        "{}: {}; {}; {} entries below their ceiling (--update lowers them)",
        label,
        totals.join(", "),
        if failed { "FAILED" } else { "ok" },
        lowered
    );
    failed
}

/// `--update` for ceilings: lower each ceiling to the current count, drop keys with none.
pub fn update_ceilings(path: &Path, header: &[&str], sites: &[Site]) -> std::io::Result<usize> {
    let base = read_ceilings(path);
    let counts = key_counts(sites);
    let kept: BTreeMap<String, i64> = base
        .iter()
        .filter(|(k, _)| counts.get(*k).copied().unwrap_or(0) > 0)
        .map(|(k, v)| (k.clone(), (*v).min(counts[k])))
        .collect();
    write_ceilings(path, header, &kept)?;
    Ok(kept.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::SourceFile;

    fn site(rule: &str, rel: &str, line: u32) -> Site {
        Site { rule: rule.into(), rel: rel.into(), line, msg: String::new(), key: String::new(), ident: String::new() }
    }

    #[test]
    fn init_lines_compares_a_setter_call_as_its_write() {
        assert_eq!(canon_text("init_lines", "set_power(5)"), "power = 5");
        assert_eq!(canon_text("init_lines", "src.set_power(a, b)"), "power = a, b");
        assert_eq!(canon_text("init_lines", "power = 5"), "power = 5");
        assert_eq!(canon_text("init_lines", "set_(1)"), "set_(1)");
        assert_eq!(canon_text("init_lines", "set_a b(1)"), "set_a b(1)");
        assert_eq!(canon_text("spawn", "set_power(5)"), "set_power(5)");
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "	set_power(5)
")]);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, "# h
init_lines	code/a.dm	power = 5
").unwrap();
        let s = vec![site("init_lines", "code/a.dm", 1)];
        let refs: Vec<&Site> = s.iter().collect();
        let by_rule = vec![("init_lines", refs)];
        let mut out = String::new();
        assert!(!check_sites("init", &tree, &by_rule, &|_| String::new(), &path, &[], &mut out), "{out}");
    }

    #[test]
    fn check_sites_budgets_and_reports_new() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "spawn(1)\n\tspawn(2)\nspawn(1)\n")]);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, "# h\nspawn\tcode/a.dm\tspawn(1)\n").unwrap();
        let s = vec![site("spawn", "code/a.dm", 1), site("spawn", "code/a.dm", 2), site("spawn", "code/a.dm", 3)];
        let refs: Vec<&Site> = s.iter().collect();
        let by_rule = vec![("spawn", refs)];
        let mut out = String::new();
        let failed = check_sites("scheduler", &tree, &by_rule, &|_| "use om_after".to_string(), &path, &[], &mut out);
        assert!(failed);
        assert!(out.contains("code/a.dm:2: [scheduler/spawn] spawn(2) -- use om_after"), "{}", out);
        assert!(out.contains("code/a.dm:3: [scheduler/spawn] spawn(1)"), "{}", out);
        assert!(!out.contains("code/a.dm:1:"), "{}", out);
    }

    #[test]
    fn update_only_shrinks_and_seed_adds() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "spawn(1)\nspawn(2)\n")]);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, "# h\nspawn\tcode/a.dm\tspawn(1)\nspawn\tcode/gone.dm\tspawn(9)\n").unwrap();
        let s = vec![site("spawn", "code/a.dm", 1), site("spawn", "code/a.dm", 2)];
        let by_rule = vec![("spawn", s.iter().collect::<Vec<_>>())];
        let n = write_sites(&path, &["header"], &tree, &by_rule, &["spawn"], Mode::Update).unwrap();
        assert_eq!(n, 1);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "# header\nspawn\tcode/a.dm\tspawn(1)\n");
        let n = write_sites(&path, &["header"], &tree, &by_rule, &["spawn"], Mode::Seed).unwrap();
        assert_eq!(n, 2);
    }

    fn decl(rule: &str, rel: &str, line: u32, ident: &str) -> Site {
        Site { ident: ident.into(), ..site(rule, rel, line) }
    }

    fn check_one(tree: &Tree, base: &str, sites: &[Site]) -> (bool, String) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, base).unwrap();
        let by_rule = vec![("var", sites.iter().collect::<Vec<_>>())];
        let mut out = String::new();
        let failed = check_sites("stored_refs", tree, &by_rule, &|_| String::new(), &path, &[], &mut out);
        (failed, out)
    }

    const ROW: &str = "# h
var	code/a.dm	@/obj/x::armor_override
";

    #[test]
    fn decl_retyped_var_still_matches_its_baseline_row() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	var/tmp/datum/armor/armor_override
")]);
        let (failed, out) = check_one(&tree, ROW, &[decl("var", "code/a.dm", 2, "/obj/x::armor_override")]);
        assert!(!failed, "{out}");
    }

    #[test]
    fn decl_renamed_var_counts_as_new() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	var/tmp/datum/armor_ref
")]);
        let (failed, out) = check_one(&tree, ROW, &[decl("var", "code/a.dm", 2, "/obj/x::armor_ref")]);
        assert!(failed, "{out}");
        assert!(out.contains("code/a.dm:2:"), "{out}");
        // The same name under another owner is another var.
        let (failed, _) = check_one(&tree, ROW, &[decl("var", "code/a.dm", 2, "/obj/y::armor_override")]);
        assert!(failed);
    }

    #[test]
    fn decl_fixed_var_drops_out_on_update_and_legacy_rows_migrate_one_to_one() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	var/datum/a
	var/datum/b
")]);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        // Two line-text rows (the old format) and one identity row; `c` is fixed (no site remains).
        std::fs::write(&path, "# h
var	code/a.dm	var/datum/a
var	code/a.dm	var/datum/b
var	code/a.dm	@/obj/x::c
").unwrap();
        let s = vec![decl("var", "code/a.dm", 2, "/obj/x::a"), decl("var", "code/a.dm", 3, "/obj/x::b")];
        let by_rule = vec![("var", s.iter().collect::<Vec<_>>())];
        let n = write_sites(&path, &["h"], &tree, &by_rule, &["var"], Mode::Update).unwrap();
        assert_eq!(n, 2);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "# h
var	code/a.dm	@/obj/x::a
var	code/a.dm	@/obj/x::b
");
        // Update never adds: a site with no row stays out.
        let more = vec![decl("var", "code/a.dm", 2, "/obj/x::a"), decl("var", "code/a.dm", 3, "/obj/x::b"), decl("var", "code/a.dm", 3, "/obj/x::new")];
        let by_rule = vec![("var", more.iter().collect::<Vec<_>>())];
        assert_eq!(write_sites(&path, &["h"], &tree, &by_rule, &["var"], Mode::Update).unwrap(), 2);
    }

    const READ_ROW: &str = "# h
unknown_read	code/a.dm	@/obj/machinery/mineral/console::refresh reads /datum/sector::map_sectors
unknown_read	code/a.dm	@/obj/machinery/mineral/console::refresh reads /datum/sector::map_sectors
";

    fn read_site(line: u32, ident: &str) -> Site {
        decl("unknown_read", "code/a.dm", line, ident)
    }

    fn check_reads(tree: &Tree, sites: &[Site]) -> (bool, String) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, READ_ROW).unwrap();
        let by_rule = vec![("unknown_read", sites.iter().collect::<Vec<_>>())];
        let mut out = String::new();
        let failed = check_sites("reads", tree, &by_rule, &|_| String::new(), &path, &[], &mut out);
        (failed, out)
    }

    const READER: &str = "/obj/machinery/mineral/console::refresh reads /datum/sector::map_sectors";

    #[test]
    fn read_sites_survive_a_text_edit_a_move_and_a_reorder() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	a = map_sectors[1]
	b = edited(map_sectors)
	c = 3
")]);
        // Text edited, moved to other lines, and swapped: same identities.
        let (failed, out) = check_reads(&tree, &[read_site(3, READER), read_site(2, READER)]);
        assert!(!failed, "{out}");
    }

    #[test]
    fn a_new_read_or_a_third_read_of_a_known_key_fails_and_a_fixed_one_shrinks() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	a = map_sectors[1]
	b = map_sectors[2]
	c = map_sectors[3]
")]);
        let (failed, out) = check_reads(&tree, &[read_site(2, READER), read_site(3, READER), read_site(4, READER)]);
        assert!(failed, "{out}");
        assert!(out.contains("code/a.dm:4:"), "{out}");
        // Another var, or another reader proc, is another site.
        let (failed, _) = check_reads(&tree, &[read_site(2, READER), read_site(3, "/obj/machinery/mineral/console::refresh reads /datum/sector::other")]);
        assert!(failed);
        let (failed, _) = check_reads(&tree, &[read_site(2, READER), read_site(3, "/obj/machinery/mineral/console::other reads /datum/sector::map_sectors")]);
        assert!(failed);
        // One of the two fixed: not a failure, and `--update` drops exactly that row.
        let (failed, out) = check_reads(&tree, &[read_site(2, READER)]);
        assert!(!failed && out.contains("1 baselined site gone"), "{out}");
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, READ_ROW).unwrap();
        let left = [read_site(2, READER)];
        let by_rule = vec![("unknown_read", left.iter().collect::<Vec<_>>())];
        assert_eq!(write_sites(&path, &["h"], &tree, &by_rule, &["unknown_read"], Mode::Update).unwrap(), 1);
    }

    #[test]
    fn migrate_matches_rows_by_text_keeps_unmatched_rows_and_is_rerunnable() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	a = map_sectors[1]
	b = other
")]);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        std::fs::write(&path, "# h
unknown_read	code/a.dm	a = map_sectors[1]
unknown_read	code/a.dm	b = old text
").unwrap();
        let s = vec![read_site(2, READER)];
        let by_rule = vec![("unknown_read", s.iter().collect::<Vec<_>>())];
        let n = write_sites(&path, &["h"], &tree, &by_rule, &["unknown_read"], Mode::Migrate).unwrap();
        assert_eq!(n, 2);
        let once = std::fs::read_to_string(&path).unwrap();
        assert!(once.contains(&format!("unknown_read	code/a.dm	@{READER}")), "{once}");
        assert!(once.contains("b = old text"), "{once}");
        assert_eq!(write_sites(&path, &["h"], &tree, &by_rule, &["unknown_read"], Mode::Migrate).unwrap(), 2);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), once);
    }

    #[test]
    fn update_keeps_every_row_the_check_still_matches_in_a_mixed_baseline() {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/x
	a = 1
	b = 2
	c = 3
	d = 4
")]);
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.txt");
        // Identity rows (one shared by two sites), a line-text row, a row for a fixed site, and a legacy row whose text no longer matches.
        std::fs::write(&path, "# h
r	code/a.dm	@/obj/x::p reads /obj/y::v
r	code/a.dm	@/obj/x::p reads /obj/y::v
r	code/a.dm	@/obj/x::q reads /obj/y::w
r	code/a.dm	c = 3
r	code/a.dm	@/obj/x::gone reads /obj/y::z
r	code/a.dm	stale text
").unwrap();
        let sites = [decl("r", "code/a.dm", 2, "/obj/x::p reads /obj/y::v"), decl("r", "code/a.dm", 3, "/obj/x::p reads /obj/y::v"), decl("r", "code/a.dm", 4, "/obj/x::q reads /obj/y::w"), decl("r", "code/a.dm", 5, "/obj/x::s reads /obj/y::t")];
        let by_rule = vec![("r", sites.iter().collect::<Vec<_>>())];
        let mut out = String::new();
        let before = check_sites("t", &tree, &by_rule, &|_| String::new(), &path, &[], &mut out);
        assert!(before, "the site with no row is new: {out}");
        let n = write_sites(&path, &["h"], &tree, &by_rule, &["r"], Mode::Update).unwrap();
        assert_eq!(n, 3, "the three sites with a row stay; the new one is not added");
        let kept: Vec<&Site> = sites.iter().take(3).collect();
        let by_rule = vec![("r", kept)];
        let mut out = String::new();
        assert!(!check_sites("t", &tree, &by_rule, &|_| String::new(), &path, &[], &mut out), "{out}");
    }
}
