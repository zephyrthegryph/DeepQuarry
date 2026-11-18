//! Original key/source call policy over a borrowed, comment-stripped raw view.
//! A declaration DSL policy only; no type/procedure tree or semantic parser.
const DEFINE_SOURCE:&str=r"\s*define\s+(\w+)";
const ENTRY_OP_SOURCE:&str=r#"(?<![\w./])op\(\s*"([^"]+)""#;
const ENTRY_HEADER_SOURCE:&str=r"^(/datum/[\w/]+)/entries\(\)";
const CALLS_SOURCE:&str=r"(?<![\w./])(extend|without|on_op|shares_effects|above|perform_op|e0_perform_op|configure|hold|hold_until|hold_override|grant|release|status_end)\s*\(";
use crate::raw_marker_policy::{matching_paren,split_args};
use crate::raw_fixture_policy::{Fixture,PatternApi,PatternMode};
/// What a key literal names, by the call it sits in (doc/rewrite/final_api.html section 4,
/// "Three kinds of key").
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum KeyKind {
    Op,
    Capability,
}

#[derive(Clone, Debug)]
pub struct KeyRef {
    pub kind: KeyKind,
    pub key: String,
    /// The call it sits in.
    pub call: String,
    pub rel: String,
    pub line: u32,
}

/// Calls whose string-literal arguments are op keys, and those whose first literal is a capability key.
pub const OP_KEY_CALLS: &[&str] = &[
    "extend",
    "without",
    "on_op",
    "shares_effects",
    "above",
    "perform_op",
    "e0_perform_op",
];
pub const CAP_KEY_CALLS: &[&str] = &["configure"];
/// Calls whose `source =` argument must be a datum or SRC_*, never text or null.
pub const SOURCE_CALLS: &[&str] = &[
    "hold",
    "hold_until",
    "hold_override",
    "grant",
    "release",
    "status_end",
];


pub fn visit_calls(rel:&str,stripped:&str,starts:&[u32],mut key:impl FnMut(KeyRef),mut bad_source:impl FnMut((String,u32,String))){
    let complete:Result<(),()>=visit_calls_with(rel,stripped,starts,|value|{key(value);Ok(())},|value|{bad_source(value);Ok(())},None,&||());
    debug_assert!(complete.is_ok());
}
/// A native producer must discard all callback rows if admission returns false.
/// Reservation runs BEFORE argument splitting and owned callback strings.
pub fn visit_calls_checked(rel:&str,stripped:&str,starts:&[u32],mut key:impl FnMut(KeyRef),mut bad_source:impl FnMut((String,u32,String)),mut admit:impl FnMut(usize)->bool)->bool{
    visit_calls_with(rel,stripped,starts,|value|{key(value);Ok(())},|value|{bad_source(value);Ok(())},Some(&mut|n|if admit(n){Ok(())}else{Err(())}),&||()).is_ok()
}
fn work<E>(admit:&mut Option<&mut dyn FnMut(usize)->Result<(),E>>,bytes:impl FnOnce()->Option<usize>,overflow:&dyn Fn()->E)->Result<(),E>{
    match admit.as_mut(){None=>Ok(()),Some(admit)=>admit(bytes().ok_or_else(overflow)?)}
}
/// Typed resource/control boundary over the SAME original callback algorithm.
/// Arithmetic overflow is a typed resource failure, never source meaning.
pub fn visit_calls_admitted<E>(rel:&str,stripped:&str,starts:&[u32],mut key:impl FnMut(KeyRef),mut bad_source:impl FnMut((String,u32,String)),mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E)->Result<(),E>{
    visit_calls_with(rel,stripped,starts,|value|{key(value);Ok(())},|value|{bad_source(value);Ok(())},Some(&mut admit),&overflow)
}
/// Typed owned-row callbacks return their actual first failure immediately.
/// Pure DATA production; source/EOF completion is issued only by the host.
pub(crate) fn visit_calls_try_admitted<E>(rel:&str,stripped:&str,starts:&[u32],key:impl FnMut(KeyRef)->Result<(),E>,bad_source:impl FnMut((String,u32,String))->Result<(),E>,mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E)->Result<(),E>{
 visit_calls_with(rel,stripped,starts,key,bad_source,Some(&mut admit),&overflow)
}
fn calls_pattern()->&'static crate::pat::Pat{
    static RE: std::sync::LazyLock<crate::pat::Pat> = std::sync::LazyLock::new(|| {
        crate::pat::Pat::new(
            r"(?<![\w./])(extend|without|on_op|shares_effects|above|perform_op|e0_perform_op|configure|hold|hold_until|hold_override|grant|release|status_end)\s*\(",
        )
    });
    &RE
}
fn visit_calls_with<E>(rel:&str,stripped:&str,starts:&[u32],mut key:impl FnMut(KeyRef)->Result<(),E>,mut bad_source:impl FnMut((String,u32,String))->Result<(),E>,mut admit:Option<&mut dyn FnMut(usize)->Result<(),E>>,overflow:&dyn Fn()->E)->Result<(),E> {
 visit_calls_pattern(rel,stripped,starts,key,bad_source,admit,overflow,calls_pattern())
}
fn visit_calls_pattern<E,P:PatternApi>(rel:&str,stripped:&str,starts:&[u32],mut key:impl FnMut(KeyRef)->Result<(),E>,mut bad_source:impl FnMut((String,u32,String))->Result<(),E>,mut admit:Option<&mut dyn FnMut(usize)->Result<(),E>>,overflow:&dyn Fn()->E,pattern:&P)->Result<(),E> {
    let line_of = |off: usize| -> u32 {
        match starts.binary_search(&(off as u32)) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    };
    work(&mut admit,||pattern.capture_group_count().checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>()).and_then(|n|n.checked_add(128)),overflow)?;
    for m in pattern.captures_iter(stripped) {
        let name = m.s(1);
        let open = m.end(0) - 1;
        let Some(close) = matching_paren(stripped, open) else {
            continue;
        };
        let body = &stripped[open + 1..close];
        work(&mut admit,||body.len().checked_mul(128).and_then(|n|n.checked_add(8192)),overflow)?;
        let line = line_of(m.start(1));
        let args = split_args(body);
        if OP_KEY_CALLS.contains(&name) {
            for a in &args {
                if let Some(s) = a.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
                    // `[x]` interpolation makes it a runtime value, not a key.
                    if !s.is_empty() && !s.contains('[') && !s.contains(' ') {
                        work(&mut admit,||s.len().checked_add(name.len()).and_then(|n|n.checked_add(rel.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)),overflow)?;
                        key(KeyRef {
                            kind: KeyKind::Op,
                            key: s.to_string(),
                            call: name.to_string(),
                            rel: rel.to_string(),
                            line,
                        })?;
                    }
                }
            }
        }
        if CAP_KEY_CALLS.contains(&name) {
            if let Some(s) = args
                .first()
                .and_then(|a| a.strip_prefix('"'))
                .and_then(|s| s.strip_suffix('"'))
            {
                if !s.is_empty() && !s.contains('[') {
                    work(&mut admit,||s.len().checked_add(name.len()).and_then(|n|n.checked_add(rel.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)),overflow)?;
                    key(KeyRef {
                        kind: KeyKind::Capability,
                        key: s.to_string(),
                        call: name.to_string(),
                        rel: rel.to_string(),
                        line,
                    })?;
                }
            }
        }
        if SOURCE_CALLS.contains(&name) {
            for a in &args {
                let compact = a.replace(' ', "");
                if let Some(v) = compact.strip_prefix("source=") {
                    if v == "null" || v.starts_with('"') {
                        work(&mut admit,||v.len().checked_add(rel.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)),overflow)?;
                        bad_source((rel.to_string(), line, v.to_string()))?;
                    }
                }
            }
        }
    }
    Ok(())
}

/// Original entries()/raw-define projections in file order. These are unique
/// declaration-policy facts, not a general type/procedure model.
pub fn visit_headers(stripped:&str,mut entry:impl FnMut(&str,&str),mut define:impl FnMut(&str)){
    let complete:Result<(),()>=visit_headers_with(stripped,|owner,name|{entry(owner,name);Ok(())},|name|{define(name);Ok(())},None,&||());
    debug_assert!(complete.is_ok());
}
/// As above, false is operational incompleteness, never an empty clean result.
pub fn visit_headers_checked(stripped:&str,mut entry:impl FnMut(&str,&str),mut define:impl FnMut(&str),mut admit:impl FnMut(usize)->bool)->bool{
    visit_headers_with(stripped,|owner,name|{entry(owner,name);Ok(())},|name|{define(name);Ok(())},Some(&mut|n|if admit(n){Ok(())}else{Err(())}),&||()).is_ok()
}
pub fn visit_headers_admitted<E>(stripped:&str,mut entry:impl FnMut(&str,&str),mut define:impl FnMut(&str),mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E)->Result<(),E>{
    visit_headers_with(stripped,|owner,name|{entry(owner,name);Ok(())},|name|{define(name);Ok(())},Some(&mut admit),&overflow)
}
/// SAME original header projection with typed callback failure propagation.
pub(crate) fn visit_headers_try_admitted<E>(stripped:&str,entry:impl FnMut(&str,&str)->Result<(),E>,define:impl FnMut(&str)->Result<(),E>,mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E)->Result<(),E>{
 visit_headers_with(stripped,entry,define,Some(&mut admit),&overflow)
}
fn entry_header_pattern()->&'static crate::pat::Pat{crate::pat_match!(r"^(/datum/[\w/]+)/entries\(\)")}
fn entry_op_pattern()->&'static crate::pat::Pat{crate::pat!(r#"(?<![\w./])op\(\s*"([^"]+)""#)}
fn define_pattern()->&'static crate::pat::Pat{crate::pat_match!(r"\s*define\s+(\w+)")}
fn visit_headers_with<E>(stripped:&str,mut entry:impl FnMut(&str,&str)->Result<(),E>,mut define:impl FnMut(&str)->Result<(),E>,mut admit:Option<&mut dyn FnMut(usize)->Result<(),E>>,overflow:&dyn Fn()->E)->Result<(),E> {
 visit_headers_patterns(stripped,entry,define,admit,overflow,entry_header_pattern(),entry_op_pattern(),define_pattern())
}
fn visit_headers_patterns<E,P:PatternApi>(stripped:&str,mut entry:impl FnMut(&str,&str)->Result<(),E>,mut define:impl FnMut(&str)->Result<(),E>,mut admit:Option<&mut dyn FnMut(usize)->Result<(),E>>,overflow:&dyn Fn()->E,header:&P,op:&P,definition:&P)->Result<(),E> {
    work(&mut admit,||header.capture_group_count().max(op.capture_group_count()).max(definition.capture_group_count()).checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>()).and_then(|n|n.checked_add(128)),overflow)?;
    let mut entries_of:Option<String>=None;
    for line in stripped.split('\n'){
        work(&mut admit,||line.len().checked_mul(8).and_then(|n|n.checked_add(1024)),overflow)?;
        let t=line.trim_start();
        if !line.is_empty() && !line.starts_with(|c:char|c.is_whitespace()){
            entries_of=header
                .captures(line).map(|m|m.s(1).to_string());
        }else if let Some(ty)=&entries_of{
            for m in op.captures_iter(line){
                work(&mut admit,||ty.len().checked_add(m.s(1).len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)),overflow)?;entry(ty,m.s(1))?;
            }
        }
        if let Some(rest)=t.strip_prefix('#'){
            if let Some(m)=definition.captures(rest){
                work(&mut admit,||m.s(1).len().checked_mul(8).and_then(|n|n.checked_add(1024)),overflow)?;define(m.s(1))?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
#[path="raw_key_visitors_tests.rs"]mod tests;

/// Same original call/header algorithms under the operation's actual pattern loan.
/// The caller must return the Fixture's first error before the pending semantic result.
pub(crate) fn visit_calls_with_fixture<E>(rel:&str,stripped:&str,starts:&[u32],key:impl FnMut(KeyRef)->Result<(),E>,bad_source:impl FnMut((String,u32,String))->Result<(),E>,mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E,fixture:&Fixture<'_>)->Result<(),E>{
 let pattern=fixture.pattern(CALLS_SOURCE,PatternMode::Search,calls_pattern);
 visit_calls_pattern(rel,stripped,starts,key,bad_source,Some(&mut admit),&overflow,&pattern)
}
pub(crate) fn visit_headers_with_fixture<E>(stripped:&str,entry:impl FnMut(&str,&str)->Result<(),E>,define:impl FnMut(&str)->Result<(),E>,mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E,fixture:&Fixture<'_>)->Result<(),E>{
 let header=fixture.pattern(ENTRY_HEADER_SOURCE,PatternMode::Match,entry_header_pattern);
 let op=fixture.pattern(ENTRY_OP_SOURCE,PatternMode::Search,entry_op_pattern);
 let definition=fixture.pattern(DEFINE_SOURCE,PatternMode::Match,define_pattern);
 visit_headers_patterns(stripped,entry,define,Some(&mut admit),&overflow,&header,&op,&definition)
}
