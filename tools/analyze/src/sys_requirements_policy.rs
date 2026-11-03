//! Unique original inline-refusal lexical effects, merge and judge; no source authority.
use std::collections::{BTreeMap,BTreeSet};
use crate::{incr,tree::{SourceFile,Tree},util::{is_py_space,py_rstrip,py_strip},pat,pat_match,pat::Pat,key_policy_control::Control};
fn decl_re() -> &'static Pat {
    pat!(r"\b(?:DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\(\s*(/[\w/]+)")
}

fn message_re() -> &'static Pat {
    pat!(r"\b(?:to_chat|balloon_alert|visible_message|audible_message|show_message|balloon_alert_to_viewers)\s*\(")
}

fn quiet_re() -> &'static Pat {
    pat_match!(r"^(?:playsound|SEND_SOUND)\s*\(")
}

fn return_re() -> &'static Pat {
    pat_match!(r"^return\b")
}

fn acting_re() -> &'static Pat {
    pat!(
        r"\b(?:drop_from_inventory|unEquip|drop_item|drop_held_item|put_in_\w+|remove_from_mob|use|use_charge|checked_use|use_tool|do_after|do_mob|tgui_\w+|input|alert|forceMove|try_\w+|attempt_\w+|consume\w*|transfer\w*|insert_item|user_unbuckle_mob|buckle_mob|Move|rerun_ask|om_ask|prob|rand|CLUMSY_FAIL_CHANCE|remove_fuel|use_resource|spend\w*|pay\w*|charge|om_task_timed)\s*\("
    )
}

/// Code part of a line: comments and string contents dropped (single quotes too), right-stripped.
fn strip(line: &str) -> String {
    let b = line.as_bytes();
    let mut out: Vec<u8> = Vec::new();
    let mut i = 0;
    let mut quote: Option<u8> = None;
    while i < b.len() {
        let c = b[i];
        if let Some(q) = quote {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == q {
                quote = None;
                out.push(c);
            }
            i += 1;
            continue;
        }
        if c == b'"' || c == b'\'' {
            quote = Some(c);
            out.push(c);
        } else if b[i..].starts_with(b"//") {
            break;
        } else {
            out.push(c);
        }
        i += 1;
    }
    let s = String::from_utf8_lossy(&out).into_owned();
    py_rstrip(&s).to_string()
}

fn related(a: &str, b: &str) -> bool {
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

/// proc name -> set of declaring types.
pub fn effects_of(f:&SourceFile)->Vec<(String,String)>{effects_of_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original requirements effects")}
pub fn effects_of_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T)->Result<Vec<(String,String)>,C::Error>{keep.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(256)?.checked_add(4096))?;
    let mut found: BTreeSet<(&str,&str)> = BTreeSet::new();
    {
        let mut decl: Option<&str> = None;
        let mut datum = false;
        for line in f.raw().lines() {
            keep.checkpoint()?;
            if let Some(m) = decl_re().captures(line) {
                decl = Some(m.s(1));
            }
            if let Some(d) = &decl {
                if pat!(r"\bINTERACT_[A-Z_]+\(").is_match(line) || decl_re().is_match(line) {
                    for r in pat!(r"\b(?:PROC_REF|TYPE_PROC_REF\([^,]*,)\s*\(?\s*(\w+)\s*\)|\.proc/(\w+)").captures_iter(line) {
                        keep.checkpoint()?;
                        let name = if r.matched(1) && !r.s(1).is_empty() { r.s(1) } else { r.s(2) };
                        if !found.contains(&(name,*d)){crate::key_policy_control::reserve(temp,||Some(2048))?;found.insert((name,*d));}
                    }
                }
            }
            if decl.is_some() && !py_rstrip(line).ends_with('\\') {
                decl = None;
            }
            if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) {
                datum = pat_match!(r"^(/datum/interaction[\w/]*)\s*$").is_match(line);
            }
            if datum {
                if let Some(m) = pat_match!(r"^\s+effect\s*=\s*(/[\w/]+?)/(?:proc/)?(\w+)\s*(?://.*)?$").captures(line) {
                    if !found.contains(&(m.s(2),m.s(1))){crate::key_policy_control::reserve(temp,||Some(2048))?;found.insert((m.s(2),m.s(1)));}
                }
            }
        }
    }
    let mut rows=Vec::new();for(name,ty)in found{keep.checkpoint()?;crate::raw_tree_report::row(keep,&mut rows)?;rows.push((crate::raw_tree_report::own(keep,name)?,crate::raw_tree_report::own(keep,ty)?));}keep.checkpoint()?;Ok(rows)
}

type Stmt = Vec<(usize, String, usize)>;

/// Top-level statements of a proc body: lists of (line_no, code, depth).
fn statements(body: &[(usize, &str)]) -> Vec<Stmt> {
    let mut stmts: Vec<Stmt> = Vec::new();
    for (no, raw) in body {
        let code = strip(raw);
        if py_strip(&code).is_empty() {
            continue;
        }
        let depth = code.chars().take_while(|c| *c == '\t').count();
        let item = (*no, py_strip(&code).to_string(), depth);
        if depth <= 1 || stmts.is_empty() {
            stmts.push(vec![item]);
        } else {
            stmts.last_mut().unwrap().push(item);
        }
    }
    stmts
}

/// TRUE when the statements only say no (a message, maybe a sound) and end in return.
fn only_refusal(parts: &[String]) -> bool {
    if parts.is_empty() || !return_re().is_match(&parts[parts.len() - 1]) {
        return false;
    }
    let mut told = false;
    for part in parts {
        if message_re().is_match(part) {
            told = true;
            if !pat_match!(
                r"^[\w.?\[\]]*\s*(?:to_chat|balloon_alert|visible_message|audible_message|show_message|balloon_alert_to_viewers)\s*\("
            )
            .is_match(part)
                && !return_re().is_match(part)
            {
                return false;
            }
        } else if return_re().is_match(part) {
            continue;
        } else if !quiet_re().is_match(part) {
            return false;
        }
    }
    told
}

fn split_parts(text: &str, parts: &mut Vec<String>) {
    for p in text.split(';') {
        let p = py_strip(p);
        if !p.is_empty() {
            parts.push(p.to_string());
        }
    }
}

/// The body of an `if` statement as simple statements, or None if it isn't a plain guard.
fn guard_parts(stmt: &Stmt) -> Option<(String, Vec<String>)> {
    let first = &stmt[0].1;
    let mut depth = 0i32;
    let mut found: Option<(String, String)> = None;
    for (i, c) in first.bytes().enumerate() {
        if c == b'(' {
            depth += 1;
        } else if c == b')' {
            depth -= 1;
            if depth == 0 {
                found = Some((first[..i + 1].to_string(), py_strip(&first[i + 1..]).to_string()));
                break;
            }
        }
    }
    let (cond, rest) = found?;
    let mut parts: Vec<String> = Vec::new();
    if !rest.is_empty() {
        let rest = rest.trim_matches(|c| c == '{' || c == '}' || c == ' ');
        split_parts(rest, &mut parts);
    }
    for (_, code, _) in &stmt[1..] {
        let code = code.trim_matches(|c| c == '{' || c == '}' || c == ' ');
        split_parts(code, &mut parts);
    }
    Some((cond, parts))
}

pub fn judge(f:&SourceFile,effects:&Effects)->Vec<(&'static str,String,usize)>{judge_using(f,effects,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original requirements judge")}
pub fn judge_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,effects:&Effects,keep:&mut C,temp:&mut T)->Result<Vec<(&'static str,String,usize)>,C::Error>{keep.checkpoint()?;let mut width=0usize;for types in effects.values(){for ty in types{keep.checkpoint()?;width=width.max(ty.len());}}crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(256)?.checked_add(width.checked_mul(8)?)?.checked_add(4096))?;
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    {
        let rel = f.rel.as_str();
        let lines = f.raw().lines_vec();
        for (idx, line) in lines.iter().enumerate() {
            keep.checkpoint()?;
            if pat!(r"\bREFUSE_IF\s*\(").is_match(&strip(line)) && !line.contains("#define") {
                crate::raw_tree_report::row(keep,&mut out)?;out.push(("inline_refusal",crate::raw_tree_report::own(keep,rel)?,idx+1));
            }
        }
        let n = lines.len();
        let mut i = 0;
        while i < n {
            keep.checkpoint()?;
            let line = lines[i];
            let Some(m) = pat_match!(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\s*\(").captures(line) else {
                i += 1;
                continue;
            };
            let Some(types) = effects.get(m.s(2)) else {
                i += 1;
                continue;
            };
            if !types.iter().any(|t| related(m.s(1), t)) {
                i += 1;
                continue;
            }
            let mut body: Vec<(usize, &str)> = Vec::new();
            let mut j = i + 1;
            while j < n && (lines[j].is_empty() || lines[j].chars().next().map(is_py_space).unwrap_or(false)) {
                keep.checkpoint()?;body.push((j + 1, lines[j]));
                j += 1;
            }
            let stmts = statements(&body);
            for (k, stmt) in stmts.iter().enumerate() {
                keep.checkpoint()?;
                let code = stmt[0].1.as_str();
                if code.starts_with("var/") && acting_re().is_match(code) {
                    break; // a local that asks the player or acts: what follows validates the outcome
                }
                if code.starts_with("var/") || code.starts_with("set ") || code.starts_with("SHOULD_") || code.starts_with("SIGNAL_HANDLER") {
                    continue;
                }
                if !pat_match!(r"^if\s*\(").is_match(code) {
                    break;
                }
                if k + 1 < stmts.len() && pat_match!(r"^else\b").is_match(&stmts[k + 1][0].1) {
                    break;
                }
                let Some((cond, parts)) = guard_parts(stmt) else { break };
                if acting_re().is_match(&cond) {
                    continue;
                }
                if parts.is_empty() || (!return_re().is_match(&parts[parts.len() - 1]) && !return_re().is_match(&parts[0])) {
                    break;
                }
                if only_refusal(&parts) || (parts.len() == 1 && return_re().is_match(&parts[0]) && message_re().is_match(&parts[0])) {
                    crate::raw_tree_report::row(keep,&mut out)?;out.push(("inline_refusal",crate::raw_tree_report::own(keep,rel)?,stmt[0].0));
                } else if !parts.iter().all(|p| return_re().is_match(p) || quiet_re().is_match(p)) {
                    // A branch that does work (another action of a multi-purpose effect) ends the head.
                    break;
                }
            }
            i = j;
        }
    }
    keep.checkpoint()?;Ok(out)
}

pub type Effects=BTreeMap<String,BTreeSet<String>>;
pub fn merge<'a,C:Control>(rows:impl IntoIterator<Item=&'a Vec<(String,String)>>,c:&mut C)->Result<Effects,C::Error>{let mut effects:Effects=BTreeMap::new();for pairs in rows{c.checkpoint()?;for(name,ty)in pairs{c.checkpoint()?;if !effects.contains_key(name){crate::key_policy_control::reserve(c,||Some(2048))?;effects.insert(crate::raw_tree_report::own(c,name)?,BTreeSet::new());}let types=effects.get_mut(name).expect("just admitted effect name");if !types.contains(ty){crate::key_policy_control::reserve(c,||Some(2048))?;types.insert(crate::raw_tree_report::own(c,ty)?);}}}c.checkpoint()?;Ok(effects)}
pub fn scan(tree:&Tree,files:&[&SourceFile])->Vec<(&'static str,String,usize)>{let _=tree;let fs=incr::facts("sys-requirements-facts",files,effects_of);let effects=merge(&fs,&mut crate::key_policy_control::Compatibility).expect("original requirements merge");let key=incr::ctx_key(&effects);let results=incr::keyed("sys-requirements-judge",key,files,|f|judge(f,&effects).into_iter().map(|(_,_,line)|line as u32).collect::<Vec<u32>>());let mut out=Vec::new();for(f,rows)in files.iter().zip(results){for line in rows{out.push(("inline_refusal",f.rel.clone(),line as usize));}}out}
