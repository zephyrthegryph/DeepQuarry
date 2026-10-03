//! `om_hook` / `om_unhook` -> `observe` / `unobserve`, with the handlers they name following. The work is in `crate::codemod::om_hook`.

use crate::codemod::om_hook;
use crate::codemod::{Codemod, Ctx, Edit, Outcome};
use crate::sem::Sem;
use crate::tree::Tree;
use std::any::Any;
use std::path::Path;
use std::sync::Arc;

pub struct OmHook;

impl Codemod for OmHook {
    fn name(&self) -> &'static str {
        "om_hook"
    }
    fn about(&self) -> &'static str {
        "om_hook(src, /datum/om/event/x, listener, PROC_REF(h)) -> observe(src, /datum/notice/x, listener, then(PROC_REF(h))), om_unhook -> unobserve, h(datum/source, event) -> h(datum/act/A)"
    }
    fn callees(&self) -> &'static [&'static str] {
        &["om_hook", "om_unhook", "om_unhook_all"]
    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        &[
            ("argc", "not (source, events, listener, handler) / (source, events, listener), or a named argument"),
            ("event_not_literal", "the event is a variable or an expression, not an om event path or list() of them"),
            ("event_unmapped", "an event with no notice twin (a before/ guard, a decision, one that reads event.result): convert by hand"),
            ("list_value_used", "an event list needs a statement to become one observe per event"),
            ("listener_not_src", "PROC_REF(h) names a proc of the listener, and the listener is not src: use TYPE_PROC_REF(/type, h)"),
            ("handler_expr", "the handler is not PROC_REF(name) / TYPE_PROC_REF(/type, name)"),
            ("handler_blocked", "the handler cannot change shape: another site or caller uses it, a hook of it does not convert, its signature is not (source, event), or its body uses the event whole, a field the notice lacks, or the name A"),
            ("unhook_unpaired", "an om_unhook whose om_hook does not convert (or is not visible on a related type): convert both by hand"),
            ("unhook_all", "om_unhook_all(listener) has no one-call form: unobserve each source"),
        ]
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        om_hook::rewrite(cx)
    }
    fn prepare(&self, tree: &Tree, sem: &Sem) -> Arc<dyn Any + Send + Sync> {
        om_hook::prepare(tree, sem, &|rel| self.excluded(rel))
    }
    fn declares(&self) -> bool {
        true
    }
    fn follow_edits(&self, root: &Path, _tree: &Tree, _sem: &Sem, prep: &(dyn Any + Send + Sync), follows: &[String]) -> Vec<(String, Vec<Edit>)> {
        om_hook::follow_edits(root, prep, follows)
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OmHook));
}
