//! Bounded pinned untagged variable/typed-field errors, GPL-3.0 provenance as
//! checker_expression_visit. `undefined_variable` is a route, not a TOML tag.
use crate::{
    checker_expression_visit::{self, Event, Walk},
    checks::{Diagnostic, Severity},
};
use dm_ir::{PackedU128, Resolver, SymbolId};
use dm_tree::{
    frontend::{ArchivedBody, BodyArchive, ColdFrontend, ParsedBody},
    SemanticTree,
};
pub fn check(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    enabled: bool,
) -> Result<Vec<Diagnostic>, String> {
    if !enabled {
        return Ok(Vec::new());
    }
    rows(
        &frontend.snapshot.tree,
        checker_expression_visit::evaluated(frontend, body, resolver, profile)?,
    )
}
pub fn archived(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    enabled: bool,
) -> Result<Vec<Diagnostic>, String> {
    if !enabled {
        return Ok(Vec::new());
    }
    rows(
        archive.tree(),
        checker_expression_visit::archived(archive, body, resolver, profile)?,
    )
}
fn rows(tree: &SemanticTree, walk: Walk<'_>) -> Result<Vec<Diagnostic>, String> {
    let mut out=Vec::new();visit_events(tree,walk.events,|row|{out.push(row);Ok::<(),String>(())})?;Ok(out)
}
pub(crate) fn visit_events<'a,E:From<String>+for<'e>From<&'e str>>(tree:&SemanticTree,events:impl IntoIterator<Item=Event<'a>>,mut emit:impl FnMut(Diagnostic)->Result<(),E>)->Result<(),E>{
    for event in events {
        let (expression, at, message) = match event {
            Event::MissingVariable {
                expression,
                at,
                name,
                explicit_global,
            } => {
                let subject = if explicit_global { "global var" } else { "var" };
                (expression, at, format!("undefined {subject}: {name:?}"))
            },
            Event::MissingField {
                expression,
                at,
                name,
                receiver,
            } => {
                let owner = if receiver == SymbolId::of("/") {
                    "(global)"
                } else {
                    tree.symbols()
                        .text(receiver)
                        .ok_or("missing field receiver spelling")?
                };
                (
                    expression,
                    at,
                    format!("undefined field: {name:?} on {owner}"),
                )
            }
            _ => continue,
        };
        emit(Diagnostic {
            family: "undefined_variable",
            severity: Severity::Error,
            span: at,
            expression_span: expression.span,
            message,
            notes: Vec::new(),
        })?;
    }
    Ok(())
}

#[cfg(test)]
#[path = "checks_undefined_variable_tests.rs"]
mod tests;

/// Genuine current-source findings from the SAME variable judge and evaluator.
/// SkippedOriginal is issued ONLY from the actual Original BODY disposition;
/// unsupported grammar, missing prefix binding and operational failures are Err.
/// Source-neutral output of the SAME evaluated variable judge. This contains
/// no source text, model, absolute current point or foreign syntax owner.
/// Code affinity alone is NOT semantic freshness; the current QueryDb consumer
/// must first verify its real resolver dependencies before lending rows.
#[derive(Debug)]pub struct CurrentUndefinedProduct{code:std::sync::Weak<dm_tree::frontend::BodyCodeIdentity>,window:dm_syntax::Span,rows:Vec<Diagnostic>,skipped:bool}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum CurrentUndefinedDisposition{Evaluated,SkippedOriginal}
#[derive(Debug)]pub struct CurrentUndefinedRow<'a>{pub diagnostic:&'a Diagnostic,pub span:dm_syntax::Span,pub expression_span:dm_syntax::Span}
impl CurrentUndefinedProduct{
 pub fn disposition(&self)->CurrentUndefinedDisposition{if self.skipped{CurrentUndefinedDisposition::SkippedOriginal}else{CurrentUndefinedDisposition::Evaluated}}
 pub fn retained_charge(&self)->Option<usize>{self.rows.capacity().checked_mul(std::mem::size_of::<Diagnostic>()).and_then(|base|self.rows.iter().try_fold(base,|sum,row|sum.checked_add(row.message.capacity()))).and_then(|bytes|bytes.checked_add(std::mem::size_of::<Self>()))}
 pub fn visit_storage(&self,mut visit:impl FnMut(crate::checker_effects::Storage)){use crate::checker_effects::Storage;visit(Storage::Buffer{owner:"current_variable.rows",address:self.rows.as_ptr()as usize,logical:self.rows.len()*std::mem::size_of::<Diagnostic>(),capacity:self.rows.capacity()*std::mem::size_of::<Diagnostic>()});for row in &self.rows{visit(Storage::Buffer{owner:"current_variable.message",address:row.message.as_ptr()as usize,logical:row.message.len(),capacity:row.message.capacity()});}}
 /// Canonical neutral bytes for the EXISTING query graph's result fingerprint.
 /// All fields influencing current delivery participate; this does not issue a
 /// source/model identity or authorize reporting without current verification.
 pub fn fingerprint_parts(&self,mut part:impl FnMut(&[u8])){part(&[self.skipped as u8]);part(&(self.rows.len()as u64).to_le_bytes());for row in &self.rows{part(&(row.span.start as u64).to_le_bytes());part(&(row.span.end as u64).to_le_bytes());part(&(row.expression_span.start as u64).to_le_bytes());part(&(row.expression_span.end as u64).to_le_bytes());part(&(row.message.len()as u64).to_le_bytes());part(row.message.as_bytes());}}
 /// Geometry-only final binding. The caller supplies semantic freshness by
 /// having just verified the producer's current resolver dependency graph.
 pub fn visit_current(&self,body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,mut visit:impl FnMut(CurrentUndefinedRow<'_>)->std::io::Result<()>)->std::io::Result<CurrentUndefinedDisposition>{
  if !std::sync::Weak::ptr_eq(&self.code,&std::sync::Arc::downgrade(body.syntax().original_code_owner()))||self.window!=body.syntax().canonical_window(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"variable product belongs to another canonical BODY"))}
  for row in &self.rows{let span=body.syntax().projection().span(row.span).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"variable point escapes current BODY binding"))?;let expression_span=body.syntax().projection().span(row.expression_span).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"variable expression escapes current BODY binding"))?;visit(CurrentUndefinedRow{diagnostic:row,span,expression_span})?;}Ok(self.disposition())
 }
}
pub fn current_using<W:crate::checker_effects::EffectReportWork>(body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,syntax_admission:&dm_syntax::SettingAdmission<'_>,admission:&crate::checker_effects::ExecutionAdmission,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<CurrentUndefinedProduct,crate::policy_body_demand::PolicyFailure>{
 current_using_context(body,resolver,profile,syntax_admission,admission,work,checkpoint,None)
}
/// Same actual canonical Kind4 producer; no separate parser/model is accepted.
pub type CurrentCanonicalBodyLoan<'a>=dyn Fn(&std::sync::Arc<dm_tree::frontend::BodySyntaxInput>)->Result<std::sync::Arc<dm_tree::frontend::OriginalBodySyntaxProduct>,dm_tree::frontend::BodySyntaxFailure>+'a;
pub fn current_using_with_prefix<W:crate::checker_effects::EffectReportWork>(body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,syntax_admission:&dm_syntax::SettingAdmission<'_>,admission:&crate::checker_effects::ExecutionAdmission,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>,prefix_loan:&CurrentCanonicalBodyLoan<'_>)->Result<CurrentUndefinedProduct,crate::policy_body_demand::PolicyFailure>{
 current_using_context(body,resolver,profile,syntax_admission,admission,work,checkpoint,Some(prefix_loan))
}
fn current_using_context<W:crate::checker_effects::EffectReportWork>(body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,syntax_admission:&dm_syntax::SettingAdmission<'_>,admission:&crate::checker_effects::ExecutionAdmission,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>,prefix_loan:Option<&CurrentCanonicalBodyLoan<'_>>)->Result<CurrentUndefinedProduct,crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure as Failure;use std::{cell::RefCell,io};
 fn oom(message:&'static str)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
 let marker=work.mark().map_err(Failure::Operational)?;let mut out:Vec<Diagnostic>=Vec::new();
 let pending={let work=RefCell::new(&mut *work);let reserve=|bytes|work.borrow_mut().reserve(bytes);let budget=crate::checker_effects::output::ReportBudget::for_operation(admission);
  checker_expression_visit::current_events_using(body,resolver,profile,syntax_admission,&budget,&reserve,checkpoint,prefix_loan,|event|{
   checkpoint().map_err(Failure::Operational)?;
   let(name,owner)=match &event{Event::MissingVariable{name,..}=>(*name,0),Event::MissingField{name,receiver,..}=>(*name,if *receiver==SymbolId::of("/"){8}else{body.tree().symbols().text(*receiver).ok_or("current undefined receiver spelling absent")?.len()}),_=>return Ok(())};
   // This EXACT judge emits body-anchored spans and no notes. Fund its real
   // Debug name +owner rendering before format! creates the owned message.
   let bound=name.len().checked_add(owner).and_then(|n|n.checked_add(64)).and_then(|n|n.checked_mul(8)).ok_or_else(||oom("current variable message geometry overflow"))?;budget.charge(bound).map_err(|_|oom("current variable message admission exhausted"))?;reserve(bound).map_err(Failure::Operational)?;
   visit_events(body.tree(),std::iter::once(event),|diagnostic|{
    if !diagnostic.notes.is_empty(){return Err("current variable judge gained unqualified source-note origins".into())}if diagnostic.message.capacity()>bound{return Err(oom("current variable message exceeded funded rendering geometry"))}
    if body.syntax().projection().span(diagnostic.span).is_none()||body.syntax().projection().span(diagnostic.expression_span).is_none(){return Err("variable judge point escapes canonical/current BODY binding".into())}
    if out.len()==out.capacity(){let count=out.capacity().max(2).checked_mul(2).ok_or_else(||oom("current variable output count overflow"))?;let bytes=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<Diagnostic>())).ok_or_else(||oom("current variable output geometry overflow"))?;budget.charge(bytes).map_err(|_|oom("current variable output admission exhausted"))?;reserve(bytes).map_err(Failure::Operational)?;out.try_reserve_exact(count-out.len()).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;if out.capacity()>count.checked_mul(4).ok_or_else(||oom("current variable output capacity overflow"))?{return Err(oom("current variable output allocator exceeded funded geometry"))}}
    out.push(diagnostic);Ok(())
   })
  })
 };
 match pending{
  Err(actual)=>{drop(out);let cleanup=work.reconcile(marker,0);if matches!(&actual,Failure::Operational(_)){return Err(actual)}cleanup.map_err(Failure::Operational)?;Err(actual)},
  Ok(checker_expression_visit::CurrentEvaluation::SkippedOriginal)=>{if !out.is_empty(){drop(out);work.reconcile(marker,0).map_err(Failure::Operational)?;return Err("genuine skipped Original BODY unexpectedly evaluated variable rows".into())}drop(out);work.reconcile(marker,0).map_err(Failure::Operational)?;Ok(CurrentUndefinedProduct{code:std::sync::Arc::downgrade(body.syntax().original_code_owner()),window:body.syntax().canonical_window(),rows:Vec::new(),skipped:true})},
  Ok(checker_expression_visit::CurrentEvaluation::Evaluated)=>{let bytes=out.capacity().checked_mul(std::mem::size_of::<Diagnostic>()).and_then(|base|out.iter().try_fold(base,|sum,row|sum.checked_add(row.message.capacity())));let Some(bytes)=bytes else{drop(out);work.reconcile(marker,0).map_err(Failure::Operational)?;return Err(oom("current variable retained output geometry overflow"))};work.reconcile(marker,bytes).map_err(Failure::Operational)?;Ok(CurrentUndefinedProduct{code:std::sync::Arc::downgrade(body.syntax().original_code_owner()),window:body.syntax().canonical_window(),rows:out,skipped:false})}
 }
}
