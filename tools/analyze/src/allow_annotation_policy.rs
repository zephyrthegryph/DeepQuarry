//! The unique ALLOW validation and unused-annotation algorithms.
//! Every input here is DATA. This module issues no source/registry/run completeness.
use std::collections::{BTreeMap,BTreeSet};
use crate::tree::CODE_MAPS_DM;
use crate::{allow,pat::Pat,util::py_split,lint::{AllowUse,Meta,Policy,RuleMeta,ScanKind},key_policy_control::{self as kc,Control}};
const MIN_REASON: usize = 20;
const MIN_REASON_WORDS: usize = 3;

/// Lints whose annotations the usage check cannot observe: check_grep reads the same line only and
/// doc_snippets reads the design docs, not the .dm tree.
pub const UNOBSERVED: &[&str] = &["check_grep", "doc_snippets"];


fn vague() -> &'static [(Pat, &'static str)] {
    static V: std::sync::LazyLock<Vec<(Pat, &'static str)>> = std::sync::LazyLock::new(|| {
        vec![
            (Pat::new(r"(?i)\ballowlist(?:s|ed)?\b"), "there is no allowlist: say why this site stays"),
            (Pat::new(r"(?i)\b(?:see|as) (?:above|below)\b"), "say the reason here, not on another line"),
            (Pat::new(r"(?i)\bnot edited here\b"), "a deferred conversion is not a reason: convert the site or say why it must stay"),
            (Pat::new(r"(?i)\bS\d+\b|\bwave F\d+|\bsec(?:tion)? \d|\bphase \d"), "a plan-phase label names the plan, not the reason"),
            (Pat::new(r"\b[A-Z]\d{1,2}[a-z]?(?:/[A-Z]?\d{1,2}[a-z]?)*\b"), "a plan item code (M1a, C9, P3, ...) names the plan, not the reason"),
        ]
    });
    &V
}

/// Why `reason` is not a reason, or None (`reason_problem`).
pub fn reason_problem(reason: &str) -> Option<String> {
    let text = crate::util::py_strip(reason);
    if text.chars().count() < MIN_REASON || py_split(text).count() < MIN_REASON_WORDS {
        return Some(format!(
            "reason {} is too short to explain anything (at least {} characters and {} words)",
            py_repr(text),
            MIN_REASON,
            MIN_REASON_WORDS
        ));
    }
    for (pattern, why) in vague() {
        if pattern.is_match(text) {
            let shown = if text.chars().count() <= 70 { text.to_string() } else { format!("{}...", text.chars().take(67).collect::<String>()) };
            return Some(format!("reason {}: {}", py_repr(&shown), why));
        }
    }
    None
}

/// Python's `%r` of a str (single quotes unless the text has a single and no double quote).
pub(crate) fn py_repr(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') { '"' } else { '\'' };
    let mut out = String::new();
    out.push(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

struct Names<'a>(&'a BTreeSet<String>);
impl std::fmt::Display for Names<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{for(i,name)in self.0.iter().enumerate(){if i!=0{f.write_str(", ")?}f.write_str(name)?}Ok(())}}
/// Same reason policy, with its real temporary/result overlap admitted before formatting.
pub fn reason_problem_with<C:Control>(reason:&str,control:&mut C)->Result<Option<String>,C::Error>{
 kc::reserve(control,||reason.len().checked_mul(12)?.checked_add(2048))?;let value=reason_problem(reason);control.checkpoint()?;Ok(value)
}
/// Lends each complete owned message in exact original per-line/rule/name order.
pub fn validate_line<C:Control>(known:&BTreeSet<String>,number:usize,line:&str,control:&mut C,mut emit:impl FnMut(&'static str,usize,String)->Result<(),C::Error>)->Result<(),C::Error>{
 if !line.contains("ALLOW("){return Ok(())}
 let Some(a)=allow::parse_with(line,control)?else{let message=kc::own(control,"malformed ALLOW annotation; write \x60// ALLOW(<lint>[, <lint>]): <reason>\x60")?;emit("malformed",number,message)?;return Ok(())};
 if a.names.is_empty(){let message=kc::own(control,"ALLOW() names no lint")?;emit("no_lint",number,message)?;}
 for name in a.names.iter().filter(|name|!known.contains(*name)){let message=kc::format(control,format_args!("ALLOW({}): unknown lint; known: {}",name,Names(known)))?;emit("unknown_lint",number,message)?;}
 if a.reason.is_empty(){let message=kc::format(control,format_args!("ALLOW({}) has no reason after the colon",Names(&a.names)))?;emit("no_reason",number,message)?;}else if let Some(weak)=reason_problem_with(&a.reason,control)?{let message=kc::format(control,format_args!("ALLOW({}): {}",Names(&a.names),weak))?;emit("weak_reason",number,message)?;}
 control.checkpoint()
}
/// Unsealed per-file facts; malformed marker lines remain relevant to digest mapping.
pub fn annotations<C:Control>(lines:impl IntoIterator<Item=(usize,impl AsRef<str>)>,control:&mut C)->Result<Vec<(u32,Vec<String>)>,C::Error>{
 let mut rows=Vec::new();for(number,line)in lines{control.checkpoint()?;let line=line.as_ref();if !line.contains("ALLOW("){continue}let Some(parsed)=allow::parse_with(line,control)?else{continue};let number=if C::CHECKED{u32::try_from(number).map_err(|_|control.overflow())?}else{number as u32};let mut names=Vec::new();for name in parsed.names{kc::row(control,&mut names)?;names.push(name);}kc::row(control,&mut rows)?;rows.push((number,names));}Ok(rows)
}
pub struct AnnotationFile<'a>{pub relative:&'a str,pub has_marker:bool,pub annotations:&'a [(u32,Vec<String>)]}
/// Full-run policy over DATA. This function issues no source/execution completion.
pub fn unused<C:Control>(known:&BTreeSet<String>,used:&[AllowUse],extra_used:&[(String,String,u32)],files:&[AnnotationFile<'_>],digest:&dyn Fn(&str)->String,control:&mut C)->Result<Vec<String>,C::Error>{
 let mut used_set:Usage=BTreeMap::new();let mut seen:BTreeSet<String>=BTreeSet::new();
 for row in used{insert_seen(&mut seen,&row.name,control)?;insert_use(&mut used_set,&row.name,&row.rel,row.line,control)?;}
 let mut by_digest:BTreeMap<String,String>=BTreeMap::new();
 for(name,value,line)in extra_used{control.checkpoint()?;insert_seen(&mut seen,name,control)?;if !by_digest.contains_key(value){for file in files{if !file.has_marker{continue}kc::reserve(control,||file.relative.len().checked_mul(4)?.checked_add(256))?;if digest(file.relative)==*value{kc::reserve(control,||value.len().checked_add(file.relative.len())?.checked_mul(4)?.checked_add(2048))?;by_digest.insert(value.clone(),file.relative.to_owned());break}}}if let Some(relative)=by_digest.get(value){insert_use(&mut used_set,name,relative,*line,control)?;}}
 let mut problems=Vec::new();let mut quiet:BTreeMap<String,usize>=BTreeMap::new();
 for file in files{for(number,names)in file.annotations{for name in names.iter().filter(|name|known.contains(*name)){control.checkpoint()?;if UNOBSERVED.contains(&name.as_str()){continue}if !seen.contains(name){if let Some(count)=quiet.get_mut(name){*count=if C::CHECKED{count.checked_add(1).ok_or_else(||control.overflow())?}else{*count+1};}else{kc::reserve(control,||name.len().checked_mul(4)?.checked_add(2048))?;quiet.insert(name.clone(),1);}continue}
 if !has_use(&used_set,name,file.relative,*number){let message=kc::format(control,format_args!("{}:{}: ALLOW({}) is unused: no longer triggers the {} lint; delete the annotation (or the site's reason is stale)",file.relative,number,name,name))?;kc::row(control,&mut problems)?;problems.push(message);}
 }}}
 for(name,count)in quiet{let message=kc::format(control,format_args!("ALLOW({}): {} annotation{}, but no lint run used any: the {} lint is not run, or every one of them is stale",name,count,if count==1{""}else{"s"},name))?;kc::row(control,&mut problems)?;problems.push(message);}control.checkpoint()?;Ok(problems)
}
fn insert_seen<C:Control>(seen:&mut BTreeSet<String>,name:&str,control:&mut C)->Result<(),C::Error>{if !seen.contains(name){kc::reserve(control,||name.len().checked_mul(4)?.checked_add(2048))?;seen.insert(name.to_owned());}Ok(())}
type Usage=BTreeMap<String,BTreeMap<String,BTreeSet<u32>>>;
fn has_use(used:&Usage,name:&str,relative:&str,line:u32)->bool{used.get(name).and_then(|files|files.get(relative)).is_some_and(|lines|lines.contains(&line))}
fn insert_use<C:Control>(used:&mut Usage,name:&str,relative:&str,line:u32,control:&mut C)->Result<(),C::Error>{
 if has_use(used,name,relative,line){return Ok(())}
 if !used.contains_key(name){kc::reserve(control,||name.len().checked_mul(4)?.checked_add(2048))?;used.insert(name.to_owned(),BTreeMap::new());}
 let files=used.get_mut(name).unwrap();if !files.contains_key(relative){kc::reserve(control,||relative.len().checked_mul(4)?.checked_add(2048))?;files.insert(relative.to_owned(),BTreeSet::new());}
 kc::reserve(control,||Some(2048))?;files.get_mut(relative).unwrap().insert(line);Ok(())
}

static META: Meta = Meta {
    name: crate::allow_registry_fields::allow_annotations::SCOPE_META_0.name,
    group: crate::allow_registry_fields::allow_annotations::SCOPE_META_0.group,
    label: "allow_annotations",
    legacy: "tools/ci/allow_annotations.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "malformed", hint: "" },
        RuleMeta { name: "no_lint", hint: "" },
        RuleMeta { name: "unknown_lint", hint: "" },
        RuleMeta { name: "no_reason", hint: "" },
        RuleMeta { name: "weak_reason", hint: "" },
    ],
    allow: crate::allow_registry_fields::allow_annotations::ALLOW_0,
    lists: crate::allow_registry_fields::allow_annotations::SCOPE_META_0.lists,
};
/// SAME original descriptor for source-selection and reporting metadata.
pub fn metadata()->&'static Meta{&META}

#[cfg(test)]#[path="allow_annotation_policy_tests.rs"]mod tests;
