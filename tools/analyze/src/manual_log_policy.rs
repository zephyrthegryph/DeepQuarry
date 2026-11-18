//! Unique original manual-fingerprint/log algorithm. Native control owns no source authority.
use crate::raw_fixture_policy::PatternApi as _;
use serde::{Serialize,Deserialize};
use crate::{dm::dx::{call_args,is_subtype,pick_arg,proc_ref,procs_in,related},tree::{SourceFile,Tree},key_policy_control::Control,pat};
/// A handler named in a constructor call: kind ("src"/"type"/"global"), the type for "type", the
/// proc name, and the calling type.
struct HandlerRef {
    kind: &'static str,
    of_type: Option<String>,
    name: String,
    caller: String,
}

/// constructor -> positional index of its handler argument
fn handler_index(name: &str) -> usize {
    match name {
        "cap_hand" => 1,
        _ => 2,
    }
}

/// One file's contribution: the handlers its constructor calls name, and the procs it holds that call a manual
/// fingerprint/log function (with the lines), in proc order.
#[derive(Clone,Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    /// (kind 0 src / 1 type / 2 global, the type for "type", the proc name, the calling type)
    refs: Vec<(u8, Option<String>, String, String)>,
    manual: Vec<ManualProc>,
}

#[derive(Clone,Serialize, Deserialize, PartialEq)]
struct ManualProc {
    name: String,
    path: String,
    lines: Vec<u32>,
}

pub fn facts_of(f:&SourceFile)->Facts{facts_of_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original manual-log facts")}
pub fn facts_of_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T)->Result<Facts,C::Error>{
 keep.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(f.rel.len().checked_mul(4)?.checked_add(512)?)?.checked_add(4096))?;
    let ctor = pat!(r"(?<![\w./:])(cap_entry|cap_hand|cap_insert|cap_tool|cap_use_on)\s*\(");
    let manual = pat!(r"(?<![\w./:])(?:add_fingerprint|log_game|log_admin|message_admins|log_and_message_admins)\s*\(");
facts_body(f,keep,temp,ctor,manual)
}
#[cfg(feature="native-policy")]
pub fn facts_with_fixture<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Facts,C::Error>{
 keep.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(f.rel.len().checked_mul(4)?.checked_add(512)?)?.checked_add(4096))?;

let ctor=fixture.pattern(r"(?<![\w./:])(cap_entry|cap_hand|cap_insert|cap_tool|cap_use_on)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w./:])(cap_entry|cap_hand|cap_insert|cap_tool|cap_use_on)\s*\("));
let manual=fixture.pattern(r"(?<![\w./:])(?:add_fingerprint|log_game|log_admin|message_admins|log_and_message_admins)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w./:])(?:add_fingerprint|log_game|log_admin|message_admins|log_and_message_admins)\s*\("));
facts_body(f,keep,temp,&ctor,&manual)
}
fn facts_body<P:crate::raw_fixture_policy::PatternApi,C:Control,T:Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T,ctor:&P,manual:&P)->Result<Facts,C::Error>{    let clean = f.clean();
    let mut out = Facts::default();
    for proc in crate::dm::dx::procs_in_using(f,temp)? {
        keep.checkpoint()?;
        let mut hits: Vec<u32> = Vec::new();
        for k in 0..proc.body_len {
            keep.checkpoint()?;
            let number = proc.body_start + k;
            let text = clean.line(number);
            if manual.is_match(text) {
                crate::raw_tree_report::row(keep,&mut hits)?;hits.push(number as u32);
            }
            if !text.contains("cap_") {
                continue;
            }
            for m in ctor.captures_iter(text) {
                keep.checkpoint()?;
                let Some(args) = crate::dm::dx::call_args_using(text,m.end(0)-1,temp)? else { continue };
                if args.is_empty() {
                    continue;
                }
                let Some(arg) = crate::dm::dx::pick_arg_using(&args,Some(handler_index(m.s(1))),"handler",temp)? else { continue };
                if let Some((kind, of_type, name)) = crate::dm::dx::proc_ref_using(&arg,temp)? {
                    let code = match kind {
                        "src" => 0,
                        "type" => 1,
                        _ => 2,
                    };
                    crate::raw_tree_report::row(keep,&mut out.refs)?;out.refs.push((code,of_type.as_deref().map(|s|crate::raw_tree_report::own(keep,s)).transpose()?,crate::raw_tree_report::own(keep,&name)?,crate::raw_tree_report::own(keep,&proc.path)?));
                }
            }
        }
        if !hits.is_empty() {
            crate::raw_tree_report::row(keep,&mut out.manual)?;out.manual.push(ManualProc { name: crate::raw_tree_report::own(keep,&proc.name)?, path: crate::raw_tree_report::own(keep,&proc.path)?, lines: hits });
        }
    }
    keep.checkpoint()?;Ok(out)
}

fn is_handler_of<C:Control>(name:&str,path:&str,refs:&[HandlerRef],control:&mut C,peak:&mut usize)->Result<bool,C::Error>{
    let global = path == "/";
    for r in refs {
        control.checkpoint()?;crate::raw_tree_report::peak(control,peak,||{let width=path.len().checked_add(r.caller.len())?.checked_add(r.of_type.as_ref().map_or(0,|s|s.len()))?;width.checked_mul(width)?.checked_mul(8)?.checked_add(4096)})?;
        if r.name != name {
            continue;
        }
        if r.kind == "global" {
            if global {
                return Ok(true);
            }
        } else if r.kind == "type" {
            if !global && is_subtype(path, r.of_type.as_deref().unwrap_or("")) {
                return Ok(true);
            }
        } else if !global && (r.caller == "/" || related(path, &r.caller)) {
            return Ok(true);
        }
    }
    Ok(false)
}

pub fn assemble<'a,C:Control>(pairs:&[(&'a str,&'a Facts)],control:&mut C)->Result<Vec<(&'static str,String,usize)>,C::Error>{
 let mut refs:Vec<HandlerRef>=Vec::new();
 for(_,fa)in pairs{control.checkpoint()?;for(code,of_type,name,caller)in &fa.refs{control.checkpoint()?;crate::raw_tree_report::row(control,&mut refs)?;refs.push(HandlerRef{kind:match code{0=>"src",1=>"type",_=>"global"},of_type:of_type.as_deref().map(|s|crate::raw_tree_report::own(control,s)).transpose()?,name:crate::raw_tree_report::own(control,name)?,caller:crate::raw_tree_report::own(control,caller)?});}}
 // Preserve the original by-name fast prefilter and its matching precedence.
 crate::key_policy_control::reserve(control,||refs.len().checked_mul(4*std::mem::size_of::<&str>())?.checked_add(4096))?;
 let mut by_name=std::collections::HashSet::new();if C::CHECKED{by_name.try_reserve(refs.len()).map_err(|_|control.allocation_failed())?;if by_name.capacity()>refs.len().saturating_mul(4).max(8){return Err(control.allocation_failed())}}
 for r in &refs{control.checkpoint()?;by_name.insert(r.name.as_str());}
 let mut found=Vec::new();let mut lineage_peak=0;
 for(relative,fa)in pairs{control.checkpoint()?;for mp in &fa.manual{control.checkpoint()?;let global=mp.path=="/";let is_action=mp.name.starts_with("act_")&&!global;
 if !is_action&&!(by_name.contains(mp.name.as_str())&&is_handler_of(&mp.name,&mp.path,&refs,control,&mut lineage_peak)?){continue}
 for number in &mp.lines{control.checkpoint()?;crate::raw_tree_report::row(control,&mut found)?;found.push(("dx_manual_fingerprint_log",crate::raw_tree_report::own(control,relative)?,*number as usize));}}}
 control.checkpoint()?;Ok(found)
}
pub fn scan(tree:&Tree,files:&[&SourceFile])->Vec<(&'static str,String,usize)>{let _=tree;let facts=crate::incr::facts("sys-dx-manual-fingerprint-log",files,facts_of);let pairs:Vec<_>=files.iter().zip(&facts).map(|(file,facts)|(file.rel.as_str(),facts)).collect();assemble(&pairs,&mut crate::key_policy_control::Compatibility).expect("original manual-log assembly")}
