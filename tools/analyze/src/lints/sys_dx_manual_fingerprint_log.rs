//! Port of `tools/ci/sys_rules/dx_manual_fingerprint_log.py`: fingerprints and log lines written
//! by hand in dispatched handlers (dx_conventions.md section 2, 8). `act_<action>` procs and the
//! handler procs named by `cap_hand/cap_tool/cap_use_on/cap_insert/cap_entry` constructor calls
//! must not call `add_fingerprint`, `log_game`, `log_admin`, `message_admins` or
//! `log_and_message_admins`: `dispatch_call()` records them.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::dm::dx::{call_args, is_subtype, pick_arg, proc_ref, procs_in, related};
use crate::incr;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_manual_fingerprint_log",
    hint: "drop it: dispatch_call() fingerprints and logs a successful dispatched call (set `log =` / ui_logged() for the level) (dx_conventions.md section 2, 8)",
}];

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
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    /// (kind 0 src / 1 type / 2 global, the type for "type", the proc name, the calling type)
    refs: Vec<(u8, Option<String>, String, String)>,
    manual: Vec<ManualProc>,
}

#[derive(Serialize, Deserialize, PartialEq)]
struct ManualProc {
    name: String,
    path: String,
    lines: Vec<u32>,
}

fn facts_of(f: &SourceFile) -> Facts {
    let ctor = pat!(r"(?<![\w./:])(cap_entry|cap_hand|cap_insert|cap_tool|cap_use_on)\s*\(");
    let manual = pat!(r"(?<![\w./:])(?:add_fingerprint|log_game|log_admin|message_admins|log_and_message_admins)\s*\(");
    let clean = f.clean();
    let mut out = Facts::default();
    for proc in procs_in(f) {
        let mut hits: Vec<u32> = Vec::new();
        for k in 0..proc.body_len {
            let number = proc.body_start + k;
            let text = clean.line(number);
            if manual.is_match(text) {
                hits.push(number as u32);
            }
            if !text.contains("cap_") {
                continue;
            }
            for m in ctor.captures_iter(text) {
                let Some(args) = call_args(text, m.end(0) - 1) else { continue };
                if args.is_empty() {
                    continue;
                }
                let Some(arg) = pick_arg(&args, Some(handler_index(m.s(1))), "handler") else { continue };
                if let Some((kind, of_type, name)) = proc_ref(&arg) {
                    let code = match kind {
                        "src" => 0,
                        "type" => 1,
                        _ => 2,
                    };
                    out.refs.push((code, of_type, name, proc.path.clone()));
                }
            }
        }
        if !hits.is_empty() {
            out.manual.push(ManualProc { name: proc.name.clone(), path: proc.path.clone(), lines: hits });
        }
    }
    out
}

fn is_handler_of(name: &str, path: &str, refs: &[HandlerRef]) -> bool {
    let global = path == "/";
    for r in refs {
        if r.name != name {
            continue;
        }
        if r.kind == "global" {
            if global {
                return true;
            }
        } else if r.kind == "type" {
            if !global && is_subtype(path, r.of_type.as_deref().unwrap_or("")) {
                return true;
            }
        } else if !global && (r.caller == "/" || related(path, &r.caller)) {
            return true;
        }
    }
    false
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let facts = incr::facts("sys-dx-manual-fingerprint-log", files, facts_of);
    let mut refs: Vec<HandlerRef> = Vec::new();
    for fa in &facts {
        for (code, of_type, name, caller) in &fa.refs {
            let kind: &'static str = match code {
                0 => "src",
                1 => "type",
                _ => "global",
            };
            refs.push(HandlerRef { kind, of_type: of_type.clone(), name: name.clone(), caller: caller.clone() });
        }
    }
    let by_name: HashSet<&str> = refs.iter().map(|r| r.name.as_str()).collect();
    let mut found = Vec::new();
    for (f, fa) in files.iter().zip(&facts) {
        for mp in &fa.manual {
            let global = mp.path == "/";
            let is_action = mp.name.starts_with("act_") && !global;
            if !is_action && !(by_name.contains(mp.name.as_str()) && is_handler_of(&mp.name, &mp.path, &refs)) {
                continue;
            }
            for number in &mp.lines {
                found.push(("dx_manual_fingerprint_log", f.rel.clone(), *number as usize));
            }
        }
    }
    found
}

const FIXTURE: &str = include_str!("../../fixtures/sys__dx_manual_fingerprint_log/code/modules/x/selftest.dm");

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let tree = Tree::from_files(vec![SourceFile::from_text("x.dm", FIXTURE)]);
    let files = vec![tree.get("x.dm").unwrap()];
    let mut got: Vec<usize> = scan(&tree, &files).into_iter().map(|(_, _, n)| n).collect();
    got.sort();
    let at = |snippet: &str| -> usize { lines.iter().position(|l| l.contains(snippet)).map(|k| k + 1).unwrap_or(0) };
    let mut want = vec![at("\tadd_fingerprint(user)"), at("log_game(\"[user] toggled"), at("message_admins("), at("log_admin(\"unbolted\")")];
    want.sort();
    if got != want {
        return Err(format!("dx_manual_fingerprint_log selftest: got {:?}, want {:?}", got, want));
    }
    Ok("dx_manual_fingerprint_log".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule {
            name: "dx_manual_fingerprint_log",
            rules: RULES,
            files_scan: Some(scan),
            selftest: Some(selftest),
            py_selftest: true,
            ..SysModule::DEFAULT
        },
    );
}
