//! `om_after(E, delay, proc, args...)` and `after_slot(E, "slot", delay, proc, args...)` to `after()`
//! (doc/rewrite/api_mapping.tsv, row om_after and step A1).
//!
//! `after(owner, delay, handler, key = null, clock = CLOCK_OWN, list/with = null)` is on master
//! (code/library/capabilities/timed.dm) and both old procs are one-line wrappers over the same `rx_after()`
//! with the same defaults, so the conversion changes the spelling and nothing else:
//!
//! ```text
//! om_after(E, 5 SECONDS, PROC_REF(x), a, b)        ->  after(E, 5 SECONDS, PROC_REF(x), with = list(a, b))
//! after_slot(E, "slot", 5 SECONDS, PROC_REF(x), a) ->  after(E, 5 SECONDS, PROC_REF(x), key = "slot", with = list(a))
//! ```
//!
//! `om_after` returns the timer id and so does `after`. `after_slot` returns `!!id`; the call is converted
//! only as a statement (its value unused), else it is `value_used` residue.
//!
//! The doc's later form, `after(owner, delay, then(PROC_REF(x)))` with an `x(datum/act/A)` handler, is not on
//! master; this converts to the form that is. The "choose" note (hold(lasts =), every(), COOLDOWN_*) is a
//! per-site judgement the rewrite does not make: the site becomes an `after()` and keeps its behaviour.

use crate::codemod::helpers::{any_named, gap, has_comment, is_arglist};
use crate::codemod::scan::Span;
use crate::codemod::{Codemod, Ctx, Edit, KeyUse, Outcome, Rewrite};

pub struct OmAfter;

impl Codemod for OmAfter {
    fn name(&self) -> &'static str {
        crate::codemod_spec::OM_AFTER.name

    }
    fn about(&self) -> &'static str {
        crate::codemod_spec::OM_AFTER.about

    }
    fn callees(&self) -> &'static [&'static str] {
        crate::codemod_spec::OM_AFTER.callees

    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        crate::codemod_spec::OM_AFTER.reasons

    }

    fn rewrite(&self, cx: &Ctx) -> Outcome {match rewrite_using(cx){Ok(outcome)=>outcome,Err(actual)=>Outcome::Operational(actual)}}
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OmAfter));
}

// SAME original decisions/edits; only allocation/checkpoint ingress differs.
fn rewrite_using(cx:&Ctx)->std::io::Result<Outcome>{
 let args=&cx.node.args;let slot=cx.callee=="after_slot";let fixed=if slot{4}else{3};
 if args.len()<fixed{return Ok(Outcome::Residue("too_few_args",cx.format_using(format_args!("{} needs {} arguments",cx.callee,fixed))?))}
 if any_named(args){return Ok(Outcome::Residue("named_arg",String::new()))}
 if(fixed..args.len()).any(|i|is_arglist(cx,i)){return Ok(Outcome::Residue("arglist",String::new()))}
 if slot&&!cx.stmt_level{return Ok(Outcome::Residue("value_used",String::new()))}
 let rest=&args[fixed..];let first=Edit::replace(cx.node.name,cx.own_using("after")?);let mut edits=cx.singleton_using(first)?;let mut keys=Vec::new();
 if slot{
  if has_comment(gap(cx,args[1].span,args[2].span)){return Ok(Outcome::Residue("comment_in_moved_span",String::new()))}
  let key_text=cx.own_using(cx.arg_text(1))?;
  cx.row_using(&mut edits)?;edits.push(Edit::delete(Span{start:args[1].span.start,end:args[2].span.start}));
  let inserted=cx.format_using(format_args!(", key = {}",key_text))?;cx.row_using(&mut edits)?;edits.push(Edit::insert(args[3].span.end,inserted));
  let owner=cx.own_using(if cx.arg_clean(0)=="src"{cx.owner}else{cx.arg_text(0)})?;
  let origin=cx.origin_using()?;let handler=cx.own_using(cx.arg_text(3))?;cx.row_using(&mut keys)?;keys.push(KeyUse{owner,key:key_text,origin,handler,synthesized:false});
 }
 if let(Some(first),Some(last))=(rest.first(),rest.last()){
  let opening=cx.own_using("with = list(")?;cx.row_using(&mut edits)?;edits.push(Edit::insert(first.span.start,opening));
  let closing=cx.own_using(")")?;cx.row_using(&mut edits)?;edits.push(Edit::insert(last.span.end,closing));
 }
 Ok(Outcome::Rewrite(Rewrite{edits,keys,..Default::default()}))
}
