//! SAME declaration named-leaf and driven-var dependency policy.
use crate::{declare_policy::Marker,reactive_facts::Leaf,raw_marker_policy::matching_paren,key_policy_control as kc};
fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// `(keyword, open paren, close paren)` of each `contributes(`, `contributes_to(` and `when(` call in `body`.
fn stat_ranges<C:kc::Control>(body:&str,control:&mut C)->Result<Vec<(&'static str,usize,usize)>,C::Error>{
    let b = body.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        control.checkpoint()?;
        if b[i] == b'"' {
            in_str = !in_str;
            i += 1;
            continue;
        }
        if in_str || !(b[i].is_ascii_alphabetic() || b[i] == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_word(b[i]) {
            i += 1;
        }
        if start > 0 && (is_word(b[start - 1]) || b[start - 1] == b'.') {
            continue;
        }
        let kw: &'static str = match &body[start..i] {
            "contributes" => "contributes",
            "contributes_to" => "contributes_to",
            "factors" => "factors",
            "when" => "when",
            _ => continue,
        };
        let rest = &body[i..];
        let skip = rest.len() - rest.trim_start().len();
        if !rest.trim_start().starts_with('(') {
            continue;
        }
        let open = i + skip;
        if let Some(close) = matching_paren(body, open) {
            kc::row(control,&mut out)?;out.push((kw, open, close));
        }
    }
    control.checkpoint()?;Ok(out)
}

/// The stat-input leaves of one CAPABILITIES block.
pub fn marker_leaves<C:kc::Control>(m:&Marker<'_>,control:&mut C)->Result<Vec<Leaf>,C::Error>{
    let Some(owner) = m.args.first().filter(|o| o.starts_with('/')) else {control.checkpoint()?;return Ok(Vec::new())};
    let body = &m.body;
    let ranges = stat_ranges(body,control)?;
    let mut contributes=Vec::new();for range in ranges.iter().filter(|r|r.0!="when"){kc::row(control,&mut contributes)?;contributes.push((range.1,range.2));}
    let feeds_stat = |pos: usize| {
        ranges.iter().any(|&(kw, s, e)| {
            pos > s && pos < e && (kw != "when" || contributes.iter().any(|&(cs, _)| cs > s && cs < e))
        })
    };
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(at) = body[from..].find("nameof(") {
        control.checkpoint()?;
        let start = from + at;
        from = start + 7;
        if start > 0 && is_word(body.as_bytes()[start - 1]) {
            continue;
        }
        let Some(close) = matching_paren(body, start + 6) else { continue };
        let name = body[start + 7..close].trim();
        if name.is_empty() || !name.bytes().all(is_word) || !feeds_stat(start) {
            continue;
        }
        kc::row(control,&mut out)?;out.push(Leaf{owner:kc::own(control,owner)?,var:kc::own(control,name)?,rel:kc::own(control,m.rel)?,line:m.line_at(start)});
    }
    control.checkpoint()?;Ok(out)
}


pub fn marker_driven_vars<C:kc::Control>(m:&Marker<'_>,control:&mut C)->Result<Vec<String>,C::Error>{
    let mut out = Vec::new();
    crate::reactive_dependency_policy::captures(crate::pat!(r"\binto\s*=\s*nameof\(\s*(\w+)\s*\)"),&m.body,control,|control,c|{
        control.checkpoint()?;kc::row(control,&mut out)?;out.push(kc::own(control,c.s(1))?);Ok(())
    })?;
    crate::reactive_dependency_policy::captures(crate::pat!(r"\btoggles\(\s*nameof\(\s*(\w+)\s*\)"),&m.body,control,|control,c|{
        control.checkpoint()?;kc::row(control,&mut out)?;out.push(kc::own(control,c.s(1))?);Ok(())
    })?;
    control.checkpoint()?;Ok(out)
}
