//! Port of `tools/ci/sys_rules/dx_ownership_forms.py`: the ownership declaration forms replaced
//! by the ownership() and relations() list overrides (doc/rewrite/ownership.md 1.2, 4.1), string
//! var names in accessors, and a var owned twice (by a capability's owned() entries and by the
//! type's own ownership()).

use std::collections::HashMap;

use crate::dm::sys::{register_module, SysModule};
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

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let old_macro = pat!(
        r"(?<![\w#])(OWN|OWN_POLICY|OWN_IF|SHARED|PROTO|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST|KEYED_TARGET|KEEP_AFTER_DESTROY|POOL_RESET|FORWARD_STATE)\s*\(|/declare_ownership\(|\b(own|shared|proto|rel)\(\s*decl\b"
    );
    let old_destroy = pat!(r"\b(DESTROY_STEP|DESTROY_CAPTURE|DESTROY_AFTER)\b");
    let string_accessor = pat!(r#"\b(own|rel|proto)_[a-z_]+\(\s*[^,()"]+,\s*"[A-Za-z_][A-Za-z0-9_]*""#);
    let proc_head = pat!(r"^(/[\w/]+)/(capabilities|ownership)\(\)");
    let cap_owns = pat!(r"\b(cap_slot|cap_cell_holder)\(\s*nameof\((\w+)\)");
    let type_owns = pat!(r"^\s*\.\s*\+=\s*owns\(\s*nameof\((\w+)\)");

    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    let mut cap_owned: HashMap<String, Vec<String>> = HashMap::new(); // var -> [holder type]
    let mut type_owned: Vec<(String, String, String, usize)> = Vec::new(); // (holder type, var, rel, number)
    for f in files {
        let mut head: Option<(String, String)> = None;
        for (number, line) in f.raw().numbered() {
            let code = before_slashes(line);
            if old_macro.is_match(code) {
                out.push(("old_ownership_macro", f.rel.clone(), number));
            }
            if old_destroy.is_match(code) {
                out.push(("old_destroy_macro", f.rel.clone(), number));
            }
            if string_accessor.is_match(code) {
                out.push(("string_accessor_var", f.rel.clone(), number));
            }
            if line.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
                // `re.match` (anchored at the start): the pattern carries its own `^`.
                head = proc_head.captures(line).map(|m| (m.s(1).to_string(), m.s(2).to_string()));
                continue;
            }
            let Some((htype, hkind)) = &head else { continue };
            if hkind == "capabilities" {
                for m in cap_owns.captures_iter(code) {
                    cap_owned.entry(m.s(2).to_string()).or_default().push(htype.clone());
                }
            } else if let Some(m) = type_owns.captures(code) {
                type_owned.push((htype.clone(), m.s(1).to_string(), f.rel.clone(), number));
            }
        }
    }
    for (holder, var, rel, number) in type_owned {
        if cap_owned.get(&var).map(|v| v.iter().any(|other| related(&holder, other))).unwrap_or(false) {
            out.push(("owned_twice", rel, number));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "dx_ownership_forms", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}
