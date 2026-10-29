//! Shared original base-vars hot-home classifier and raw home-marker policy.
//! No semantic model, raw variable parser, filesystem access or cache.
use std::collections::HashSet;
use crate::pat;
pub const BASE_TYPES: &[&str] = &[
    "/atom",
    "/atom/movable",
    "/obj",
    "/obj/item",
    "/obj/machinery",
    "/mob",
    "/mob/living",
    "/mob/living/carbon",
    "/mob/living/carbon/human",
];
/// Shortest justification a `base_var_home_hot` entry may carry.
pub const HOT_MIN_JUSTIFICATION: usize = 40;
pub(crate) const HOT_TABLE: &str = "base_var_home_hot";
pub(crate) const SCOPES_FILE: &str = "tools/ci/lint_scopes.toml";
pub(crate) fn homes_in(text: &str, macros: &[String], relations: &[String]) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for m in pat!(r"(?m)^[ 	]*([A-Z_]+)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures_iter(text) {
        if macros.iter().any(|x| x == m.s(1)) {
            out.push((m.s(2).to_string(), m.s(3).to_string()));
        }
    }
    if relations.is_empty() {
        return out;
    }
    let block = pat!(r"^CAPABILITIES\(\s*(/[\w/]+)\s*\)");
    let entry = pat!(r"\b([a-z_]+)\(\s*nameof\(\s*(?:(/[\w/]+)::|(?:src|[A-Za-z_]\w*)\.)?(\w+)\s*\)");
    let link_end = pat!(r"(/[\w/]+)::(\w+)");
    let mut owner: Option<String> = None;
    for line in text.lines() {
        if !line.starts_with('\t') && !line.starts_with(' ') && !line.trim().is_empty() {
            owner = block.captures(line).map(|c| c.s(1).to_string());
        }
        for c in entry.captures_iter(line) {
            if !relations.iter().any(|x| x == c.s(1)) {
                continue;
            }
            if let Some(explicit) = c.get(2) {
                out.push((explicit.to_string(), c.s(3).to_string()));
            } else if let Some(o) = &owner {
                out.push((o.clone(), c.s(3).to_string()));
            }
        }
        if relations.iter().any(|x| x == "links") && line.contains("links(") {
            if let Some(i) = line.find("links(") {
                for c in link_end.captures_iter(&line[i..]) {
                    out.push((c.s(1).to_string(), c.s(2).to_string()));
                }
            }
        }
    }
    out
}

pub(crate) fn hot_key(key: &str) -> Option<(&str, &str)> {
    let (owner, name) = key.rsplit_once('/')?;
    if owner.is_empty() || name.is_empty() || !owner.starts_with('/') {
        return None;
    }
    Some((owner, name))
}

/// What is wrong with the hot table: `(key, message)`. `declared` is the `(type, var)` pairs that exist as counted base vars, or
/// None when there is no model to check existence against (the text fallback).
pub(crate) fn hot_problems(hot: &std::collections::BTreeMap<String, String>, declared: Option<&HashSet<(String, String)>>, homed: &HashSet<(String, String)>, ceiling: Option<usize>) -> Vec<(String, String)> {
    let mut out = Vec::new();
    if let Some(c) = ceiling {
        if hot.len() > c {
            out.push(("base_var_home_hot".to_string(), format!("the hot list has {} entries, over hot_ceiling {} (the ceiling only falls; a new entry is a reviewed design change)", hot.len(), c)));
        }
    }
    for (key, why) in hot {
        let Some((owner, name)) = hot_key(key) else {
            out.push((key.clone(), format!("`{}` is not a `<type>/<var>` key", key)));
            continue;
        };
        if homed.contains(&(owner.to_string(), name.to_string())) {
            out.push((key.clone(), format!("`{}` is already homed by a TRACKED/STAT/SETTER declaration or a relation: drop the entry", key)));
        }
        if !BASE_TYPES.contains(&owner) {
            out.push((key.clone(), format!("`{}`: {} is not a base type", key, owner)));
        } else if let Some(d) = declared {
            if !d.contains(&(owner.to_string(), name.to_string())) {
                out.push((key.clone(), format!("`{}` is stale: {} declares no counted var `{}`", key, owner, name)));
            }
        }
        let why = why.trim();
        if why.chars().count() < HOT_MIN_JUSTIFICATION {
            out.push((key.clone(), format!("`{}` needs a justification of at least {} characters (has {})", key, HOT_MIN_JUSTIFICATION, why.chars().count())));
        } else if !why.contains(".dm") {
            out.push((key.clone(), format!("`{}`: the justification must name the hot reader (a .dm file and the proc that reads it)", key)));
        }
    }
    out
}
