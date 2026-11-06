//! Actual directive traversal metadata in the EXISTING DirectivePlan.
//! Original output has no PreparedLine/environment snapshots; the raw driver
//! supplies its one source/token/parser product. This owner funds metadata
//! before allocation and moves its SAME root to final product/Mapping owners.
use super::{DirectivePlan,IncludeOccurrence,IncludeRegion,OrderedItem,MacroEffect,ExpansionSegment};
use crate::{SourceAcquisitionLease,InitialEnvironment,macro_expansion::{OriginalMacroRows as Rows, empty_exact as exact_rows}};
use super::original_output_trace::OriginalTraceProjectionKey;
use dm_syntax::{SettingAdmission,SettingRootLease,SharedSettingRetention,Span};
use std::{io,mem,path::{Path,PathBuf},sync::Arc,collections::BTreeMap};
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn add(left:usize,right:usize)->io::Result<usize>{left.checked_add(right).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
fn scaled(n:usize,scale:usize)->io::Result<usize>{n.checked_mul(scale).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
fn grow(root:&mut SettingRootLease,bytes:usize,a:&SettingAdmission<'_>)->io::Result<()>{a.grow(root,bytes).map_err(|e|a.take_operational_error().unwrap_or(e))}
// SAME pinned std B-tree conservative <=16-slot/node allowance reviewed by the
// existing environment wrapper. This is a reservation, NEVER a heap census row.
fn node<K,V>()->io::Result<usize>{add(scaled(mem::size_of::<(K,V)>(),16)?,256)}
fn path_bound(path:&Path)->io::Result<usize>{add(scaled(path.as_os_str().len(),4)?,mem::size_of::<PathBuf>()+4*mem::size_of::<usize>())}
fn owned_path(path:&Path)->io::Result<PathBuf>{let mut result=PathBuf::new();result.try_reserve_exact(path.as_os_str().len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;result.push(path);if result.capacity()>path.as_os_str().len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}Ok(result)}
/// Reconcile only the variable byte allowance after constructing this exact
/// retained PathBuf. Its inline/Arc and map-node grants stay separate.
fn opened_path_unused(path:&PathBuf)->io::Result<usize>{
 scaled(path.as_os_str().len(),4)?.checked_sub(path.capacity()).ok_or(io::ErrorKind::InvalidData.into())
}
fn owned_text(text:&str)->io::Result<String>{let mut out=String::new();out.try_reserve_exact(text.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if out.capacity()>text.len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}out.push_str(text);Ok(out)}
fn push<T>(rows:&mut Vec<T>,value:T,root:&mut SettingRootLease,a:&SettingAdmission<'_>)->io::Result<()>{
 poll(a)?;if rows.len()==rows.capacity(){let target=rows.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or(io::ErrorKind::OutOfMemory)?;let bound=scaled(target,4)?;let old=scaled(rows.capacity(),mem::size_of::<T>())?;let peak=scaled(bound,mem::size_of::<T>())?;grow(root,peak,a)?;rows.try_reserve_exact(target-rows.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if rows.capacity()>bound{return Err(io::ErrorKind::OutOfMemory.into())}let actual=scaled(rows.capacity(),mem::size_of::<T>())?;let release=add(old,peak-actual)?;a.shrink(root,release).map_err(|e|a.take_operational_error().unwrap_or(e))?;}rows.push(value);Ok(())
}
struct LastTraceProjection {
    key: OriginalTraceProjectionKey,
    rows: Arc<Vec<super::MacroExpansion>>,
}
pub(super) struct OriginalPlanOwner{
 plan:DirectivePlan,current_region:Option<usize>,failed:bool,
 empty_trace:Option<Arc<Vec<super::MacroExpansion>>>,
 empty_replacement_chain:Option<Arc<[Arc<str>]>>,
 last_trace:Option<LastTraceProjection>,
 credit:SettingRootLease,
}
impl OriginalPlanOwner{
 pub(super) fn new(project:&Path,initial:InitialEnvironment,defines:&BTreeMap<String,String>,revision:Option<u64>,a:&SettingAdmission<'_>)->io::Result<Self>{
  poll(a)?;if initial!=InitialEnvironment::OriginalChecker0290{return Err(io::ErrorKind::InvalidInput.into())}
  let mut credit=a.reserve(add(mem::size_of::<Self>(),path_bound(project.parent().unwrap_or_else(||Path::new("")))?)?).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let mut plan=DirectivePlan::default();plan.initial_environment=initial;plan.input_revision=revision;plan.source_acquisitions=super::SourceAcquisitions::original(a)?;plan.project_dir=owned_path(project.parent().unwrap_or_else(||Path::new("")))?;
  for(name,replacement)in defines{poll(a)?;let bytes=add(node::<String,String>()?,scaled(add(name.len(),replacement.len())?,4)?)?;grow(&mut credit,bytes,a)?;plan.defines.insert(owned_text(name)?,owned_text(replacement)?);}
  Ok(Self{plan,current_region:None,failed:false,empty_trace:None,empty_replacement_chain:None,last_trace:None,credit})
 }
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=if !a.matches_lease_domain(&self.credit){Err(io::ErrorKind::InvalidInput.into())}else{poll(a)};if result.is_err(){self.failed=true}result}
 #[cfg(debug_assertions)]
 pub(super) fn trace_reservations(&self) -> (usize, usize, usize) {
  (self.plan.occurrences.len(), self.plan.regions.len(), self.credit.bytes())
 }
 pub(super) fn plan(&self)->&DirectivePlan{&self.plan}
 /// Only the actual admitted read/recorded acquisition path supplies a lease.
 /// No normalization/preparation/reopen occurs; decoded line metadata is DATA
 /// over that SAME facade, while all Original token points stay raw-issued.
 pub(super) fn register_opened_using(&mut self,path:&Path,semantic_path:&Path,lease:SourceAcquisitionLease,parent:Option<usize>,directive_span:Span,directive_line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  self.check(a)?;let result=self.register_inner(path,semantic_path,lease,parent,directive_span,directive_line,a);if result.is_err(){self.failed=true}result
 }
 fn register_inner(&mut self,path:&Path,semantic_path:&Path,lease:SourceAcquisitionLease,parent:Option<usize>,directive_span:Span,directive_line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  if parent.is_some_and(|p|p>=self.plan.occurrences.len()){return Err(io::ErrorKind::InvalidInput.into())}
  let occurrence=self.plan.occurrences.len();let text=lease.source_text();let key_exists=self.plan.source_texts.contains_key(path);
  if self.plan.source_texts.get(path).is_some_and(|previous|previous.as_str()!=text.as_str()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"same captured source path changed during actual traversal"))}
  let mut metadata=add(path_bound(path)?,scaled(mem::size_of::<usize>(),8)?)?;
  if !self.plan.dependencies.contains(path){metadata=add(metadata,add(node::<PathBuf,()>()?,path_bound(path)?)?)?;}
  if !key_exists{metadata=add(metadata,add(node::<PathBuf,crate::SourceText>()?,path_bound(path)?)?)?;}
  path.to_str().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual semantic source path is not UTF8"))?;
  let semantic=semantic_path.to_str().ok_or(io::ErrorKind::InvalidInput)?;
  // The real include branch has already registered this semantic name. Own
  // its exact Arc payload once; the fixed grant covers control and alignment.
  metadata=add(metadata,add(semantic.len(),4*mem::size_of::<usize>())?)?;grow(&mut self.credit,metadata,a)?;
  let path=Arc::new(owned_path(path)?);let mut unused=opened_path_unused(&path)?;
  let semantic_path:Arc<str>=Arc::from(semantic);
  let row=IncludeOccurrence{path:Arc::clone(&path),semantic_path,original_entry:if parent.is_none(){Some(Arc::clone(&path))}else{None},parent,directive_span,directive_line,suppressed:false,non_text_kind:None,return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None};
  push(&mut self.plan.occurrences,row,&mut self.credit,a)?;
  if !key_exists{
   // No eager full-file line scan: raw geometry is issued by the SAME
   // demanded lexical frames. Generic decoded line tables are deliberately
   // absent; raw OriginArena rows own the authenticated line/span mapping.
   let key=owned_path(&path)?;unused=add(unused,opened_path_unused(&key)?)?;
   self.plan.source_texts.insert(key,text.clone());
  }
  if !self.plan.dependencies.contains(path.as_path()){
   let key=owned_path(&path)?;unused=add(unused,opened_path_unused(&key)?)?;
   self.plan.dependencies.insert(key);
  }
  self.plan.source_acquisitions.append_original(occurrence,lease,a)?;
  // All real path allocations and map inserts happened in their original
  // order; retire only unused allowance after those owners are settled.
  if unused!=0{a.shrink(&mut self.credit,unused).map_err(|e|a.take_operational_error().unwrap_or(e))?;}
  self.current_region=None;Ok(occurrence)
 }
 /// Actual emitted token chooses a region from its current registered physical
 /// occurrence. A return from a real child starts another encounter segment;
 /// no environment snapshot or PreparedLine is fabricated for raw output.
 pub(super) fn region_for_emission_using(&mut self,occurrence:usize,decoded_row:Span,a:&SettingAdmission<'_>)->io::Result<usize>{
  self.check(a)?;let result=(||{let lease=self.plan.source_acquisitions.get(&occurrence).ok_or(io::ErrorKind::InvalidInput)?;if decoded_row.start>decoded_row.end||decoded_row.end>lease.source_text().as_str().len(){return Err(io::ErrorKind::InvalidInput.into())}
   if let Some(index)=self.current_region{let row=&mut self.plan.regions[index];if row.occurrence==occurrence{row.source_span.start=row.source_span.start.min(decoded_row.start);row.source_span.end=row.source_span.end.max(decoded_row.end);return Ok(index)}}
   grow(&mut self.credit,2*(mem::size_of::<Vec<ExpansionSegment>>()+4*mem::size_of::<usize>()),a)?;let index=self.plan.regions.len();let region=IncludeRegion{occurrence,source_span:decoded_row,encounter_ordinal:self.plan.items.len(),manifest_source:self.plan.occurrences[occurrence].path.extension().is_some_and(|e|e=="dme"),segments:Arc::new(Vec::new()),effects:Arc::<Vec<MacroEffect>>::new(Vec::new())};push(&mut self.plan.regions,region,&mut self.credit,a)?;push(&mut self.plan.items,OrderedItem::Text(index),&mut self.credit,a)?;self.current_region=Some(index);Ok(index)
  })();if result.is_err(){self.failed=true}result
 }

 pub(super) fn occurrence(&self,index:usize)->io::Result<&IncludeOccurrence>{self.plan.occurrences.get(index).ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn lease(&self,index:usize)->io::Result<SourceAcquisitionLease>{self.plan.source_acquisitions.get(&index).cloned().ok_or_else(||io::ErrorKind::InvalidInput.into())}
 pub(super) fn charge_using(&mut self,bytes:usize,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;grow(&mut self.credit,bytes,a)}
 pub(super) fn definition_using(&self,origin:crate::macro_expansion::OriginalMacroOrigin,driver:&mut super::original_driver::RawSourceDriver,provider:&dyn crate::SourceProvider,a:&SettingAdmission<'_>)->io::Result<super::DefinitionOrigin>{let occurrence=self.occurrence(origin.occurrence)?;let lease=self.lease(origin.occurrence)?;let row=driver.physical_row_using(origin,&lease,provider,a)?;let end=driver.decoded_offset_using(origin.occurrence,&lease,origin.physical.end,a)?;Ok(super::DefinitionOrigin{path:Arc::clone(&occurrence.path),source_span:Span::new(row.point.source_offset,end),source_line:row.point.line})}
 pub(super) fn add_dependency_using(&mut self,path:&Path,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;if !self.plan.dependencies.contains(path){grow(&mut self.credit,add(node::<PathBuf,()>()?,path_bound(path)?)?,a)?;self.plan.dependencies.insert(owned_path(path)?);}Ok(())}
 pub(super) fn add_non_text_using(&mut self,path:&Path,parent:usize,span:Span,line:usize,kind:super::NonTextKind,a:&SettingAdmission<'_>)->io::Result<usize>{self.check(a)?;self.add_dependency_using(path,a)?;grow(&mut self.credit,add(path_bound(path)?,scaled(path.as_os_str().len(),4)?)?,a)?;let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(path.to_str().ok_or(io::ErrorKind::InvalidInput)?);let occurrence=self.plan.occurrences.len();push(&mut self.plan.occurrences,IncludeOccurrence{path,semantic_path,original_entry:None,parent:Some(parent),directive_span:span,directive_line:line,suppressed:false,non_text_kind:Some(kind),return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None},&mut self.credit,a)?;push(&mut self.plan.items,OrderedItem::NonText{occurrence,kind},&mut self.credit,a)?;self.current_region=None;Ok(occurrence)}
 pub(super) fn add_omitted_using(&mut self,path:&Path,parent:usize,span:Span,line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{self.check(a)?;self.add_dependency_using(path,a)?;grow(&mut self.credit,add(path_bound(path)?,scaled(path.as_os_str().len(),4)?)?,a)?;let path=Arc::new(owned_path(path)?);let semantic_path:Arc<str>=Arc::from(path.to_str().ok_or(io::ErrorKind::InvalidInput)?);let occurrence=self.plan.occurrences.len();push(&mut self.plan.occurrences,IncludeOccurrence{path,semantic_path,original_entry:None,parent:Some(parent),directive_span:span,directive_line:line,suppressed:false,non_text_kind:None,return_cursor:None,eof_cursor_line:None,eof_cursor_encounter:None},&mut self.credit,a)?;self.current_region=None;Ok(occurrence)}
 pub(super) fn add_file_dir_using(&mut self,path:&Path,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;grow(&mut self.credit,path_bound(path)?,a)?;push(&mut self.plan.file_dirs,owned_path(path)?,&mut self.credit,a)}

 pub(super) fn trace_using(&mut self,actual:&super::original_output_trace::OriginalOutputTrace,driver:&mut super::original_driver::RawSourceDriver,provider:&dyn crate::SourceProvider,a:&SettingAdmission<'_>)->io::Result<Arc<Vec<super::MacroExpansion>>>{
  self.check(a)?;
  if actual.depth()==0{
   // An empty trace carries no locations or authority. Reuse one funded
   // allocation in this plan so adjacent authenticated ordinary origins can
   // share their physical-row group, and do not reserve it per token.
   if self.empty_trace.is_none(){
    let bytes=mem::size_of::<Vec<super::MacroExpansion>>()+2*mem::size_of::<usize>();
    grow(&mut self.credit,bytes,a)?;
    self.empty_trace=Some(Arc::new(Vec::new()));
   }
   return Ok(Arc::clone(self.empty_trace.as_ref().expect("actual empty trace allocated")));
  }
  if let Some(last) = self.last_trace.as_ref().filter(|last| last.key.matches(actual, a)) {
   let mut matches = true;
   actual.visit_inner_to_outer_using(a, |entry| {
    // Geometry still borrows real provider bytes, in exactly the old order.
    // Never skip or replay that call on a hit, including its first IO error.
    let definition = entry.definition.map(|origin| self.definition_using(origin, driver, provider, a)).transpose()?;
    let prior = &last.rows[entry.depth - 1].definition;
    matches &= match (&definition, prior) {
     (None, None) => true,
     (Some(current), Some(previous)) => Arc::ptr_eq(&current.path, &previous.path)
      && current.source_span == previous.source_span && current.source_line == previous.source_line,
     _ => false,
    };
    Ok(())
   })?;
   if !matches {
    return Err(io::Error::new(io::ErrorKind::InvalidData, "actual macro trace definition changed within its source acquisition"));
   }
   return Ok(Arc::clone(&last.rows));
  }
  // Retire the previous weak backing before funding any new key.
  self.last_trace = None;
  let depth = actual.depth();
  let control = 4 * mem::size_of::<usize>();
  // Arc<Vec<_>> owns this Vec header in addition to the backing rows.
  let mut rows = Vec::new();
  grow(&mut self.credit, add(mem::size_of::<Vec<super::MacroExpansion>>(), control)?, a)?;
  actual.visit_inner_to_outer_using(a, |entry| {
   // The Arc<str> has one immutable byte payload. Keep the existing fixed
   // Arc allocation allowance for control and alignment, not four copies of
   // the spelling. The existing borrowed source name never becomes a String.
   grow(&mut self.credit, add(entry.name.len(), control)?, a)?;
   let name: Arc<str> = Arc::from(entry.name);
   let definition = entry.definition.map(|origin| self.definition_using(origin, driver, provider, a)).transpose()?;
   if self.empty_replacement_chain.is_none() {
    grow(&mut self.credit, control, a)?;
    self.empty_replacement_chain = Some(Arc::from([]));
   }
   if rows.is_empty() {
    // Fund the exact original trace depth once, after the first definition
    // loan (where the former row allocation ran). No transient geometric
    // copies or unfunded Vec capacity growth are possible.
    grow(&mut self.credit, scaled(depth, mem::size_of::<super::MacroExpansion>())?, a)?;
    rows = exact_rows(depth, a)?;
   }
   if rows.len() >= depth {
    return Err(io::ErrorKind::InvalidData.into());
   }
   let replacement_chain = Arc::clone(self.empty_replacement_chain.as_ref().expect("original empty replacement chain funded"));
   rows.push(super::MacroExpansion { name, invocation_span: entry.origin.physical, replacement_chain, definition });
   Ok(())
  })?;
  if rows.len() != depth {
   return Err(io::ErrorKind::InvalidData.into());
  }
  rows.reverse();
  // The outer row keeps the shared empty chain. Every other row aliases
  // the same earlier projected names. Keep the exact Arc payload funded,
  // and release the scratch Vec only after Arc::from has consumed it.
  for at in 1..rows.len() {
   let bytes = scaled(at, mem::size_of::<Arc<str>>())?;
   grow(&mut self.credit, add(bytes, control)?, a)?;
   let scratch = a.reserve(bytes).map_err(|error| a.take_operational_error().unwrap_or(error))?;
   let mut parents = exact_rows(at, a)?;
   parents.extend(rows[..at].iter().map(|row| Arc::clone(&row.name)));
   rows[at].replacement_chain = Arc::from(parents);
   drop(scratch);
  }
  let rows = Arc::new(rows);
  self.last_trace = Some(LastTraceProjection { key: actual.projection_key_using(a)?, rows: Arc::clone(&rows) });
  Ok(rows)
 }
 pub(super) fn finish_using(mut self,a:&SettingAdmission<'_>)->io::Result<(DirectivePlan,SharedSettingRetention)>{
  self.check(a)?;
  grow(&mut self.credit,mem::size_of::<SettingRootLease>()+4*mem::size_of::<usize>(),a)?;
  let Self{plan,credit,..}=self;
  Ok((plan,SharedSettingRetention::new(credit)))
 }
}

#[cfg(test)]
mod trace_storage_tests {
    use super::*;
    use crate::macro_expansion::OriginalMacroOrigin;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct NoSource;
    impl crate::SourceProvider for NoSource {
        fn read(&self, _: &Path) -> Result<String, String> {
            panic!("this trace fixture has no raw source to acquire")
        }
    }

    #[test]
    fn ordinary_tokens_share_one_funded_empty_projection_across_an_actual_macro_trace() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let defines = BTreeMap::new();
        let mut plan = OriginalPlanOwner::new(
            Path::new("empty-trace.dme"), InitialEnvironment::OriginalChecker0290,
            &defines, None, &a,
        ).unwrap();
        let mut driver = super::super::original_driver::RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290, &defines, &a,
            &mut |input, a| super::super::original_token_factory::initial_definition_using(
                input, a, &mut |_| panic!("fixed defaults have no lexical notice"),
                &mut |_, _| panic!("fixed defaults have no numeric notice"),
            ),
        ).unwrap();
        let empty = super::super::original_output_trace::OriginalOutputTrace::default();
        let first = plan.trace_using(&empty, &mut driver, &NoSource, &a).unwrap();
        let origin = OriginalMacroOrigin {
            physical: Span::new(5, 11), line: 2, byte_column: Some(3),
            occurrence: 0, invocation: true,
        };
        let actual = empty.pushed_using("TRACE", origin, 1, None, &a).unwrap();
        let nonempty = plan.trace_using(&actual, &mut driver, &NoSource, &a).unwrap();
        assert_eq!(nonempty.len(), 1);
        assert_eq!(nonempty[0].name.as_ref(), "TRACE");
        assert_eq!(nonempty[0].invocation_span, origin.physical);
        let before = used.load(Ordering::Acquire);
        for _ in 0..32 {
            let next = plan.trace_using(&empty, &mut driver, &NoSource, &a).unwrap();
            assert!(next.is_empty());
            assert!(Arc::ptr_eq(&first, &next));
            assert_eq!(used.load(Ordering::Acquire), before);
        }
        drop((first, nonempty, actual, empty, driver, plan));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn projected_trace_charges_exact_depth_and_releases_parent_scratch() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let defines = BTreeMap::new();
        let mut plan = OriginalPlanOwner::new(
            Path::new("exact-trace.dme"), InitialEnvironment::OriginalChecker0290,
            &defines, None, &a,
        ).unwrap();
        let mut driver = super::super::original_driver::RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290, &defines, &a,
            &mut |input, a| super::super::original_token_factory::initial_definition_using(
                input, a, &mut |_| panic!("fixed defaults have no lexical notice"),
                &mut |_, _| panic!("fixed defaults have no numeric notice"),
            ),
        ).unwrap();
        let origin = OriginalMacroOrigin {
            physical: Span::new(2, 7), line: 1, byte_column: Some(3),
            occurrence: 0, invocation: true,
        };
        let mut actual = super::super::original_output_trace::OriginalOutputTrace::default();
        let names = ["OUTER", "MIDDLE", "INNER"];
        for (at, name) in names.into_iter().enumerate() {
            actual = actual.pushed_using(name, origin, at + 1, None, &a).unwrap();
        }
        let before = plan.credit.bytes();
        let rows = plan.trace_using(&actual, &mut driver, &NoSource, &a).unwrap();
        assert_eq!(rows.capacity(), names.len(), "no power-of-two slack in projected rows");
        assert_eq!(rows.len(), names.len());
        for (at, row) in rows.iter().enumerate() {
            assert_eq!(row.name.as_ref(), names[at]);
            assert_eq!(row.replacement_chain.len(), at);
            for (alias, parent) in row.replacement_chain.iter().zip(&rows[..at]) {
                assert!(Arc::ptr_eq(alias, &parent.name));
            }
        }
        let control = 4 * mem::size_of::<usize>();
        let expected = mem::size_of::<Vec<super::super::MacroExpansion>>() + control
            + names.len() * mem::size_of::<super::super::MacroExpansion>()
            + names.iter().map(|name| name.len() + control).sum::<usize>()
            + control + (mem::size_of::<Arc<str>>() + control)
            + (2 * mem::size_of::<Arc<str>>() + control);
        assert_eq!(plan.credit.bytes() - before, expected);
        let other = super::super::original_output_trace::OriginalOutputTrace::default()
            .pushed_using("OTHER", origin, 1, None, &a).unwrap();
        let previous = plan.credit.bytes();
        let next = plan.trace_using(&other, &mut driver, &NoSource, &a).unwrap();
        assert!(Arc::ptr_eq(&rows[0].replacement_chain, &next[0].replacement_chain));
        assert_eq!(plan.credit.bytes() - previous,
            mem::size_of::<Vec<super::super::MacroExpansion>>() + control
            + mem::size_of::<super::super::MacroExpansion>() + "OTHER".len() + control);
        drop((rows, next, other, actual, driver, plan));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn exact_trace_hit_lends_both_actual_definition_sources_and_keeps_first_io_error() {
        use std::cell::{Cell, RefCell};
        use super::super::{original_driver::RawSourceDriver, original_output_trace::OriginalOutputTrace};

        struct Sources {
            definitions: [SourceAcquisitionLease; 2],
            calls: RefCell<Vec<usize>>,
            fail_at: Cell<Option<usize>>,
        }
        impl crate::SourceProvider for Sources {
            fn read(&self, _: &Path) -> Result<String, String> {
                panic!("a definition lookup must lend its original acquisition")
            }
            fn original_source_bytes<'a>(&'a self, lease: &'a SourceAcquisitionLease) -> io::Result<Option<&'a [u8]>> {
                let source = self.definitions.iter().position(|actual| actual.same_original_acquisition(lease))
                    .ok_or(io::ErrorKind::InvalidInput)?;
                let mut calls = self.calls.borrow_mut();
                calls.push(source);
                if self.fail_at.get() == Some(calls.len()) {
                    return Err(io::Error::from_raw_os_error(1450));
                }
                Ok(Some(lease.source_text().as_bytes()))
            }
        }

        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let defines = BTreeMap::new();
        let mut plan = OriginalPlanOwner::new(
            Path::new("outer.dme"), InitialEnvironment::OriginalChecker0290,
            &defines, None, &a,
        ).unwrap();
        let mut driver = RawSourceDriver::new(
            InitialEnvironment::OriginalChecker0290, &defines, &a,
            &mut |input, a| super::super::original_token_factory::initial_definition_using(
                input, a, &mut |_| panic!("fixed defaults have no lexical notice"),
                &mut |_, _| panic!("fixed defaults have no numeric notice"),
            ),
        ).unwrap();
        let sources = Sources {
            definitions: [
                SourceAcquisitionLease::from_raw_original_bytes(b"outer\n".to_vec(), 10u64),
                SourceAcquisitionLease::from_raw_original_bytes(b"inner\n".to_vec(), 20u64),
            ],
            calls: RefCell::new(Vec::new()),
            fail_at: Cell::new(None),
        };
        for (ordinal, (name, lease)) in ["outer.dme", "inner.dm"].iter().zip(&sources.definitions).enumerate() {
            let path = Path::new(name);
            let parent = ordinal.checked_sub(1);
            assert_eq!(plan.register_opened_using(path, path, lease.clone(), parent, Span::default(), 0, &a).unwrap(), ordinal);
            driver.push_opened_at(&sources, lease.clone(), ordinal, path, &a).unwrap();
        }
        let invocation = OriginalMacroOrigin {
            physical: Span::new(0, 5), line: 1, byte_column: Some(1), occurrence: 0, invocation: true,
        };
        let outer_definition = OriginalMacroOrigin { invocation: false, ..invocation };
        let inner_definition = OriginalMacroOrigin { occurrence: 1, ..outer_definition };
        let outer = OriginalOutputTrace::default().pushed_using("OUTER", invocation, 1, Some(outer_definition), &a).unwrap();
        let trace = outer.pushed_using("INNER", invocation, 2, Some(inner_definition), &a).unwrap();

        sources.calls.borrow_mut().clear();
        let first = plan.trace_using(&trace, &mut driver, &sources, &a).unwrap();
        assert_eq!(*sources.calls.borrow(), [1, 0]);
        assert_eq!(first[0].definition.as_ref().unwrap().path.as_path(), Path::new("outer.dme"));
        assert_eq!(first[1].definition.as_ref().unwrap().path.as_path(), Path::new("inner.dm"));
        assert_eq!(first[1].replacement_chain[0].as_ref(), "OUTER");

        sources.calls.borrow_mut().clear();
        let before = used.load(Ordering::Acquire);
        let repeat = plan.trace_using(&trace, &mut driver, &sources, &a).unwrap();
        assert_eq!(*sources.calls.borrow(), [1, 0]);
        assert!(Arc::ptr_eq(&repeat, &first));
        assert_eq!(used.load(Ordering::Acquire), before);

        let equal_but_distinct = outer.pushed_using("INNER", invocation, 2, Some(inner_definition), &a).unwrap();
        sources.calls.borrow_mut().clear();
        let other = plan.trace_using(&equal_but_distinct, &mut driver, &sources, &a).unwrap();
        assert_eq!(*sources.calls.borrow(), [1, 0]);
        assert_eq!(other, first);
        assert!(!Arc::ptr_eq(&other, &first));

        sources.calls.borrow_mut().clear();
        sources.fail_at.set(Some(2));
        let error = plan.trace_using(&equal_but_distinct, &mut driver, &sources, &a).unwrap_err();
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(*sources.calls.borrow(), [1, 0], "hit must neither skip nor replay real IO");
        drop((trace, equal_but_distinct, outer, driver, plan, first, repeat, other));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}

#[cfg(test)]
mod opened_path_storage_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn actual_open_registration_charges_each_retained_path_capacity_once() {
        let used=Arc::new(AtomicUsize::new(0));
        let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
        let root=Path::new("root.dme");
        let semantic=Path::new("child.dm");
        let measure=|physical:&Path|{
            let mut plan=OriginalPlanOwner::new(root,InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),None,&a).unwrap();
            let lease=SourceAcquisitionLease::from_raw_original_bytes(b"/datum/x\n".to_vec(),17u64);
            plan.register_opened_using(root,root,lease.clone(),None,Span::default(),0,&a).unwrap();
            let prior=plan.credit.bytes();
            let child=plan.register_opened_using(physical,semantic,lease.clone(),Some(0),Span::new(2,7),1,&a).unwrap();
            let row=plan.occurrence(child).unwrap();
            assert_eq!(row.path.as_path(),physical);
            assert_eq!(row.semantic_path.as_ref(),"child.dm");
            assert!(plan.lease(child).unwrap().same_binding(&lease));
            let text_key=plan.plan.source_texts.get_key_value(physical).unwrap().0;
            let dep_key=plan.plan.dependencies.get(physical).unwrap();
            let path_bytes=row.path.capacity()+text_key.capacity()+dep_key.capacity();
            let charge=plan.credit.bytes()-prior;
            drop(plan);
            assert_eq!(used.load(Ordering::Acquire),0);
            (charge,path_bytes)
        };
        let(short,short_path)=measure(Path::new("E:/root/child.dm"));
        let(long,long_path)=measure(Path::new("E:/root/a-much-longer-physical-prefix/child.dm"));
        assert!(long_path>short_path);
        assert_eq!(long-short,long_path-short_path,"only the three live physical PathBuf buffers scale with physical spelling");
    }
}
