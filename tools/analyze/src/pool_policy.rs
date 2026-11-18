//! Exact original cross-file pool raw policy; no semantic model/parser.
use crate::raw_fixture_policy::PatternApi as _;
use crate::{
    captured_generator_budget::Budget,
    lint::{Meta, Policy, RuleMeta, ScanKind},
    pat,
    tree::{SourceFile, CODE_DM},
    util::{before_slashes, starts_with_any},
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::pool::SCOPE_META_0.name,
    group: crate::allow_registry_fields::pool::SCOPE_META_0.group,
    label: "pool",
    legacy: "tools/ci/pool_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta {
            name: "new_pooled",
            hint: "take it with take(type) and give it back with .release()",
        },
        RuleMeta {
            name: "take_leak",
            hint: "release what the file takes (a leak by construction)",
        },
    ],
    allow: &[], // the Python never lists `pool` in allow_annotations.LINTS, so ALLOW(pool) stays unknown
    lists: crate::allow_registry_fields::pool::SCOPE_META_0.lists,
};

pub const RULE_NAMES: [&str; 2] = ["new_pooled", "take_leak"];
pub const NEW_POOLED: u8 = 0;
pub const TAKE_LEAK: u8 = 1;
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    pub pooled: Vec<String>,
}
fn charge(b: Option<&Budget>, bytes: Option<usize>) -> Result<(), String> {
    if let Some(b) = b {
        let Some(bytes) = bytes else {
            b.deny();
            return Err("pool temporary accounting overflow".into());
        };
        b.charge(bytes)?;
    }
    Ok(())
}
fn strip(line: &str, b: Option<&Budget>) -> Result<String, String> {strip_with_fixture(line,b,&crate::raw_fixture_policy::Fixture::legacy())}
fn strip_with_fixture(line: &str, b: Option<&Budget>,fixture:&crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    charge(
        b,
        line.len().checked_mul(4).and_then(|n| n.checked_add(256)),
    )?;
    Ok(fixture.replace_static(r#""[^"]*""#,before_slashes(line), "\"\"",||pat!(r#""[^"]*""#))?)
}
pub fn facts_of(
    f: &SourceFile,
    b: Option<&Budget>,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Facts, String> {facts_of_with_fixture(f,b,checkpoint,&crate::raw_fixture_policy::Fixture::legacy())}
pub fn facts_of_with_fixture(
    f: &SourceFile,
    b: Option<&Budget>,
    mut checkpoint: impl FnMut() -> Result<(), String>,fixture:&crate::raw_fixture_policy::Fixture<'_>) -> Result<Facts, String> {
    let mut pooled: BTreeSet<String> = BTreeSet::new();
    let mut current: Option<String> = None;
    for line in f.raw().lines() {
        checkpoint()?;
        if let Some(m) = fixture.pattern(r"^(/datum/[A-Za-z0-9_/]+)\s*$",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^(/datum/[A-Za-z0-9_/]+)\s*$")).captures(line) {
            charge(
                b,
                m.s(1).len().checked_mul(2).and_then(|n| n.checked_add(64)),
            )?;
            current = Some(m.s(1).to_string());
        }
        if let Some(m) =
            fixture.pattern(r"^\s+parent_type\s*=\s*(/datum/pooled\b[A-Za-z0-9_/]*|/datum/[A-Za-z0-9_/]+)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\s+parent_type\s*=\s*(/datum/pooled\b[A-Za-z0-9_/]*|/datum/[A-Za-z0-9_/]+)"))
                .captures(line)
        {
            if let Some(cur) = &current {
                if m.s(1).starts_with("/datum/pooled") {
                    charge(b, cur.len().checked_mul(2).and_then(|n| n.checked_add(512)))?;
                    pooled.insert(cur.clone());
                }
            }
        }
        for d in fixture.pattern(r"POOL_DECLARE\((/datum/[A-Za-z0-9_/]+)\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"POOL_DECLARE\((/datum/[A-Za-z0-9_/]+)\)")).captures_iter(line) {
            checkpoint()?;
            charge(
                b,
                d.s(1).len().checked_mul(2).and_then(|n| n.checked_add(512)),
            )?;
            pooled.insert(d.s(1).to_string());
        }
    }
    charge(
        b,
        pooled
            .len()
            .checked_mul(3 * std::mem::size_of::<String>())
            .and_then(|n| n.checked_add(64)),
    )?;
    Ok(Facts {
        pooled: pooled.into_iter().collect(),
    })
}
fn returned_acquisition(
    lines: &[&str],
    at: usize,
    b: Option<&Budget>,
    checkpoint: &mut impl FnMut() -> Result<(), String>,
) -> Result<bool, String> {returned_acquisition_with_fixture(lines,at,b,checkpoint,&crate::raw_fixture_policy::Fixture::legacy())}
fn returned_acquisition_with_fixture(
    lines: &[&str],
    at: usize,
    b: Option<&Budget>,
    checkpoint: &mut impl FnMut() -> Result<(), String>,fixture:&crate::raw_fixture_policy::Fixture<'_>) -> Result<bool, String> {
    let declaration = strip_with_fixture(lines[at], b,fixture)?;
    let Some(local)=fixture.pattern(r"^\tvar/(?:[A-Za-z0-9_]+/)+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:pool_take|take)\(/datum/[A-Za-z0-9_/]+\)\s*$",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\tvar/(?:[A-Za-z0-9_]+/)+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:pool_take|take)\(/datum/[A-Za-z0-9_/]+\)\s*$")).captures(&declaration)else{return Ok(false);};
    let name = local.s(1);
    for raw in &lines[at + 1..] {
        checkpoint()?;
        let line = strip_with_fixture(raw, b,fixture)?;
        if !line.trim().is_empty() && !line.starts_with('\t') && !line.starts_with(' ') {
            break;
        }
        let trimmed = line.trim();
        if trimmed.starts_with("return") {
            // Equivalent to the ORIGINAL format!("\treturn {}",name) equality,
            // without allocating that comparison string on the captured path.
            return Ok(line.strip_prefix("\treturn ") == Some(name));
        }
        if let Some(write) =
            fixture.pattern(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|\+=|-=|\*=|/=)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|\+=|-=|\*=|/=)")).captures(&line)
        {
            if write.s(1) == name {
                return Ok(false);
            }
        }
    }
    Ok(false)
}
/// Callback preserves original emission order while native messages stream into
/// an admitted sink. Legacy adapter retains the same Vec tuple interface.
pub fn judge(
    f: &SourceFile,
    pooled: &BTreeSet<String>,
    exempt_prefixes: &[String],
    b: Option<&Budget>,
    mut checkpoint: impl FnMut() -> Result<(), String>,
    mut emit: impl FnMut(u8, u32, std::fmt::Arguments<'_>) -> Result<(), String>,
) -> Result<(), String> {judge_with_fixture(f,pooled,exempt_prefixes,b,checkpoint,emit,&crate::raw_fixture_policy::Fixture::legacy())}
pub fn judge_with_fixture(
    f: &SourceFile,
    pooled: &BTreeSet<String>,
    exempt_prefixes: &[String],
    b: Option<&Budget>,
    mut checkpoint: impl FnMut() -> Result<(), String>,
    mut emit: impl FnMut(u8, u32, std::fmt::Arguments<'_>) -> Result<(), String>,fixture:&crate::raw_fixture_policy::Fixture<'_>) -> Result<(), String> {
    let exempt = starts_with_any(&f.rel, exempt_prefixes);
    let mut takes: Vec<(usize, String)> = Vec::new();
    let mut releases = false;
    charge(
        b,
        f.raw()
            .num_lines()
            .checked_mul(3 * std::mem::size_of::<&str>())
            .and_then(|n| n.checked_add(256)),
    )?;
    let lines: Vec<&str> = f.raw().lines().collect();
    for (number, raw) in f.raw().numbered() {
        checkpoint()?;
        if raw.contains("ALLOW(pool)") {
            continue;
        }
        let line = strip_with_fixture(raw, b,fixture)?;
        if fixture.pattern(r"\.release\(\)|\bpool_release\(|\brelease\(\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\.release\(\)|\bpool_release\(|\brelease\(\)")).is_match(&line) {
            releases = true;
        }
        for t in fixture.pattern(r"\b(?:pool_take|take)\((/datum/[A-Za-z0-9_/]+)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\b(?:pool_take|take)\((/datum/[A-Za-z0-9_/]+)")).captures_iter(&line) {
            checkpoint()?;
            if !returned_acquisition_with_fixture(&lines, number - 1, b, &mut checkpoint,fixture)? {
                charge(
                    b,
                    t.s(1).len().checked_mul(2).and_then(|n| n.checked_add(64)),
                )?;
                if let Some(b) = b {
                    if !b.row(&mut takes) {
                        return Err("pool take retention denied".into());
                    }
                }
                takes.push((number, t.s(1).to_string()));
            }
        }
        if exempt {
            continue;
        }
        for t in fixture.pattern(r"\bnew\s+(/datum/[A-Za-z0-9_/]+)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\bnew\s+(/datum/[A-Za-z0-9_/]+)")).captures_iter(&line) {
            checkpoint()?;
            let t = t.s(1);
            if pooled.iter().any(|p| {
                t == p || (t.starts_with(p.as_str()) && t.as_bytes().get(p.len()) == Some(&b'/'))
            }) {
                emit(
                    NEW_POOLED,
                    u32::try_from(number).map_err(|_| "pool line overflow")?,
                    format_args!("new {}: a pooled type is taken with take(), not built", t),
                )?;
            }
        }
    }
    if !takes.is_empty() && !releases && !exempt {
        let (number, t) = &takes[0];
        emit(
            TAKE_LEAK,
            u32::try_from(*number).map_err(|_| "pool line overflow")?,
            format_args!(
                "take({}) but the file never releases: give it back with .release()",
                t
            ),
        )?;
    }
    checkpoint()?;
    if let Some(b) = b {
        b.require()?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn raw_parent_and_marker_quirks_are_source_policy_not_native_hierarchy() {
        let f=SourceFile::from_text("code/a.dm","/datum/a\n/proc/irrelevant()\n\tparent_type = /datum/pooledish\n// POOL_DECLARE(/datum/commented)\n");
        assert_eq!(
            facts_of(&f, None, || Ok(())).unwrap().pooled,
            ["/datum/a", "/datum/commented"]
        );
    }
    #[test]
    fn real_retained_line_and_factory_temporaries_deny_before_clean_result() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/proc/f()\n\tvar/datum/packet/P = take(/datum/packet)\n\treturn P\n",
        );
        let b = Budget::new(64).unwrap();
        let called = std::cell::Cell::new(false);
        assert!(judge(
            &f,
            &BTreeSet::new(),
            &[],
            Some(&b),
            || Ok(()),
            |_, _, _| {
                called.set(true);
                Ok(())
            }
        )
        .is_err());
        assert!(b.denied());
        assert!(!called.get());
    }
}
