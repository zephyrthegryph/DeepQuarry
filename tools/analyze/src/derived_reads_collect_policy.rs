//! Unique derived-read lexical policies; adapters lend original raw data only.
use crate::{key_policy_control as kc,pat,util::py_lstrip};
pub(crate) fn proc_kind(name: &str) -> Option<&'static str> {
    match name {
        "should_run" => Some("runs"),
        "draw" | "hidden_verbs" => Some("drawn"),
        "tgui_data" | "ui_data" => Some("ui"),
        "push_to_rust" => Some("push"),
        _ => None,
    }
}


fn path_prefixes(path: &str) -> Vec<String> {
    let segs: Vec<&str> = path.trim_matches('/').split('/').collect();
    (1..=segs.len()).map(|i| format!("/{}", segs[..i].join("/"))).collect()
}

/// `state_schema_lint.chain`: the type and its ancestors, root first, with DM's implicit parents.
pub(crate) fn chain(path: &str) -> Vec<String> {
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


pub(crate) fn derive_value(name: &str) -> Option<&str> {
    name.strip_prefix("derive_").filter(|v| !v.is_empty())
}


pub(crate) fn paren_args(text: &str, open: usize) -> (&str, usize) {
    let b = text.as_bytes();
    let mut depth = 0i32;
    for i in open..b.len() {
        if b[i] == b'(' {
            depth += 1;
        } else if b[i] == b')' {
            depth -= 1;
            if depth == 0 {
                return (&text[open + 1..i], i + 1);
            }
        }
    }
    (&text[open + 1..], text.len())
}


fn reaction_kind_flag(call: &str) -> &'static str {
    match call {
        "every" => "RXB_EVERY",
        "on_cross" => "RXB_CROSS",
        "on_notice" => "RXB_NOTICE",
        _ => unreachable!("reaction kind {call}"),
    }
}


pub(crate) fn called_names<'a,C:kc::Control>(lines:impl IntoIterator<Item=(usize,&'a str)>,control:&mut C)->Result<Vec<String>,C::Error>{let mut out=Vec::new();for(_,line)in lines{control.checkpoint()?;let text=py_lstrip(line);if text.starts_with('#'){continue}crate::reactive_dependency_policy::captures(pat!(r"(?<![\w.:/])(?:src\.)?([A-Za-z_]\w*)\s*\("),text,control,|control,matched|{let name=matched.s(1);if !out.iter().any(|existing:&String|existing==name){crate::reactive_dependency_fold::row(control,&mut out)?;out.push(kc::own(control,name)?);}Ok(())})?;}control.checkpoint()?;Ok(out)}
pub(crate) fn boot_declarations<'a,C:kc::Control>(owner:&str,lines:impl IntoIterator<Item=(usize,&'a str)>,flags:&mut std::collections::BTreeMap<String,std::collections::BTreeSet<&'static str>>,members:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{let mut body=String::new();let mut first=true;for(_,line)in lines{control.checkpoint()?;if crate::util::py_strip(line).is_empty(){continue}if !first{kc::reserve(control,||Some(1))?;body.push('\n');}first=false;kc::reserve(control,||line.len().checked_mul(4).and_then(|n|n.checked_add(64)))?;body.push_str(line);}let mut pos=0;loop{control.checkpoint()?;let pattern=pat!(r"(?<![\w.])(every|on_cross|on_notice)\s*\(");kc::reserve(control,||pattern.capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;let Some(m)=pattern.captures_at(&body,pos)else{break};let(inner,end)=paren_args(&body,m.end(0)-1);pos=end;kc::reserve(control,||owner.len().checked_mul(4)?.checked_add(1024))?;flags.entry(kc::own(control,owner)?).or_default().insert(reaction_kind_flag(m.s(1)));if m.s(1)=="every"{let pattern=pat!(r"\bmembers\s*=\s*(/[\w/]+)");kc::reserve(control,||pattern.capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;if let Some(found)=pattern.captures(inner){kc::reserve(control,||Some(512))?;members.insert(kc::own(control,found.s(1))?);}}}control.checkpoint()}
