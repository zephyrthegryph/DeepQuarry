//! Port of `tools/ci/sys_rules/dx_ownership_forms.py`: the ownership declaration forms replaced
//! by the ownership() and relations() list overrides (doc/rewrite/ownership.md 1.2, 4.1), string
//! var names in accessors, and a var owned twice (by a capability's owned() entries and by the
//! type's own ownership()).

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{before_slashes, is_py_space};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "old_ownership_macro",
        hint: "ownership() with owns()/shares()/proto() and relations() with rel_one()/rel_many()/rel_key() (ownership.md §1.2, §4.1)",
    },
    RuleMeta { name: "old_destroy_macro", hint: "an override of the well-known teardown proc (destroy_step/destroy_capture/destroy_after) (ownership.md §6)" },
    RuleMeta { name: "string_accessor_var", hint: "nameof(var) / nameof(/type::var) for the var name of an own_*/rel_*/proto_* accessor (ownership.md §1.2)" },
    RuleMeta {
        name: "owned_twice",
        hint: "drop the ownership() line: the capability (cap_slot) already owns this var through its owned() entries (ownership.md §1.2)",
    },
];

/// The same type, or one an ancestor of the other.
fn related(a: &str, b: &str) -> bool {
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

/// One file's contribution: its own sites (rule index into `RULES`), the vars its capabilities()
/// own (`(var, holder type)`) and the vars its ownership() owns (`(holder type, var, line)`).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    sites: Vec<(u8, u32)>,
    cap: Vec<(String, String)>,
    typ: Vec<(String, String, u32)>,
}

fn facts_of(f: &SourceFile) -> Facts {
    let old_macro = pat!(
        r"(?<![\w#])(OWN|OWN_POLICY|OWN_IF|SHARED|PROTO|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST|KEYED_TARGET|KEEP_AFTER_DESTROY|POOL_RESET|FORWARD_STATE)\s*\(|/declare_ownership\(|\b(own|shared|proto|rel)\(\s*decl\b"
    );
    let old_destroy = pat!(r"\b(DESTROY_STEP|DESTROY_CAPTURE|DESTROY_AFTER)\b");
    let string_accessor = pat!(r#"\b(own|rel|proto)_[a-z_]+\(\s*[^,()"]+,\s*"[A-Za-z_][A-Za-z0-9_]*""#);
    let proc_head = pat!(r"^(/[\w/]+)/(capabilities|ownership)\(\)");
    let cap_owns = pat!(r"\b(cap_slot|cap_cell_holder)\(\s*nameof\((\w+)\)");
    let type_owns = pat!(r"^\s*\.\s*\+=\s*owns\(\s*nameof\((\w+)\)");

    let mut out = Facts::default();
    let mut head: Option<(String, String)> = None;
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if old_macro.is_match(code) {
            out.sites.push((0, number as u32));
        }
        if old_destroy.is_match(code) {
            out.sites.push((1, number as u32));
        }
        if string_accessor.is_match(code) {
            out.sites.push((2, number as u32));
        }
        if line.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
            // `re.match` (anchored at the start): the pattern carries its own `^`.
            head = proc_head.captures(line).map(|m| (m.s(1).to_string(), m.s(2).to_string()));
            continue;
        }
        let Some((htype, hkind)) = &head else { continue };
        if hkind == "capabilities" {
            for m in cap_owns.captures_iter(code) {
                out.cap.push((m.s(2).to_string(), htype.clone()));
            }
        } else if let Some(m) = type_owns.captures(code) {
            out.typ.push((htype.clone(), m.s(1).to_string(), number as u32));
        }
    }
    out
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-dx-ownership-forms", files, facts_of);
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    let mut cap_owned: HashMap<&str, Vec<&str>> = HashMap::new(); // var -> [holder type]
    for (f, x) in files.iter().zip(&fs) {
        for (rule, number) in &x.sites {
            out.push((RULES[*rule as usize].name, f.rel.clone(), *number as usize));
        }
        for (var, holder) in &x.cap {
            cap_owned.entry(var.as_str()).or_default().push(holder.as_str());
        }
    }
    for (f, x) in files.iter().zip(&fs) {
        for (holder, var, number) in &x.typ {
            if cap_owned.get(var.as_str()).map(|v| v.iter().any(|other| related(holder, other))).unwrap_or(false) {
                out.push(("owned_twice", f.rel.clone(), *number as usize));
            }
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "dx_ownership_forms", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}
