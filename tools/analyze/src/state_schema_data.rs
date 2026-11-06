//! Unique lexical state-schema data and scans. No Tree/Sem, source receipt, or completion.
use std::collections::{BTreeSet,HashMap,HashSet};
use crate::{tree::View,util::under,pat,pat_match};
pub use crate::raw_declaration_policy::MODIFIERS;
pub const UNSAVED: &[&str] = &["tmp", "static", "global", "const"];
/// Object type roots. A declared type under one of these holds a reference.
pub const REF_ROOTS: &[&str] = &[
    "/datum",
    "/atom",
    "/obj",
    "/mob",
    "/turf",
    "/area",
    "/image",
    "/icon",
    "/client",
    "/sound",
    "/matrix",
    "/mutable_appearance",
    "/savefile",
    "/regex",
    "/database",
    "/exception",
    "/callback",
    "/decl",
];
/// Frozen definition / registry types that are never deleted (implicitly SHARED).
pub const DEF_TYPES: &[&str] = &[
    "/datum/material",
    "/datum/decl",
    "/decl",
    "/datum/language",
    "/datum/property_def",
    "/datum/msg",
];
/// Base types whose vars are reported by `--report` (the tmp hygiene pass).
pub const BASE_TYPES: &[&str] = &[
    "/datum",
    "/atom",
    "/atom/movable",
    "/obj",
    "/obj/item",
    "/obj/machinery",
    "/mob",
];
/// Where `REGISTRY_TYPE(...)` rows live.
pub const REGISTRY_FILE: &str = "code/library/ownership/registry_types.dm";

/// A declared var (`class Var`).
#[derive(Clone, Debug)]
pub struct Var {
    pub owner: String,
    pub name: String,
    pub mods: BTreeSet<String>,
    pub vtype: String,
    pub is_list: bool,
    /// Repo-relative path of the declaring file.
    pub path: String,
    pub line: usize,
}

impl Var {
    /// Not `tmp`, `static`, `global` or `const`.
    pub fn saved(&self) -> bool {
        !self.mods.iter().any(|m| UNSAVED.contains(&m.as_str()))
    }

    pub fn holds_ref(&self) -> bool {
        under(&self.vtype, REF_ROOTS)
    }

    /// `registry` needs the registry list (`Schema::registry`): the Python read a module global.
    pub fn registry(&self, registry: &[String]) -> bool {
        under(&self.vtype, registry)
    }
}

/// `ancestors(path)`: the path's prefixes, shortest first, the path included.
pub fn ancestors(path: &str) -> Vec<String> {
    let segs: Vec<&str> = path.trim_matches('/').split('/').collect();
    (1..=segs.len())
        .map(|i| format!("/{}", segs[..i].join("/")))
        .collect()
}

/// The type and its ancestors, root first. Everything inherits /datum, except the built-in roots
/// that do not (none of ours).
pub fn chain(path: &str) -> Vec<String> {
    let mut out = ancestors(path);
    if out[0] != "/datum" {
        let first = out[0].as_str();
        if matches!(first, "/obj" | "/mob" | "/turf" | "/area") {
            let n = if matches!(first, "/obj" | "/mob") {
                3
            } else {
                2
            };
            let mut pre: Vec<String> = ["/datum", "/atom", "/atom/movable"][..n]
                .iter()
                .map(|s| s.to_string())
                .collect();
            pre.extend(out);
            out = pre;
        } else if first == "/atom" {
            out.insert(0, "/datum".to_string());
        }
    }
    out
}

/// `split_decl`: `(name, mods, vtype, is_list)` of the path segments of a declaration, or None.
pub(crate) fn push_var(
    decls: &mut HashMap<String, Vec<Var>>,
    owner: &str,
    d: (String, BTreeSet<String>, String, bool),
    rel: &str,
    line: usize,
) {
    let (name, mods, vtype, is_list) = d;
    decls.entry(owner.to_string()).or_default().push(Var {
        owner: owner.to_string(),
        name,
        mods,
        vtype,
        is_list,
        path: rel.to_string(),
        line,
    });
}

/// `parse()` for one file's `code_only` view: appends to `decls` and `latent`.
pub fn parse_file(rel:&str,code:&View,decls:&mut HashMap<String,Vec<Var>>,latent:&mut HashMap<String,bool>){match parse_file_using(rel,code,decls,latent,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility){Ok(())=>(),Err(never)=>match never{}}}
/// SAME original raw declaration scanner. Its temporary parsed parts are funded
/// in the actual FileScope before scanning; retained parts are separately funded
/// before moving to the phase owner. Regex internals remain the shared baseline.
pub fn parse_file_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(rel:&str,code:&View,decls:&mut HashMap<String,Vec<Var>>,latent:&mut HashMap<String,bool>,keep:&mut C,temporary:&mut T)->Result<(),C::Error>{
 use crate::key_policy_control as kc;
 if T::CHECKED{let mut width=0usize;let mut parts=0usize;for(_,line)in code.numbered(){temporary.checkpoint()?;width=width.max(line.len());parts=parts.max(line.bytes().filter(|byte|*byte==b'/').count().checked_add(1).ok_or_else(||temporary.overflow())?);}kc::reserve(temporary,||width.checked_mul(8)?.checked_add(parts.checked_mul(6*std::mem::size_of::<&str>())?)?.checked_add(32768))?;}
 let control=std::cell::RefCell::new(keep);let error=std::cell::RefCell::new(None);crate::raw_declaration_policy::visit_file(rel,code,|owner,parts,rel,line|{if error.borrow().is_some(){return}let result=(||{let mut control=control.borrow_mut();let c=&mut **control;c.checkpoint()?;let(name,mods,vtype,is_list)=parts;if !decls.contains_key(owner){kc::reserve(c,||Some(2048))?;decls.insert(kc::own(c,owner)?,Vec::new());}let rows=decls.get_mut(owner).expect("actual admitted schema owner");kc::row(c,rows)?;if C::CHECKED{let bytes=mods.iter().fold(name.capacity().checked_add(vtype.capacity()),|n,word|n?.checked_add(2048)?.checked_add(word.capacity())).ok_or_else(||c.overflow())?;c.reserve(bytes)?;}rows.push(Var{owner:kc::own(c,owner)?,name,mods,vtype,is_list,path:kc::own(c,rel)?,line});Ok::<(),C::Error>(())})();if let Err(actual)=result{*error.borrow_mut()=Some(actual)}},|owner,value|{if error.borrow().is_some(){return}let result=(||{let mut control=control.borrow_mut();let c=&mut **control;c.checkpoint()?;if let Some(old)=latent.get_mut(owner){*old=value}else{kc::reserve(c,||Some(2048))?;latent.insert(kc::own(c,owner)?,value);}Ok::<(),C::Error>(())})();if let Err(actual)=result{*error.borrow_mut()=Some(actual)}});if let Some(actual)=error.into_inner(){return Err(actual)}control.into_inner().checkpoint()
}

/// `parse_codec_keys` for one file: `state_codecs()` keys are string literals, which `code_only`
/// blanks, so they are read from the raw text of each `state_codecs()` proc.
pub fn parse_codec_keys_file(text:&str,codecs:&mut HashMap<String,HashSet<String>>){match parse_codec_keys_file_using(text,codecs,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility){Ok(())=>(),Err(never)=>match never{}}}
/// Same raw codec policy; persistent keys and per-file capture/owner scratch
/// have distinct actual operation/FileScope controls in native consumers.
pub fn parse_codec_keys_file_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(text:&str,codecs:&mut HashMap<String,HashSet<String>>,keep:&mut C,temporary:&mut T)->Result<(),C::Error>{
 let head=pat!(r"(?m)^(/[\w/]+)/state_codecs\(\)");let first_nonspace_line=pat!(r"(?m)^\S");let key=pat!(r#""(\w+)"\s*=\s*/datum/state_codec"#);
 crate::key_policy_control::reserve(temporary,||head.capture_group_count().checked_add(key.capture_group_count())?.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(2*std::mem::size_of::<crate::pat::Caps<'_>>()+128))?;let mut owner_peak=0usize;
 for m in head.captures_iter(text){temporary.checkpoint()?;if T::CHECKED{let peak=m.s(1).len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||temporary.overflow())?;if peak>owner_peak{temporary.reserve(peak-owner_peak)?;owner_peak=peak;}}let owner=m.s(1).replace("/proc","");let end=m.end(0);let rest=&text[end..];let stop=first_nonspace_line.find(rest).map(|e|e.start).unwrap_or(rest.len());let body=&rest[..stop];for k in key.captures_iter(body){temporary.checkpoint()?;if !codecs.contains_key(&owner){crate::key_policy_control::reserve(keep,||Some(2048))?;let name=crate::key_policy_control::own(keep,&owner)?;codecs.insert(name,HashSet::new());}let rows=codecs.get_mut(&owner).expect("actual codec owner");if !rows.contains(k.s(1)){crate::key_policy_control::reserve(keep,||Some(2048))?;rows.insert(crate::key_policy_control::own(keep,k.s(1))?);}}}keep.checkpoint()
}

/// The whole parse, built once per run (`Schema::get`).
#[derive(Debug, Default)]
pub struct Schema {
    /// type -> declared vars, in file order then line order
    pub decls: HashMap<String, Vec<Var>>,
    /// type -> `latent_safe` as set in that type's own block
    pub latent: HashMap<String, bool>,
    /// type -> `state_codecs()` key names
    pub codecs: HashMap<String, HashSet<String>>,
    /// `REGISTRY_TYPES`
    pub registry: Vec<String>,
}

impl Schema {
    /// `effective_latent(path, latent)`: the last `latent_safe` set along the chain.
    pub fn effective_latent(&self, path: &str) -> bool {
        let mut val = false;
        for a in chain(path) {
            if let Some(v) = self.latent.get(&a) {
                val = *v;
            }
        }
        val
    }

    /// `has_codec(owner, name, subject)`: a `state_codecs()` key `name` on `subject` or an ancestor.
    pub fn has_codec(&self, name: &str, subject: &str) -> bool {
        chain(subject).iter().any(|a| {
            self.codecs
                .get(a)
                .map(|s| s.contains(name))
                .unwrap_or(false)
        })
    }

    /// Every type that is latent-safe, sorted.
    pub fn safe_types(&self) -> Vec<String> {
        let mut all: BTreeSet<&String> = self.decls.keys().collect();
        all.extend(self.latent.keys());
        all.into_iter()
            .filter(|t| self.effective_latent(t))
            .cloned()
            .collect()
    }
}


/// Same original ownership-entry expression. Kept phase-local as before; this
/// is not an additional retained regex cache or source index.
pub fn ownership_entry_pattern()->Result<regex::Regex,regex::Error>{regex::Regex::new(r"\b(owns_one|owns_many|ref_one|ref_many|hud_element|profile)\(\s*nameof\((\w+)\)")}
pub fn visit_ownership_entries(pattern:&regex::Regex,body:&str,mut emit:impl FnMut(&str,&'static str)){for c in pattern.captures_iter(body){let rest=body[c.get(0).map(|x|x.end()).unwrap_or(0)..].split('\n').next().unwrap_or("");let owned_hud=&c[1]=="hud_element"&&!rest.contains("owned = FALSE");let kind=if c[1].starts_with("owns_")||owned_hud||&c[1]=="profile"{"OWN"}else{"REL"};emit(&c[2],kind);}}
