//! Port of `tools/ci/sys_rules/dx_manual_fingerprint_log.py`: fingerprints and log lines written
//! by hand in dispatched handlers (dx_conventions.md section 2, 8). `act_<action>` procs and the
//! handler procs named by `cap_hand/cap_tool/cap_use_on/cap_insert/cap_entry` constructor calls
//! must not call `add_fingerprint`, `log_game`, `log_admin`, `message_admins` or
//! `log_and_message_admins`: `dispatch_call()` records them.

use std::collections::HashSet;

use crate::dm::dx::{call_args, is_subtype, pick_arg, proc_ref, related, DxIndex, Proc};
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

fn handler_refs(tree: &Tree, procs: &[Proc]) -> Vec<HandlerRef> {
    let ctor = pat!(r"(?<![\w./:])(cap_entry|cap_hand|cap_insert|cap_tool|cap_use_on)\s*\(");
    let mut out = Vec::new();
    for proc in procs {
        for (_n, text) in proc.lines(tree) {
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
                    out.push(HandlerRef { kind, of_type, name, caller: proc.path.clone() });
                }
            }
        }
    }
    out
}

fn is_handler(proc: &Proc, refs: &[HandlerRef]) -> bool {
    for r in refs {
        if r.name != proc.name {
            continue;
        }
        if r.kind == "global" {
            if proc.is_global() {
                return true;
            }
        } else if r.kind == "type" {
            if !proc.is_global() && is_subtype(&proc.path, r.of_type.as_deref().unwrap_or("")) {
                return true;
            }
        } else if !proc.is_global() && (r.caller == "/" || related(&proc.path, &r.caller)) {
            return true;
        }
    }
    false
}

fn scan_procs(tree: &Tree, procs: &[Proc]) -> Vec<(&'static str, String, usize)> {
    let manual = pat!(r"(?<![\w./:])(?:add_fingerprint|log_game|log_admin|message_admins|log_and_message_admins)\s*\(");
    let refs = handler_refs(tree, procs);
    let by_name: HashSet<&str> = refs.iter().map(|r| r.name.as_str()).collect();
    let mut found = Vec::new();
    for proc in procs {
        let is_action = proc.name.starts_with("act_") && !proc.is_global();
        if !is_action && !(by_name.contains(proc.name.as_str()) && is_handler(proc, &refs)) {
            continue;
        }
        for (number, text) in proc.lines(tree) {
            if manual.is_match(text) {
                found.push(("dx_manual_fingerprint_log", proc.rel.clone(), number));
            }
        }
    }
    found
}

fn scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    scan_procs(tree, &DxIndex::get(tree, files).procs)
}

const FIXTURE: &str = include_str!("../../fixtures/sys__dx_manual_fingerprint_log/code/modules/x/selftest.dm");

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let tree = Tree::from_files(vec![SourceFile::from_text("x.dm", FIXTURE)]);
    let files = vec![tree.get("x.dm").unwrap()];
    let idx = DxIndex::get(&tree, &files);
    let mut got: Vec<usize> = scan_procs(&tree, &idx.procs).into_iter().map(|(_, _, n)| n).collect();
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
