//! `op_order`: the order ops answer a click in (doc/rewrite/final_api.html section 8, "Order"; section 9, metadata).
//!
//! Two rules:
//!
//! * `unordered_clash`: two ops one type composes (its own, its named bundles' and the capabilities its CAPABILITIES block expands to, with
//!   their parameters substituted) that can answer the same input (the same intent, an overlapping held tool or item type, the same binding
//!   kind) at the same tier, with nothing ordering them: no priority(above/below(...)) naming the other, no click_order() of a composing bundle
//!   covering both, no binding specificity (a narrower item type, then a tool quality, then a broad item), no passes(), and when() parts that are not mutually
//!   exclusive. The engine's boot check (RULE_OP_CLASH) catches the identical-binding case at runtime; this one also sees overlapping item
//!   types, statically. Ops the engine derives (a construction ladder's steps) are not modelled.
//!
//!   What it models as the resolver does (code/engine/parts/resolve.dm): the intents each binding answers (answers(), hostile(), a pinned
//!   gesture(): a drag answers INTENT_DROP_ONTO, never a click), the tier by value (hostile() yields ATTACK; OP_PRIORITY_PART - 1 is its own
//!   tier), disjoint stance() sets, when() conjuncts that negate (c / not(c), req_is(K) / req_is(K, FALSE), req_bool(X) is X, graph stages
//!   that do not meet), and a constructor's entries its params switch off (`lid ? op(...) : null`, `if(by_hand)`), and binding specificity
//!   (op_binding_specificity): of two held-item bindings, an item type narrower than /obj/item answers before a tool quality, which answers
//!   before a broad item (item(/obj/item), whatever acceptance proc gates it), and a deeper item type before a shallower one, so only two
//!   bindings of equal specificity clash. An opaque when() proc is not exclusive of anything; the engine has no annotation that says it is.
//! * `relative_priority`: a hand-written priority(above(...)) or priority(below(...)). Each one is a per-type patch for an order a bundle
//!   should declare once (click_order()); the count is a ceiling that can only fall.
//!
//! Both are hard bans (no baseline).
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::{op_order_policy as policy,tree::SourceFile,sem::decls::Decls};
struct OpOrder;
impl Lint for OpOrder {
 fn meta(&self)->&Meta{&policy::META}
 fn scan_file(&self,_:&Cx,f:&SourceFile,out:&mut Sink){policy::relative_priority(f,|number|{if !out.allowed(f,number,"op_order"){out.site_keyed("relative_priority",&f.rel,number,f.line(number).trim().to_string(),"relative_priority");}})}
 fn scan_tree(&self,cx:&Cx,out:&mut Sink){
  let decls=Decls::get(cx.tree);let files=cx.all_files().into_iter().map(policy::file_facts).collect::<Vec<_>>();
  let markers=decls.markers.iter().map(|m|policy::Marker{name:&m.name,relative:&m.rel,line:m.line,args:&m.args}).collect::<Vec<_>>();
  let model=policy::Model::from_owned_facts(files,&markers);
  for m in markers.iter().filter(|m|m.name=="CAPABILITIES"){
   if cx.exempt(m.relative)||m.relative.starts_with("code/engine/_generated/"){continue}
   for clash in model.judge(m.args){
    if let Some(f)=cx.tree.get(m.relative){if out.allowed(f,m.line as usize,"op_order"){continue}}
    out.site_keyed("unordered_clash",m.relative,m.line as usize,clash.message,clash.key);
   }
  }
 }
}
pub fn register(reg:&mut Registry){reg.add(OpOrder)}
