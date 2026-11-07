//! Banned legacy names: a hard ban, no baseline. Each entry of `[lint.legacy_forms.lists] banned` in tools/ci/lint_scopes.toml is
//! `name = hint`; any mention of the name in code (a call, a definition, a member) fails with that hint; a name ending in `*` bans every word
//! that starts with it. When a legacy form is deleted,
//! its names go on the list so it cannot come back.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};
use std::collections::HashMap;

static META: Meta = Meta {
    name: crate::allow_registry_fields::legacy_forms::SCOPE_META_0.name,
    group: crate::allow_registry_fields::legacy_forms::SCOPE_META_0.group,
    label: "legacy_forms",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "banned_name", hint: "the form was deleted: use its replacement (the hint after the name, in [lint.legacy_forms.lists] banned of tools/ci/lint_scopes.toml)" }],
    allow: crate::allow_registry_fields::legacy_forms::ALLOW_0,
    lists: crate::allow_registry_fields::legacy_forms::SCOPE_META_0.lists,
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
        scan_banned(cx.list("banned"), f, out);
    }
}

struct Needle<'a> {
    text: &'a str,
    prefix: bool,
    exceptions: Vec<&'a str>,
}

impl<'a> Needle<'a> {
    fn new(name: &'a str, outside: bool) -> Self {
        let (name, exceptions) = if outside {
            match name.split_once(" except ") {
                Some((name, exceptions)) => (name.trim(), exceptions.split(',').map(str::trim).collect()),
                None => (name, Vec::new()),
            }
        } else {
            (name, Vec::new())
        };
        let (text, prefix) = name.strip_suffix('*').map_or((name, false), |text| (text, true));
        Self { text, prefix, exceptions }
    }

    fn matches(&self, line: &str) -> bool {
        let bytes = line.as_bytes();
        // The outside form already rejects empty needles. For the main ban
        // keep its first-position behavior without repeating a zero-width miss.
        if self.text.is_empty() {
            return self.prefix || bytes.first().is_none_or(|&byte| !is_word(byte));
        }
        let mut from = 0;
        while let Some(found) = line[from..].find(self.text) {
            let at = from + found;
            let end = at + self.text.len();
            if (at == 0 || !is_word(bytes[at - 1]))
                && (self.prefix || end == bytes.len() || !is_word(bytes[end]))
            {
                if self.exceptions.is_empty() {
                    return true;
                }
                let tail = bytes[end..].iter().take_while(|&&byte| is_word(byte)).count();
                if !self.exceptions.contains(&&line[at..end + tail]) {
                    return true;
                }
            }
            // Punctuation needles can overlap. The original search advanced
            // to the end of every occurrence, including rejected occurrences.
            from = end;
        }
        false
    }
}

struct Banned<'a> {
    name: &'a str,
    hint: &'a str,
    needle: Needle<'a>,
    previous_exact: Option<usize>,
    matched_on: usize,
}

fn scan_banned(entries: &[String], f: &SourceFile, out: &mut Sink) {
    if entries.is_empty() {
        return;
    }
    let mut exact = HashMap::with_capacity(entries.len());
    let mut prefixes = HashMap::<u8, Vec<usize>>::new();
    let mut other = Vec::new();
    let mut rules = Vec::with_capacity(entries.len());
    for (index, entry) in entries.iter().enumerate() {
        let (name, hint) = entry.split_once('=').map_or((entry.trim(), ""), |(name, hint)| (name.trim(), hint.trim()));
        let needle = Needle::new(name, false);
        let previous_exact = match needle.text.as_bytes().first() {
            Some(&first) if needle.text.bytes().all(is_word) => {
                if needle.prefix {
                    prefixes.entry(first).or_default().push(index);
                    None
                } else {
                    exact.insert(needle.text, index)
                }
            }
            _ => {
                other.push(index);
                None
            }
        };
        rules.push(Banned { name, hint, needle, previous_exact, matched_on: 0 });
    }
    let mut matched = Vec::new();
    for (number, line) in f.code().numbered() {
        let bytes = line.as_bytes();
        let mut at = 0;
        while at < bytes.len() {
            if !is_word(bytes[at]) {
                at += 1;
                continue;
            }
            let start = at;
            while at < bytes.len() && is_word(bytes[at]) {
                at += 1;
            }
            // An ASCII word's endpoints are UTF-8 boundaries even when
            // adjacent source contains non-ASCII characters.
            let word = &line[start..at];
            let mut duplicate = exact.get(word).copied();
            while let Some(index) = duplicate {
                let rule = &mut rules[index];
                if rule.matched_on != number {
                    rule.matched_on = number;
                    matched.push(index);
                }
                duplicate = rule.previous_exact;
            }
            if let Some(indices) = prefixes.get(&bytes[start]) {
                for &index in indices {
                    let rule = &mut rules[index];
                    if rule.matched_on != number && word.starts_with(rule.needle.text) {
                        rule.matched_on = number;
                        matched.push(index);
                    }
                }
            }
        }
        for &index in &other {
            if rules[index].needle.matches(line) {
                matched.push(index);
            }
        }
        matched.sort_unstable();
        for index in matched.drain(..) {
            let rule = &rules[index];
            out.site_msg("banned_name", number, format!("{} is gone: {}", rule.name, rule.hint));
        }
    }
}

/// `banned_outside` entries are `name @ prefix;prefix = hint`: the name is gone everywhere except under the listed path prefixes (the
/// folders that still have callers). A name ending in `*` is itself a prefix: `vg_* @ ...` bans every word that starts with `vg_`, and
/// `vg_* except vg_entity @ ...` leaves that one word alone. Shrink the path prefixes as callers convert; delete the entry's prefixes
/// entirely when none remain.
fn scan_outside(cx: &Cx, f: &SourceFile, out: &mut Sink) {
    for entry in cx.list("banned_outside") {
        let Some((left, hint)) = entry.split_once('=') else { continue };
        let Some((name, prefixes)) = left.split_once('@') else { continue };
        let name = name.trim();
        if prefixes.split(';').map(str::trim).any(|p| !p.is_empty() && f.rel.starts_with(p)) {
            continue;
        }
        let needle = Needle::new(name, true);
        if needle.text.is_empty() {
            continue;
        }
        for (number, line) in f.code().numbered() {
            if needle.matches(line) {
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
    use super::*;
    use crate::{scopes::LintScope, tree::Tree};

    fn has_word(line: &str, name: &str) -> bool {
        let needle = Needle::new(name.trim(), true);
        !needle.text.is_empty() && needle.matches(line)
    }

    fn slow_match(line: &str, text: &str, prefix: bool, exceptions: &[&str]) -> bool {
        let bytes = line.as_bytes();
        let mut from = 0;
        while let Some(found) = line[from..].find(text) {
            let at = from + found;
            let end = at + text.len();
            if (at == 0 || !is_word(bytes[at - 1]))
                && (prefix || end >= bytes.len() || !is_word(bytes[end]))
            {
                let mut stop = end;
                while stop < bytes.len() && is_word(bytes[stop]) {
                    stop += 1;
                }
                if !exceptions.contains(&&line[at..stop]) {
                    return true;
                }
            }
            from = end;
        }
        false
    }

    fn slow_scan(cx: &Cx, file: &SourceFile, out: &mut Sink) {
        for entry in cx.list("banned_outside") {
            let Some((left, hint)) = entry.split_once('=') else { continue };
            let Some((name, prefixes)) = left.split_once('@') else { continue };
            let name = name.trim();
            if prefixes.split(';').map(str::trim).any(|p| !p.is_empty() && file.rel.starts_with(p)) {
                continue;
            }
            let (needle, exceptions) = match name.split_once(" except ") {
                Some((name, exceptions)) => (name.trim(), exceptions.split(',').map(str::trim).collect()),
                None => (name, Vec::new()),
            };
            let (needle, prefix) = needle.strip_suffix('*').map_or((needle, false), |n| (n, true));
            if needle.is_empty() {
                continue;
            }
            for (number, line) in file.code().numbered() {
                if slow_match(line, needle, prefix, &exceptions) {
                    out.site_msg("banned_name", number, format!("{} is gone here: {}", name, hint.trim()));
                }
            }
        }
        for (number, line) in file.code().numbered() {
            for entry in cx.list("banned") {
                let (name, hint) = entry.split_once('=').map_or((entry.trim(), ""), |(n, h)| (n.trim(), h.trim()));
                let (needle, prefix) = name.strip_suffix('*').map_or((name, false), |n| (n, true));
                if slow_match(line, needle, prefix, &[]) {
                    out.site_msg("banned_name", number, format!("{} is gone: {}", name, hint));
                }
            }
        }
    }

    #[test]
    fn indexed_scan_preserves_original_order_duplicates_boundaries_and_stripped_code() {
        let mut scope = LintScope::default();
        scope.lists.insert("banned".into(), [
            "vg_* = prefix", "old = first", "call( = call boundary",
            "old = duplicate", "/datum/req = path", "a-a = overlap",
            "factor(* = punctuation prefix", "old_* = longer prefix", "missing",
            "βeta* = unicode prefix",
        ].into_iter().map(str::to_owned).collect());
        scope.lists.insert("banned_outside".into(), [
            "vg_* except vg_entity, vg_bind @ code/kept/; code/sibling/ = outside prefix",
            "old @ code/kept/ = outside word", "ignored = has no @ separator",
            "vg_* except vg_entity @ ; = another outside row", "* @ = empty outside needle",
            "a-a @ code/kept/ = nonoverlapping legacy punctuation",
        ].into_iter().map(str::to_owned).collect());
        let tree = Tree::from_files(vec![]);
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let source = r#"/datum/req/child
    old old vg_entity vg_bind vg_forbidden old_prefix factor(x)
    xold old2 _old old_ a-a xa-a-a!
    xa-a-a!
    call(1)
    call( 1)
    call()
    βetaOK éold oldé évg_forbidden vg_forbiddené
    var/text = "old vg_forbidden call()"
    // old /datum/req
    /* old vg_forbidden */ old
"#;
        for path in ["code/blocked/test.dm", "code/kept/test.dm", "code/sibling/test.dm"] {
            let file = SourceFile::from_text(path, source);
            let mut actual = Sink::new();
            let mut expected = Sink::new();
            actual.set_current(path);
            expected.set_current(path);
            LegacyForms.scan_file(&cx, &file, &mut actual);
            slow_scan(&cx, &file, &mut expected);
            assert_eq!(actual.sites, expected.sites, "{path}");
            assert!(!actual.sites.is_empty());
            assert!(!actual.sites.iter().any(|site| site.line == 4 && site.msg.starts_with("a-a ")));
        }
    }

    #[test]
    fn malformed_empty_main_name_cannot_stall_a_word_line() {
        assert!(!Needle::new("", false).matches("word"));
        assert!(Needle::new("", false).matches(" word"));
        assert!(Needle::new("*", false).matches("word"));
    }

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
    fn an_exception_is_left_alone() {
        let name = "vg_* except vg_entity, vg_bind";
        assert!(!has_word("if(vg_entity)", name));
        assert!(!has_word("vg_bind()", name));
        assert!(has_word("vg_entity_index(e)", name));
        assert!(has_word("if(vg_entity) vg_frame()", name));
    }

    #[test]
    fn a_bare_star_matches_nothing() {
        assert!(!has_word("anything at all", "*"));
    }
}
