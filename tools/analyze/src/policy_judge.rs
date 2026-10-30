//! Shared client-side ratchet judgement over already-computed findings.
//! No semantic model, scanner, query cache or frontend is constructed here.
//! Baseline file IO belongs after native query/page delivery, never inside it.
use crate::{
    baseline,
    lint::{Cx, Lint, Policy, Run},
};
use std::{
    collections::HashSet,
    fmt::Write as _,
    path::{Path, PathBuf},
};
pub fn judge(
    lint: &dyn Lint,
    cx: &Cx<'_>,
    run: &Run,
    root: &Path,
    changed: &Option<HashSet<String>>,
    raw: bool,
) -> (bool, String) {
    let meta = lint.meta();
    let mut text = String::new();
    for n in &run.notes {
        let _ = writeln!(text, "{}", n);
    }
    // `--changed-only`: judge only the sites in files that changed.
    let filtered: Run;
    let run = match changed {
        Some(changed) => {
            filtered = Run {
                sites: run
                    .sites
                    .iter()
                    .filter(|s| changed.contains(&s.rel))
                    .cloned()
                    .collect(),
                notes: run.notes.clone(),
            };
            &filtered
        }
        None => run,
    };
    let mut by_rule = run.by_rule(meta);
    let hints = |rule: &str| {
        meta.rule(rule)
            .map(|r| r.hint.to_string())
            .unwrap_or_default()
    };
    // Rules with a configured ceiling (`[lint.<name>.ceilings]`) are judged by their count.
    let mut ceiling_failed = false;
    if !raw
        && matches!(meta.policy, Policy::Sites { .. } | Policy::Hard)
        && !cx.scope.ceilings.is_empty()
    {
        let (with, without): (Vec<_>, Vec<_>) = by_rule
            .into_iter()
            .partition(|(r, _)| cx.scope.ceilings.contains_key(*r));
        by_rule = without;
        for (rule, found) in &with {
            let ceiling = cx.scope.ceilings[*rule];
            let count = found.len() as i64;
            let status = if count > ceiling {
                ceiling_failed = true;
                format!("FAIL (rose above its ceiling {})", ceiling)
            } else if count < ceiling {
                format!(
                    "below ceiling {}: lower it with `analyze baseline --update`",
                    ceiling
                )
            } else {
                "ok".to_string()
            };
            let _ = writeln!(
                text,
                "{} {:<19} {:>6}  (ceiling {})  {}",
                meta.label, rule, count, ceiling, status
            );
            if count > ceiling {
                let hint = hints(rule);
                let suffix = if hint.is_empty() {
                    String::new()
                } else {
                    format!(" -- {}", hint)
                };
                for s in found.iter().take(60) {
                    let body = if s.msg.is_empty() {
                        cx.tree.site_text(&s.rel, s.line as usize)
                    } else {
                        s.msg.clone()
                    };
                    let _ = writeln!(
                        text,
                        "{}:{}: [{}/{}] {}{}",
                        s.rel, s.line, meta.label, rule, body, suffix
                    );
                }
                if found.len() > 60 {
                    let _ = writeln!(text, "... and {} more", found.len() - 60);
                }
            }
        }
    }
    let failed = ceiling_failed
        | match meta.policy {
            Policy::Sites {
                baseline, banned, ..
            } => {
                let path = if raw {
                    PathBuf::from("")
                } else {
                    root.join(baseline)
                };
                baseline::check_sites(
                    meta.label, cx.tree, &by_rule, &hints, &path, banned, &mut text,
                )
            }
            Policy::Ceilings { baseline, .. } => {
                let path = if raw {
                    PathBuf::from("")
                } else {
                    root.join(baseline)
                };
                let rules: Vec<&str> = meta.rules.iter().map(|r| r.name).collect();
                baseline::check_ceilings(meta.label, &run.sites, &rules, &path, &mut text)
            }
            Policy::Hard => {
                let mut failed = false;
                for (rule, found) in &by_rule {
                    let _ = writeln!(
                        text,
                        "{}: {} {} {}",
                        meta.label,
                        rule,
                        found.len(),
                        if found.is_empty() { "OK" } else { "FAIL" }
                    );
                    let hint = hints(rule);
                    for s in found {
                        failed = true;
                        let body = if s.msg.is_empty() {
                            cx.tree.site_text(&s.rel, s.line as usize)
                        } else {
                            s.msg.clone()
                        };
                        let suffix = if hint.is_empty() {
                            String::new()
                        } else {
                            format!(" -- {}", hint)
                        };
                        let _ = writeln!(
                            text,
                            "{}:{}: [{}/{}] {}{}",
                            s.rel, s.line, meta.label, rule, body, suffix
                        );
                    }
                }
                failed
            }
            Policy::Custom => lint.finish_raw(cx, run, &mut text, raw),
        };
    let failed = if matches!(meta.policy, Policy::Custom) {
        failed
    } else {
        lint.post_judge(cx, run, &mut text) | failed
    };
    (failed, text)
}

#[cfg(test)]
#[path = "policy_judge_tests.rs"]
mod tests;
