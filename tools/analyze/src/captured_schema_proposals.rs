//! Genuine current schema proposal report over the existing untyped raw/source proof.
//! No independent parser, source reader, writer, classification or completion flag.
use super::*;
/// Payload drops before the original admitted operation credit. This is owned DATA,
/// not an archive/current-source capability and cannot construct a query.
pub struct Data { proposals:dm_analysis::untyped_native::SchemaProposalData, _retained:Arc<Budget> }
impl Data {
 pub fn rows(&self)->&[dm_analysis::untyped_native::SchemaProposalRow]{self.proposals.rows()}
 pub fn write_text(&self,poll:&dyn Fn()->io::Result<()>,out:&mut dyn io::Write)->io::Result<()>{self.proposals.write_text(poll,out)}
}
pub fn collect_from_pages(inputs:&dm_analysis::policy_inputs::PolicyInputs,value_input:&Arc<dm_analysis::value_query::ArchiveValueInput>,proof:Arc<dm_analysis::value_query::ArchiveValueProof>,manifest:crate::captured_untyped::ManifestRead<'_>,root_path:&Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,config:&Config,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,bodies:Option<&dyn CurrentBodyLoan>)->Result<Data,Failure>{
 fund::checked(root,poll)?;
 if !value_input.requires_canonical_bodies() || bodies.is_none() {
     return Err("schema proposal requires actual canonical value and finding BODY lenders".into());
 }
 let mut phase=Phase{budget:Budget::scoped_temporaries(root).map_err(|m|oom(root,m))?,ok:false};let pending=(||{
 let empty=crate::scopes::LintScope::default();let scope=config.borrowed_report_scope("untyped","").unwrap_or(&empty);let mut work=crate::captured_allow_annotations::Operation{budget:&phase.budget,poll};let mut expected=Vec::new();for ty in scope.list("exempt_types"){crate::key_policy_control::row(&mut work,&mut expected)?;expected.push(crate::key_policy_control::own(&mut work,ty)?);}dm_analysis::checker_order::sort_policy_data(&mut expected,&mut|a,b|->Result<std::cmp::Ordering,Failure>{fund::checked(&phase.budget,poll)?;Ok(a.cmp(b))})?;expected.dedup();if !Arc::ptr_eq(value_input.archive(),inputs.archive())||value_input.exempt_types()!=expected.as_slice(){return Err("untyped actual archive/exemption proof owner differs".into())}inputs.archive().tree().checker_builtin_profile().ok_or("untyped native schemas need certified fixed builtin ancestry")?;let mut proof_work=Work{budget:&phase.budget,poll,peak:0,bodies:None};let values=dm_analysis::value_program::Values::from_archive_input_using(value_input,proof,&mut proof_work)?;
 let mut retained=crate::captured_allow_annotations::Operation{budget:&phase.budget,poll};let order=crate::untyped_policy_schemas::order_from_original(manifest,&mut retained)?;let mut events=Vec::new();if !pages.for_each(&mut|relative,views|{fund::checked(&phase.budget,poll)?;if !crate::captured_raw_file::is_code_dm(relative){return Err("untyped schema source escaped unexempt CODE".into())}let file=views.source_file()?;if file.rel!=relative{return Err("untyped original schema path differs".into())}let mut temporary=crate::captured_allow_annotations::Operation{budget:views.allocation_budget(&phase.budget),poll};crate::untyped_policy_schemas::read_file(file,&mut events,&mut retained,&mut temporary)?;Ok(true)})?{return Err("untyped schema phase stopped before actual unexempt CODE EOF".into())}let schemas=crate::untyped_policy_schemas::finish(events,&order,&mut retained)?;
 let mut native=Work{budget:&phase.budget,poll,peak:0,bodies};
 let project = |anchor,source| crate::captured_untyped::project_origin(inputs,anchor,source);
 let proposals=dm_analysis::untyped_native::current_schema_proposals_workspace_using(inputs.archive(),&values,&schemas,root_path,value_input.exempt_types(),|file|scope.exempt(file),project,&mut native)?;
 // As for Untyped, actual selected original declaration files must be lent and
 // both raw passes reach genuine EOF before any report callback. No text guessing.
 let mut seen=Vec::new();fund::reserve_append(&phase.budget,poll,&mut seen,proposals.rows().len())?;for _ in proposals.rows(){seen.push(false);}
 if !pages.for_each(&mut|relative,views|{
  fund::checked(&phase.budget,poll)?;
  if !crate::captured_raw_file::is_code_dm(relative)||scope.exempt(relative){return Err("schema proposal source escaped selected CODE".into())}
  let file=views.source_file()?;if file.rel!=relative{return Err("schema proposal actual original declaration path differs".into())}
  let raw=file.raw();for(i,row)in proposals.rows().iter().enumerate(){fund::checked(&phase.budget,poll)?;if row.file()!=relative{continue}
   if seen[i]||row.line()==0||row.line()>raw.num_lines(){return Err("schema proposal actual original declaration source missing or repeated".into())}seen[i]=true;
  }Ok(true)
 })?{return Err("schema proposal source report phase stopped before actual selected CODE EOF".into())}
 for actual in seen{fund::checked(&phase.budget,poll)?;if !actual{return Err("schema proposal declaration lacks actual raw source loan".into())}}
 fund::checked(root,poll)?;Ok::<_,Failure>(Data{proposals,_retained:Arc::clone(&phase.budget)})
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}fund::checked(root,poll)?;phase.ok=pending.is_ok();drop(phase);pending
}
