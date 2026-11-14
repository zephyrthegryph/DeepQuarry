//! Complete original Untyped policy using its SAME compiler-owned value proof.
//! No source/header/manifest authority or secondary inference graph lives here.
use crate::{captured_api_pages as fund,captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_raw_file::Config,lint::Site};
use std::{io,path::Path,sync::Arc};
use dm_tree::frontend::{ArchivedBody, BodyArchive, BodySyntaxFailure, CurrentArchivedBody};

/// The existing workspace host alone binds the current Original syntax loan.
/// This callback cannot manufacture a source, or keep the loan after return.
pub trait CurrentBodyLoan {
    fn visit_body<'a>(
        &self, archive: &'a BodyArchive, ordinal: usize,
        consume: &mut dyn for<'p, 'budget> FnMut(
            CurrentArchivedBody<'a, 'p>, &dm_syntax::SettingAdmission<'budget>,
        ) -> Result<(), Failure>,
    ) -> Result<(), Failure>;
}

pub fn body_failure(error: BodySyntaxFailure) -> Failure {
    match error {
        BodySyntaxFailure::Operational(actual) => Failure::Operational(actual),
        BodySyntaxFailure::Syntax(error) => Failure::Unsupported(error.message),
    }
}
fn oom(b:&Budget,m:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m.into()))}
pub struct UntypedData{sites:Vec<Site>,source_text:Vec<String>}
impl UntypedData{pub fn metadata(&self)->&'static crate::lint::Meta{crate::untyped_policy_metadata::metadata()}pub fn sites(&self)->&[Site]{&self.sites}pub fn source_text(&self)->&[String]{&self.source_text}pub fn notes(&self)->&[String]{&[]}pub fn allow_used(&self)->&[crate::lint::AllowUse]{&[]}pub fn allow_source_digest(&self,_:&str)->Option<&[u8;20]>{None}}
struct Work<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>,peak:usize,bodies:Option<&'a dyn CurrentBodyLoan>}
impl dm_analysis::policy_body_demand::WorkspaceWork for Work<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{fund::checked(self.budget,self.poll)}fn retain(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|m|oom(self.budget,m))}fn temporary(&mut self,bytes:usize)->Result<(),Failure>{if bytes>self.peak{self.budget.charge(bytes-self.peak).map_err(|m|oom(self.budget,m))?;self.peak=bytes;}Ok(())}fn overflow(&mut self)->Failure{oom(self.budget,"untyped workspace geometry overflow")}fn allocation_failed(&mut self)->Failure{oom(self.budget,"untyped workspace allocation refused")}fn body<'a>(&mut self,archive:&'a dm_tree::frontend::BodyArchive,ordinal:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{fund::checked(self.budget,self.poll)?;if self.bodies.is_some(){return Err("canonical Untyped finding pass cannot use compatibility BODY".into())}archive.parse_checked(ordinal).map_err(body_failure)}}

impl dm_analysis::untyped_native::CurrentFindingWork for Work<'_> {
    fn with_current_body<'a>(
        &mut self, archive: &'a BodyArchive, ordinal: usize,
        use_body: impl for<'p> FnOnce(
            &mut Self, CurrentArchivedBody<'a, 'p>, &dm_syntax::SettingAdmission<'_>,
        ) -> Result<(), Failure>,
    ) -> Result<(), Failure> {
        fund::checked(self.budget, self.poll)?;
        let lender = self.bodies.ok_or("canonical Untyped finding pass requires its actual BODY lender")?;
        let mut use_body = Some(use_body);
        lender.visit_body(archive, ordinal, &mut |body, admission| {
            let once = use_body.take().ok_or("canonical Untyped BODY loan delivered twice")?;
            once(self, body, admission)
        })?;
        if use_body.is_some() {
            return Err("canonical Untyped BODY lender omitted its actual body".into());
        }
        fund::checked(self.budget, self.poll)
    }

    fn syntax_failure(&mut self, error: BodySyntaxFailure) -> Failure {
        body_failure(error)
    }
}
struct Phase{budget:Arc<Budget>,ok:bool}impl Drop for Phase{fn drop(&mut self){if !self.ok{self.budget.keep_failed_scratch()}}}
pub fn collect_from_pages(inputs:&dm_analysis::policy_inputs::PolicyInputs,value_input:&Arc<dm_analysis::value_query::ArchiveValueInput>,proof:Arc<dm_analysis::value_query::ArchiveValueProof>,manifest:crate::captured_untyped::ManifestRead<'_>,root_path:&Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,config:&Config,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,bodies:Option<&dyn CurrentBodyLoan>)->Result<UntypedData,Failure>{
 fund::checked(root,poll)?;
 if value_input.requires_canonical_bodies() != bodies.is_some() {
     return Err("Untyped value and finding BODY roles differ".into());
 }
 let mut phase=Phase{budget:Budget::scoped_temporaries(root).map_err(|m|oom(root,m))?,ok:false};let pending=(||{
 let empty=crate::scopes::LintScope::default();let scope=config.borrowed_report_scope("untyped","").unwrap_or(&empty);let mut work=crate::captured_allow_annotations::Operation{budget:&phase.budget,poll};let mut expected=Vec::new();for ty in scope.list("exempt_types"){crate::key_policy_control::row(&mut work,&mut expected)?;expected.push(crate::key_policy_control::own(&mut work,ty)?);}dm_analysis::checker_order::sort_policy_data(&mut expected,&mut|a,b|->Result<std::cmp::Ordering,Failure>{fund::checked(&phase.budget,poll)?;Ok(a.cmp(b))})?;expected.dedup();if !Arc::ptr_eq(value_input.archive(),inputs.archive())||value_input.exempt_types()!=expected.as_slice(){return Err("untyped actual archive/exemption proof owner differs".into())}inputs.archive().tree().checker_builtin_profile().ok_or("untyped native schemas need certified fixed builtin ancestry")?;let mut proof_work=Work{budget:&phase.budget,poll,peak:0,bodies:None};let values=dm_analysis::value_program::Values::from_archive_input_using(value_input,proof,&mut proof_work)?;
 let mut retained=crate::captured_allow_annotations::Operation{budget:&phase.budget,poll};let order=crate::untyped_policy_schemas::order_from_original(manifest,&mut retained)?;let mut events=Vec::new();if !pages.for_each(&mut|relative,views|{fund::checked(&phase.budget,poll)?;if !crate::captured_raw_file::is_code_dm(relative){return Err("untyped schema source escaped unexempt CODE".into())}let file=views.source_file()?;if file.rel!=relative{return Err("untyped original schema path differs".into())}let mut temporary=crate::captured_allow_annotations::Operation{budget:views.allocation_budget(&phase.budget),poll};crate::untyped_policy_schemas::read_file(file,&mut events,&mut retained,&mut temporary)?;Ok(true)})?{return Err("untyped schema phase stopped before actual unexempt CODE EOF".into())}let schemas=crate::untyped_policy_schemas::finish(events,&order,&mut retained)?;
 let mut native=Work{budget:&phase.budget,poll,peak:0,bodies};
 let project = |anchor,source| crate::captured_untyped::project_origin(inputs,anchor,source);
 let rows = if bodies.is_some() {
     dm_analysis::untyped_native::current_findings_workspace_using(
         inputs.archive(), &values, &schemas, root_path, value_input.exempt_types(),
         |file| scope.exempt(file), project, &mut native,
     )?
 } else {
     dm_analysis::untyped_native::archived_findings_workspace_using(
         inputs.archive(), &values, &schemas, root_path, value_input.exempt_types(),
         |file| scope.exempt(file), project, &mut native,
     )?
 };
 let mut texts=Vec::new();fund::reserve_append(&phase.budget,poll,&mut texts,rows.len())?;for _ in &rows{texts.push(None);}if !pages.for_each(&mut|relative,views|{fund::checked(&phase.budget,poll)?;if !crate::captured_raw_file::is_code_dm(relative)||scope.exempt(relative){return Err("untyped report source escaped selected CODE".into())}let file=views.source_file()?;if file.rel!=relative{return Err("untyped original report path differs".into())}let raw=file.raw();for(i,row)in rows.iter().enumerate(){fund::checked(&phase.budget,poll)?;if row.file!=relative{continue}if texts[i].is_some()||row.line==0||row.line>raw.num_lines(){return Err("untyped actual original declaration source is missing or repeated".into())}let text=raw.line(row.line);phase.budget.charge(text.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||oom(root,"untyped source text geometry overflow"))?).map_err(|m|oom(root,m))?;texts[i]=Some(crate::util::normalize_ws(text));}Ok(true)})?{return Err("untyped report phase stopped before actual selected CODE EOF".into())}
 let mut data=UntypedData{sites:Vec::new(),source_text:Vec::new()};for(row,text)in rows.into_iter().zip(texts){fund::checked(root,poll)?;let text=text.ok_or("untyped finding lacks actual original declaration source loan")?;fund::row(root,poll,&mut data.sites)?;data.sites.push(Site{rule:fund::own(root,poll,row.rule.name())?,rel:fund::own(root,poll,&row.file)?,line:u32::try_from(row.line).map_err(|_|oom(root,"untyped declaration line overflow"))?,msg:fund::own(root,poll,&row.message)?,key:String::new(),ident:fund::own(root,poll,&row.identity)?});fund::row(root,poll,&mut data.source_text)?;data.source_text.push(fund::own(root,poll,&text)?);}fund::checked(root,poll)?;Ok::<_,Failure>(data)
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}fund::checked(root,poll)?;phase.ok=pending.is_ok();drop(phase);pending
}

#[path="captured_schema_proposals.rs"]
pub mod schema_proposals;
