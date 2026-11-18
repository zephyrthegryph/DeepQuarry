//! Real native frontend aliases and same-counter BODY pressure through public contracts.
use std::{sync::Arc,path::Path};
use dm_preprocess::{SourceProvider,SourceText,SourceAcquisitionLease,source_arena_credit::SourceArenaWork};
use dmbc::{query_db::QueryDb,input_snapshot::{RecordingInputs,FileSystemInputs}};
use dm_tree::frontend::{self,BodySyntaxQueries,SettingExpressionQueries,BodySyntaxFailure};
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
const EXISTING_SYNTAX_LIMIT:usize=128*1024*1024;
fn used(db:&QueryDb)->usize{
 // Probe the existing non-sticky optimization grant, without allocating
 // payloads or exposing private counters/debug-only APIs. Each lease is
 // physically dropped before the next probe on this single owned QueryDb.
 let mut bytes=0;db.with_original_header_admission(&mut|a|{
  let(mut lo,mut hi)=(0usize,EXISTING_SYNTAX_LIMIT);
  while lo<hi{let mid=lo+(hi-lo)/2+1;match a.try_reserve_optimization(mid).map_err(BodySyntaxFailure::Operational)?{
   Some(lease)=>{drop(lease);lo=mid;},None=>hi=mid-1,
  }}bytes=EXISTING_SYNTAX_LIMIT-lo;Ok(())
 }).unwrap();bytes
}
fn reserve(db:&QueryDb,bytes:usize)->dm_syntax::SettingRootLease{
 let mut lease=None;db.with_original_header_admission(&mut|a|{
  lease=Some(a.reserve(bytes).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?);Ok(())
 }).unwrap();lease.unwrap()
}
struct Source(RecordingInputs<FileSystemInputs>);
impl SourceProvider for Source{
 fn original_batch_source(&self)->std::io::Result<Option<&(dyn SourceProvider+Sync)>>{Ok(Some(self))}
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.0.initial_environment()}
 fn read(&self,p:&Path)->Result<String,String>{SourceProvider::read(&self.0,p)}
 fn acquired_source(&self,p:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{SourceProvider::acquired_source(&self.0,p)}
 fn source_acquisition(&self,p:&Path,t:&SourceText)->Option<dm_preprocess::AcquiredSource>{SourceProvider::source_acquisition(&self.0,p,t)}
 fn path_presence_admitted(&self,p:&Path,w:&dyn SourceArenaWork)->std::io::Result<bool>{self.0.path_presence_admitted(p,w)}
 fn original_raw_source_open_admitted(&self,p:&Path,max:usize,w:&dyn SourceArenaWork,after:&mut dyn FnMut()->std::io::Result<dm_preprocess::OriginalRawOpenDecision>,before:&mut dyn FnMut(usize)->std::io::Result<()>,decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->std::io::Result<()>,acquired:&mut dyn FnMut(&SourceAcquisitionLease)->std::io::Result<()>)->std::io::Result<dm_preprocess::OriginalRawReadOutcome>{self.0.original_raw_source_open_admitted(p,max,w,after,before,decode,acquired)}
 fn original_source_bytes<'a>(&'a self,l:&'a SourceAcquisitionLease)->std::io::Result<Option<&'a[u8]>>{self.0.original_source_bytes(l)}
}
#[test]
fn actual_body_pressure_prunes_only_retired_original_signature_grants(){
 let db=Arc::new(QueryDb::default());let root=scratch::dir("body-pressure-retired-signatures");
 let project=root.join("old.dme");std::fs::write(&project,br#"/datum/old
    var/value=1
/proc/old(argument=1)
    return argument
"#).unwrap();
 let recording=RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
 let source=Source(recording);
 let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;
 let old=frontend::build_for_checker_diagnostics_with_state_checked(&project,&source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&settings).unwrap();
 let live_tree=Arc::clone(old.source_view().unwrap().tree());drop(old);
 let current_project=root.join("current.dme");std::fs::write(&current_project,br#"/proc/current()
    return 1
"#).unwrap();
 let current_source=Source(RecordingInputs::new(FileSystemInputs,0));
 let current=frontend::build(&current_project,&current_source,&Default::default(),1).unwrap().with_body_queries(Arc::clone(&db)as Arc<dyn BodySyntaxQueries>);
 let archive=current.body_archive().unwrap();let input=&archive.syntax_inputs().unwrap()[0];
 db.prepare_checked_input(input).unwrap();let before=used(&db);
 let held=reserve(&db,EXISTING_SYNTAX_LIMIT-before-64*1024);let live=used(&db);db.prepare_checked_input(input).unwrap();
 assert_eq!(used(&db),live,"a real detached tree keeps its original signature grants");
 drop(live_tree);let retired=used(&db);assert!(retired<=live,"tree storage can retire before its weak census");
 let tree_release=live-retired;let tail=reserve(&db,tree_release);let before_prune=used(&db);assert_eq!(before_prune,live);
 db.prepare_checked_input(input).unwrap();let after=used(&db);
 assert!(after<before_prune,"BODY pressure must reclaim dead signature owners before the next parse");
 assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0,"resource pruning is not a syntax query");
 drop(held);drop(tail);assert_eq!(used(&db),before-tree_release-(before_prune-after));
 assert!(db.syntax_checked(input).is_ok(),"same real input still parses after reclaiming only retired owners");
}
