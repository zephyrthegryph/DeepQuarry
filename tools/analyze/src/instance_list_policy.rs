//! Unique original per-instance list lexical facts; DATA only, no source role.
use std::collections::{BTreeSet,HashMap,HashSet};
use serde::{Deserialize,Serialize};
use crate::{lint::{AllowUse,Meta,Policy,RuleMeta,ScanKind},tree::{Select,SourceFile},pat::Pat,util::{py_rstrip,py_strip},key_policy_control::{self as kc,Control},pat,pat_match};
pub const LINT: &str = "instance_list";
const SHARED_MODS: &[&str] = &["static", "global", "const"];

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::instance_list::SCOPE_META_0.name,
    group: crate::allow_registry_fields::instance_list::SCOPE_META_0.group,
    label: "instance_list",
    legacy: "tools/ci/instance_list_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "instance_list",
        hint: "allocates a list per instance: use a static var or getter (constant table), a lazy list (usually empty) or a starting list (`per_type(nameof(v), PROC_REF(build), copy_on_write = TRUE)`, AGENTS.md 3a); if it really is per-instance and always filled, mark it `// ALLOW(instance_list): <reason>`",
    }],
    allow: crate::allow_registry_fields::instance_list::ALLOW_0,
    lists: crate::allow_registry_fields::instance_list::SCOPE_META_0.lists,
};


fn row<C:Control,T>(c:&mut C,rows:&mut Vec<T>)->Result<(),C::Error>{if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}let target=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;let bound=target.checked_mul(4).ok_or_else(||c.overflow())?;kc::reserve(c,||bound.checked_mul(std::mem::size_of::<T>())?.checked_add(128))?;rows.try_reserve_exact(target-rows.len()).map_err(|_|c.allocation_failed())?;if rows.capacity()>bound{return Err(c.allocation_failed())}Ok(())}


// Exactly one formatted candidate is live. Old type/modifier contexts now borrow
// their actual raw line; only a positive increase of this temporary peak is charged.
fn candidate<C:Control>(c:&mut C,peak:&mut usize,args:std::fmt::Arguments<'_>)->Result<String,C::Error>{
 if !C::CHECKED{return Ok(std::fmt::format(args))}
 struct Count<'a,C:Control>{control:&'a mut C,count:usize,error:Option<C::Error>}
 impl<C:Control>std::fmt::Write for Count<'_,C>{fn write_str(&mut self,text:&str)->std::fmt::Result{if self.error.is_some(){return Err(std::fmt::Error)}if let Err(actual)=self.control.checkpoint(){self.error=Some(actual);return Err(std::fmt::Error)}match self.count.checked_add(text.len()){Some(next)=>{self.count=next;Ok(())},None=>{self.error=Some(self.control.overflow());Err(std::fmt::Error)}}}}
 let mut count=Count{control:c,count:0,error:None};let result=std::fmt::write(&mut count,args);if let Some(actual)=count.error.take(){return Err(actual)}if result.is_err(){return Err(count.control.allocation_failed())}let width=count.count;drop(count);let bound=width.checked_mul(8).and_then(|n|n.checked_add(256)).ok_or_else(||c.overflow())?;if bound>*peak{c.reserve(bound-*peak)?;*peak=bound;}let text=std::fmt::format(args);if text.capacity()>bound{return Err(c.allocation_failed())}c.checkpoint()?;Ok(text)
}

/// `var/[mods/]list/[typed/path/]name = list(...) | new/list(...) | new(...) | new`.
fn init_re() -> &'static Pat {
    pat_match!(
        r"^(?:var/)?((?:\w+/)*?)list/(?:\w+/)*?(\w+)\s*(?:=\s*(?:list\s*\(|alist\s*\(|new\s*/list|new\s*\(|new\s*$)|\[\s*\w+\s*\])"
    )
}

/// `strip_comment`: cut a `//` that is not inside a string (an escaped quote is skipped, as the
/// Python's `text[i - 1] != "\\"` does).
pub fn strip_comment(text: &str) -> &str {
    let mut in_str: Option<char> = None;
    let mut prev = '\0';
    for (i, ch) in text.char_indices() {
        if let Some(q) = in_str {
            if ch == q && prev != '\\' {
                in_str = None;
            }
        } else if ch == '"' || ch == '\'' {
            in_str = Some(ch);
        } else if text[i..].starts_with("//") {
            return py_rstrip(&text[..i]);
        }
        prev = ch;
    }
    py_rstrip(text)
}

/// `indent_of`: the number of leading tabs.
fn indent_of(line: &str) -> usize {
    line.len() - line.trim_start_matches('\t').len()
}

/// `scan_file`: `(type_path, var_name, line number)` of every per-instance list declaration.
pub fn scan_decls_using<C:Control>(f:&SourceFile,c:&mut C)->Result<Vec<(String,String,usize)>,C::Error>{
    let mut found = Vec::new();
    let mut type_path: Option<&str> = None;
    let mut candidate_peak=0usize;
    let mut in_proc = false;
    let mut proc_indent = 0usize;
    let mut var_block: Option<(usize, &str)> = None; // (indent, modifiers) of an open `var` block
    let mut in_comment = false;
    let head=pat_match!(r"^(/[\w/]+?)/var/(.*)$");kc::reserve(c,||head.capture_group_count().checked_add(init_re().capture_group_count())?.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(256))?;
    for (number, raw) in f.raw().numbered() {c.checkpoint()?;
        let line = raw.trim_end_matches('\r');
        let stripped = py_strip(line);
        if in_comment {
            if stripped.contains("*/") {
                in_comment = false;
            }
            continue;
        }
        if stripped.starts_with("/*") && !stripped.contains("*/") {
            in_comment = true;
            continue;
        }
        if stripped.is_empty() || stripped.starts_with("//") || stripped.starts_with('#') {
            continue;
        }
        let depth = indent_of(line);
        let body = strip_comment(stripped);
        if depth == 0 {
            var_block = None;
            in_proc = false;
            type_path = None;
            if body.contains('(') {
                in_proc = true; // a top-level proc definition
                continue;
            }
            if !body.starts_with('/') {
                continue;
            }
            if let Some(m) = pat_match!(r"^(/[\w/]+?)/var/(.*)$").captures(body) {
                let candidate = candidate(c,&mut candidate_peak,format_args!("var/{}",m.s(2)))?;
                if let Some(decl) = init_re().captures(&candidate) {
                    // A substring test on the modifier text, not a segment test.
                    if !SHARED_MODS.iter().any(|s| decl.s(1).contains(s)) {
                        row(c,&mut found)?;found.push((kc::own(c,m.s(1))?,kc::own(c,decl.s(2))?,number));
                    }
                }
                continue;
            }
            type_path = Some(py_strip(body.trim_end_matches('{')));
            continue;
        }
        let Some(tp) = type_path.as_ref() else { continue };
        if in_proc {
            if depth > proc_indent {
                continue;
            }
            in_proc = false;
        }
        if let Some((d, _)) = &var_block {
            if depth <= *d {
                var_block = None;
            }
        }
        if var_block.is_none() && pat_match!(r"^(?:(?:proc|verb)/)?\w+\(.*\)\s*$").is_match(body) {
            in_proc = true;
            proc_indent = depth;
            continue;
        }
        if var_block.is_none() && pat_match!(r"^var(?:/(?:static|global|tmp|const))*$").is_match(body) {
            var_block = Some((depth,body[3..].trim_matches('/')));
            continue;
        }
        let candidate = if body.starts_with("var/") {
            std::borrow::Cow::Borrowed(body)
        } else if let Some((_, mods)) = &var_block {
            std::borrow::Cow::Owned(candidate(c,&mut candidate_peak,format_args!("var/{}{}{}",mods,if mods.is_empty(){""}else{"/"},body))?)
        } else {
            continue;
        };
        if let Some(decl) = init_re().captures(&candidate) {
            if !decl.s(1).split('/').any(|m| SHARED_MODS.contains(&m)) {
                row(c,&mut found)?;found.push((kc::own(c,tp)?,kc::own(c,decl.s(2))?,number));
            }
        }
    }
    c.checkpoint()?;Ok(found)
}
pub fn scan_decls(f:&SourceFile)->Vec<(String,String,usize)>{scan_decls_using(f,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}

/// One file's contribution: its per-instance list declarations and the `GLOBAL_DATUM_INIT` types
/// it creates.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    pub decls: Vec<(String, String, u32)>,
    pub globals: Vec<String>,
}

/// One file's declarations that survive the singleton and ALLOW questions.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Judged {
    pub decls: Vec<(String, String, u32)>,
    pub uses: Vec<AllowUse>,
}

pub fn globals_of_using<C:Control>(f:&SourceFile,c:&mut C)->Result<Vec<String>,C::Error>{let mut globals=Vec::new();if f.rel.starts_with("code/"){let text=f.raw().text.as_str();let global=pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\b");let system=pat!(r"(?m)^SYSTEM_DEF\((\w+)\)");kc::reserve(c,||global.capture_group_count().checked_add(system.capture_group_count())?.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(256))?;if text.contains("GLOBAL_DATUM_INIT"){for m in global.captures_iter(text){c.checkpoint()?;row(c,&mut globals)?;globals.push(kc::own(c,m.s(1))?);}}if text.contains("SYSTEM_DEF("){for m in system.captures_iter(text){c.checkpoint()?;row(c,&mut globals)?;globals.push(kc::format(c,format_args!("/datum/system/{}",m.s(1)))?);}}}kc::reserve(c,||globals.len().checked_mul(std::mem::size_of::<String>())?.checked_add(128))?;globals.sort();globals.dedup();c.checkpoint()?;Ok(globals)}
pub fn facts_of(f:&SourceFile)->Facts{Facts{decls:scan_decls(f).into_iter().map(|(t,v,n)|(t,v,n as u32)).collect(),globals:globals_of_using(f,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}}
/// Input order is the SAME actual NTFS walk-key order supplied by both adapters.
/// Ordered results/ALLOW uses remain unsealed, no whole-source grant is made.
pub fn finish_using<'a,C:Control>(files:impl IntoIterator<Item=(&'a str,&'a Judged)>,c:&mut C,allowed:&mut dyn FnMut(&AllowUse,&mut C)->Result<(),C::Error>,emit:&mut dyn FnMut(usize,&str,u32,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{let mut seen=HashSet::new();let mut found=Vec::new();let mut used=Vec::new();for(index,(relative,judged))in files.into_iter().enumerate(){c.checkpoint()?;for value in &judged.uses{c.checkpoint()?;if !used.contains(&value){row(c,&mut used)?;used.push(value);allowed(value,c)?;}}for(owner,name,line)in &judged.decls{c.checkpoint()?;let key=kc::format(c,format_args!("{owner}/{name}"))?;if !seen.contains(&key){kc::reserve(c,||Some(2048))?;seen.insert(key);row(c,&mut found)?;found.push((kc::format(c,format_args!("{relative}:{line}"))?,index,relative,*line));}}}kc::reserve(c,||found.len().checked_mul(std::mem::size_of::<(String,usize,&str,u32)>())?.checked_add(128))?;found.sort_by(|a,b|a.0.cmp(&b.0));for(_,index,relative,line)in found{c.checkpoint()?;emit(index,relative,line,c)?;}c.checkpoint()}

/// Pure membership DATA from the same actual registered Select.
pub fn selects_path(relative:&str)->bool{META.select.matches_path(relative)}
