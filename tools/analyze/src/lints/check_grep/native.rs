//! Source-neutral complete check_grep fold. Only the host's exhausted recorded
//! file/fixed/glob/semantic issuer can authorize publication of these DATA rows.
//! No Tree/Sem, filesystem access, source-role receipt or cached operation owner.
use super::*;
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
use std::{io,sync::Arc};
// The same pre-existing native policy singleton serves both judgment and metadata.
fn policy()->&'static CheckGrep{static POLICY:std::sync::LazyLock<CheckGrep>=std::sync::LazyLock::new(CheckGrep::new);&POLICY}
/// Actual unique rule-derived lists, not a second registry/parts projection.
pub fn metadata()->&'static crate::lint::Meta{policy().meta}
/// The exact unique Meta selector, shared with the legacy registration.
pub fn source_roots()->&'static[(&'static str,&'static str)]{SOURCE_ROOTS}
pub fn selects_source(relative:&str)->bool{crate::tree::Select{roots:SOURCE_ROOTS,hidden:true}.matches_path(relative)}
pub fn is_root_dme(name:&str)->bool{name.ends_with(".dme")&&!name.starts_with('.')&&!name.contains('/')&&!name.contains(char::from(92u8))}
pub fn is_jsx_name(relative:&str)->bool{relative.starts_with("tgui/")&&relative.ends_with(".jsx")&&!relative.split('/').any(|part|part.starts_with('.'))}
/// Exact selector over a traversal-issued relative filesystem path. Borrowed
/// components avoid allocating a report spelling before discovery admission.
pub fn selects_filesystem_source(relative:&std::path::Path)->bool{
 let Some(name)=relative.file_name()else{return false};let bytes=name.as_encoded_bytes();if !bytes.contains(&b'.'){return false}let extension=bytes.rsplit(|byte|*byte==b'.').next().unwrap_or(&[]);
 SOURCE_ROOTS.iter().any(|(directory,wanted)|extension==wanted.as_bytes()&&(directory.is_empty()||relative.strip_prefix(directory).is_ok_and(|tail|tail.components().next().is_some())))
}
pub fn is_jsx_path(relative:&std::path::Path)->bool{relative.starts_with("tgui")&&relative.file_name().is_some_and(|name|name.as_encoded_bytes().ends_with(b".jsx"))&&!relative.components().any(|part|part.as_os_str().as_encoded_bytes().first()==Some(&b'.'))}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Fixed{GitIgnore,Dependencies,Changelog,Configuration,Seeds,Bindings}
impl Fixed{
 pub fn all()->&'static[Self]{&[Self::GitIgnore,Self::Dependencies,Self::Changelog,Self::Configuration,Self::Seeds,Self::Bindings]}
 pub fn for_purpose(purpose:Purpose)->&'static[Self]{match purpose{Purpose::Check=>Self::all(),Purpose::Baseline=>&[Self::GitIgnore,Self::Changelog,Self::Configuration,Self::Seeds,Self::Bindings]}}
 pub fn relative(self)->&'static str{match self{Self::GitIgnore=>".gitignore",Self::Dependencies=>"dependencies.sh",Self::Changelog=>"html/changelogs/example.yml",Self::Configuration=>"config/example/config.txt",Self::Seeds=>"code/__defines/verdigris/_bindings_types.dm",Self::Bindings=>"code/__defines/verdigris/_bindings.dm"}}
 pub fn index(self)->usize{match self{Self::GitIgnore=>0,Self::Dependencies=>1,Self::Changelog=>2,Self::Configuration=>3,Self::Seeds=>4,Self::Bindings=>5}}
}

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Semantic{SlotMutation,NonClientHolder}
/// Requested lexical candidates only, never a procedure/file semantic model.
pub struct SemanticRequest{pub relative:String,pub slot_mutation:bool,pub non_client_holder:bool}
/// Required observations. There are deliberately no empty/default providers.
/// These callbacks produce DATA; they never grant complete/current authority.
pub trait Inputs{
 fn scope(&self)->&LintScope;
 fn budget(&self)->&Arc<Budget>;
 fn checkpoint(&self)->io::Result<()>;
 fn files(&self,include_exempt:bool,visit:&mut dyn FnMut(&SourceFile)->Result<(),Failure>)->Result<(),Failure>;
 fn fixed(&self,which:Fixed,visit:&mut dyn FnMut(Option<&[u8]>)->Result<(),Failure>)->Result<(),Failure>;
 fn dmes(&self,visit:&mut dyn FnMut(&str,&[u8])->Result<(),Failure>)->Result<(),Failure>;
 fn jsx(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<(),Failure>;
 fn prepare_positions(&self,requests:&[SemanticRequest])->Result<(),Failure>;
 fn positions(&self,file:&SourceFile,which:Semantic,visit:&mut dyn FnMut(&std::collections::BTreeSet<(usize,usize)>)->Result<(),Failure>)->Result<(),Failure>;
}
pub struct Output{pub run:Run,pub allow_used:Vec<crate::lint::AllowUse>,pub report:String,pub failed:bool,pub macro_ceiling:i64,source_lines:Vec<Line>,allow_digests:std::collections::BTreeMap<String,[u8;20]>}
/// Baseline scan facts contain no finish result or fabricated macro observation.
pub struct BaselineData{pub run:Run,pub allow_used:Vec<crate::lint::AllowUse>,source_lines:Vec<Line>,allow_digests:std::collections::BTreeMap<String,[u8;20]>}
impl BaselineData{
 pub fn source_line(&self,relative:&str,line:u32)->Option<&str>{self.source_lines.binary_search_by(|row|(row.relative.as_str(),row.line).cmp(&(relative,line))).ok().map(|index|self.source_lines[index].text.as_str())}
 pub fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_digests.get(relative)}
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Purpose{Check,Baseline}

struct Line{relative:String,line:u32,text:String}
impl Output{
 pub fn source_line(&self,relative:&str,line:u32)->Option<&str>{self.source_lines.binary_search_by(|row|(row.relative.as_str(),row.line).cmp(&(relative,line))).ok().map(|index|self.source_lines[index].text.as_str())}
 pub fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_digests.get(relative)}
}
/// Same unique original custom finish over completed as-of delivery. No source I/O.
pub fn finish_report_after_delivery(scope:&LintScope,macro_ceiling:i64,run:&Run,source:&impl crate::baseline::SiteText,text:&mut String)->bool{policy().finish_data(scope,macro_ceiling,run,text,&mut|rel,line|source.site_text(rel,line))}
/// Only the original baseline/config publisher, after completed delivery.
pub fn update_baseline_after_delivery(root:&Path,scope:&LintScope,run:&Run,mode:Mode)->io::Result<String>{policy().update_baseline_data(root,scope,run,mode)}

fn oom(b:&Budget,message:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn reserve(b:&Budget,bytes:Option<usize>)->Result<(),Failure>{b.charge(bytes.ok_or_else(||oom(b,"check_grep output capacity overflow"))?).map_err(|m|oom(b,m))}
fn own(b:&Budget,text:&str)->Result<String,Failure>{reserve(b,text.len().checked_mul(4).and_then(|n|n.checked_add(64)))?;Ok(text.to_owned())}
fn checked(source:&dyn Inputs)->Result<(),Failure>{source.budget().require().map_err(|m|oom(source.budget(),m))?;source.checkpoint()?;source.budget().require().map_err(|m|oom(source.budget(),m))}
fn sink(source:&dyn Inputs)->Result<Sink,Failure>{Sink::bounded_budget(source.budget()).map_err(|m|oom(source.budget(),m))}
fn pending_sink(source:&dyn Inputs,out:&Sink)->Result<(),Failure>{if let Some(message)=out.admission_error(){return Err(oom(source.budget(),message))}checked(source)}
fn remember(source:&dyn Inputs,file:&SourceFile,sites:&[Site],lines:&mut Vec<Line>)->Result<(),Failure>{
 for site in sites{checked(source)?;if !site.msg.is_empty(){continue}if !source.budget().row(lines){return Err(oom(source.budget(),"check_grep report-line vector refused"))}let raw=file.raw();let line=site.line as usize;let original=if line>=1&&line<=raw.num_lines(){raw.line(line)}else{""};reserve(source.budget(),original.len().checked_mul(8).and_then(|n|n.checked_add(128)))?;lines.push(Line{relative:own(source.budget(),&site.rel)?,line:site.line,text:crate::util::normalize_ws(original)});}
 Ok(())
}
fn remember_allow(source:&dyn Inputs,file:&SourceFile,used:&[crate::lint::AllowUse],digests:&mut std::collections::BTreeMap<String,[u8;20]>)->Result<(),Failure>{
 if used.is_empty(){return Ok(())}for row in used{if row.rel!=file.rel{return Err("check_grep ALLOW label differs from actual original file".into())}}
 if !digests.contains_key(file.rel.as_str()){reserve(source.budget(),Some(2048+std::mem::size_of::<(String,[u8;20])>()))?;let digest=crate::captured_raw_file::source_allow_digest(file);digests.insert(own(source.budget(),&file.rel)?,digest);}checked(source)
}
fn append(source:&dyn Inputs,mut from:Sink,to:&mut Sink,allow_start:usize)->Result<(),Failure>{
 pending_sink(source,&from)?;for site in from.sites.drain(..){if !source.budget().row(&mut to.sites){return Err(oom(source.budget(),"check_grep joined finding vector refused"))}to.sites.push(site)}for row in from.allow_used.drain(..){if to.allow_used[allow_start..].contains(&row){continue}if !source.budget().row(&mut to.allow_used){return Err(oom(source.budget(),"check_grep joined ALLOW vector refused"))}to.allow_used.push(row)}for note in from.notes.drain(..){if !source.budget().row(&mut to.notes){return Err(oom(source.budget(),"check_grep joined note vector refused"))}to.notes.push(note)}std::mem::drop(from);Ok(())
}
fn with_tree_text<T>(source:&dyn Inputs,bytes:&[u8],action:impl FnOnce(&str)->Result<T,Failure>)->Result<T,Failure>{
 let mut temporary=Temps{budget:Budget::scoped_temporaries(source.budget()).map_err(|message|oom(source.budget(),message))?,complete:false};let max=bytes.len().checked_mul(8).and_then(|n|n.checked_add(512)).ok_or_else(||oom(&temporary.budget,"check_grep original text normalization overflow"))?;reserve(&temporary.budget,max.checked_mul(2))?;
 let decoded=String::from_utf8_lossy(bytes).into_owned();if decoded.capacity()>max{return Err(oom(&temporary.budget,"check_grep lossy original text capacity exceeds admitted backing"))}let normalized=crate::util::universal_newlines(decoded);if normalized.capacity()>max{return Err(oom(&temporary.budget,"check_grep normalized original text capacity exceeds admitted backing"))}
 let pending=action(&normalized);std::mem::drop(normalized);if matches!(&pending,Err(Failure::Operational(_))){return pending}checked(source)?;let value=pending?;temporary.complete=true;std::mem::drop(temporary);Ok(value)
}
fn fixed_text<T>(source:&dyn Inputs,which:Fixed,visit:impl FnOnce(Option<&str>)->Result<T,Failure>)->Result<T,Failure>{
 let mut visit=Some(visit);let mut result=None;source.fixed(which,&mut|bytes|{let action=visit.take().ok_or("check_grep fixed observation repeated")?;result=Some(if matches!(which,Fixed::Seeds|Fixed::Bindings){match bytes{Some(bytes)=>with_tree_text(source,bytes,|text|action(Some(text)))?,None=>action(None)?}}else{action(bytes.and_then(|bytes|std::str::from_utf8(bytes).ok()))?});Ok(())})?;checked(source)?;result.ok_or_else(||Failure::from("check_grep fixed observation omitted"))
}
fn remember_dme(source:&dyn Inputs,relative:&str,bytes:&[u8],sites:&[Site],lines:&mut Vec<Line>)->Result<(),Failure>{
 if !sites.iter().any(|site|site.msg.is_empty()){return Ok(())}
 with_tree_text(source,bytes,|text|{let mut raw=text.split('\n');let mut number=0usize;let mut original="";for site in sites{if !site.msg.is_empty(){continue}let target=site.line as usize;if target<number{return Err("check_grep actual manifest sites changed line order".into())}while number<target{original=raw.next().unwrap_or("");number+=1;}checked(source)?;if !source.budget().row(lines){return Err(oom(source.budget(),"check_grep manifest report-line vector refused"))}reserve(source.budget(),original.len().checked_mul(8).and_then(|n|n.checked_add(128)))?;lines.push(Line{relative:own(source.budget(),relative)?,line:site.line,text:crate::util::normalize_ws(original)});}Ok(())})
}
struct Temps{budget:Arc<Budget>,complete:bool}impl Drop for Temps{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
struct Count{bytes:usize,denied:bool}impl std::fmt::Write for Count{fn write_str(&mut self,text:&str)->std::fmt::Result{let Some(next)=self.bytes.checked_add(text.len())else{self.denied=true;return Err(std::fmt::Error)};self.bytes=next;Ok(())}}
struct FixedWriter<'a>{text:&'a mut String,limit:usize,denied:bool}impl std::fmt::Write for FixedWriter<'_>{fn write_str(&mut self,text:&str)->std::fmt::Result{if self.text.len().checked_add(text.len()).is_none_or(|n|n>self.limit||n>self.text.capacity()){self.denied=true;return Err(std::fmt::Error)}self.text.push_str(text);Ok(())}}
/// Complete original policy, called only with actual operation-local loans.
pub fn judge(source:&dyn Inputs)->Result<Output,Failure>{
 let pending=judge_using(source);if matches!(&pending,Err(Failure::Operational(_))){return pending}checked(source)?;pending
}
fn scan_using(source:&dyn Inputs)->Result<BaselineData,Failure>{
 checked(source)?;let policy=policy();let mut output=sink(source)?;let mut lines=Vec::new();let mut allow_digests=std::collections::BTreeMap::new();let mut requests=Vec::new();
 let ignored=fixed_text(source,Fixed::GitIgnore,|text|{let mut rows=std::collections::BTreeSet::new();for row in ignored_outputs(text.unwrap_or("")){reserve(source.budget(),row.len().checked_mul(4).and_then(|n|n.checked_add(2048)))?;rows.insert(own(source.budget(),row)?);}Ok(rows)})?;
 source.files(false,&mut|file|{checked(source)?;if Files::Code.matches(file){let slot_mutation=file.text().contains("slot_flags");let non_client_holder=file.text().contains(".holder");if slot_mutation||non_client_holder{if !source.budget().row(&mut requests){return Err(oom(source.budget(),"check_grep semantic request vector refused"))}requests.push(SemanticRequest{relative:own(source.budget(),&file.rel)?,slot_mutation,non_client_holder});}}if ignored.contains(&file.rel){return Ok(())}let mut local=sink(source)?;local.set_current(&file.rel);for part in policy.compiled(){checked(source)?;part.scan_with(source.scope(),file,&mut local);pending_sink(source,&local)?;}remember(source,file,&local.sites,&mut lines)?;remember_allow(source,file,&local.allow_used,&mut allow_digests)?;let allow_start=output.allow_used.len();append(source,local,&mut output,allow_start)})?;
 // No raw-file loan remains live while the actual host prepares requested
 // original-body position facts. This permits one global callable walk and
 // file-grouped loans, instead of nested loans or files-times-bodies searches.
 requests.sort_unstable_by(|a,b|a.relative.cmp(&b.relative));if requests.windows(2).any(|pair|pair[0].relative==pair[1].relative){return Err("check_grep semantic request file repeats".into())}source.prepare_positions(&requests)?;checked(source)?;std::mem::drop(requests);
 let tree_allow_start=output.allow_used.len();
 let slot=policy.compiled().iter().find(|c|c.rule=="legacy_equip_restriction_vars__slot_flags").ok_or("check_grep slot rule missing")?;let slot_pattern=regex::Regex::new(r"slot_flags\s*&[^=]").unwrap();
 source.files(false,&mut|file|{checked(source)?;if !Files::Code.matches(file)||!file.text().contains("slot_flags"){return Ok(())}let mut local=sink(source)?;local.set_current(&file.rel);let mut called=false;source.positions(file,Semantic::SlotMutation,&mut|positions|{if called{return Err("check_grep slot proof repeated".into())}called=true;let mut scratch=Temps{budget:Budget::scoped_temporaries(source.budget()).map_err(|message|oom(source.budget(),message))?,complete:false};reserve(&scratch.budget,file.raw_quiet().num_lines().checked_mul(4*std::mem::size_of::<usize>()).and_then(|n|n.checked_add(4096)))?;slot.scan_lines_with(source.scope(),file,&mut local,slot_flags_guard_lines(file.text(),&slot_pattern,positions));pending_sink(source,&local)?;scratch.complete=true;std::mem::drop(scratch);Ok(())})?;if !called{return Err("check_grep slot proof omitted".into())}remember(source,file,&local.sites,&mut lines)?;remember_allow(source,file,&local.allow_used,&mut allow_digests)?;append(source,local,&mut output,tree_allow_start)})?;
 let holder=policy.compiled().iter().find(|c|c.rule=="admin_rights_shrink_only_baseline_one_mechanism_admin_can__holder").ok_or("check_grep holder rule missing")?;let holder_pattern=regex::Regex::new(r"\.holder\b").unwrap();
 source.files(false,&mut|file|{checked(source)?;if !Files::Code.matches(file)||!file.text().contains(".holder"){return Ok(())}let mut local=sink(source)?;local.set_current(&file.rel);let mut called=false;source.positions(file,Semantic::NonClientHolder,&mut|positions|{if called{return Err("check_grep holder proof repeated".into())}called=true;let mut scratch=Temps{budget:Budget::scoped_temporaries(source.budget()).map_err(|message|oom(source.budget(),message))?,complete:false};let width=file.text().len().checked_mul(16).and_then(|n|n.checked_add(file.raw_quiet().num_lines().checked_mul(4*(std::mem::size_of::<String>()+std::mem::size_of::<usize>()+std::mem::size_of::<u32>()))?)).and_then(|n|n.checked_add(file.rel.len().checked_mul(128)?)).and_then(|n|n.checked_add(8192));reserve(&scratch.budget,width)?;let masked=mask_act_holder_fields(file.text(),positions);let hits=masked.split('\n').enumerate().filter_map(|(i,line)|holder_pattern.is_match(line).then_some(i+1)).collect();let filtered=SourceFile::from_text(&file.rel,&masked);holder.scan_lines_with(source.scope(),&filtered,&mut local,hits);pending_sink(source,&local)?;std::mem::drop(filtered);std::mem::drop(masked);scratch.complete=true;std::mem::drop(scratch);Ok(())})?;if !called{return Err("check_grep holder proof omitted".into())}remember(source,file,&local.sites,&mut lines)?;remember_allow(source,file,&local.allow_used,&mut allow_digests)?;append(source,local,&mut output,tree_allow_start)})?;
 let dynamic=fixed_text(source,Fixed::Seeds,|seeds|fixed_text(source,Fixed::Bindings,|bindings|Ok(dynamic_parts_from(seeds,bindings))))?;
 if !dynamic.is_empty(){source.files(true,&mut|file|{checked(source)?;let mut local=sink(source)?;local.set_current(&file.rel);for part in &dynamic{part.scan_with(source.scope(),file,&mut local);pending_sink(source,&local)?}remember(source,file,&local.sites,&mut lines)?;remember_allow(source,file,&local.allow_used,&mut allow_digests)?;append(source,local,&mut output,tree_allow_start)})?;}
 source.dmes(&mut|relative,bytes|{checked(source)?;let start=output.sites.len();scan_dme_bytes(relative,bytes,&mut output);pending_sink(source,&output)?;remember_dme(source,relative,bytes,&output.sites[start..],&mut lines)})?;
 let mut changelog=false;source.fixed(Fixed::Changelog,&mut|bytes|{if changelog{return Err("check_grep changelog observation repeated".into())}changelog=true;scan_changelog_bytes(bytes,&mut output);pending_sink(source,&output)})?;if !changelog{return Err("check_grep changelog observation omitted".into())}
 source.jsx(&mut|relative|{output.site_in_msg(RULE_JSX,relative,1,"JSX file");pending_sink(source,&output)})?;
 let mut config=false;source.fixed(Fixed::Configuration,&mut|bytes|{if config{return Err("check_grep configuration observation repeated".into())}config=true;scan_toast_bytes(bytes,&mut output);pending_sink(source,&output)})?;if !config{return Err("check_grep configuration observation omitted".into())}
 lines.sort_unstable_by(|a,b|(&a.relative,a.line).cmp(&(&b.relative,b.line)));lines.dedup_by(|a,b|a.relative==b.relative&&a.line==b.line);
 let run=Run{sites:std::mem::take(&mut output.sites),notes:std::mem::take(&mut output.notes)};let allow_used=std::mem::take(&mut output.allow_used);std::mem::drop(output);
 Ok(BaselineData{run,allow_used,source_lines:lines,allow_digests})
}

/// Baseline purpose executes the same complete scan without asking for Dependencies or running finish.
pub fn judge_baseline(source:&dyn Inputs)->Result<BaselineData,Failure>{let pending=scan_using(source);if matches!(&pending,Err(Failure::Operational(_))){return pending}checked(source)?;pending}
fn judge_using(source:&dyn Inputs)->Result<Output,Failure>{
 let BaselineData{run,allow_used,source_lines:lines,allow_digests}=scan_using(source)?;let policy=policy();
 let macros=fixed_text(source,Fixed::Dependencies,|text|Ok(macro_count_text(text.unwrap_or(""))))?;
 let lookup=|relative:&str,line:usize|lines.binary_search_by(|row|(row.relative.as_str(),row.line as usize).cmp(&(relative,line))).ok().map(|index|lines[index].text.clone()).unwrap_or_default();
 let mut report_scratch=Temps{budget:Budget::scoped_temporaries(source.budget()).map_err(|m|oom(source.budget(),m))?,complete:false};let widths=run.sites.iter().try_fold(0usize,|n,row|n.checked_add(row.rule.len())?.checked_add(row.rel.len())?.checked_add(row.msg.len())?.checked_add(row.key.len())?.checked_add(row.ident.len()));let line_width=lines.iter().try_fold(0usize,|n,row|n.checked_add(row.text.len()));let report_peak=widths.and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(line_width?.checked_mul(8)?)).and_then(|n|n.checked_add(run.sites.len().checked_mul(256)?)).and_then(|n|n.checked_add(policy.parts.len().checked_mul(2048)?));reserve(&report_scratch.budget,report_peak)?;
 let mut count=Count{bytes:0,denied:false};let failed=policy.finish_data(source.scope(),macros,&run,&mut count,&mut|r,l|lookup(r,l));if count.denied{return Err(oom(source.budget(),"check_grep report count overflow"))}reserve(source.budget(),count.bytes.checked_mul(4).and_then(|n|n.checked_add(128)))?;let mut report=String::new();report.try_reserve_exact(count.bytes).map_err(|e|oom(source.budget(),e.to_string()))?;if report.capacity()>count.bytes.saturating_mul(4).saturating_add(128){return Err(oom(source.budget(),"check_grep report exposed excess capacity"))}let mut writer=FixedWriter{text:&mut report,limit:count.bytes,denied:false};let repeated=policy.finish_data(source.scope(),macros,&run,&mut writer,&mut|r,l|lookup(r,l));if writer.denied||writer.text.len()!=count.bytes||failed!=repeated{return Err(oom(source.budget(),"check_grep report count/encoding differs"))}std::mem::drop(writer);report_scratch.complete=true;std::mem::drop(report_scratch);checked(source)?;Ok(Output{run,allow_used,report,failed,macro_ceiling:macros,source_lines:lines,allow_digests})
}

/// Loan the SAME local raw SourceFile to the unique policy. No reference is
/// returned; the outer actual workspace reader remains the source authority.
pub fn with_source_file(views:crate::captured_raw_file::RawPolicyViews<'_>,visit:&mut dyn FnMut(&SourceFile)->Result<(),Failure>)->Result<(),Failure>{visit(views.source_file()?) }
pub use crate::check_grep_native_semantics::Positions;
/// Actual archive/body values are required. The result remains unsealed DATA;
/// the host must bind the current snapshot and exhaust all selected inputs.
pub fn body_positions(archive:&dm_tree::frontend::BodyArchive,body:&dm_tree::frontend::ArchivedBody<'_>,root:&std::path::Path,file:&SourceFile,tracked_slot_owners:&std::collections::BTreeSet<String>,slots:bool,holders:bool,scratch:&Budget,output_budget:&Budget,poll:&dyn Fn()->io::Result<()>,out:&mut Positions)->Result<(),Failure>{crate::check_grep_native_semantics::positions_for_body(archive,body,root,file,tracked_slot_owners,slots,holders,scratch,output_budget,poll,out)}
/// Exact old Decls CODE_DM tracked-line question, including generated tracking
/// declarations and excluding hidden paths according to that original selector.
pub fn observe_tracked_slot_owners(relative:&str,views:crate::captured_raw_file::RawPolicyViews<'_>,budget:&Budget,poll:&dyn Fn()->io::Result<()>,owners:&mut std::collections::BTreeSet<String>)->Result<(),Failure>{
 if !crate::tree::CODE_DM.matches_path(relative){return Ok(())}
 let local=views.allocation_budget(budget);local.charge(4096).map_err(|message|oom(local,message))?;
 for line in views.marker()?.split('\n'){
  local.require().map_err(|message|oom(local,message))?;poll()?;
  crate::raw_reactive_metadata_policy::visit_line(line,|event|{if let crate::raw_reactive_metadata_policy::Event::Tracked{owner,name:"slot_flags"}=event{if !owners.contains(owner){reserve(budget,owner.len().checked_mul(4).and_then(|n|n.checked_add(2048)))?;owners.insert(owner.to_owned());}}Ok::<_,Failure>(())})?;
 }
 local.require().map_err(|message|oom(local,message))?;poll()?;local.require().map_err(|message|oom(local,message))
}

pub fn is_effective_body(archive:&dm_tree::frontend::BodyArchive,ordinal:usize,budget:&Budget)->Result<bool,Failure>{crate::check_grep_native_semantics::is_effective_body(archive,ordinal,budget)}

#[cfg(test)]mod final_control_tests{
 use super::*;use std::cell::Cell;
 struct Refusal{budget:Arc<Budget>,scope:LintScope,late:Cell<bool>,actual:bool}
 impl Inputs for Refusal{
 fn scope(&self)->&LintScope{&self.scope}fn budget(&self)->&Arc<Budget>{&self.budget}fn checkpoint(&self)->io::Result<()>{if self.late.get(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())}}
 fn fixed(&self,_:Fixed,_:&mut dyn FnMut(Option<&[u8]>)->Result<(),Failure>)->Result<(),Failure>{self.late.set(true);if self.actual{Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}else{Err(Failure::Unsupported("actual source provider stopped before its required observation".into()))}}
 fn files(&self,_:bool,_:&mut dyn FnMut(&SourceFile)->Result<(),Failure>)->Result<(),Failure>{panic!("refused fixed observation must prevent file traversal")}
 fn dmes(&self,_:&mut dyn FnMut(&str,&[u8])->Result<(),Failure>)->Result<(),Failure>{panic!("no DME after refusal")}fn jsx(&self,_:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<(),Failure>{panic!("no JSX after refusal")}fn prepare_positions(&self,_:&[SemanticRequest])->Result<(),Failure>{panic!("no body preparation after refusal")}fn positions(&self,_:&SourceFile,_:Semantic,_:&mut dyn FnMut(&std::collections::BTreeSet<(usize,usize)>)->Result<(),Failure>)->Result<(),Failure>{panic!("no semantic positions after refusal")}
 }
 #[test]fn semantic_provider_stop_runs_final_control_but_actual_first_io_survives_late_cancellation(){
 for actual in [false,true]{let source=Refusal{budget:Budget::new(4*1024*1024).unwrap(),scope:LintScope::default(),late:Cell::new(false),actual};let error=judge(&source).err().expect("provider refusal cannot produce an output");match error{Failure::Operational(error)if actual=>assert_eq!(error.raw_os_error(),Some(1450)),Failure::Operational(error)=>assert_eq!(error.kind(),io::ErrorKind::Interrupted),Failure::Unsupported(message)=>panic!("late current control must precede semantic refusal: {message}")}}
 }
}
