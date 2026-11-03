//! SAME original dx_reactive raw/proc judges over borrowed current lines.
//! Proc/header/type-var DATA comes from the existing dx policy producer only.
//! No semantic graph, SourceFile facade, Tree clone, parser or cache is created.
use crate::key_policy_control::Gate;
use std::collections::{HashMap,HashSet};
use crate::{dm::dx::{self,call_args,match_paren,Proc},pat::Pat,util::{py_lstrip,py_rstrip,py_strip},pat,pat_match};
use crate::reactive_writer_policy::local_decl;
pub use crate::reactive_writer_policy::reactive_writes_lines_using;
const REACTIVE_ANY: &[&str] = &["should_run", "hidden_verbs", "tgui_data"];
const REACTIVE_CAP: &[&str] = &["draw", "gate", "ui_data", "examine", "hidden_verbs"];
const CONTEXT_ROOTS: &[&str] = &["src", "user", "held", "look", "entry", "data", "ui", "state", "world", "global", "usr", "GLOB", "config", "callee"];
/// Relation vars whose target marks its owner changed on every write (review 2 M8).
pub(crate) const MARKING_RELATIONS: &[&str] = &["reagents"];
const NEVER_STATE: &[&str] = &["len", "type", "parent_type"];





fn hide_args() -> &'static Pat {
    pat!(r"\b(?:nameof|PROC_REF|TYPE_PROC_REF|GLOBAL_PROC_REF|TYPE_VERB_REF|VERB_REF)\s*\(")
}

fn initial_call() -> &'static Pat {
    pat!(r"\binitial\s*\(")
}



const ASSIGN_OP: &str = r"\s*(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)";

// ---- reactive procs ---------------------------------------------------------------------------

pub fn is_reactive_using(proc: &Proc, needs_names: &HashSet<String>, gate:&dyn Gate) -> bool {
 if !gate.checkpoint(){return false;}

    if proc.path.starts_with("/datum/capability") {
        return REACTIVE_CAP.contains(&proc.name.as_str()) || needs_names.contains(&proc.name);
    }
    if proc.name == "draw" || proc.name == "look_parts" {
        // look_parts(look) is a chain's provider dispatch, called only from its draw (the draw sweep): it is the draw's body
        return proc.params.iter().any(|p| p.contains("look"));
    }
    REACTIVE_ANY.contains(&proc.name.as_str()) || needs_names.contains(&proc.name)
}

/// `blank_calls`: `text` with the argument lists of the calls `p` matches blanked out.
pub fn blank_calls_using(text: &str, p: &Pat, gate:&dyn Gate) -> String {
 if !gate.checkpoint(){return String::new();}
 if gate.checked()&&!gate.reserve(text.len().checked_mul(2).and_then(|n|n.checked_add(128))){return String::new();}


    let mut b = Vec::new();
    if b.try_reserve_exact(text.len()).is_err(){gate.allocation_failed();return String::new()}
    b.extend_from_slice(text.as_bytes());
    for m in matches_using(p,text,gate) {
 if !gate.checkpoint(){return String::new();}
        if let Some(end) = match_paren(text, m.end - 1) {
            if end > 0 {
                for byte in b.iter_mut().take(end).skip(m.end) {
 if !gate.checkpoint(){return String::new();}
                    *byte = b' ';
                }
            }
        }
    }
    String::from_utf8(b).unwrap_or_else(|_| text.to_string())
}

/// `foreign_reads`: the var names read on another object in one sanitized line.
pub fn foreign_reads_using<'t>(text: &'t str, own_roots: &HashSet<String>, context: &HashSet<String>, relations: &HashSet<String>, gate:&dyn Gate) -> Vec<&'t str> {
 if !gate.checkpoint(){return Vec::new();}

    let mut out: Vec<&'t str> = Vec::new();
    let chain = pat!(r#"(?<![\w.\]\)"'/:])([A-Za-z_]\w*)((?:\s*\??\.\s*[A-Za-z_]\w*)+)"#);
    let segment = pat!(r"\??\.\s*([A-Za-z_]\w*)");
    let global_root = pat_match!(r"(?:SS[a-z]\w*|[A-Z][A-Z0-9_]{2,})$");
    for m in captures_using(chain,text,gate) {
 if !gate.checkpoint(){return Vec::new();}
        let root = m.s(1);
        let mut segs = Vec::new();
        for capture in captures_using(segment,m.s(2),gate){if !reserve_row(&mut segs,gate){return Vec::new()}segs.push(capture.s(1));}
        let after = py_lstrip(&text[m.end(0)..]);
        if after.starts_with('(') {
            segs.pop();
        }
        if segs.is_empty() {
            continue;
        }
        let first_foreign;
        if root == "GLOB" || own_roots.contains(root) {
            first_foreign = 1;
        } else if global_root.is_match(root) || CONTEXT_ROOTS.contains(&root) || context.contains(root) {
            continue;
        } else {
            first_foreign = 0;
        }
        let mut prev = root;
        for (k, name) in segs.iter().enumerate() {
 if !gate.checkpoint(){return Vec::new();}
            if k >= first_foreign && !NEVER_STATE.contains(name) && !relations.contains(prev) {
                if !reserve_row(&mut out,gate){return Vec::new()}out.push(name);
            }
            prev = name;
        }
    }
    out
}

// ---- dx_caps_instance_read --------------------------------------------------------------------

/// `caps_reads`: `(line, name)` for each instance read in a capabilities() body.
pub fn caps_reads_using(proc: &Proc, lines:&[(usize,&str)], table: &HashMap<String, HashSet<String>>, gate:&dyn Gate) -> Vec<(usize, String)> {
 if !gate.checkpoint(){return Vec::new();}
 if gate.checked()&&!gate.reserve(proc.params.iter().try_fold(4096usize,|n,s|n.checked_add(s.len())?.checked_add(4096))){return Vec::new();}


    let own=match dx::vars_of_using(table,&proc.path,true,&mut Proxy(gate)){Ok(value)=>value,Err(())=>return Vec::new()};

    let mut local = HashSet::new();
    for parameter in &proc.params{if !insert(&mut local,parameter,gate){return Vec::new()}}
    for (_n, text) in lines {
 if !gate.checkpoint(){return Vec::new();}
        for m in captures_using(local_decl(),text,gate) {
 if !gate.checkpoint(){return Vec::new();}
            if !insert(&mut local,m.s(1),gate){return Vec::new()}
        }
    }
    let mut out = Vec::new();
    let ident = pat!(r"(?<![\w./:])(src\s*\??\.\s*)?([A-Za-z_]\w*)");
    for (number, text) in lines {
 if !gate.checkpoint(){return Vec::new();}
        let text = blank_calls_using(text, hide_args(), gate);
        let mut hit: Option<String> = None;
        for m in captures_using(ident,&text,gate) {
 if !gate.checkpoint(){return Vec::new();}
            let name = m.s(2);
            if m.matched(1) && !m.s(1).is_empty() {
                if !py_lstrip(&text[m.end(0)..]).starts_with('(') {
                    hit=Some(owned(name,gate));
                    break;
                }
                continue;
            }
            if name == "src" || local.contains(name) || !own.contains(name) {
                continue;
            }
            let rest = &text[m.end(0)..];
            if py_lstrip(rest).starts_with('(') {
                continue; // a call
            }
            let before = &text[..m.start(0)];
            if pat_match!(r"\s*=(?!=)").is_match(rest) && before.matches('(').count() > before.matches(')').count() {
                continue; // a named argument key
            }
            if py_rstrip(before).ends_with("var") {
                continue;
            }
            hit=Some(owned(name,gate));
            break;
        }
        if let Some(h) = hit {
            if !reserve_row(&mut out,gate){return Vec::new()}out.push((*number,h));
        }
    }
    out
}

// ---- dx_timed_write ---------------------------------------------------------------------------

/// `timed_vars`: `{var name: type paths}` for every `timed_set(D, nameof(v))` / `timed_set(D, "v")`.
pub fn add_timed_vars_using<'a>(proc:&Proc,lines:&[(usize,&str)],raw_line:&dyn Fn(usize)->&'a str,out:&mut HashMap<String,HashSet<String>>, gate:&dyn Gate) {
 if !gate.checkpoint(){return;}

    let timed = pat!(r"(?<![\w./:])timed_set\s*\(");
    let nameof_var = pat_match!(r"\s*nameof\(\s*(?:[\w.]+\.|/[\w/]+::)?(\w+)\s*\)\s*$");
    {
        for &(number, text) in lines {
 if !gate.checkpoint(){return;}
            for m in matches_using(timed,text,gate) {
 if !gate.checkpoint(){return;}
                let args=match dx::call_args_using(text,m.end-1,&mut Proxy(gate)){Ok(Some(args))=>args,Ok(None)=>continue,Err(())=>return};
                if args.len() < 2 {
                    continue;
                }
                let name: Option<String> = if let Some(nm) = capture_using(nameof_var,&args[1],gate) {
                    Some(owned(nm.s(1),gate))
                } else {
                    let raw=raw_line(number);
                    capture_using(pat!(r#"timed_set\s*\([^,]*,\s*"(\w+)""#),raw,gate).map(|l|owned(l.s(1),gate))
                };
                if let Some(n) = name {
                    if !n.is_empty() {
                        if crate::key_policy_control::hash_room(&mut Proxy(gate),out).is_err(){return}let paths=out.entry(n).or_default();if !insert(paths,&proc.path,gate){return}
                    }
                }
            }
        }
    }
}

/// The local `related` of dx_reactive.py (path prefixes only; not `dx::related`).
fn related_using(a: &str, b: &str, gate:&dyn Gate) -> bool {
 if !gate.checkpoint(){return false;}

    a == b || a.strip_prefix(b).is_some_and(|tail|tail.starts_with('/')) || b.strip_prefix(a).is_some_and(|tail|tail.starts_with('/'))
}

pub struct TimedPats {
    dotted: Pat,
    bare: Pat,
    incdec: Pat,
    decl: Pat,
}

/// `timed_writes`: the lines where a timed var is written outside timed_set()/its setter.
pub fn timed_writes_using(proc: &Proc, lines:&[(usize,&str)], timed: &HashMap<String, HashSet<String>>, cache: &mut HashMap<String, TimedPats>, gate:&dyn Gate) -> Vec<usize> {
 if !gate.checkpoint(){return Vec::new();}


    let mut local = HashSet::new();
    for parameter in &proc.params{if !insert(&mut local,parameter,gate){return Vec::new()}}
    for (_n, text) in lines {
 if !gate.checkpoint(){return Vec::new();}
        for m in captures_using(local_decl(),text,gate) {
 if !gate.checkpoint(){return Vec::new();}
            if !insert(&mut local,m.s(1),gate){return Vec::new()}
        }
    }
    let timed_set = pat!(r"(?<![\w./:])timed_set\s*\(");
    let mut out = Vec::new();
    for (number, text) in lines {
 if !gate.checkpoint(){return Vec::new();}
        if timed_set.is_match(text) {
            continue;
        }
        for (name, paths) in timed {
 if !gate.checkpoint(){return Vec::new();}
            // Every pattern below needs the name in the line.
            if !text.contains(name.as_str()) {
                continue;
            }
            if proc.name.strip_prefix("set_") == Some(name.as_str()) {
                continue;
            }
            if !cache.contains_key(name)&&gate.checked()&&!gate.reserve(name.len().checked_mul(512).and_then(|n|n.checked_add(16384))){return Vec::new()}
            if !cache.contains_key(name){
                if crate::key_policy_control::hash_room(&mut Proxy(gate),cache).is_err(){return Vec::new()}
                let key=owned(name,gate);if !gate.checkpoint(){return Vec::new()}
                cache.insert(key,TimedPats {
                dotted: Pat::new(&format!(r"\??\.\s*{}\b{}", name, ASSIGN_OP)),
                bare: Pat::new(&format!(r"(?<![\w.]){}\b{}", name, ASSIGN_OP)),
                incdec: Pat::new(&format!(r"(?:\+\+|--)\s*{}\b", name)),
                decl: Pat::new(&format!(r"\bvar/(?:[\w/]+/)?{}\b", name)),
                });
            }
            let Some(p)=cache.get(name)else{return Vec::new()};
            let dotted = p.dotted.is_match(text);
            let mut bare = false;
            if !local.contains(name) && paths.iter().any(|q| related_using(&proc.path, q, gate)) {
                bare = p.bare.is_match(text) || p.incdec.is_match(text);
                if bare && p.decl.is_match(text) {
                    bare = false;
                }
            }
            if dotted || bare {
                if !reserve_row(&mut out,gate){return Vec::new()}out.push(*number);
                break;
            }
        }
    }
    out
}

// ---- dx_reactive_write ------------------------------------------------------------------------

/// `reactive_writes`: the line numbers where a reactive proc writes state.
// ---- own roots --------------------------------------------------------------------------------

/// `own_roots_of`: (own roots, context roots, relation roots) of a proc.
pub fn own_roots_of_using(proc: &Proc, lines:&[(usize,&str)], relations: &HashSet<String>, gate:&dyn Gate) -> (HashSet<String>, HashSet<String>, HashSet<String>) {
 if !gate.checkpoint(){return (HashSet::new(),HashSet::new(),HashSet::new());}
 if gate.checked()&&!gate.reserve(proc.params.iter().try_fold(4096usize,|n,s|n.checked_add(s.len())?.checked_add(4096))){return (HashSet::new(),HashSet::new(),HashSet::new());}


    let mut roots: HashSet<String> = HashSet::new();
    if !insert(&mut roots,"src",gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
    let mut context: HashSet<String> = HashSet::new();
    let mut rels: HashSet<String> = HashSet::new();
    if proc.path.starts_with("/datum/capability") && !proc.params.is_empty() {
        if !insert(&mut roots,&proc.params[0],gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
    }
    let cap_typed = pat!(r"\bvar/datum/capability(?:/\w+)*/(\w+)\b");
    let local_from = pat!(r"\bvar/(?:[\w/]+/)?(\w+)\s*=\s*(.+)$");
    let config_calls = pat_match!(r"(?:cap_of|ladder_for|caps_of|caps_all)\s*\(");
    let cap_data_expr = pat_match!(r"(?:(\w+)\s*\??\.\s*)?cap_data\s*(?:\(|\??\[)");
    let capability_data_expr = pat_match!(r"\bcapability_data\s*\(\s*(\w+)\s*\)");
    let relation_expr = pat_match!(r"(?:(\w+)\s*\??\.\s*)?(\w+)\s*$");
    let dotted_root = pat_match!(r"(\w+)\s*\??\.");
    // `look.watch(X)` (and `look.watch_look(X)`, the hop read of X's look only) declares the draw's read through X: the last name of X is a relation, like a watched REL.
    let look_watch = pat!(r"look\s*\.\s*watch(?:_look)?\s*\(\s*([\w.?]+)\s*\)");
    let last_name = pat_match!(r"(?:\w+\s*\??\.\s*)*(\w+)$");
    // `look.neighbours(...)` is a watched read too: a local it fills (`var/x = look.neighbours(..)[1]`, `for(var/x in look.neighbours(..))`) is a relation.
    let look_neighbours = pat!(r"\bvar/(?:[\w/]+/)?(\w+)\s*(?:=|in)\s*look\s*\.\s*neighbours?\s*\(");
    for (_n, text) in lines {
 if !gate.checkpoint(){return (HashSet::new(),HashSet::new(),HashSet::new());}
        for w in captures_using(look_watch,text,gate) {
 if !gate.checkpoint(){return (HashSet::new(),HashSet::new(),HashSet::new());}
            if let Some(l) = capture_using(last_name,w.s(1),gate) {
                if !insert(&mut rels,l.s(1),gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
            }
        }
        for w in captures_using(look_neighbours,text,gate) {
 if !gate.checkpoint(){return (HashSet::new(),HashSet::new(),HashSet::new());}
            if !insert(&mut rels,w.s(1),gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        }
        for m in captures_using(cap_typed,text,gate) {
 if !gate.checkpoint(){return (HashSet::new(),HashSet::new(),HashSet::new());}
            if !insert(&mut context,m.s(1),gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        }
        let Some(m) = capture_using(local_from,py_rstrip(text),gate) else { continue };
        let name=owned(m.s(1),gate);
        let expr = py_strip(m.s(2));
        if roots.contains(expr) {
            if !insert_owned(&mut roots,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        } else if context.contains(expr) || CONTEXT_ROOTS.contains(&expr) {
            if !insert_owned(&mut context,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())} // `var/datum/interaction/capability/E = entry`: still context
        } else if let Some(cd) = capture_using(cap_data_expr,expr,gate).filter(|cd| !cd.matched(1) || cd.s(1).is_empty() || roots.contains(cd.s(1))) {
            let _ = cd;
            if !insert_owned(&mut roots,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        } else if capture_using(capability_data_expr,expr,gate).is_some_and(|cd| roots.contains(cd.s(1))) {
            // The runtime accessor retains the same holder-owned payload identity.
            if !insert_owned(&mut roots,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        } else if config_calls.is_match(expr) {
            if !insert_owned(&mut context,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        } else if let Some(d) = capture_using(dotted_root,expr,gate).filter(|d| context.contains(d.s(1))) {
            let _ = d;
            if !insert_owned(&mut context,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
        } else if let Some(r) = capture_using(relation_expr,expr,gate) {
            if relations.contains(r.s(2)) && (!r.matched(1) || r.s(1).is_empty() || roots.contains(r.s(1))) {
                if !insert_owned(&mut rels,name,gate){return (HashSet::new(),HashSet::new(),HashSet::new())}
            }
        }
    }
    (roots, context, rels)
}


pub const RULE_READ:&str="dx_untracked_read";pub const RULE_WRITE:&str="dx_reactive_write";pub const RULE_CAPS:&str="dx_caps_instance_read";pub const RULE_TIMED:&str="dx_timed_write";
pub fn metadata()->&'static crate::lint::Meta{static META:std::sync::OnceLock<crate::lint::Meta>=std::sync::OnceLock::new();META.get_or_init(||crate::dm::sys::module_metadata(&crate::dm::sys::SysModule{name:crate::allow_registry_fields::sys_dx_reactive::SCOPE_MODULE_NAME,rules:crate::allow_registry_fields::sys_dx_reactive::RULES,..crate::dm::sys::SysModule::DEFAULT},crate::lint::ScanKind::Tree))}
#[derive(Default)]pub struct Context{pub needs:HashSet<String>,pub tracked:HashSet<String>,pub watched:HashSet<String>,pub timed:HashMap<String,HashSet<String>>}
pub fn body_lines<'a,C:crate::key_policy_control::Control>(proc:&Proc,file:&'a crate::tree::SourceFile,c:&mut C)->Result<Vec<(usize,&'a str)>,C::Error>{use crate::key_policy_control as kc;let mut out=Vec::new();for k in 0..proc.body_len{c.checkpoint()?;let line=proc.body_start.checked_add(k).ok_or_else(||c.overflow())?;kc::row(c,&mut out)?;out.push((line,file.clean().line(line)));}Ok(out)}
pub fn add_file_context_using(file:&crate::tree::SourceFile,procs:&[Proc],context:&mut Context, gate:&dyn Gate){
 if !gate.checkpoint(){return;}

 let needs_re=pat!(r"\bneeds\s*=\s*(?:PROC_REF\(\s*(\w+)\s*\)|TYPE_PROC_REF\(\s*[/\w]+\s*,\s*(\w+)\s*\))");
 let tracked_re=pat_match!(r"\s*(?:TRACKED\(\s*/[\w/]+\s*,\s*(\w+)\s*[,)]|SETTER\(\s*/[\w/]+\s*,\s*(\w+)\s*\))");
 let watch_re=pat!(r"^\s*REL\w*\(\s*/[\w/]+\s*,\s*(\w+)\b[^\n]*\bWATCH\w*|\brel\(\s*nameof\(\s*(?:[\w.]+\.|/[\w/]+::)?(\w+)\s*\)[^\n]*\bwatch\s*=");
 for line in file.clean().lines(){
 if !gate.checkpoint(){return;}
  if line.contains("needs"){for m in captures_using(needs_re,line,gate){let n=if m.matched(1){m.s(1)}else{m.s(2)};if !insert(&mut context.needs,n,gate){return}}}
  if line.contains("TRACKED")||line.contains("SETTER("){if let Some(t)=capture_using(tracked_re,line,gate){let n=if t.matched(1)&&!t.s(1).is_empty(){t.s(1)}else{t.s(2)};if !insert(&mut context.tracked,n,gate){return}}}
  if line.contains("REL")||line.contains("rel("){if let Some(w)=capture_using(watch_re,line,gate){let n=if w.matched(1)&&!w.s(1).is_empty(){w.s(1)}else{w.s(2)};if !insert(&mut context.watched,n,gate){return}}}
 }
 for proc in procs{if !gate.checkpoint(){return}let lines=borrow_body_lines(proc,file,gate);add_timed_vars_using(proc,&lines,&|line|file.line(line),&mut context.timed, gate);}
}
pub fn add_auto_tracked_using(file:&crate::tree::SourceFile,context:&mut Context, gate:&dyn Gate){
 if !gate.checkpoint(){return;}
let line=pat!(r"^TRACKED\(/[A-Za-z0-9_/]+, (\w+)\)");for l in file.raw().lines(){if !gate.checkpoint(){return}if let Some(m)=capture_using(line,l,gate){if !insert(&mut context.tracked,m.s(1),gate){return}}}}
pub fn judge_procs_using(file:&crate::tree::SourceFile,fd:&crate::dm::dx::FileDx,context:&Context, gate:&dyn Gate)->[Vec<usize>;3]{
 if !gate.checkpoint(){return [Vec::new(),Vec::new(),Vec::new()];}
 if gate.checked()&&!gate.reserve(set_bound(&context.watched).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(4096))){return [Vec::new(),Vec::new(),Vec::new()];}


 let mut base_relations=HashSet::new();
 for name in &context.watched{if !insert(&mut base_relations,name,gate){return empty_groups()}}
 for name in MARKING_RELATIONS{if !insert(&mut base_relations,name,gate){return empty_groups()}}
 let(mut reads,mut writes,mut timed)=(Vec::new(),Vec::new(),Vec::new());
 for proc in &fd.procs{
  if !gate.checkpoint(){return empty_groups()}
  if is_reactive_using(proc,&context.needs,gate){
   let mut relations=HashSet::new();
   for name in &base_relations{if !insert(&mut relations,name,gate){return empty_groups()}}
   let lines=borrow_body_lines(proc,file,gate);
   let(roots,local,local_relations)=own_roots_of_using(proc,&lines,&relations,gate);
   for name in local_relations{if !insert_owned(&mut relations,name,gate){return empty_groups()}}
   for(number,text)in &lines{
    if !gate.checkpoint(){return empty_groups()}
    let text=blank_calls_using(text,initial_call(),gate);
    if foreign_reads_using(&text,&roots,&local,&relations,gate).into_iter().any(|name|!context.tracked.contains(name)){
     if !reserve_row(&mut reads,gate){return empty_groups()}reads.push(*number);
    }
   }
   let found=match reactive_writes_lines_using(proc,&lines,&mut Proxy(gate),&mut Proxy(gate)){Ok(rows)=>rows,Err(())=>return empty_groups()};
   if !append_rows(&mut writes,found,gate){return empty_groups()}
  }
 }
 if !context.timed.is_empty(){let mut cache=HashMap::new();for proc in &fd.procs{
  if !gate.checkpoint(){return empty_groups()}
  let lines=borrow_body_lines(proc,file,gate);
  let found=timed_writes_using(proc,&lines,&context.timed,&mut cache,gate);
  if !append_rows(&mut timed,found,gate){return empty_groups()}
 }}
 [reads,writes,timed]
}

pub fn judge_caps_using(file:&crate::tree::SourceFile,fd:&crate::dm::dx::FileDx,table:&HashMap<String,HashSet<String>>, gate:&dyn Gate)->Vec<usize>{
 if !gate.checkpoint(){return Vec::new();}
let mut caps=Vec::new();
 for proc in &fd.procs{if !gate.checkpoint(){return Vec::new()}if proc.name=="capabilities"&&proc.path!="/atom"{let lines=borrow_body_lines(proc,file,gate);for(line,_)in caps_reads_using(proc,&lines,table,gate){if !reserve_row(&mut caps,gate){return Vec::new()}caps.push(line);}}}
 caps
}

struct Compatibility;
impl Gate for Compatibility{fn checked(&self)->bool{false}fn checkpoint(&self)->bool{true}fn reserve(&self,_:Option<usize>)->bool{true}fn allocation_failed(&self){}}
pub fn is_reactive(proc:&Proc,needs:&HashSet<String>)->bool{is_reactive_using(proc,needs,&Compatibility)}
pub fn blank_calls(text:&str,p:&Pat)->String{blank_calls_using(text,p,&Compatibility)}
pub fn foreign_reads<'a>(text:&'a str,roots:&HashSet<String>,context:&HashSet<String>,relations:&HashSet<String>)->Vec<&'a str>{foreign_reads_using(text,roots,context,relations,&Compatibility)}
pub fn caps_reads(proc:&Proc,lines:&[(usize,&str)],table:&HashMap<String,HashSet<String>>)->Vec<(usize,String)>{caps_reads_using(proc,lines,table,&Compatibility)}
pub fn add_timed_vars<'a>(proc:&Proc,lines:&[(usize,&str)],raw:&dyn Fn(usize)->&'a str,out:&mut HashMap<String,HashSet<String>>){add_timed_vars_using(proc,lines,raw,out,&Compatibility)}
pub fn timed_writes(proc:&Proc,lines:&[(usize,&str)],timed:&HashMap<String,HashSet<String>>,cache:&mut HashMap<String,TimedPats>)->Vec<usize>{timed_writes_using(proc,lines,timed,cache,&Compatibility)}
pub fn own_roots_of(proc:&Proc,lines:&[(usize,&str)],relations:&HashSet<String>)->(HashSet<String>,HashSet<String>,HashSet<String>){own_roots_of_using(proc,lines,relations,&Compatibility)}
pub fn add_file_context(file:&crate::tree::SourceFile,procs:&[Proc],context:&mut Context){add_file_context_using(file,procs,context,&Compatibility)}
pub fn add_auto_tracked(file:&crate::tree::SourceFile,context:&mut Context){add_auto_tracked_using(file,context,&Compatibility)}
pub fn judge_procs(file:&crate::tree::SourceFile,fd:&crate::dm::dx::FileDx,context:&Context)->[Vec<usize>;3]{judge_procs_using(file,fd,context,&Compatibility)}
pub fn judge_caps(file:&crate::tree::SourceFile,fd:&crate::dm::dx::FileDx,table:&HashMap<String,HashSet<String>>)->Vec<usize>{judge_caps_using(file,fd,table,&Compatibility)}
fn set_bound(s:&HashSet<String>)->Option<usize>{s.iter().try_fold(s.capacity().checked_mul(std::mem::size_of::<String>()+128)?,|n,s|n.checked_add(s.len())?.checked_add(4096))}
fn set_table_bound(t:&HashMap<String,HashSet<String>>)->Option<usize>{t.iter().try_fold(4096usize,|n,(owner,s)|n.checked_add(owner.len())?.checked_add(set_bound(s)?)?.checked_add(4096))}
fn reserve_row<T>(out:&mut Vec<T>,gate:&dyn Gate)->bool{if out.len()<out.capacity(){return gate.checkpoint()}let Some(target)=out.capacity().checked_mul(2).map(|n|n.max(4))else{gate.reserve(None);return false};if gate.checked()&&!gate.reserve(target.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(128))){return false}match out.try_reserve_exact(target-out.len()){Ok(())=>true,Err(_)=>{gate.allocation_failed();false}}}
fn captures_using<'a>(p:&Pat,source:&'a str,gate:&dyn Gate)->Vec<crate::pat::Caps<'a>>{let mut out=Vec::new();let result=p.try_for_each_capture(source,&mut out,|_,groups|{if !gate.checkpoint(){return Err(())}if gate.checked()&&!gate.reserve(groups.checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>()).and_then(|n|n.checked_add(128))){return Err(())}Ok(())},|out,capture|{if !reserve_row(out,gate){return Err(())}out.push(capture);Ok(())});if result.is_err(){Vec::new()}else{out}}
fn matches_using<'a>(p:&Pat,source:&'a str,gate:&dyn Gate)->Vec<crate::pat::M<'a>>{let mut out=Vec::new();let result=p.try_for_each_match(source,&mut out,|_|if gate.checkpoint(){Ok(())}else{Err(())},|out,m|{if !reserve_row(out,gate){return Err(())}out.push(m);Ok(())});if result.is_err(){Vec::new()}else{out}}
fn borrow_body_lines<'a>(proc:&Proc,file:&'a crate::tree::SourceFile,gate:&dyn Gate)->Vec<(usize,&'a str)>{let mut out=Vec::new();for k in 0..proc.body_len{if !gate.checkpoint()||!reserve_row(&mut out,gate){return Vec::new()}let Some(n)=proc.body_start.checked_add(k)else{gate.reserve(None);return Vec::new()};out.push((n,file.clean().line(n)));}out}
struct Proxy<'a>(&'a dyn Gate);
impl crate::key_policy_control::Control for Proxy<'_>{type Error=();const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),()>{if self.0.checkpoint(){Ok(())}else{Err(())}}fn reserve(&mut self,n:usize)->Result<(),()>{if self.0.reserve(Some(n)){Ok(())}else{Err(())}}fn overflow(&mut self){self.0.reserve(None);}fn allocation_failed(&mut self){self.0.allocation_failed();}}

fn owned(source:&str,gate:&dyn Gate)->String{if !gate.checkpoint(){return String::new()}if gate.checked()&&!gate.reserve(source.len().checked_mul(2).and_then(|n|n.checked_add(64))){return String::new()}let mut out=String::new();if out.try_reserve_exact(source.len()).is_err(){gate.allocation_failed();return out}out.push_str(source);out}
fn insert(set:&mut HashSet<String>,value:&str,gate:&dyn Gate)->bool{if !gate.checkpoint(){return false}if set.contains(value){return true}if crate::key_policy_control::set_room(&mut Proxy(gate),set).is_err(){return false}let value=owned(value,gate);if !gate.checkpoint(){return false}set.insert(value);true}
fn insert_owned(set:&mut HashSet<String>,value:String,gate:&dyn Gate)->bool{if !gate.checkpoint(){return false}if set.contains(&value){return true}if crate::key_policy_control::set_room(&mut Proxy(gate),set).is_err(){return false}set.insert(value);true}
fn capture_using<'a>(p:&Pat,source:&'a str,gate:&dyn Gate)->Option<crate::pat::Caps<'a>>{if !gate.checkpoint(){return None}if gate.checked()&&!gate.reserve(p.capture_group_count().checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>()).and_then(|n|n.checked_add(128))){return None}p.captures(source)}

fn empty_groups()->[Vec<usize>;3]{[Vec::new(),Vec::new(),Vec::new()]}
fn append_rows<T>(out:&mut Vec<T>,rows:Vec<T>,gate:&dyn Gate)->bool{for row in rows{if !reserve_row(out,gate){return false}out.push(row)}true}

#[cfg(all(test,feature="legacy-sem"))]
#[path="sys_reactive_policy_tests.rs"]mod tests;
