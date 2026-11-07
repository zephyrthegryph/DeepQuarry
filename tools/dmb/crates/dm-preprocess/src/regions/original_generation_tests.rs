//! Small real raw/controller/product controls. Fixtures issue raw acquisitions;
//! the actual driver/indenter/primary perform every traversal and EOF decision.
use super::*;use dm_syntax::{OriginalDeclarationHeaderObserver,OriginalPrimaryHeader,OriginalHeaderFlow,OriginalPrimaryLiveHeader};
use crate::{SourceAcquisitionLease,OriginalRawOpenDecision,OriginalRawReadOutcome,OriginalRawAllocationPlan};
use std::{path::PathBuf,sync::{Mutex,atomic::{AtomicUsize,Ordering}},any::Any};
struct Memory{files:BTreeMap<PathBuf,SourceAcquisitionLease>,opened:Mutex<Vec<PathBuf>>,probed:Mutex<Vec<PathBuf>>}
impl Memory{fn new(files:&[(&str,&str)])->Self{Self{files:files.iter().map(|(path,text)|(PathBuf::from(path),SourceAcquisitionLease::from_raw_original_bytes(text.as_bytes().to_vec(),17u64))).collect(),opened:Mutex::new(Vec::new()),probed:Mutex::new(Vec::new())}}}
impl SourceProvider for Memory{
 fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::OriginalChecker0290}
 fn read(&self,_:&Path)->Result<String,String>{panic!("actual Original never requests ordinary preparation")}
 fn path_presence_admitted(&self,path:&Path,_:&dyn SourceArenaWork)->io::Result<bool>{self.probed.lock().unwrap().push(path.to_path_buf());Ok(self.files.contains_key(path))}
 fn original_raw_source_open_admitted(&self,path:&Path,_:usize,_:&dyn SourceArenaWork,after:&mut dyn FnMut()->io::Result<OriginalRawOpenDecision>,_:&mut dyn FnMut(usize)->io::Result<()>,decode:&mut dyn FnMut(OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&SourceAcquisitionLease)->io::Result<()>)->io::Result<OriginalRawReadOutcome>{
  self.opened.lock().unwrap().push(path.to_path_buf());let Some(source)=self.files.get(path)else{return Ok(OriginalRawReadOutcome::SourceOpenFailed(io::ErrorKind::NotFound.into()))};if after()?==OriginalRawOpenDecision::Suppress{return Ok(OriginalRawReadOutcome::Suppressed)}decode(OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;acquired(source)?;Ok(OriginalRawReadOutcome::Acquired(source.clone()))
 }
 fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !self.files.values().any(|actual|actual.same_original_acquisition(lease)){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(lease.source_text().as_bytes()))}
}
struct Credit{bytes:AtomicUsize,live:Arc<AtomicUsize>}
impl Drop for Credit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
impl crate::source_arena_credit::SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
struct Work{live:Arc<AtomicUsize>}
impl SourceArenaWork for Work{
 fn original_read_bookkeeping_bytes(&self)->io::Result<usize>{Ok(0)}
 fn checkpoint(&self)->io::Result<()>{Ok(())}
 fn reserve(&self,n:usize)->io::Result<crate::source_arena_credit::SourceArenaCredit>{self.live.fetch_add(n,Ordering::AcqRel);Ok(crate::source_arena_credit::SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(n),live:Arc::clone(&self.live)})))}
 fn grow(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let own=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&self.live,&own.live){return Err(io::ErrorKind::InvalidInput.into())}own.bytes.fetch_add(n,Ordering::AcqRel);self.live.fetch_add(n,Ordering::AcqRel);Ok(())}
 fn shrink(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let own=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&self.live,&own.live){return Err(io::ErrorKind::InvalidInput.into())}own.bytes.fetch_update(Ordering::AcqRel,Ordering::Acquire,|old|old.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.live.fetch_sub(n,Ordering::AcqRel);Ok(())}
}
#[test]
fn original_diagnostic_history_preserves_macro_origins_but_cannot_issue_generation() {
    struct BatchHost(Arc<dm_syntax::SettingChargeCounter>);
    impl super::super::OriginalBatchSyntaxHost for BatchHost {
        fn with_producer_admission(&self, run: &mut dyn FnMut(&SettingAdmission<'_>) -> io::Result<()>) -> io::Result<()> {
            run(&SettingAdmission::new(&self.0, 64 << 20, &|| Ok(())))
        }
    }
    let root = "E:/controller/diagnostic-history.dme";
    let provider = Memory::new(&[(root, concat!(
        "/// Original docs for the first VALUE\n",
        "#define VALUE 3\n",
        "#define VALUE 7\n",
        "/datum/before\n    var/value = VALUE\n",
        "#undef VALUE\n",
        "/datum/after\n    var/value = VALUE\n",
    ))]);
    let work = Work { live: Arc::new(AtomicUsize::new(0)) };
    let syntax = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&syntax, 64 << 20, &|| Ok(()));
    let host = BatchHost(Arc::clone(&syntax));
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let batch = OriginalBatchExecution::new(&provider, &host, &executor);
    let run = |compact| {
        let mut consumer = Consumer;
        let definitions = BTreeMap::new();
        if compact {
            GenerationDirectivePlan::prepare_original_diagnostic_stream_using(
                Path::new(root), &provider, &definitions, omissions(), 1 << 20, &work, &a,
                Some(&batch), &mut consumer,
            )
        } else {
            GenerationDirectivePlan::prepare_original_stream_using(
                Path::new(root), &provider, &definitions, omissions(), 1 << 20, &work, &a,
                Some(&batch), &mut consumer,
            )
        }.unwrap()
    };
    let full_generation = run(false);
    assert!(full_generation.into_generation_parts().is_ok());
    let restricted_generation = run(true);
    assert_eq!(restricted_generation.delivery(), OriginalDemandDelivery::AnalyzeBatch8192x64);
    assert!(restricted_generation.token_projection.as_ref().unwrap().eof);
    assert_eq!(restricted_generation.into_generation_parts().err().unwrap().kind(), io::ErrorKind::InvalidInput);
    assert_eq!(syntax.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());

    let full = run(false);
    let retained_full = syntax.load(Ordering::Acquire);
    let compact = run(true);
    assert!(syntax.load(Ordering::Acquire) - retained_full < retained_full,
        "same issued expansion retains fewer charged historical owners");
    let (marks, live, authored) = compact.retention.history.diagnostic_marks();
    let removed = marks.collect::<Vec<_>>();
    assert_eq!(removed.len(), 1);
    assert_eq!(removed[0].0, "VALUE");
    assert_eq!(removed[0].1.unwrap().line, 3);
    assert_eq!(removed[0].2.line, 6);
    let with_docs = full.retention.history.entries()
        .find(|entry| entry.name == "VALUE" && entry.defined_at.is_some_and(|point| point.line == 2))
        .unwrap();
    assert!(with_docs.product.docs().iter().any(|doc| doc.text.get().contains("Original docs for the first VALUE")));
    let full_current = full.retention.history.entries()
        .filter(|entry| matches!(entry.end, super::super::original_define_history::OriginalDefineHistoryEnd::Final { .. }));
    assert_eq!(full_current.count(), live);
    assert_eq!(authored, 1);
    drop(removed);

    let (full_plan, full_expanded, full_primary, full_binding) = full.into_diagnostic_parts_using(&a).unwrap();
    let (compact_plan, compact_expanded, compact_primary, compact_binding) = compact.into_diagnostic_parts_using(&a).unwrap();
    assert_eq!(full_expanded.text.as_str(), compact_expanded.text.as_str());
    assert!(full_expanded.origins.iter().map(|row| row.macro_expansions)
        .eq(compact_expanded.origins.iter().map(|row| row.macro_expansions)));
    let notices: Vec<_> = compact_plan.original_notices().iter().map(|notice| (notice.error_type, notice.message)).collect();
    assert!(notices.iter().any(|(kind, _)| *kind == Some("macro_redefined")));
    assert!(full_plan.original_notices().iter().map(|notice| (notice.error_type, notice.message))
        .eq(notices));
    drop((full_plan, full_expanded, full_primary, full_binding, compact_plan, compact_expanded, compact_primary, compact_binding));
    assert_eq!(syntax.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(work.live.load(Ordering::Acquire), 0);
}

struct Consumer;impl OriginalDeclarationHeaderObserver for Consumer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}
impl OriginalPrimaryStreamConsumer for Consumer{fn callable(&mut self,_:OriginalPrimaryLiveHeader,_:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{panic!("this raw traversal fixture has no callable declaration")}}
fn omissions()->GenerationOmissions{GenerationOmissions::probe([], &mut |_|panic!("empty explicit output roster"),&mut |_|Ok(())).unwrap()}
#[test]
fn committed_original_stream_keeps_the_actual_token_and_literal_owners() {
    struct Committed;
    impl OriginalDeclarationHeaderObserver for Committed {
        fn header(&mut self, _: OriginalPrimaryHeader<'_>) -> io::Result<OriginalHeaderFlow> {
            Ok(OriginalHeaderFlow::Continue)
        }
    }
    impl OriginalPrimaryStreamConsumer for Committed {
        fn retains_committed_items(&self) -> bool { true }

        fn callable(&mut self, _: OriginalPrimaryLiveHeader, _: &mut dyn super::super::OriginalFormalTokenStream) -> io::Result<OriginalHeaderFlow> {
            panic!("this stream contains no callable")
        }
    }

    let root = Path::new("E:/controller/committed.dme");
    let provider = Memory::new(&[("E:/controller/committed.dme", "#define VALUE 7\n/datum/retained\n    var/value = VALUE\n")]);
    let work = Work { live: Arc::new(AtomicUsize::new(0)) };
    let syntax = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&syntax, 8 << 20, &|| Ok(()));
    let product = GenerationDirectivePlan::prepare_original_checker_stream_using(
        root, &provider, &BTreeMap::new(), omissions(), 1 << 20, &work, &a, &mut Committed,
    ).unwrap();
    let checked = product.token_projection.as_ref().unwrap();
    assert!(checked.eof);
    assert_eq!(checked.rows, product.expanded().tokens.shared().unwrap().window().len());
    let (plan, expanded, primary, binding) = product.into_diagnostic_parts_using(&a).unwrap();
    let OriginalStreamPrimary::Committed(primary) = primary else { panic!("compact consumer got dense items") };
    assert!(primary.tokens().same_owner(expanded.tokens.shared().unwrap()));
    let items = primary.items(&expanded.text).unwrap();
    let owner = items.get(0).unwrap();
    assert_eq!(owner.header(), "/datum/retained");
    let var = owner.children().get(0).unwrap();
    assert_eq!(var.header(), &expanded.text[var.header_span().range()]);
    assert!(var.header().ends_with('7'));
    let full = dm_syntax::Span::new(0, expanded.text.len());
    let view = binding.checked_view(&expanded.text, full, &binding, &a).unwrap();
    assert!(!view.checked_facts(&expanded.text).unwrap().raw_parts().0.is_empty());
    let foreign = SourceText::from(expanded.text.as_str().to_owned());
    assert!(binding.checked_view(&foreign, full, &binding, &a).is_err());
    assert_eq!(*provider.opened.lock().unwrap(), [root.to_path_buf()]);
    drop((view, plan, expanded, primary, binding));
    assert_eq!(syntax.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(work.live.load(Ordering::Acquire), 0);
}
#[test]fn real_lazy_controller_runs_include_define_pop_and_publishes_same_literal_binding_and_raw_mapping(){
 let provider=Memory::new(&[("E:/controller/main.dme","#define VALUE 3\n#include \"child.dm\"\n#undef VALUE\n/datum/root\n    var/value = VALUE\n"),("E:/controller/child.dm","#define VALUE 7\n/datum/child\n    var/value = VALUE\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));
 let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/main.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();assert_eq!(product.delivery(),OriginalDemandDelivery::CheckerLazy0290);assert!(product.expanded().text.as_str().contains('7'));assert!(product.expanded().text.as_str().contains('3'));assert!(product.expanded().origins.len()>0);let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert_eq!(plan.occurrences().len(),2);assert_eq!(plan.occurrences()[0].semantic_path.as_ref(),"E:/controller/main.dme");assert_eq!(plan.occurrences()[1].semantic_path.as_ref(),"child.dm");assert_eq!(plan.occurrences()[1].path.as_path(),Path::new("E:/controller/child.dm"));assert!(plan.original_notices().iter().any(|notice|notice.error_type==Some("macro_redefined")));assert_eq!(provider.opened.lock().unwrap().as_slice(),[PathBuf::from("E:/controller/main.dme"),PathBuf::from("E:/controller/child.dm")]);assert!(plan.source_line_starts().is_empty(),"no eager line walk over unread body" );drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);
}
#[test]
fn actual_original_origins_share_empty_trace_across_includes_without_losing_macro_provenance() {
    let provider=Memory::new(&[
        ("E:/controller/shared-trace.dme",
         "#define FROM_ROOT 7\n#include \"child.dm\"\n/datum/root\n    var/value = 3\n"),
        ("E:/controller/child.dm","/datum/child\n    var/value = FROM_ROOT\n"),
    ]);
    let work=Work{live:Arc::new(AtomicUsize::new(0))};
    let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));
    let product=GenerationDirectivePlan::prepare_original_checker_stream_using(
        Path::new("E:/controller/shared-trace.dme"),&provider,&BTreeMap::new(),omissions(),
        1<<20,&work,&a,&mut Consumer,
    ).unwrap();
    let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();
    let regions=plan.regions();
    assert!(regions.len()>1);
    assert!(regions.iter().all(|region|region.segments.is_empty()&&region.effects.is_empty()));
    assert!(regions.iter().all(|region|Arc::ptr_eq(&region.segments,&regions[0].segments)
        &&Arc::ptr_eq(&region.effects,&regions[0].effects)));
    let expected: Vec<_> = expanded.origins.iter().map(|row| row.region).collect();
    assert!(expected.windows(2).any(|pair| pair[0] == pair[1]));
    let ordinary = ExpandedRegions { dense_emission_regions: expected.clone(), ..Default::default() };
    assert!(expanded.same_emission_regions(&ordinary));
    assert!(ordinary.same_emission_regions(&expanded));
    let changed = ExpandedRegions { dense_emission_regions: expected[1..].to_vec(), ..Default::default() };
    assert!(!expanded.same_emission_regions(&changed));
    let mut ordinals = expanded.emission_regions();
    assert_eq!(ordinals.len(), expected.len());
    assert_eq!(ordinals.nth(1), expected.get(1).copied());
    assert_eq!(ordinals.next_back(), expected.last().copied());
    assert_eq!(ordinals.collect::<Vec<_>>(), expected[2..expected.len() - 1]);
    let mut empty=expanded.origins.iter().filter(|row|row.macro_expansions.is_empty());
    let first=empty.next().expect("actual ordinary emitted token");
    let mut saw_root=first.origin.path.ends_with("shared-trace.dme");
    let mut saw_child=first.origin.path.ends_with("child.dm");
    for row in empty {
        assert!(first.macro_expansions.same_owner(row.macro_expansions));
        saw_root|=row.origin.path.ends_with("shared-trace.dme");
        saw_child|=row.origin.path.ends_with("child.dm");
    }
    assert!(saw_root&&saw_child);
    let trace=expanded.origins.iter().map(|row|row.macro_expansions)
        .find(|trace|trace.get(0).is_some_and(|entry|entry.name=="FROM_ROOT"))
        .expect("actual rooted macro expansion in child");
    let expansion=trace.get(0).unwrap();
    assert!(expansion.definition.unwrap().path.ends_with("shared-trace.dme"));
    assert_eq!(trace.len(),1);
    assert!(trace.pooled_backing().is_some(), "actual narrow Original trace uses its admitted page");
    #[cfg(target_pointer_width = "64")]
    assert_eq!(trace.buffers(), [(trace.owner_address(),16),(0,0)]);
    let escaped=trace.to_owned();
    let pointer=trace.owner_address();
    assert!(escaped.view().same_owner(trace));
    assert_eq!(provider.opened.lock().unwrap().len(),2);
    let alias=expanded.origins.clone();
    drop((plan,expanded,primary,binding));
    assert!(syntax.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes());
    drop(alias);
    assert_eq!(escaped.view().owner_address(),pointer);
    assert!(escaped.view().get(0).unwrap().definition.unwrap().path.ends_with("shared-trace.dme"));
    drop(escaped);
    assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(work.live.load(Ordering::Acquire),0);
}

#[test]
fn actual_nested_macro_resumes_the_same_projected_outer_origin() {
    let root = Path::new("E:/controller/trace-resume.dme");
    let provider = Memory::new(&[("E:/controller/trace-resume.dme",
        "#define INNER 200\n#define OUTER 100 + INNER + 300\n/datum/holder\n    var/value = OUTER\n")]);
    let work = Work { live: Arc::new(AtomicUsize::new(0)) };
    let syntax = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&syntax, 8 << 20, &|| Ok(()));
    let product = GenerationDirectivePlan::prepare_original_checker_stream_using(
        root, &provider, &BTreeMap::new(), omissions(), 1 << 20, &work, &a, &mut Consumer,
    ).unwrap();
    let expanded = product.expanded();
    let find_trace = |token| expanded.origins.iter()
        .find(|row| expanded.text.as_str().get(row.output_span.range()) == Some(token))
        .expect("actual emitted replacement token").macro_expansions;
    let first = find_trace("100");
    let nested = find_trace("200");
    let resumed = find_trace("300");
    assert_eq!(first.iter().map(|row| row.name).collect::<Vec<_>>(), ["OUTER"]);
    assert_eq!(nested.iter().map(|row| row.name).collect::<Vec<_>>(), ["OUTER", "INNER"]);
    assert!(first.same_owner(resumed));
    assert!(!first.same_owner(nested));
    assert!(resumed.get(0).unwrap().definition.unwrap().path.ends_with("trace-resume.dme"));
    assert_eq!(*provider.opened.lock().unwrap(), [root.to_path_buf()]);
    drop(product);
    assert_eq!(syntax.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(work.live.load(Ordering::Acquire), 0);
}

#[test]fn real_controller_duplicate_still_opens_before_suppression_and_nontext_only_probes_metadata(){
 let provider=Memory::new(&[("E:/controller/main.dme","#include \"child.dm\"\n#include \"child.dm\"\n#include \"map.dmm\"\n/datum/root\n"),("E:/controller/child.dm","/datum/child\n"),("E:/controller/map.dmm","this must not be read as source")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/main.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert_eq!(provider.opened.lock().unwrap().iter().filter(|path|path.ends_with("child.dm")).count(),2);assert!(!provider.opened.lock().unwrap().iter().any(|path|path.ends_with("map.dmm")));let notice=plan.original_notices().iter().find(|notice|notice.error_type==Some("duplicate_include")).unwrap();assert_eq!(notice.notes.count(),1);assert!(plan.items().iter().any(|item|matches!(item,super::super::OrderedItem::NonText{kind:super::super::NonTextKind::Map,..})));drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);
}

#[test]fn genuine_empty_and_lf_raw_sources_keep_real_final_newline_locations(){
 for(text,line)in[("",1),("\n",2)]{let provider=Memory::new(&[("E:/controller/empty.dme",text)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/empty.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();assert_eq!(product.expanded().text.as_str(),";\n");assert_eq!(product.expanded().origins.len(),1);let(_,point,_,_,_)=product.expanded().origins.original_raw_point_geometry(0).unwrap();assert_eq!((point.line,point.byte_column),(line,1));let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert_eq!(plan.occurrences().len(),1);assert!(plan.original_notices().is_empty());drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}
}

#[test]fn actual_empty_condition_records_old_first_term_failure_at_hash_and_keeps_endif_balanced(){let provider=Memory::new(&[("E:/controller/empty-condition.dme","#if\n/datum/disabled\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/empty-condition.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1);assert_eq!(notices[0].message,"got EOF, expected one of: operator, literal, variable, proc call");assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:1,..}));assert!(!expanded.text.as_str().contains("disabled"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_else_and_real_eof_keep_completed_conditional_ranges(){let provider=Memory::new(&[("E:/controller/ranges.dme","#if 0\n/datum/no\n#else\n/datum/yes\n#endif\n#if 1\n/datum/open\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/ranges.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let ranges=plan.conditional_ranges().collect::<Vec<_>>();assert_eq!(ranges.len(),3);assert_eq!(ranges.iter().map(|range|range.active).collect::<Vec<_>>(),[false,true,true]);assert_eq!(plan.original_notices().iter().filter(|notice|notice.message=="unterminated #if/#ifdef").count(),1);drop(ranges);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_lazy_callable_stop_retains_open_conditional_without_inventing_history_or_eof_notice(){struct Stop;impl OriginalDeclarationHeaderObserver for Stop{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}impl OriginalPrimaryStreamConsumer for Stop{fn callable(&mut self,_:OriginalPrimaryLiveHeader,_:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Stop)}}let provider=Memory::new(&[("E:/controller/stopped-range.dme","#if 1\n/datum/proc/prefix(x)\n    BODY\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/stopped-range.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Stop).unwrap();let checked=product.token_projection.as_ref().unwrap();assert!(!checked.eof);assert_eq!(checked.rows,product.expanded().tokens.shared().unwrap().window().len());let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.conditional_ranges().next().is_none(),"a parser stop is not source EOF or a completed conditional interval");assert!(!plan.original_notices().iter().any(|notice|notice.message=="unterminated #if/#ifdef"));assert!(!expanded.text.as_str().contains("BODY"));assert_eq!(expanded.emission_regions().len(),expanded.origins.len());drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_raw_controller_keeps_indented_procedure_body_inside_real_braces(){struct Body;impl OriginalDeclarationHeaderObserver for Body{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}impl OriginalPrimaryStreamConsumer for Body{fn callable(&mut self,_:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{for expected in ["var","/","static","/","A","=","1",")"]{let actual=source.next_header_token()?.ok_or(io::ErrorKind::UnexpectedEof)?;assert_eq!(actual.text,expected);}Ok(OriginalHeaderFlow::Continue)}}let provider=Memory::new(&[("E:/controller/body.dme","/proc/p(var/static/A=1)\n    return A\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/body.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Body).unwrap();let checked=product.token_projection.as_ref().unwrap();assert!(checked.eof);assert_eq!(checked.rows,product.expanded().tokens.shared().unwrap().window().len());let text=product.expanded().text.as_str();assert!(text.contains("{\nreturn A;\n}\n"),"actual produced body must retain indentation: {text:?}");drop(product);assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_nested_define_in_condition_dispatches_on_same_raw_cursor_and_preserves_enclosing_completion(){let provider=Memory::new(&[("E:/controller/nested-condition.dme","#if #define VALUE 1\nVALUE\n/datum/yes\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/nested-condition.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(!expanded.text.as_str().contains("yes"));assert!(expanded.text.as_str().contains("after"));let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1);assert_eq!(notices[0].message,"got '\n', expected one of: operator, literal, variable, proc call");assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:5,..}));drop(notices);assert_eq!(plan.conditional_ranges().count(),1);assert!(plan.final_macro("VALUE").is_some());drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}
#[test]fn nested_directive_stack_resource_refusal_is_operational_and_never_source_false_recovery(){let provider=Memory::new(&[("E:/controller/nested-resource.dme","#if #define VALUE 1\nVALUE\n/datum/yes\n#endif\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::with_stack_allowance(&syntax,64<<20,32*1024,&||Ok(()));let error=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/nested-resource.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).err().expect("actual root plus outer control consume two frames; nested control exceeds them");assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_consumes_first_expression_and_retires_unused_queue_without_false_syntax_error(){let provider=Memory::new(&[("E:/controller/prefix-condition.dme","#if 1 2\n/datum/yes\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/prefix-condition.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty());assert!(expanded.text.as_str().contains("yes"));assert!(!expanded.text.as_str().contains('2'));drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_script_includes_retain_order_duplicates_and_paths_without_opening_payload(){let provider=Memory::new(&[("E:/controller/scripts.dme","#include \"one.dms\"\n#include \"two.dms\"\n#include \"one.dms\"\n/datum/after\n"),("E:/controller/one.dms","SCRIPT_BYTES_MUST_NOT_OPEN"),("E:/controller/two.dms","OTHER_SCRIPT_BYTES")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/scripts.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let scripts=plan.script_includes().collect::<Vec<_>>();assert_eq!(scripts.iter().map(|(path,_)|path.file_name().unwrap().to_str().unwrap()).collect::<Vec<_>>(),["one.dms","two.dms","one.dms"]);for(index,(_,place))in scripts.iter().enumerate(){assert!(matches!(place,super::super::OriginalNoticePlace::Actual{line,..}if *line==index+1));}assert_eq!(*provider.opened.lock().unwrap(),[PathBuf::from("E:/controller/scripts.dme")]);assert!(!expanded.text.as_str().contains("SCRIPT_BYTES"));drop(scripts);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_root_open_observer_sees_only_typed_initial_open_failure_and_precedes_real_read(){struct Observe{before:AtomicUsize,failed:AtomicUsize,stop:bool}impl super::OriginalRootOpenObserver for Observe{fn before_root_read_using(&self,_:&dyn SourceProvider,_:&Path,_:&dyn SourceArenaWork,_:&SettingAdmission<'_>)->io::Result<()>{self.before.fetch_add(1,Ordering::AcqRel);if self.stop{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}fn actual_root_open_failed_using(&self,failed:super::OriginalRootOpenFailureLoan<'_,'_>){assert_eq!(failed.error().kind(),io::ErrorKind::NotFound);assert_eq!(failed.path(),Path::new("E:/controller/missing.dme"));self.failed.fetch_add(1,Ordering::AcqRel);}}let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));for stop in [false,true]{let provider=Memory::new(&[]);let observer=Observe{before:AtomicUsize::new(0),failed:AtomicUsize::new(0),stop};let error=GenerationDirectivePlan::prepare_original_checker_stream_observing_root_using(Path::new("E:/controller/missing.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer,&observer).err().unwrap();assert_eq!(observer.before.load(Ordering::Acquire),1);assert_eq!(observer.failed.load(Ordering::Acquire),usize::from(!stop));assert_eq!(provider.opened.lock().unwrap().len(),usize::from(!stop));if stop{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),io::ErrorKind::NotFound)}}assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_fexists_uses_saved_include_file_and_metadata_only_probe(){let provider=Memory::new(&[("E:/controller/exists.dme","#include \"nested/child.dm\"\n/datum/after\n"),("E:/controller/nested/child.dm","#if fexists(\"present.bin\")\n/datum/yes\n#endif\n#if fexists(\"missing.bin\")\n/datum/no\n#endif\n"),("E:/controller/nested/present.bin","NEVER_OPEN_PAYLOAD")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/exists.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(expanded.text.as_str().contains("yes"));assert!(!expanded.text.as_str().contains("/no"));assert!(plan.original_notices().is_empty());assert!(provider.probed.lock().unwrap().contains(&PathBuf::from("E:/controller/nested/present.bin")));assert!(provider.probed.lock().unwrap().contains(&PathBuf::from("E:/controller/nested/missing.bin")));assert_eq!(provider.opened.lock().unwrap().len(),2);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_parser_recovery_notice_is_retained_before_constant_failure(){let provider=Memory::new(&[("E:/controller/input-notice.dme","#if input() as unknown_name\n/datum/no\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/input-notice.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),2);assert_eq!(notices[0].message,"bad input type: 'unknown_name'");assert_eq!(notices[1].message,"non-constant expression");assert_eq!(notices[0].severity,super::super::OriginalNoticeSeverity::Error);assert!(!expanded.text.as_str().contains("/no"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_warning_and_error_directive_strings_preserve_plain_payload_and_keep_following_source(){let provider=Memory::new(&[("E:/controller/stringy.dme","#warn \"quoted\" / 3\n#error causal_failure\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/stringy.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),2);assert_eq!(notices[0].message,"#warn \"quoted\" / 3");assert_eq!(notices[1].message,"#error causal_failure");assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_raw_condition_trig_uses_existing_native_judge_without_full_source_fallback(){let provider=Memory::new(&[("E:/controller/trig.dme","#if cos(0) && !sin(0)\n/datum/yes\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/trig.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(expanded.text.as_str().contains("yes"));assert!(plan.original_notices().is_empty());drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_typed_unary_tokens_preserve_old_rejection_and_never_drop_postfix(){for(condition,message)in[("++1","non-constant unary operation: ++1"),("1++","non-constant unary operation: 1++"),("&1","non-constant unary operation: &1"),("*1","non-constant unary operation: *1"),("+1","got '+', expected one of: operator, literal, variable, proc call")]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/unary.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/unary.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1);assert_eq!(notices[0].message,message);assert!(!expanded.text.as_str().contains("disabled"),"actual postfix must not be discarded as unused queue");drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_condition_group_call_and_ternary_failures_match_executed_pinned_expectations(){for(condition,message,column)in[("(1","got EOF, expected one of: operator, field access, ')'",6),("(1 ]","got ']', expected one of: operator, field access, ')'",8),("defined(","got EOF, expected one of: ')', ',', operator, literal, variable, proc call",12),("1 ? 2","got EOF, expected one of: operator, field access, ':'",9)]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/group.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/group.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1);assert_eq!(notices[0].message,message);assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:actual,..}if actual==column));assert!(!expanded.text.as_str().contains("disabled"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_condition_absolute_prefab_values_preserve_truth_and_equality_without_model_lookup(){let provider=Memory::new(&[("E:/controller/path-values.dme","#if /datum == /datum && /datum != /obj\n/datum/yes\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/path-values.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty());assert!(expanded.text.as_str().contains("yes"));drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_delimiter_frontiers_match_namespace_controlled_pinned_library(){for(condition,message,column)in[("defined(1","got EOF, expected one of: operator, field access, ')', ','",13),("defined(1 ]","got ']', expected one of: operator, field access, ')', ','",15),("(1 2","got '2', expected one of: operator, field access, ')'",8),("x[1","got EOF, expected one of: operator, field access, ']'",7),("x[1)","got ')', expected one of: operator, field access, ']'",8),("::","got EOF, expected one of: identifier",5),("f(1,","got EOF, expected one of: ')', ',', operator, literal, variable, proc call",8),("f(1 2","got '2', expected one of: operator, field access, ')', ','",9),("1 ? 2 ]","got ']', expected one of: operator, field access, ':'",11)]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/delimiters.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/delimiters.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1,"{condition}");assert_eq!(notices[0].message,message,"{condition}");assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:actual,..}if actual==column),"{condition}");assert!(!expanded.text.as_str().contains("disabled"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_condition_missing_member_keeps_recovery_notice_and_real_follower(){let provider=Memory::new(&[("E:/controller/member.dme","#if x.\n/datum/disabled\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/member.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),2);assert_eq!(notices[0].message,"got EOF, expected one of: identifier");assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:6,..}));assert_eq!(notices[1].message,"cannot reference variable \"x\" in this context");assert!(matches!(notices[1].place,super::super::OriginalNoticePlace::Actual{line:1,column:1,..}));assert!(!expanded.text.as_str().contains("disabled"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_compound_folded_values_preserve_typed_ordered_argument_equality(){for condition in["list(1+1,name=3)==list(2,\"name\"=3)","matrix(1+1)==matrix(2)","matrix()!=list()","list(\"x\")!=list('x')","list(1,2)!=list(2,1)","list(name=1)!=list(\"name\",1)","icon(list(1+1))==icon(list(2))","file(\"x\")!=icon(\"x\")"]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/compound.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/compound.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty(),"{condition}");assert!(expanded.text.as_str().contains("yes"),"{condition}");drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_rgb_ordered_colorspace_and_warning_failures_use_real_condition_result(){for condition in["rgb(1,2,3)==\"#010203\"","rgb(red=1,green=2,blue=3,alpha=4)==\"#01020304\"","rgb(h=0,s=100,v=100)==\"#ff0000\""]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/rgb.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/rgb.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty(),"{condition}");assert!(expanded.text.as_str().contains("yes"),"{condition}");drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}let provider=Memory::new(&[("E:/controller/rgb.dme","#if rgb(300,0,0)\n/datum/disabled\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/rgb.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notice=plan.original_notices().iter().next().unwrap();assert_eq!(notice.severity,super::super::OriginalNoticeSeverity::Warning);assert_eq!(notice.message,"malformed rgb() call, 300 is not within the valid range (0..255)");assert!(!expanded.text.as_str().contains("disabled"));drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_prefab_fields_fold_before_path_and_preserve_indexmap_duplicate_and_equality_contract(){for condition in["/datum{a=1;b=2}==/datum{b=2;a=1}","/datum{a=1;a=2}==/datum{a=2}","/datum{a=1+1}==/datum{a=2}","/datum{a=1}!=/datum{a=2}"]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/prefab.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/prefab.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty(),"{condition}");assert!(expanded.text.as_str().contains("yes"),"{condition}");drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_native_new_argument_presence_distinguishes_absent_empty_and_folded_typed_construction(){for condition in["new","new != new()","new /datum","new /datum != new /datum()","new /datum(1+1)==new /datum(2)","list(new,new())!=list(new(),new())"]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/new.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/new.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty(),"{condition}");assert!(expanded.text.as_str().contains("yes"),"{condition}");drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_pragma_multiple_keeps_semantic_file_identity_before_first_include(){for(project,roots,duplicate)in[("root.dme",3,false),("E:/controller/root.dme",2,true)]{let raw="#ifndef ONCE\n#pragma multiple\n#define ONCE 1\n#include \"root.dme\"\n#include \"root.dme\"\n#endif\n/datum/root\n";let provider=Memory::new(&[(project,raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new(project),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert_eq!(expanded.text.as_str().matches("/datum/root").count(),roots,"root FileId key must remain distinct from physical path identity");assert_eq!(plan.original_notices().iter().any(|n|n.error_type==Some("duplicate_include")),duplicate);assert_eq!(provider.opened.lock().unwrap().len(),3,"real open still precedes suppression decision");drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}


#[test]fn actual_root_prefab_and_spaced_scalar_follower_match_qualified_library(){for condition in["/","/datum/"]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/rootpath.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/rootpath.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();assert!(plan.original_notices().is_empty(),"{condition}");assert!(expanded.text.as_str().contains("yes"),"{condition}");drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}let provider=Memory::new(&[("E:/controller/member-scalar.dme","#if 1 .\n/datum/disabled\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/member-scalar.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),2);assert_eq!(notices[0].message,"got EOF, expected one of: identifier");assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:7,..}));assert_eq!(notices[1].message,"non-constant expression follower: 1 Field(Dot, \"\")");assert!(!expanded.text.as_str().contains("disabled"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_condition_interpolation_parses_children_before_nonconstant_template_judge(){for condition in["\"prefix[1+1]suffix\"","\"[MISSING]\"","\"[]\""]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/template.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/template.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1,"{condition}");assert_eq!(notices[0].message,"non-constant expression","{condition}");assert!(!expanded.text.as_str().contains("disabled"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_condition_template_admission_deadline_and_quota_never_become_source_notice(){use std::cell::Cell;let raw="#if \"prefix[1+1]suffix\"\n/datum/disabled\n#endif\n/datum/after\n";let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let work=Work{live:Arc::new(AtomicUsize::new(0))};let calls=Cell::new(0usize);let peak=Cell::new(0usize);{let provider=Memory::new(&[("E:/controller/template-budget.dme",raw)]);let checkpoint=||{calls.set(calls.get()+1);peak.set(peak.get().max(used.load(Ordering::Acquire)));Ok(())};let a=SettingAdmission::new(&used,64<<20,&checkpoint);drop(GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/template-budget.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap());}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);assert!(calls.get()>3&&peak.get()>0);for stop_at in[1,calls.get()/2,calls.get()-1]{let provider=Memory::new(&[("E:/controller/template-budget.dme",raw)]);let count=Cell::new(0usize);let checkpoint=||{count.set(count.get()+1);if count.get()>=stop_at{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&used,64<<20,&checkpoint);let error=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/template-budget.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}let provider=Memory::new(&[("E:/controller/template-budget.dme",raw)]);let a=SettingAdmission::new(&used,peak.get()-1,&||Ok(()));let error=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/template-budget.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_original_brace_is_prefab_term_only_and_unread_suffix_does_not_execute(){for(condition,message)in[("foo{a=MISSING}",Some("cannot reference variable \"foo\" in this context")),("func(){a=MISSING}",Some("non-constant function call: func")),("(/datum){a=MISSING}",None),("/datum{}{}",None),("1{a=MISSING}",None),("new{a=MISSING}",None)]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/prefix-brace.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/prefix-brace.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();if let Some(message)=message{assert_eq!(notices.len(),1,"{condition}");assert_eq!(notices[0].message,message,"{condition}");assert!(!expanded.text.as_str().contains("yes"));}else{assert!(notices.is_empty(),"{condition}");assert!(expanded.text.as_str().contains("yes"),"{condition}");}drop(notices);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_single_safe_followers_and_global_terms_never_collapse_to_plain_prefix_value(){for(condition,message)in[("::name","non-constant expression"),("::func(MISSING)","non-constant expression"),("0?.field","non-constant expression follower: 0 Field(SafeDot, \"field\")"),("null?.field","non-constant expression follower: null Field(SafeDot, \"field\")"),("0?:field","non-constant expression follower: 0 Field(SafeColon, \"field\")")]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/safe.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/safe.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1,"{condition}");assert_eq!(notices[0].message,message,"{condition}");assert!(!expanded.text.as_str().contains("disabled"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_template_child_notice_and_malformed_child_match_qualified_order_and_location(){for(condition,expected)in[("\"[input() as unknown_name]\"", &[("bad input type: 'unknown_name'",18),("non-constant expression",1)][..]),("\"[(1]\"", &[("got ']\"', expected one of: operator, field access, ')'",9)][..])]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/template-child.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/template-child.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),expected.len(),"{condition}");for(notice,(message,column))in notices.iter().zip(expected){assert_eq!(notice.message,*message,"{condition}");assert!(matches!(notice.place,super::super::OriginalNoticePlace::Actual{line:1,column:actual,..}if actual==*column),"{condition}");}assert!(!expanded.text.as_str().contains("disabled"));assert!(expanded.text.as_str().contains("after"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

#[test]fn actual_single_safe_missing_member_keeps_both_qualified_notices(){let provider=Memory::new(&[("E:/controller/safe-missing.dme","#if 0?.\n/datum/disabled\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/safe-missing.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),2);assert_eq!(notices[0].message,"got EOF, expected one of: identifier");assert!(matches!(notices[0].place,super::super::OriginalNoticePlace::Actual{line:1,column:6,..}));assert_eq!(notices[1].message,"non-constant expression follower: 0 Field(SafeDot, \"\")");assert!(matches!(notices[1].place,super::super::OriginalNoticePlace::Actual{line:1,column:1,..}));assert!(!expanded.text.as_str().contains("disabled"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}


#[test]fn actual_safe_index_leaf_debug_borrows_real_file_id_and_typed_child_without_folding(){for(condition,message)in[("0?[1]","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Int(1) }, follow: [] })"),("0?[MISSING]","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Ident(\"MISSING\") }, follow: [] })")]{let raw=format!("#if {condition}\n/datum/disabled\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/index-debug.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/index-debug.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1);assert_eq!(notices[0].message,message);assert!(!expanded.text.as_str().contains("disabled"));drop(notices);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}
#[test]fn index_debug_reuses_semantic_file_registration_across_multiple_include_acquisitions(){let provider=Memory::new(&[("E:/controller/index-files.dme","#include \"absent.dm\"\n#include \"child.dm\"\n#include \"child.dm\"\n/datum/after\n"),("E:/controller/child.dm","#pragma multiple\n#if 0?[1]\n/datum/disabled\n#endif\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/index-files.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let messages=plan.original_notices().iter().filter(|row|row.message.starts_with("non-constant expression follower:")).map(|row|row.message).collect::<Vec<_>>();assert_eq!(messages.len(),2);assert_eq!(messages[0],"non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(2), line: 2, column: 8 }, elem: Int(1) }, follow: [] })");assert_eq!(messages[1],messages[0],"semantic FileId2 must not become occurrence3 after a repeated acquisition");assert!(!expanded.text.as_str().contains("disabled"));drop(messages);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

// Qualified actual pinned-library index12 roster: controlled-index-reference-20261103.
// Literal expected strings below are authored DATA, never runtime golden replacement.
#[test]fn actual_index_debug_supported_roster_preserves_typed_children_and_exact_old_messages(){
 for(case,raw,message)in[
("safe_int","#if 0?[1]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Int(1) }, follow: [] })"),
("normal_ident","#if 0[MISSING]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Normal, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 7 }, elem: Ident(\"MISSING\") }, follow: [] })"),
("safe_float","#if 0?[1.5]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Float(1.5) }, follow: [] })"),
("safe_string","#if 0?[\"x\"]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: String(\"x\") }, follow: [] })"),
("safe_null","#if 0?[null]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Null }, follow: [] })"),
("safe_group","#if 0?[(1)]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Expr(Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 9 }, elem: Int(1) }, follow: [] }) }, follow: [] })"),
("safe_binary","#if 0?[1+2]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, BinaryOp { op: Add, lhs: Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Int(1) }, follow: [] }, rhs: Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 10 }, elem: Int(2) }, follow: [] } })"),
("safe_ternary","#if 0?[1?2:3]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, TernaryOp { cond: Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Int(1) }, follow: [] }, if_: Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 10 }, elem: Int(2) }, follow: [] }, else_: Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 12 }, elem: Int(3) }, follow: [] } })"),
("call_child","#if 0?[f(MISSING)]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Call(\"f\", [Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 10 }, elem: Ident(\"MISSING\") }, follow: [] }]) }, follow: [] })"),
("unary_child","#if 0?[-1]\n/datum/yes\n#endif\n/datum/after\n","non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 9 }, elem: Int(1) }, follow: [Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Unary(Neg) }] })")]{let provider=Memory::new(&[("E:/controller/index-roster.dme",raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/index-roster.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let notices=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(notices.len(),1,"{case}");assert_eq!(notices[0].message,message,"{case}");assert!(expanded.text.as_str().contains("after"),"{case}");drop(notices);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"{case}");assert_eq!(work.live.load(Ordering::Acquire),0,"{case}");}
}
#[test]fn actual_index_prefab_debug_borrows_issued_path_components_without_folding(){let provider=Memory::new(&[("E:/controller/index-prefab.dme","#if 0?[/datum]\n/datum/yes\n#endif\n/datum/after\n")]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/index-prefab.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let rows=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(rows.len(),1);assert_eq!(rows[0].message,"non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Prefab(Prefab { path: [(Slash, \"datum\")], vars: [] }) }, follow: [] })");drop(rows);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}

#[test]fn actual_empty_group_and_nameof_use_same_native_null_and_name_products(){for(condition,yes,warning)in[("()",false,true),("nameof(::name)==\"name\"",true,false),("nameof(.datum)==\"datum\"",true,false),("nameof(:datum)==\"datum\"",true,false),("nameof(/datum{})==\"datum\"",true,false)]{let raw=format!("#if {condition}\n/datum/yes\n#endif\n/datum/after\n");let provider=Memory::new(&[("E:/controller/grammar-tail.dme",&raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/grammar-tail.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let rows=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(rows.len(),usize::from(warning),"{condition}");if warning{assert_eq!(rows[0].message,"'()' should be replaced with 'null'");}assert_eq!(expanded.text.as_str().contains("yes"),yes,"{condition}");drop(rows);drop((plan,expanded,primary,binding));assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);}}

// Exact uniquely qualified compound-debug12 library output. No dynamic blessing.
#[test]fn actual_compound_debug_nameof_and_empty_group_match_qualified_source_diagnostics(){
 let cases:&[(&str,&str,&[(&str,usize,usize)])]=&[
("empty_group","#if ()\n/datum/yes\n#endif\n/datum/after\n",&[("'()' should be replaced with 'null'",1,6)][..]),
("index_empty_group","#if 0?[()]\n/datum/yes\n#endif\n/datum/after\n",&[("'()' should be replaced with 'null'",1,9),("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Null }, follow: [] })",1,1)][..]),
("nameof_global","#if nameof(::name)==\"name\"\n/datum/yes\n#endif\n/datum/after\n",&[][..]),
("nameof_dot","#if nameof(.datum)==\"datum\"\n/datum/yes\n#endif\n/datum/after\n",&[][..]),
("nameof_colon","#if nameof(:datum)==\"datum\"\n/datum/yes\n#endif\n/datum/after\n",&[][..]),
("nameof_empty_prefab","#if nameof(/datum{})==\"datum\"\n/datum/yes\n#endif\n/datum/after\n",&[][..]),
("index_prefab","#if 0?[/datum]\n/datum/yes\n#endif\n/datum/after\n",&[("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Prefab(Prefab { path: [(Slash, \"datum\")], vars: [] }) }, follow: [] })",1,1)][..]),
("index_prefab_vars","#if 0?[/datum{a=1}]\n/datum/yes\n#endif\n/datum/after\n",&[("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Prefab(Prefab { path: [(Slash, \"datum\")], vars: [(\"a\", Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 17 }, elem: Int(1) }, follow: [] })] }) }, follow: [] })",1,1)][..]),
("index_member","#if 0?[x.y]\n/datum/yes\n#endif\n/datum/after\n",&[("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Ident(\"x\") }, follow: [Spanned { location: Location { file: FileId(1), line: 1, column: 9 }, elem: Field(Dot, \"y\") }] })",1,1)][..]),
("index_call_follow","#if 0?[f().x]\n/datum/yes\n#endif\n/datum/after\n",&[("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: Call(\"f\", []) }, follow: [Spanned { location: Location { file: FileId(1), line: 1, column: 11 }, elem: Field(Dot, \"x\") }] })",1,1)][..]),
("index_nested","#if 0?[list(1)[1]]\n/datum/yes\n#endif\n/datum/after\n",&[("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: List([Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 13 }, elem: Int(1) }, follow: [] }]) }, follow: [Spanned { location: Location { file: FileId(1), line: 1, column: 15 }, elem: Index(Normal, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 16 }, elem: Int(1) }, follow: [] }) }] })",1,1)][..]),
("index_global","#if 0?[::value]\n/datum/yes\n#endif\n/datum/after\n",&[("non-constant expression follower: 0 Index(Safe, Base { term: Spanned { location: Location { file: FileId(1), line: 1, column: 8 }, elem: GlobalIdent(\"value\") }, follow: [] })",1,1)][..])];
 for &(case,raw,wanted)in cases{let provider=Memory::new(&[("E:/controller/compound-debug.dme",raw)]);let work=Work{live:Arc::new(AtomicUsize::new(0))};let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new("E:/controller/compound-debug.dme"),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap_or_else(|e|panic!("{case}: {e:?}"));let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();let rows=plan.original_notices().iter().collect::<Vec<_>>();assert_eq!(rows.len(),wanted.len(),"{case}");for(row,(message,line,column))in rows.iter().zip(wanted){assert_eq!(row.message,*message,"{case}");assert!(matches!(row.place,super::super::OriginalNoticePlace::Actual{line:l,column:c,..}if l==*line&&c==*column),"{case}: {:?}",row.place);}assert!(expanded.text.as_str().contains("after"),"{case}");drop(rows);drop((plan,expanded,primary,binding));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"{case}");assert_eq!(work.live.load(Ordering::Acquire),0,"{case}");}
}

#[test]
fn real_redefinition_and_undef_restore_only_the_exact_definition_owner() {
    let root = "E:/controller/origin-stack.dme";
    let child = "E:/controller/origin-child.dm";
    let provider = Memory::new(&[
        (root, "#define VALUE 3\n/datum/root\n    var/first = VALUE\n    var/again = VALUE\n#include \"origin-child.dm\"\n#undef VALUE\n/datum/root\n    var/restored = VALUE\n"),
        (child, "#define VALUE 7\n/datum/child\n    var/changed = VALUE\n"),
    ]);
    let work = Work { live: Arc::new(AtomicUsize::new(0)) };
    let syntax = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&syntax, 64 << 20, &|| Ok(()));
    let product = GenerationDirectivePlan::prepare_original_checker_stream_using(
        Path::new(root), &provider, &BTreeMap::new(), omissions(), 1 << 20, &work, &a, &mut Consumer,
    ).unwrap();
    let rows: Vec<_> = product.expanded().origins.iter().filter(|row| {
        row.macro_expansions.get(0).is_some_and(|expansion| expansion.name == "VALUE")
    }).collect();
    let [first, again, changed, restored] = rows.as_slice() else { panic!("expected four actual invocations"); };
    let outer = first.macro_expansions.author_buffers(0).unwrap();
    assert_eq!(again.macro_expansions.author_buffers(0), Some(outer));
    assert!(!first.macro_expansions.same_owner(again.macro_expansions));
    let inner = changed.macro_expansions.author_buffers(0).unwrap();
    assert_eq!(restored.macro_expansions.author_buffers(0), Some(outer));
    assert_ne!(outer, inner);
    assert!(!first.macro_expansions.same_owner(restored.macro_expansions));
    for (row, path) in [(first, root), (again, root), (changed, child), (restored, root)] {
        let definition = row.macro_expansions.get(0).unwrap().definition.unwrap();
        assert_eq!(definition.path.as_path(), Path::new(path));
        assert_eq!(definition.source_line, 1);
    }
    drop(rows);
    drop(product);
    assert_eq!(syntax.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(work.live.load(Ordering::Acquire), 0);
}

#[test]
fn physical_short_line_starts_preserve_macro_definition_after_include_eof() {
    let root = "E:/controller/short-lines.dme";
    let child = "E:/controller/short-lines.dm";
    let child_prefix = "// earlier line\n";
    let define = "#define OLD_VALUE 29\n";
    let child_text = format!("{child_prefix}{define}// later physical line\n");
    let provider = Memory::new(&[
        (root, "#include \"short-lines.dm\"\n/datum/probe\n    var/number = OLD_VALUE\n"),
        (child, &child_text),
    ]);
    let work = Work { live: Arc::new(AtomicUsize::new(0)) };
    let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
    let syntax = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
    let a = SettingAdmission::new(&syntax, 64 << 20, &|| Ok(()));
    let product = GenerationDirectivePlan::prepare_original_checker_stream_using(
        Path::new(root), &provider, &BTreeMap::new(), omissions(), 1 << 20, &work, &a, &mut Consumer,
    ).unwrap();
    let invocation = product.expanded().origins.iter().find(|row| {
        row.macro_expansions.get(0).is_some_and(|entry| entry.name == "OLD_VALUE")
    }).expect("actual expansion after the child frame has returned");
    assert_eq!(invocation.origin.source_line, 3);
    let definition = invocation.macro_expansions.get(0).unwrap().definition.unwrap();
    assert_eq!(definition.path.as_path(), Path::new(child));
    assert_eq!(definition.source_line, 2);
    let start = child_prefix.len() + "#define ".len();
    assert_eq!(definition.source_span, dm_syntax::Span::new(start, start + "OLD_VALUE".len()));
    assert!(product.expanded().text.as_str().contains("29"));
    assert_eq!(provider.opened.lock().unwrap().as_slice(), [PathBuf::from(root), PathBuf::from(child)]);
    drop(product);
    assert_eq!(syntax.load(Ordering::Acquire), fixed);
    assert_eq!(work.live.load(Ordering::Acquire), 0);
}

#[test]
fn real_nested_macro_tokens_share_their_exact_projection_across_one_invocation() {
    let provider = Memory::new(&[(
        "E:/controller/trace-pair.dme",
        "#define OUTER INNER\n#define INNER 1 + 2\n/datum/probe\n    var/a = OUTER\n    var/b = OUTER\n",
    )]);
    let work = Work { live: Arc::new(AtomicUsize::new(0)) };
    let syntax = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&syntax, 64 << 20, &|| Ok(()));
    let product = GenerationDirectivePlan::prepare_original_checker_stream_using(
        Path::new("E:/controller/trace-pair.dme"), &provider, &BTreeMap::new(),
        omissions(), 1 << 20, &work, &a, &mut Consumer,
    ).unwrap();
    let first: Vec<_> = product.expanded().origins.iter().filter(|row| {
        row.origin.source_line == 4 && row.macro_expansions.len() == 2
    }).collect();
    let second: Vec<_> = product.expanded().origins.iter().filter(|row| {
        row.origin.source_line == 5 && row.macro_expansions.len() == 2
    }).collect();
    assert!(first.len() >= 3 && second.len() >= 3);
    assert!(first.iter().all(|row| row.macro_expansions.same_owner(first[0].macro_expansions)));
    assert!(second.iter().all(|row| row.macro_expansions.same_owner(second[0].macro_expansions)));
    assert!(!first[0].macro_expansions.same_owner(second[0].macro_expansions));
    for at in 0..2 {
        let left = first[0].macro_expansions.author_buffers(at).unwrap();
        let right = second[0].macro_expansions.author_buffers(at).unwrap();
        assert_eq!(left, right, "one definition owner across separate invocation owners");
    }
    assert_ne!(first[0].macro_expansions.author_buffers(0), first[0].macro_expansions.author_buffers(1));
    assert_eq!(first[0].macro_expansions.get(1).unwrap().replacement_chain.get(0).unwrap(), "OUTER");
    drop((first, second));
    drop(product);
    assert_eq!(syntax.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(work.live.load(Ordering::Acquire), 0);
}


#[test]
fn actual_original_numeric_tokens_reuse_payload_without_collapsing_occurrence_positions(){
 let source="/datum/repeated_numbers\n    var/a = 7\n    var/b = 7\n    var/c = 7.0\n    var/d = 7.0\n";
 let project="E:/controller/repeated-numbers.dme";
 let provider=Memory::new(&[(project,source)]);
 let work=Work{live:Arc::new(AtomicUsize::new(0))};
 let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
 let a=SettingAdmission::new(&used,16<<20,&||Ok(()));
 let product=GenerationDirectivePlan::prepare_original_checker_stream_using(Path::new(project),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer).unwrap();
 let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();
 let view=binding.checked_view(&expanded.text,dm_syntax::Span::new(0,expanded.text.len()),&binding,&a).unwrap();
 let issued=view.checked_facts(&expanded.text).unwrap();
 let (facts,origin)=issued.raw_parts();
 assert_eq!(origin,0);
 assert_eq!(facts.len(),4);
 for pair in [0..2,2..4] {
  let (first_span,first)=facts.get(pair.start).unwrap();
  let (second_span,second)=facts.get(pair.start+1).unwrap();
  assert!(first_span.end<second_span.start);
  assert!(first.equal_data(second).unwrap());
  assert!(!first.same_owner(second));
  assert_eq!(first.raw_storage().unwrap().as_ptr(),second.raw_storage().unwrap().as_ptr());
  for span in [first_span,second_span]{
   assert_eq!(expanded.text.as_str().get(span.range()),Some(first.raw().unwrap()));
   let ordinal=expanded.origins.partition_point(|row|row.output_span.start<span.start);
   let (_,point,_,_,_)=expanded.origins.original_raw_point_geometry(ordinal).unwrap();
   let raw_source_line=source.lines().nth(point.line-1).unwrap();
   assert_eq!(raw_source_line.get(point.byte_column-1..),Some(first.raw().unwrap()));
  }
 }
 assert!(matches!(facts.get(0).unwrap().1.value().unwrap(),dm_syntax::OriginalTokenValue::Int(7)));
 assert!(matches!(facts.get(2).unwrap().1.value().unwrap(),dm_syntax::OriginalTokenValue::Float(value) if value.to_bits()==7.0f32.to_bits()));
 drop(issued);
 drop(view);
 drop((plan,expanded,primary,binding));
 assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 assert_eq!(work.live.load(Ordering::Acquire),0);
}

#[test]
fn actual_repeated_static_original_tokens_retain_distinct_issued_positions() {
 let source=concat!("/datum/repeated_static\n",
  "    var/a = \"same string\"\n", "    var/b = \"same string\"\n",
  "    var/c = 'icons/test.dmi'\n", "    var/d = 'icons/test.dmi'\n");
 let project="E:/controller/repeated-static.dme";
 let provider=Memory::new(&[(project,source)]);
 let work=Work{live:Arc::new(AtomicUsize::new(0))};
 let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
 let a=SettingAdmission::new(&used,16<<20,&||Ok(()));
 let product=GenerationDirectivePlan::prepare_original_checker_stream_using(
  Path::new(project),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer,
 ).unwrap();
 let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();
 let view=binding.checked_view(&expanded.text,dm_syntax::Span::new(0,expanded.text.len()),&binding,&a).unwrap();
 let issued=view.checked_facts(&expanded.text).unwrap();
 let (facts,origin)=issued.raw_parts();
 assert_eq!(origin,0);
 assert_eq!(facts.len(),4);
 for index in 0..2 {
  let (first_span,first)=facts.get(index*2).unwrap();
  let (second_span,second)=facts.get(index*2+1).unwrap();
  assert!(first_span.end<second_span.start);
  assert!(first.equal_data(second).unwrap());
  assert!(!first.same_owner(second));
  assert_eq!(first.raw().unwrap().as_ptr(),second.raw().unwrap().as_ptr());
  for (n, span) in [first_span,second_span].into_iter().enumerate() {
   assert_eq!(expanded.text.as_str().get(span.range()),Some(first.raw().unwrap()));
   let ordinal=expanded.origins.partition_point(|row|row.output_span.start<span.start);
   let (_,point,_,_,_)=expanded.origins.original_raw_point_geometry(ordinal).unwrap();
   assert_eq!(point.line,2+index*2+n);
   let raw_line=source.lines().nth(point.line-1).unwrap();
   assert_eq!(raw_line.get(point.byte_column-1..),Some(first.raw().unwrap()));
  }
 }
 assert_eq!(facts.get(0).unwrap().1.string_mode(),dm_syntax::OriginalStringMode::Normal);
 assert!(matches!(facts.get(0).unwrap().1.value().unwrap(),dm_syntax::OriginalTokenValue::String("same string")));
 assert!(matches!(facts.get(2).unwrap().1.value().unwrap(),dm_syntax::OriginalTokenValue::Resource("icons/test.dmi")));
 drop(issued);
 drop(view);
 drop((plan,expanded,primary,binding));
 assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 assert_eq!(work.live.load(Ordering::Acquire),0);
}

#[test]
fn actual_original_literal_fact_pages_keep_exact_source_owner_across_boundary() {
 let source=format!("/datum/literal_page
{}", "    var/value = 12
".repeat(260));
 let project="E:/controller/literal-page.dme";
 let provider=Memory::new(&[(project,&source)]);
 let work=Work{live:Arc::new(AtomicUsize::new(0))};
 let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
 let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
 let product=GenerationDirectivePlan::prepare_original_checker_stream_using(
  Path::new(project),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,&mut Consumer,
 ).unwrap();
 let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();
 let full=binding.checked_view(&expanded.text,dm_syntax::Span::new(0,expanded.text.len()),&binding,&a).unwrap();
 let (all,_)=full.checked_facts(&expanded.text).unwrap().raw_parts();
 assert_eq!(all.len(),260);
 let before=all.get(255).unwrap();
 let after=all.get(256).unwrap();
 assert!(!before.1.same_owner(after.1));
 let window=dm_syntax::Span::new(before.0.start,after.0.end);
 let exact=expanded.text.checked_view(window.range()).unwrap();
 let clipped=binding.checked_view(&exact,window,&binding,&a).unwrap();
 let (rows,origin)=clipped.checked_facts(&exact).unwrap().raw_parts();
 assert_eq!(origin,window.start);
 assert_eq!(rows.len(),2);
 assert!(rows.get(0).unwrap().1.same_owner(before.1));
 assert!(rows.get(1).unwrap().1.same_owner(after.1));
 let foreign=crate::SourceText::from(exact.as_str().to_owned());
 assert!(clipped.checked_facts(&foreign).is_err());
 drop((clipped,full,exact,plan,expanded,primary,binding));
 assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 assert_eq!(work.live.load(Ordering::Acquire),0);
}

#[test]
fn actual_analyze_batches_share_full_physical_pages_and_trim_receiver_stop() {
    struct Host(Arc<dm_syntax::SettingChargeCounter>);
    impl super::super::OriginalBatchSyntaxHost for Host {
        fn with_producer_admission(&self, run:&mut dyn FnMut(&SettingAdmission<'_>)->io::Result<()>) -> io::Result<()> {
            run(&SettingAdmission::new(&self.0,64<<20,&||Ok(())))
        }
    }
    struct Stream{committed:bool,stop:bool}
    impl OriginalDeclarationHeaderObserver for Stream {
        fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}
    }
    impl OriginalPrimaryStreamConsumer for Stream {
        fn retains_committed_items(&self)->bool{self.committed}
        fn callable(&mut self,_:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)
            ->io::Result<OriginalHeaderFlow>{
            if self.stop{return Ok(OriginalHeaderFlow::Stop)}
            assert_eq!(source.next_header_token()?.ok_or(io::ErrorKind::UnexpectedEof)?.text,")");
            Ok(OriginalHeaderFlow::Continue)
        }
    }
    use std::fmt::Write;
    let mut text=String::new();
    for index in 0..1000 {writeln!(text,"/datum/preceding_{index}").unwrap();}
    text.push_str("/proc/stop_here()
    return 7
");
    for index in 0..2000 {writeln!(text,"/datum/unread_{index}").unwrap();}
    let root="E:/controller/batch-shared-geometry.dme";
    for (committed,stop) in [(true,false),(true,true),(false,false)] {
        let provider=Memory::new(&[(root,&text)]);
        let work=Work{live:Arc::new(AtomicUsize::new(0))};
        let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a=SettingAdmission::new(&syntax,64<<20,&||Ok(()));
        let host=Host(syntax.clone());
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let batch=OriginalBatchExecution::new(&provider,&host,&executor);
        let product=GenerationDirectivePlan::prepare_original_stream_using(
            Path::new(root),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch),
            &mut Stream{committed,stop},
        ).unwrap();
        let verified=product.token_projection.as_ref().unwrap();
        assert_eq!(verified.eof,!stop);
        assert!(verified.rows>dm_syntax::ORIGINAL_TOKEN_PAGE_ROWS);
        assert_eq!(product.expanded().text.as_str().contains("unread_1999"),!stop);
        let mut origin_addresses=std::collections::BTreeSet::new();
        let narrow_bytes=4*dm_syntax::ORIGINAL_TOKEN_PAGE_ROWS;
        product.expanded().origins.visit_storage(|address,_,capacity|{
            if capacity==narrow_bytes {origin_addresses.insert(address);}
        });
        let mut aliased=0;
        product.expanded().tokens.shared().unwrap().visit_storage(|address,_,capacity|{
            if capacity==narrow_bytes&&origin_addresses.contains(&address){aliased+=1;}
        });
        assert_eq!(aliased,if committed{verified.rows/dm_syntax::ORIGINAL_TOKEN_PAGE_ROWS}else{0});
        drop(product);
        assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
        assert_eq!(work.live.load(Ordering::Acquire),0);
    }
}

#[test]
fn actual_body_projection_releases_only_diagnostic_standalones_and_detaches_without_source() {
 use std::fmt::Write;
 struct Body;
 impl OriginalDeclarationHeaderObserver for Body{
  fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}
 }
 impl OriginalPrimaryStreamConsumer for Body{
  fn retains_committed_items(&self)->bool{true}
  fn callable(&mut self,_:OriginalPrimaryLiveHeader,source:&mut dyn super::super::OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
   loop{if source.next_header_token()?.ok_or(io::ErrorKind::UnexpectedEof)?.text==")"{break}}Ok(OriginalHeaderFlow::Continue)
  }
 }
 struct Host(Arc<dm_syntax::SettingChargeCounter>);
 impl super::super::OriginalBatchSyntaxHost for Host{
  fn with_producer_admission(&self,run:&mut dyn FnMut(&SettingAdmission<'_>)->io::Result<()>)->io::Result<()>{run(&SettingAdmission::new(&self.0,64<<20,&||Ok(())))}
 }
 let project="E:/controller/body-projection.dme";
 let mut source=format!("/datum/header\n    var/static/label = \"{}\"\n/proc/p(arg=\"{}\")\n    return \"escaped\\ntext\"\n","header".repeat(250),"formal".repeat(250));
 // Exceeds real batch packing's 1024-byte bound: this exercises true unique
 // standalone payload release, not reference-weighted shared-page estimates.
 for n in 0..300{writeln!(source,"    return \"{}-{n}\"","x".repeat(1100)).unwrap();}
 source.push_str("/datum/after_body\n");
 let mut full_escaped_value = None;
 for (diagnostic,batches)in [(false,true),(true,false),(true,true)]{
  let provider=Memory::new(&[(project,&source)]);
  let work=Work{live:Arc::new(AtomicUsize::new(0))};
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,64<<20,&||Ok(()));
  let host=Host(used.clone());let executor=dm_exec::BuildExecutor::new(1).unwrap();let batch=OriginalBatchExecution::new(&provider,&host,&executor);
  let product=if diagnostic{
   GenerationDirectivePlan::prepare_original_diagnostic_stream_using(Path::new(project),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,batches.then_some(&batch),&mut Body)
  }else{
   GenerationDirectivePlan::prepare_original_stream_using(Path::new(project),&provider,&BTreeMap::new(),omissions(),1<<20,&work,&a,Some(&batch),&mut Body)
  }.unwrap();
  let(plan,expanded,primary,binding)=product.into_diagnostic_parts_using(&a).unwrap();
  let weak=expanded.text.downgrade();
  let view=binding.checked_view(&expanded.text,dm_syntax::Span::new(0,expanded.text.len()),&binding,&a).unwrap();
  let facts=view.checked_facts(&expanded.text).unwrap();let(rows,_)=facts.raw_parts();assert_eq!(rows.len(),303);
  let projected=rows.iter().filter(|(_,data)|data.is_projected()).count();
  assert_eq!(projected,if diagnostic{253}else{0},"only complete BODY pages in actual diagnostic recipe");
  for at in 0..3{assert!(!rows.get(at).unwrap().1.is_projected(),"header/formal/escaped DATA stays owned")}
  let dm_syntax::OriginalTokenValue::String(escaped_value) = rows.get(2).unwrap().1.value().unwrap() else {
   panic!("escaped source must remain an Original string");
  };
  if diagnostic {
   assert_eq!(Some(escaped_value), full_escaped_value.as_deref());
  } else {
   full_escaped_value = Some(escaped_value.to_owned());
  }
  assert!(!rows.get(302).unwrap().1.is_projected(),"unfinished BODY page remains full");
  let(span,first)=rows.get(3).unwrap();let raw=first.raw().unwrap();
  assert_eq!(raw.as_ptr(),if diagnostic{expanded.text.as_str()[span.range()].as_ptr()}else{first.raw().unwrap().as_ptr()});
  if diagnostic{assert_eq!(first.raw_storage().unwrap().capacity(),0)}
  let clipped_source=expanded.text.checked_view(span.range()).unwrap();
  let clipped=binding.checked_view(&clipped_source,span,&binding,&a).unwrap();
  let clipped_facts=clipped.checked_facts(&clipped_source).unwrap();let clipped_first=clipped_facts.raw_parts().0.get(0).unwrap().1;
  assert!(first.same_owner(clipped_first));assert_eq!(first.raw().unwrap(),clipped_first.raw().unwrap());
  let foreign:crate::SourceText=expanded.text.as_str().to_owned().into();
  assert_eq!(view.checked_facts(&foreign).err().unwrap().kind(),io::ErrorKind::InvalidInput);
  let before=used.load(Ordering::Acquire);
  if diagnostic{
   let denied=SettingAdmission::new(&used,before,&||Ok(()));
   assert_eq!(first.detach_using(&denied).err().unwrap().kind(),io::ErrorKind::OutOfMemory);
   assert_eq!(used.load(Ordering::Acquire),before,"denial must destroy raw scratch before returning its credit");
   let failing=SettingAdmission::new(&used,64<<20,&||Err(io::Error::from_raw_os_error(1450)));
   assert_eq!(first.detach_using(&failing).err().unwrap().raw_os_error(),Some(1450));
   assert_eq!(used.load(Ordering::Acquire),before);
  }
  // The public AST literal constructor exercises actual paid local spelling
  // adoption. The resulting literal owns no whole-source or fact-roster root.
  let detached=first.detach_using(&a).unwrap();
  let after_detach=used.load(Ordering::Acquire);
  let literal=dm_syntax::LiteralText::from_original_data(&detached,span.start,&a).unwrap();
  assert_eq!(used.load(Ordering::Acquire),after_detach,"owned detach is an immutable alias, not a second spelling copy");
  assert_eq!(literal.as_str(),raw);
  assert!(matches!(literal.original_value(),Some(dm_syntax::OriginalTokenValue::String(value))if value.starts_with("xxx")));
  if diagnostic{assert!(detached.as_view().same_owner(first));assert_ne!(detached.raw().as_ptr(),raw.as_ptr())}
  drop((clipped_facts,facts));drop((clipped,clipped_source,view,foreign));
  drop((plan,expanded,primary,binding));
  assert!(weak.upgrade().is_none(),"detached AST cannot retain its complete source");
  assert!(literal.as_str().ends_with("-0\""));
  drop((literal,detached,weak));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.live.load(Ordering::Acquire),0);
 }
}
