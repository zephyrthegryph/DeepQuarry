//! Banned legacy names: a hard ban, no baseline. Each entry of `[lint.legacy_forms.lists] banned` in tools/ci/lint_scopes.toml is
//! `name = hint`; any mention of the name in code (a call, a definition, a member) fails with that hint; a name ending in `*` bans every word
//! that starts with it. When a legacy form is deleted,
//! its names go on the list so it cannot come back.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "legacy_forms",
    group: "",
    label: "legacy_forms",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "banned_name", hint: "the form was deleted: use its replacement (the hint after the name, in [lint.legacy_forms.lists] banned of tools/ci/lint_scopes.toml)" }],
    allow: &[],
    lists: &["banned", "banned_outside"],
};

struct LegacyForms;

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

impl Lint for LegacyForms {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        scan_outside(cx, f, out);
        let banned: Vec<(&str, &str)> = cx.list("banned").iter().map(|e| e.split_once('=').map(|(n, h)| (n.trim(), h.trim())).unwrap_or((e.trim(), ""))).collect();
        if banned.is_empty() {
            return;
        }
        for (number, line) in f.code().numbered() {
            let b = line.as_bytes();
            for (name, hint) in &banned {
                // A name ending in `*` is a prefix: `BF_*` bans every word that starts with `BF_`.
                let (needle, prefix) = match name.strip_suffix('*') {
                    Some(p) => (p, true),
                    None => (*name, false),
                };
                let mut from = 0;
                while let Some(p) = line[from..].find(needle) {
                    let at = from + p;
                    let end = at + needle.len();
                    if (at == 0 || !is_word(b[at - 1])) && (prefix || end >= b.len() || !is_word(b[end])) {
                        out.site_msg("banned_name", number, format!("{} is gone: {}", name, hint));
                        break;
                    }
                    from = end;
                }
            }
        }
    }
}

/// Whether `line` holds the word `name`; a `name` ending in `*` is a prefix and matches any word that starts with it
/// (`vg_*` is every word that starts with `vg_`).
fn has_word(line: &str, name: &str) -> bool {
    let (needle, prefix) = match name.strip_suffix('*') {
        Some(p) => (p, true),
        None => (name, false),
    };
    if needle.is_empty() {
        return false;
    }
    let b = line.as_bytes();
    let mut from = 0;
    while let Some(p) = line[from..].find(needle) {
        let at = from + p;
        let end = at + needle.len();
        if (at == 0 || !is_word(b[at - 1])) && (prefix || end >= b.len() || !is_word(b[end])) {
            return true;
        }
        from = end;
    }
    false
}

/// `banned_outside` entries are `name @ prefix;prefix = hint`: the name is gone everywhere except under the listed path prefixes (the
/// folders that still have callers). A name ending in `*` is itself a prefix: `vg_* @ ...` bans every word that starts with `vg_`.
/// Shrink the path prefixes as callers convert; delete the entry's prefixes entirely when none remain.
fn scan_outside(cx: &Cx, f: &SourceFile, out: &mut Sink) {
    for entry in cx.list("banned_outside") {
        let Some((left, hint)) = entry.split_once('=') else { continue };
        let Some((name, prefixes)) = left.split_once('@') else { continue };
        let name = name.trim();
        if prefixes.split(';').map(str::trim).any(|p| !p.is_empty() && f.rel.starts_with(p)) {
            continue;
        }
        for (number, line) in f.code().numbered() {
            if has_word(line, name) {
                out.site_msg("banned_name", number, format!("{} is gone here: {}", name, hint.trim()));
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(LegacyForms);
}

#[cfg(test)]
mod tests {
    use super::has_word;

    #[test]
    fn a_plain_name_is_a_whole_word() {
        assert!(has_word("x = vg_foo(1)", "vg_foo"));
        assert!(!has_word("x = vg_foobar(1)", "vg_foo"));
        assert!(!has_word("x = my_vg_foo(1)", "vg_foo"));
    }

    #[test]
    fn a_star_name_is_a_prefix_of_words() {
        assert!(has_word("x = vg_foo(1)", "vg_*"));
        assert!(has_word("x = vg_(1)", "vg_*"));
        assert!(has_word("a(); vg_entity_index(e)", "vg_*"));
        assert!(!has_word("x = my_vg_foo(1)", "vg_*"));
        assert!(!has_word("x = foo_vg(1)", "vg_*"));
    }

    #[test]
    fn a_bare_star_matches_nothing() {
        assert!(!has_word("anything at all", "*"));
    }
}
