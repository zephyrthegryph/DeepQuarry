//! Native admitted pattern programs. Original Pat constructors stay unchanged.
//! The query owner supplies one real allocation lender; this module has no cache.
pub use regex_syntax::native_admission as admission;
use admission::{Hook,Refused};
use std::borrow::Cow;
use regex_automata::native::Regex as Plain;
use fancy_regex::native::Regex as Fancy;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub enum Mode{Search,Match,Full}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct Spec<'a>{pub pattern:&'a str,pub mode:Mode}
/// Borrowed actual same-Db execution port. Implementations must retain program
/// and scratch owners through the visitor; no compiler host is stored here.
/// A syntax-only diagnostic retains the original error object and its real
/// allocation owner. Operational failures stay in the outer Result channel.
#[derive(Debug)]pub enum Validation{Valid,Invalid(std::io::Error)}
pub trait Provider:Sync{
 fn validate(&self,spec:Spec)->std::io::Result<Validation>{self.capture_len(spec).map(|_|Validation::Valid)}

 fn capture_len(&self,spec:Spec)->std::io::Result<usize>;
 fn find(&self,spec:Spec,text:&str,start:usize,visit:&mut dyn FnMut((usize,usize))->std::io::Result<()>)->std::io::Result<bool>;
 fn capture(&self,spec:Spec,text:&str,start:usize,visit:&mut dyn FnMut(&[Option<(usize,usize)>])->std::io::Result<()>)->std::io::Result<bool>;
}
impl Spec<'_>{
 pub fn fingerprint(self)->u128{xxhash_rust::xxh3::xxh3_128_with_seed(self.pattern.as_bytes(),self.mode as u64)}
}
#[derive(Debug)]
pub enum CompileFailure{Refused,Invalid(String)}
impl From<Refused> for CompileFailure{fn from(_:Refused)->Self{Self::Refused}}
enum Actual{Plain(Plain),Behind{re:Plain,class:Plain,negative:bool},Fancy{re:Fancy,pre:Option<Plain>}}
pub struct Program{signature:u128,actual:Actual}
impl Program{
 /// Corroborating compiler DATA only. The actual host owner retains and
 /// compares full source/mode Params; this hash never establishes equality.
 pub fn signature(&self)->u128{self.signature}

 pub fn retained_bytes(&self)->Option<usize>{match &self.actual{Actual::Plain(re)=>re.retained_bytes(),Actual::Behind{re,class,..}=>re.retained_bytes()?.checked_add(class.retained_bytes()?),Actual::Fancy{re,pre}=>re.retained_bytes()?.checked_add(match pre{Some(pre)=>pre.retained_bytes()?,None=>0})}}
 pub fn capture_len(&self)->usize{match &self.actual{Actual::Plain(re)|Actual::Behind{re,..}=>re.capture_len(),Actual::Fancy{re,..}=>re.capture_len()}}
 /// Original Pat::find applies its existing optional prefilter; captures
 /// does not. Keep that distinction, including the original UTF8-class DATA
 /// behavior, rather than treating this optimization as semantic authority.
 pub fn find_at(&self,hay:&str,start:usize,hook:&Hook<'_>)->Result<Option<(usize,usize)>,Refused>{
  hook.require_active()?;hook.checkpoint()?;
  if let Actual::Fancy{pre:Some(pre),..}=&self.actual{if plain_captures(pre,&hay[start..],0,hook)?.is_none(){return Ok(None)}}
  Ok(self.captures_at(hay,start,hook)?.and_then(|rows|rows.first().copied().flatten()))
 }
 /// Scratch and returned rows are both admitted by the caller's live operation
 /// hook. Neither they nor the hook are retained in the compiled query value.
 pub fn captures_at(&self,hay:&str,start:usize,hook:&Hook<'_>)->Result<Option<Vec<Option<(usize,usize)>>>,Refused>{
  hook.require_active()?;hook.checkpoint()?;
  match &self.actual{
   Actual::Plain(re)=>plain_captures(re,hay,start,hook),
   Actual::Behind{re,class,negative}=>{
    let mut at=start;
    while at<=hay.len(){
     hook.checkpoint()?;let Some(rows)=plain_captures(re,hay,at,hook)? else{return Ok(None)};
     let Some((begin,_))=rows.first().copied().flatten() else{return Err(hook.allocation_failed())};
     let allowed=if begin==0{*negative}else{
      let prev=hay[..begin].chars().next_back().ok_or_else(||hook.allocation_failed())?;let mut bytes=[0;4];
      let included=plain_captures(class,prev.encode_utf8(&mut bytes),0,hook)?.is_some();included!=*negative
     };
     if allowed{return Ok(Some(rows))}
     at=begin.checked_add(hay[begin..].chars().next().map_or(1,char::len_utf8)).ok_or_else(||hook.overflow())?;
    }Ok(None)
   }
   Actual::Fancy{re,..}=>{
    let saves=match re.search(hay,start,hook){
     Ok(actual)=>actual,
     Err(fancy_regex::Error::RuntimeError(fancy_regex::RuntimeError::NativeAdmissionRefused))=>return Err(Refused),
     // Original Pat treats the Fancy backtrack-limit failure as no match.
     Err(_)=>{hook.checkpoint()?;return Ok(None)},
    };
    let Some(saves)=saves else{return Ok(None)};let mut rows=Vec::new();
    for pair in saves.chunks_exact(2).take(re.capture_len()){
     let actual=if pair[0]==usize::MAX{None}else{Some((pair[0],pair[1]))};hook.push(&mut rows,actual)?;
    }Ok(Some(rows))
   }
  }
 }
}
fn plain_captures(re:&Plain,hay:&str,start:usize,hook:&Hook<'_>)->Result<Option<Vec<Option<(usize,usize)>>>,Refused>{
 let mut executor=re.executor(hook)?;
 let Some(slots)=executor.search(&regex_automata::Input::new(hay).span(start..hay.len()))? else{return Ok(None)};
 let mut rows=Vec::new();for group in 0..re.capture_len(){hook.push(&mut rows,slots.get(group))?}Ok(Some(rows))
}
pub fn compile(spec:Spec,hook:&Hook<'_>)->Result<Program,CompileFailure>{
 hook.require_active()?;hook.checkpoint()?;
 let source=match spec.mode{
  Mode::Search=>Cow::Borrowed(spec.pattern),
  Mode::Match=>Cow::Owned(hook.format(format_args!(r"\A(?:{})",spec.pattern))?),
  Mode::Full=>Cow::Owned(hook.format(format_args!(r"\A(?:{})\z",spec.pattern))?),
 };
 if let Some((class,negative,rest))=split_leading_lookbehind(&source){
  let re=Plain::compile(rest,Some(10*(1<<20)),hook);hook.checkpoint()?;
  let wrapped=hook.format(format_args!("^(?:{})$",class))?;
  let cls=Plain::compile(&wrapped,Some(10*(1<<20)),hook);hook.checkpoint()?;
  if let(Ok(re),Ok(class))=(re,cls){return Ok(Program{signature:spec.fingerprint(),actual:Actual::Behind{re,class,negative}})}
 }
 let plain=Plain::compile(&source,Some(10*(1<<20)),hook);hook.checkpoint()?;
 match plain{
  Ok(re)=>Ok(Program{signature:spec.fingerprint(),actual:Actual::Plain(re)}),
  Err(plain)=>match Fancy::compile(&source,hook){
   Ok(re)=>{
    let pre=if let Some(source)=strip_lookarounds(&source,hook)?{let result=Plain::compile(&source,Some(10*(1<<20)),hook);hook.checkpoint()?;result.ok()}else{None};
    Ok(Program{signature:spec.fingerprint(),actual:Actual::Fancy{re,pre}})
   },
   Err(actual)=>{hook.checkpoint()?;Err(CompileFailure::Invalid(hook.format(format_args!("{:?} / {}",plain,actual))?))},
  },
 }
}
fn append_char(out:&mut String,ch:char,hook:&Hook<'_>)->Result<(),Refused>{let mut bytes=[0;4];hook.append(out,ch.encode_utf8(&mut bytes))}
fn split_leading_lookbehind(p: &str) -> Option<(&str,bool,&str)> {
    let (negative, rest) = if let Some(r) = p.strip_prefix("(?<!") {
        (true, r)
    } else if let Some(r) = p.strip_prefix("(?<=") {
        (false, r)
    } else {
        return None;
    };
    let bytes = rest.as_bytes();
    let class_end = if bytes.first() == Some(&b'[') {
        // find the closing ] of the class (a `]` right after `[` or `[^` is literal)
        let mut i = 1;
        if bytes.get(i) == Some(&b'^') {
            i += 1;
        }
        if bytes.get(i) == Some(&b']') {
            i += 1;
        }
        loop {
            match bytes.get(i) {
                None => return None,
                Some(b'\\') => i += 2,
                Some(b']') => break i + 1,
                Some(_) => i += 1,
            }
        }
    } else if bytes.first() == Some(&b'\\') {
        2
    } else if bytes.first().map(|b| b.is_ascii_alphanumeric() || *b == b'_' || *b == b'/').unwrap_or(false) {
        1
    } else {
        return None;
    };
    if rest.as_bytes().get(class_end) != Some(&b')') {
        return None;
    }
    let class = &rest[..class_end];
    let remainder = &rest[class_end + 1..];
    // The remainder must itself be free of look-around so it can run on the plain engine, and
    // must not have a top-level `|` (the lookbehind would bind only the first alternative).
    if remainder.contains("(?<") || remainder.contains("(?=") || remainder.contains("(?!") || has_backref(remainder) || has_top_level_alt(remainder) {
        return None;
    }
    Some((class,negative,remainder))
}

fn has_top_level_alt(p: &str) -> bool {
    let b = p.as_bytes();
    let (mut depth, mut i, mut in_class) = (0i32, 0usize, false);
    while i < b.len() {
        match b[i] {
            b'\\' => i += 1,
            b'[' if !in_class => in_class = true,
            b']' if in_class => in_class = false,
            b'(' if !in_class => depth += 1,
            b')' if !in_class => depth -= 1,
            b'|' if !in_class && depth == 0 => return true,
            _ => {}
        }
        i += 1;
    }
    false
}

fn strip_lookarounds(p:&str,hook:&Hook<'_>)->Result<Option<String>,Refused>{
    if has_backref(p) {
        return Ok(None);
    }
    let b = p.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    let mut in_class = false;
    while i < b.len() {
        hook.checkpoint()?;
        let c = b[i];
        if c == b'\\' {
            hook.append(&mut out,&p[i..(i + 2).min(p.len())])?;
            i += 2;
            continue;
        }
        if in_class {
            if c == b']' {
                in_class = false;
            }
            append_char(&mut out,c as char,hook)?;
            i += 1;
            continue;
        }
        if c == b'[' {
            in_class = true;
            append_char(&mut out,'[',hook)?;
            i += 1;
            continue;
        }
        if p[i..].starts_with("(?<!") || p[i..].starts_with("(?<=") || p[i..].starts_with("(?!") || p[i..].starts_with("(?=") {
            // skip to the matching close paren
            let mut depth = 0i32;
            let mut j = i;
            let mut cls = false;
            while j < b.len() {
                hook.checkpoint()?;
                match b[j] {
                    b'\\' => j += 1,
                    b'[' if !cls => cls = true,
                    b']' if cls => cls = false,
                    b'(' if !cls => depth += 1,
                    b')' if !cls => {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                    _ => {}
                }
                j += 1;
            }
            i = j + 1;
            continue;
        }
        let ch = p[i..].chars().next().unwrap();
        append_char(&mut out,ch,hook)?;
        i += ch.len_utf8();
    }
    Ok(Some(out))
}
fn has_backref(p: &str) -> bool {
    let b = p.as_bytes();
    let mut i = 0;
    while i + 1 < b.len() {
        if b[i] == b'\\' {
            if b[i + 1].is_ascii_digit() && b[i + 1] != b'0' {
                return true;
            }
            i += 2;
        } else {
            i += 1;
        }
    }
    false
}
