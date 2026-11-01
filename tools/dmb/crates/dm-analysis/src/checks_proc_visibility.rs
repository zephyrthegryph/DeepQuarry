//! Pinned private/protected procedure policy over the one evaluated native call walk.
//! Source: SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc
//! dreamchecker lib.rs1191..1200,2190..2215,2407..2417 (GPL-3.0).
use crate::{checks::{Diagnostic,Note,Severity},checker_call_facts::CallableFact,checker_prefix_demand::Demand,policy_body_demand::PolicyFailure};
use dm_ir::{ProcedureIdentity,PackedU128,Resolver,ResolveQuery as Q,ResolvedMeaning as M,SymbolId};
use dm_syntax::Span;
use dm_tree::frontend::{ArchivedBody,BodyArchive};
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Family{Private,Protected,MustCallParent,MustNotOverride,Redefined}
impl Family{pub fn name(self)->&'static str{match self{Self::Private=>"private_proc",Self::Protected=>"protected_proc",Self::MustCallParent=>"must_call_parent",Self::MustNotOverride=>"must_not_override",Self::Redefined=>"redefined_proc"}}}
#[derive(Clone,Copy)]struct Annotation{identity:ProcedureIdentity,at:Span,enabled:bool}
pub(crate) struct Row{pub(crate) diagnostic:Diagnostic,pub(crate) synthetic:bool}
/// Sealed findings tied to the actual immutable archive; reported synthetic
/// locations are DATA from the primary marker, never a source-span authority.
pub struct Findings<'a>{archive:&'a BodyArchive,rows:Vec<Row>}
pub struct Finding<'a>{archive:&'a BodyArchive,row:&'a Row}
pub enum ReportedPoint{Source(dm_tree::frontend::SourceNoteOrigin),ParserSynthetic}
impl ReportedPoint{pub fn coordinates(&self)->(&std::path::Path,usize,usize){match self{Self::Source(point)=>(point.path.as_path(),point.line,point.byte_column),Self::ParserSynthetic=>(std::path::Path::new("(unknown)"),0,0)}}}
impl<'a> Findings<'a>{pub(crate) fn from_rows(archive:&'a BodyArchive,rows:Vec<Row>)->Self{Self{archive,rows}}pub fn iter(&self)->impl ExactSizeIterator<Item=Finding<'_>>{self.rows.iter().map(|row|Finding{archive:self.archive,row})}}
impl Finding<'_>{pub fn diagnostic(&self)->&Diagnostic{&self.row.diagnostic}pub fn registration_tag(&self)->Option<&'static str>{(!matches!(self.row.diagnostic.family,"procedure_redeclaration"|"bad_keyword_argument"|"non_keyword_after_keyword"|"filter_call"|"catch_parameter_count"|"static_reference")).then_some(self.row.diagnostic.family)}pub fn is_parser_synthetic(&self)->bool{self.row.synthetic}pub fn reported_point(&self)->Result<ReportedPoint,String>{if self.row.synthetic{Ok(ReportedPoint::ParserSynthetic)}else{self.archive.source_note_point(self.row.diagnostic.span.start).map(ReportedPoint::Source)}}}
pub(crate) struct Access<'a>{archive:&'a BodyArchive,caller:ProcedureIdentity,family:Family,severity:Severity,rows:Vec<Row>,calls_parent:bool,emit:bool}
impl<'a> Access<'a>{
 /// Reuse private/protected pre-argument transitions without selecting a
 /// per-body finding family. The whole keyword fold owns its final rows.
 pub(crate) fn for_keyword_calls(archive:&'a BodyArchive,body:&ArchivedBody<'_>)->Result<Self,String>{let mut value=Self::new(archive,body,Family::Private,Severity::Disabled)?;value.emit=false;Ok(value)}

 pub(crate) fn new(archive:&'a BodyArchive,body:&ArchivedBody<'_>,family:Family,severity:Severity)->Result<Self,String>{let caller=archive.callables().identity_for_member(body.occurrence().member).ok_or("procedure visibility caller identity unavailable")?;Ok(Self{archive,caller,family,severity,rows:Vec::new(),calls_parent:false,emit:true})}
 fn inherited<D:Demand>(&self,fact:&CallableFact,index:usize,resolver:&(impl Resolver+?Sized),profile:PackedU128,demand:&D)->Result<Option<Annotation>,D::Error>{
  let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|format!("procedure directive hop catalog: {e:?}"))?;if catalog.profile!=profile{return Err("procedure directive hop profile differs from actual catalog".into())}
  // An acyclic predecessor path cannot contain more distinct source callables
  // plus builtin declarations than these actual issued immutable inventories.
  // Repeated nodes exhaust the same cardinality without per-call heap scratch.
  let mut remaining=checked_predecessor_cardinality(self.archive.callables().members().len(),catalog.declarations.len())?;
  let mut target=Some(crate::checker_effects::callable_target(self.archive.tree(),profile,fact)?);
  while let Some(current)=target{demand.checkpoint()?;remaining=remaining.checked_sub(1).ok_or("procedure visibility directive predecessor cycle")?;if let crate::checker_effects::EffectTarget::Source(identity)=current{let own=crate::checks_directive_binding::accepted_own_using(self.archive,identity,demand)?;if let Some(accepted)=own[index]{return Ok(Some(Annotation{identity,at:accepted.at,enabled:accepted.enabled}))}}target=match current{crate::checker_effects::EffectTarget::Source(identity)=>{let member=self.archive.callables().members().iter().copied().find(|member|self.archive.callables().identity_for_member(*member)==Some(identity)).ok_or("source annotation predecessor has no actual body member")?;crate::checks_parent_call::source_annotation_predecessor(self.archive.tree(),member,resolver,profile)?.map(crate::checker_effects::EffectTarget::Source)},crate::checker_effects::EffectTarget::Builtin(_)=>crate::checker_effects::original_target_parent_using(self.archive,profile,resolver,current,&mut||demand.checkpoint())?};
  }Ok(None)
 }

 fn display<D:Demand>(&self,identity:ProcedureIdentity,demand:&D)->Result<crate::checker_callable_display::CallableDisplay<'a>,D::Error>{
  let tree=self.archive.tree();let owner=tree.lookup_type(identity.owner).ok_or("visibility display owner absent")?;for member in tree.type_node(owner).ok_or("visibility display owner unavailable")?.members.iter(){demand.checkpoint()?;let node=tree.member(*member).ok_or("visibility display member unavailable")?;if node.name==identity.name&&matches!(node.kind,dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb)&&(node.kind==dm_tree::MemberKind::Verb)!=identity.verb{return Err("procedure visibility display needs original unified proc/verb version chronology".into())}}
  crate::checker_callable_display::original(tree,identity,|_|Ok::<(),D::Error>(()),&mut||demand.checkpoint())
 }
 fn diagnostic<D:Demand>(&mut self,at:Option<Span>,expression:Span,annotation:Annotation,protected:bool,override_parent:bool,demand:&D)->Result<(),D::Error>{
  if !self.emit||self.family!=(if protected{Family::Protected}else{Family::Private}){return Ok(())}demand.checkpoint()?;let tree=self.archive.tree();let prohibited=self.display(annotation.identity,demand)?;
  let message=if override_parent{format!("proc overrides private parent, prohibited by {prohibited}")}else{let caller=self.display(self.caller,demand)?;if protected{format!("{caller} attempting to call protected proc {prohibited}")}else{format!("{caller} attempting to call private proc {prohibited}, types do not match")}};
  let headers=self.archive.callable_header_source();let source=headers.reported_source_point(annotation.at.start)?;let explanation=if protected{"prohibited by this protected_proc annotation"}else{"prohibited by this private_proc annotation"};
  let note=if let Some(at)=at{crate::checks_directive_binding::original_note_message(source,headers.reported_source_point(at.start)?,explanation)}else{let(path,line,column)=source.reported_coordinates();Note{message:format!("{}:{line}:{column}: {explanation}",path.display()),source:None}};
  self.rows.push(Row{diagnostic:Diagnostic{family:self.family.name(),severity:self.severity,span:at.unwrap_or_default(),expression_span:expression,message,notes:vec![note]},synthetic:at.is_none()});Ok(())
 }
 /// The static receiver check belongs to Follow::Call and precedes BOTH the
 /// caller check and argument visitation. Its refusal aborts the call result.
 pub(crate) fn call<D:Demand>(&mut self,fact:&CallableFact,receiver:SymbolId,member_follow:bool,at:Option<Span>,expression:Span,resolver:&(impl Resolver+?Sized),profile:PackedU128,demand:&D)->Result<bool,D::Error>{
  let private=self.inherited(fact,2,resolver,profile,demand)?;
  if member_follow{
   if let Some(annotation)=private{if annotation.enabled&&receiver!=annotation.identity.owner{self.diagnostic(at,expression,annotation,false,false,demand)?;return Ok(true)}}
   if let Some(annotation)=self.inherited(fact,3,resolver,profile,demand)?{let query=Q::Ancestry(self.caller.owner);let expected=Resolver::resolve(self.archive.tree(),query);if resolver.resolve(query)!=expected{return Err("procedure visibility caller ancestry differs from issued source".into())}let M::Symbols(ancestors)=expected else{return Err("procedure visibility caller ancestry unavailable".into())};if annotation.enabled&&!ancestors.contains(&annotation.identity.owner){self.diagnostic(at,expression,annotation,true,false,demand)?;}}
  }
  // visit_call has a second, lexical-caller check. Unlike Follow::Call this
  // emits a finding and still evaluates the arguments in their original order.
  if let Some(annotation)=private{if annotation.enabled&&self.caller.owner!=annotation.identity.owner{self.diagnostic(at,expression,annotation,false,false,demand)?;}}
  Ok(false)
 }

 pub(crate) fn explicit_fact<D:Demand>(&self,parent:bool,resolver:&(impl Resolver+?Sized),profile:PackedU128,demand:&D)->Result<Option<CallableFact>,D::Error>{
  demand.checkpoint()?;let current=crate::checker_effects::EffectTarget::Source(self.caller);let target=if parent{crate::checker_effects::original_target_parent_using(self.archive,profile,resolver,current,&mut||demand.checkpoint())?}else{Some(current)};
  target.map(|target|match target{crate::checker_effects::EffectTarget::Source(identity)=>{let query=Q::SourceDeclarationChain{owner:identity.owner,name:identity.name,verb:identity.verb};let expected=Resolver::resolve(self.archive.tree(),query);if resolver.resolve(query)!=expected{return Err("procedure visibility explicit call chain differs from original".into())}let M::Members(rows)=expected else{return Err("procedure visibility explicit source chain absent".into())};let metadata=rows.iter().find_map(|row|match row{M::Declaration{identity:actual,data,..}if *actual==identity=>Some(data.clone()),_=>None}).ok_or("procedure visibility explicit source occurrence absent")?;Ok(CallableFact::Source{identity,metadata})},crate::checker_effects::EffectTarget::Builtin(id)=>self.archive.tree().with_checker_builtin_procedure(id,|row|CallableFact::CheckerBuiltin{declaring_owner:row.owner,name:row.name,metadata:row.metadata.clone()}).map_err(|e|format!("procedure visibility explicit builtin: {e:?}").into())}).transpose()
 }
 fn redefinition_diagnostic<D:Demand>(&mut self,current:dm_tree::MemberId,previous:ProcedureIdentity,demand:&D)->Result<(),D::Error>{
  demand.checkpoint()?;let tree=self.archive.tree();let previous_member=self.archive.callables().members().iter().copied().find(|member|self.archive.callables().identity_for_member(*member)==Some(previous)).ok_or("redefinition previous original header absent")?;let headers=self.archive.callable_header_source();let at=headers.reported_span(current)?;
  let source=headers.reported_point(previous_member)?;let note=crate::checks_directive_binding::original_note_message(source,headers.reported_source_point(at.start)?,"previous definition is here");let owner=tree.symbols().text(self.caller.owner).ok_or("redefinition owner spelling absent")?;let owner=if owner=="/"{"(global)"}else{owner};let name=tree.symbols().text(self.caller.name).ok_or("redefinition name spelling absent")?;
  self.rows.push(Row{diagnostic:Diagnostic{family:self.family.name(),severity:self.severity,span:at,expression_span:at,message:format!("redefining proc {owner}/{name}"),notes:vec![note]},synthetic:false});Ok(())
 }
 pub(crate) fn parent_call(&mut self){self.calls_parent=true;}
 fn inherited_end_diagnostic<D:Demand>(&mut self,at:Span,annotation:Annotation,demand:&D)->Result<(),D::Error>{
  demand.checkpoint()?;let declared=self.display(annotation.identity,demand)?;let(message,explanation)=match self.family{Family::MustNotOverride=>(format!("proc overrides parent, prohibited by {declared}"),"prohibited by this must_not_override annotation"),Family::MustCallParent=>(format!("proc never calls parent, required by {declared}"),"required by this must_call_parent annotation"),_=>return Err("inherited end diagnostic family differs".into())};
  let headers=self.archive.callable_header_source();let note=crate::checks_directive_binding::original_note_message(headers.reported_source_point(annotation.at.start)?,headers.reported_source_point(at.start)?,explanation);
  self.rows.push(Row{diagnostic:Diagnostic{family:self.family.name(),severity:self.severity,span:at,expression_span:at,message,notes:vec![note]},synthetic:false});Ok(())
 }
 pub(crate) fn finish<D:Demand>(mut self,resolver:&(impl Resolver+?Sized),profile:PackedU128,demand:&D)->Result<Vec<Row>,D::Error>{
  if matches!(self.family,Family::Private|Family::MustNotOverride|Family::MustCallParent|Family::Redefined){let current=self.archive.callables().members().iter().copied().find(|member|self.archive.callables().identity_for_member(*member)==Some(self.caller)).ok_or("procedure visibility caller member absent")?;
   if crate::checks_parent_call::parent_fact_in_profile_using(self.archive.tree(),current,resolver,Some(profile),&mut||demand.checkpoint())?.has_parent{
    let fact=CallableFact::Source{identity:self.caller,metadata:match Resolver::resolve(self.archive.tree(),Q::SourceDeclarationChain{owner:self.caller.owner,name:self.caller.name,verb:self.caller.verb}){M::Members(rows)=>rows.iter().find_map(|row|match row{M::Declaration{identity,data,..}if *identity==self.caller=>Some(data.clone()),_=>None}).ok_or("procedure visibility exact caller metadata absent")?,_=>return Err("procedure visibility caller source chain unavailable".into())}};
    if self.family==Family::Redefined{if let Some(CallableFact::Source{identity:previous,..})=self.explicit_fact(true,resolver,profile,demand)?{if previous.owner==self.caller.owner&&self.inherited(&fact,7,resolver,profile,demand)?.is_none(){self.redefinition_diagnostic(current,previous,demand)?;}}}else{
    let index=match self.family{Family::Private=>2,Family::MustNotOverride=>0,Family::MustCallParent=>1,_=>unreachable!()};
    if let Some(annotation)=self.inherited(&fact,index,resolver,profile,demand)?{let emit=annotation.enabled&&match self.family{Family::Private|Family::MustNotOverride=>annotation.identity!=self.caller,Family::MustCallParent=>!self.calls_parent,_=>false};if emit{let at=self.archive.callable_header_source().reported_span(current)?;if self.family==Family::Private{self.diagnostic(Some(at),at,annotation,false,true,demand)?;}else{self.inherited_end_diagnostic(at,annotation,demand)?;}}}
    }
   }
  }
  demand.checkpoint()?;Ok(self.rows)
 }

}
/// Checked source family; this grants no ordinary compiler acceptance or full
/// checker parity. Existing scanner/diagnostic Vec allocation baselines remain.
pub fn archived_checked<'a>(archive:&'a BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,family:Family,severity:Severity,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Findings<'a>,PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;if !body.belongs_to(archive)||resolver.source_owner()!=Some(std::ptr::from_ref(archive.tree()).cast()){return Err("procedure visibility requires this exact archive/resolver owner".into())}archive.tree().validate_checker_builtin_profile(profile).map_err(|e|format!("procedure visibility profile: {e:?}"))?;if severity==Severity::Disabled{return Ok(Findings{archive,rows:Vec::new()})}
 let pending=crate::checker_expression_visit::procedure_visibility_archived(archive,body,resolver,profile,family,severity,checkpoint).map(|rows|Findings{archive,rows});if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
}
fn checked_predecessor_cardinality(source:usize,builtins:usize)->Result<usize,&'static str>{source.checked_add(builtins).ok_or("procedure directive predecessor inventory overflow")}
#[cfg(test)]mod predecessor_cardinality_tests{use super::*;#[test]fn actual_inventory_bound_overflow_refuses_without_wrapping_or_allocation(){assert!(checked_predecessor_cardinality(usize::MAX,1).is_err());assert_eq!(checked_predecessor_cardinality(usize::MAX,0).unwrap(),usize::MAX);assert_eq!(checked_predecessor_cardinality(0,0).unwrap(),0);}}

/// Original parser companion only: same-owner repeated source Proc/Verb formal.
/// Native inherited-declaration restrictions are deliberately not reported as
/// original errors. No ordinary compiler admission is granted by this loan.
pub fn declaration_redeclaration_checked<'a>(archive:&'a BodyArchive,ordinal:usize,receipt:&dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Findings<'a>,PolicyFailure>{
 let pending=(||{checkpoint().map_err(PolicyFailure::Operational)?;let tree=archive.tree();if !receipt.authenticates(tree){return Err("procedure redeclaration receipt belongs to another source tree".into())}let body=archive.occurrences().get(ordinal).ok_or("procedure redeclaration source ordinal absent")?;if archive.callables().ordinal(body.member)!=Some(ordinal)||tree.declarations().get(body.declaration.0 as usize)!=Some(&dm_tree::Target::Member(body.member)){return Err("procedure redeclaration exact source occurrence differs".into())}let node=tree.member(body.member).ok_or("procedure redeclaration member absent")?;let owner=tree.type_node(node.owner).ok_or("procedure redeclaration owner absent")?.path;
 if node.definition!=dm_tree::DefinitionMode::Declare||!matches!(node.kind,dm_tree::MemberKind::Proc|dm_tree::MemberKind::Verb)||!receipt.errors().iter().any(|error|matches!(error,dm_tree::TreeError::Duplicate{owner:actual,name,kind}if *actual==owner&&*name==node.name&&*kind==node.kind)){return Ok(Findings{archive,rows:Vec::new()})}
 let mut current=tree.resolve(node.owner,node.name,node.kind);let mut remaining=tree.declarations().len();let mut first:Option<(dm_tree::OccurrenceId,dm_tree::MemberId)>=None;
 while let Some(member)=current{checkpoint().map_err(PolicyFailure::Operational)?;remaining=remaining.checked_sub(1).ok_or("procedure redeclaration actual source chain cycles")?;let candidate=tree.member(member).ok_or("procedure redeclaration predecessor absent")?;if candidate.owner!=node.owner{break}if candidate.name!=node.name||candidate.kind!=node.kind{return Err("procedure redeclaration source group differs".into())}if candidate.definition==dm_tree::DefinitionMode::Declare{let position=archive.callables().ordinal(member).ok_or("procedure redeclaration formal lacks original header")?;let occurrence=archive.occurrences().get(position).filter(|row|row.member==member).ok_or("procedure redeclaration formal occurrence differs")?;if first.is_none_or(|(previous,_)|occurrence.declaration.0<previous.0){first=Some((occurrence.declaration,member));}}current=candidate.previous;}
 let(first_ordinal,first_member)=first.ok_or("procedure redeclaration first source formal absent")?;if first_ordinal.0>=body.declaration.0{return Ok(Findings{archive,rows:Vec::new()})}
 let headers=archive.callable_header_source();let at=headers.reported_span(body.member)?;let note=crate::checks_directive_binding::original_note_message(headers.reported_point(first_member)?,headers.reported_source_point(at.start)?,"previous definition");let name=tree.symbols().text(node.name).ok_or("procedure redeclaration name spelling absent")?;let kind=if node.kind==dm_tree::MemberKind::Verb{"verb"}else{"proc"};let diagnostic=Diagnostic{family:"procedure_redeclaration",severity:Severity::Error,span:at,expression_span:at,message:format!("duplicate definition of {kind}/{name}"),notes:vec![note]};Ok(Findings{archive,rows:vec![Row{diagnostic,synthetic:false}]})})();
 if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
}

/// Borrow authentic report coordinates without allocating a second path owner.
pub enum BorrowedReportedPoint<'a>{Source(dm_tree::frontend::BorrowedSourceNoteOrigin<'a>),ParserSynthetic}
impl BorrowedReportedPoint<'_>{pub fn coordinates(&self)->(&std::path::Path,usize,usize){match self{Self::Source(point)=>point.reported_coordinates(),Self::ParserSynthetic=>(std::path::Path::new("(unknown)"),0,0)}}}
impl Finding<'_>{pub fn borrowed_reported_point(&self)->Result<BorrowedReportedPoint<'_>,String>{if self.row.synthetic{Ok(BorrowedReportedPoint::ParserSynthetic)}else{Ok(self.archive.borrowed_source_note_point(self.row.diagnostic.span.start).map(BorrowedReportedPoint::Source)?)}}}
