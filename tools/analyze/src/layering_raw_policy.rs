//! SAME original raw provenance events. No semantic/type existence is guessed here.
/// One line of a file as the layering index reads it (see `Sem::build_with`).
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug, PartialEq)]
pub enum Event {
    /// `/type/var/x`: the type owns a field (if the model has the type).
    Owner(String),
    /// A `CAPABILITY_TYPE` / `CAPABILITY_DEF` marker's type.
    Type(String),
    /// A non-empty line's indent (pops the header stack).
    Indent(u32),
    /// A bare type header at an indent.
    Header(u32, String),
}

pub fn events(code:&str,capability_type:&regex::Regex,capability_def:&regex::Regex)->Vec<Event>{events_using(code,capability_type,capability_def,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
pub fn events_using<C:crate::key_policy_control::Control>(code:&str,capability_type:&regex::Regex,capability_def:&regex::Regex,c:&mut C)->Result<Vec<Event>,C::Error>{
    let mut out = Vec::new();
    let mut headers: Vec<usize> = Vec::new();
    for raw in code.lines() {c.checkpoint()?;
        let text = raw.trim();
        if text.is_empty() { continue; }
        // An uninitialized absolute field declaration can carry no
        // useful value/declaration location in ObjectTree. Its explicit
        // owner is still an actual definition, not a typed reference.
        let declaration = text.split_whitespace().next().unwrap_or("");
        if declaration.starts_with('/') {
            if let Some((owner, member)) = declaration.split_once("/var/") {
                if !member.is_empty() {
                    crate::key_policy_control::row(c,&mut out)?;out.push(Event::Owner(crate::key_policy_control::own(c,owner)?));
                }
            }
        }
        if let Some(cap) = capability_type.captures(text) {
            crate::key_policy_control::row(c,&mut out)?;out.push(Event::Type(crate::key_policy_control::own(c,&cap[1])?));
        }
        if let Some(cap) = capability_def.captures(text) {
            crate::key_policy_control::row(c,&mut out)?;out.push(Event::Type(crate::key_policy_control::format(c,format_args!("/datum/capability/def/{}",&cap[1]))?));
        }
        let indent = raw.len() - raw.trim_start().len();
        // An indent can only pop a header stack entry at or past it: kept only while some earlier header could be on the stack.
        if headers.last().is_some_and(|n| *n >= indent) {
            while headers.last().is_some_and(|n| *n >= indent) { headers.pop(); }
            crate::key_policy_control::row(c,&mut out)?;out.push(Event::Indent(indent as u32));
        }
        // A bare type header is a definition. Typed arguments, locals,
        // member declarations and proc definitions are only references.
        let header = text.trim_end_matches('{').trim();
        let mut valid=!header.is_empty();for ch in header.chars(){c.checkpoint()?;if !(ch.is_ascii_alphanumeric()||ch=='_'||ch=='/'){valid=false;break}}
        if valid {
            crate::key_policy_control::row(c,&mut out)?;out.push(Event::Header(indent as u32,crate::key_policy_control::own(c,header)?));
            crate::key_policy_control::row(c,&mut headers)?;headers.push(indent);
        }
    }
    Ok(out)
}
