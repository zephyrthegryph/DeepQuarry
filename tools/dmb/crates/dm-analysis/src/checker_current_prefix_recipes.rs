
//! Complete initial-setting phase over the SAME native insertion/return judges.
//! Neutral recipes carry producer provenance, never heuristic message tags.
use super::*;
use crate::checker_effects::{EffectReportWork,Storage};
use crate::checker_return_expression::CurrentReturnRecipe;
use dm_tree::frontend::{BodySyntaxFailure,CurrentArchivedBody,InitialSettingSource,OriginalBodyDisposition};
use std::{io,sync::{Arc,Weak}};
#[derive(Clone,Copy,Debug)]enum NoteOrigin{Setting(Span),CurrentHeader}
#[derive(Debug)]enum Recipe{GlobalFinal,Unknown(usize),AtDefinition(usize),Invalid(usize),Return(CurrentReturnRecipe),Rejected{ordinal:usize,family:u8,first:Option<NoteOrigin>}}
#[derive(Debug)]pub struct CurrentSettingPrelude{code:dm_tree::frontend::BodyCodeWeak,window:Span,identity:ProcedureIdentity,rows:Vec<Recipe>,skipped:bool}
pub struct CurrentPreludeFinding<'a>{diagnostic:&'a Diagnostic,tag:Option<&'static str>,level:crate::check_policy::DiagnosticSeverity}
impl CurrentPreludeFinding<'_>{pub fn diagnostic(&self)->&Diagnostic{self.diagnostic}pub fn registration_tag(&self)->Option<&'static str>{self.tag}pub fn default_level(&self)->crate::check_policy::DiagnosticSeverity{self.level}}
fn syntax_failure(actual:BodySyntaxFailure)->PolicyFailure{match actual{BodySyntaxFailure::Operational(actual)=>PolicyFailure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>actual.message.into()}}
fn oom()->PolicyFailure{PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"current initial-setting recipe storage denied"))}
fn recipe_message_bytes(recipe:&Recipe)->Option<usize>{match recipe{Recipe::Return(value)=>value.retained_bytes()?.checked_sub(std::mem::size_of::<CurrentReturnRecipe>()),_=>Some(0)}}
impl CurrentSettingPrelude{
 pub fn retained_charge(&self)->Option<usize>{self.rows.capacity().checked_mul(std::mem::size_of::<Recipe>()).and_then(|bytes|self.rows.iter().try_fold(bytes,|sum,row|sum.checked_add(recipe_message_bytes(row)?))).and_then(|n|n.checked_add(std::mem::size_of::<Self>()))}
 pub fn visit_storage(&self,mut visit:impl FnMut(Storage)){self.code.visit_allocation_storage(&mut |address,logical,capacity|visit(crate::checker_effects::Storage::Buffer{owner:"current_prefix.weak_code",address,logical,capacity}));visit(Storage::Buffer{owner:"current_prefix.recipes",address:self.rows.as_ptr()as usize,logical:self.rows.len()*std::mem::size_of::<Recipe>(),capacity:self.rows.capacity()*std::mem::size_of::<Recipe>()});for row in &self.rows{if let Recipe::Return(value)=row{value.visit_storage(&mut visit);}}}
 pub fn fingerprint_parts(&self,mut part:impl FnMut(&[u8])){part(&[self.skipped as u8]);part(&(self.rows.len()as u64).to_le_bytes());for row in &self.rows{match row{Recipe::GlobalFinal=>part(&[0]),Recipe::Unknown(n)=>{part(&[1]);part(&(*n as u64).to_le_bytes());},Recipe::AtDefinition(n)=>{part(&[2]);part(&(*n as u64).to_le_bytes());},Recipe::Invalid(n)=>{part(&[3]);part(&(*n as u64).to_le_bytes());},Recipe::Return(value)=>{part(&[4]);value.fingerprint_parts(&mut part);},Recipe::Rejected{ordinal,family,first}=>{part(&[5,*family]);part(&(*ordinal as u64).to_le_bytes());match first{None=>part(&[0]),Some(NoteOrigin::CurrentHeader)=>part(&[1]),Some(NoteOrigin::Setting(span))=>{part(&[2]);part(&(span.start as u64).to_le_bytes());part(&(span.end as u64).to_le_bytes());}}}}}}
 pub fn visit_current<W:EffectReportWork>(&self,body:&CurrentArchivedBody<'_,'_>,a:&dm_syntax::SettingAdmission<'_>,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>,mut emit:impl FnMut(&Diagnostic)->io::Result<()>)->Result<(),PolicyFailure>{self.visit_current_registered(body,a,work,checkpoint,|row|emit(row.diagnostic()))}
 /// Current delivery only. Full aggregate must call ALL preludes before bodies.
 pub fn visit_current_registered<W:EffectReportWork>(&self,body:&CurrentArchivedBody<'_,'_>,a:&dm_syntax::SettingAdmission<'_>,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>,mut emit:impl FnMut(CurrentPreludeFinding<'_>)->io::Result<()>)->Result<(),PolicyFailure>{
  self.deliver_current(body,a,work,checkpoint,|row,tag,level|{
   emit(CurrentPreludeFinding{diagnostic:&row,tag,level})?;
   Ok(0)
  })
 }
 /// Move rendered rows to the already-admitted effect draft. The caller
 /// reserves its output vector before rendering; only the physical backing
 /// owned by each moved row is retained across the per-row mark.
 pub(crate) fn move_current_registered<W:EffectReportWork>(&self,body:&CurrentArchivedBody<'_,'_>,a:&dm_syntax::SettingAdmission<'_>,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>,mut emit:impl FnMut(Diagnostic,Option<&'static str>,crate::check_policy::DiagnosticSeverity)->io::Result<()>)->Result<(),PolicyFailure>{
  self.deliver_current(body,a,work,checkpoint,|row,tag,level|{
   let retained=current_prelude_diagnostic_backing(&row).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"current prelude retained diagnostic capacity overflows"))?;
   emit(row,tag,level)?;
   Ok(retained)
  })
 }
 pub(crate) fn row_count(&self)->usize{self.rows.len()}
 fn deliver_current<W:EffectReportWork>(&self,body:&CurrentArchivedBody<'_,'_>,a:&dm_syntax::SettingAdmission<'_>,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>,mut emit:impl FnMut(Diagnostic,Option<&'static str>,crate::check_policy::DiagnosticSeverity)->io::Result<usize>)->Result<(),PolicyFailure>{
  checkpoint().map_err(PolicyFailure::Operational)?;if !self.code.matches(body.syntax().original_code_owner())||self.window!=body.syntax().canonical_window(){return Err("initial-setting recipes belong to another canonical body".into())}
  let pending=body.with_initial_setting_prefix(self.identity,a,|prefix|{if self.skipped{if !prefix.settings().is_empty()||prefix.first_non_setting().is_some(){return Err("skipped initial-setting recipe rebound to available code".into())}return Ok(())}
   // Admit actual current formatting geometry before ANY name/path/message Vec
   // is allocated. Syntax reservation remains separate on the real host counter.
   let archive=body.archive_owner();let mut path=0usize;for(p,_)in archive.source_mapping().source_acquisitions(){checkpoint().map_err(PolicyFailure::Operational)?;path=path.max(p.as_os_str().len());}
   let names=body.tree().symbols().text(self.identity.owner).ok_or("prefix owner spelling absent")?.len().checked_add(body.tree().symbols().text(self.identity.name).ok_or("prefix name spelling absent")?.len()).ok_or_else(oom)?;
   for recipe in &self.rows{checkpoint().map_err(PolicyFailure::Operational)?;let mark=work.mark().map_err(PolicyFailure::Operational)?;let result=(||{
    let ordinal=match recipe{Recipe::Unknown(n)|Recipe::AtDefinition(n)|Recipe::Invalid(n)=>Some(*n),Recipe::Rejected{ordinal,..}=>Some(*ordinal),_=>None};let statement=ordinal.map(|n|prefix.settings().get(n).ok_or("current prefix recipe ordinal absent")).transpose()?;
    let width=statement.map_or(0,|s|s.header_span.end.saturating_sub(s.header_span.start));let bound=path.checked_add(names).and_then(|n|n.checked_add(width)).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(4096)).ok_or_else(oom)?;work.reserve(bound).map_err(PolicyFailure::Operational)?;
    let source=prefix.source_body();let row=match recipe{
     Recipe::Invalid(n)=>crate::checker_original_expression_debug::source_invalid_setting_into_body_work(source,*n,work)?,
     Recipe::Return(value)=>value.render(source,work,checkpoint)?,
     Recipe::GlobalFinal=>{let display=crate::checker_callable_display::original(body.tree(),self.identity,|_|Ok::<(),PolicyFailure>(()),&mut||checkpoint().map_err(PolicyFailure::Operational))?;let point=archive.callable_header_source().reported_span(body.occurrence().member)?;Diagnostic{family:Family::Incompatible.name(),severity:Severity::Error,span:point,expression_span:point,message:format!("{display} sets SpacemanDMM_should_not_override, which cannot be set on global procs"),notes:Vec::new()}},
     Recipe::Unknown(_)=>{let mut row=crate::checks_unknown_linter_setting::original_prefix_diagnostic(statement.ok_or("unknown prefix statement absent")?).ok_or("authenticated unknown setting changed classification")?;row.span=source.source_point(row.span)?;row.expression_span=source.source_point(row.expression_span)?;row},
     Recipe::AtDefinition(_)=>{let statement=statement.ok_or("definition prefix statement absent")?;let setting=statement.setting().ok_or("definition prefix setting absent")?;Diagnostic{family:Family::AtDefinition.name(),severity:Severity::Warning,span:source.source_point(statement.header_span)?,expression_span:source.source_point(setting.value.current_span())?,message:format!("Can't define procs {} outside their initial definition",setting.attribute),notes:Vec::new()}},
     Recipe::Rejected{family,first,..}=>{let statement=statement.ok_or("rejected prefix statement absent")?;let name=statement.setting().ok_or("rejected prefix setting absent")?.attribute;let display=crate::checker_callable_display::original(body.tree(),self.identity,|_|Ok::<(),PolicyFailure>(()),&mut||checkpoint().map_err(PolicyFailure::Operational))?;let(family,severity,message)=match family{0=>(Family::Incompatible,Severity::Error,format!("{display} sets {name}, which cannot be set on global procs")),1=>(Family::Disabled,Severity::Warning,format!("{display} sets {name} false, but it cannot be disabled.")),2=>(Family::Duplicate,Severity::Warning,format!("{display} sets {name} twice")),_=>return Err("private prefix rejection family invalid".into())};let mut notes=Vec::new();if matches!(family,Family::Duplicate){let headers=archive.callable_header_source();let origin=match first.ok_or("duplicate recipe first origin absent")?{NoteOrigin::CurrentHeader=>headers.reported_point(body.occurrence().member)?,NoteOrigin::Setting(span)=>headers.reported_source_point(source.source_point(span)?.start)?};let current=headers.reported_source_point(source.source_point(statement.header_span)?.start)?;notes.push(original_note(origin,current));}Diagnostic{family:family.name(),severity,span:source.source_point(statement.header_span)?,expression_span:source.source_point(statement.setting().ok_or("rejected setting absent")?.value.current_span())?,message,notes}},
    };
    // Mutable binding above never evaluates anything. All diagnostic points are
    // genuine current source points by their recipe-specific producer route.
    use crate::check_policy::DiagnosticSeverity as Level;
    let(tag,level)=match recipe{Recipe::GlobalFinal=>(Some("incompatible_directive"),Level::Error),Recipe::Unknown(_)=>{let name=statement.ok_or("unknown prefix statement absent")?.setting().ok_or("unknown prefix setting absent")?.attribute;(name.starts_with("SpacemanDMM_").then_some("unknown_linter_setting"),Level::Warning)},Recipe::AtDefinition(_)|Recipe::Invalid(_)=>(None,Level::Warning),Recipe::Return(_)=>(None,Level::Error),Recipe::Rejected{family:0,..}=>(Some("incompatible_directive"),Level::Error),Recipe::Rejected{family:1,..}=>(Some("disabled_directive"),Level::Warning),Recipe::Rejected{family:2,..}=>(Some("sets_directive_twice"),Level::Warning),_=>return Err("prefix recipe registration absent".into())};
    checkpoint().map_err(PolicyFailure::Operational)?;emit(row,tag,level).map_err(PolicyFailure::Operational)
   })();let retained=match result{Ok(bytes)=>bytes,Err(actual)=>{let cleanup=work.reconcile(mark,0);if matches!(&actual,PolicyFailure::Operational(_)){return Err(actual)}cleanup.map_err(PolicyFailure::Operational)?;return Err(actual)}};work.reconcile(mark,retained).map_err(PolicyFailure::Operational)?;}
   Ok(())
  });match pending{Ok(value)=>value,Err(actual)=>Err(syntax_failure(actual))}
 }
}

pub(crate) fn current_prelude_diagnostic_backing(row:&Diagnostic)->Option<usize>{
 let initial=row.notes.capacity().checked_mul(std::mem::size_of::<crate::checks::Note>())?.checked_add(row.message.capacity())?;
 row.notes.iter().try_fold(initial,|bytes,note|{
  let bytes=bytes.checked_add(note.message.capacity())?;
  match &note.source{
   Some(source)=>bytes.checked_add(std::mem::size_of::<std::path::PathBuf>()+2*std::mem::size_of::<usize>())?.checked_add(source.path.capacity()),
   None=>Some(bytes),
  }
 })
}

pub fn current_setting_prelude<W:EffectReportWork>(body:&CurrentArchivedBody<'_,'_>,resolver:&(impl Resolver+?Sized),a:&dm_syntax::SettingAdmission<'_>,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>)->Result<CurrentSettingPrelude,PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;if resolver.source_owner()!=Resolver::source_owner(body.tree()){return Err("current prefix resolver belongs to another source".into())}
 let archive=body.archive_owner();let roster=archive.callables();let current=body.occurrence().member;let identity=roster.identity_for_member(current).ok_or("current prefix callable issuance absent")?;let skipped=match body.syntax().original_code_disposition().map_err(syntax_failure)?{OriginalBodyDisposition::Available(_)=>false,OriginalBodyDisposition::Skipped(_)=>true};let marker=work.mark().map_err(PolicyFailure::Operational)?;let mut rows=Vec::new();
 let pending=body.with_initial_setting_prefix(identity,a,|prefix|{
  if skipped{return Ok(())}
  for query in[Q::SourceDeclarationChain{owner:identity.owner,name:identity.name,verb:identity.verb},Q::Ancestry(identity.owner)]{checkpoint().map_err(PolicyFailure::Operational)?;if resolver.resolve(query)!=Resolver::resolve(body.tree(),query){return Err("current prefix dependency differs from actual native model".into())}}
  let count=prefix.settings().len().checked_add(1).ok_or_else(oom)?;let peak=count.checked_mul(std::mem::size_of::<Recipe>()).and_then(|n|n.checked_mul(4)).ok_or_else(oom)?;work.reserve(peak).map_err(PolicyFailure::Operational)?;rows.try_reserve_exact(count).map_err(|_|oom())?;if rows.capacity()>count.checked_mul(4).ok_or_else(oom)?{return Err(oom())}
  let headers=OriginalHeaders{roster,current,source:archive.callable_header_source()};let mut sink=|event|{checkpoint().map_err(PolicyFailure::Operational)?;let row=match event{
   PrefixEmission::HeaderGlobalFinal=>Some(Recipe::GlobalFinal),PrefixEmission::Unknown{ordinal}=>Some(Recipe::Unknown(ordinal)),PrefixEmission::AtDefinition{ordinal}=>Some(Recipe::AtDefinition(ordinal)),PrefixEmission::InvalidValue{ordinal}=>Some(Recipe::Invalid(ordinal)),PrefixEmission::ReturnType{ordinal}=>crate::checker_return_expression::current_setting_recipe(prefix.source_body(),resolver,ordinal,work,checkpoint)?.map(Recipe::Return),PrefixEmission::Rejected{ordinal,family,first}=>{let family=match family{Family::Incompatible=>0,Family::Disabled=>1,Family::Duplicate=>2,_=>return Err("native prefix emitted unexpected rejection".into())};let first=first.map(|value|match value{FirstOrigin::Setting(span)=>Ok(NoteOrigin::Setting(span)),FirstOrigin::Header(member)if member==current=>Ok(NoteOrigin::CurrentHeader),_=>Err(PolicyFailure::from("prefix first header belongs to another callable"))}).transpose()?;Some(Recipe::Rejected{ordinal,family,first})}};
   if let Some(row)=row{if rows.len()==rows.capacity(){return Err(oom())}rows.push(row);}Ok(())};
  let ordinary=syntax_using_observed_recipes(prefix.statement_body(),body.tree(),identity,&headers,Family::Duplicate,Severity::Error,&mut||checkpoint().map_err(PolicyFailure::Operational),&mut|_|Ok(()),None,None,Some(&mut sink))?;if !ordinary.is_empty(){return Err("prefix event adapter retained unqualified physical rows".into())}Ok(())
 });let result=match pending{Ok(value)=>value,Err(actual)=>Err(syntax_failure(actual))};if let Err(actual)=result{drop(rows);let cleanup=work.reconcile(marker,0);if matches!(&actual,PolicyFailure::Operational(_)){return Err(actual)}cleanup.map_err(PolicyFailure::Operational)?;return Err(actual)}
 let mut bytes=rows.capacity().checked_mul(std::mem::size_of::<Recipe>()).ok_or_else(oom)?;for row in &rows{bytes=bytes.checked_add(recipe_message_bytes(row).ok_or_else(oom)?).ok_or_else(oom)?;}work.reconcile(marker,bytes).map_err(PolicyFailure::Operational)?;Ok(CurrentSettingPrelude{code:dm_tree::frontend::BodyCodeIdentity::downgrade(body.syntax().original_code_owner()),window:body.syntax().canonical_window(),identity,rows,skipped})
}

#[cfg(test)]#[test]fn actual_weak_code_locator_owner_widths_are_measured(){
 {#[allow(dead_code)]struct Prior{code:std::sync::Weak<dm_tree::frontend::BodyCodeIdentity>,window:Span,identity:ProcedureIdentity,rows:Vec<Recipe>,skipped:bool}
let old=std::mem::size_of::<Prior>();let new=std::mem::size_of::<CurrentSettingPrelude>();eprintln!("WEAK_CODE_OWNER CurrentSettingPrelude prior={old} current={new} delta={}",new as isize-old as isize);assert!(new<=old+std::mem::size_of::<usize>());}
}
