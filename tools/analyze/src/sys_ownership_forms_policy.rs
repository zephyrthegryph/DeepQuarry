//! Unique original ownership-form lexical facts and cross-file policy. DATA only.
use std::collections::HashMap;
use serde::{Serialize,Deserialize};
use crate::{tree::SourceFile,util::{before_slashes,is_py_space},pat,key_policy_control::{self as kc,Control}};
pub use crate::allow_registry_fields::sys_dx_ownership_forms::RULES;
fn row<C:Control,T>(c:&mut C,rows:&mut Vec<T>)->Result<(),C::Error>{if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}let target=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;let max=target.checked_mul(4).ok_or_else(||c.overflow())?;kc::reserve(c,||max.checked_mul(std::mem::size_of::<T>())?.checked_add(128))?;rows.try_reserve_exact(target-rows.len()).map_err(|_|c.allocation_failed())?;if rows.capacity()>max{return Err(c.allocation_failed())}Ok(())}
fn line_number<C:Control>(n:usize,c:&mut C)->Result<u32,C::Error>{if C::CHECKED{u32::try_from(n).map_err(|_|c.overflow())}else{Ok(n as u32)}}
pub fn related(a:&str,b:&str)->bool{a==b||a.strip_prefix(b).is_some_and(|tail|tail.starts_with('/'))||b.strip_prefix(a).is_some_and(|tail|tail.starts_with('/'))}
/// One file's contribution: its own sites (rule index into `RULES`), the vars its capabilities()
/// own (`(var, holder type)`) and the vars its ownership() owns (`(holder type, var, line)`).
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    pub sites: Vec<(u8, u32)>,
    pub cap: Vec<(String, String)>,
    pub typ: Vec<(String, String, u32)>,
}

pub fn facts_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,c:&mut C,temporary:&mut T)->Result<Facts,C::Error>{
    let old_macro = pat!(
        r"(?<![\w#])(OWN|OWN_POLICY|OWN_IF|SHARED|PROTO|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST|KEYED_TARGET|KEEP_AFTER_DESTROY|POOL_RESET|FORWARD_STATE)\s*\(|/declare_ownership\(|\b(own|shared|proto|rel)\(\s*decl\b"
    );
    let old_destroy = pat!(r"\b(DESTROY_STEP|DESTROY_CAPTURE|DESTROY_AFTER)\b");
    let string_accessor = pat!(r#"\b(own|rel|proto)_[a-z_]+\(\s*[^,()"]+,\s*"[A-Za-z_][A-Za-z0-9_]*""#);
    let proc_head = pat!(r"^(/[\w/]+)/(capabilities|ownership)\(\)");
    let cap_owns = pat!(r"\b(cap_slot|cap_cell_holder)\(\s*nameof\((\w+)\)");
    let type_owns = pat!(r"^\s*\.\s*\+=\s*owns\(\s*nameof\((\w+)\)");

    let mut out = Facts::default();
    let mut head: Option<(&str,&str)> = None;
    let groups=proc_head.capture_group_count().checked_add(cap_owns.capture_group_count()).and_then(|n|n.checked_add(type_owns.capture_group_count()));kc::reserve(temporary,||groups?.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(256))?;
    for (number, line) in f.raw().numbered() {c.checkpoint()?;temporary.checkpoint()?;
        let code = before_slashes(line);
        if old_macro.is_match(code) {
            row(c,&mut out.sites)?;out.sites.push((0, line_number(number,c)?));
        }
        if old_destroy.is_match(code) {
            row(c,&mut out.sites)?;out.sites.push((1, line_number(number,c)?));
        }
        if string_accessor.is_match(code) {
            row(c,&mut out.sites)?;out.sites.push((2, line_number(number,c)?));
        }
        if line.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
            // `re.match` (anchored at the start): the pattern carries its own `^`.
            head = proc_head.captures(line).map(|m| (m.s(1),m.s(2)));
            continue;
        }
        let Some((htype, hkind)) = &head else { continue };
        if *hkind == "capabilities" {
            for m in cap_owns.captures_iter(code) {
                c.checkpoint()?;row(c,&mut out.cap)?;out.cap.push((kc::own(c,m.s(2))?,kc::own(c,htype)?));
            }
        } else if let Some(m) = type_owns.captures(code) {
            row(c,&mut out.typ)?;out.typ.push((kc::own(c,htype)?,kc::own(c,m.s(1))?,line_number(number,c)?));
        }
    }
    c.checkpoint()?;Ok(out)
}

pub fn facts_of(f:&SourceFile)->Facts{facts_using(f,&mut kc::Compatibility,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub fn scan_borrowed_using<'a,C:Control>(files:&[(&'a str,&'a Facts)],c:&mut C,emit:&mut dyn FnMut(&'static str,&str,u32,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{let mut cap_owned:HashMap<&str,Vec<&str>>=HashMap::new();for(relative,facts)in files{c.checkpoint()?;for(rule,line)in &facts.sites{c.checkpoint()?;emit(RULES[*rule as usize].name,relative,*line,c)?;}for(var,holder)in &facts.cap{c.checkpoint()?;if !cap_owned.contains_key(var.as_str()){kc::reserve(c,||Some(2048+std::mem::size_of::<(&str,Vec<&str>)>()))?;}let rows=cap_owned.entry(var.as_str()).or_default();row(c,rows)?;rows.push(holder.as_str());}}
for(relative,facts)in files{c.checkpoint()?;for(holder,var,line)in &facts.typ{c.checkpoint()?;let mut found=false;if let Some(values)=cap_owned.get(var.as_str()){for other in values{c.checkpoint()?;if related(holder,other){found=true;break;}}}if found{emit("owned_twice",relative,*line,c)?;}}}c.checkpoint()}

pub fn scan_using<C:Control>(files:&[(&str,Facts)],c:&mut C,emit:&mut dyn FnMut(&'static str,&str,u32,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{kc::reserve(c,||files.len().checked_mul(4*std::mem::size_of::<(&str,&Facts)>())?.checked_add(128))?;let rows:Vec<_>=files.iter().map(|(relative,facts)|(*relative,facts)).collect();if C::CHECKED&&rows.capacity()>files.len().saturating_mul(4){return Err(c.allocation_failed())}scan_borrowed_using(&rows,c,emit)}
