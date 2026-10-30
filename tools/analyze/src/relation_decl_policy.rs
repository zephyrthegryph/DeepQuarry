//! Original relation declaration projection, not a general declaration model.
use crate::tree::{SourceFile, CODE_DM};
use std::collections::{BTreeMap, HashMap};
pub fn visit_legacy_line(
    t: &str,
    mut emit: impl FnMut(&str, &str) -> Result<(), String>,
) -> Result<(), String> {
    if let Some(m)=crate::pat_match!(r"(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(t){emit(m.s(1),m.s(2))?;}
    Ok(())
}
pub fn legacy_line(t: &str) -> Option<(String, String)> {
    let mut pair = None;
    visit_legacy_line(t, |a, b| {
        pair = Some((a.to_owned(), b.to_owned()));
        Ok(())
    })
    .expect("infallible legacy collector");
    pair
}

pub fn visit_capability_pairs(
    ty: &str,
    body: &str,
    mut emit: impl FnMut(&str, &str) -> Result<(), String>,
) -> Result<(), String> {
    static OWN: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
        regex::Regex::new(
            r"\b(?:owns_one|owns_many|ref_one|ref_many|hud_element|profile)\(\s*nameof\((\w+)\)",
        )
        .unwrap()
    });
    static LINK: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
        regex::Regex::new(r"\blinks?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)").unwrap()
    });
    for c in OWN.captures_iter(body) {
        emit(ty, &c[1])?;
    }
    for c in LINK.captures_iter(body) {
        emit(&c[1], &c[2])?;
        emit(&c[3], &c[4])?;
    }
    Ok(())
}
pub fn capability_pairs(ty: &str, body: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    visit_capability_pairs(ty, body, |a, b| {
        out.push((a.to_owned(), b.to_owned()));
        Ok(())
    })
    .expect("infallible legacy collector");
    out
}

fn add(
    out: &mut HashMap<String, Vec<String>>,
    owner: &str,
    var: &str,
    retained: &mut usize,
    limit: usize,
) -> Result<(), String> {
    let bytes = owner
        .len()
        .checked_add(var.len())
        .and_then(|n| n.checked_mul(4))
        .and_then(|n| n.checked_add(256))
        .ok_or("relation declaration accounting overflow")?;
    *retained = retained
        .checked_add(bytes)
        .ok_or("relation declaration accounting overflow")?;
    if *retained > limit {
        return Err("relation declaration retention exceeds admission".into());
    }
    out.entry(var.to_owned())
        .or_default()
        .push(owner.to_owned());
    Ok(())
}
/// Exact union of Decls relations and ownership_index declaration projection.
/// The old scanner emits ephemeral events; no Index/member/type model is built.
pub(crate) struct DeclarationIndex {
    pub relations: HashMap<String, Vec<String>>,
    pub retained_admission: usize,
    pub registry: Vec<String>,
}
pub(crate) fn declarations(
    files: Vec<&SourceFile>,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    project(files, false, 0, checkpoint)
}
pub(crate) fn declarations_with_registry(
    files: Vec<&SourceFile>,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    project(files, true, 0, checkpoint)
}
pub(crate) fn declarations_with_registry_reserved(
    files: Vec<&SourceFile>,
    reserved: usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    project(files, true, reserved, checkpoint)
}
fn project(
    mut files: Vec<&SourceFile>,
    include_registry: bool,
    reserved: usize,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    if reserved > 64 * 1024 * 1024 {
        return Err("relation coordination exceeds admission before allocation".into());
    }
    // Reuse the caller's admitted coordination Vec; do not collect a second one.
    files.retain(|f| CODE_DM.matches(f));
    files.sort_by_key(|f| &f.rel);
    let mut out = HashMap::new();
    let mut retained = reserved;
    let mut legacy = BTreeMap::new();
    let mut registry = Vec::new();
    if include_registry {
        for ty in crate::raw_ownership_policy::FLYWEIGHT_TYPES {
            retained = retained
                .checked_add(ty.len().saturating_mul(4).saturating_add(128))
                .ok_or("registry accounting overflow")?;
            registry.push((*ty).to_owned());
        }
    }
    for f in files {
        checkpoint()?;
        let text = f.marker();
        let mut offset = 0;
        for line in text.as_str().split('\n') {
            checkpoint()?;
            let t = line.trim_start();
            if !t.starts_with('#') && !t.is_empty() {
                visit_legacy_line(t, |owner, var| {
                    add(&mut out, owner, var, &mut retained, 64 * 1024 * 1024)
                })?;
                if let Some(m) = crate::raw_marker_policy::statement_marker(
                    text.as_str(),
                    offset,
                    line,
                    &["CAPABILITIES"],
                ) {
                    let end = if line.len() == t.len() {
                        crate::raw_marker_policy::block_extent(text.as_str(), m.close)
                    } else {
                        None
                    };
                    let bytes = end
                        .unwrap_or(m.close)
                        .saturating_sub(m.open)
                        .checked_mul(32)
                        .ok_or("relation block overflow")?;
                    if retained.saturating_add(bytes) > 64 * 1024 * 1024 {
                        return Err("relation block exceeds admission before allocation".into());
                    }
                    let body = match end {
                        Some(end) => crate::raw_marker_policy::block_body(
                            text.as_str(),
                            m.open + 1,
                            m.close,
                            end,
                        ),
                        None => text.as_str()[m.open + 1..m.close].to_owned(),
                    };
                    let args = crate::raw_marker_policy::split_args(&body);
                    if let Some(owner) = args.first() {
                        visit_capability_pairs(owner, &body, |owner, var| {
                            add(
                                &mut out,
                                owner,
                                var,
                                &mut retained,
                                64 * 1024 * 1024 - bytes,
                            )
                        })?;
                    }
                }
            }
            offset += line.len() + 1;
        }
        let temporary = f
            .raw()
            .text
            .len()
            .checked_mul(32)
            .ok_or("relation event admission overflow")?;
        if retained.saturating_add(temporary) > 64 * 1024 * 1024 {
            return Err("relation event projection exceeds admission before allocation".into());
        }
        crate::raw_ownership_policy::visit_file_events(&f.rel, f.raw(), f.code(), |ev| {
            if let crate::raw_ownership_policy::IdxEv::Decl {
                owner,
                name,
                macro_name,
                ..
            } = ev
            {
                // Original Index overwrites each (owner,var) with the last declaration.
                let bytes = owner
                    .len()
                    .saturating_add(name.len())
                    .saturating_add(macro_name.len())
                    .saturating_mul(4)
                    .saturating_add(256);
                retained = retained
                    .checked_add(bytes)
                    .ok_or("relation legacy table accounting overflow")?;
                if retained > 64 * 1024 * 1024 - temporary {
                    return Err("relation legacy table exceeds admission".into());
                }
                legacy.insert((owner, name), macro_name);
            } else if let crate::raw_ownership_policy::IdxEv::Registry(ty) = ev {
                if include_registry {
                    retained = retained
                        .checked_add(ty.len().saturating_mul(4).saturating_add(128))
                        .ok_or("registry accounting overflow")?;
                    if retained > 64 * 1024 * 1024 - temporary {
                        return Err("registry projection admission exceeded".into());
                    }
                    registry.push(ty);
                }
            }
            Ok(())
        })?;
    }
    for ((owner, var), kind) in legacy {
        if kind != "ANNOTATE" {
            add(&mut out, &owner, &var, &mut retained, 64 * 1024 * 1024)?
        }
    }
    checkpoint()?;
    Ok(DeclarationIndex {
        relations: out,
        retained_admission: retained,
        registry,
    })
}

#[cfg(feature = "unified-oracle")]
pub fn oracle_projection(tree: &crate::tree::Tree) -> Result<HashMap<String, Vec<String>>, String> {
    Ok(declarations(tree.select(&CODE_DM), || Ok(()))?.relations)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn relation_pair_denial_happens_before_repeated_owner_rows_are_collected() {
        let mut seen = 0;
        let error = visit_capability_pairs(
            "/datum/holder",
            "ref_one(nameof(a)), ref_one(nameof(b))",
            |_, _| {
                seen += 1;
                Err("denied".into())
            },
        )
        .unwrap_err();
        assert_eq!(seen, 1);
        assert_eq!(error, "denied");
    }
}
