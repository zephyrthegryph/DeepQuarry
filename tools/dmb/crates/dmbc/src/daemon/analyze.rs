//! Explicit partial-policy client over the same resident host and immutable pins.
//! Findings/settings are delivered data; no parser, Tree or source reread exists here.
use crate::{request::{BuildRequest,BuildCommand,BuildOutcome},query_db::WorkspaceCursor};
use super::query::{QueryRequest,QueryReply,SourceQuery};
use dq_analyze::{lint::{Run,Site,AllowUse},scopes::LintScope,policy_finish::{self,Timing},baseline::{SiteText,Mode}};
use serde::{Serialize,Deserialize};
use std::{collections::{BTreeMap,BTreeSet,HashMap,HashSet},error::Error,fs::File,io::{self,Read,Write},path::{Path,PathBuf}};
fn report_metadata(name:&str)->Option<&'static dq_analyze::lint::Meta>{if let Some(policy)=dq_analyze::workspace_fold_policy::Policy::from_name(name){return Some(policy.metadata())}if let Some(policy)=dq_analyze::captured_raw_tree_pages::Policy::from_name(name){return Some(policy.metadata())}match name{"map_edits"=>Some(&dq_analyze::map_edits_policy::META),"silicon_entry"=>Some(&dq_analyze::silicon_entry_policy::META),"lifeforms"=>Some(dq_analyze::lifeforms_policy::metadata()),"sys/dx_reactive"=>Some(dq_analyze::sys_reactive_policy::metadata()),"engine_layering"=>Some(dq_analyze::engine_layering_policy::metadata()),"library_layering"=>Some(dq_analyze::engine_layering_policy::Layer::Library.metadata()),"stored_refs"=>Some(dq_analyze::stored_refs_policy::metadata()),"untyped"=>Some(dq_analyze::untyped_policy_metadata::metadata()),"rel_write_undeclared"=>Some(dq_analyze::rel_write_policy::metadata()),"weak_raw_read"=>Some(dq_analyze::weak_relation_policy::metadata()),"untyped_member"=>Some(dq_analyze::untyped_member_policy::metadata()),"player_link"=>Some(dq_analyze::player_link_policy::metadata()),"requirement_bool"=>Some(dq_analyze::captured_requirement_bool_pages::metadata()),"base_vars"=>Some(dq_analyze::captured_base_vars_pages::metadata()),"init"=>Some(dq_analyze::captured_init_pages::metadata()),"decl"=>Some(dq_analyze::captured_decl_pages::metadata()),"sem/reads"=>Some(dq_analyze::sem_reads_policy::metadata()),"untracked_inputs"=>Some(dq_analyze::untracked_inputs_policy::metadata()),"setter_publishes"=>Some(dq_analyze::setter_publication_policy::metadata()),"sem/keys"=>Some(dq_analyze::keys_policy::metadata()),"sys/hygiene"=>Some(dq_analyze::captured_sys_hygiene_pages::metadata()),"sys/resolvers"=>Some(dq_analyze::captured_sys_resolvers_pages::metadata()),"sys/tables"=>Some(dq_analyze::captured_sys_tables_pages::metadata()),"system_boundary"=>Some(dq_analyze::captured_system_boundary_pages::metadata()),"check_grep"=>Some(dq_analyze::lints::check_grep::native::metadata()),_=>dq_analyze::captured_raw_policy::metadata(name)}}
const GENERIC_REPORT_LINTS:&[&str]=&["actor_forwarding","breakpoint","containment","dcs","door_gates","entity_ids","i7_handler","in_precedence","leftovers","legacy_forms","lifecycle_counts","mouse_override","native_ref_write","engine_internal","organ_slots","qdel_src","reactions_table_proc","ref_text","registry","saved_handle","scheduler","silent_catch","spatial","stance_examine","subsystem_fire","verb_category","sys/sync_sql","lifeform_allows","escape_hatches","sys/contents","sys/damage_reactions","sys/dx_manual_transfer","sys/dx_raw_delay","sys/dx_raw_overlays","sys/dx_review","sys/emag","sys/grants","sys/messages","sys/presentation","sys/topic","sys/usr_use","entry_slots"];
const LIMIT:usize=super::generation::MAX_REPORT_BYTES;
const CONTROL:usize=super::protocol::MAX_FRAME;
fn invalid(message:impl Into<String>)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message.into())}
#[derive(Clone,Copy,Debug,Serialize,Deserialize)]#[serde(rename_all="snake_case")]
pub enum BaselineMode{Update,Seed,Migrate}
impl From<BaselineMode> for Mode{fn from(value:BaselineMode)->Self{match value{BaselineMode::Update=>Self::Update,BaselineMode::Seed=>Self::Seed,BaselineMode::Migrate=>Self::Migrate}}}
#[derive(Clone,Debug,Serialize,Deserialize)]#[serde(deny_unknown_fields)]
pub struct AnalyzeRequest{
 pub build:BuildRequest,pub lints:Vec<String>,#[serde(default)]pub raw:bool,
 #[serde(default)]pub changed:Option<Vec<String>>,#[serde(default)]pub scopes_root:Option<PathBuf>,
 #[serde(default,rename="baselineMode")]pub baseline_mode:Option<BaselineMode>,#[serde(default)]pub ci:bool,
}
impl AnalyzeRequest{
 pub(super) fn validate(&self,baseline:bool)->io::Result<()> {
  if self.lints.as_slice()==["derived_reads"] { return self.validate_derived(baseline); }
  if self.lints.as_slice()==["sem/handlers"] { return self.validate_handlers(baseline); }
  if baseline&&self.lints.as_slice()==["silicon_entry"]{return Err(invalid("silicon_entry supports checks only"))}
  if baseline&&self.lints.as_slice()==["map_edits"]{return Err(invalid("map_edits supports checks only"))}
  let b=&self.build;
  if b.command!=BuildCommand::PrepareQuery||b.no_daemon||b.trace_path.is_some()||b.record_inputs.is_some()||b.replay_inputs.is_some()||b.artifact_directory.is_some()||b.output_store.is_some()||b.source_questions.is_some()||b.diagnostic_declarations{return Err(invalid("Analyze report requires the ordinary resident PrepareQuery route without record/replay/trace or output redirects"))}
  let policy=b.policy_inputs.as_ref().ok_or_else(||invalid("explicit workspace policy intent required"))?;
  let workspace=policy.workspace.as_ref().ok_or_else(||invalid("actual workspace policy intent required"))?;
  if !policy.workspace_generators.is_empty()||!policy.files.is_empty()||!policy.search_folders.is_empty(){return Err(invalid("report intent cannot include generator or fixture roles"))}
  policy.clone().admit()?;super::build_admission::validate(b).map_err(io::Error::other)?;
  if !b.project.is_absolute()||!workspace.root.is_absolute(){return Err(invalid("caller-resolved absolute project and workspace required"))}
  if self.lints.is_empty()||self.lints.len()>dq_analyze::captured_raw_policy::RAW_FILE_LINTS.len()||self.lints.iter().collect::<BTreeSet<_>>().len()!=self.lints.len(){return Err(invalid("explicit unique supported lint list required"))}
  if self.lints.as_slice()==["allow_annotations"] {
      if baseline || policy.analysis_context!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)
          || !crate::policy_request::exact_code_maps_roots(&workspace.root,&workspace.recursive_roots)
      {
          return Err(invalid("allow_annotations requires an explicit Original Analyze check over exactly code and maps"));
      }
  }
  let read_cohort=dq_analyze::native_policy_roster::is_semantic_read_report_cohort(&self.lints);
  if read_cohort&&(baseline||policy.analysis_context!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)){
      return Err(invalid("shared semantic read cohort requires a check in the Original Analyze workspace"));
  }
  for name in &self.lints{if dq_analyze::workspace_fold_policy::Policy::from_name(name).is_none()&&dq_analyze::captured_raw_tree_pages::Policy::from_name(name).is_none()&&!GENERIC_REPORT_LINTS.contains(&name.as_str())&&name!="deadline_polling"&&!["sys/hygiene","sys/resolvers","sys/tables","system_boundary","sem/keys","check_grep","sem/reads","untracked_inputs","setter_publishes","sys/dx_reactive","lifeforms","decl","init","base_vars","requirement_bool","player_link","untyped_member","silicon_entry","map_edits","weak_raw_read","rel_write_undeclared","untyped","stored_refs","engine_layering","library_layering"].contains(&name.as_str()){return Err(invalid(format!("policy {name} lacks the complete public report evidence/hook adapter")))}let meta=report_metadata(name).ok_or_else(||invalid("unknown report metadata"))?;if matches!(meta.policy,dq_analyze::lint::Policy::Custom)&&name!="deadline_polling"&&name!="system_boundary"&&name!="check_grep"&&name!="doc_snippets"{return Err(invalid("custom report hooks require explicit captured evidence"))}}
  if self.lints.iter().any(|name|dq_analyze::workspace_fold_policy::Policy::from_name(name).is_some()||dq_analyze::captured_raw_tree_pages::Policy::from_name(name).is_some()||["sys/hygiene","sys/resolvers","sys/tables","system_boundary","sem/keys","check_grep","sem/reads","untracked_inputs","setter_publishes","sys/dx_reactive","lifeforms","decl","init","base_vars","requirement_bool","player_link","untyped_member","silicon_entry","map_edits","weak_raw_read","rel_write_undeclared","untyped","stored_refs","engine_layering","library_layering"].contains(&name.as_str()))&&self.lints.len()!=1&&!read_cohort{return Err(invalid("whole-fold report currently requires an exclusive explicit selection"))}
  let selected_deadline=self.lints.iter().any(|name|name=="deadline_polling");
  let admitted=policy.clone().admit()?;let selected_grep=self.lints.as_slice()==["check_grep"];let expected=if read_cohort{
      use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
      &[Q::SemReads,Q::UntrackedInputs,Q::SetterPublishes][..]
  }else if self.lints.as_slice()==["op_order"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::OpOrder][..]}else if self.lints.as_slice()==["ui_actions"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::UiActions][..]}else if self.lints.as_slice()==["engine_layering"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering][..]}else if self.lints.as_slice()==["library_layering"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::LibraryLayering][..]}else if self.lints.as_slice()==["notice_publisher"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::NoticePublisher][..]}else if self.lints.as_slice()==["ownership"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Ownership][..]}else if self.lints.as_slice()==["doc_snippets"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippets][..]}else if self.lints.as_slice()==["stored_refs"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::StoredRefs][..]}else if self.lints.as_slice()==["untyped"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Untyped][..]}else if self.lints.as_slice()==["rel_write_undeclared"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::RelWriteUndeclared][..]}else if self.lints.as_slice()==["weak_raw_read"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::WeakRawRead][..]}else if self.lints.as_slice()==["map_edits"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::MapEdits][..]}else if self.lints.as_slice()==["silicon_entry"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::SiliconEntry][..]}else if self.lints.as_slice()==["untyped_member"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::UntypedMember][..]}else if self.lints.as_slice()==["player_link"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::PlayerLink][..]}else if self.lints.as_slice()==["requirement_bool"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::RequirementBool][..]}else if self.lints.as_slice()==["base_vars"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars][..]}else if self.lints.as_slice()==["init"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Init][..]}else if self.lints.as_slice()==["decl"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Decl][..]}else if self.lints.as_slice()==["tracked"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Tracked][..]}else if self.lints.as_slice()==["tracked_tests"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::TrackedTests][..]}else if self.lints.as_slice()==["sem/reads"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::SemReads][..]}else if self.lints.as_slice()==["untracked_inputs"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::UntrackedInputs][..]}else if self.lints.as_slice()==["lifeforms"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Lifeforms][..]}else if self.lints.as_slice()==["sys/dx_reactive"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive][..]}else if self.lints.as_slice()==["setter_publishes"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::SetterPublishes][..]}else if self.lints.as_slice()==["sem/keys"]{&[crate::policy_request::WorkspaceAuxiliaryQuestion::Keys][..]}else if selected_grep{if baseline{&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrepBaseline][..]}else{&[crate::policy_request::WorkspaceAuxiliaryQuestion::CheckGrep][..]}}else if selected_deadline&&!baseline{&[crate::policy_request::WorkspaceAuxiliaryQuestion::DeadlinePollingAllowlist][..]}else{&[][..]};if admitted.workspace_auxiliary()!=expected{return Err(invalid("selected report requires exactly its admitted fixed auxiliary questions"))}
  if self.lints.iter().any(|name|matches!(name.as_str(),"check_grep"|"sem/reads"|"untracked_inputs"|"setter_publishes"|"sys/dx_reactive"|"lifeforms"|"tracked"|"tracked_tests"|"decl"|"init"|"base_vars"|"requirement_bool"|"player_link"|"untyped_member"|"silicon_entry"|"map_edits"|"weak_raw_read"|"rel_write_undeclared"|"untyped"|"stored_refs"|"engine_layering"|"library_layering"))&&admitted.analysis_context().is_none(){return Err(invalid("selected semantic report requires its actual Original analysis context"))}
  if matches!(self.lints.as_slice(),[name]if matches!(name.as_str(),"doc_snippets"|"ownership"|"notice_publisher"|"ui_actions"|"op_order"))&&admitted.analysis_context()!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){return Err(invalid("raw-only report requires its actual original source purpose"))}
  if baseline!=self.baseline_mode.is_some()||baseline&&(self.raw||self.changed.is_some()){return Err(invalid("baseline requires baselineMode and cannot silently ignore raw/changed options"))}
  if let Some(root)=&self.scopes_root{if !root.is_absolute(){return Err(invalid("scopes_root must be absolute"))}}
  if baseline&&workspace.configuration!=self.scopes_root.as_ref().unwrap_or(&workspace.root).join("tools/ci/lint_scopes.toml"){return Err(invalid("baseline ceiling target must match the actually captured configuration path"))}
  if self.changed.as_ref().is_some_and(|paths|paths.iter().any(|p|p.is_empty()||Path::new(p).is_absolute()||p.split(['/', '\\']).any(|part|part==".."))){return Err(invalid("changed files must be workspace-relative paths"))}
  Ok(())
 }
}
#[derive(Default)]struct Admission{used:usize,denied:bool}
impl Admission{fn add(&mut self,bytes:usize)->io::Result<()>{match self.used.checked_add(bytes).filter(|n|*n<=LIMIT){Some(next)=>{self.used=next;Ok(())},None=>{self.denied=true;Err(io::Error::new(io::ErrorKind::OutOfMemory,"delivered report data exceeds existing metadata allowance"))}}}fn row<T>(&mut self,strings:usize)->io::Result<()>{match 1024usize.checked_add(std::mem::size_of::<T>()).and_then(|n|n.checked_add(strings)){Some(bytes)=>self.add(bytes),None=>{self.denied=true;Err(io::ErrorKind::OutOfMemory.into())}}}}

impl dq_analyze::key_policy_control::Control for Admission{
 type Error=io::Error;const CHECKED:bool=true;
 // This is source-free delivered-data work. The owned process watchdog bounds
 // the CLI; server request deadlines/cancellation were enforced before delivery.
 fn checkpoint(&mut self)->io::Result<()>{Ok(())}fn reserve(&mut self,bytes:usize)->io::Result<()>{self.add(bytes)}
 fn overflow(&mut self)->io::Error{self.denied=true;io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{self.denied=true;io::ErrorKind::OutOfMemory.into()}
}
struct LintData{doc_blocks:Vec<dq_analyze::doc_snippets_policy::SummaryBlock>,doc_complete:Option<usize>,run:Run,allows:Vec<AllowUse>,scope:LintScope,projection:String}
struct DeadlineData{path:PathBuf,parsed:Option<dq_analyze::lints::deadline_polling::ObservedDeadlineAllowlist>}

struct Delivery{
 pins:(String,String,String),aggregate:Option<String>,total:Option<usize>,offset:usize,done:bool,
 deadline:Option<DeadlineData>,grep_purpose:Option<dq_analyze::lints::check_grep::native::Purpose>,macro_ceiling:Option<i64>,
 roots:Option<Vec<String>>,lints:BTreeMap<String,LintData>,lines:BTreeMap<String,BTreeMap<usize,String>>,digests:BTreeMap<String,String>,admission:Admission,
}
impl SiteText for Delivery{fn site_text(&self,rel:&str,line:usize)->String{self.lines.get(rel).and_then(|lines|lines.get(&line)).expect("all report sites validated before common finish").clone()}}
type ScopeWire=(Vec<String>,Vec<String>,Vec<String>,HashMap<String,Vec<String>>,HashMap<String,BTreeMap<String,String>>,BTreeMap<String,i64>,Vec<String>);
// First pass measures actual decoded strings/rows before the owning tuple parse.
// Standard serde token scratch and allocator geometry retain the existing codec qualification.
struct ScopeMeasure<'a>(&'a mut Admission);
impl<'de> serde::de::DeserializeSeed<'de> for ScopeMeasure<'_>{type Value=();fn deserialize<D:serde::Deserializer<'de>>(self,d:D)->Result<(),D::Error>{d.deserialize_any(self)}}
impl<'de> serde::de::Visitor<'de> for ScopeMeasure<'_>{type Value=();fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("interpreted scope data")}
 fn visit_str<E:serde::de::Error>(self,s:&str)->Result<(),E>{self.0.row::<String>(s.len()).map_err(E::custom)}
 fn visit_i64<E:serde::de::Error>(self,_:i64)->Result<(),E>{Ok(())}fn visit_u64<E:serde::de::Error>(self,_:u64)->Result<(),E>{Ok(())}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut seq:A)->Result<(),A::Error>{while seq.next_element_seed(ScopeMeasure(&mut *self.0))?.is_some(){}Ok(())}
 fn visit_map<A:serde::de::MapAccess<'de>>(self,mut map:A)->Result<(),A::Error>{while map.next_key_seed(ScopeMeasure(&mut *self.0))?.is_some(){map.next_value_seed(ScopeMeasure(&mut *self.0))?;}Ok(())}
}
fn scope_decode(text:&str,admission:&mut Admission)->io::Result<LintScope>{use serde::de::DeserializeSeed;let mut decoder=serde_json::Deserializer::from_str(text);if let Err(actual)=ScopeMeasure(&mut *admission).deserialize(&mut decoder){if admission.denied{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"interpreted scope ownership admission denied"))}return Err(io::Error::other(actual))}decoder.end().map_err(io::Error::other)?;drop(decoder);let(a,b,c,d,e,f,g):ScopeWire=serde_json::from_str(text).map_err(io::Error::other)?;Ok(LintScope{exempt_prefixes:a,exempt_contains:b,exempt_files:c,lists:d,tables:e,ceilings:f,reason_codes:g})}
impl Delivery{
 fn new(pins:(String,String,String))->Self{Self{pins,aggregate:None,total:None,offset:0,done:false,deadline:None,grep_purpose:None,macro_ceiling:None,roots:None,lints:BTreeMap::new(),lines:BTreeMap::new(),digests:BTreeMap::new(),admission:Admission::default()}}
 fn page(&mut self,reply:&QueryReply,request:&QueryRequest)->io::Result<Option<WorkspaceCursor>>{
  if self.done||reply.revision!=self.pins.0||reply.source_revision.as_deref()!=Some(&self.pins.1)||reply.policy_revision.as_deref()!=Some(&self.pins.2){return Err(invalid("report session pins changed or page follows terminal"))}
  super::query::validate_workspace_report_delivery(reply,&request.source_queries)?;
  use dq_analyze::lints::check_grep::native::Purpose;
  let purpose=match request.source_queries.as_slice(){[SourceQuery::NativeWorkspaceCheckGrepReportPage{..}]=>Some(Purpose::Check),[SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{..}]=>Some(Purpose::Baseline),_=>None};
  if self.aggregate.is_some()&&self.grep_purpose!=purpose{return Err(invalid("report purpose changed between pages"))}
  let mut rows=reply.jsonl.lines();let row:serde_json::Value=serde_json::from_str(rows.next().ok_or_else(||invalid("missing report page"))?).map_err(io::Error::other)?;if rows.next().is_some(){return Err(invalid("one exact workspace page required"))}
  let observed_macro=if purpose==Some(Purpose::Check){Some(row["macro_ceiling"].as_i64().filter(|value|*value>=0).ok_or_else(||invalid("missing actual CheckGrep macro observation"))?)}else{None};
  if self.aggregate.is_some()&&self.macro_ceiling!=observed_macro{return Err(invalid("CheckGrep macro observation changed between pages"))}self.grep_purpose=purpose;self.macro_ceiling=observed_macro;
  let total=row["total_items"].as_u64().and_then(|n|usize::try_from(n).ok()).ok_or_else(||invalid("invalid total"))?;let aggregate=row["aggregate_id"].as_str().ok_or_else(||invalid("missing aggregate"))?;
  if self.aggregate.as_deref().is_some_and(|a|a!=aggregate)||self.total.is_some_and(|n|n!=total)||row["offset"].as_u64()!=Some(self.offset as u64){return Err(invalid("aggregate/total/progress changed between report pages"))}
  let root_rows=row["recursive_roots"].as_array().ok_or_else(||invalid("missing recursive roots"))?;
  if let Some(roots)=&self.roots{if roots.len()!=root_rows.len()||roots.iter().zip(root_rows).any(|(a,b)|b.as_str()!=Some(a.as_str())){return Err(invalid("discovery domain changed between pages"))}}else{
   let capacity=root_rows.len().checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<String>())).ok_or(io::ErrorKind::OutOfMemory)?;self.admission.add(capacity)?;
   for value in root_rows{let text=value.as_str().ok_or_else(||invalid("invalid recursive root"))?;self.admission.add(text.len())?;}
   let mut roots=Vec::new();roots.try_reserve_exact(root_rows.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;if roots.capacity()>root_rows.len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}for value in root_rows{roots.push(value.as_str().unwrap().to_owned())}
   self.roots=Some(roots);
  }
  if self.aggregate.is_none(){
   self.admission.row::<String>(aggregate.len())?;
   self.aggregate=Some(aggregate.to_owned());
   self.total=Some(total);
  }
  for pair in row["policy_scopes"].as_array().ok_or_else(||invalid("missing scopes"))?{let name=pair[0].as_str().ok_or_else(||invalid("scope name"))?;let text=pair[1].as_str().ok_or_else(||invalid("scope text"))?;if let Some(old)=self.lints.get(name){if old.projection!=text{return Err(invalid("captured scope changed between pages"))}}else{self.admission.row::<LintData>(name.len()+text.len())?;let scope=scope_decode(text,&mut self.admission)?;self.lints.insert(name.to_owned(),LintData{doc_blocks:Vec::new(),doc_complete:None,run:Run::default(),allows:Vec::new(),scope,projection:text.to_owned()});}}
  for item in row["items"].as_array().ok_or_else(||invalid("missing items"))?{let name=item["lint"].as_str().ok_or_else(||invalid("item lint"))?;let data=self.lints.get_mut(name).ok_or_else(||invalid("unrequested lint"))?;if data.doc_complete.is_some(){return Err(invalid("record follows completed doc summary"))}if !data.doc_blocks.is_empty()&&!matches!(item["kind"].as_str(),Some("doc_block"|"doc_complete")){return Err(invalid("findings follow doc summary phase"))}match item["kind"].as_str(){
   Some("doc_block")=>{if name!="doc_snippets"||data.doc_complete.is_some(){return Err(invalid("unissued or already finished doc summary"))}let block=&item["block"];let bytes=["kind","rel","first"].into_iter().try_fold(0usize,|n,key|n.checked_add(block[key].as_str().map_or(0,str::len))).ok_or(io::ErrorKind::OutOfMemory)?;self.admission.row::<dq_analyze::doc_snippets_policy::SummaryBlock>(bytes)?;self.admission.add(4*std::mem::size_of::<dq_analyze::doc_snippets_policy::SummaryBlock>())?;data.doc_blocks.try_reserve(1).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;data.doc_blocks.push(serde_json::from_value(block.clone()).map_err(io::Error::other)?);},
   Some("doc_complete")=>{let count=item["count"].as_u64().and_then(|n|usize::try_from(n).ok()).ok_or_else(||invalid("invalid doc block count"))?;if name!="doc_snippets"||data.doc_complete.is_some()||count!=data.doc_blocks.len(){return Err(invalid("doc completion does not match all delivered summaries"))}data.doc_complete=Some(count);},
   Some("hard_site")=>{
    if (!matches!(name,"engine_layering"|"sem/keys"|"sem/reads"|"untracked_inputs"|"setter_publishes"|"sys/dx_reactive"|"lifeforms"|"ownership"|"notice_publisher"|"report_in_catch"|"player_link"|"untyped_member"|"weak_raw_read"|"rel_write_undeclared"|"map_edits")&&!dq_analyze::workspace_fold_policy::Policy::from_name(name).is_some_and(|p|p.message_only()))||!report_metadata(name).is_some_and(|meta|matches!(meta.policy,dq_analyze::lint::Policy::Hard)){return Err(invalid("unissued message-only report"))}
    let raw=&item["site"];let bytes=["rule","rel","msg","key","ident"].into_iter().try_fold(0usize,|n,key|n.checked_add(raw[key].as_str().map_or(0,str::len))).ok_or(io::ErrorKind::OutOfMemory)?;
    self.admission.row::<Site>(bytes)?;let site:Site=serde_json::from_value(raw.clone()).map_err(io::Error::other)?;
    if site.msg.is_empty(){return Err(invalid("hard policy refusal text is absent"))}self.admission.add(4*std::mem::size_of::<Site>())?;data.run.sites.push(site);
   },
   Some("site")=>{let raw=&item["site"];let bytes=["rule","rel","msg","key","ident"].into_iter().try_fold(0usize,|n,key|n.checked_add(raw[key].as_str().map_or(0,str::len))).ok_or(io::ErrorKind::OutOfMemory)?;self.admission.row::<Site>(bytes)?;let site:Site=serde_json::from_value(raw.clone()).map_err(io::Error::other)?;let text=item["source_text"].as_str();if text.is_none()&&(self.grep_purpose.is_none()||site.msg.is_empty()||!item["source_text"].is_null()){return Err(invalid("missing captured site text"))}let line=site.line as usize;if let Some(text)=text{if line==0{if name!="system_boundary"||!matches!(site.rule.as_str(),"B5"|"B7")||!text.is_empty(){return Err(invalid("unissued global report point"))}}else{if let Some(old)=self.lines.get(site.rel.as_str()).and_then(|lines|lines.get(&line)){if old!=text{return Err(invalid("conflicting source text for same as-of line"))}}else{self.admission.row::<(usize,String)>(text.len())?;if !self.lines.contains_key(site.rel.as_str()){self.admission.row::<(String,BTreeMap<usize,String>)>(site.rel.len())?;self.lines.insert(site.rel.clone(),BTreeMap::new());}self.lines.get_mut(site.rel.as_str()).unwrap().insert(line,text.to_owned());}}}self.admission.add(4*std::mem::size_of::<Site>())?;data.run.sites.push(site);},
   Some("allow")=>{let bytes=["rel","name","code"].into_iter().try_fold(0usize,|n,key|n.checked_add(item["allow"][key].as_str().map_or(0,str::len))).ok_or(io::ErrorKind::OutOfMemory)?;self.admission.row::<AllowUse>(bytes)?;let used:AllowUse=serde_json::from_value(item["allow"].clone()).map_err(io::Error::other)?;let digest=item["source_digest"].as_str().ok_or_else(||invalid("missing captured ALLOW digest"))?;if let Some(old)=self.digests.get(&used.rel){if old!=digest{return Err(invalid("conflicting captured whole-file digests"))}}else{self.admission.row::<(String,String)>(used.rel.len()+digest.len())?;self.digests.insert(used.rel.clone(),digest.to_owned());}data.allows.push(used);},
   Some("note")=>{let text=item["text"].as_str().ok_or_else(||invalid("note"))?;self.admission.row::<String>(text.len())?;data.run.notes.push(text.to_owned());},_=>return Err(invalid("unsupported report record"))}}
  let count=row["count"].as_u64().and_then(|n|usize::try_from(n).ok()).ok_or_else(||invalid("count"))?;self.offset=self.offset.checked_add(count).ok_or_else(||invalid("offset overflow"))?;
  if self.offset==total{self.done=true;Ok(None)}else{serde_json::from_value(row["next_cursor"].clone()).map(Some).map_err(io::Error::other)}
 }
 fn deadline(&mut self,reply:&QueryReply,request:&QueryRequest)->io::Result<()>{
  if !self.done||self.deadline.is_some()||reply.revision!=self.pins.0||reply.source_revision.as_deref()!=Some(&self.pins.1)||reply.policy_revision.as_deref()!=Some(&self.pins.2){return Err(invalid("Deadline evidence is not bound to the completed pinned policy frame"))}
  super::query::validate_deadline_evidence_delivery(reply,&request.source_queries)?;let mut lines=reply.jsonl.lines();let row:serde_json::Value=serde_json::from_str(lines.next().ok_or_else(||invalid("missing Deadline observation"))?).map_err(io::Error::other)?;if lines.next().is_some(){return Err(invalid("one exact Deadline observation required"))}
  use dq_analyze::lints::deadline_polling::{ReportAllowlist,prepare_observed_report};
  let path=row["path"].as_str().ok_or_else(||invalid("missing observed path"))?;self.admission.row::<DeadlineData>(path.len())?;
  let observed=match row["observation"].as_str(){Some("captured_utf8")=>ReportAllowlist::CapturedUtf8(row["text"].as_str().ok_or_else(||invalid("missing captured UTF8"))?),Some("proven_missing")=>ReportAllowlist::ProvenMissing,Some("captured_non_utf8")=>ReportAllowlist::CapturedNonUtf8,_=>return Err(invalid("unknown actual observation"))};
  let parsed=prepare_observed_report(observed,&mut self.admission)?;self.deadline=Some(DeadlineData{path:path.into(),parsed:Some(parsed)});Ok(())
 }

}
/// Data-only output; partial policy availability is explicit in every response.
#[derive(Serialize)]struct Report<'a>{schema:&'static str,complete:bool,full_policy_parity:bool,baseline:bool,clean:bool,semantic_revision:&'a str,source_revision:&'a str,policy_revision:&'a str,lints:&'a [String],text:String,allow_usage:&'a BTreeSet<(String,String,u32)>}
fn complete(request:&AnalyzeRequest,delivery:&mut Delivery,baseline:bool)->Result<(bool,Vec<u8>,BTreeSet<(String,String,u32)>),Box<dyn Error>>{
 if !delivery.done||delivery.offset!=delivery.total.unwrap_or(usize::MAX){return Err(invalid("incomplete report delivery").into())}
 let workspace=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();
 if !baseline&&request.lints.iter().any(|name|name=="deadline_polling")&&delivery.deadline.is_none(){return Err(invalid("selected custom finish lacks its captured fixed auxiliary observation").into())}
 if request.lints.as_slice()==["check_grep"]{use dq_analyze::lints::check_grep::native::Purpose;let expected=if baseline{Purpose::Baseline}else{Purpose::Check};if delivery.grep_purpose!=Some(expected)||(baseline&&delivery.macro_ceiling.is_some())||(!baseline&&delivery.macro_ceiling.is_none()){return Err(invalid("completed CheckGrep delivery has the wrong actual purpose").into())}}
 if request.lints.as_slice()==["doc_snippets"]&&delivery.lints.get("doc_snippets").is_none_or(|data|data.doc_complete!=Some(data.doc_blocks.len())){return Err(invalid("selected doc report lacks its completed source summary").into())}
 if dq_analyze::native_policy_roster::is_semantic_read_report_cohort(&request.lints)
     && (delivery.lints.len()!=request.lints.len()||request.lints.iter().any(|name|!delivery.lints.contains_key(name))){
     return Err(invalid("incomplete shared semantic read report delivery").into());
 }
 let mut deadline=delivery.deadline.take();
 let changed=request.changed.as_ref().map(|v|v.iter().cloned().collect::<HashSet<_>>());let mut outcomes=Vec::new();let mut baseline_text=String::new();
 // Legacy registration is lexical module order; the two Lifeforms adapters
 // retain their original adjacent position, not their appended native roster order.
 let mut order=request.lints.iter().collect::<Vec<_>>();order.sort_by_key(|name|legacy_order(name));
 for name in order{let meta=report_metadata(name).ok_or_else(||invalid("unknown metadata"))?;let data=delivery.lints.remove(name).ok_or_else(||invalid("missing captured interpreted scope"))?;
  for required in meta.missing_scope_lists(&data.scope){return Err(invalid(format!("{}: required list {required:?} is absent from captured configuration",meta.name)).into())}
  if baseline{let text=policy_finish::update_baseline_report(meta,&data.scope,delivery,&data.run,&workspace.root,request.scopes_root.as_ref().unwrap_or(&workspace.root),request.baseline_mode.unwrap().into(),|run,mode|if name=="check_grep"{dq_analyze::lints::check_grep::native::update_baseline_after_delivery(&workspace.root,&data.scope,run,mode)}else if name=="deadline_polling"{Ok(dq_analyze::lints::deadline_polling::observed_baseline_report())}else if name=="system_boundary"{dq_analyze::captured_system_boundary_pages::update_baseline_after_delivery(&workspace.root,&data.run,request.baseline_mode.unwrap().into())}else{Err(invalid("unported custom baseline hook"))})?;baseline_text.push_str(&text);baseline_text.push('\n');outcomes.push(policy_finish::Outcome{name:meta.name.to_owned(),failed:false,text:String::new(),run:data.run,allow_used:data.allows,timing:Timing::default(),internal_error:None});continue;}
  // Audited generic policies have the original default post hook. Deadline
  // alone has its actual prepared custom observation; every other hook refuses.
  outcomes.push(policy_finish::finish_report(meta,&data.scope,delivery,data.run,data.allows,Timing::default(),&workspace.root,&changed,request.raw,|run,text,_raw|{if name=="check_grep"{return dq_analyze::lints::check_grep::native::finish_report_after_delivery(&data.scope,delivery.macro_ceiling.expect("completed Check purpose"),run,delivery,text)}if name=="system_boundary"{return dq_analyze::captured_system_boundary_pages::finish_report_after_delivery(&workspace.root,run,text)}let observed=deadline.as_mut().expect("selected custom observation checked before any finish/baseline IO");observed.parsed.take().expect("custom policy is invoked once per selected lint").finish(run,&observed.path.to_string_lossy(),text)},|run,text| {
        name == "doc_snippets" && dq_analyze::doc_snippets_policy::finish_summary(
            meta, &workspace.root, delivery, &data.doc_blocks, run, text, request.raw,
        )
    }));
 }
 let (mut text,failed)=if baseline{(baseline_text,Vec::new())}else{policy_finish::render(&outcomes,request.ci)};
 if !baseline{text.push_str(&policy_finish::result_line(&failed));}
 let allows=policy_finish::allow_usage_rows(&outcomes,|relative|delivery.digests.get(relative).map(|s|policy_finish::AllowFileDigest::Captured(s)).ok_or_else(||invalid("missing ALLOW evidence")))?;
 let clean=failed.is_empty();let report=Report{schema:"native-analyze-report-v1",complete:true,full_policy_parity:false,baseline,clean,semantic_revision:&delivery.pins.0,source_revision:&delivery.pins.1,policy_revision:&delivery.pins.2,lints:&request.lints,text,allow_usage:&allows};let mut output=Capped(Vec::new());serde_json::to_writer(&mut output,&report)?;output.write_all(b"\n")?;Ok((clean,output.0,allows))
}
fn legacy_order(name:&str)->(String,u8){match name{"lifeform_allows"=>("lifeforms".into(),0),"escape_hatches"=>("lifeforms".into(),1),name=>(name.replace("sys/","sys_"),0)}}
struct Capped(Vec<u8>);impl Write for Capped{fn write(&mut self,b:&[u8])->io::Result<usize>{if b.len()>LIMIT.saturating_sub(self.0.len()){return Err(io::ErrorKind::OutOfMemory.into())}self.0.try_reserve(b.len()).map_err(io::Error::other)?;self.0.extend_from_slice(b);Ok(b.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
/// Preparation emits diagnostic frames on either original stream. Preserve every
/// byte on stderr; stdout belongs exclusively to the final validated report.
fn preparation_diagnostic(bytes:&[u8],total:&mut usize,stderr:&mut impl Write)->io::Result<()>{
 *total=total.checked_add(bytes.len()).filter(|n|*n<=LIMIT).ok_or(io::ErrorKind::OutOfMemory)?;
 stderr.write_all(bytes)
}
fn collect_report_pages(
    request:&AnalyzeRequest,
    delivery:&mut Delivery,
    baseline:bool,
    mut execute:impl FnMut(QueryRequest)->Result<QueryReply,Box<dyn Error>>,
)->Result<(),Box<dyn Error>>{
    if dq_analyze::native_policy_roster::is_semantic_read_report_cohort(&request.lints){
        for (index,name) in request.lints.iter().enumerate(){
            if index!=0{
                if !delivery.done{return Err(invalid("shared semantic page series was incomplete").into())}
                // Only progress is per-policy. The captured pins, roots, findings,
                // text, ALLOW evidence and single admission remain joined.
                delivery.aggregate=None;
                delivery.total=None;
                delivery.offset=0;
                delivery.done=false;
            }
            collect_page_series(request,std::slice::from_ref(name),delivery,baseline,&mut execute)?;
        }
    }else{
        collect_page_series(request,&request.lints,delivery,baseline,&mut execute)?;
    }
    Ok(())
}
fn collect_page_series(
    request:&AnalyzeRequest,
    lints:&[String],
    delivery:&mut Delivery,
    baseline:bool,
    execute:&mut impl FnMut(QueryRequest)->Result<QueryReply,Box<dyn Error>>,
)->Result<(),Box<dyn Error>>{
 let workspace=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();
 let mut cursor=None;
 loop{let query=QueryRequest{analysis_context:request.build.policy_inputs.as_ref().and_then(|intent|intent.analysis_context),timeout_seconds:request.build.timeout_seconds,project:request.build.project.clone(),defines:request.build.defines.clone(),engine_template:request.build.engine_template.clone(),bootstrap_catalog:request.build.bootstrap_catalog,expected_revision:Some(delivery.pins.0.clone()),expected_source_revision:Some(delivery.pins.1.clone()),expected_policy_revision:Some(delivery.pins.2.clone()),queries:Vec::new(),source_queries:vec![if lints.len()==1&&dq_analyze::workspace_fold_policy::Policy::from_name(&lints[0]).is_some(){SourceQuery::NativeWorkspacePolicyReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else if lints.len()==1&&dq_analyze::captured_raw_tree_pages::Policy::from_name(&lints[0]).is_some(){SourceQuery::NativeWorkspaceRawTreeReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else if lints==["check_grep"]{if baseline{SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else{SourceQuery::NativeWorkspaceCheckGrepReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}}else if lints.len()==1&&super::query::semantic_report_metadata(&lints[0]).is_some(){SourceQuery::NativeWorkspaceSemanticReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else if lints==["sem/keys"]{SourceQuery::NativeWorkspaceKeysReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else if lints==["sys/hygiene"]{SourceQuery::NativeWorkspaceHygieneReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else if lints.len()==1&&["sys/resolvers","sys/tables","system_boundary"].contains(&lints[0].as_str()){SourceQuery::NativeWorkspaceSysReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}else{SourceQuery::NativeWorkspaceRawReportPage{root:workspace.root.clone(),configuration:workspace.configuration.clone(),lints:lints.to_vec(),cursor,limit:128}}]};let reply=execute(query.clone())?;cursor=delivery.page(&reply,&query)?;if cursor.is_none(){break}}
 Ok(())
}

pub fn run_file(path:&Path,baseline:bool)->Result<bool,Box<dyn Error>>{
 let mut bytes=Vec::new();File::open(path)?.take((CONTROL+1)as u64).read_to_end(&mut bytes)?;if bytes.len()>CONTROL{return Err(invalid("Analyze control request exceeds existing frame bound").into())}
 run_request(serde_json::from_slice(&bytes)?,baseline)
}

fn semantic_workspace_request(args:&[String])->Result<AnalyzeRequest,Box<dyn Error>>{
    let [root,format,flags @ ..] = args else {
        return Err(invalid("usage: dmbc analyze-check --workspace ABSOLUTE_ROOT --jsonl [--ci] [--raw]").into());
    };
    let root=PathBuf::from(root);
    if !root.is_absolute()||format!="--jsonl" {
        return Err(invalid("native workspace check requires an absolute root and --jsonl").into());
    }
    let(mut ci,mut raw)=(false,false);
    for flag in flags {
        let value=match flag.as_str(){
            "--ci"=>&mut ci,
            "--raw"=>&mut raw,
            _=>return Err(invalid("unsupported native workspace check option").into()),
        };
        if std::mem::replace(value,true) {
            return Err(invalid("duplicate native workspace check option").into());
        }
    }
    let project=root.join("deepquarry.dme");
    let args=[
        "prepare-query".to_owned(),
        project.to_str().ok_or_else(||invalid("native workspace project is not Unicode"))?.to_owned(),
        "--exact-inputs".to_owned(),
        "--request-timeout-seconds".to_owned(),
        "300".to_owned(),
    ];
    let crate::request::Command::Build(mut build)=crate::cli::parse(&args)? else {
        return Err(invalid("native workspace check did not construct a PrepareQuery").into());
    };
    use crate::policy_request::{AnalysisContext,PolicyInputRequest,WorkspaceAuxiliaryQuestion as Q,WorkspacePolicyRequest};
    build.policy_inputs=Some(PolicyInputRequest{
        analysis_context:Some(AnalysisContext::OriginalAnalyze0290),
        workspace_auxiliary:vec![Q::SemReads,Q::UntrackedInputs,Q::SetterPublishes],
        workspace:Some(WorkspacePolicyRequest{
            recursive_roots:vec![root.join("code"),root.join("maps")],
            configuration:root.join("tools/ci/lint_scopes.toml"),
            root,
        }),
        ..Default::default()
    });
    let lints=dq_analyze::native_policy_roster::SEMANTIC_READ_REPORT_COHORT.iter().map(|name|(*name).to_owned()).collect();
    Ok(AnalyzeRequest{build:*build,lints,raw,changed:None,scopes_root:None,baseline_mode:None,ci})
}

/// Standard check opt-in uses the exact same report admission and resident
/// execution as a caller-supplied JSON request. No temporary manifest.
pub fn run_semantic_workspace(args:&[String])->Result<bool,Box<dyn Error>>{
    run_request(semantic_workspace_request(args)?,false)
}

fn run_request(request:AnalyzeRequest,baseline:bool)->Result<bool,Box<dyn Error>>{
 request.validate(baseline)?;
 if request.lints.as_slice()==["derived_reads"] {let delivered=route_derived(request,&mut io::stderr().lock())?;delivered.write_allow_usage_best_effort();io::stdout().lock().write_all(delivered.bytes())?;return Ok(delivered.clean()); }
 if request.lints.as_slice()==["sem/handlers"] {
  let delivered=route_attempt(request,AttemptKind::Handlers,&mut io::stderr().lock())?;
  let complete=delivered.complete();
  if complete{delivered.write_allow_usage_best_effort();}
  io::stdout().lock().write_all(delivered.bytes())?;
  if !complete{return Err(invalid("sem/handlers full preparation failed; structural report is incomplete").into())}
  return Ok(delivered.clean());
 }
 let mut diagnostic_bytes=0usize;let prepared=super::route_with_diagnostics(request.build.clone(),&mut |_stdout,bytes|preparation_diagnostic(bytes,&mut diagnostic_bytes,&mut io::stderr().lock()))?;
 let(semantic_revision,source_revision,policy_revision)=match prepared{BuildOutcome::QueryPrepared{semantic_revision,source_revision,policy_revision:Some(policy_revision),retained:true}=>(semantic_revision,source_revision,policy_revision),BuildOutcome::RawQueryPrepared{query_revision,source_revision,policy_revision,retained:true}if request.lints.as_slice()==["doc_snippets"]||request.lints.as_slice()==["notice_publisher"]||request.lints.as_slice()==["ownership"]||request.lints.as_slice()==["ui_actions"]||request.lints.as_slice()==["op_order"]||request.lints.as_slice()==["engine_layering"]||request.lints.as_slice()==["library_layering"]=>(query_revision,source_revision,policy_revision),_=>return Err(invalid("resident preparation did not issue the selected actual source/policy frame").into())};
 let workspace=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();
 let mut delivery=Delivery::new((semantic_revision,source_revision,policy_revision));
 collect_report_pages(&request,&mut delivery,baseline,super::query::execute)?;
 if !baseline&&request.lints.iter().any(|name|name=="deadline_polling"){
  let query=QueryRequest{analysis_context:request.build.policy_inputs.as_ref().and_then(|intent|intent.analysis_context),timeout_seconds:request.build.timeout_seconds,project:request.build.project.clone(),defines:request.build.defines.clone(),engine_template:request.build.engine_template.clone(),bootstrap_catalog:request.build.bootstrap_catalog,expected_revision:Some(delivery.pins.0.clone()),expected_source_revision:Some(delivery.pins.1.clone()),expected_policy_revision:Some(delivery.pins.2.clone()),queries:Vec::new(),source_queries:vec![SourceQuery::NativeDeadlinePollingEvidence{root:workspace.root.clone(),configuration:workspace.configuration.clone()}]};let reply=super::query::execute(query.clone())?;delivery.deadline(&reply,&query)?;
 }
 let(clean,bytes,allows)=complete(&request,&mut delivery,baseline)?;if !baseline{if let Some(path)=std::env::var_os("DQ_ALLOW_USAGE").filter(|value|!value.is_empty()){if let Ok(mut file)=std::fs::OpenOptions::new().create(true).append(true).open(path){let _=policy_finish::write_allow_rows(&allows,&mut file);}}}io::stdout().lock().write_all(&bytes)?;Ok(clean)
}

#[cfg(test)]pub(crate) fn finish_captured_for_test(request:&AnalyzeRequest,pages:&[(QueryReply,QueryRequest)],baseline:bool)->Result<(bool,Vec<u8>),Box<dyn Error>>{let first=pages.first().ok_or_else(||invalid("no pages"))?;let mut delivery=Delivery::new((first.0.revision.clone(),first.0.source_revision.clone().ok_or_else(||invalid("source pin"))?,first.0.policy_revision.clone().ok_or_else(||invalid("policy pin"))?));for(reply,query)in pages{delivery.page(reply,query)?;}complete(request,&mut delivery,baseline).map(|(clean,bytes,_)|(clean,bytes))}
#[cfg(test)]pub(crate) fn finish_auxiliary_captured_for_test(request:&AnalyzeRequest,pages:&[(QueryReply,QueryRequest)],evidence:Option<&(QueryReply,QueryRequest)>,baseline:bool)->Result<(bool,Vec<u8>),Box<dyn Error>>{request.validate(baseline)?;let first=pages.first().ok_or_else(||invalid("no pages"))?;let mut delivery=Delivery::new((first.0.revision.clone(),first.0.source_revision.clone().ok_or_else(||invalid("source pin"))?,first.0.policy_revision.clone().ok_or_else(||invalid("policy pin"))?));for(reply,query)in pages{delivery.page(reply,query)?;}if let Some((reply,query))=evidence{delivery.deadline(reply,query)?;}complete(request,&mut delivery,baseline).map(|(clean,bytes,_)|(clean,bytes))}
#[cfg(test)]mod tests{
 use super::*;use serde_json::json;
 fn request()->AnalyzeRequest{let(_,mut build,_,_)=crate::generation_test_fixture::fixture();build.policy_inputs.as_mut().unwrap().workspace_generators.clear();AnalyzeRequest{build,lints:vec!["scheduler".into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false}}
 fn page(request:&AnalyzeRequest,offset:usize,total:usize,items:serde_json::Value)->(QueryReply,QueryRequest){let w=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();let pins=("11111111111111111111111111111111".to_owned(),"22222222222222222222222222222222".to_owned(),"33333333333333333333333333333333".to_owned());let count=items.as_array().unwrap().len();let id="44444444444444444444444444444444";let next=if offset+count==total{serde_json::Value::Null}else{json!({"aggregate_id":id,"offset":offset+count})};let cursor=if offset==0{None}else{Some(serde_json::from_value(json!({"aggregate_id":id,"offset":offset})).unwrap())};let row=json!({"row":"source_native_workspace_raw_report","schema":"dm-session-source-query-v1","source_revision":pins.1,"policy_revision":pins.2,"semantic_revision":pins.0,"snapshot_as_of":"policy_revision","root":w.root,"configuration":w.configuration,"recursive_roots":w.recursive_roots,"requested_lints":request.lints,"lint_whitelist":dq_analyze::captured_raw_policy::RAW_FILE_LINTS,"scope":"typed_discovery_raw_files","full_policy_parity":false,"baseline_applied":false,"admission":"complete_selected_raw_policy_findings","configuration_scope":"proven_missing_configuration","aggregate_id":id,"offset":offset,"count":count,"total_items":total,"next_cursor":next,"items":items,"policy_scopes":[["scheduler","[[],[],[],{},{},{},[]]"]]});
 let query=QueryRequest{analysis_context:None,timeout_seconds:None,project:request.build.project.clone(),defines:request.build.defines.clone(),engine_template:request.build.engine_template.clone(),bootstrap_catalog:request.build.bootstrap_catalog,expected_revision:Some(pins.0.clone()),expected_source_revision:Some(pins.1.clone()),expected_policy_revision:Some(pins.2.clone()),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceRawReportPage{root:w.root.clone(),configuration:w.configuration.clone(),lints:request.lints.clone(),cursor,limit:128}]};let reply=QueryReply{schema:"dm-session-query-v1".into(),revision:pins.0,complete:false,coverage:"partial".into(),query_count:0,source_query_count:1,source_revision:Some(pins.1),policy_revision:Some(pins.2),snapshot_outcome:"analyzed".into(),last_request_outcome:"analyzed".into(),publication_pair:None,jsonl:format!("{row}\n")};(reply,query)}
 fn site(text:&str)->serde_json::Value{json!({"lint":"scheduler","kind":"site","site":{"rule":"sleep","rel":"code/a.dm","line":2,"msg":"","key":"","ident":""},"source_text":text})}

 #[test]fn analyze_preparation_preserves_both_diagnostic_streams_exactly_and_keeps_first_writer_io_and_cap(){
  let mut out=Vec::new();let mut total=0;let mut callback=|_stdout:bool,bytes:&[u8]|preparation_diagnostic(bytes,&mut total,&mut out);callback(true,b"stdout debug\0").unwrap();callback(false,b"stderr trace\xff\n").unwrap();drop(callback);assert_eq!(out,b"stdout debug\0stderr trace\xff\n");assert_eq!(total,out.len());
  struct Fail;impl Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}assert_eq!(preparation_diagnostic(b"actual debug",&mut 0,&mut Fail).unwrap_err().raw_os_error(),Some(1450));
  let mut total=LIMIT;let mut output=Vec::new();assert_eq!(preparation_diagnostic(b"x",&mut total,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(total,LIMIT);
 }
 #[test]fn analyze_client_captures_scope_site_text_and_digest_then_common_finishes_complete_selection(){let request=request();request.validate(false).unwrap();let a=page(&request,0,2,json!([site("sleep(1)")]));let b=page(&request,1,2,json!([{"lint":"scheduler","kind":"allow","allow":{"rel":"code/a.dm","line":3,"name":"scheduler","code":""},"source_digest":"1234567890123456789012345678901234567890"}]));let(clean,bytes)=finish_captured_for_test(&request,&[a,b],false).unwrap();assert!(!clean);let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(value["schema"],"native-analyze-report-v1");assert_eq!(value["complete"],true);assert_eq!(value["full_policy_parity"],false);assert!(value["text"].as_str().unwrap().contains("sleep(1)"));assert_eq!(value["allow_usage"][0][1],"1234567890123456789012345678901234567890");}
 #[test]fn analyze_client_refuses_incomplete_foreign_and_conflicting_pages_before_baseline_io(){let mut request=request();request.raw=false;request.baseline_mode=Some(BaselineMode::Update);let a=page(&request,0,2,json!([site("sleep(1)")]));assert!(finish_captured_for_test(&request,&[a.clone()],true).is_err());let(mut b,q)=page(&request,1,2,json!([site("sleep(2)")]));assert!(finish_captured_for_test(&request,&[a.clone(),(b.clone(),q.clone())],true).is_err());b.source_revision=Some("foreign".into());assert!(finish_captured_for_test(&request,&[a,(b,q)],true).is_err());}
 fn doc_page(request:&AnalyzeRequest,items:serde_json::Value)->(QueryReply,QueryRequest){let count=items.as_array().unwrap().len();let(mut reply,mut query)=page(request,0,count,items);let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();row["row"]="source_native_workspace_raw_tree_report".into();row["scope"]="typed_discovery_complete_raw_tree".into();row["admission"]="complete_selected_raw_tree_findings".into();row["lint_whitelist"]=json!(["doc_snippets"]);row["policy_scopes"]=json!([["doc_snippets","[[],[],[],{},{},{},[]]"]]);reply.jsonl=format!("{row}\n");let w=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();query.source_queries=vec![SourceQuery::NativeWorkspaceRawTreeReportPage{root:w.root.clone(),configuration:w.configuration.clone(),lints:request.lints.clone(),cursor:None,limit:128}];(reply,query)}
 #[test]fn analyze_client_doc_summary_is_complete_typed_custom_and_cannot_be_raw_or_code_authority(){let mut actual=request();actual.lints=vec!["doc_snippets".into()];let intent=actual.build.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippets];let w=intent.workspace.as_mut().unwrap();w.recursive_roots=vec![w.root.join("code"),w.root.join("doc/rewrite")];actual.validate(false).unwrap();let complete=json!({"lint":"doc_snippets","kind":"doc_complete","count":0});let page=doc_page(&actual,json!([complete.clone()]));let(clean,bytes)=finish_captured_for_test(&actual,&[page],false).unwrap();assert!(clean);let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(row["text"].as_str().unwrap().contains("doc_snippets: 0 block(s)"));
 for items in [json!([]),json!([{"lint":"doc_snippets","kind":"doc_complete","count":1}]),json!([complete.clone(),complete.clone()]),json!([{"lint":"doc_snippets","kind":"doc_block","block":{"kind":"complete","rel":"code/not-markdown.dm","first":"missing()"}},complete.clone()]),json!([{"lint":"doc_snippets","kind":"doc_block","block":{"kind":"complete","rel":"doc/rewrite/a.md","first":"missing()","extra":"forged"}},complete.clone()]),json!([{"lint":"doc_snippets","kind":"doc_block","block":{"kind":"unissued","rel":"doc/rewrite/a.md","first":"missing()"}},complete.clone()])]{assert!(finish_captured_for_test(&actual,&[doc_page(&actual,items)],false).is_err());}
 actual.build.policy_inputs.as_mut().unwrap().workspace_auxiliary.clear();assert!(actual.validate(false).is_err());assert!(!dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&"doc_snippets"));assert!(!crate::policy_request::WorkspaceAuxiliaryQuestion::DocSnippets.is_semantic());}
 #[test]fn analyze_client_requires_explicit_generic_hooks_and_refuses_silent_option_bypass(){let mut request=request();assert_eq!(GENERIC_REPORT_LINTS.len(),42);for name in GENERIC_REPORT_LINTS{assert!(!matches!(report_metadata(name).unwrap().policy,dq_analyze::lint::Policy::Custom));}for name in ["deadline_polling","check_grep","derived_reads"]{request.lints=vec![name.into()];assert!(request.validate(false).is_err());}request.lints=vec!["scheduler".into()];request.build.no_daemon=true;assert!(request.validate(false).is_err());request.build.no_daemon=false;request.build.trace_path=Some(PathBuf::from("trace"));assert!(request.validate(false).is_err());}
 #[test]
 fn analyze_client_allow_annotations_admits_only_exact_check_over_code_and_maps() {
  let mut actual=request();
  actual.lints=vec!["allow_annotations".into()];
  let intent=actual.build.policy_inputs.as_mut().unwrap();
  intent.analysis_context=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);
  let workspace=intent.workspace.as_mut().unwrap();
  workspace.recursive_roots=vec![workspace.root.join("code"),workspace.root.join("maps")];
  actual.validate(false).unwrap();
  assert!(actual.validate(true).is_err());
  let mut mixed=actual.clone();
  mixed.lints.push("scheduler".into());
  assert!(mixed.validate(false).is_err());
  let mut foreign=actual.clone();
  foreign.build.policy_inputs.as_mut().unwrap().analysis_context=None;
  assert!(foreign.validate(false).is_err());
  let mut extra=actual.clone();
  extra.build.policy_inputs.as_mut().unwrap().workspace_auxiliary.push(crate::policy_request::WorkspaceAuxiliaryQuestion::OpOrder);
  assert!(extra.validate(false).is_err());
  let roots=&mut actual.build.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap().recursive_roots;
  roots.pop();
  assert!(actual.validate(false).is_err());
 }
 #[test]fn analyze_client_zero_findings_requires_real_scope_and_preserves_negative_ceiling(){let request=request();let(mut reply,query)=page(&request,0,0,json!([]));let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim_end()).unwrap();row["policy_scopes"][0][1]=json!("[[],[],[],{},{},{\"sleep\":-1},[]]");reply.jsonl=format!("{row}\n");let(clean,bytes)=finish_captured_for_test(&request,&[(reply.clone(),query.clone())],false).unwrap();assert!(clean,"raw intentionally ignores actual negative ceiling");assert!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["allow_usage"].as_array().unwrap().is_empty());row["policy_scopes"]=json!([]);reply.jsonl=format!("{row}\n");assert!(finish_captured_for_test(&request,&[(reply,query)],false).is_err());}
 #[test]fn analyze_client_whole_sys_families_require_exclusive_real_hook_issuance(){let mut request=request();for name in ["sys/resolvers","sys/tables","system_boundary"]{request.lints=vec![name.into()];request.validate(false).unwrap();for names in [vec![name.into(),"scheduler".into()],vec!["scheduler".into(),name.into()],vec![name.into(),name.into()]]{request.lints=names;assert!(request.validate(false).is_err());}}}
 #[test]fn analyze_client_report_order_matches_original_lifeforms_registration_and_lexical_modules(){let mut names=vec!["scheduler","sys/contents","escape_hatches","lifeform_allows","lifecycle_counts"];names.sort_by_key(|n|legacy_order(n));assert_eq!(names,vec!["lifecycle_counts","lifeform_allows","escape_hatches","scheduler","sys/contents"]);}
 #[test]fn analyze_scope_measure_preserves_actual_oom_and_root_clone_is_funded_before_retention(){let mut admission=Admission{used:LIMIT,denied:false};assert_eq!(scope_decode("[[\"actual\"],[],[],{},{},{},[]]",&mut admission).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(admission.denied);let request=request();let(mut reply,query)=page(&request,0,0,json!([]));let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim_end()).unwrap();let root=&request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap().root;row["recursive_roots"]=json!((0..256).map(|n|root.join(format!("code/branch{n}"))).collect::<Vec<_>>());reply.jsonl=format!("{row}\n");let mut delivery=Delivery::new((reply.revision.clone(),reply.source_revision.clone().unwrap(),reply.policy_revision.clone().unwrap()));delivery.admission.used=LIMIT-1024;assert_eq!(delivery.page(&reply,&query).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(delivery.roots.is_none()&&delivery.lines.is_empty());}


 #[test]fn analyze_client_entry_slots_uses_existing_generic_file_report_adapter(){let meta=report_metadata("entry_slots").unwrap();assert!(matches!(meta.scan,dq_analyze::lint::ScanKind::File));assert!(matches!(meta.policy,dq_analyze::lint::Policy::Hard));assert!(dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(&"entry_slots"));assert!(GENERIC_REPORT_LINTS.contains(&"entry_slots"));let mut actual=request();for names in [vec!["entry_slots".into()],vec!["entry_slots".into(),"scheduler".into()],vec!["scheduler".into(),"entry_slots".into()]]{actual.lints=names;actual.validate(false).unwrap();}for name in ["entry_slots_unported","ENTRY_SLOTS","cooldown_unported","cap_bits_unported"]{actual.lints=vec![name.into()];assert!(actual.validate(false).is_err());}}

 #[test]fn analyze_client_complete_collectors_require_exclusive_exact_metadata_and_selected_semantic_intent(){use dq_analyze::workspace_fold_policy::Policy as P;for policy in [P::Tracked,P::TrackedTests,P::StateSchema,P::Lifecycle,P::Loot,P::InstanceList,P::Cache,P::OwnershipForms,P::Api,P::Fields,P::Appearance]{let mut actual=request();actual.lints=vec![policy.name().into()];assert!(!matches!(policy.metadata().policy,dq_analyze::lint::Policy::Custom));if let Some(tests)=policy.tracked(){let intent=actual.build.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(crate::policy_request::AnalysisContext::OriginalChecker0290);intent.workspace_auxiliary=vec![if tests{crate::policy_request::WorkspaceAuxiliaryQuestion::TrackedTests}else{crate::policy_request::WorkspaceAuxiliaryQuestion::Tracked}];}actual.validate(false).unwrap();let mut baseline=actual.clone();baseline.raw=false;baseline.baseline_mode=Some(BaselineMode::Update);{let workspace=baseline.build.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap();workspace.configuration=workspace.root.join("tools/ci/lint_scopes.toml");}baseline.validate(true).unwrap();let mut wrong_target=baseline.clone();{let workspace=wrong_target.build.policy_inputs.as_mut().unwrap().workspace.as_mut().unwrap();workspace.configuration=workspace.root.join("missing.toml");}assert!(wrong_target.validate(true).unwrap_err().to_string().contains("baseline ceiling target must match the actually captured configuration path"));for names in [vec![policy.name().into(),"scheduler".into()],vec!["scheduler".into(),policy.name().into()],vec![policy.name().into(),policy.name().into()],vec![format!("{}_unported",policy.name())]]{let mut mixed=actual.clone();mixed.lints=names;assert!(mixed.validate(false).is_err());}if policy.tracked().is_some(){let intent=actual.build.policy_inputs.as_mut().unwrap();intent.workspace_auxiliary.clear();assert!(actual.validate(false).is_err());}}}
}

#[cfg(test)]mod admitted_semantic_hard_delivery_tests{
 use super::*;use serde_json::json;
 fn request(name:&str)->AnalyzeRequest{
  let(_,mut build,_,_)=crate::generation_test_fixture::fixture();let intent=build.policy_inputs.as_mut().unwrap();intent.workspace_generators.clear();intent.analysis_context=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![match name{"engine_layering"=>crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering,"player_link"=>crate::policy_request::WorkspaceAuxiliaryQuestion::PlayerLink,"untyped_member"=>crate::policy_request::WorkspaceAuxiliaryQuestion::UntypedMember,"weak_raw_read"=>crate::policy_request::WorkspaceAuxiliaryQuestion::WeakRawRead,"rel_write_undeclared"=>crate::policy_request::WorkspaceAuxiliaryQuestion::RelWriteUndeclared,"untyped"=>crate::policy_request::WorkspaceAuxiliaryQuestion::Untyped,_=>unreachable!()}];
  AnalyzeRequest{build,lints:vec![name.into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false}
 }
 fn page(request:&AnalyzeRequest,kind:&str,message:&str)->(QueryReply,QueryRequest){
  let w=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();let pins=("11111111111111111111111111111111".to_owned(),"22222222222222222222222222222222".to_owned(),"33333333333333333333333333333333".to_owned());let name=&request.lints[0];let rule=report_metadata(name).unwrap().rules[0].name;
  let row=json!({"row":"source_native_workspace_semantic_report","schema":"dm-session-source-query-v1","semantic_revision":pins.0,"source_revision":pins.1,"policy_revision":pins.2,"snapshot_as_of":"policy_revision","root":w.root,"configuration":w.configuration,"recursive_roots":w.recursive_roots,"requested_lints":request.lints,"lint_whitelist":[name],"scope":"typed_discovery_complete_semantic","full_policy_parity":false,"baseline_applied":false,"admission":"complete_selected_semantic_findings","configuration_scope":"proven_missing_configuration","aggregate_id":"44444444444444444444444444444444","offset":0,"count":1,"total_items":1,"next_cursor":null,"items":[{"lint":name,"kind":kind,"site":{"rule":rule,"rel":"code/a.dm","line":2,"msg":message,"key":"","ident":""}}],"policy_scopes":[[name,"[[],[],[],{},{},{},[]]"]]});
  let query=QueryRequest{analysis_context:Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290),timeout_seconds:None,project:request.build.project.clone(),defines:request.build.defines.clone(),engine_template:request.build.engine_template.clone(),bootstrap_catalog:request.build.bootstrap_catalog,expected_revision:Some(pins.0.clone()),expected_source_revision:Some(pins.1.clone()),expected_policy_revision:Some(pins.2.clone()),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSemanticReportPage{root:w.root.clone(),configuration:w.configuration.clone(),lints:request.lints.clone(),cursor:None,limit:128}]};
  (QueryReply{schema:"dm-session-query-v1".into(),revision:pins.0,complete:false,coverage:"partial".into(),query_count:0,source_query_count:1,source_revision:Some(pins.1),policy_revision:Some(pins.2),snapshot_outcome:"analyzed".into(),last_request_outcome:"analyzed".into(),publication_pair:None,jsonl:format!("{row}\n")},query)
 }
 #[test]fn already_admitted_semantic_hard_families_deliver_their_actual_refusal_rows(){
  for name in ["player_link","untyped_member","weak_raw_read","rel_write_undeclared"]{
   let request=request(name);request.validate(false).unwrap();let result=finish_captured_for_test(&request,&[page(&request,"hard_site","exact admitted semantic refusal")],false).unwrap();assert!(!result.0,"{name}: hard finding must fail the check");let row:serde_json::Value=serde_json::from_slice(&result.1).unwrap();assert!(row["text"].as_str().unwrap().contains("exact admitted semantic refusal"),"{name}");assert_eq!(row["complete"],true);assert!(row["allow_usage"].as_array().unwrap().is_empty());
  }
 }
 #[test]fn semantic_hard_delivery_still_refuses_empty_messages_foreign_pins_and_nonhard_policies(){
  for name in ["player_link","untyped_member","weak_raw_read","rel_write_undeclared"]{
   let request=request(name);assert!(finish_captured_for_test(&request,&[page(&request,"hard_site","")],false).is_err());let(mut reply,query)=page(&request,"hard_site","real refusal");reply.source_revision=Some("foreign".into());assert!(finish_captured_for_test(&request,&[(reply,query)],false).is_err());
  }
  let request=request("untyped");assert!(!matches!(report_metadata("untyped").unwrap().policy,dq_analyze::lint::Policy::Hard));assert!(finish_captured_for_test(&request,&[page(&request,"hard_site","not an issued Hard policy")],false).is_err());
 }
 #[test]fn engine_hard_delivery_uses_its_exact_closed_protocol_and_preserves_refusal_text(){let request=request("engine_layering");request.validate(false).unwrap();let actual=finish_captured_for_test(&request,&[page(&request,"hard_site","/proc/ordinary_helper is declared downstream")],false).unwrap();assert!(!actual.0);let row:serde_json::Value=serde_json::from_slice(&actual.1).unwrap();assert!(row["text"].as_str().unwrap().contains("/proc/ordinary_helper is declared downstream"));assert_eq!(row["lints"],json!(["engine_layering"]));assert!(finish_captured_for_test(&request,&[page(&request,"hard_site","")],false).is_err());let(mut reply,query)=page(&request,"hard_site","actual engine refusal");reply.source_revision=Some("foreign".into());assert!(finish_captured_for_test(&request,&[(reply,query)],false).is_err());}

}

/// Closed, source-authenticated Derived route. It does not widen generic report
/// selection or claim full-policy parity. Baseline publication is explicitly
/// refused here until its mutating transaction receives separate qualification.
impl AnalyzeRequest {
 fn validate_derived(&self,baseline:bool)->io::Result<()> {
  if baseline||self.baseline_mode.is_some(){return Err(invalid("Derived resident baseline transaction is not qualified; no baseline was changed"))}
  let b=&self.build;
  if b.command!=BuildCommand::PrepareQuery||b.no_daemon||b.trace_path.is_some()||b.record_inputs.is_some()||b.replay_inputs.is_some()||b.artifact_directory.is_some()||b.output_store.is_some()||b.source_questions.is_some()||b.diagnostic_declarations||!b.defines.is_empty()||b.engine_template.is_some()||b.bootstrap_catalog{return Err(invalid("Derived report requires the exclusive ordinary resident PrepareQuery factory"))}
  let intent=b.policy_inputs.as_ref().ok_or_else(||invalid("Derived workspace intent required"))?.clone().admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid("Derived report requires its exact Original Analyze purpose"))}
  let w=b.policy_inputs.as_ref().unwrap().workspace.as_ref().ok_or_else(||invalid("Derived workspace required"))?;
  if !b.project.is_absolute()||!w.root.is_absolute(){return Err(invalid("absolute Derived source and workspace required"))}
  super::build_admission::validate(b).map_err(io::Error::other)?;
  if self.changed.as_ref().is_some_and(|paths|paths.iter().any(|p|p.is_empty()||Path::new(p).is_absolute()||p.split(['/', '\\']).any(|part|part==".."))){return Err(invalid("changed files must be workspace-relative"))}
  if self.scopes_root.as_ref().is_some_and(|p|!p.is_absolute()){return Err(invalid("scopes_root must be absolute"))}Ok(())
 }
 fn validate_handlers(&self,baseline:bool)->io::Result<()> {
  if baseline||self.baseline_mode.is_some(){return Err(invalid("Derived resident baseline transaction is not qualified; no baseline was changed"))}
  let b=&self.build;
  if b.command!=BuildCommand::PrepareQuery||b.no_daemon||b.trace_path.is_some()||b.record_inputs.is_some()||b.replay_inputs.is_some()||b.artifact_directory.is_some()||b.output_store.is_some()||b.source_questions.is_some()||b.diagnostic_declarations||!b.defines.is_empty()||b.engine_template.is_some()||b.bootstrap_catalog{return Err(invalid("Handlers report requires the exclusive ordinary resident PrepareQuery factory"))}
  let intent=b.policy_inputs.as_ref().ok_or_else(||invalid("Handlers workspace intent required"))?.clone().admit().map_err(io::Error::other)?;
  if intent.analysis_context()!=Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[crate::policy_request::WorkspaceAuxiliaryQuestion::SemHandlers]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid("Handlers report requires its exact Original Analyze purpose"))}
  let w=b.policy_inputs.as_ref().unwrap().workspace.as_ref().ok_or_else(||invalid("Handlers workspace required"))?;
  if !b.project.is_absolute()||!w.root.is_absolute(){return Err(invalid("absolute Handlers source and workspace required"))}
  super::build_admission::validate(b).map_err(io::Error::other)?;
  if self.changed.as_ref().is_some_and(|paths|paths.iter().any(|p|p.is_empty()||Path::new(p).is_absolute()||p.split(['/', '\\']).any(|part|part==".."))){return Err(invalid("changed files must be workspace-relative"))}
  if self.scopes_root.as_ref().is_some_and(|p|!p.is_absolute()){return Err(invalid("scopes_root must be absolute"))}Ok(())
 }
}
#[derive(Debug,Serialize,Deserialize)]#[serde(tag="kind",rename_all="snake_case",deny_unknown_fields)]
pub enum DerivedPreparation {
 Current{semantic_revision:String,source_revision:String,policy_revision:String},
 /// Issued only after the actual factory supplied a one-shot raw report. No
 /// semantic/source revision exists and this variant is never a query pin.
 FailedRootOneShot{failure:crate::request_failure::RequestFailure,io_kind:Option<String>,os_code:Option<i32>},
}
#[derive(Debug,Serialize,Deserialize)]#[serde(deny_unknown_fields)]pub struct DerivedReport{pub schema:String,pub complete:bool,pub full_policy_parity:bool,pub baseline:bool,pub clean:bool,pub preparation:DerivedPreparation,pub lints:Vec<String>,pub text:String,pub allow_usage:BTreeSet<(String,String,u32)>}
/// Owned output remains funded through actual transport/caller consumption.
/// Payload drops before credit; there is no public uncredited Vec extraction.
pub struct FundedBytes{bytes:Vec<u8>,credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
impl std::ops::Deref for FundedBytes{type Target=[u8];fn deref(&self)->&[u8]{&self.bytes}}
impl std::fmt::Debug for FundedBytes{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("FundedBytes").field("bytes",&self.bytes.len()).finish_non_exhaustive()}}
struct FundedWriter<'a>{bytes:&'a mut Vec<u8>,credit:&'a mut dm_preprocess::source_arena_credit::SourceArenaCredit,work:&'a dyn dm_preprocess::source_arena_credit::SourceArenaWork,first:Option<io::Error>}
impl Write for FundedWriter<'_>{fn write(&mut self,input:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::ErrorKind::Other.into())}let result=(||{let need=self.bytes.len().checked_add(input.len()).filter(|n|*n<=LIMIT).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;if need>self.bytes.capacity(){let cap=need.max(self.bytes.capacity().saturating_mul(2)).max(256);let grant=cap.checked_mul(4).and_then(|n|n.checked_add(64)).ok_or(io::ErrorKind::OutOfMemory)?;self.work.grow(self.credit,grant)?;self.bytes.try_reserve_exact(cap-self.bytes.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;if self.bytes.capacity()>grant{return Err(io::ErrorKind::OutOfMemory.into())}}self.bytes.extend_from_slice(input);Ok(input.len())})();match result{Ok(value)=>Ok(value),Err(first)=>{self.first=Some(first);Err(io::ErrorKind::Other.into())}}}fn flush(&mut self)->io::Result<()>{if self.first.is_some(){Err(io::ErrorKind::Other.into())}else{Ok(())}}}
struct BorrowedFailure<'a>(&'a(dyn Error+'static));impl Serialize for BorrowedFailure<'_>{fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeStruct;struct Display<'a>(&'a(dyn Error+'static));impl Serialize for Display<'_>{fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{s.collect_str(self.0)}}let mut row=s.serialize_struct("Failure",2)?;row.serialize_field("kind",&crate::request_failure::classify(self.0))?;row.serialize_field("message",&Display(self.0))?;row.end()}}
struct Kind(io::ErrorKind);impl Serialize for Kind{fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{struct Display(io::ErrorKind);impl std::fmt::Display for Display{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"{:?}",self.0)}}s.collect_str(&Display(self.0))}}
#[derive(Serialize)]#[serde(tag="kind",rename_all="snake_case")]
enum BorrowedPreparation<'a>{Current{semantic_revision:&'a str,source_revision:&'a str,policy_revision:&'a str},FailedRootOneShot{failure:BorrowedFailure<'a>,io_kind:Option<Kind>,os_code:Option<i32>}}
#[derive(Serialize)]struct BorrowedDerivedWire<'a>{schema:&'static str,complete:bool,full_policy_parity:bool,baseline:bool,clean:bool,preparation:BorrowedPreparation<'a>,lints:&'a[String],text:&'a str,allow_usage:&'a BTreeSet<(String,String,u32)>}
/// Closed actual host coordinator. Genuine current and failed-root callbacks
/// lend their SAME gate-held operation work; no counter/model is constructed.
pub fn with_derived_host_to(host:&mut crate::runner_host::BuildHost,request:AnalyzeRequest,diagnostics:&mut impl Write)->Result<(bool,FundedBytes),Box<dyn Error>>{with_derived_host_source_to(host,request,None,diagnostics)}
pub fn with_derived_host_from_to(host:&mut crate::runner_host::BuildHost,request:AnalyzeRequest,provider:&(dyn crate::input_snapshot::SnapshotProvider+Sync),diagnostics:&mut impl Write)->Result<(bool,FundedBytes),Box<dyn Error>>{with_derived_host_source_to(host,request,Some(provider),diagnostics)}
fn with_derived_host_source_to(host:&mut crate::runner_host::BuildHost,request:AnalyzeRequest,provider:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,diagnostics:&mut impl Write)->Result<(bool,FundedBytes),Box<dyn Error>>{
 request.validate(false)?;if request.lints.as_slice()!=["derived_reads"]{return Err(invalid("exclusive Derived selection required").into())}let workspace=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();
 let mut attempt=host.with_funded_derived_attempt_report_to(request.build.clone(),provider,diagnostics,|data,configuration,work|{let empty=LintScope::default();let meta=data.metadata();let scope=configuration.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);if let Some(required)=meta.missing_scope_lists(scope).next(){return Err(invalid(format!("{}: required list {required:?} is absent",meta.name)))}dq_analyze::policy_finish::admitted::derived(data,scope,&workspace.root,request.changed.as_deref(),request.raw,request.ci,work)})?;
 let preparation=attempt.preparation.take().expect("real funded factory returns actual preparation once");let rendered=match attempt.report.take(){Some(Ok(value))=>value,Some(Err(report))=>return Err(Box::new(DerivedOutputFailure{preparation:preparation.err(),report,credit:Some(attempt.credit)})),None=>return match preparation{Err(error)=>Err(error),Ok(_)=>Err(Box::new(DerivedOutputFailure{preparation:None,report:invalid("actual Derived preparation supplied no report"),credit:Some(attempt.credit)})as Box<dyn Error>)}};
 let borrowed=match &preparation{Ok(BuildOutcome::QueryPrepared{semantic_revision,source_revision,policy_revision:Some(policy_revision),retained:true})=>BorrowedPreparation::Current{semantic_revision,source_revision,policy_revision},Ok(_)=>return Err(Box::new(DerivedOutputFailure{preparation:None,report:invalid("Derived report lacks current Kind12 frame"),credit:Some(attempt.credit)})),Err(error)=>{let actual=actual_derived_io(error.as_ref());BorrowedPreparation::FailedRootOneShot{failure:BorrowedFailure(error.as_ref()),io_kind:actual.map(|e|Kind(e.kind())),os_code:actual.and_then(io::Error::raw_os_error)}}};
 let report=BorrowedDerivedWire{schema:"native-analyze-derived-report-v1",complete:true,full_policy_parity:false,baseline:false,clean:rendered.clean,preparation:borrowed,lints:&request.lints,text:&rendered.text,allow_usage:&rendered.allow_usage};let clean=rendered.clean;let mut bytes=Vec::new();
 let mut writer=FundedWriter{bytes:&mut bytes,credit:&mut attempt.credit,work:host.source_arena_work(),first:None};let encoded=serde_json::to_writer(&mut writer,&report).and_then(|_|writer.write_all(b"\n").map_err(serde_json::Error::io));let first=writer.first.take();drop(writer);drop(report);
 if let Some(report)=first{return Err(Box::new(DerivedOutputFailure{preparation:preparation.err(),report,credit:Some(attempt.credit)}))}if let Err(error)=encoded{return Err(Box::new(DerivedOutputFailure{preparation:preparation.err(),report:io::Error::other(error),credit:Some(attempt.credit)}))}
 drop(rendered);drop(preparation);Ok((clean,FundedBytes{bytes,credit:attempt.credit}))
}
#[derive(Serialize)]enum BorrowedDerivedReply<'a>{DerivedFragment{sequence:u32,offset:u64,bytes:&'a[u8]}}
pub(super) fn send_derived(stream:&mut impl Write,clean:bool,bytes:&FundedBytes,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork)->io::Result<()> {
 if bytes.len()>LIMIT{return Err(io::ErrorKind::OutOfMemory.into())}
 // serde_json numeric-byte encoding, geometric encoded Vec overlap and all
 // fixed fields are admitted BEFORE protocol::send creates its temporary Vec.
 let width=bytes.len().min(65_536);let _frame=work.reserve(width.checked_mul(18).and_then(|n|n.checked_add(4096)).ok_or(io::ErrorKind::OutOfMemory)?)?;
 let mut offset=0usize;for(sequence,part)in bytes.chunks(65_536).enumerate(){super::protocol::send(stream,&BorrowedDerivedReply::DerivedFragment{sequence:sequence as u32,offset:offset as u64,bytes:part})?;offset+=part.len()}super::protocol::send(stream,&super::protocol::Reply::DerivedFinished{clean,total:offset as u64,hash:xxhash_rust::xxh3::xxh3_128(bytes)})
}
#[path="analyze_derived_client.rs"]mod derived_client;
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub(super) enum AttemptKind{Derived,Handlers}
impl AttemptKind{
 pub(super) fn require(self,request:&AnalyzeRequest)->io::Result<()>{
  let name=match self{Self::Derived=>"derived_reads",Self::Handlers=>"sem/handlers"};
  if request.lints.as_slice()!=[name]{return Err(invalid("exclusive report transport family differs from its request"))}
  request.validate(false)
 }
}
fn route_derived(request:AnalyzeRequest,diagnostics:&mut impl Write)->Result<derived_client::Delivered,Box<dyn Error>>{route_attempt(request,AttemptKind::Derived,diagnostics)}
fn route_attempt(mut request:AnalyzeRequest,kind:AttemptKind,diagnostics:&mut impl Write)->Result<derived_client::Delivered,Box<dyn Error>>{
 kind.require(&request)?;if request.build.cache_root.is_none(){request.build.cache_root=Some(crate::request::client_cache_root()?)}
 if let Some(root)=&mut request.build.cache_root{if !root.is_absolute(){*root=std::env::current_dir()?.join(&*root)}}
 derived_client::receive(request,kind,diagnostics)
}

/// Preserve actual preparation as first error even if later callback/output IO
/// also failed. The secondary error stays owned rather than replacing source.
struct DerivedOutputFailure{preparation:Option<Box<dyn Error>>,report:io::Error,credit:Option<dm_preprocess::source_arena_credit::SourceArenaCredit>}
impl std::fmt::Debug for DerivedOutputFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("DerivedOutputFailure").field("preparation",&self.preparation).field("report",&self.report).finish_non_exhaustive()}}
impl std::fmt::Display for DerivedOutputFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{match &self.preparation{Some(error)=>std::fmt::Display::fmt(error,f),None=>std::fmt::Display::fmt(&self.report,f)}}}
impl Error for DerivedOutputFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.preparation.as_deref().unwrap_or(&self.report))}}

fn actual_derived_io<'a>(mut error:&'a(dyn Error+'static))->Option<&'a io::Error>{loop{if let Some(actual)=error.downcast_ref::<io::Error>(){return Some(actual)}error=error.source()?}}

#[cfg(test)]
#[path = "analyze_semantic_read_cohort_tests.rs"]
mod semantic_read_cohort_tests;

#[derive(Serialize)]#[serde(tag="kind",rename_all="snake_case")]
enum HandlerPreparation<'a>{
 Current{query_revision:&'a str,partial_source_revision:Option<&'a str>,full_source_revision:Option<&'a str>},
 FailedFullOneShot{failure:BorrowedFailure<'a>,io_kind:Option<Kind>,os_code:Option<i32>},
}
#[derive(Serialize)]struct HandlerReport<'a>{schema:&'static str,complete:bool,full_policy_parity:bool,baseline:bool,clean:bool,preparation:HandlerPreparation<'a>,lints:&'a[String],text:&'a str,allow_usage:&'a BTreeSet<(String,String,u32)>}
pub(super) fn with_handlers_host_to(host:&mut crate::runner_host::BuildHost,request:AnalyzeRequest,diagnostics:&mut impl Write)->Result<(bool,FundedBytes),Box<dyn Error>>{with_handlers_host_source_to(host,request,None,diagnostics)}
/// Embedding callers can lend the same real source provider as native PrepareQuery.
pub fn with_handlers_host_from_to(host:&mut crate::runner_host::BuildHost,request:AnalyzeRequest,provider:&(dyn crate::input_snapshot::SnapshotProvider+Sync),diagnostics:&mut impl Write)->Result<(bool,FundedBytes),Box<dyn Error>>{with_handlers_host_source_to(host,request,Some(provider),diagnostics)}
fn with_handlers_host_source_to(host:&mut crate::runner_host::BuildHost,request:AnalyzeRequest,provider:Option<&(dyn crate::input_snapshot::SnapshotProvider+Sync)>,diagnostics:&mut impl Write)->Result<(bool,FundedBytes),Box<dyn Error>>{
 AttemptKind::Handlers.require(&request)?;
 let workspace=request.build.policy_inputs.as_ref().unwrap().workspace.as_ref().unwrap();
 let mut attempt=host.with_funded_handlers_attempt_report_to(request.build.clone(),provider,diagnostics,|data,configuration,complete,work|{
  let empty=LintScope::default();let meta=data.metadata();let scope=configuration.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);
  if let Some(required)=meta.missing_scope_lists(scope).next(){return Err(invalid(format!("{}: required list {required:?} is absent",meta.name)))}
  dq_analyze::policy_finish::admitted::handlers(data,scope,&workspace.root,request.changed.as_deref(),request.raw,request.ci,complete,work)
 })?;
 let preparation=attempt.preparation;
 let rendered=match attempt.report.take(){
  Some(Ok(value))=>value,
  Some(Err(report))=>return Err(Box::new(DerivedOutputFailure{preparation:preparation.err(),report,credit:Some(attempt.credit)})),
  None=>return match preparation{Err(error)=>Err(error),Ok(_)=>Err(Box::new(DerivedOutputFailure{preparation:None,report:invalid("actual handlers preparation supplied no report"),credit:Some(attempt.credit)})as Box<dyn Error>)},
 };
 let (complete,borrowed)=match &preparation{
  Ok(BuildOutcome::HandlersQueryPrepared{query_revision,partial_source_revision,full_source_revision,retained:true})=>(true,HandlerPreparation::Current{query_revision,partial_source_revision:partial_source_revision.as_deref(),full_source_revision:full_source_revision.as_deref()}),
  Ok(_)=>return Err(Box::new(DerivedOutputFailure{preparation:None,report:invalid("handler report lacks actual current preparation"),credit:Some(attempt.credit)})),
  // A callback can reach here only with its same failed-root disposition.
  Err(error)=>{let actual=actual_derived_io(error.as_ref());(false,HandlerPreparation::FailedFullOneShot{failure:BorrowedFailure(error.as_ref()),io_kind:actual.map(|e|Kind(e.kind())),os_code:actual.and_then(io::Error::raw_os_error)})},
 };
 let clean=complete&&rendered.clean;
 let report=HandlerReport{schema:"native-analyze-handlers-report-v1",complete,full_policy_parity:false,baseline:false,clean,preparation:borrowed,lints:&request.lints,text:&rendered.text,allow_usage:&rendered.allow_usage};
 let mut bytes=Vec::new();
 let mut writer=FundedWriter{bytes:&mut bytes,credit:&mut attempt.credit,work:host.source_arena_work(),first:None};
 let encoded=serde_json::to_writer(&mut writer,&report).and_then(|_|writer.write_all(b"\n").map_err(serde_json::Error::io));
 let first=writer.first.take();drop(writer);drop(report);
 if let Some(report)=first{return Err(Box::new(DerivedOutputFailure{preparation:preparation.err(),report,credit:Some(attempt.credit)}))}
 if let Err(error)=encoded{return Err(Box::new(DerivedOutputFailure{preparation:preparation.err(),report:io::Error::other(error),credit:Some(attempt.credit)}))}
 drop(rendered);drop(preparation);Ok((clean,FundedBytes{bytes,credit:attempt.credit}))
}
