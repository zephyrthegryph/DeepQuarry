//! Metadata moved from the actual sys_dx_review registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta { name: "effect_refusal", hint: "make the refusal a requirement: needs(req(PROC_REF(x), because = MSG(...))) (final_api.html section 9)" },
    RuleMeta { name: "request_in_effect", hint: "ask with asks(/datum/prompt/x, fields = ...) on the op, read A.answer.value in then() (section 16.13)" },
    RuleMeta { name: "nameof_unrelated", hint: "name a var of the holder's own type (nameof(var)); another type's var is not this holder's to name" },
    RuleMeta { name: "unkeyed_wire_after", hint: "give the timer a key (after(..., key = \"x\")) or make the pulse a timed hold (wires(), hold(..., lasts =))" },
    RuleMeta { name: "manual_push", hint: "write the state through its setter: the push is generated from what it reads (section 7)" },
    RuleMeta { name: "output_side_effect", hint: "outputs (ui_data, draw, appearance) say and play nothing, and a look changes no atom (its own or another's): move it to the op or handler that changes the state, or draw it through the look (look.overlay(), look.glow(range, power, color), look.held_state())" },
    RuleMeta { name: "undef_then_used", hint: "#undef a file-local define after its last use, or define it in __defines" },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}

// SAME actual registered name/group/required-list fields, no policy/source role.
pub const SCOPE_MODULE_NAME:&str="dx_review";
#[cfg(feature="native-policy")]
pub(crate) fn visit_scopes<C:crate::key_policy_control::Control>(control:&mut C,visit:&mut dyn FnMut(crate::required_scope_policy::Requirement<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
crate::required_scope_registry::visit_sys(SCOPE_MODULE_NAME,control,visit)?;
control.checkpoint()
}
