//! SAME complete original Lifeforms raw marker/declaration/source judges.
//! No second marker parser/model/cache or source authority.
use crate::key_policy_control::Gate;
use std::collections::{BTreeMap,BTreeSet,HashMap};
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::{SourceFile,CODE_DM},raw_marker_policy::{matching_paren,split_args},lifeform_source_policy::is_engine};
pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::lifeforms::SCOPE_META_0.name,
    group: crate::allow_registry_fields::lifeforms::SCOPE_META_0.group,
    label: "lifeforms",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "make_unknown_param", hint: "declare it on the made type: param(nameof(var), schema) in its CAPABILITIES block (code/engine/lifeforms/params.dm)" },
        RuleMeta { name: "make_missing_required", hint: "pass every required param: make(/T, at = loc, name = value)" },
        RuleMeta { name: "make_parts_without_built_from", hint: "declare built_from(nameof(var)) on the made type, or drop parts =" },
        RuleMeta { name: "after_init_bare_new", hint: "the type declares after_init(), which a plain datum runs only when made by make(/T, ...): make it with make()" },
        RuleMeta { name: "per_type_write", hint: "a per_type() table is read-only and shared by every instance of the type: build it in its build proc, copy it to change it" },
        RuleMeta { name: "ctor_dead_arg", hint: "no param(nameof(v), pos = N) of the type takes the argument and no New()/Initialize() reads it: drop it (python3 tools/dx/codemods/ctor_args.py --apply), or declare the param it was meant for" },
        RuleMeta { name: "ctor_forward_only", hint: "the override only hands these parameters to ..(), which passes the caller's arguments by itself: drop them (python3 tools/dx/codemods/ctor_args.py --apply)" },
        RuleMeta { name: "param_pos_override", hint: "an ancestor already maps this constructor position: say param(..., pos = N, overrides = TRUE) when the subtype means to take it over" },
        RuleMeta { name: "param_overrides_nothing", hint: "overrides = TRUE but no ancestor declares a param at this position: drop overrides =" },
    ],
    allow: crate::allow_registry_fields::lifeforms::ALLOW_0,
    lists: crate::allow_registry_fields::lifeforms::SCOPE_META_0.lists,
};

#[derive(Default)]
pub(crate) struct Declared {
    pub(crate) params: HashMap<String, BTreeSet<String>>,
    pub(crate) required: HashMap<String, BTreeSet<String>>,
    pub(crate) built_from: BTreeSet<String>,
    /// type -> (var, build proc)
    pub(crate) per_type: HashMap<String, Vec<(String, String)>>,
    /// Plain datum types whose block declares after_init().
    pub(crate) after_init: BTreeSet<String>,
    /// type -> constructor position -> (var, overrides = TRUE, file, line of the CAPABILITIES block)
    pub(crate) positions: HashMap<String, BTreeMap<usize, (String, bool, String, u32)>>,
}

impl Declared {
    pub(crate) fn marker_using(&mut self,ty:&str,args:&[String],relative:&str,line:u32, gate:&dyn Gate) {
 if !gate.checkpoint(){return;}

        if gate.checked()&&!gate.reserve(ty.len().checked_add(64)){return;}let ty = ty.trim().to_string();
            for a in args.iter().skip(1) {
 if !gate.checkpoint(){return;}
                for (name, args) in calls_using(a, gate) {
 if gate.checked()&&!gate.reserve(ty.len().checked_mul(8).and_then(|n|n.checked_add(relative.len().checked_mul(2)?)).and_then(|n|n.checked_add(8192)).and_then(|start|args.iter().try_fold(start,|n,arg|n.checked_add(arg.len().checked_mul(12)?)))){return;}
 if !gate.checkpoint(){return;}
                    match name.as_str() {
                        "param" => {
                            let Some(var) = args.first().and_then(|x| nameof_inner_using(x, gate)) else { continue };
                            self.params.entry(ty.clone()).or_default().insert(var.clone());
                            let named = |key: &str| args.iter().find_map(|x| x.replace(' ', "").strip_prefix(&format!("{key}=")).map(|v| v.to_string()));
                            if let Some(pos) = named("pos").and_then(|v| v.parse::<usize>().ok()) {
                                let overrides = named("overrides").is_some_and(|v| v == "TRUE" || v == "1");
                                self.positions.entry(ty.clone()).or_default().insert(pos, (var.clone(), overrides, relative.to_owned(), line));
                            }
                            if args.iter().any(|x| x.replace(' ', "") == "required=TRUE") {
                                self.required.entry(ty.clone()).or_default().insert(var);
                            }
                        }
                        "built_from" => {
                            self.built_from.insert(ty.clone());
                        }
                        "after_init" if ty.starts_with("/datum") => {
                            self.after_init.insert(ty.clone());
                        }
                        "per_type" => {
                            let var = args.first().and_then(|x| nameof_inner_using(x, gate));
                            let build = args.get(1).and_then(|x| x.trim().strip_prefix("PROC_REF(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string()));
                            if let (Some(var), Some(build)) = (var, build) {
                                self.per_type.entry(ty.clone()).or_default().push((var, build));
                            }
                        }
                        _ => {}
                    }
                }
            }
    }

    /// The type and its ancestors (by path prefix), nearest first.
    pub(crate) fn lineage_using(ty: &str, gate:&dyn Gate) -> Vec<String> {
 if !gate.checkpoint(){return Vec::new();}

        let mut parts=Vec::new();for part in ty.split('/') {if !row(&mut parts,gate){return Vec::new()}parts.push(part);}let mut output=Vec::new();for cut in (2..=parts.len()).rev(){if !row(&mut output,gate){return Vec::new()}if gate.checked()&&!gate.reserve(parts[..cut].iter().try_fold(cut,|n,s|n.checked_add(s.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128))){return Vec::new()}output.push(parts[..cut].join("/"));}output
    }

    pub(crate) fn has_param_using(&self, ty: &str, name: &str, gate:&dyn Gate) -> bool {
 if !gate.checkpoint(){return false;}

        Self::lineage_using(ty, gate).iter().any(|t| self.params.get(t).is_some_and(|s| s.contains(name)))
    }

    pub(crate) fn required_of_using(&self, ty: &str, gate:&dyn Gate) -> BTreeSet<String> {
 if !gate.checkpoint(){return BTreeSet::new();}

        let mut out = BTreeSet::new();
        for t in Self::lineage_using(ty, gate) {
 if !gate.checkpoint(){return BTreeSet::new();}
            if let Some(s) = self.required.get(&t) {
                for name in s{if !gate.checkpoint(){return BTreeSet::new()}if !out.contains(name){if gate.checked()&&!gate.reserve(name.len().checked_mul(4).and_then(|n|n.checked_add(512))){return BTreeSet::new()}out.insert(name.clone());}}
            }
        }
        out
    }

    pub(crate) fn builds_from_using(&self, ty: &str, gate:&dyn Gate) -> bool {
 if !gate.checkpoint(){return false;}

        Self::lineage_using(ty, gate).iter().any(|t| self.built_from.contains(t))
    }

    /// `ty` or an ancestor is a plain datum that declares after_init().
    pub(crate) fn after_init_of_using(&self, ty: &str, gate:&dyn Gate) -> Option<String> {
 if !gate.checkpoint(){return None;}

        Self::lineage_using(ty, gate).into_iter().find(|t| self.after_init.contains(t))
    }

    /// A line (comments and strings cleaned) that makes a plain datum declaring after_init() with a bare new: `new /T(...)` or
    /// `var/T/x = new` / `new()`. (made type, declaring type). `new some_var` is a type in a var: /datum/New() reports it at run time.
    pub(crate) fn after_init_bare_new_using(&self, line: &str, gate:&dyn Gate) -> Option<(String, String)> {
 if !gate.checkpoint(){return None;}

        if gate.checked()&&!gate.reserve(Some(1024)){return None;}let bare_new = crate::pat!(r"\bnew\s*(/datum/[\w/]+)");
        let typed_new = crate::pat!(r"\bvar/(datum/[\w/]+)/\w+\s*=\s*new\s*(?:\(|$)");
        let (spelling,prefix)=bare_new.captures(line).and_then(|c|c.get(1)).map(|text|(text,false)).or_else(||typed_new.captures(line).and_then(|c|c.get(1)).map(|text|(text,true)))?;
        if gate.checked()&&!gate.reserve(spelling.len().checked_add(1).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128))){return None;}
        let ty=if prefix{format!("/{spelling}")}else{spelling.to_owned()};let ty=ty.trim_end_matches('/').to_owned();
        let decl = self.after_init_of_using(&ty, gate)?;
        Some((ty, decl))
    }
}

pub(crate) fn nameof_inner_using(arg: &str, gate:&dyn Gate) -> Option<String> {
 if !gate.checkpoint(){return None;}

    if gate.checked()&&!gate.reserve(arg.len().checked_mul(2).and_then(|n|n.checked_add(64))){return None;}arg.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string())
}

/// Every call in `text`: (name, arguments), outermost first, nested calls too.
pub(crate) fn calls_using(text: &str, gate:&dyn Gate) -> Vec<(String, Vec<String>)> {
 if !gate.checkpoint(){return Vec::new();}

    let mut out = Vec::new();
    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
 if !gate.checkpoint(){return Vec::new();}
        if b[i] == b'"' {
            i += 1;
            while i < b.len() && b[i] != b'"' {
 if !gate.checkpoint(){return Vec::new();}
                if b[i] == b'\\' {
                    i += 1;
                }
                i += 1;
            }
            i += 1;
            continue;
        }
        if b[i].is_ascii_alphabetic() || b[i] == b'_' {
            let start = i;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
 if !gate.checkpoint(){return Vec::new();}
                i += 1;
            }
            let prev = if start > 0 { b[start - 1] } else { b' ' };
            if i < b.len() && b[i] == b'(' && prev != b'.' && prev != b'/' {
                if let Some(close) = match crate::raw_marker_policy::matching_paren_using(text,i,&mut Proxy(gate)){Ok(close)=>close,Err(())=>return Vec::new()} {
                    if !gate.checkpoint(){return Vec::new()}let inner=&text[i+1..close];if gate.checked()&&!gate.reserve(inner.len().checked_add(1).and_then(|n|n.checked_mul(4*std::mem::size_of::<String>())).and_then(|n|n.checked_add(inner.len().checked_mul(4)?)).and_then(|n|n.checked_add(i-start)).and_then(|n|n.checked_add(256))){return Vec::new()}if !row(&mut out,gate){return Vec::new()}let arguments=match crate::raw_marker_policy::split_args_using(inner,&mut Proxy(gate)){Ok(rows)=>rows,Err(())=>return Vec::new()};out.push((text[start..i].to_string(),arguments));
                }
            }
            continue;
        }
        i += 1;
    }
    out
}

pub(crate) fn scan_file_using(d:&Declared,f:&SourceFile,emit:&mut dyn FnMut(&'static str,usize,String), gate:&dyn Gate) {
 if !gate.checkpoint(){return;}

 let make=crate::pat!(r"\bmake\(\s*(/[\w/]+)");
            let clean = f.clean();
            if !d.after_init.is_empty() && !is_engine(&f.rel) && f.text().contains("new") {
                for (number, line) in clean.numbered() {
 if !gate.checkpoint(){return;}
                    if !line.contains("new") {
                        continue;
                    }
                    if let Some((ty, decl)) = d.after_init_bare_new_using(line, gate) {
                        if !message(gate,&[&ty,&decl]){return;}emit("after_init_bare_new", number, format!("new {}: {} declares after_init(), which runs only for make({})", ty, decl, ty));
                    }
                }
            }
            if f.text().contains("make(") {
                for (number, line) in clean.numbered() {
 if !gate.checkpoint(){return;}
                    if !line.contains("make(") {
                        continue;
                    }
                    for (name, args) in calls_using(line, gate) {
 if !gate.checkpoint(){return;}
                        if name != "make" {
                            continue;
                        }
                        let Some(first) = args.first() else { continue };
                        if !make.is_match(&format!("make({}", first)) {
                            continue; // a type in a var: checked at runtime
                        }
                        if gate.checked()&&!gate.reserve(first.len().checked_mul(4).and_then(|n|n.checked_add(256))){return;}let ty = first.trim().to_string();
                        let mut given = BTreeSet::new();
                        for a in args.iter().skip(1) {
 if !gate.checkpoint(){return;}
                            let Some((k, _)) = a.split_once('=') else { continue };
                            let k = k.trim();
                            if k.is_empty() || !k.chars().all(|c| c.is_alphanumeric() || c == '_') || a.contains("==") {
                                continue;
                            }
                            if gate.checked()&&!gate.reserve(k.len().checked_mul(4).and_then(|n|n.checked_add(512))){return;}given.insert(k.to_string());
                            if k == "parts" {
                                if !d.builds_from_using(&ty, gate) {
                                    if !message(gate,&[&ty]){return;}emit("make_parts_without_built_from", number, format!("make({}, parts = ...): no built_from()", ty));
                                }
                                continue;
                            }
                            if k == "at" || k == "by" {
                                continue;
                            }
                            if !d.has_param_using(&ty, k, gate) {
                                if !message(gate,&[&ty,k]){return;}emit("make_unknown_param", number, format!("make({}, {} = ...): {} declares no param(nameof({}))", ty, k, ty, k));
                            }
                        }
                        for req in d.required_of_using(&ty, gate) {
 if !gate.checkpoint(){return;}
                            if !given.contains(&req) {
                                if !message(gate,&[&ty,&req]){return;}emit("make_missing_required", number, format!("make({}): the required param {} is not given", ty, req));
                            }
                        }
                    }
                }
            }
            if d.per_type.is_empty() {
                return;
            }
            let procs=match crate::dm::dx::procs_in_using(f,&mut Proxy(gate)){Ok(rows)=>rows,Err(())=>return};
            for p in procs {
 if !gate.checkpoint(){return;}
                if p.is_global() {
                    continue;
                }
                for ancestor in Declared::lineage_using(&p.path, gate) {
 if !gate.checkpoint(){return;}
                    let Some(list) = d.per_type.get(&ancestor) else { continue };
                    for (var, build) in list {
 if !gate.checkpoint(){return;}
                        if &p.name == build {
                            continue;
                        }
                        if gate.checked()&&!gate.reserve(var.len().checked_mul(512).and_then(|n|n.checked_add(16384))){return;}let v = regex::escape(var);
                        let write = regex::Regex::new(&format!(r"(?:^|[^\w.]){v}(?:\s*\[[^\]]*\]\s*=[^=]|\s*(?:\+=|-=|\|=|&=)|\.(?:Add|Remove|Cut|Insert|Swap)\(|\s*=[^=])")).expect("per_type write");
                        for k in 0..p.body_len {
 if !gate.checkpoint(){return;}
                            let number = p.body_start + k;
                            if write.is_match(clean.line(number)) {
                                if !message(gate,&[var,&ancestor]){return;}emit("per_type_write", number, format!("{} is a per_type() table of {}: read-only", var, ancestor));
                            }
                        }
                    }
                }
            }
}

pub(crate) fn position_findings_using(d:&Declared,skip:&dyn Fn(&str)->bool,emit:&mut dyn FnMut(&'static str,&str,usize,String), gate:&dyn Gate){
 if !gate.checkpoint(){return;}

        let mut types=Vec::new();for key in d.positions.keys(){if !row(&mut types,gate){return;}types.push(key);}
        if crate::key_policy_control::sort_data(&mut types,&mut|a,b|->Result<std::cmp::Ordering,()>{if !gate.checkpoint(){return Err(())}Ok(a.cmp(b))}).is_err(){return;}
        for ty in types {
 if !gate.checkpoint(){return;}
            for (pos, (var, overrides, rel, line)) in &d.positions[ty] {
 if !gate.checkpoint(){return;}
                if skip(rel) {
                    continue;
                }
                let lineage = Declared::lineage_using(ty, gate);if !message(gate,&[ty,var,rel]){return;}
                let inherited = lineage.iter().skip(1).find(|t| d.positions.get(*t).is_some_and(|m| m.contains_key(pos)));
                match (inherited, overrides) {
                    (Some(from), false) => emit(
                        "param_pos_override",
                        rel,
                        *line as usize,
                        format!("{ty}: param(nameof({var}), pos = {pos}) takes over the position {from} maps; add overrides = TRUE"),
                    ),
                    (None, true) => emit("param_overrides_nothing", rel, *line as usize, format!("{ty}: param(nameof({var}), pos = {pos}, overrides = TRUE) overrides no ancestor's position")),
                    _ => {}
                }
            }
        }
}

pub fn metadata()->&'static Meta{&META}

struct Compatibility;impl Gate for Compatibility{fn checked(&self)->bool{false}fn checkpoint(&self)->bool{true}fn reserve(&self,_:Option<usize>)->bool{true}fn allocation_failed(&self){}}
impl Declared{
 pub(crate) fn marker(&mut self,ty:&str,args:&[String],relative:&str,line:u32){self.marker_using(ty,args,relative,line,&Compatibility)}
 pub(crate) fn lineage(ty:&str)->Vec<String>{Self::lineage_using(ty,&Compatibility)}
 pub(crate) fn has_param(&self,ty:&str,name:&str)->bool{self.has_param_using(ty,name,&Compatibility)}
 pub(crate) fn required_of(&self,ty:&str)->BTreeSet<String>{self.required_of_using(ty,&Compatibility)}
 pub(crate) fn builds_from(&self,ty:&str)->bool{self.builds_from_using(ty,&Compatibility)}
 pub(crate) fn after_init_of(&self,ty:&str)->Option<String>{self.after_init_of_using(ty,&Compatibility)}
 pub(crate) fn after_init_bare_new(&self,line:&str)->Option<(String,String)>{self.after_init_bare_new_using(line,&Compatibility)}
}
pub(crate) fn nameof_inner(arg:&str)->Option<String>{nameof_inner_using(arg,&Compatibility)}
pub(crate) fn calls(text:&str)->Vec<(String,Vec<String>)>{calls_using(text,&Compatibility)}
pub(crate) fn scan_file(d:&Declared,f:&SourceFile,emit:&mut dyn FnMut(&'static str,usize,String)){scan_file_using(d,f,emit,&Compatibility)}
pub(crate) fn position_findings(d:&Declared,skip:&dyn Fn(&str)->bool,emit:&mut dyn FnMut(&'static str,&str,usize,String)){position_findings_using(d,skip,emit,&Compatibility)}
fn message(gate:&dyn Gate,parts:&[&str])->bool{gate.checkpoint()&&(!gate.checked()||gate.reserve(parts.iter().try_fold(512usize,|n,s|n.checked_add(s.len().checked_mul(8)?))))}
fn row<T>(out:&mut Vec<T>,gate:&dyn Gate)->bool{if !gate.checkpoint(){return false}if out.len()<out.capacity(){return true}let Some(cap)=out.capacity().checked_mul(2).map(|n|n.max(4))else{gate.reserve(None);return false};if gate.checked()&&!gate.reserve(cap.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(128))){return false}if out.try_reserve_exact(cap-out.len()).is_err(){gate.allocation_failed();return false}true}
struct Proxy<'a>(&'a dyn Gate);impl crate::key_policy_control::Control for Proxy<'_>{type Error=();const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),()>{if self.0.checkpoint(){Ok(())}else{Err(())}}fn reserve(&mut self,n:usize)->Result<(),()>{if self.0.reserve(Some(n)){Ok(())}else{Err(())}}fn overflow(&mut self){self.0.reserve(None);}fn allocation_failed(&mut self){self.0.allocation_failed();}}

#[cfg(test)]#[path="lifeforms_policy_tests.rs"]mod tests;
