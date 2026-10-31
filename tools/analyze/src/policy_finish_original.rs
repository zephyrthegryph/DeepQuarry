//! Test-only exact original algorithm projection; never a production provider.
use super::*;
use std::fmt::Write as _;
/// Prints outcomes the way `check_ratchets.sh` did. Returns the names of failed lints.
pub fn render(outcomes: &[Outcome], ci: bool) -> (String, Vec<String>) {
    let mut s = String::new();
    let mut failed = Vec::new();
    for o in outcomes {
        if ci {
            let _ = writeln!(s, "::group::{}", o.name);
        }
        s.push_str(&o.text);
        if ci {
            let _ = writeln!(s, "::endgroup::");
        }
        if o.failed {
            failed.push(o.name.clone());
        }
    }
    (s, failed)
}


pub fn update<S:SiteText+?Sized>(meta:&Meta,scope:&LintScope,source:&S,run:&Run,root:&Path,scopes_root:&Path,mode:Mode,mut custom:impl FnMut(&Run,Mode)->std::io::Result<String>)->std::io::Result<String>{
        let by_rule = run.by_rule(meta);
        // Per-rule ceilings live in lint_scopes.toml: lower them (--update) or set them (--seed).
        let mut ceiling_note = String::new();
        if matches!(meta.policy, Policy::Sites { .. } | Policy::Hard) {
            let scopes_root = scopes_root.to_path_buf();
            let scopes_path = scopes_root.join("tools").join("ci").join("lint_scopes.toml");
            for (rule, found) in &by_rule {
                let Some(&ceiling) = scope.ceilings.get(*rule) else { continue };
                let count = found.len() as i64;
                let new = match mode {
                    Mode::Update => ceiling.min(count),
                    Mode::Seed => count,
                    Mode::Migrate => ceiling,
                };
                if new != ceiling {
                    crate::scopes::write_ceiling(&scopes_path, meta.name, rule, new)?;
                    ceiling_note.push_str(&format!(" ceiling {} {} -> {};", rule, ceiling, new));
                }
            }
        }
        let by_rule_for_baseline: Vec<(&str, Vec<&crate::lint::Site>)> =
            by_rule.iter().filter(|(r, _)| !scope.ceilings.contains_key(*r)).map(|(r, s)| (*r, s.clone())).collect();
        let by_rule = if matches!(meta.policy, Policy::Sites { .. }) { by_rule_for_baseline } else { by_rule };
        match meta.policy {
            Policy::Sites { baseline, header, banned } => {
                let rules: Vec<&str> = meta
                    .rules
                    .iter()
                    .map(|r| r.name)
                    .filter(|r| !banned.contains(r) && !scope.ceilings.contains_key(*r))
                    .collect();
                let n = baseline::write_sites(&root.join(baseline), header, source, &by_rule, &rules, mode)?;
                let counts: Vec<String> = by_rule.iter().map(|(r, s)| format!("{} {}", r, s.len())).collect();
                Ok(format!("{}: baseline {} ({} rows; {});{}", meta.name, baseline, n, counts.join(", "), ceiling_note))
            }
            Policy::Ceilings { baseline, header } => {
                let path = root.join(baseline);
                let n = match mode {
                    Mode::Update => baseline::update_ceilings(&path, header, &run.sites)?,
                    Mode::Migrate => baseline::read_ceilings(&path).len(),
                    Mode::Seed => {
                        let counts = baseline::key_counts(&run.sites);
                        baseline::write_ceilings(&path, header, &counts)?;
                        counts.len()
                    }
                };
                Ok(format!("{}: baseline {} ({} entries)", meta.name, baseline, n))
            }
            Policy::Hard => Ok(format!("{}: no baseline (hard ban);{}", meta.name, ceiling_note)),
            Policy::Custom => custom(run, mode),
        }
    }

pub fn original_allow_usage(tree:&crate::tree::Tree,outcomes:&[Outcome])->std::collections::BTreeSet<(String,String,u32)>{
    use sha1::{Digest,Sha1};
    let mut rows: std::collections::BTreeSet<(String, String, u32)> = std::collections::BTreeSet::new();
    let mut digests: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    for o in outcomes {
        for u in &o.allow_used {
            let digest = digests.entry(u.rel.clone()).or_insert_with(|| match tree.get(&u.rel) {
                Some(f) => {
                    let mut h = Sha1::new();
                    h.update(f.text().trim_end_matches('\n').as_bytes());
                    h.finalize().iter().map(|b| format!("{:02x}", b)).collect()
                }
                None => String::new(),
            });
            rows.insert((u.name.clone(), digest.clone(), u.line));
        }
    }

    rows
}
