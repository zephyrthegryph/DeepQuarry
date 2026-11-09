//! Explicit complete selected Sys report. Each page refolds its original policy.
//! No retained source/Budget cache or shared-warm-work claim is made here.
use super::SourceSnapshot;
use dq_analyze::{captured_sys_hygiene_pages::HygieneData,scopes::LintScope,captured_generator_budget::Budget};
use serde::{Serialize,Serializer,ser::SerializeSeq};
use std::{io::{self,Write},path::Path,mem::size_of};
trait ReportData{
 fn sites(&self)->&[dq_analyze::lint::Site];fn text_at(&self,index:usize)->io::Result<Option<&str>>;fn require_text_shape(&self)->io::Result<()>;
 fn allow_used(&self)->&[dq_analyze::lint::AllowUse];fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>;
 fn doc_blocks(&self)->Option<&[dq_analyze::doc_snippets_policy::SummaryBlock]>{None}
 fn message_only(&self)->bool{false}
 fn notes(&self)->&[String]{&[]}fn macro_ceiling(&self)->Option<i64>{None}
}
macro_rules! data_view{($($ty:path),+)=>{$(impl ReportData for $ty{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,index:usize)->io::Result<Option<&str>>{self.source_text().get(index).map(|s|Some(s.as_str())).ok_or_else(||io::Error::other("completed site text absent"))}fn require_text_shape(&self)->io::Result<()>{if self.sites().len()==self.source_text().len(){Ok(())}else{Err(io::Error::other("completed site text shape differs"))}}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}})+};}
data_view!(dq_analyze::captured_silicon_entry::Data,dq_analyze::captured_sys_reactive::Data,dq_analyze::captured_stored_refs_pages::StoredData,dq_analyze::captured_requirement_bool_pages::RequirementData,dq_analyze::captured_init_pages::InitData,dq_analyze::captured_decl_pages::DeclData,HygieneData,dq_analyze::captured_sys_resolvers_pages::ResolverData,dq_analyze::captured_sys_tables_pages::TablesData,dq_analyze::captured_system_boundary_pages::BoundaryData);
fn raw_tree_text_shape(message_only:bool,sites:&[dq_analyze::lint::Site],text:&[String])->io::Result<()>{
 if message_only{if text.is_empty()&&sites.iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("raw tree message-only findings have source text or absent messages"))}}
 else if sites.len()==text.len(){Ok(())}else{Err(io::Error::other("raw tree actual source text shape differs"))}
}
impl ReportData for dq_analyze::captured_untyped_pages::UntypedData {
    fn sites(&self) -> &[dq_analyze::lint::Site] { self.sites() }
    fn text_at(&self, _index: usize) -> io::Result<Option<&str>> { Ok(None) }
    fn require_text_shape(&self) -> io::Result<()> {
        if self.sites().iter().all(|site| !site.msg.is_empty()) { Ok(()) }
        else { Err(io::Error::other("untyped Hard finding has no message")) }
    }
    fn message_only(&self) -> bool { true }
    fn allow_used(&self) -> &[dq_analyze::lint::AllowUse] { self.allow_used() }
    fn allow_source_digest(&self, relative: &str) -> Option<&[u8; 20]> {
        self.allow_source_digest(relative)
    }
}
impl ReportData for dq_analyze::captured_raw_tree_pages::Data{
 fn doc_blocks(&self)->Option<&[dq_analyze::doc_snippets_policy::SummaryBlock]>{self.doc_blocks()}
 fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}
 fn text_at(&self,index:usize)->io::Result<Option<&str>>{if self.message_only(){if index<self.sites().len(){Ok(None)}else{Err(io::Error::other("raw tree actual message finding absent"))}}else{self.source_text().get(index).map(|s|Some(s.as_str())).ok_or_else(||io::Error::other("raw tree actual source text absent"))}}
 fn require_text_shape(&self)->io::Result<()>{raw_tree_text_shape(self.message_only(),self.sites(),self.source_text())}
 fn message_only(&self)->bool{dq_analyze::captured_raw_tree_pages::Data::message_only(self)}
 fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}
 fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}
 fn notes(&self)->&[String]{self.notes()}
}
impl ReportData for dq_analyze::captured_keys_pages::KeyData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_index:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("hard policy message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}}
impl ReportData for dq_analyze::captured_player_link_pages::PlayerData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_index:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("hard policy message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}}
impl ReportData for dq_analyze::captured_untyped_member_pages::MemberData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_index:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("hard policy message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}}
impl ReportData for dq_analyze::captured_weak_raw_read_pages::WeakData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_index:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("hard policy message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}}
impl ReportData for dq_analyze::captured_rel_write_pages::RelationData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_index:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("hard policy message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}}
impl ReportData for dq_analyze::captured_sem_reads::SemanticPolicyData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_index:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("hard policy message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}}
impl ReportData for dq_analyze::lints::check_grep::native::Output{
 fn sites(&self)->&[dq_analyze::lint::Site]{&self.run.sites}
 fn text_at(&self,index:usize)->io::Result<Option<&str>>{let site=self.run.sites.get(index).ok_or_else(||io::Error::other("CheckGrep site absent"))?;if site.msg.is_empty(){self.source_line(&site.rel,site.line).map(Some).ok_or_else(||io::Error::other("CheckGrep required original line absent"))}else{Ok(None)}}
 fn require_text_shape(&self)->io::Result<()>{for index in 0..self.run.sites.len(){self.text_at(index)?;}Ok(())}
 fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{&self.allow_used}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}
 fn notes(&self)->&[String]{&self.run.notes}fn macro_ceiling(&self)->Option<i64>{Some(self.macro_ceiling)}
}
impl ReportData for dq_analyze::lints::check_grep::native::BaselineData{
 fn sites(&self)->&[dq_analyze::lint::Site]{&self.run.sites}
 fn text_at(&self,index:usize)->io::Result<Option<&str>>{let site=self.run.sites.get(index).ok_or_else(||io::Error::other("CheckGrep site absent"))?;if site.msg.is_empty(){self.source_line(&site.rel,site.line).map(Some).ok_or_else(||io::Error::other("CheckGrep required original line absent"))}else{Ok(None)}}
 fn require_text_shape(&self)->io::Result<()>{for index in 0..self.run.sites.len(){self.text_at(index)?;}Ok(())}
 fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{&self.allow_used}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}
 fn notes(&self)->&[String]{&self.run.notes}
}

impl ReportData for dq_analyze::workspace_fold_policy::Data<'_>{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,index:usize)->io::Result<Option<&str>>{match self.source_text(){Some(text)=>text.get(index).map(|s|Some(s.as_str())).ok_or_else(||io::Error::other("completed collector source text absent")),None=>Ok(None)}}fn require_text_shape(&self)->io::Result<()>{match self.source_text(){Some(text)if text.len()==self.sites().len()=>Ok(()),None if self.sites().iter().all(|site|!site.msg.is_empty())=>Ok(()),_=>Err(io::Error::other("completed collector report shape differs"))}}fn message_only(&self)->bool{self.source_text().is_none()}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}fn notes(&self)->&[String]{self.notes()}}
impl ReportData for dq_analyze::captured_base_vars_pages::BaseVarsData{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,index:usize)->io::Result<Option<&str>>{self.source_text().get(index).map(|text|Some(text.as_str())).ok_or_else(||io::Error::other("base-vars current source text absent"))}fn require_text_shape(&self)->io::Result<()>{if self.sites().len()==self.source_text().len(){Ok(())}else{Err(io::Error::other("base-vars original site/text shape differs"))}}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_source_digest(relative)}fn notes(&self)->&[String]{self.notes()}}

fn oom()->io::Error{io::ErrorKind::OutOfMemory.into()}
fn charge(b:&Budget,n:Option<usize>)->io::Result<()>{b.charge(n.ok_or_else(oom)?).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))}
struct Count(usize);impl Write for Count{fn write(&mut self,b:&[u8])->io::Result<usize>{self.0=self.0.checked_add(b.len()).ok_or_else(oom)?;Ok(b.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
struct Fixed(Vec<u8>);impl Write for Fixed{fn write(&mut self,b:&[u8])->io::Result<usize>{if b.len()>self.0.capacity()-self.0.len(){return Err(oom())}self.0.extend_from_slice(b);Ok(b.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
fn scope_json(scope:&LintScope,budget:&Budget)->io::Result<Fixed>{let row=(&scope.exempt_prefixes,&scope.exempt_contains,&scope.exempt_files,&scope.lists,&scope.tables,&scope.ceilings,&scope.reason_codes);let mut count=Count(0);serde_json::to_writer(&mut count,&row).map_err(io::Error::from)?;let max=count.0.checked_mul(4).ok_or_else(oom)?;charge(budget,max.checked_add(size_of::<Fixed>()+64))?;let mut out=Fixed(Vec::new());out.0.try_reserve_exact(count.0).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if out.0.capacity()>max{return Err(oom())}serde_json::to_writer(&mut out,&row).map_err(io::Error::from)?;Ok(out)}
struct Hex<'a>(&'a [u8;20]);impl Serialize for Hex<'_>{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{let mut text=[0u8;40];for(i,b)in self.0.iter().enumerate(){text[2*i]=b"0123456789abcdef"[(b>>4)as usize];text[2*i+1]=b"0123456789abcdef"[(b&15)as usize];}s.serialize_str(std::str::from_utf8(&text).expect("hex is ASCII"))}}
struct Items<'a>{data:&'a dyn ReportData,name:&'static str,start:usize,end:usize}
impl Serialize for Items<'_>{fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error>{let mut out=s.serialize_seq(Some(self.end-self.start))?;for index in self.start..self.end{
 if index<self.data.sites().len(){let site=&self.data.sites()[index];if self.data.message_only(){if (!matches!(self.name,"sem/keys"|"sem/reads"|"untracked_inputs"|"setter_publishes"|"engine_layering"|"ownership"|"player_link"|"untyped"|"untyped_member"|"weak_raw_read"|"rel_write_undeclared"|"map_edits")&&!dq_analyze::workspace_fold_policy::Policy::from_name(self.name).is_some_and(|p|p.message_only()&&matches!(p.metadata().policy,dq_analyze::lint::Policy::Hard))&&!dq_analyze::captured_raw_tree_pages::Policy::from_name(self.name).is_some_and(|p|p.message_only()&&matches!(p.metadata().policy,dq_analyze::lint::Policy::Hard)))||site.msg.is_empty(){return Err(serde::ser::Error::custom("unissued message-only finding"))}#[derive(Serialize)]struct HardSite<'a>{lint:&'static str,kind:&'static str,site:&'a dq_analyze::lint::Site}out.serialize_element(&HardSite{lint:self.name,kind:"hard_site",site})?;continue}let text=self.data.text_at(index).map_err(serde::ser::Error::custom)?;#[derive(Serialize)]struct Site<'a>{lint:&'static str,kind:&'static str,site:&'a dq_analyze::lint::Site,source_text:Option<&'a str>}out.serialize_element(&Site{lint:self.name,kind:"site",site,source_text:text})?;}
 else if index<self.data.sites().len()+self.data.allow_used().len(){let used=&self.data.allow_used()[index-self.data.sites().len()];let digest=self.data.allow_source_digest(&used.rel).ok_or_else(||serde::ser::Error::custom("ALLOW original fingerprint absent"))?;#[derive(Serialize)]struct Allow<'a>{lint:&'static str,kind:&'static str,allow:&'a dq_analyze::lint::AllowUse,source_digest:Hex<'a>}out.serialize_element(&Allow{lint:self.name,kind:"allow",allow:used,source_digest:Hex(digest)})?;}
 else if index<self.data.sites().len()+self.data.allow_used().len()+self.data.notes().len(){let note=&self.data.notes()[index-self.data.sites().len()-self.data.allow_used().len()];#[derive(Serialize)]struct Note<'a>{lint:&'static str,kind:&'static str,text:&'a str}out.serialize_element(&Note{lint:self.name,kind:"note",text:note})?;}
 else{if self.name!="doc_snippets"{return Err(serde::ser::Error::custom("unissued doc summary role"))}let blocks=self.data.doc_blocks().ok_or_else(||serde::ser::Error::custom("doc summary absent"))?;let row=index-self.data.sites().len()-self.data.allow_used().len()-self.data.notes().len();if row<blocks.len(){#[derive(Serialize)]struct Block<'a>{lint:&'static str,kind:&'static str,block:&'a dq_analyze::doc_snippets_policy::SummaryBlock}out.serialize_element(&Block{lint:self.name,kind:"doc_block",block:&blocks[row]})?;}else if row==blocks.len(){#[derive(Serialize)]struct Complete{lint:&'static str,kind:&'static str,count:usize}out.serialize_element(&Complete{lint:self.name,kind:"doc_complete",count:blocks.len()})?;}else{return Err(serde::ser::Error::custom("doc summary row out of bounds"))}}
 }out.end()}}

struct Hash(xxhash_rust::xxh3::Xxh3);impl Write for Hash{fn write(&mut self,b:&[u8])->io::Result<usize>{self.0.update(b);Ok(b.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
#[derive(Serialize)]struct Next<'a>{aggregate_id:&'a str,offset:usize}
#[derive(Serialize)]struct Page<'a>{row:&'static str,schema:&'static str,semantic_revision:&'a str,source_revision:&'a str,policy_revision:&'a str,snapshot_as_of:&'static str,root:&'a Path,configuration:&'a Path,recursive_roots:&'a [std::path::PathBuf],requested_lints:&'a [String],lint_whitelist:[&'static str;1],scope:&'static str,full_policy_parity:bool,baseline_applied:bool,admission:&'static str,configuration_scope:&'static str,aggregate_id:&'a str,offset:usize,count:usize,total_items:usize,next_cursor:Option<Next<'a>>,items:Items<'a>,policy_scopes:[(&'static str,&'a str);1],#[serde(skip_serializing_if="Option::is_none")]macro_ceiling:Option<i64>}
struct ReportFrame<'a>{root:&'a Path,configuration:&'a Path,recursive_roots:&'a[std::path::PathBuf],semantic:u128,source:u128,policy:u128,configuration_present:bool,grep_purpose:Option<dq_analyze::lints::check_grep::native::Purpose>}
fn write_data_page(data:&dyn ReportData,name:&'static str,frame:&ReportFrame<'_>,exact:&str,budget:&std::sync::Arc<Budget>,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,output:&mut impl Write,current:&mut dyn FnMut()->io::Result<()>)->io::Result<()>{
 let complete_policy=dq_analyze::workspace_fold_policy::Policy::from_name(name);let raw_tree_policy=dq_analyze::captured_raw_tree_pages::Policy::from_name(name);let raw_tree=raw_tree_policy.is_some();let hygiene=name=="sys/hygiene";let keys=name=="sem/keys";let semantic_family=crate::daemon::query::semantic_report_metadata(name).is_some();let grep=name=="check_grep";let baseline=frame.grep_purpose==Some(dq_analyze::lints::check_grep::native::Purpose::Baseline);if grep!=frame.grep_purpose.is_some(){return Err(io::Error::other("report purpose differs from actual family"))}
   let total=data.sites().len().checked_add(data.allow_used().len()).and_then(|n|n.checked_add(data.notes().len())).and_then(|n|match data.doc_blocks(){Some(blocks)=>n.checked_add(blocks.len())?.checked_add(1),None=>Some(n)}).ok_or_else(oom)?;data.require_text_shape()?;if data.doc_blocks().is_some()!=(name=="doc_snippets"){return Err(io::Error::other("custom doc summary differs from its actual closed role"))}let hard=match name{"map_edits"=>Some(&dq_analyze::map_edits_policy::META),"lifeforms"=>Some(dq_analyze::lifeforms_policy::metadata()),"engine_layering"=>Some(dq_analyze::engine_layering_policy::metadata()),"ownership"=>Some(dq_analyze::ownership_policy::metadata()),"rel_write_undeclared"=>Some(dq_analyze::rel_write_policy::metadata()),"weak_raw_read"=>Some(dq_analyze::weak_relation_policy::metadata()),"untyped_member"=>Some(dq_analyze::untyped_member_policy::metadata()),"untyped"=>Some(dq_analyze::untyped_policy_metadata::metadata()),"player_link"=>Some(dq_analyze::player_link_policy::metadata()),"sem/keys"=>Some(dq_analyze::keys_policy::metadata()),"sem/reads"=>Some(dq_analyze::sem_reads_policy::metadata()),"untracked_inputs"=>Some(dq_analyze::untracked_inputs_policy::metadata()),"setter_publishes"=>Some(dq_analyze::setter_publication_policy::metadata()),_=>complete_policy.filter(|p|p.message_only()).map(|p|p.metadata()).or_else(||raw_tree_policy.filter(|p|p.message_only()).map(|p|p.metadata()))};if data.message_only()!=hard.is_some()||hard.is_some_and(|meta|!matches!(meta.policy,dq_analyze::lint::Policy::Hard)){return Err(io::Error::other("message-only findings lack actual Hard contract"))}let macro_ceiling=data.macro_ceiling();if (grep&&!baseline)!=macro_ceiling.is_some(){return Err(io::Error::other("report context differs from actual family"))}
   // Fixed pin/cursor strings are funded before formatting/clone. This does
   // not claim serde/parser/global allocator geometry or process RSS.
   charge(budget,Some(2048))?;let semantic=format!("{:032x}",frame.semantic);let source=format!("{:032x}",frame.source);let policy=format!("{:032x}",frame.policy);let mut hash=Hash(xxhash_rust::xxh3::Xxh3::new());if grep{if baseline{hash.0.update(b"native-check-grep-baseline-report-v1")}else{hash.0.update(b"native-check-grep-complete-report-v1");hash.0.update(&macro_ceiling.unwrap().to_le_bytes())}}else if complete_policy.is_some(){hash.0.update(b"native-complete-policy-report-v1");hash.0.update(name.as_bytes());}else if raw_tree{hash.0.update(b"native-raw-tree-complete-report-v1");hash.0.update(name.as_bytes());}else if semantic_family{hash.0.update(b"native-semantic-complete-report-v1");hash.0.update(name.as_bytes());}else if keys{hash.0.update(b"native-keys-complete-report-v1")}else if hygiene{hash.0.update(b"native-hygiene-complete-report-v1")}else{hash.0.update(b"native-sys-complete-report-v1");hash.0.update(name.as_bytes());}serde_json::to_writer(&mut hash,&(&semantic,&source,&policy,frame.root,frame.configuration,exact,Items{data,name,start:0,end:total})).map_err(io::Error::from)?;let id=format!("{:032x}",hash.0.digest128());let start=cursor.map_or(0,|c|c.offset());if start>total||cursor.is_some_and(|c|c.aggregate_id()!=id){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Hygiene cursor belongs to another complete ordered result"))}
   let mut count=limit.min(total-start);loop{let end=start.checked_add(count).ok_or_else(oom)?;let page=Page{row:if baseline{"source_native_workspace_check_grep_baseline_report"}else if grep{"source_native_workspace_check_grep_report"}else if complete_policy.is_some(){"source_native_workspace_policy_report"}else if raw_tree{"source_native_workspace_raw_tree_report"}else if semantic_family{"source_native_workspace_semantic_report"}else if keys{"source_native_workspace_keys_report"}else if hygiene{"source_native_workspace_hygiene_report"}else{"source_native_workspace_sys_report"},schema:"dm-session-source-query-v1",semantic_revision:&semantic,source_revision:&source,policy_revision:&policy,snapshot_as_of:"policy_revision",root:frame.root,configuration:frame.configuration,recursive_roots:frame.recursive_roots,requested_lints:lints,lint_whitelist:[name],scope:if baseline{"typed_discovery_complete_check_grep_baseline"}else if grep{"typed_discovery_complete_check_grep"}else if complete_policy.is_some(){"typed_discovery_complete_policy"}else if raw_tree{"typed_discovery_complete_raw_tree"}else if semantic_family{"typed_discovery_complete_semantic"}else if keys{"typed_discovery_complete_keys"}else if hygiene{"typed_discovery_complete_hygiene"}else{"typed_discovery_complete_sys_family"},full_policy_parity:false,baseline_applied:false,admission:if baseline{"complete_selected_check_grep_baseline_findings"}else if grep{"complete_selected_check_grep_findings"}else if complete_policy.is_some(){"complete_selected_policy_findings"}else if raw_tree{"complete_selected_raw_tree_findings"}else if semantic_family{"complete_selected_semantic_findings"}else if keys{"complete_selected_keys_findings"}else if hygiene{"complete_selected_hygiene_findings"}else{"complete_selected_sys_findings"},configuration_scope:if frame.configuration_present{"captured_configuration_bytes"}else{"proven_missing_configuration"},aggregate_id:&id,offset:start,count,total_items:total,next_cursor:if end<total{Some(Next{aggregate_id:&id,offset:end})}else{None},items:Items{data,name,start,end},policy_scopes:[(name,exact)],macro_ceiling};let mut measured=Count(0);serde_json::to_writer(&mut measured,&page).map_err(io::Error::from)?;if measured.0.checked_add(1).is_none_or(|n|n>crate::daemon::query::MAX_OUTPUT){if count>1{count=(count/2).max(1);continue}return Err(io::Error::new(io::ErrorKind::OutOfMemory,"one Hygiene report record exceeds unchanged query wire bound"))}
    charge(budget,measured.0.checked_mul(4).and_then(|n|n.checked_add(1024)))?;budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;current()?;serde_json::to_writer(&mut *output,&page).map_err(io::Error::from)?;output.write_all(b"\n")?;budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;current()?;return Ok(())}
}

impl SourceSnapshot{
 pub(crate) fn write_native_workspace_check_grep_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{self.write_native_workspace_check_grep_page_using(dq_analyze::lints::check_grep::native::Purpose::Check,root,configuration,lints,cursor,limit,tree,output)}
 pub(crate) fn write_native_workspace_check_grep_baseline_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{self.write_native_workspace_check_grep_page_using(dq_analyze::lints::check_grep::native::Purpose::Baseline,root,configuration,lints,cursor,limit,tree,output)}
 fn write_native_workspace_check_grep_page_using(&self,purpose:dq_analyze::lints::check_grep::native::Purpose,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  if lints.len()!=1||lints[0]!="check_grep"||!(1..=128).contains(&limit){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact CheckGrep report request required"))}
  self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual CheckGrep workspace required"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("CheckGrep report workspace/configuration differs"))}
  // Match the real-DME branch of the unique old Sem::build_with. The synthetic
  // all-CODE subject is a distinct future issuer, never inferred from this context.
  self.require_original_analyze_subject(&capture)?;
  let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:Some(purpose)};
  let mut render=|data:&dyn ReportData,scope:&dq_analyze::captured_raw_file::Scope,budget:&std::sync::Arc<Budget>|{let exact=scope.report_scope_json().map_err(|error|dq_analyze::captured_reactive_reads::Failure::Unsupported(error.to_string()))?;write_data_page(data,"check_grep",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()}).map_err(dq_analyze::captured_reactive_reads::Failure::Operational)};
  let pending=match purpose{dq_analyze::lints::check_grep::native::Purpose::Check=>self.with_native_check_grep_report(tree,|data,scope,budget|render(data,scope,budget)),dq_analyze::lints::check_grep::native::Purpose::Baseline=>self.with_native_check_grep_baseline_report(tree,|data,scope,budget|render(data,scope,budget))};pending.map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
 }
 pub(crate) fn write_native_workspace_hygiene_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  if lints.len()!=1||lints[0]!="sys/hygiene"{return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact Hygiene report selection required"))}self.write_native_workspace_complete_fold(root,configuration,lints,cursor,limit,tree,output)
 }
 pub(crate) fn write_native_workspace_sys_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  if lints.len()!=1||!matches!(lints[0].as_str(),"sys/resolvers"|"sys/tables"|"system_boundary"){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed Sys family selection required"))}self.write_native_workspace_complete_fold(root,configuration,lints,cursor,limit,tree,output)
 }
 pub(crate) fn write_native_workspace_keys_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{if lints.len()!=1||lints[0]!="sem/keys"{return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact selected Keys report required"))}self.write_native_workspace_complete_fold(root,configuration,lints,cursor,limit,tree,output)}
 fn write_native_workspace_complete_fold(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  let name=match lints.first().map(String::as_str){Some("sys/hygiene")=>"sys/hygiene",Some("sys/resolvers")=>"sys/resolvers",Some("sys/tables")=>"sys/tables",Some("system_boundary")=>"system_boundary",Some("sem/keys")=>"sem/keys",_=>return Err(io::ErrorKind::InvalidInput.into())};let keys=name=="sem/keys";let group=if keys{"sem"}else if name=="system_boundary"{""}else{"sys"};

  crate::daemon::control::checkpoint()?;if !self.matches_tree(tree)||lints.len()!=1||!(1..=128).contains(&limit){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact Hygiene report selection required"))}
  let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual workspace capture required"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("Hygiene report requires actual current workspace configuration"))}let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;let db=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("Hygiene report requires same native QueryDb"))?;
  let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
  let mut render=|data:&dyn ReportData,config:&dq_analyze::captured_raw_file::Config,budget:&std::sync::Arc<Budget>|{
   let empty=LintScope::default();let captured=config.borrowed_report_scope(name,group).unwrap_or(&empty);let exact=scope_json(captured,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;
   write_data_page(data,name,&frame,exact,budget,lints,cursor,limit,output,&mut||{crate::daemon::control::checkpoint()?;capture.require_scope(&guard)})
  };
  match name{"sem/keys"=>db.with_workspace_keys(capture,&guard,|data,config,budget|render(data,config,budget)).map_err(|error|match error{dq_analyze::captured_reactive_reads::Failure::Operational(error)=>error,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::other(message)}),"sys/hygiene"=>db.with_workspace_hygiene_report(capture,&guard,|data,config,budget|render(data,config,budget)),"sys/resolvers"=>db.with_workspace_resolvers_report(capture,&guard,|data,config,budget|render(data,config,budget)),"sys/tables"=>db.with_workspace_tables_report(capture,&guard,|data,config,budget|render(data,config,budget)),"system_boundary"=>db.with_workspace_boundary_report(capture,&guard,|data,config,budget|render(data,config,budget)),_=>unreachable!("closed literal family dispatch")}
 }
}

impl SourceSnapshot{
 pub(crate) fn write_native_workspace_semantic_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  for question in [crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering,crate::policy_request::WorkspaceAuxiliaryQuestion::LibraryLayering]{
   let layer=question.layering().expect("closed layering report question");
   if lints==[layer.name()]{return self.write_native_workspace_layering_report_page(question,root,configuration,lints,cursor,limit,tree,output)}
  }
  if lints==["lifeforms"]{return self.write_native_workspace_lifeforms_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["sys/dx_reactive"]{return self.write_native_workspace_sys_reactive_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["stored_refs"]{return self.write_native_workspace_stored_refs_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["untyped"]{return self.write_native_workspace_untyped_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["rel_write_undeclared"]{return self.write_native_workspace_rel_write_undeclared_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["weak_raw_read"]{return self.write_native_workspace_weak_raw_read_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["map_edits"]{return self.write_native_workspace_map_edits_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["silicon_entry"]{return self.write_native_workspace_silicon_entry_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["untyped_member"]{return self.write_native_workspace_untyped_member_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["player_link"]{return self.write_native_workspace_player_link_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["requirement_bool"]{return self.write_native_workspace_requirement_bool_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["base_vars"]{return self.write_native_workspace_base_vars_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["init"]{return self.write_native_workspace_init_report_page(root,configuration,lints,cursor,limit,tree,output)}
  if lints==["decl"]{return self.write_native_workspace_decl_report_page(root,configuration,lints,cursor,limit,tree,output)}
  use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
  let(name,question,meta)=match lints.first().map(String::as_str){Some("sem/reads")=>("sem/reads",Q::SemReads,dq_analyze::sem_reads_policy::metadata()),Some("untracked_inputs")=>("untracked_inputs",Q::UntrackedInputs,dq_analyze::untracked_inputs_policy::metadata()),Some("setter_publishes")=>("setter_publishes",Q::SetterPublishes,dq_analyze::setter_publication_policy::metadata()),_=>return Err(io::ErrorKind::InvalidInput.into())};
  if lints.len()!=1||!(1..=128).contains(&limit)||!self.matches_tree(tree)||!matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact actual Hard semantic report required"))}
  self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual semantic workspace absent"))?;
  if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("semantic report capture differs"))}
  // Public real-DME subject only. Private alternate-project proofs grant no
  // synthetic or empty old-Sem subject and remain separate.
  self.require_original_analyze_subject(&capture)?;
  let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
  self.with_original_semantic_policy_report(question,|data,config,budget|{
   let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;
   write_data_page(data,name,&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;crate::daemon::control::checkpoint()})
  })
 }
}

impl SourceSnapshot{
 pub(crate) fn require_original_fixed_report_subject(&self,tree:&dm_tree::SemanticTree)->io::Result<()>{
  self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  if !self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original report subject tree differs"))}
  let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual Original report workspace absent"))?;
  let mapping=self.source_mapping.as_ref().ok_or_else(||io::Error::other("actual Original report mapping absent"))?;
  let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;
  let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("actual Original report QueryDb absent"))?;
  queries.require_original_fixed_report_subject(capture,&guard,mapping).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
 }
}

impl SourceSnapshot{
 fn require_original_analyze_subject(&self,capture:&crate::runner_host::workspace_capture::WorkspaceCapture)->io::Result<()>{
  if let Some(subject)=&self.analysis_subject{
   let mapping=self.source_mapping.as_ref().ok_or_else(||io::Error::other("actual Analyze source mapping absent"))?;
   let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;subject.require_bound_mapping(mapping)?;return capture.require_analysis_subject(subject)
  }
  self.require_original_fixed_report_subject(&self.tree)
 }
}

struct MapEditsReport<'a>(&'a [dq_analyze::lint::Site]);
impl ReportData for MapEditsReport<'_> {
    fn sites(&self) -> &[dq_analyze::lint::Site] { self.0 }
    fn text_at(&self, _: usize) -> io::Result<Option<&str>> { Ok(None) }
    fn require_text_shape(&self) -> io::Result<()> {
        if self.0.iter().any(|site| site.msg.is_empty()) {
            Err(io::Error::other("map_edits hard finding has no message"))
        } else { Ok(()) }
    }
    fn message_only(&self) -> bool { true }
    fn allow_used(&self) -> &[dq_analyze::lint::AllowUse] { &[] }
    fn allow_source_digest(&self, _: &str) -> Option<&[u8; 20]> { None }
}

impl SourceSnapshot {
    fn write_native_workspace_map_edits_report_page(
        &self, root: &Path, configuration: &Path, lints: &[String],
        cursor: Option<&crate::query_db::WorkspaceCursor>, limit: usize,
        tree: &dm_tree::SemanticTree, output: &mut impl Write,
    ) -> io::Result<()> {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        use dq_analyze::map_edits_policy::META;
        if lints != ["map_edits"] || !(1..=128).contains(&limit) || !self.matches_tree(tree) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "exact map_edits report required"));
        }
        self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
        let workspace = self.native_workspace.as_ref().ok_or_else(|| io::Error::other("map_edits workspace absent"))?;
        if root != workspace.root() || configuration != workspace.configuration().0
            || self.policy_revision != Some(workspace.policy_revision())
            || !workspace.matches_auxiliary_questions(&[Q::MapEdits]) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits capture differs"));
        }
        let frame = ReportFrame { root, configuration, recursive_roots: workspace.recursive_roots(),
            semantic: tree.identity(), source: self.source_revision, policy: workspace.policy_revision(),
            configuration_present: workspace.configuration().1.is_some(), grep_purpose: None };
        self.with_original_map_edits_policy(tree, |sites, config, budget, checkpoint| {
            let empty = LintScope::default();
            let scope = config.borrowed_report_scope(META.name, META.group).unwrap_or(&empty);
            let exact = scope_json(scope, budget)?;
            let exact = std::str::from_utf8(&exact.0).map_err(io::Error::other)?;
            write_data_page(&MapEditsReport(sites), META.name, &frame, exact, budget, lints,
                cursor, limit, output, &mut || checkpoint())?;
            Ok(())
        })
    }

    pub(super) fn with_original_map_edits_policy<R>(
        &self, tree: &dm_tree::SemanticTree,
        consume: impl FnOnce(&[dq_analyze::lint::Site], &dq_analyze::captured_raw_file::Config, &std::sync::Arc<Budget>, &dyn Fn() -> io::Result<()>) -> io::Result<R>,
    ) -> io::Result<R> {
        use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
        use dq_analyze::{
            captured_allow_annotations::Operation,
            captured_raw_file::Config, captured_raw_policy::Configuration,
            captured_reactive_reads::Failure, map_edits_policy::{self, CodeNames},
        };
        if !self.matches_tree(tree) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "exact map_edits model required"));
        }
        self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
        let workspace = self.native_workspace.as_ref().ok_or_else(|| io::Error::other("map_edits workspace absent"))?;
        if self.policy_revision != Some(workspace.policy_revision())
            || !workspace.has_map_edits_capture() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "map_edits capture differs"));
        }
        let guard = self.workspace_native_read()?;
        workspace.require_scope(&guard)?;
        let child = self.workspace_semantic_inputs(Q::MapEdits)?;
        let inputs = child.policy();
        child.semantic_source_evidence().check(inputs.mapping())?;
        let subject = child.original_analysis_subject()
            .ok_or_else(|| io::Error::other("map_edits actual Original subject absent"))?;
        workspace.require_analysis_subject(subject)?;
        subject.require_bound_mapping(inputs.mapping())?;
        if subject.synthetic() {
            return Err(io::Error::new(io::ErrorKind::Unsupported, "map_edits requires authored Original source"));
        }
        let profile = tree.checker_builtin_profile()
            .ok_or_else(|| io::Error::other("map_edits pinned checker profile absent"))?;
        let builtin = tree.validated_checker_profile(profile).map_err(|error| io::Error::other(format!("map_edits checker profile: {error:?}")))?;
        let queries = self.native_raw_queries.as_ref().ok_or_else(|| io::Error::other("map_edits QueryDb absent"))?;
        let operational = |failure| match failure {
            Failure::Operational(error) => error,
            Failure::Unsupported(message) => io::Error::new(io::ErrorKind::Unsupported, message),
        };
        queries.with_workspace_code_pages(workspace, &guard, |reader| {
            let budget = reader.budget();
            let checkpoint = || {
                budget.require().map_err(|message| io::Error::new(io::ErrorKind::OutOfMemory, message))?;
                crate::daemon::control::checkpoint()?;
                workspace.require_scope(&guard)
            };
            let mut control = Operation { budget, poll: &checkpoint };
            let (_, bytes) = reader.configuration();
            charge(budget, bytes.map_or(Some(1024), |data| data.len().checked_mul(64).and_then(|n| n.checked_add(1024))))?;
            let config = Config::capture(bytes.map_or(Configuration::ProvenMissing, Configuration::Captured))?;
            let mut names = CodeNames::default();
            let witness = reader.for_each_code_file_completed(inputs, &mut |relative, views| {
                names.add_file_using(relative, views.raw()?.lines(), &mut control)?;
                Ok(true)
            })?.into_witness()?.ok_or("map_edits actual CODE_DM index did not complete")?;
            let names = names.finish_using(&mut control)?;
            let mut sites = Vec::new();
            workspace.for_each_map_edit_file(&guard, |relative, rows| {
                names.append_map_using(relative, rows, |owner, field| {
                    map_edits_policy::native_declaration(tree, &builtin, profile, owner, field).map_err(Failure::Unsupported)
                }, &mut sites, &mut control).map_err(operational)
            })?;
            if !witness.matches(workspace, &guard, inputs)? {
                return Err("map_edits CODE completion belongs to another capture".into());
            }
            consume(&sites, &config, budget, &checkpoint).map_err(Failure::Operational)
        }).map_err(operational)
    }
}

impl SourceSnapshot{
 fn write_native_workspace_decl_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints.len()!=1||lints[0]!="decl"||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed decl report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
 let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual decl workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("decl report capture differs"))}self.require_original_analyze_subject(capture)?;
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
 self.with_original_decl_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Sites{..}){return Err(io::Error::other("decl actual baseline policy changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"decl",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
 pub(crate) fn write_native_workspace_raw_tree_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{let policy=lints.first().and_then(|name|dq_analyze::captured_raw_tree_pages::Policy::from_name(name)).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"exact implemented raw tree policy required"))?;if lints.len()!=1||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::ErrorKind::InvalidInput.into())}let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("raw tree actual workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("raw tree report actual configuration/frame differs"))}let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_native_raw_tree(tree,policy,|data,config,budget|{let empty=LintScope::default();let scope=config.borrowed_report_scope(policy.name(),policy.metadata().group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,policy.name(),&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})}).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})}
}

impl SourceSnapshot{pub(crate) fn write_native_workspace_policy_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{let policy=lints.first().and_then(|name|dq_analyze::workspace_fold_policy::Policy::from_name(name)).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"exact implemented complete policy required"))?;if lints.len()!=1||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::ErrorKind::InvalidInput.into())}let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("complete policy actual workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("complete policy actual frame/configuration differs"))}if policy.tracked().is_some(){self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;self.require_original_analyze_subject(capture)?;}if policy==dq_analyze::workspace_fold_policy::Policy::AllowAnnotations{
 self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
 if !capture.matches_auxiliary_questions(&[])||!crate::policy_request::exact_code_maps_roots(root,capture.recursive_roots()){
  return Err(io::Error::new(io::ErrorKind::InvalidInput,"allow_annotations actual capture must cover exactly code and maps with no other purpose"));
 }
}let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_native_workspace_fold_report(tree,policy,|data,config,budget|{let meta=policy.metadata();let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(&data,policy.name(),&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})}).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})}}
impl SourceSnapshot{
 fn write_native_workspace_init_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints.len()!=1||lints[0]!="init"||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed init report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
 let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual init workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("init report capture differs"))}self.require_original_analyze_subject(capture)?;
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
 self.with_original_init_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Sites{..}){return Err(io::Error::other("init actual baseline policy changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"init",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}
impl SourceSnapshot{
 fn write_native_workspace_base_vars_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints.len()!=1||lints[0]!="base_vars"||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed base_vars report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
 let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual base_vars workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("base_vars report capture differs"))}self.require_original_analyze_subject(capture)?;
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
 self.with_original_base_vars_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Sites{..}){return Err(io::Error::other("base_vars actual baseline policy changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"base_vars",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 fn write_native_workspace_requirement_bool_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints.len()!=1||lints[0]!="requirement_bool"||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed requirement_bool report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
 let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual requirement_bool workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("requirement_bool report capture differs"))}self.require_original_analyze_subject(capture)?;
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
 self.with_original_requirement_bool_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Sites{..}){return Err(io::Error::other("requirement_bool actual baseline policy changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"requirement_bool",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_player_link_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_player_link_pages::PlayerData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::PlayerLink;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original player-link workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"player-link full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original player-link QueryDb unavailable"))?;queries.with_original_workspace_player_link_guard(workspace,&guard,capture,subject,consume)
 }
 fn write_native_workspace_player_link_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["player_link"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed player-link report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual player-link workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("player-link report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_player_link_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("player-link actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"player_link",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_untyped_member_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_untyped_member_pages::MemberData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::UntypedMember;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original untyped-member workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"untyped-member full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original untyped-member QueryDb unavailable"))?;queries.with_original_workspace_untyped_member_guard(workspace,&guard,capture,subject,consume)
 }
 fn write_native_workspace_untyped_member_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["untyped_member"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed untyped-member report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual untyped-member workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("untyped-member report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_untyped_member_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("untyped-member actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"untyped_member",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_silicon_entry_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_silicon_entry::Data,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
  self.with_original_silicon_entry_policy_using(crate::runner_host::workspace_capture::SiliconActorDomain::CodeOnly,consume)
 }
 pub(super) fn with_original_silicon_entry_policy_using<T>(&self,domain:crate::runner_host::workspace_capture::SiliconActorDomain<'_>,consume:impl FnOnce(&dq_analyze::captured_silicon_entry::Data,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::SiliconEntry;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original silicon_entry workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"silicon_entry full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original silicon_entry QueryDb unavailable"))?;queries.with_original_workspace_silicon_entry_guard_using(workspace,&guard,capture,subject,domain,None,consume)
 }
 fn write_native_workspace_silicon_entry_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["silicon_entry"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed silicon_entry report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual silicon_entry workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("silicon_entry report actual frame differs"))}
 self.require_original_fixed_report_subject(tree)?;
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_silicon_entry_policy(|data,config,budget|{let meta=&dq_analyze::silicon_entry_policy::META;if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("silicon_entry actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"silicon_entry",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_weak_raw_read_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_weak_raw_read_pages::WeakData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::WeakRawRead;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original weak-raw-read workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"weak-raw-read full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original weak-raw-read QueryDb unavailable"))?;queries.with_original_workspace_weak_raw_read_guard(workspace,&guard,capture,subject,consume)
 }
 fn write_native_workspace_weak_raw_read_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["weak_raw_read"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed weak-raw-read report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual weak-raw-read workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("weak-raw-read report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_weak_raw_read_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("weak-raw-read actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"weak_raw_read",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_rel_write_undeclared_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_rel_write_pages::RelationData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::RelWriteUndeclared;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original rel-write workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"rel-write full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original rel-write QueryDb unavailable"))?;queries.with_original_workspace_rel_write_undeclared_guard(workspace,&guard,capture,subject,consume)
 }
 fn write_native_workspace_rel_write_undeclared_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["rel_write_undeclared"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed rel-write report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual rel-write workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("rel-write report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_rel_write_undeclared_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("rel-write actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"rel_write_undeclared",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_untyped_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_untyped_pages::UntypedData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::Untyped;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original untyped workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"untyped full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original untyped QueryDb unavailable"))?;queries.with_original_workspace_untyped_guard(workspace,&guard,capture,subject,consume)
 }
 fn write_native_workspace_untyped_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["untyped"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed untyped report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual untyped workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("untyped report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_untyped_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard)||!meta.allow.is_empty()||!data.allow_used().is_empty(){return Err(io::Error::other("untyped actual Hard/no-ALLOW contract differs"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"untyped",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_stored_refs_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_stored_refs_pages::StoredData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let question=crate::policy_request::WorkspaceAuxiliaryQuestion::StoredRefs;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original stored_refs workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"stored_refs full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original stored_refs QueryDb unavailable"))?;queries.with_original_workspace_stored_refs_guard(workspace,&guard,capture,subject,consume)
 }
 fn write_native_workspace_stored_refs_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 if lints!=["stored_refs"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed stored_refs report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual stored_refs workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("stored_refs report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_stored_refs_policy(|data,config,budget|{let meta=data.metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("stored_refs actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"stored_refs",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl super::RawWorkspaceSnapshot{
 pub(crate) fn write_report_page(&self,request:&crate::daemon::query::QueryRequest,output:&mut impl Write)->io::Result<()>{
  self.require_request(request)?;if self.source.purpose().layering_no_model(){return self.write_engine_unselected_page(request,output)}let crate::daemon::query::SourceQuery::NativeWorkspaceRawTreeReportPage{root,configuration,lints,cursor,limit}=&request.source_queries[0]else{return Err(io::ErrorKind::InvalidInput.into())};let policy=dq_analyze::captured_raw_tree_pages::Policy::from_name(self.source.purpose().name()).ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual raw producer is not registered"))?;
  let frame=ReportFrame{root,configuration,recursive_roots:self.capture.recursive_roots(),semantic:self.revision(),source:self.source_revision(),policy:self.policy_revision(),configuration_present:self.capture.configuration().1.is_some(),grep_purpose:None};
  self.with_native_raw_tree(policy,|data,config,budget|{let empty=LintScope::default();let scope=config.borrowed_report_scope(policy.name(),policy.metadata().group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,policy.name(),&frame,exact,budget,lints,cursor.as_ref(),*limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})}).map_err(|error|match error{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_engine_layering_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_engine_layering_pages::LayeringData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 self.with_original_layering_policy(crate::policy_request::WorkspaceAuxiliaryQuestion::EngineLayering,consume)
 }
 fn with_original_layering_policy<T>(&self,question:crate::policy_request::WorkspaceAuxiliaryQuestion,consume:impl FnOnce(&dq_analyze::captured_engine_layering_pages::LayeringData,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
 let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("original engine-layering workspace unavailable"))?;let subject=self.analysis_subject.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"engine-layering full Original Analyze subject unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("original engine-layering QueryDb unavailable"))?;queries.with_original_workspace_layering_guard_limit(question,workspace,&guard,capture,subject,None,consume)
 }
 fn write_native_workspace_layering_report_page(&self,question:crate::policy_request::WorkspaceAuxiliaryQuestion,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
 let layer=question.layering().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual layering role required"))?;
 if lints!=[layer.name()]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact completed engine-layering report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalChecker0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("actual engine-layering workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("engine-layering report actual frame differs"))}
 let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_layering_policy(question,|data,config,budget|{let meta=data.metadata();if !std::ptr::eq(meta,layer.metadata()){return Err(io::Error::other("layering report differs from the actual admitted policy"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,layer.name(),&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}

impl ReportData for dq_analyze::captured_engine_layering_pages::LayeringData {
 fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}
 fn text_at(&self,index:usize)->io::Result<Option<&str>>{
  self.source_text().map(|lines|lines.get(index).map(String::as_str).ok_or_else(||io::Error::other("library layering fingerprint absent"))).transpose()
 }
 fn require_text_shape(&self)->io::Result<()>{
  raw_tree_text_shape(self.message_only(),self.sites(),self.source_text().unwrap_or(&[]))
 }
 fn message_only(&self)->bool{matches!(self.metadata().policy,dq_analyze::lint::Policy::Hard)}
 fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{self.allow_used()}
 fn allow_source_digest(&self,_:&str)->Option<&[u8;20]>{None}
}

impl super::RawWorkspaceSnapshot{
 fn write_engine_unselected_page(&self,request:&crate::daemon::query::QueryRequest,output:&mut impl Write)->io::Result<()>{
  self.require_request(request)?;let crate::daemon::query::SourceQuery::NativeWorkspaceSemanticReportPage{root,configuration,lints,cursor,limit}=&request.source_queries[0]else{return Err(io::ErrorKind::InvalidInput.into())};let guard=super::workspace_native_guard::NativeReadGuard::raw_owned(&self.capture,&self.source,&self.queries)?;let proof=self.capture.engine_no_model()?;let layer=proof.preflight().question().layering().ok_or_else(||io::Error::other("unissued layering empty selection"))?;let frame=ReportFrame{root,configuration,recursive_roots:self.capture.recursive_roots(),semantic:self.revision(),source:self.source_revision(),policy:self.policy_revision(),configuration_present:self.capture.configuration().1.is_some(),grep_purpose:None};self.queries.with_engine_unselected(&self.capture,&guard,|data,config,budget|{if !std::ptr::eq(data.metadata(),layer.metadata()){return Err(io::Error::other("empty layering proof differs from its role"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(layer.name(),"").unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,layer.name(),&frame,exact,budget,lints,cursor.as_ref(),*limit,output,&mut||{crate::daemon::control::checkpoint()?;self.capture.engine_no_model()?;Ok(())})}).map_err(|f|match f{dq_analyze::captured_reactive_reads::Failure::Operational(e)=>e,dq_analyze::captured_reactive_reads::Failure::Unsupported(m)=>io::Error::new(io::ErrorKind::Unsupported,m)})
 }
}

#[cfg(test)]mod raw_tree_hard_shape_tests{
 use super::*;
 fn site(message:&str)->dq_analyze::lint::Site{dq_analyze::lint::Site{rule:"unknown_var".into(),rel:"code/probe.dm".into(),line:1,msg:message.into(),key:String::new(),ident:String::new()}}
 #[test]fn actual_raw_hard_shape_requires_empty_source_text_and_nonempty_message_without_relaxing_text_policy_cardinality(){let sites=[site("actual ownership refusal")];assert!(raw_tree_text_shape(true,&sites,&[]).is_ok());assert!(raw_tree_text_shape(true,&sites,&["forged unobserved source".into()]).is_err());assert!(raw_tree_text_shape(true,&[site("")],&[]).is_err());assert!(raw_tree_text_shape(false,&sites,&[]).is_err());assert!(raw_tree_text_shape(false,&sites,&["actual observed source".into()]).is_ok());assert!(raw_tree_text_shape(false,&[],&["extra source".into()]).is_err());}
 struct Hard{sites:Vec<dq_analyze::lint::Site>}
 impl ReportData for Hard{fn sites(&self)->&[dq_analyze::lint::Site]{&self.sites}fn text_at(&self,_:usize)->io::Result<Option<&str>>{panic!("a genuine message-only finding never asks for source text")}fn require_text_shape(&self)->io::Result<()>{raw_tree_text_shape(true,&self.sites,&[])}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{&[]}fn allow_source_digest(&self,_:&str)->Option<&[u8;20]>{None}}
 #[test]fn ownership_is_exact_closed_raw_hard_emitter_and_cannot_grant_ui_message_findings(){let data=Hard{sites:vec![site("exact ownership message")]};let row=serde_json::to_value(Items{data:&data,name:"ownership",start:0,end:1}).unwrap();assert_eq!(row[0]["kind"],"hard_site");assert_eq!(row[0]["site"]["msg"],"exact ownership message");assert!(row[0].get("source_text").is_none());assert!(serde_json::to_value(Items{data:&data,name:"ui_actions",start:0,end:1}).is_err());assert!(serde_json::to_value(Items{data:&data,name:"ownership_unissued",start:0,end:1}).is_err());}
}

impl SourceSnapshot{
 pub(crate) fn with_original_sys_reactive_policy_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_sys_reactive::Data,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{
  let capture=self.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive)?;
  let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("Sys reactive actual workspace absent"))?;
  self.require_original_analyze_subject(workspace)?;
  let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("Sys reactive actual QueryDb absent"))?;
  queries.with_original_workspace_sys_reactive_guard_report(workspace,&guard,capture,consume)
 }
 fn write_native_workspace_sys_reactive_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  if lints!=["sys/dx_reactive"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact complete Sys reactive report required"))}
  self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;
  let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("Sys reactive actual workspace absent"))?;
  if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("Sys reactive actual report frame differs"))}
  let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};
  self.with_original_sys_reactive_policy_report(|data,config,budget|{let meta=dq_analyze::sys_reactive_policy::metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("Sys reactive actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"sys/dx_reactive",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;crate::daemon::control::checkpoint()})})
 }
}

impl ReportData for dq_analyze::captured_lifeforms::Data{fn sites(&self)->&[dq_analyze::lint::Site]{self.sites()}fn text_at(&self,_:usize)->io::Result<Option<&str>>{Ok(None)}fn require_text_shape(&self)->io::Result<()>{if self.sites().iter().all(|site|!site.msg.is_empty()){Ok(())}else{Err(io::Error::other("Lifeforms Hard message absent"))}}fn message_only(&self)->bool{true}fn allow_used(&self)->&[dq_analyze::lint::AllowUse]{&[]}fn allow_source_digest(&self,_:&str)->Option<&[u8;20]>{None}}
impl SourceSnapshot{
 pub(crate) fn with_original_lifeforms_policy_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_lifeforms::Data,&dq_analyze::captured_raw_file::Config,&std::sync::Arc<Budget>)->io::Result<T>)->io::Result<T>{let capture=self.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::Lifeforms)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||io::Error::other("Lifeforms actual workspace absent"))?;self.require_original_analyze_subject(workspace)?;let queries=self.native_raw_queries.as_ref().ok_or_else(||io::Error::other("Lifeforms actual QueryDb absent"))?;queries.with_original_workspace_lifeforms_guard_report(workspace,&guard,capture,consume)}
 fn write_native_workspace_lifeforms_report_page(&self,root:&Path,configuration:&Path,lints:&[String],cursor:Option<&crate::query_db::WorkspaceCursor>,limit:usize,tree:&dm_tree::SemanticTree,output:&mut impl Write)->io::Result<()>{
  if lints!=["lifeforms"]||!(1..=128).contains(&limit)||!self.matches_tree(tree){return Err(io::Error::new(io::ErrorKind::InvalidInput,"exact complete Lifeforms report required"))}self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290))?;let capture=self.native_workspace.as_ref().ok_or_else(||io::Error::other("Lifeforms actual workspace absent"))?;if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(io::Error::other("Lifeforms report frame differs"))}let frame=ReportFrame{root,configuration,recursive_roots:capture.recursive_roots(),semantic:tree.identity(),source:self.source_revision,policy:capture.policy_revision(),configuration_present:capture.configuration().1.is_some(),grep_purpose:None};self.with_original_lifeforms_policy_report(|data,config,budget|{let meta=dq_analyze::lifeforms_policy::metadata();if !matches!(meta.policy,dq_analyze::lint::Policy::Hard){return Err(io::Error::other("Lifeforms actual Hard contract changed"))}let empty=LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let exact=scope_json(scope,budget)?;let exact=std::str::from_utf8(&exact.0).map_err(io::Error::other)?;write_data_page(data,"lifeforms",&frame,exact,budget,lints,cursor,limit,output,&mut||{budget.require().map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;crate::daemon::control::checkpoint()})})
 }
}
