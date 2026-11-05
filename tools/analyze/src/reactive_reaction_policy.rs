//! Unique historical reaction-read lexical judgement over borrowed original
//! procedure views. The legacy Model stays in its legacy adapter only.
use std::collections::{HashSet,BTreeSet};
use crate::{tree::View,key_policy_control as kc,util::{py_strip,py_lstrip},pat};
#[derive(Clone,Copy)]pub enum Lines<'a>{Owned(&'a[(usize,String)]),Code{view:&'a View,first:usize,last:usize},IndentedCode{view:&'a View,first:usize}}
pub(crate) enum LineIter<'a>{Owned(std::slice::Iter<'a,(usize,String)>),Code{view:&'a View,next:usize,last:usize,done:bool},IndentedCode{view:&'a View,next:usize,done:bool}}
impl<'a> Iterator for LineIter<'a>{type Item=(usize,&'a str);fn next(&mut self)->Option<Self::Item>{match self{Self::Owned(rows)=>rows.next().map(|(n,line)|(*n,line.as_str())),Self::Code{view,next,last,done}=>{if *done||*next>*last{return None}let line=*next;if line==*last{*done=true}else{*next+=1}Some((line,view.line(line)))},Self::IndentedCode{view,next,done}=>{if *done||*next>view.num_lines(){return None}let number=*next;let text=view.line(number);if text.chars().next().is_some_and(|ch|!crate::util::is_py_space(ch)){*done=true;return None}*next+=1;Some((number,text))}}}}
impl<'a> Lines<'a>{pub(crate) fn iter(self)->LineIter<'a>{match self{Self::Owned(rows)=>LineIter::Owned(rows.iter()),Self::Code{view,first,last}=>LineIter::Code{view,next:first,last,done:false},Self::IndentedCode{view,first}=>LineIter::IndentedCode{view,next:first,done:false}}}}
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub enum ProcedureKey<'a>{Legacy(usize),Raw{relative:&'a str,header:usize}}
pub struct Procedure<'a>{pub owner:&'a str,pub name:&'a str,pub relative:&'a str,pub args:&'a str,pub lines:Lines<'a>}

/// Acceptance/spelling only on a genuinely issued original header line. This
/// does not discover procedures or grant source authority.
pub struct Header<'a>{pub owner:&'a str,pub name:&'a str,pub args:&'a str}
pub fn header(line:&str)->Option<Header<'_>>{match header_admitted(line,|_|Ok::<(),std::convert::Infallible>(())){Ok(value)=>value,Err(never)=>match never{}}}
pub fn header_admitted<'a,E>(line:&'a str,mut admit:impl FnMut(usize)->Result<(),E>)->Result<Option<Header<'a>>,E>{
 if !line.chars().next().is_some_and(|ch|!crate::util::is_py_space(ch)){return Ok(None)}
 let text=crate::util::py_rstrip(line);if text.starts_with('#')||crate::pat_match!(r"/[\w/]+\s*$").is_match(text){return Ok(None)}
 let pattern=crate::pat_match!(r"(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$");admit(pattern.capture_group_count())?;let Some(found)=pattern.captures(text)else{return Ok(None)};
 let owner=if found.s(1).is_empty(){"/"}else{found.s(1)};Ok(Some(Header{owner,name:found.s(2),args:found.s(3)}))
}
pub trait Membership{type Error;fn contains(&self,name:&str)->Result<bool,Self::Error>;}
impl Membership for HashSet<String>{type Error=std::convert::Infallible;fn contains(&self,name:&str)->Result<bool,Self::Error>{Ok(HashSet::contains(self,name))}}
pub trait Source{
 type Error;type Known<'a>:Membership<Error=Self::Error> where Self:'a;
 /// Stream only requested raw-policy names. False stops this lookup; it does
 /// not mint a compiled procedure/source receipt.
 fn for_each_named(&self,name:&str,visit:&mut dyn FnMut(ProcedureKey<'_>,Procedure<'_>)->Result<bool,Self::Error>)->Result<(),Self::Error>;
 fn known<'a>(&'a self,owner:&'a str)->Result<Self::Known<'a>,Self::Error>;
}
pub(crate) const GENERATED_SKIP_DIRS:&[&str]=&["code/modules/unit_tests/","code/tests/unit_tests/","code/modules/benchmarks/"];
pub(crate) const GENERATED_REL:&str="code/_generated/reads.dm";
pub(crate) const EXEMPT_VARS:&[&str]=&["cap_state","cap_data"];
fn helper_name(name:&str)->bool{crate::pat_match!(r"(?:life_hud|life_vision|life_canmove|update_canmove|hud_available|process_glasses|process_nifsoft_vision|pain_knockout_fraction|set_fullscreen|life_placed)").is_match(name)}
const REACTION_OUTPUTS: &[(&str, &str, &[&str], &[&str])] = &[
    (
        "hud",
        "life_hud_changed",
        &["life_hud", "life_hud_health_icons", "life_hud_darksight"],
        &[
            "dsoverlay", "health_doll_key", "healths", "damageoverlaytemp", "global_hud_claims", "alerts", "screens", "hud_list",
            "hud_used", "card", "borer_chem_display", "pai_fold_display",
        ],
    ),
    ("vision", "life_vision_changed", &["life_vision"], &["plane_holder", "global_hud_claims", "hud_used", "seer"]),
    (
        "canmove",
        "life_canmove_changed",
        &["life_canmove", "update_canmove"],
        &["canmove", "lying", "lying_prev", "passtable_crawl_checked", "passtable_reset", "pass_flags"],
    ),
];


fn without_matches<C:kc::Control>(pattern:&crate::pat::Pat,text:&str,control:&mut C)->Result<String,C::Error>{
 kc::reserve(control,||text.len().checked_mul(4)?.checked_add(64))?;let mut out=if C::CHECKED{let mut out=String::new();out.try_reserve_exact(text.len()).map_err(|_|control.allocation_failed())?;if out.capacity()>text.len().saturating_mul(4).saturating_add(64){return Err(control.allocation_failed())}out}else{String::with_capacity(text.len())};
 let mut last=0;crate::reactive_dependency_policy::captures(pattern,text,control,|_,matched|{out.push_str(&text[last..matched.start(0)]);last=matched.end(0);Ok(())})?;out.push_str(&text[last..]);Ok(out)
}
pub fn body_reads<C:kc::Control,K:Membership<Error=C::Error>>(proc:&Procedure<'_>,known:&K,control:&mut C)->Result<Vec<(String,usize)>,C::Error>{
    let mut locals:HashSet<String>=HashSet::new();
    fn parameter<C:kc::Control>(piece:&str,locals:&mut HashSet<String>,control:&mut C)->Result<(),C::Error>{
        control.checkpoint()?;let before_eq=py_strip(piece.split('=').next().unwrap_or(""));let piece=match pat!(r"\s+as\s+").find(before_eq){Some(m)=>&before_eq[..m.start],None=>before_eq};if !piece.is_empty(){kc::reserve(control,||Some(256))?;locals.insert(kc::own(control,py_strip(piece.rsplit('/').next().unwrap_or("")))?);}Ok(())
    }
    // SAME paren-only split/first closing delimiter policy as old args parser;
    // retain borrowed slices rather than copying an entire parameter roster.
    let mut depth=0i32;let mut from=0;let mut end=proc.args.len();
    for(at,ch)in proc.args.char_indices(){control.checkpoint()?;if ch=='('{depth+=1}else if ch==')'{if depth==0{end=at;break}depth-=1}if ch==','&&depth==0{parameter(&proc.args[from..at],&mut locals,control)?;from=at+1;}}
    parameter(&proc.args[from..end],&mut locals,control)?;
    let mut reads: Vec<(String, usize)> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for (number,line) in proc.lines.iter(){
        control.checkpoint()?;
        if py_strip(line).is_empty()||py_lstrip(line).starts_with('#') {
            continue;
        }
        let mut cur_line=std::borrow::Cow::Borrowed(line);
        loop {
            if pat!(r"\b(?:nameof|initial)\s*\([^()]*\)").find(cur_line.as_ref()).is_none(){break}
            let next=without_matches(pat!(r"\b(?:nameof|initial)\s*\([^()]*\)"),&cur_line,control)?;
            if next.as_str()==cur_line.as_ref(){
                break;
            }
            cur_line = std::borrow::Cow::Owned(next);
        }
        crate::reactive_dependency_policy::captures(pat!(r"\bvar/(?:[\w/]*/)?(\w+)"),&cur_line,control,|control,m|{control.checkpoint()?;kc::reserve(control,||Some(256))?;locals.insert(kc::own(control,m.s(1))?);Ok(())})?;
        crate::reactive_dependency_policy::captures(pat!(r"(?<![\w.:/])(?:src\.)?([A-Za-z_]\w*)\b(?!\s*\()(?!\s*::)(?!\s*=(?!=))"),&cur_line,control,|control,m|{
            control.checkpoint()?;let name = m.s(1);
            if known.contains(name)? && !locals.contains(name) && !seen.contains(name) && !EXEMPT_VARS.contains(&name) {
                kc::reserve(control,||Some(256))?;seen.insert(kc::own(control,name)?);crate::reactive_dependency_fold::row(control,&mut reads)?;
                reads.push((kc::own(control,name)?,number));
            }
            Ok(())
        })?;
    }
    control.checkpoint()?;Ok(reads)
}

/// Owned UNIQUE reaction summary only; never a procedure/body/source model.
pub enum OwnedProcedureKey{Legacy(usize),Raw{relative:String,header:usize}}
pub struct ReactionRead{pub owner:String,pub kind:&'static str,pub handler:&'static str,pub procedure:OwnedProcedureKey,pub reads:Vec<(String,usize)>}
fn own_key<C:kc::Control>(key:ProcedureKey<'_>,control:&mut C)->Result<OwnedProcedureKey,C::Error>{Ok(match key{ProcedureKey::Legacy(index)=>OwnedProcedureKey::Legacy(index),ProcedureKey::Raw{relative,header}=>OwnedProcedureKey::Raw{relative:kc::own(control,relative)?,header}})}
struct EveryName<E>(std::marker::PhantomData<E>);impl<E> Membership for EveryName<E>{type Error=E;fn contains(&self,_:&str)->Result<bool,E>{Ok(true)}}
fn eligible(proc:&Procedure<'_>)->bool{proc.owner.starts_with("/mob")&&!GENERATED_SKIP_DIRS.iter().any(|prefix|proc.relative.starts_with(prefix))&&proc.relative!=GENERATED_REL}
fn has_name<S:Source,C:kc::Control<Error=S::Error>>(source:&S,name:&str,control:&mut C)->Result<bool,C::Error>{let mut found=false;source.for_each_named(name,&mut|_key,proc|{control.checkpoint()?;if eligible(&proc)&&proc.name==name{found=true;Ok(false)}else{Ok(true)}})?;Ok(found)}
/// Exact historical helper closure over streaming raw-policy procedure loans.
/// No by-name/procedure index or owned body lines are rebuilt.
pub fn reaction_reads<S:Source,C:kc::Control<Error=S::Error>>(source:&S,control:&mut C)->Result<Vec<ReactionRead>,C::Error>{
 let mut out=Vec::new();
 for(kind,handler,roots,skip)in REACTION_OUTPUTS{
  let mut names=HashSet::new();let mut todo=Vec::new();
  for root in *roots{kc::reserve(control,||Some(256))?;names.insert(kc::own(control,root)?);crate::reactive_dependency_fold::row(control,&mut todo)?;todo.push(kc::own(control,root)?);}
  while let Some(name)=todo.pop(){
   // A page loan cannot recursively acquire another page while its source
   // views/scratch are live. Keep only ordered candidate identifiers, then
   // release the body loan before the exact original name-membership question.
   let mut called=Vec::new();source.for_each_named(&name,&mut|_key,proc|{
    control.checkpoint()?;if !eligible(&proc)||proc.name!=name.as_str(){return Ok(true)}
    for(_,text)in proc.lines.iter(){control.checkpoint()?;if py_strip(text).is_empty(){continue}crate::reactive_dependency_policy::captures(pat!(r"(?<![\w.])(?:src\.)?([A-Za-z_]\w*)\s*\("),text,control,|control,matched|{
     let callee=matched.s(1);if !names.contains(callee){crate::reactive_dependency_fold::row(control,&mut called)?;called.push(kc::own(control,callee)?);}Ok(())
    })?;}Ok(true)
   })?;
   for callee in called{control.checkpoint()?;if !names.contains(callee.as_str())&&has_name(source,&callee,control)?&&helper_name(&callee){kc::reserve(control,||Some(256))?;names.insert(kc::own(control,&callee)?);crate::reactive_dependency_fold::row(control,&mut todo)?;todo.push(callee);}}
  }
  kc::reserve(control,||names.len().checked_mul(std::mem::size_of::<&String>())?.checked_mul(4)?.checked_add(64))?;let mut sorted:Vec<&String>=names.iter().collect();if C::CHECKED&&sorted.capacity()>names.len().saturating_mul(4).saturating_add(8){return Err(control.allocation_failed())}sorted.sort();
  for name in sorted{
   let mut pending=Vec::new();source.for_each_named(name,&mut|key,proc|{
    control.checkpoint()?;if !eligible(&proc)||proc.name!=name.as_str(){return Ok(true)}
    let reads=body_reads(&proc,&EveryName(std::marker::PhantomData),control)?;let owner=kc::own(control,proc.owner)?;let key=own_key(key,control)?;crate::reactive_dependency_fold::row(control,&mut pending)?;pending.push((owner,key,reads));Ok(true)
   })?;
   for(owner,procedure,mut reads)in pending{
    // Same first-occurrence lexical reads, now filter actual immutable
    // membership after the file dies. In-place compaction preserves order and
    // moves original Strings; no second result/body roster is constructed.
    let known=source.known(&owner)?;let mut write=0;
    for read in 0..reads.len(){control.checkpoint()?;if known.contains(&reads[read].0)?&&!skip.contains(&reads[read].0.as_str()){if write!=read{reads.swap(write,read)}write+=1;}}
    reads.truncate(write);drop(known);crate::reactive_dependency_fold::row(control,&mut out)?;out.push(ReactionRead{owner,kind,handler,procedure,reads});
   }
  }
 }
 control.checkpoint()?;Ok(out)
}

pub fn reaction_pairs<S:Source,C:kc::Control<Error=S::Error>>(source:&S,control:&mut C)->Result<BTreeSet<(String,String)>,C::Error>{let mut out=BTreeSet::new();for read in reaction_reads(source,control)?{let owner=read.owner;for(name,_)in read.reads{control.checkpoint()?;kc::reserve(control,||Some(256))?;out.insert((kc::own(control,&owner)?,name));}}control.checkpoint()?;Ok(out)}

/// One old lexical declaration-pattern match. Raw policy data only: these
/// spans include inactive text and cannot issue compiled declaration receipts.
pub struct VariableName<'a>{pub owner_without_leading_slash:&'a str,pub qualified:&'a str,pub name:&'a str,pub line:usize}
const MODIFIERS:&[&str]=&["tmp","static","global","const","final"];
fn declared_name(path:&str)->Option<&str>{path.split('/').skip_while(|part|MODIFIERS.contains(part)).last()}
// Each row drops its capture before the next lexical declaration probe. Only
// slices of the already borrowed source are passed to the row consumer.
fn one<'h,C:kc::Control>(pattern:&crate::pat::Pat,text:&'h str,control:&mut C)->Result<Option<crate::pat::Caps<'h>>,C::Error>{kc::temporary(control,0,||pattern.capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64))?;Ok(pattern.captures(text))}
/// Stream the original parse_vars policy with scalar context only. No var/proc
/// table, owner String, hierarchy index or body-line copies are built.
pub fn visit_variable_names<'a,C:kc::Control>(view:&'a View,control:&mut C,emit:impl FnMut(&mut C,VariableName<'a>)->Result<bool,C::Error>)->Result<bool,C::Error>{visit_variable_lines(view.numbered(),control,emit)}
pub fn visit_variable_lines<'a,C:kc::Control>(lines:impl IntoIterator<Item=(usize,&'a str)>,control:&mut C,mut emit:impl FnMut(&mut C,VariableName<'a>)->Result<bool,C::Error>)->Result<bool,C::Error>{
 let mut current=None;let mut in_proc=false;let mut block_indent=None;
 for(number,raw)in lines{control.checkpoint()?;if py_strip(raw).is_empty(){continue}let stripped=raw.trim_start_matches(['\t',' ']);let indent=raw.len()-stripped.len();let text=crate::util::py_rstrip(stripped);if text.starts_with('#'){continue}
  if indent==0{block_indent=None;in_proc=false;current=None;
   let Some(m)=one(crate::pat_match!(r"(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()"),text,control)?else{continue};let path=m.s(1);let full=path.trim_matches('/');
   if full.split('/').any(|part|matches!(part,"proc"|"verb"))||crate::util::py_lstrip(&text[m.end(1)..]).starts_with('('){in_proc=true;continue}
   let mut at=0;let mut variable=None;
   for part in full.split('/'){if part=="var"{variable=Some(at);break}at+=part.len()+1;}
   if let Some(at)=variable{let after=&full[at+3..];if let Some(qualified)=after.strip_prefix('/') {if let Some(name)=declared_name(qualified){let owner=if at==0{""}else{&full[..at-1]};if !emit(control,VariableName{owner_without_leading_slash:owner,qualified,name,line:number})?{control.checkpoint()?;return Ok(false)}}}continue}
   current=Some(path.trim_end_matches('/').strip_prefix('/').unwrap_or(path.trim_end_matches('/')));continue
  }
  if in_proc{continue}let Some(owner)=current else{continue};
  if let Some(block)=block_indent{if indent>block{
   if let Some(m)=one(crate::pat_match!(r"((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)"),text,control)?{let qualified=m.s(1);if let Some(name)=declared_name(qualified){if !emit(control,VariableName{owner_without_leading_slash:owner,qualified,name,line:number})?{control.checkpoint()?;return Ok(false)}}}continue
  }}
  block_indent=None;if indent!=1&&!raw.starts_with("    "){continue}
  if crate::pat_match!(r"var(/(tmp|static|global|const))*\s*$").is_match(text){block_indent=Some(indent);continue}
  if let Some(m)=one(crate::pat_match!(r"var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)"),text,control)?{let qualified=m.s(1).trim_matches('/');if let Some(name)=declared_name(qualified){if !emit(control,VariableName{owner_without_leading_slash:owner,qualified,name,line:number})?{control.checkpoint()?;return Ok(false)}}}
 }
 control.checkpoint()?;Ok(true)
}
/// EXACT historical chain(path) membership, including its lexical implicit
/// roots. This deliberately does not follow semantic parent_type overrides.
pub fn owner_in_chain(candidate_without_leading_slash:&str,receiver:&str)->bool{
 let path=receiver.trim_matches('/');let candidate=candidate_without_leading_slash;
 if path.starts_with(candidate)&&(path.len()==candidate.len()||path.as_bytes().get(candidate.len())==Some(&b'/')){return true}
 let first=path.split('/').next().unwrap_or("");match candidate{"datum"=>matches!(first,"obj"|"mob"|"turf"|"area"|"atom"),"atom"=>matches!(first,"obj"|"mob"|"turf"|"area"),"atom/movable"=>matches!(first,"obj"|"mob"),_=>false}
}

#[cfg(test)]mod tests{
 use crate::{pat_match,util::py_rstrip};
 use super::*;use std::collections::HashMap;
 fn starts_any(relative:&str,prefixes:&[&str])->bool{prefixes.iter().any(|p|relative.starts_with(p))}
 const REACTION_OWNER_ROOT:&str="/mob";
 #[derive(Clone)]struct Proc{rel:String,owner:String,name:String,args:String,body:Vec<(usize,String)>}
 struct Model{procs:Vec<Proc>,vars:HashMap<String,HashSet<String>>}
 impl Model{fn union(&self,vars:&HashMap<String,HashSet<String>>,owner:&str)->HashSet<String>{vars.get(owner).cloned().unwrap_or_default()}}
 struct ReactionRead{kind:&'static str,handler:&'static str,proc:usize,reads:Vec<(String,usize)>}
 fn body_reads(proc: &Proc, known: &HashSet<String>) -> Vec<(String, usize)> {
    let mut locals: HashSet<String> = HashSet::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    let mut params: Vec<String> = Vec::new();
    for ch in proc.args.chars() {
        if ch == '(' {
            depth += 1;
        } else if ch == ')' {
            if depth == 0 {
                break;
            }
            depth -= 1;
        }
        if ch == ',' && depth == 0 {
            params.push(std::mem::take(&mut cur));
        } else {
            cur.push(ch);
        }
    }
    params.push(cur);
    for p in &params {
        let before_eq = py_strip(p.split('=').next().unwrap_or(""));
        let piece = match pat!(r"\s+as\s+").find(before_eq) {
            Some(m) => &before_eq[..m.start],
            None => before_eq,
        };
        if !piece.is_empty() {
            locals.insert(py_strip(piece.rsplit('/').next().unwrap_or("")).to_string());
        }
    }
    let mut reads: Vec<(String, usize)> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for (number, line) in &proc.body {
        if py_lstrip(line).starts_with('#') {
            continue;
        }
        let mut cur_line = line.clone();
        loop {
            let next = pat!(r"\b(?:nameof|initial)\s*\([^()]*\)").replace_all(&cur_line, "");
            if next == cur_line {
                break;
            }
            cur_line = next;
        }
        for m in pat!(r"\bvar/(?:[\w/]*/)?(\w+)").captures_iter(&cur_line) {
            locals.insert(m.s(1).to_string());
        }
        for m in pat!(r"(?<![\w.:/])(?:src\.)?([A-Za-z_]\w*)\b(?!\s*\()(?!\s*::)(?!\s*=(?!=))").captures_iter(&cur_line) {
            let name = m.s(1);
            if known.contains(name) && !locals.contains(name) && !seen.contains(name) && !EXEMPT_VARS.contains(&name) {
                seen.insert(name.to_string());
                reads.push((name.to_string(), *number));
            }
        }
    }
    reads
}
 fn original_reaction_reads(model: &Model) -> Vec<ReactionRead> {
    let mut byname: HashMap<&str, Vec<usize>> = HashMap::new();
    for (i, proc) in model.procs.iter().enumerate() {
        if proc.owner.starts_with(REACTION_OWNER_ROOT) && !starts_any(&proc.rel, GENERATED_SKIP_DIRS) && proc.rel != GENERATED_REL {
            byname.entry(proc.name.as_str()).or_default().push(i);
        }
    }
    let mut out = Vec::new();
    for (kind, handler, roots, skip) in REACTION_OUTPUTS {
        let mut names: HashSet<String> = roots.iter().map(|s| s.to_string()).collect();
        let mut todo: Vec<String> = roots.iter().map(|s| s.to_string()).collect();
        while let Some(t) = todo.pop() {
            for &pi in byname.get(t.as_str()).map(|v| v.as_slice()).unwrap_or(&[]) {
                for (_n, text) in &model.procs[pi].body {
                    for m in pat!(r"(?<![\w.])(?:src\.)?([A-Za-z_]\w*)\s*\(").captures_iter(text) {
                        let name = m.s(1);
                        if !names.contains(name) && byname.contains_key(name) && helper_name(name) {
                            names.insert(name.to_string());
                            todo.push(name.to_string());
                        }
                    }
                }
            }
        }
        let mut sorted: Vec<&String> = names.iter().collect();
        sorted.sort();
        for name in sorted {
            for &pi in byname.get(name.as_str()).map(|v| v.as_slice()).unwrap_or(&[]) {
                let proc = &model.procs[pi];
                let known = model.union(&model.vars, &proc.owner);
                let reads: Vec<(String, usize)> = body_reads(proc, &known).into_iter().filter(|(v, _)| !skip.contains(&v.as_str())).collect();
                out.push(ReactionRead { kind, handler, proc: pi, reads });
            }
        }
    }
    out
}
 struct Borrowed<'a>(&'a Model);
 impl Source for Borrowed<'_>{type Error=std::convert::Infallible;type Known<'a>=HashSet<String>where Self:'a;
 fn for_each_named(&self,name:&str,visit:&mut dyn FnMut(ProcedureKey<'_>,Procedure<'_>)->Result<bool,Self::Error>)->Result<(),Self::Error>{for(index,p)in self.0.procs.iter().enumerate(){if p.name==name&&!visit(ProcedureKey::Legacy(index),Procedure{owner:&p.owner,name:&p.name,relative:&p.rel,args:&p.args,lines:Lines::Owned(&p.body)})?{break}}Ok(())}
 fn known<'a>(&'a self,owner:&'a str)->Result<Self::Known<'a>,Self::Error>{Ok(self.0.union(&self.0.vars,owner))}}

 fn proc(owner:&str,name:&str,body:&str)->Proc{Proc{rel:"code/probe.dm".into(),owner:owner.into(),name:name.into(),args:"value, datum/box/local=initial(seed))".into(),body:body.lines().enumerate().map(|(n,l)|(n+10,l.to_owned())).collect()}}
 #[test]fn independent_original_helper_closure_and_each_ordered_read_row_match_borrowed_policy(){
  let mut procs=vec![proc("/mob/a","life_hud","life_hud_health_icons()\nprocess_glasses()\nunrelated()\nenergy += 1\nhud_list"),proc("/mob/a","life_hud_health_icons","src.energy + local + value + initial(hidden) + nameof(ignored)\nvar/other = 1\nother + pressure"),proc("/mob/b","process_glasses","life_vision()\ncharge"),proc("/mob/a","life_vision","process_glasses()\nsight + plane_holder"),proc("/mob/a","life_canmove","update_canmove()\ncanmove + speed"),proc("/mob/a","update_canmove","speed + cap_state + cap_data"),proc("/mobile","life_hud","odd_prefix"),proc("/datum/not_mob","life_hud","not_read")];let mut skipped=proc("/mob/a","process_glasses","ignored");skipped.rel="code/tests/unit_tests/ignored.dm".into();procs.push(skipped);
  let names:HashSet<String>=["energy","local","value","hidden","ignored","pressure","charge","sight","plane_holder","canmove","speed","cap_state","cap_data","odd_prefix","not_read","hud_list"].into_iter().map(str::to_owned).collect();let vars=["/mob/a","/mob/b","/mobile","/datum/not_mob"].into_iter().map(|owner|(owner.to_owned(),names.clone())).collect();let model=Model{procs,vars};let expected=original_reaction_reads(&model).into_iter().map(|r|(r.kind,r.handler,r.proc,r.reads)).collect::<Vec<_>>();let source=Borrowed(&model);let got=super::reaction_reads(&source,&mut kc::Compatibility).unwrap().into_iter().map(|r|(r.kind,r.handler,match r.procedure{OwnedProcedureKey::Legacy(index)=>index,OwnedProcedureKey::Raw{..}=>panic!("legacy source emitted raw locator")},r.reads)).collect::<Vec<_>>();assert_eq!(got,expected);assert!(!got.is_empty());assert!(got.iter().any(|(_,_,index,_)|*index==6),"old /mob prefix rule is retained");
 }
 #[test]fn code_line_loan_filters_blank_work_without_changing_lexical_reads(){let view=View::new("energy + value\n\n    pressure + initial(hidden)\n".into());let owned=Proc{rel:"code/probe.dm".into(),owner:"/mob/a".into(),name:"life_hud".into(),args:"value)".into(),body:vec![(1,"energy + value".into()),(3,"    pressure + initial(hidden)".into())]};let known:HashSet<String>=["energy","value","pressure","hidden"].into_iter().map(str::to_owned).collect();let expected=body_reads(&owned,&known);let borrowed=Procedure{owner:&owned.owner,name:&owned.name,relative:&owned.rel,args:&owned.args,lines:Lines::Code{view:&view,first:1,last:view.num_lines()}};assert_eq!(super::body_reads(&borrowed,&known,&mut kc::Compatibility).unwrap(),expected);}

 mod raw_variable_oracle{
  use super::*;type VarTable=HashMap<String,HashSet<String>>;
  const OBJECT_ROOTS:&[&str]=&["datum","obj","mob","atom","turf","area","client","image","list"];
fn path_prefixes(path: &str) -> Vec<String> {
    let segs: Vec<&str> = path.trim_matches('/').split('/').collect();
    (1..=segs.len()).map(|i| format!("/{}", segs[..i].join("/"))).collect()
}

/// `state_schema_lint.chain`: the type and its ancestors, root first, with DM's implicit parents.
fn chain(path: &str) -> Vec<String> {
    let mut out = path_prefixes(path);
    if out[0] != "/datum" {
        let first = out[0].clone();
        if matches!(first.as_str(), "/obj" | "/mob" | "/turf" | "/area") {
            let n = if first == "/obj" || first == "/mob" { 3 } else { 2 };
            let mut pre: Vec<String> = ["/datum", "/atom", "/atom/movable"][..n].iter().map(|s| s.to_string()).collect();
            pre.extend(out);
            out = pre;
        } else if first == "/atom" {
            out.insert(0, "/datum".to_string());
        }
    }
    out
}


fn decl_name(segs: &[&str]) -> Option<String> {
    let mut i = 0;
    while i < segs.len() && MODIFIERS.contains(&segs[i]) {
        i += 1;
    }
    segs[i..].last().map(|s| s.to_string())
}

fn note_typed(typed: &mut VarTable, owner: &str, segs: &[&str], name: &str) {
    let segs: Vec<&&str> = segs.iter().filter(|s| !s.is_empty() && !MODIFIERS.contains(*s)).collect();
    if segs.len() > 1 && OBJECT_ROOTS.contains(segs[0]) {
        typed.entry(owner.to_string()).or_default().insert(name.to_string());
    }
}

/// `parse_vars`: `{type: var names}` declared in one file's `code_only` lines; `typed` collects the
/// object-typed ones.
fn parse_vars(lines: &[&str], typed: &mut VarTable) -> VarTable {
    let mut found: VarTable = HashMap::new();
    let mut cur: Option<String> = None;
    let mut in_proc = false;
    let mut block_indent: Option<usize> = None;
    for raw in lines {
        if py_strip(raw).is_empty() {
            continue;
        }
        let stripped = raw.trim_start_matches(['\t', ' ']);
        let indent = raw.len() - stripped.len();
        let text = py_rstrip(stripped);
        if text.starts_with('#') {
            continue;
        }
        if indent == 0 {
            block_indent = None;
            in_proc = false;
            cur = None;
            let Some(m) = pat_match!(r"(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()").captures(text) else { continue };
            let g1 = m.s(1);
            let full = if g1.starts_with('/') { g1.to_string() } else { format!("/{}", g1) };
            let segs: Vec<&str> = full.trim_matches('/').split('/').collect();
            if segs.contains(&"proc") || segs.contains(&"verb") || py_lstrip(&text[m.end(1)..]).starts_with('(') {
                in_proc = true;
                continue;
            }
            if let Some(k) = segs.iter().position(|s| *s == "var") {
                if let Some(name) = decl_name(&segs[k + 1..]) {
                    let owner = format!("/{}", segs[..k].join("/"));
                    found.entry(owner.clone()).or_default().insert(name.clone());
                    note_typed(typed, &owner, &segs[k + 1..], &name);
                }
                continue;
            }
            cur = Some(full.trim_end_matches('/').to_string());
            continue;
        }
        if in_proc {
            continue;
        }
        let Some(owner) = cur.clone() else { continue };
        if let Some(bi) = block_indent {
            if indent > bi {
                if let Some(m) = pat_match!(r"((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)").captures(text) {
                    let segs: Vec<&str> = m.s(1).split('/').collect();
                    if let Some(name) = decl_name(&segs) {
                        found.entry(owner.clone()).or_default().insert(name.clone());
                        note_typed(typed, &owner, &segs, &name);
                    }
                }
                continue;
            }
        }
        block_indent = None;
        if indent != 1 && !raw.starts_with("    ") {
            continue;
        }
        if pat_match!(r"var(/(tmp|static|global|const))*\s*$").is_match(text) {
            block_indent = Some(indent);
            continue;
        }
        if let Some(m) = pat_match!(r"var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)").captures(text) {
            let segs: Vec<&str> = m.s(1).trim_matches('/').split('/').collect();
            if let Some(name) = decl_name(&segs) {
                found.entry(owner.clone()).or_default().insert(name.clone());
                note_typed(typed, &owner, &segs, &name);
            }
        }
    }
    found
}


  #[test]fn same_borrowed_lexical_rows_preserve_original_vars_typedness_and_inactive_text(){
   let text="/mob/probe\n    var/own\n    var/list/typed[2]\n    var/tmp\n        datum/box/inside\n        static/plain=1\n    var/const/global/static\n  var/ignored_two_spaces\n\tvar/tabbed\n#if 0\n    var/inactive\n#endif\n/mob/probe/var/datum/thing/absolute=1\n/mob/probe/proc/run()\n    var/local_never_member\n/mob/other\n    var/list as num\n        nested_weird\n    var/block\n        var/nested\nvar/global/root_value=1\n/atom/movable/var/static/flag\n";
   let lines:Vec<_>=text.lines().collect();let mut expected_typed=VarTable::new();let expected=parse_vars(&lines,&mut expected_typed);let mut got=VarTable::new();let mut got_typed=VarTable::new();
   super::super::visit_variable_lines(lines.iter().enumerate().map(|(i,line)|(i+1,*line)),&mut kc::Compatibility,|_,row|{let owner=format!("/{}",row.owner_without_leading_slash);got.entry(owner.clone()).or_default().insert(row.name.to_owned());let parts:Vec<_>=row.qualified.split('/').collect();note_typed(&mut got_typed,&owner,&parts,row.name);Ok(true)}).unwrap();
   assert_eq!(got,expected);assert_eq!(got_typed,expected_typed);assert!(got["/mob/probe"].contains("inactive"),"old lexical policy includes inactive text");assert!(!got["/mob/probe"].contains("local_never_member"));assert!(got["/"].contains("root_value"));
  }
  #[test]fn no_allocation_owner_membership_matches_exact_old_chain_for_implicit_and_lexical_paths(){
   let paths=["/","/datum","/datum/probe","/obj","/obj/item/deep","/mob","/mob/living/probe","/turf/open","/area/test","/atom","/atom/movable/deep","/client","/image/probe","/mobile/probe","obj//item/"];
   let candidates=["","datum","obj","obj/item","obj/item/deep","mob","mob/living","turf","area","atom","atom/movable","client","image","mobile","obj/","nope"];
   for receiver in paths{let old=chain(receiver);for owner in candidates{assert_eq!(super::super::owner_in_chain(owner,receiver),old.iter().any(|value|value==&format!("/{owner}")),"receiver={receiver},owner={owner},old={old:?}");}}
  }
 }

}

#[cfg(test)]mod page_loan_tests{
 use super::*;use std::{cell::Cell,convert::Infallible};
 struct LoanSource{active:Cell<bool>,root:Vec<(usize,String)>,helper:Vec<(usize,String)>}
 struct Known<'a>(&'a LoanSource);impl Membership for Known<'_>{type Error=Infallible;fn contains(&self,name:&str)->Result<bool,Infallible>{assert!(!self.0.active.get(),"membership lookup nested inside original file loan");Ok(name=="charge")}}
 impl Source for LoanSource{type Error=Infallible;type Known<'a>=Known<'a> where Self:'a;
 fn for_each_named(&self,name:&str,visit:&mut dyn FnMut(ProcedureKey<'_>,Procedure<'_>)->Result<bool,Infallible>)->Result<(),Infallible>{assert!(!self.active.replace(true),"name lookup nested inside original file loan");let rows=match name{"life_hud"=>Some((0,&self.root)),"life_hud_helper"=>Some((1,&self.helper)),_=>None};if let Some((index,rows))=rows{let answer=visit(ProcedureKey::Legacy(index),Procedure{owner:"/mob/unit",name,relative:"code/unit.dm",args:"",lines:Lines::Owned(rows)});self.active.set(false);answer?;}else{self.active.set(false)}Ok(())}
 fn known<'a>(&'a self,_:&'a str)->Result<Known<'a>,Infallible>{assert!(!self.active.get());Ok(Known(self))}}
 #[test]fn reaction_name_and_variable_questions_wait_until_actual_local_body_loan_ends(){let source=LoanSource{active:Cell::new(false),root:vec![(2,"\tcharge + unknown".into()),(3,"\tlife_hud_helper()".into())],helper:vec![(7,"\tcharge + charge".into())]};let rows=reaction_reads(&source,&mut kc::Compatibility).unwrap();let hud:Vec<_>=rows.iter().filter(|row|row.kind=="hud").map(|row|(row.owner.as_str(),row.reads.as_slice())).collect();assert_eq!(hud,vec![("/mob/unit",[("charge".to_owned(),2)].as_slice()),("/mob/unit",[("charge".to_owned(),7)].as_slice())]);assert!(!source.active.get());}
}
