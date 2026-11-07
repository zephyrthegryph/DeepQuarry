//! Common report/baseline policy over delivered, already-admitted evidence.
//! No source scanner, Tree, parser, source receipt or request cache is created.
//! The caller supplies real Meta, captured scope/SiteText and explicit custom hooks;
//! this data-only module cannot certify omitted policies or source completeness.
use crate::{baseline::{self,Mode,SiteText},lint::{Meta,Policy,Run,AllowUse},scopes::LintScope};
use std::{collections::{HashSet,BTreeSet,HashMap},path::Path,time::Duration,fmt::Write as _};

#[derive(Clone, Debug, Default)]
pub struct Timing {
    pub total: Duration,
    pub files: usize,
    pub rescanned: usize,
    pub tree_memo_hit: bool,
}

pub struct Outcome {
    pub name: String,
    pub failed: bool,
    pub text: String,
    pub run: Run,
    pub allow_used: Vec<AllowUse>,
    pub timing: Timing,
    pub internal_error: Option<String>,
}

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


/// Common completion of one already-produced run. Hooks are mandatory: a
/// caller must port a custom/post policy rather than silently replace it.
pub fn finish_report<S:SiteText+?Sized>(meta:&Meta,scope:&LintScope,source:&S,run:Run,allow_used:Vec<AllowUse>,timing:Timing,root:&Path,changed:&Option<HashSet<String>>,raw:bool,custom:impl FnMut(&Run,&mut String,bool)->bool,post:impl FnMut(&Run,&mut String)->bool)->Outcome{
 let(failed,text)=crate::policy_judge::judge_report(meta,scope,source,&run,root,changed,raw,custom,post);
 Outcome{name:meta.name.to_owned(),failed,text,run,allow_used,timing,internal_error:None}
}

/// Exact original baseline update. All IO is the existing baseline/ceiling
/// publisher after source delivery; no mutable source is reread here.
pub fn update_baseline_report<S:SiteText+?Sized>(meta:&Meta,scope:&LintScope,source:&S,run:&Run,root:&Path,scopes_root:&Path,mode:Mode,mut custom:impl FnMut(&Run,Mode)->std::io::Result<String>)->std::io::Result<String>{
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


/// As-of normalized whole-file digest data from a validated response. Neither
/// variant grants a source role. Missing transport evidence is an Err from the
/// mandatory provider; it must never be confused with observed source absence.
pub enum AllowFileDigest<'a>{Captured(&'a str),CapturedOwned(String),ProvenMissing}
/// Exact old ordered name/digest/line rows. The original code intentionally
/// ignores reason codes and deduplicates identical rows across lint outcomes.
pub fn allow_usage_rows<'a,E>(outcomes:&[Outcome],mut digest:impl FnMut(&str)->Result<AllowFileDigest<'a>,E>)->Result<BTreeSet<(String,String,u32)>,E>{
 let mut rows=BTreeSet::new();let mut digests:HashMap<String,String>=HashMap::new();
 for outcome in outcomes{for used in &outcome.allow_used{
  if !digests.contains_key(&used.rel){let value=match digest(&used.rel)?{AllowFileDigest::Captured(value)=>value.to_owned(),AllowFileDigest::CapturedOwned(value)=>value,AllowFileDigest::ProvenMissing=>String::new()};digests.insert(used.rel.clone(),value);}
  rows.insert((used.name.clone(),digests.get(&used.rel).unwrap().clone(),used.line));
 }}Ok(rows)
}
pub fn write_allow_rows(rows:&BTreeSet<(String,String,u32)>,output:&mut impl std::io::Write)->std::io::Result<()>{for(name,digest,line)in rows{writeln!(output,"{}\t{}\t{}",name,digest,line)?;}Ok(())}

#[cfg(test)]#[path="policy_finish_tests.rs"]mod tests;

/// Exact final CLI line, after any existing timing/unused-ALLOW presentation.
/// Failed labels intentionally retain input order and duplicates.
pub fn result_line(failed: &[String]) -> String {
    let mut line = Vec::new();
    write_result_line(failed.iter().map(String::as_str), &mut line)
        .expect("writing the result line into a Vec cannot return an I/O error");
    String::from_utf8(line).expect("the result line writes only valid UTF-8")
}

/// Borrow labels from the actual ordered result producer and write once.
/// True means no failed labels, including the optional unused-ALLOW suffix.
pub fn write_result_line<'a>(
    failed: impl IntoIterator<Item = &'a str>, output: &mut impl std::io::Write,
) -> std::io::Result<bool> {
    let mut labels = failed.into_iter();
    let Some(first) = labels.next() else {
        output.write_all(b"All ratchet lints passed.\n")?;
        return Ok(true);
    };
    output.write_all(b"Ratchet lints failed: ")?;
    output.write_all(first.as_bytes())?;
    for label in labels {
        output.write_all(b" ")?;
        output.write_all(label.as_bytes())?;
    }
    output.write_all(b"\n")?;
    Ok(false)
}

#[cfg(test)]
mod result_line_tests {
    use super::*;

    #[test]
    fn whole_cli_result_line_preserves_success_order_duplicates_and_selftest_labels() {
        assert_eq!(result_line(&[]), "All ratchet lints passed.\n");
        assert_eq!(
            result_line(&["qdel_src".into(),"scheduler".into(),"scheduler --selftest".into(),"scheduler".into()]),
            "Ratchet lints failed: qdel_src scheduler scheduler --selftest scheduler\n",
        );
    }

    #[test]
    fn streamed_result_handles_registry_sized_sequence_and_preserves_first_io() {
        let labels: Vec<_> = (0..104).map(|n| format!("policy_{n}")).collect();
        let mut line = Vec::new();
        assert!(!write_result_line(labels.iter().map(String::as_str), &mut line).unwrap());
        assert_eq!(line, format!("Ratchet lints failed: {}\n", labels.join(" ")).as_bytes());

        struct Fails;
        impl std::io::Write for Fails {
            fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
                Err(std::io::Error::from_raw_os_error(1450))
            }
            fn flush(&mut self) -> std::io::Result<()> { Ok(()) }
        }
        let mut labels = ["one", "two"].into_iter();
        let error = write_result_line(&mut labels, &mut Fails).unwrap_err();
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(labels.next(), Some("two"));
    }
}

#[path="policy_report_admitted.rs"]pub mod admitted;

pub use dq_analyze_client::policy_report_wire as derived_wire;
