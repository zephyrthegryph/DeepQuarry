//! Original key/source call policy over a borrowed, comment-stripped raw view.
//! A declaration DSL policy only; no type/procedure tree or semantic parser.
use crate::keys_old_marker::{matching_paren,split_args};
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


pub fn visit_calls(rel:&str,stripped:&str,starts:&[u32],key:impl FnMut(KeyRef),bad_source:impl FnMut((String,u32,String))){
    let complete:Result<(),()>=visit_calls_with(rel,stripped,starts,key,bad_source,None,&||());
    debug_assert!(complete.is_ok());
}
/// A native producer must discard all callback rows if admission returns false.
/// Reservation runs BEFORE argument splitting and owned callback strings.
pub fn visit_calls_checked(rel:&str,stripped:&str,starts:&[u32],key:impl FnMut(KeyRef),bad_source:impl FnMut((String,u32,String)),mut admit:impl FnMut(usize)->bool)->bool{
    visit_calls_with(rel,stripped,starts,key,bad_source,Some(&mut|n|if admit(n){Ok(())}else{Err(())}),&||()).is_ok()
}
fn work<E>(admit:&mut Option<&mut dyn FnMut(usize)->Result<(),E>>,bytes:impl FnOnce()->Option<usize>,overflow:&dyn Fn()->E)->Result<(),E>{
    match admit.as_mut(){None=>Ok(()),Some(admit)=>admit(bytes().ok_or_else(overflow)?)}
}
/// Typed resource/control boundary over the SAME original callback algorithm.
/// Arithmetic overflow is a typed resource failure, never source meaning.
pub fn visit_calls_admitted<E>(rel:&str,stripped:&str,starts:&[u32],key:impl FnMut(KeyRef),bad_source:impl FnMut((String,u32,String)),mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E)->Result<(),E>{
    visit_calls_with(rel,stripped,starts,key,bad_source,Some(&mut admit),&overflow)
}
fn visit_calls_with<E>(rel:&str,stripped:&str,starts:&[u32],mut key:impl FnMut(KeyRef),mut bad_source:impl FnMut((String,u32,String)),mut admit:Option<&mut dyn FnMut(usize)->Result<(),E>>,overflow:&dyn Fn()->E)->Result<(),E> {
    static RE: std::sync::LazyLock<crate::pat::Pat> = std::sync::LazyLock::new(|| {
        crate::pat::Pat::new(
            r"(?<![\w./])(extend|without|on_op|shares_effects|above|perform_op|e0_perform_op|configure|hold|hold_until|hold_override|grant|release|status_end)\s*\(",
        )
    });
    let line_of = |off: usize| -> u32 {
        match starts.binary_search(&(off as u32)) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    };
    for m in RE.captures_iter(stripped) {
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
                        });
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
                    });
                }
            }
        }
        if SOURCE_CALLS.contains(&name) {
            for a in &args {
                let compact = a.replace(' ', "");
                if let Some(v) = compact.strip_prefix("source=") {
                    if v == "null" || v.starts_with('"') {
                        work(&mut admit,||v.len().checked_add(rel.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)),overflow)?;
                        bad_source((rel.to_string(), line, v.to_string()));
                    }
                }
            }
        }
    }
    Ok(())
}

/// Original entries()/raw-define projections in file order. These are unique
/// declaration-policy facts, not a general type/procedure model.
pub fn visit_headers(stripped:&str,entry:impl FnMut(&str,&str),define:impl FnMut(&str)){
    let complete:Result<(),()>=visit_headers_with(stripped,entry,define,None,&||());
    debug_assert!(complete.is_ok());
}
/// As above, false is operational incompleteness, never an empty clean result.
pub fn visit_headers_checked(stripped:&str,entry:impl FnMut(&str,&str),define:impl FnMut(&str),mut admit:impl FnMut(usize)->bool)->bool{
    visit_headers_with(stripped,entry,define,Some(&mut|n|if admit(n){Ok(())}else{Err(())}),&||()).is_ok()
}
pub fn visit_headers_admitted<E>(stripped:&str,entry:impl FnMut(&str,&str),define:impl FnMut(&str),mut admit:impl FnMut(usize)->Result<(),E>,overflow:impl Fn()->E)->Result<(),E>{
    visit_headers_with(stripped,entry,define,Some(&mut admit),&overflow)
}
fn visit_headers_with<E>(stripped:&str,mut entry:impl FnMut(&str,&str),mut define:impl FnMut(&str),mut admit:Option<&mut dyn FnMut(usize)->Result<(),E>>,overflow:&dyn Fn()->E)->Result<(),E> {
    let mut entries_of:Option<String>=None;
    for line in stripped.split('\n'){
        work(&mut admit,||line.len().checked_mul(8).and_then(|n|n.checked_add(1024)),overflow)?;
        let t=line.trim_start();
        if !line.is_empty() && !line.starts_with(|c:char|c.is_whitespace()){
            entries_of=crate::pat_match!(r"^(/datum/[\w/]+)/entries\(\)")
                .captures(line).map(|m|m.s(1).to_string());
        }else if let Some(ty)=&entries_of{
            for m in crate::pat!(r#"(?<![\w./])op\(\s*"([^"]+)""#).captures_iter(line){
                work(&mut admit,||ty.len().checked_add(m.s(1).len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)),overflow)?;entry(ty,m.s(1));
            }
        }
        if let Some(rest)=t.strip_prefix('#'){
            if let Some(m)=crate::pat_match!(r"\s*define\s+(\w+)").captures(rest){
                work(&mut admit,||m.s(1).len().checked_mul(8).and_then(|n|n.checked_add(1024)),overflow)?;define(m.s(1));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
#[path="raw_key_visitors_tests.rs"]mod tests;
