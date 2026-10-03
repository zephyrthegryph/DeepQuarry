//! `om_ask` -> `open_request` for the generic confirm / text / number / choice prompts. The work is in `crate::codemod::om_ask`.

use crate::codemod::om_ask;
use crate::codemod::{Codemod, Ctx, Edit, Outcome};
use crate::sem::Sem;
use crate::tree::Tree;
use std::any::Any;
use std::path::Path;
use std::sync::Arc;

pub struct OmAsk;

impl Codemod for OmAsk {
    fn name(&self) -> &'static str {
        "om_ask"
    }
    fn about(&self) -> &'static str {
        "om_ask(M, /datum/om/prompt/text, PROC_REF(h), message = ...) -> open_request(src, /datum/prompt/text, PROC_REF(h), answerer = M, question = ..., timeout = 0), h(ask) -> h(datum/act/request/A) with a guard"
    }
    fn callees(&self) -> &'static [&'static str] {
        &["om_ask"]
    }
    fn ast_alias(&self) -> &'static [(&'static str, &'static str)] {
        &[("om_ask_begin", "om_ask")]
    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        &[
            ("argc", "fewer than (answerer, prompt, handler), or a positional argument after them"),
            ("kind_unsupported", "not literally /datum/om/prompt/confirm, text, number or choice (a subtype carries its own state and checks)"),
            ("roles_or_checks", "asker, subject, receiver, requires, ask_flags, a cancel option or another option the new request has no field for"),
            ("unsupported_param", "a parameter the kind does not take, or answer_on_no that is not TRUE"),
            ("no_message", "no message: the old window showed nothing, the new kind has a default question"),
            ("name_text_unknown", "max_length is not MAX_NAME_LEN and name_text is not given, so whether the answer is name-stripped is not known"),
            ("handler_expr", "the handler is not PROC_REF(name) / TYPE_PROC_REF(/type, name), or the call is outside a type's proc (no src)"),
            ("comment_in_call", "a comment inside the call would be lost"),
            ("value_used", "the call is not a statement of its own"),
            ("handler_blocked", "the handler cannot change shape: another site or caller uses it, its sites differ in kind, it does not take the one prompt parameter, or its body reads more of the prompt than the answer and answerer"),
        ]
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        om_ask::rewrite(cx)
    }
    fn prepare(&self, tree: &Tree, sem: &Sem) -> Arc<dyn Any + Send + Sync> {
        om_ask::prepare(tree, sem, &|rel| self.excluded(rel))
    }
    fn declares(&self) -> bool {
        true
    }
    fn follow_edits(&self, root: &Path, _tree: &Tree, _sem: &Sem, prep: &(dyn Any + Send + Sync), follows: &[String]) -> Vec<(String, Vec<Edit>)> {
        om_ask::follow_edits(root, prep, follows)
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OmAsk));
}
