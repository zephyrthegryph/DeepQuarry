//! Key resolution: op keys, capability keys, stat, stage and source ids.
//!
//! Stats, tracked vars, capability and tag keys, op keys, sources, stages and messages are schema:
//! declared once and resolved by the build (doc/rewrite/final_api.html section 4). The DM compiler
//! cannot check a marker's arguments (`CAPABILITIES(...)` expands to nothing), so every id and
//! key that sits inside one, and every string-literal key passed to `extend/without/configure/
//! perform_op/on_op/...`, is resolved here against what the tree declares.
//!
//! What counts as declared:
//!
//! | Kind | Declared by |
//! |---|---|
//! | stat id `STAT_<NAME>` | `STAT(T, name, ...)`, or a `#define STAT_X` |
//! | source id `SRC_<NAME>` | `SOURCE_DEF(name)`, or a `#define SRC_X` |
//! | stage id `STAGE_<GROUP>_<NAME>` | `STAGE_DEF(group, name)`, or a `#define` |
//! | capability id `CAP_<X>` | `CAPABILITY_DEF/TYPE(name, CAP_X, ...)`, or a `#define CAP_X` |
//! | capability key `name` | the same marker's first argument |
//! | capability state id `<NAME>_<KEY>` | `cap_keys(CAP_X, KEY = ...)` for the capability named by `CAP_X` |
//! | op key `cap.op` / `op` | an `op("name", ...)` entry inside a capability marker (`cap.name`) or a `CAPABILITIES` (`name`) |

use std::collections::{BTreeMap, BTreeSet, HashSet};

use crate::{raw_marker_policy::{split_args,matching_paren,ENTRY_PROC},declare_policy::Marker};
/// Only original raw declaration-marker policy rows; never a DM semantic model.
pub struct Input<'a>{pub markers:&'a [Marker<'a>],pub entry_ops:&'a [(String,String)]}
impl Input<'_>{fn markers_named<'a>(&'a self,name:&'a str)->impl Iterator<Item=&'a Marker<'a>>{self.markers.iter().filter(move|m|m.name==name)}}

#[derive(Default, Debug)]
pub struct KeyIndex {
    pub stats: BTreeMap<String, (String, String)>,
    pub sources: BTreeSet<String>,
    pub stages: BTreeSet<String>,
    /// capability key (the name) -> its CAP_ id.
    pub caps: BTreeMap<String, String>,
    pub cap_ids: BTreeSet<String>,
    pub cap_state_ids: BTreeSet<String>,
    pub ops: BTreeSet<String>,
    /// "prefix|op" of the ops a capability with a selector declares: its keys read `prefix.selector.op` ("cell_bay.cell.insert").
    pub sel_ops: BTreeSet<String>,
    /// Duplicates found while indexing: (kind, name, first site, second site).
    pub duplicates: Vec<(String, String, (String, u32), (String, u32))>,
}

/// The id prefixes the build resolves. A token with one of these prefixes inside a marker must be declared.
/// Exact source marker union needed by this policy; synthetic ENTRY_PROC rows
/// are supplied by the original first-return issuer, not a new parser.
pub const MARKERS:&[&str]=&["CAPABILITIES","CAPABILITY_DEF","CAPABILITY_TYPE","cap_keys","ACTION","STAT","SCHEMA","SYSTEM_ACCESSOR","STAGE_DEF","STATE_GRAPH","RESOURCE_DEF","SOURCE_DEF"];
pub const ID_PREFIXES: &[&str] = &["STAT_", "SRC_", "STAGE_", "CAP_"];

fn up(s: &str) -> String {
    s.to_uppercase()
}

impl KeyIndex {
    pub fn from_markers(decls: &Input<'_>) -> KeyIndex {
        match Self::from_markers_controlled(decls,&mut crate::key_policy_control::Compatibility){Ok(k)=>k,Err(never)=>match never{}}
    }
    pub fn from_markers_controlled<C:crate::key_policy_control::Control>(decls:&Input<'_>,c:&mut C)->Result<Self,C::Error>{
        use crate::key_policy_control as kc;
        c.checkpoint()?;
        // Coordination envelope for the fixed set of B-tree roots and split
        // overlap. It is not a platform allocator/RSS measurement.
        kc::reserve(c,||Some(8192))?;
        let mut k=Self::default();
        let mut seen:BTreeMap<(String,String),(String,u32)>=BTreeMap::new();
        for m in decls.markers {
            c.checkpoint()?;
            match m.name {
                "STAT"=>if let(Some(t),Some(n))=(m.args.first(),m.args.get(1)){
                    let label=kc::format(c,format_args!("{t}::{n}"))?;note_controlled(&mut k,&mut seen,"stat",&label,m,c)?;
                    let upper=kc::upper(c,n)?;let id=kc::format(c,format_args!("STAT_{upper}"))?;
                    let ty=kc::own(c,t)?;let name=kc::own(c,n)?;key_node(c)?;k.stats.insert(id,(ty,name));
                },
                "SOURCE_DEF"=>if let Some(n)=m.args.first(){
                    note_controlled(&mut k,&mut seen,"source",n,m,c)?;
                    let upper=kc::upper(c,n)?;let id=kc::format(c,format_args!("SRC_{upper}"))?;key_node(c)?;k.sources.insert(id);
                },
                "STAGE_DEF"=>if let(Some(g),Some(n))=(m.args.first(),m.args.get(1)){
                    let label=kc::format(c,format_args!("{g}/{n}"))?;note_controlled(&mut k,&mut seen,"stage",&label,m,c)?;
                    let group=kc::upper(c,g)?;let name=kc::upper(c,n)?;let id=kc::format(c,format_args!("STAGE_{group}_{name}"))?;key_node(c)?;k.stages.insert(id);
                },
                "CAPABILITY_DEF"|"CAPABILITY_TYPE"=>if let(Some(n),Some(id))=(m.args.first(),m.args.get(1)){
                    note_controlled(&mut k,&mut seen,"capability",n,m,c)?;
                    let name=kc::own(c,n)?;let cap_id=kc::own(c,id)?;key_node(c)?;k.caps.insert(name,cap_id);
                    let cap_id=kc::own(c,id)?;key_node(c)?;k.cap_ids.insert(cap_id);
                    let prefix=match marker_option_controlled(m,"prefix",c)?{Some(p)=>kc::own(c,p.trim_matches('"'))?,None=>kc::own(c,n)?};
                    collect_ops_controlled(&m.body,Some(&prefix),&mut k.ops,c)?;
                    let entries_type=if m.name=="CAPABILITY_TYPE"{match m.args.get(2){Some(ty)=>Some(kc::own(c,ty)?),None=>None}}else{Some(kc::format(c,format_args!("/datum/capability/def/{n}"))?)};
                    let selected=marker_option_controlled(m,"key",c)?.map(|v|v!="NONE").unwrap_or(false);
                    if let Some(ty)=entries_type.as_ref(){for(t,op)in decls.entry_ops.iter().filter(|(t,_)|t==ty){
                        let _=t;c.checkpoint()?;
                        let key=kc::format(c,format_args!("{prefix}.{op}"))?;key_node(c)?;k.ops.insert(key);
                        if selected{let key=kc::format(c,format_args!("{prefix}|{op}"))?;key_node(c)?;k.sel_ops.insert(key);}
                    }}
                },
                "CAPABILITIES"|ENTRY_PROC=>collect_ops_controlled(&m.body,None,&mut k.ops,c)?,
                _=>{}
            }
        }
        let mut by_id:BTreeMap<&String,&String>=BTreeMap::new();
        for(n,id)in &k.caps{c.checkpoint()?;key_node(c)?;by_id.insert(id,n);}
        let mut state=BTreeSet::new();
        for m in decls.markers_named("cap_keys"){
            c.checkpoint()?;let Some(id)=m.args.first()else{continue};
            let name=match by_id.get(id){Some(n)=>kc::upper(c,n)?,None=>kc::own(c,id.trim_start_matches("CAP_"))?};
            for a in m.args.iter().skip(1){c.checkpoint()?;if let Some((key,_))=a.split_once('='){
                let upper=kc::upper(c,key.trim())?;let value=kc::format(c,format_args!("{name}_{upper}"))?;key_node(c)?;state.insert(value);
            }}
        }
        k.cap_state_ids=state;
        for op in ["construction.build","construction.undo","construction.dismantle","ui_open","ui_observe","silicon_hand","silicon_ui"]{
            c.checkpoint()?;let name=kc::own(c,op)?;key_node(c)?;k.ops.insert(name);
        }
        c.checkpoint()?;Ok(k)
    }

    /// Whether `token` (a `STAT_X`/`SRC_X`/`STAGE_G_N`/`CAP_X` or a cap-state id) is declared by a
    /// marker or by a `#define`.
    pub fn id_resolves(&self, token: &str, defines: &HashSet<String>) -> bool {
        defines.contains(token)
            || self.stats.contains_key(token)
            || self.sources.contains(token)
            || self.stages.contains(token)
            || self.cap_ids.contains(token)
            || self.cap_state_ids.contains(token)
    }

    /// `COVER_` for a declared capability named `cover`: ids with it are capability-state ids.
    pub fn cap_state_prefixes(&self)->Vec<String>{match self.cap_state_prefixes_controlled(&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}}
    pub fn cap_state_prefixes_controlled<C:crate::key_policy_control::Control>(&self,c:&mut C)->Result<Vec<String>,C::Error>{
        use crate::key_policy_control as kc;
        let mut out=Vec::new();for name in self.caps.keys(){c.checkpoint()?;let name=kc::upper(c,name)?;let prefix=kc::format(c,format_args!("{name}_"))?;kc::row(c,&mut out)?;out.push(prefix);}Ok(out)
    }
    pub fn suggest(&self,token:&str,defines:&HashSet<String>)->Option<String>{match self.suggest_controlled(token,defines,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}}
    pub fn suggest_controlled<C:crate::key_policy_control::Control>(&self,token:&str,defines:&HashSet<String>,c:&mut C)->Result<Option<String>,C::Error>{
        let mut best:Option<(usize,String)>=None;
        for candidate in self.stats.keys().chain(self.sources.iter()).chain(self.stages.iter()).chain(self.cap_ids.iter()).chain(defines.iter()){
            c.checkpoint()?;if !ID_PREFIXES.iter().any(|p|candidate.starts_with(p)){continue}
            let d=edit_distance_controlled(token,candidate,c)?;
            if d<=3&&best.as_ref().map(|(old,_)|d<*old).unwrap_or(true){best=Some((d,crate::key_policy_control::own(c,candidate)?));}
        }
        Ok(best.map(|(_,s)|s))
    }
    pub fn op_resolves(&self,key:&str)->bool{match self.op_resolves_controlled(key,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}}
    pub fn op_resolves_controlled<C:crate::key_policy_control::Control>(&self,key:&str,c:&mut C)->Result<bool,C::Error>{
        c.checkpoint()?;let base=key.split(':').next().unwrap_or(key);
        if self.ops.contains(key)||self.ops.contains(base){return Ok(true)}
        // Same exact three-segment test without allocating a temporary Vec.
        let mut parts=base.split('.');let first=parts.next();let second=parts.next();let third=parts.next();
        let(Some(a),Some(_),Some(b))=(first,second,third)else{return Ok(false)};
        if parts.next().is_some(){return Ok(false)}
        let key=crate::key_policy_control::format(c,format_args!("{a}|{b}"))?;Ok(self.sel_ops.contains(&key))
    }
    pub fn suggest_op(&self,key:&str)->Option<String>{match self.suggest_op_controlled(key,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}}
    pub fn suggest_op_controlled<C:crate::key_policy_control::Control>(&self,key:&str,c:&mut C)->Result<Option<String>,C::Error>{
        let mut best:Option<(usize,&String)>=None;
        for candidate in &self.ops{c.checkpoint()?;let d=edit_distance_controlled(key,candidate,c)?;if d<=3&&best.map(|(old,_)|d<old).unwrap_or(true){best=Some((d,candidate));}}
        match best{Some((_,value))=>Ok(Some(crate::key_policy_control::own(c,value)?)),None=>Ok(None)}
    }

}

/// The value of `name = value` among a marker's arguments, or None.
fn marker_option(m: &Marker<'_>, name: &str) -> Option<String> {
    m.args.iter().find_map(|a| {
        let (k, v) = a.split_once('=')?;
        (k.trim() == name).then(|| v.trim().to_string())
    })
}

/// Every `op("name", ...)` in a marker body: `cap.name` inside a capability marker, `name` otherwise.
fn collect_ops_controlled<C:crate::key_policy_control::Control>(body:&str,cap:Option<&String>,out:&mut BTreeSet<String>,c:&mut C)->Result<(),C::Error>{
    if C::CHECKED { return collect_ops_iterative(body,cap,out,c); }
    use crate::key_policy_control as kc;
    c.checkpoint()?;let mut j=0;
    while let Some(p)=body[j..].find("stages("){
        c.checkpoint()?;let at=j+p;j=at+7;
        if at>0&&(body.as_bytes()[at-1].is_ascii_alphanumeric()||body.as_bytes()[at-1]==b'_'){continue}
        let Some(close)=matching_paren(body,at+6)else{continue};
        for op_args in crate::raw_marker_policy::stages_op_args_controlled(&body[at+7..close],c)?{
            let nested=kc::format(c,format_args!("op({op_args})"))?;
            collect_ops_controlled(&nested,cap,out,c)?;
        }
    }
    collect_literal_ops(body,cap,out,c)
}
fn collect_literal_ops<C:crate::key_policy_control::Control>(body:&str,cap:Option<&String>,out:&mut BTreeSet<String>,c:&mut C)->Result<(),C::Error>{
    use crate::key_policy_control as kc;
    let b=body.as_bytes();let mut i=0;
    while let Some(p)=body[i..].find("op("){
        c.checkpoint()?;let at=i+p;i=at+3;
        if at>0&&(b[at-1].is_ascii_alphanumeric()||b[at-1]==b'_'||b[at-1]==b'.'){continue}
        let Some(close)=matching_paren(body,at+2)else{continue};
        kc::split(c,close-at-3)?;let args=split_args(&body[at+3..close]);
        if let Some(name)=args.first().and_then(|a|a.strip_prefix('"')).and_then(|a|a.strip_suffix('"')){
            let key=match cap{Some(prefix)=>kc::format(c,format_args!("{prefix}.{name}"))?,None=>kc::own(c,name)?};
            key_node(c)?;out.insert(key);
        }
    }
    Ok(())
}

/// Checked traversal owns an admitted flat DFS worklist, never Rust recursion.
/// Resume each parent's stages iterator before its literal-op phase, exactly as
/// the original recursive stages-first walk. Compatibility keeps its old path.
fn collect_ops_iterative<C:crate::key_policy_control::Control>(body:&str,cap:Option<&String>,out:&mut BTreeSet<String>,c:&mut C)->Result<(),C::Error>{
 use crate::key_policy_control as kc;
 struct Frame<'a>{body:std::borrow::Cow<'a,str>,from:usize,expanded:std::vec::IntoIter<String>}
 fn next<C:kc::Control>(f:&mut Frame<'_>,c:&mut C)->Result<Option<String>,C::Error>{
  loop{
   c.checkpoint()?;
   if let Some(args)=f.expanded.next(){return Ok(Some(kc::format(c,format_args!("op({args})"))?))}
   let Some(p)=f.body[f.from..].find("stages(") else{return Ok(None)};
   let at=f.from+p;f.from=at+7;
   if at>0&&(f.body.as_bytes()[at-1].is_ascii_alphanumeric()||f.body.as_bytes()[at-1]==b'_'){continue}
   let Some(close)=matching_paren(&f.body,at+6)else{continue};
   f.expanded=crate::raw_marker_policy::stages_op_args_controlled(&f.body[at+7..close],c)?.into_iter();
  }
 }
 let mut frames=Vec::new();kc::row(c,&mut frames)?;
 frames.push(Frame{body:std::borrow::Cow::Borrowed(body),from:0,expanded:Vec::new().into_iter()});
 while let Some(frame)=frames.last_mut(){
  c.checkpoint()?;
  match next(frame,c)?{
   Some(body)=>{kc::row(c,&mut frames)?;frames.push(Frame{body:std::borrow::Cow::Owned(body),from:0,expanded:Vec::new().into_iter()});}
   None=>{collect_literal_ops(&frame.body,cap,out,c)?;frames.pop();}
  }
 }
 Ok(())
}

/// Every identifier-like token in `text` with one of the resolved prefixes, with its byte offset.
pub fn id_tokens(text:&str,extra_prefixes:&[String])->Vec<(usize,String)>{match id_tokens_controlled(text,extra_prefixes,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}}
pub fn id_tokens_controlled<C:crate::key_policy_control::Control>(text:&str,extra_prefixes:&[String],c:&mut C)->Result<Vec<(usize,String)>,C::Error>{
    use crate::key_policy_control as kc;
    let mut out=Vec::new();let b=text.as_bytes();let mut i=0;let mut in_str=false;
    while i<b.len(){
        if i&1023==0{c.checkpoint()?;}
        let ch=b[i];if ch==b'"'{in_str=!in_str;i+=1;continue}
        if in_str||!(ch.is_ascii_alphabetic()||ch==b'_'){i+=1;continue}
        let start=i;while i<b.len()&&(b[i].is_ascii_alphanumeric()||b[i]==b'_'){i+=1;if i&1023==0{c.checkpoint()?;}}
        let tok=&text[start..i];let prev_ok=start==0||!(b[start-1]==b'.'||b[start-1]==b'/');
        if prev_ok&&(ID_PREFIXES.iter().any(|p|tok.starts_with(p))||extra_prefixes.iter().any(|p|tok.starts_with(p.as_str())))&&tok.len()>4&&tok.chars().all(|ch|ch.is_ascii_uppercase()||ch.is_ascii_digit()||ch=='_'){
            kc::row(c,&mut out)?;out.push((start,kc::own(c,tok)?));
        }
    }
    c.checkpoint()?;Ok(out)
}
fn edit_distance(a:&str,b:&str)->usize{match edit_distance_controlled(a,b,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}}
fn edit_distance_controlled<C:crate::key_policy_control::Control>(a:&str,b:&str,c:&mut C)->Result<usize,C::Error>{
    c.checkpoint()?;
    crate::key_policy_control::reserve(c,||a.len().checked_add(b.len())?.checked_mul(8)?.checked_add(b.len().checked_add(1)?.checked_mul(2*std::mem::size_of::<usize>())?)?.checked_add(512))?;
    let a:Vec<char>=a.chars().collect();let b:Vec<char>=b.chars().collect();let mut prev:Vec<usize>=(0..=b.len()).collect();
    for i in 1..=a.len(){c.checkpoint()?;let mut cur=vec![i;b.len()+1];for j in 1..=b.len(){if j&1023==0{c.checkpoint()?;}let cost=usize::from(a[i-1]!=b[j-1]);cur[j]=(prev[j]+1).min(cur[j-1]+1).min(prev[j-1]+cost);}prev=cur;}
    Ok(prev[b.len()])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_skip_strings_and_members() {
        let t = id_tokens("contributes(STAT_DENSITY, x.SRC_NOT, \"STAT_IN_STRING\", SRC_AI_CONTROL)", &[]);
        let names: Vec<&str> = t.iter().map(|(_, s)| s.as_str()).collect();
        assert_eq!(names, vec!["STAT_DENSITY", "SRC_AI_CONTROL"]);
    }

    #[test]
    fn edit_distance_basics() {
        assert_eq!(edit_distance("STAT_DENSTY", "STAT_DENSITY"), 1);
    }
}

/// Exact unique key-declaration judgement over original marker/call projections.
/// Providers supply the original own-field policy; no model is built here.
pub struct ScanInput<'a>{
 pub keys:Input<'a>,pub defines:&'a HashSet<String>,
 pub key_refs:&'a [crate::raw_key_calls_policy::KeyRef],
 pub bad_sources:&'a [(String,u32,String)],
}
pub fn scan_keys(cx:&crate::lint::Cx<'_>,decls:&ScanInput<'_>,out:&mut crate::lint::Sink,
 mut system_vars:impl FnMut(&str)->(bool,HashSet<String>),system_types:impl Fn(&str)->Vec<String>){
    let result=scan_keys_controlled(cx,decls,out,&mut crate::key_policy_control::Compatibility,
        |system,var,_|{let(known,vars)=system_vars(system);Ok((known,vars.contains(var)))},
        |system,_|Ok(system_types(system)));
    match result{Ok(())=>{},Err(never)=>match never{}}
}
pub fn scan_keys_controlled<C:crate::key_policy_control::Control>(cx:&crate::lint::Cx<'_>,decls:&ScanInput<'_>,out:&mut crate::lint::Sink,c:&mut C,
 mut system_var:impl FnMut(&str,&str,&mut C)->Result<(bool,bool),C::Error>,mut system_types:impl FnMut(&str,&mut C)->Result<Vec<String>,C::Error>)->Result<(),C::Error>{
 macro_rules! key_format{($control:expr,$($args:tt)*)=>{crate::key_policy_control::format($control,format_args!($($args)*))?}}
 use crate::raw_key_calls_policy::KeyKind;
 const CHECKED_MARKERS:&[&str]=&["CAPABILITIES","CAPABILITY_DEF","CAPABILITY_TYPE","cap_keys",crate::raw_entry_proc_policy::ENTRY_PROC,"STATE_GRAPH","RESOURCE_DEF","SCHEMA","ACTION"];
        let idx = KeyIndex::from_markers_controlled(&decls.keys,c)?;


        let cap_prefixes = idx.cap_state_prefixes_controlled(c)?;
        for m in decls.keys.markers {
            c.checkpoint()?;
            if !CHECKED_MARKERS.contains(&m.name) || cx.exempt(&m.rel) {
                continue;
            }
            for (off, tok) in id_tokens_controlled(&m.body, &cap_prefixes,c)? {
                if idx.id_resolves(&tok, &decls.defines) {
                    continue;
                }
                let line = m.line_at(off);
                if allowed_controlled(cx,out,&m.rel,line,c)? {
                    continue;
                }
                let msg = match idx.suggest_controlled(&tok, &decls.defines,c)? {
                    Some(s) => key_format!(c,"`{}` is not declared; did you mean `{}`?", tok, s),
                    None => key_format!(c,"`{}` is not declared", tok),
                };
                out.site_in_msg("unresolved_id", &m.rel, line as usize, msg);
            }
        }

        for r in decls.key_refs.iter().filter(|r| !cx.exempt(&r.rel)) {
            c.checkpoint()?;
            match r.kind {
                KeyKind::Op if !idx.op_resolves_controlled(&r.key,c)? => {
                    if allowed_controlled(cx,out,&r.rel,r.line,c)? {
                        continue;
                    }
                    let msg = match idx.suggest_op_controlled(&r.key,c)? {
                        Some(s) => key_format!(c,"op key \"{}\" in {}() is not declared; did you mean \"{}\"?", r.key, r.call, s),
                        None => key_format!(c,"op key \"{}\" in {}() is not declared", r.key, r.call),
                    };
                    out.site_in_msg("unresolved_op", &r.rel, r.line as usize, msg);
                }
                KeyKind::Capability if !idx.caps.contains_key(&r.key) => {
                    if allowed_controlled(cx,out,&r.rel,r.line,c)? {
                        continue;
                    }
                    out.site_in_msg("unresolved_capability", &r.rel, r.line as usize, key_format!(c,"capability key \"{}\" in {}() is not declared", r.key, r.call));
                }
                _ => {}
            }
        }

        for (rel, line, v) in decls.bad_sources.iter().filter(|(rel, _, _)| !cx.exempt(rel)) {
            c.checkpoint()?;
            if allowed_controlled(cx,out,rel,*line,c)? {
                continue;
            }
            out.site_in_msg("text_source", rel, *line as usize, key_format!(c,"source = {} is not a datum or a SRC_*", v));
        }

        for (kind, name, first, second) in &idx.duplicates {
            c.checkpoint()?;
            if allowed_controlled(cx,out,&second.0,second.1,c)? {
                continue;
            }
            out.site_in_msg("duplicate_declaration", &second.0, second.1 as usize, key_format!(c,"{} `{}` is already declared at {}:{}", kind, name, first.0, first.1));
        }

        // SYSTEM_ACCESSOR(system, name, nameof(var)): the var must be on the system.
        for m in decls.keys.markers_named("SYSTEM_ACCESSOR") {
            c.checkpoint()?;
            let (Some(system), Some(name), Some(key)) = (m.args.first(), m.args.get(1), m.args.get(2)) else { continue };
            let Some(var) = key.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).map(str::trim) else { continue };
            let (known, contains) = system_var(system,var,c)?;
            if !contains && !allowed_controlled(cx,out,&m.rel,m.line,c)? {
                let msg = if known {
                    key_format!(c,"accessor `{}`: system `{}` has no var `{}`", name, system, var)
                } else {
                    {let types=system_types(system,c)?;let joined=types_joined_controlled(types,c)?;key_format!(c,"accessor `{}`: no system type for `{}` (looked for {})", name, system, joined)}
                };
                out.site_in_msg("accessor_var", &m.rel, m.line as usize, msg);
            }
        }

    c.checkpoint()?;Ok(())
}

fn key_node<C:crate::key_policy_control::Control>(c:&mut C)->Result<(),C::Error>{crate::key_policy_control::reserve(c,||Some(256))}
fn note_controlled<C:crate::key_policy_control::Control>(k:&mut KeyIndex,seen:&mut BTreeMap<(String,String),(String,u32)>,kind:&str,name:&str,m:&Marker<'_>,c:&mut C)->Result<(),C::Error>{
    use crate::key_policy_control as kc;
    c.checkpoint()?;let key=(kc::own(c,kind)?,kc::own(c,name)?);
    if let Some(first)=seen.get(&key){
        kc::row(c,&mut k.duplicates)?;
        let kind=kc::own(c,kind)?;let name=kc::own(c,name)?;let first=(kc::own(c,&first.0)?,first.1);let second=(kc::own(c,m.rel)?,m.line);
        k.duplicates.push((kind,name,first,second));
    }else{let site=(kc::own(c,m.rel)?,m.line);key_node(c)?;seen.insert(key,site);}
    Ok(())
}
fn marker_option_controlled<C:crate::key_policy_control::Control>(m:&Marker<'_>,name:&str,c:&mut C)->Result<Option<String>,C::Error>{
    for a in m.args{c.checkpoint()?;if let Some((k,v))=a.split_once('='){if k.trim()==name{return Ok(Some(crate::key_policy_control::own(c,v.trim())?))}}}Ok(None)
}

fn allowed_controlled<C:crate::key_policy_control::Control>(cx:&crate::lint::Cx<'_>,out:&mut crate::lint::Sink,rel:&str,line:u32,c:&mut C)->Result<bool,C::Error>{
    c.checkpoint()?;let Some(file)=cx.tree.get(rel)else{return Ok(false)};
    if C::CHECKED{
        let raw=file.raw();let number=line as usize;
        for text in [raw.line(number),if number>=2&&crate::util::py_lstrip(raw.line(number-1)).starts_with("//"){raw.line(number-1)}else{""}]{
            if text.contains("ALLOW("){crate::key_policy_control::reserve(c,||text.len().checked_mul(512)?.checked_add(1024))?;}
        }
    }
    Ok(out.allowed(file,line as usize,"keys"))
}
fn types_joined_controlled<C:crate::key_policy_control::Control>(types:Vec<String>,c:&mut C)->Result<String,C::Error>{
    crate::key_policy_control::reserve(c,||types.iter().try_fold(0usize,|n,t|n.checked_add(t.len()))?.checked_add(types.len().saturating_sub(1).checked_mul(2)?)?.checked_mul(2)?.checked_add(128))?;
    Ok(types.join(", "))
}

use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::CODE_DM;
const H_ID: &str = "declare it with STAT/SOURCE_DEF/STAGE_DEF/CAPABILITY_DEF (or #define it), or fix the spelling";
const H_OP: &str = "declare the op (op(\"name\", ...) in its capability) or fix the key; perform_op with an unknown key is an error, not a no-op";
const H_CAP: &str = "declare the capability (CAPABILITY_DEF/CAPABILITY_TYPE name) or fix the key";
const H_SRC: &str = "a source is a datum or a SOURCE_DEF flyweight (SRC_X): text and null are errors";
const H_DUP: &str = "declare each stat, source, stage and capability once";
const H_ACC: &str = "name a var the system declares: SYSTEM_ACCESSOR(system, accessor, nameof(var))";

static META: Meta = Meta {
    name: "sem/keys",
    group: "sem",
    label: "keys",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "unresolved_id", hint: H_ID },
        RuleMeta { name: "unresolved_op", hint: H_OP },
        RuleMeta { name: "unresolved_capability", hint: H_CAP },
        RuleMeta { name: "text_source", hint: H_SRC },
        RuleMeta { name: "duplicate_declaration", hint: H_DUP },
        RuleMeta { name: "accessor_var", hint: H_ACC },
    ],
    allow: &["keys"],
    lists: &[],
};
pub fn metadata()->&'static Meta{&META}

#[cfg(test)]mod controlled_stage_tests{
 use super::*;
 struct Limited{left:usize,polls:usize,cancel:usize}
 impl crate::key_policy_control::Control for Limited{
  type Error=std::io::Error;const CHECKED:bool=true;
  fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.cancel{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}
  fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.left=self.left.checked_sub(n).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}
  fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}
  fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}
 }
 fn nested(depth:usize)->String{let mut s="op(\"leaf\")".to_owned();for i in 0..depth{s=format!("stages(nameof(state{i}), stage_step(A, B, {s}))")}s}
 #[test]fn iterative_checked_stages_preserve_original_recursive_keys_and_refuse_deep_work_without_stack(){
  let source=nested(5);let mut old=BTreeSet::new();collect_ops_controlled(&source,None,&mut old,&mut crate::key_policy_control::Compatibility).unwrap();
  let mut actual=BTreeSet::new();collect_ops_controlled(&source,None,&mut actual,&mut Limited{left:32*1024*1024,polls:0,cancel:usize::MAX}).unwrap();assert_eq!(actual,old);assert!(actual.contains("leaf"));assert!(actual.contains("state0_A_B"));
  let deep=nested(3000);let e=collect_ops_controlled(&deep,None,&mut BTreeSet::new(),&mut Limited{left:1024,polls:0,cancel:usize::MAX}).unwrap_err();assert_eq!(e.kind(),std::io::ErrorKind::OutOfMemory);
  let e=collect_ops_controlled(&source,None,&mut BTreeSet::new(),&mut Limited{left:32*1024*1024,polls:0,cancel:5}).unwrap_err();assert_eq!(e.raw_os_error(),Some(1450));
  let mut recovered=BTreeSet::new();collect_ops_controlled(&source,None,&mut recovered,&mut Limited{left:32*1024*1024,polls:0,cancel:usize::MAX}).unwrap();assert_eq!(recovered,old);
 }
}
