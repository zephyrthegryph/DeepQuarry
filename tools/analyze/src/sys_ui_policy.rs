//! Unique original lexical UI declaration/params-helper/judgment policy.
//! No compiler model or source/EOF authority lives here.
use std::collections::{BTreeMap,BTreeSet};
use serde::{Deserialize,Serialize};
#[cfg(feature="legacy-sem")]use crate::{incr,tree::Tree};
use crate::{pat,pat_match,pat::Pat,tree::SourceFile,util::{is_py_space,py_strip},key_policy_control::Control};
use crate::allow_registry_fields::sys_ui::RULES;
/// Where windows are legitimately built by hand: the tgui core and the declared-UI runtime.
const OPEN_EXEMPT: &[&str] =
    &["code/modules/tgui/", "code/modules/tgui_input/", "code/controllers/subsystems/tgui.dm", "code/datums/sys/ui.dm"];

/// The vendored TGS DMAPI: its `params` are world.Topic query strings, never a tgui message.
const NOT_TGUI: &[&str] = &["code/modules/tgs/"];

fn starts_any(rel: &str, prefixes: &[&str]) -> bool {
    prefixes.iter().any(|p| rel.starts_with(p))
}

/// (callee, top-level argument text with nested calls blanked) for every call in `code`, nested
/// calls included. A nested call's `(` and contents drop out, its closing `)` stays (quirk).
fn calls_of<C:Control>(code:&str,control:&mut C)->Result<Vec<(String,String)>,C::Error>{
    control.checkpoint()?;
    let b = code.as_bytes();
    let mut out = Vec::new();
    for c in pat!(r"\b(\w+)\s*\(").captures_iter(code) {
        control.checkpoint()?;
        let callee = c.s(1).to_string();
        let mut depth = 1i32;
        let mut i = c.end(0);
        let mut buf: Vec<u8> = Vec::new();
        while i < b.len() && depth != 0 {
            control.checkpoint()?;
            let ch = b[i];
            if ch == b'(' {
                depth += 1;
            } else if ch == b')' {
                depth -= 1;
                if depth == 0 {
                    break;
                }
            }
            if depth == 1 {
                buf.push(ch);
            }
            i += 1;
        }
        out.push((callee, String::from_utf8_lossy(&buf).into_owned()));
    }
    control.checkpoint()?;Ok(out)
}

/// The line without its `//` comment and with string literal contents blanked.
fn code_of<C:Control>(line:&str,control:&mut C)->Result<String,C::Error>{
    control.checkpoint()?;
    let b = line.as_bytes();
    let mut out: Vec<u8> = Vec::new();
    let mut quote = false;
    let mut i = 0;
    while i < b.len() {
        control.checkpoint()?;
        let c = b[i];
        if quote {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == b'"' {
                quote = false;
                out.push(c);
            }
        } else {
            if b[i..].starts_with(b"//") {
                break;
            }
            out.push(c);
            if c == b'"' {
                quote = true;
            }
        }
        i += 1;
    }
    control.checkpoint()?;Ok(String::from_utf8_lossy(&out).into_owned())
}

/// The line without its `//` comment (strings kept).
fn strip_comment<'a,C:Control>(line:&'a str,control:&mut C)->Result<&'a str,C::Error>{
    control.checkpoint()?;
    let b = line.as_bytes();
    let mut quote = false;
    let mut i = 0;
    while i < b.len() {
        control.checkpoint()?;
        let c = b[i];
        if quote {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == b'"' {
                quote = false;
            }
        } else if c == b'"' {
            quote = true;
        } else if b[i..].starts_with(b"//") {
            return Ok(&line[..i]);
        }
        i += 1;
    }
    control.checkpoint()?;Ok(line)
}

#[derive(PartialEq)]
enum Kind {
    Handler,
    Proc,
}

struct Body<'a> {
    kind: Kind,
    owner: String,
    name: String,
    args: String,
    start: usize,
    body: Vec<(usize, &'a str)>,
}

fn bodies<'a,C:Control>(lines:&[&'a str],control:&mut C)->Result<Vec<Body<'a>>,C::Error>{
    control.checkpoint()?;
    let mut out = Vec::new();
    let n = lines.len();
    let mut i = 0;
    while i < n {
        control.checkpoint()?;
        let line = lines[i];
        let kind;
        let (owner, name, args);
        if let Some(c) = pat_match!(r"UI_(?:ACT|SUBACT)_(?:PROC|OVERRIDE|PREF_PROC)\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)").captures(line) {
            kind = Kind::Handler;
            owner = c.s(1).to_string();
            name = c.s(2).to_string();
            args = String::new();
        } else if let Some(c) = pat_match!(r"(/[\w/]+?)/(?:proc/)?(\w+)\s*\(([^)]*)\)").captures(line) {
            kind = Kind::Proc;
            owner = c.s(1).to_string();
            name = c.s(2).to_string();
            args = c.s(3).to_string();
        } else {
            i += 1;
            continue;
        }
        let mut j = i + 1;
        let mut body = Vec::new();
        while j < n && (py_strip(lines[j]).is_empty() || matches!(lines[j].as_bytes()[0], b'\t' | b' ')) {
            control.checkpoint()?;
            body.push((j + 1, lines[j]));
            j += 1;
        }
        out.push(Body { kind, owner, name, args, start: i + 1, body });
        i = j;
    }
    control.checkpoint()?;Ok(out)
}

fn arg_names<C:Control>(text:&str,control:&mut C)->Result<Vec<String>,C::Error>{let mut out=Vec::new();for c in pat!(r#"UI_ARG_\w+\(\s*"([^"]+)""#).captures_iter(text){control.checkpoint()?;out.push(c.s(1).to_string());}control.checkpoint()?;Ok(out)}

/// One file's UI_ACT rows: `(type, handler, declared arg names)`, sorted by `(type, handler)`.
fn declared_rows_of<C:Control>(f:&SourceFile,control:&mut C)->Result<Vec<(String,String,BTreeSet<String>)>,C::Error>{
    control.checkpoint()?;
    let mut rows: BTreeMap<(String, String), BTreeSet<String>> = BTreeMap::new();
    for line in f.raw().lines() {
        control.checkpoint()?;
        let m = pat_match!(r#"UI_SUBACT\(\s*(/[\w/]+)\s*,\s*"[^"]*"\s*,\s*[^,]+,\s*(\w+)\s*(.*)\)\s*$"#)
            .captures(line)
            .or_else(|| {
                pat_match!(r#"UI_(?:ACT|SUBACT)\(\s*(/[\w/]+)\s*,(?:\s*"[^"]*"\s*,(?=\s*"))?\s*[^,]+,\s*(\w+)\s*(.*)\)\s*$"#).captures(line)
            });
        if let Some(m) = m {
            rows.entry((m.s(1).to_string(), m.s(2).to_string())).or_default().extend(arg_names(m.s(3),control)?);
        } else if line.starts_with("#define") && line.contains("TYPE_PROC_REF(/datum,") {
            // Row-generating macros (DECLARE_UI_MODAL): their handlers live on /datum.
            for part in line.split("TYPE_PROC_REF(/datum,").skip(1) {
                control.checkpoint()?;
                let handler = py_strip(part.split(')').next().unwrap_or(""));
                rows.entry(("/datum".to_string(), handler.to_string())).or_default().extend(arg_names(part,control)?);
            }
        }
    }
    control.checkpoint()?;Ok(rows.into_iter().map(|((t,h),k)|(t,h,k)).collect())
}

type ByHandler = BTreeMap<String, Vec<(String, BTreeSet<String>)>>;

/// `(type, handler) -> declared arg names`, from every UI_ACT row; indexed by handler here.
fn declared_keys<C:Control>(per_file:&[&Vec<DeclRow>],control:&mut C)->Result<ByHandler,C::Error>{
    control.checkpoint()?;
    let mut rows: BTreeMap<(String, String), BTreeSet<String>> = BTreeMap::new();
    for rs in per_file {
        control.checkpoint()?;
        for (t, h, k) in rs.iter() {
            control.checkpoint()?;
            rows.entry((t.clone(), h.clone())).or_default().extend(k.iter().cloned());
        }
    }
    let mut by_handler: ByHandler = BTreeMap::new();
    for ((ty, handler), keys) in rows {
        control.checkpoint()?;
        by_handler.entry(handler).or_default().push((ty, keys));
    }
    control.checkpoint()?;Ok(by_handler)
}

fn keys_for<C:Control>(rows:&ByHandler,owner:&str,handler:&str,control:&mut C)->Result<BTreeSet<String>,C::Error>{
    control.checkpoint()?;
    let mut out = BTreeSet::new();
    if let Some(list) = rows.get(handler) {
        for (row_type, keys) in list {
            control.checkpoint()?;
            if row_type == owner || owner.starts_with(&format!("{}/", row_type)) || row_type.starts_with(&format!("{}/", owner)) {
                out.extend(keys.iter().cloned());
            }
        }
    }
    control.checkpoint()?;Ok(out)
}

fn count(p: &Pat, text: &str) -> usize {
    p.find_iter(text).len()
}

/// Procs taking `list/params` that may receive a handler's typed params: name -> keys it reads
/// (itself and the helpers it calls).
fn helper_cands_of<C:Control>(f:&SourceFile,control:&mut C)->Result<Vec<Cand>,C::Error>{
    control.checkpoint()?;
    let passthrough = ["act_ask", "om_act_ask", "rerun_ask", "list"];
    let mut out: Vec<Cand> = Vec::new();
    {
        let lines = f.raw().lines_vec();
        for b in bodies(&lines,control)? {
            control.checkpoint()?;
            if b.kind != Kind::Proc || !pat!(r"(?:^|,)\s*(?:list/)?params\s*(?:,|$)").is_match(&b.args) {
                continue;
            }
            let mut keys = BTreeSet::new();
            let mut callees = BTreeSet::new();
            let mut ok = true;
            for (_n, line) in &b.body {
                control.checkpoint()?;
                let text = strip_comment(line,control)?;
                if !pat!(r"\bparams\b").is_match(text) {
                    continue;
                }
                if raw_re().is_match(text) || dynamic_re().is_match(text) {
                    ok = false;
                    break;
                }
                for c in keyread_re().captures_iter(text) {
                    control.checkpoint()?;
                    keys.insert(c.s(1).to_string());
                }
                let rest = code_of(&keyread_re().replace_all(text, ""),control)?;
                let total = count(pat!(r"\bparams\b"), &rest);
                let mut covered = 0;
                for (callee, argtext) in calls_of(&rest,control)? {
                    control.checkpoint()?;
                    let hits = count(pat!(r"(?:^|,)\s*params\s*(?=,|$)"), &argtext);
                    if hits == 0 {
                        continue;
                    }
                    covered += hits;
                    if !passthrough.contains(&callee.as_str()) {
                        callees.insert(callee);
                    }
                }
                if covered != total {
                    ok = false;
                    break;
                }
            }
            if ok {
                out.push((b.name.clone(), keys, callees));
            }
        }
    }
    control.checkpoint()?;Ok(out)
}

/// One proc taking `params`: name, keys it reads, helpers it forwards to.
type Cand = (String, BTreeSet<String>, BTreeSet<String>);
type DeclRow = (String, String, BTreeSet<String>);

fn typed_param_helpers<C:Control>(per_file:&[&Vec<Cand>],control:&mut C)->Result<BTreeMap<String,BTreeSet<String>>,C::Error>{
    control.checkpoint()?;
    let mut cands: BTreeMap<String, (BTreeSet<String>, BTreeSet<String>)> = BTreeMap::new();
    for cs in per_file {
        control.checkpoint()?;
        for (name, keys, callees) in cs.iter() {
            control.checkpoint()?;
            cands.insert(name.clone(), (keys.clone(), callees.clone()));
        }
    }
    let mut changed = true;
    while changed {
        control.checkpoint()?;
        changed = false;
        let names: Vec<String> = cands.keys().cloned().collect();
        for name in names {
            control.checkpoint()?;
            let drop = cands.get(&name).map(|(_, callees)| callees.iter().any(|c| !cands.contains_key(c))).unwrap_or(false);
            if drop {
                cands.remove(&name);
                changed = true;
            }
        }
    }
    let mut out = BTreeMap::new();
    for name in cands.keys() {
        control.checkpoint()?;
        let mut seen: BTreeSet<String> = BTreeSet::new();
        let mut todo = vec![name.clone()];
        let mut keys = BTreeSet::new();
        while let Some(n) = todo.pop() {
            control.checkpoint()?;
            if !seen.insert(n.clone()) {
                continue;
            }
            let (k, callees) = &cands[&n];
            keys.extend(k.iter().cloned());
            todo.extend(callees.iter().cloned());
        }
        out.insert(name.clone(), keys);
    }
    control.checkpoint()?;Ok(out)
}

fn raw_re() -> &'static Pat {
    pat!(
        r"\b(?:text2num|locate|text2path|json_decode|params2list)\s*\(\s*params\s*\??\[|\blocate_in_list\s*\([^;]*,\s*params\s*\??\[|\blocate_within\s*\([^;]*,\s*params\s*\??\["
    )
}

fn dynamic_re() -> &'static Pat {
    pat!(r#"\bparams\s*\??\[\s*(?!")"#)
}

fn keyread_re() -> &'static Pat {
    pat!(r#"\bparams\s*\??\[\s*"([^"]+)"\s*\]"#)
}

fn judge<C:Control>(f:&SourceFile,rows:&ByHandler,helpers:&BTreeMap<String,BTreeSet<String>>,control:&mut C)->Result<Vec<(&'static str,String,usize)>,C::Error>{
    control.checkpoint()?;
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    {
        let rel = f.rel.as_str();
        if starts_any(rel, NOT_TGUI) {
            return Ok(out);
        }
        let exempt_open = starts_any(rel, OPEN_EXEMPT);
        let lines = f.raw().lines_vec();
        for (idx, line) in lines.iter().enumerate() {
            control.checkpoint()?;
            let number = idx + 1;
            let code = code_of(line,control)?;
            if pat_match!(r"/[\w/]+?/(?:proc/)?tgui_data\s*\(").is_match(line) && !line.starts_with("/datum/proc/tgui_data(") {
                out.push(("tgui_data_override", rel.to_string(), number));
            }
            if pat_match!(r"(/[\w/]+?)/(?:proc/)?tgui_state\s*\(").is_match(line) && !line.starts_with("/datum/proc/tgui_state(") {
                let mut body: Vec<String> = Vec::new();
                for follow in &lines[number..] {
                    control.checkpoint()?;
                    if !py_strip(follow).is_empty() && !follow.chars().next().map(is_py_space).unwrap_or(false) {
                        break;
                    }
                    let c = code_of(follow,control)?;
                    if !py_strip(&c).is_empty() {
                        body.push(c.trim_end_matches(is_py_space).to_string());
                    }
                }
                if body.len() == 1 && pat_match!(r"\treturn\s+(GLOB\.\w+|ADMIN_STATE\([^)]*\))\s*$").is_match(&body[0]) {
                    out.push(("tgui_state_override", rel.to_string(), number));
                }
            }
            if pat_match!(r"/[\w/]+?/(?:proc/)?tgui_interact\s*\(").is_match(line) && !line.starts_with("/datum/proc/tgui_interact(") {
                out.push(("tgui_interact_boilerplate", rel.to_string(), number));
            } else if !exempt_open
                && pat!(r"\bSStgui\.try_update_ui\s*\(|\bnew\s*/datum/tgui\s*\(|\bui\s*=\s*new\s*\(|var/datum/tgui/\w+\s*=\s*new\s*\(").is_match(&code)
            {
                out.push(("tgui_interact_boilerplate", rel.to_string(), number));
            }
            if raw_re().is_match(strip_comment(line,control)?) {
                out.push(("text2num_params", rel.to_string(), number));
            }
        }
        for b in bodies(&lines,control)? {
            control.checkpoint()?;
            if b.kind == Kind::Proc && b.name == "tgui_act" && b.owner != "/datum" {
                out.push(("ui_act_dispatch", rel.to_string(), b.start));
                for (number, line) in &b.body {
                    control.checkpoint()?;
                    let text = strip_comment(line,control)?;
                    if pat!(r"\bparams\s*\??\[").is_match(text) && !raw_re().is_match(text) {
                        out.push(("text2num_params", rel.to_string(), *number));
                    }
                }
                continue;
            }
            if b.kind != Kind::Handler {
                continue;
            }
            let allowed_keys = keys_for(&rows,&b.owner,&b.name,control)?;
            let mut aliases: Vec<String> = Vec::new();
            for (number, line) in &b.body {
                control.checkpoint()?;
                let text = strip_comment(line,control)?;
                if raw_re().is_match(text) {
                    continue; // already counted
                }
                let mut flagged = false;
                for c in keyread_re().captures_iter(text) {
                    control.checkpoint()?;
                    if !allowed_keys.contains(c.s(1)) {
                        flagged = true;
                    }
                }
                if dynamic_re().is_match(text) {
                    flagged = true;
                }
                if let Some(m) = pat!(r#"var/(?:[\w/]+/)?(\w+)\s*=\s*params\s*\??\[\s*"([^"]+)"\s*\]\s*$"#).captures(py_strip(text)) {
                    let alias = m.s(1).to_string();
                    if !aliases.contains(&alias) {
                        aliases.push(alias);
                    }
                }
                for alias in &aliases {
                    control.checkpoint()?;
                    if Pat::cached(&format!(r"\b(?:text2num|locate|text2path|json_decode)\s*\(\s*{}\s*\)", alias)).is_match(text) {
                        flagged = true;
                    }
                }
                let blank = code_of(line,control)?;
                for (callee, argtext) in calls_of(&blank,control)? {
                    control.checkpoint()?;
                    if matches!(callee.as_str(), "tgui_act" | "act_ask" | "om_act_ask" | "rerun_ask" | "list") {
                        continue;
                    }
                    if let Some(h) = helpers.get(&callee) {
                        if h.is_subset(&allowed_keys) {
                            continue;
                        }
                    }
                    if pat!(r"(?:^|,)\s*params\s*(?:,|$)").is_match(&argtext) {
                        flagged = true;
                    }
                }
                if flagged {
                    out.push(("text2num_params", rel.to_string(), *number));
                }
            }
        }
    }
    control.checkpoint()?;Ok(out)
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    rows: Vec<DeclRow>,
    cands: Vec<Cand>,
}

#[derive(Serialize)]
pub struct Merged {
    rows: ByHandler,
    helpers: BTreeMap<String, BTreeSet<String>>,
}

#[cfg(feature="legacy-sem")]
pub fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-ui-facts", files, |f| facts_of(f));
    let rows_of: Vec<&Vec<DeclRow>> = fs.iter().map(|x| &x.rows).collect();
    let cands_of: Vec<&Vec<Cand>> = fs.iter().map(|x| &x.cands).collect();
    let merged = Merged { rows: declared_keys(&rows_of,&mut crate::key_policy_control::Compatibility).expect("original UI declarations"), helpers: typed_param_helpers(&cands_of,&mut crate::key_policy_control::Compatibility).expect("original UI helper closure") };
    let key = incr::ctx_key(&merged);
    let results = incr::keyed("sys-ui-judge", key, files, |f| {
        judge(f,&merged.rows,&merged.helpers,&mut crate::key_policy_control::Compatibility).expect("original UI judgment")
            .into_iter()
            .map(|(rule, _, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32))
            .collect::<Vec<(u8, u32)>>()
    });
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}


fn facts_bound(f:&Facts)->Option<usize>{let mut n=std::mem::size_of::<Facts>().checked_add(f.rows.capacity().checked_mul(4*std::mem::size_of::<DeclRow>())?)?.checked_add(f.cands.capacity().checked_mul(4*std::mem::size_of::<Cand>())?)?;for(t,h,keys)in &f.rows{n=n.checked_add(t.capacity().checked_add(h.capacity())?.checked_mul(4)?)?.checked_add(512)?;for k in keys{n=n.checked_add(k.capacity().checked_mul(4)?)?.checked_add(2048)?;}}for(name,keys,callees)in &f.cands{n=n.checked_add(name.capacity().checked_mul(4)?)?.checked_add(256)?;for value in keys.iter().chain(callees){n=n.checked_add(value.capacity().checked_mul(4)?)?.checked_add(2048)?;}}Some(n)}
fn context_bound(ctx:&Merged)->Option<usize>{let mut n=std::mem::size_of::<Merged>().checked_add(4096)?;for(handler,rows)in &ctx.rows{n=n.checked_add(handler.capacity().checked_mul(4)?)?.checked_add(2048)?.checked_add(rows.capacity().checked_mul(4*std::mem::size_of::<(String,BTreeSet<String>)>())?)?;for(owner,keys)in rows{n=n.checked_add(owner.capacity().checked_mul(4)?)?.checked_add(256)?;for k in keys{n=n.checked_add(k.capacity().checked_mul(4)?)?.checked_add(2048)?;}}}for(name,keys)in &ctx.helpers{n=n.checked_add(name.capacity().checked_mul(4)?)?.checked_add(2048)?;for key in keys{n=n.checked_add(key.capacity().checked_mul(4)?)?.checked_add(2048)?;}}Some(n)}
pub fn facts_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T)->Result<Facts,C::Error>{keep.checkpoint()?;let text=f.text();if !text.contains("params")&&!text.contains("UI_ACT(")&&!text.contains("UI_SUBACT(")&&!text.contains("TYPE_PROC_REF(/datum,"){return Ok(Facts::default())}crate::key_policy_control::reserve(temp,||text.len().checked_mul(256)?.checked_add(4096))?;let result=Facts{rows:declared_rows_of(f,temp)?,cands:helper_cands_of(f,temp)?};crate::key_policy_control::reserve(keep,||facts_bound(&result))?;keep.checkpoint()?;Ok(result)}
#[cfg(feature="legacy-sem")]fn facts_of(f:&SourceFile)->Facts{facts_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original UI facts")}
pub fn context_using<C:Control,T:Control<Error=C::Error>>(facts:&[&Facts],keep:&mut C,temp:&mut T)->Result<Merged,C::Error>{keep.checkpoint()?;let mut width=0usize;let mut count=0usize;for f in facts{keep.checkpoint()?;width=width.checked_add(facts_bound(f).ok_or_else(||keep.overflow())?).ok_or_else(||keep.overflow())?;count=count.checked_add(f.cands.len()).ok_or_else(||keep.overflow())?;}crate::key_policy_control::reserve(temp,||width.checked_mul(count.checked_add(1)?)?.checked_mul(8)?.checked_add(facts.len().checked_mul(4*std::mem::size_of::<&Facts>())?)?.checked_add(4096))?;let rows_of:Vec<_>=facts.iter().map(|f|&f.rows).collect();let cands_of:Vec<_>=facts.iter().map(|f|&f.cands).collect();let merged=Merged{rows:declared_keys(&rows_of,temp)?,helpers:typed_param_helpers(&cands_of,temp)?};crate::key_policy_control::reserve(keep,||context_bound(&merged))?;keep.checkpoint()?;Ok(merged)}
pub fn judge_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,ctx:&Merged,keep:&mut C,temp:&mut T)->Result<Vec<(&'static str,usize)>,C::Error>{keep.checkpoint()?;let text=f.text();if starts_any(&f.rel,NOT_TGUI)||(!text.contains("ui")&&!text.contains("params")&&!text.contains("UI_")){return Ok(Vec::new())}crate::key_policy_control::reserve(temp,||text.len().checked_mul(f.rel.len().checked_mul(4)?.checked_add(512)?)?.checked_add(context_bound(ctx)?.checked_mul(4)?)?.checked_add(4096))?;let found=judge(f,&ctx.rows,&ctx.helpers,temp)?;let mut rows=Vec::new();for(rule,path,line)in found{keep.checkpoint()?;if path!=f.rel{return Err(keep.allocation_failed())}crate::raw_tree_report::row(keep,&mut rows)?;rows.push((rule,line));}keep.checkpoint()?;Ok(rows)}
