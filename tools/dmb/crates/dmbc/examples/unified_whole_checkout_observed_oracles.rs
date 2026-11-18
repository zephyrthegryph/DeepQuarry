//! Held qualification harness. Each external oracle runs inside the actual native observation.
//! No source/generator writes, defaults, parity flags or separate semantic frontend are added.
use dmbc::{runner_host::{BuildHost,FullRegistryCheckOptions},request::{BuildRequest,Command},
 policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest},GeneratorName};
use std::{error::Error,fs::{self,File,OpenOptions},io::{self,Read,Write},path::{Path,PathBuf},
 process::{Child,Command as Process,Stdio},time::{Duration,Instant}};
use sha2::{Digest,Sha256};
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
const ORACLE:&str="77ae3e3e8b7667527873fa84e4ebc460260c40d280e08a12366ec38be0e880e2";
const CHECKER_ORACLE:&str="bafd54168a539e61d8c3f71d9778e92de76d7ffbf11c693541e10be10c9633ba";
const BOUND:u64=64*1024*1024;
// Actual ordinary legacy registry/report order; Declare registers IDs before Declare.
const NAMES:[&str;12]=["actions","auto_tracked","declare_ids","declare","deps","derived_reads","plans","reads","stats","system_accessors","tracked_lists","ui_types"];
const ROOTS:[&str;6]=["code","doc/rewrite","interface","maps","modular_chomp","tgui"];
fn invalid(message:impl Into<String>)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message.into())}
fn new(path:&Path)->io::Result<File>{OpenOptions::new().create_new(true).write(true).open(path)}
fn json(path:&Path,value:&impl serde::Serialize)->io::Result<()>{let mut file=new(path)?;serde_json::to_writer(&mut file,value).map_err(io::Error::from)?;file.write_all(b"\n")}
fn hash(path:&Path)->io::Result<String>{let mut file=File::open(path)?;let mut hasher=Sha256::new();let mut block=[0u8;8192];loop{dmbc::daemon::control::checkpoint()?;let n=file.read(&mut block)?;if n==0{break}hasher.update(&block[..n]);}Ok(format!("{:x}",hasher.finalize()))}
fn read_json(path:&Path)->io::Result<serde_json::Value>{if fs::metadata(path)?.len()>BOUND{return Err(io::ErrorKind::OutOfMemory.into())}serde_json::from_reader(File::open(path)?).map_err(io::Error::from)}
fn reference_for_mode(mode:&str)->io::Result<&'static str>{match mode{"raw"|"ci"|"gen"=>Ok(ORACLE),"checker"=>Ok(CHECKER_ORACLE),_=>Err(invalid("mode must be raw, ci, gen or checker"))}}
fn require_oracle(path:&Path,expected:&str)->io::Result<()>{if hash(path)?!=expected{return Err(invalid("independent oracle image differs from the exact selected frozen reference"))}Ok(())}
struct OwnedChild(Child);impl Drop for OwnedChild{fn drop(&mut self){if !matches!(self.0.try_wait(),Ok(Some(_))){let _=self.0.kill();let _=self.0.wait();}}}
fn oracle(exe:&Path,root:&Path,run:&Path,label:&str,args:&[String],deadline:Instant,expected:&str)->io::Result<()>{
 dmbc::daemon::control::checkpoint()?;if Instant::now()>=deadline{return Err(io::Error::new(io::ErrorKind::Interrupted,"original observation deadline exhausted before oracle"))}require_oracle(exe,expected)?;
 let cache=run.join(format!("{label}-cache"));fs::create_dir(&cache)?;
 let stdout=run.join(format!("{label}.stdout"));let stderr=run.join(format!("{label}.stderr"));
 let mut command=Process::new(exe);command.args(args).current_dir(root).stdin(Stdio::null()).stdout(Stdio::from(new(&stdout)?)).stderr(Stdio::from(new(&stderr)?));
 command.env("DQ_ANALYZE_CACHE",&cache).env("DQ_ANALYZE_SHARED_CACHE","off").env("DQ_MODEL_STORE","off").env("DQ_GEN_STORE","off").env("RAYON_NUM_THREADS","2").env("RUST_TEST_THREADS","1").env("TEMP",run).env("TMP",run);
 for key in ["DQ_ALLOW_USAGE","DQ_ANALYZE_TRACE","DQ_PREWARM","DQ_MODEL_VERIFY","DQ_ANALYZE_TIMING"]{command.env_remove(key);}
 #[cfg(windows)]{use std::os::windows::process::CommandExt;command.creation_flags(0x08000000|0x00004000);}
 let mut child=OwnedChild(command.spawn()?);
 let status=loop{dmbc::daemon::control::checkpoint()?;if Instant::now()>=deadline{return Err(io::Error::new(io::ErrorKind::Interrupted,"oracle exceeded actual original observation deadline"))}
  if fs::metadata(&stdout)?.len()>BOUND||fs::metadata(&stderr)?.len()>BOUND{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"oracle stream exceeded qualification bound"))}
  if let Some(status)=child.0.try_wait()?{break status}std::thread::sleep(Duration::from_millis(25));};
 if fs::metadata(&stdout)?.len()>BOUND||fs::metadata(&stderr)?.len()>BOUND{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"completed oracle stream exceeded qualification bound"))}require_oracle(exe,expected)?;dmbc::daemon::control::checkpoint()?;
 json(&run.join(format!("{label}.invocation.json")),&serde_json::json!({"executable":exe,"sha256":expected,"arguments":args,"status":status.code(),"stdout":stdout,"stderr":stderr,"ran_inside_actual_observation":true,"matching_memory_quota_claim":false}))
}
fn request(root:&Path,cache:&Path,generation:bool)->Result<BuildRequest,Box<dyn Error>>{
 let Command::Build(build)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()])?else{return Err(invalid("actual prepare request parser returned another command").into())};
 let mut build=*build;build.no_cache=true;build.exact_inputs=true;build.progress_enabled=false;build.workers=1;build.timeout_seconds=Some(300);build.engine_template=None;build.bootstrap_catalog=false;build.cache_root=Some(cache.to_owned());
 let workspace_generators=if generation{vec![GeneratorName::Actions,GeneratorName::AutoTracked,GeneratorName::Declare,GeneratorName::DeclareIds,GeneratorName::Deps,GeneratorName::DerivedReads,GeneratorName::Plans,GeneratorName::Reads,GeneratorName::Stats,GeneratorName::SystemAccessors,GeneratorName::TrackedLists,GeneratorName::UiTypes]}else{Vec::new()};
 build.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.to_owned(),recursive_roots:if generation{vec![root.join("code")]}else{ROOTS.map(|p|root.join(p)).to_vec()},configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_generators,..Default::default()});Ok(build)
}
fn copy_target(path:&Path,destination:&Path,expected:u64,wanted:&str,remaining:&mut u64)->io::Result<()>{
 if expected>*remaining{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"target archive aggregate exceeds held qualification bound"))}
 let mut source=File::open(path)?;let mut target=new(destination)?;let mut hash=xxhash_rust::xxh3::Xxh3::new();let mut total=0u64;let mut block=[0u8;8192];loop{dmbc::daemon::control::checkpoint()?;let n=source.read(&mut block)?;if n==0{break}total=total.checked_add(n as u64).filter(|n|*n<=expected).ok_or_else(||invalid("observed target grew"))?;hash.update(&block[..n]);target.write_all(&block[..n])?;}
 if total!=expected||format!("{:032x}",hash.digest128())!=wanted{return Err(invalid("physical target differs from actual retained preimage proof"))}*remaining-=total;Ok(())
}
fn seal_files(out:&Path,known:&mut std::collections::BTreeMap<String,String>,skip_delivery:bool)->io::Result<()>{
 for entry in fs::read_dir(out)?{let entry=entry?;if !entry.file_type()?.is_file(){continue}let name=entry.file_name().into_string().map_err(|_|invalid("nonUTF8 private artifact name"))?;if skip_delivery&&matches!(name.as_str(),"native-analyze.stdout"|"native-analyze.stderr"){continue}let current=hash(&entry.path())?;if known.get(&name).is_some_and(|old|old!=&current){return Err(invalid(format!("provisional observation artifact changed: {name}")))}known.insert(name,current);}
 Ok(())
}
fn verify_stream(path:&Path,seal:&serde_json::Value)->io::Result<()>{let mut file=File::open(path)?;let mut hash=xxhash_rust::xxh3::Xxh3::new();let mut length=0u64;let mut block=[0u8;8192];loop{let n=file.read(&mut block)?;if n==0{break}length+=n as u64;hash.update(&block[..n]);}if seal["length"].as_u64()!=Some(length)||seal["hash"].as_str()!=Some(format!("{:032x}",hash.digest128()).as_str()){return Err(invalid("actual delivered stream does not match its native frame seal"))}Ok(())}

// Two legitimate requests on ONE host. no_cache disables disk/result shortcuts;
// it does not clear the retained QueryDb or native source/semantic owners.
// Neither the warm frame nor these artifact hashes authorize the second input:
// that request still captures and validates its own complete actual ledger.

// InputSnapshot's SAME compact Serialize codec emits scanned_ns first, then
// every actual fact domain in stable BTree order (input_snapshot.rs). Ignore
// ONLY that observation-clock scalar; compare all remaining encoded fact bytes
// without decoding a second all-file map or treating serialized DATA as proof.
fn skip_snapshot_clock(reader:&mut impl io::BufRead)->io::Result<()>{
 const PREFIX:&[u8]=b"{\"scanned_ns\":";let mut actual=[0u8;14];
 reader.read_exact(&mut actual[..PREFIX.len()])?;if &actual[..PREFIX.len()]!=PREFIX{return Err(invalid("actual snapshot codec no longer starts with scanned_ns"))}
 let mut digits=0usize;loop{let mut byte=[0u8;1];reader.read_exact(&mut byte)?;if byte[0]==b','&&digits!=0{return Ok(())}if !byte[0].is_ascii_digit(){return Err(invalid("actual snapshot scanned_ns is not its serialized integer"))}digits+=1;if digits>39{return Err(invalid("actual snapshot clock overflows u128 encoding"))}}
}
fn require_same_input_facts(a:&mut impl io::BufRead,b:&mut impl io::BufRead)->io::Result<()>{
 skip_snapshot_clock(a)?;skip_snapshot_clock(b)?;
 loop{dmbc::daemon::control::checkpoint()?;let left=a.fill_buf()?;let right=b.fill_buf()?;if left.is_empty()||right.is_empty(){return if left.is_empty()&&right.is_empty(){Ok(())}else{Err(invalid("warmup and current native snapshot fact lengths differ"))}}
  let n=left.len().min(right.len());if left[..n]!=right[..n]{return Err(invalid("warmup and current native source/config/discovery facts differ; reference not started"))}a.consume(n);b.consume(n);
 }
}
fn actual_frame(header:&serde_json::Value,name:&str)->io::Result<dq_analyze::selected_exclusions_wire::Frame>{serde_json::from_value(header["binding"][name].clone()).map_err(io::Error::from)}
struct CheckerWarmup{directory:PathBuf,header:serde_json::Value,artifacts:std::collections::BTreeMap<String,String>}
impl CheckerWarmup{
 fn require_seals(&self)->io::Result<()>{for(name,wanted)in &self.artifacts{if hash(&self.directory.join(name))?!=*wanted{return Err(invalid("actual Checker warmup artifact changed"))}}Ok(())}
 fn require_same_frames(&self,header:&serde_json::Value)->io::Result<()>{
  self.require_seals()?;
  // These wire frames contain ONLY semantic/source/policy revision scalars,
  // not request nonce, pointer identity or recorder epoch.
  for name in["frame","checker_frame"]{if actual_frame(&self.header,name)?!=actual_frame(header,name)?{return Err(invalid("native source or Checker frame changed after same-host warmup; reference not started"))}}
  if self.header["project"]!=header["project"]{return Err(invalid("observed native project changed after warmup"))}
  Ok(())
 }
}
fn warm_checker_host(host:&mut BuildHost,root:&Path,cache:&Path,out:&Path)->Result<CheckerWarmup,Box<dyn Error>>{
 let directory=out.join("native-warmup");fs::create_dir(&directory)?;
 let started=Instant::now();let(mut diagnostics,mut report)=(new(&directory.join("native-analyze.stderr"))?,new(&directory.join("native-analyze.stdout"))?);
 let mut callback=false;let clean=host.write_full_registry_check_with_input_observation(request(root,cache,false)?,FullRegistryCheckOptions{raw:true,ci:false,unused:true,..Default::default()},|observation|{
  callback=true;observation.write_inputs(&mut new(&directory.join("report-header.json"))?,&mut new(&directory.join("combined-preparation-inputs.json"))?,&mut new(&directory.join("native-checker.json"))?)
 },&mut diagnostics,&mut report)?;drop((diagnostics,report));
 if !callback{return Err(invalid("actual native warmup observation did not run").into())}
 let header=read_json(&directory.join("report-header.json"))?;verify_stream(&directory.join("native-analyze.stdout"),&header["binding"]["report"])?;verify_stream(&directory.join("native-checker.json"),&header["binding"]["checker"])?;
 let diagnostic=&header["binding"]["diagnostics"];if diagnostic.is_null(){if fs::metadata(directory.join("native-analyze.stderr"))?.len()!=0{return Err(invalid("unsealed warmup diagnostics").into())}}else{verify_stream(&directory.join("native-analyze.stderr"),diagnostic)?}
 let mut artifacts=std::collections::BTreeMap::new();seal_files(&directory,&mut artifacts,false)?;
 json(&out.join("native-warmup-summary.json"),&serde_json::json!({"completed":true,"same_build_host":true,"original_request_seconds":300,"reference_invocations":0,"elapsed_seconds":started.elapsed().as_secs_f64(),"clean":clean,"artifacts_sha256":artifacts,"claim":"actual closed warmup request; no standalone oracle and no source authority for the later request"}))?;
 Ok(CheckerWarmup{directory,header,artifacts})
}
fn run(mode:&str,root:&Path,cache:&Path,out:&Path,legacy:&Path)->Result<(),Box<dyn Error>>{
 let expected=reference_for_mode(mode)?;require_oracle(legacy,expected)?;let generation=mode=="gen";let checker_only=mode=="checker";let build=request(root,cache,generation)?;let mut host=BuildHost::default();let mut observed=false;let mut artifacts=std::collections::BTreeMap::new();
 let warmup=if checker_only{Some(warm_checker_host(&mut host,root,cache,out)?)}else{None};
 let result:Result<bool,Box<dyn Error>>=if generation{
  dmbc::with_all_generation_check_input_observation(&mut host,build,|mut observation|{
   observed=true;let deadline=observation.deadline;observation.write_header(&mut new(&out.join("generation-header.json"))?)?;
   let slots=observation.phase_slots();let mut targets=Vec::new();let mut remaining=BOUND;
   for slot in 0..3{if !slots[slot]{continue}let(mut inputs,mut previous,mut journal)=(new(&out.join(format!("phase{slot}-inputs.json")))?,new(&out.join(format!("phase{slot}-targets.json")))?,new(&out.join(format!("phase{slot}-journal.bin")))?);observation.write_phase(slot,&mut inputs,&mut previous,&mut journal)?;drop((inputs,previous,journal));
    let rows=read_json(&out.join(format!("phase{slot}-targets.json")))?;for(index,row)in rows.as_array().ok_or_else(||invalid("actual target array absent"))?.iter().enumerate(){let path=PathBuf::from(row["path"].as_str().ok_or_else(||invalid("actual target path absent"))?);if !path.starts_with(root){return Err(invalid("actual target is outside observed source root"))}let archived=if row["previous"].is_null(){None}else{let rel=format!("target-{slot}-{index}.bin");copy_target(&path,&out.join(&rel),row["previous_length"].as_u64().ok_or_else(||invalid("actual previous length absent"))?,row["previous_hash"].as_str().ok_or_else(||invalid("actual previous hash absent"))?,&mut remaining)?;Some(rel)};targets.push(serde_json::json!({"slot":slot,"index":index,"path":path,"archived":archived}));}
   }
   json(&out.join("target-archives.json"),&targets)?;observation.write_report(&mut new(&out.join("native-generation-report.json"))?)?;
   seal_files(out,&mut artifacts,false)?;
   // Real ordinary CHECK, no source write; max two selected generator workers per child.
   // Every child sees the same still-borrowed actual phase/target closure.
   for(index,names)in NAMES.chunks(2).enumerate(){let mut args=vec!["gen".into(),"--check".into(),"--root".into(),root.to_string_lossy().into_owned()];args.extend(names.iter().map(|name|(*name).to_owned()));oracle(legacy,root,out,&format!("legacy-gen-{index}"),&args,deadline,expected)?;}
   seal_files(out,&mut artifacts,false)?;Ok(())
  })
 }else{
  let options=match mode{"raw"|"checker"=>FullRegistryCheckOptions{raw:true,ci:false,unused:true,..Default::default()},"ci"=>FullRegistryCheckOptions{raw:false,ci:true,unused:true,..Default::default()},_=>return Err(invalid("mode must be raw, ci, gen or checker").into())};
  let(mut diagnostics,mut report)=(new(&out.join("native-analyze.stderr"))?,new(&out.join("native-analyze.stdout"))?);
  host.write_full_registry_check_with_input_observation(build,options,|observation|{
   observed=true;let deadline=observation.deadline;let observed_project=observation.project;let(mut header,mut inputs,mut checker)=(new(&out.join("report-header.json"))?,new(&out.join("combined-preparation-inputs.json"))?,new(&out.join("native-checker.json"))?);observation.write_inputs(&mut header,&mut inputs,&mut checker)?;drop((header,inputs,checker));
   seal_files(out,&mut artifacts,true)?;
   if checker_only{
    // One explicitly requested pinned reference, within the SAME real native
    // observation borrow. This invocation has no native/default fallback and
    // does not itself promote DATA to source or universal-parity authority.
    if observed_project.parent()!=Some(root){return Err(invalid("Checker reference project differs from actual observed root"))}
    let warmup=warmup.as_ref().ok_or_else(||invalid("Checker mode lacks its actual same-host warmup"))?;
    warmup.require_same_frames(&read_json(&out.join("report-header.json"))?)?;
    require_same_input_facts(&mut io::BufReader::new(File::open(warmup.directory.join("combined-preparation-inputs.json"))?),&mut io::BufReader::new(File::open(out.join("combined-preparation-inputs.json"))?))?;
    let started=Instant::now();let reference_deadline=deadline.min(started+Duration::from_secs(300));
    json(&out.join("pinned-checker-budget.json"),&serde_json::json!({"second_original_request_seconds":300,"standalone_reference_seconds_max":300,"actual_remaining_seconds":reference_deadline.saturating_duration_since(started).as_secs_f64(),"same_build_host":true,"two_original_requests":true,"aggregate_outer_seconds_max":630,"native_performance_claim":false}))?;
    oracle(legacy,root,out,"pinned-checker",&["-e".into(),observed_project.to_string_lossy().into_owned()],reference_deadline,expected)?;
    warmup.require_seals()?;
   }else{oracle(legacy,root,out,"legacy-analyze",&["check".into(),format!("--{mode}"),"--no-cache".into(),"--no-selftest".into(),"--unused".into(),"--root".into(),root.to_string_lossy().into_owned()],deadline,expected)?;}
   seal_files(out,&mut artifacts,true)
  },&mut diagnostics,&mut report)
 };
 match result{Ok(clean)=>{require_oracle(legacy,expected)?;if !generation{let header=read_json(&out.join("report-header.json"))?;verify_stream(&out.join("native-analyze.stdout"),&header["binding"]["report"])?;let diagnostic=&header["binding"]["diagnostics"];if diagnostic.is_null(){if fs::metadata(out.join("native-analyze.stderr"))?.len()!=0{return Err(invalid("unexpected unsealed diagnostics").into())}}else{verify_stream(&out.join("native-analyze.stderr"),diagnostic)?}}seal_files(out,&mut artifacts,false)?;json(&out.join("capture.json"),&serde_json::json!({"completed":true,"mode":mode,"root":root,"oracle":legacy,"oracle_sha256":expected,"native_clean":clean,"callback_ran":observed,"artifacts_sha256":artifacts,"scope":"actual before/after observed source/target frame; comparison still required","universal_parity":false}))?;Ok(())},Err(error)=>{let _=json(&out.join("capture.json"),&serde_json::json!({"completed":false,"mode":mode,"root":root,"callback_ran":observed,"error":error.to_string(),"artifacts":"provisional only; no completed observed frame"}));Err(error)}}
}
fn main()->Result<(),Box<dyn Error>>{
 let args=std::env::args_os().skip(1).collect::<Vec<_>>();if args.len()!=5{return Err(invalid("usage: MODE ROOT EXISTING-EXTERNAL-CACHE NEW-OUTPUT-DIR FROZEN-REFERENCE-EXE (raw/ci/gen:77ae Analyze; checker:bafd Checker)").into())}
 let mode=args[0].to_str().ok_or_else(||invalid("mode is not UTF8"))?;let root=fs::canonicalize(&args[1])?;let cache=fs::canonicalize(&args[2])?;let legacy=fs::canonicalize(&args[4])?;let output_argument=PathBuf::from(&args[3]);if !output_argument.is_absolute(){return Err(invalid("output path must be absolute").into())}let out=fs::canonicalize(output_argument.parent().ok_or_else(||invalid("output parent absent"))?)?.join(output_argument.file_name().ok_or_else(||invalid("output name absent"))?);
 let e_only=cache.components().next().is_some_and(|component|matches!(component,std::path::Component::Prefix(prefix)if matches!(prefix.kind(),std::path::Prefix::Disk(b'E'|b'e')|std::path::Prefix::VerbatimDisk(b'E'|b'e'))));
 if !root.is_absolute()||!cache.is_absolute()||cache.starts_with(&root)||!out.starts_with(&cache)||!e_only||!cache.starts_with(fs::canonicalize("E:/dq-cache")?){return Err(invalid("owned cache/output must be absolute external E paths").into())}fs::create_dir(&out)?;run(mode,&root,&cache,&out,&legacy)
}

#[cfg(test)]mod reference_mode_controls{
 use super::*;
 #[test]fn actual_held_oracle_mode_selects_one_exact_independent_image_without_changing_existing_routes(){
  for mode in["raw","ci","gen"]{assert_eq!(reference_for_mode(mode).unwrap(),ORACLE)}
  assert_eq!(reference_for_mode("checker").unwrap(),CHECKER_ORACLE);assert_ne!(CHECKER_ORACLE,ORACLE);
  for mode in["","check","checker-all","raw-checker"]{assert!(reference_for_mode(mode).is_err())}
 }
 #[test]fn actual_snapshot_fact_comparison_ignores_only_serialized_scan_clock_and_keeps_all_domains(){
  let first=serde_json::to_vec(&dmbc::input_snapshot::InputSnapshot::new(1)).unwrap();let later=serde_json::to_vec(&dmbc::input_snapshot::InputSnapshot::new(u128::MAX)).unwrap();require_same_input_facts(&mut io::Cursor::new(&first),&mut io::Cursor::new(&later)).unwrap();
  // Decode the real typed DTO directly: generic Value may represent u128::MAX
  // as f64 and lose precision before from_value can recover the typed clock.
  let mut changed:dmbc::input_snapshot::InputSnapshot=serde_json::from_slice(&later).unwrap();
  assert_eq!(changed.scanned_ns,u128::MAX,"typed snapshot codec preserves the full actual clock domain");
  changed.record_negative(Path::new("E:/changed-source.dm")).unwrap();
  // Preserve actual codec order, changing only a real source fact payload.
  let changed=serde_json::to_vec(&changed).unwrap();
  let roundtrip:dmbc::input_snapshot::InputSnapshot=serde_json::from_slice(&changed).unwrap();assert_eq!(roundtrip.scanned_ns,u128::MAX);
  assert!(require_same_input_facts(&mut io::Cursor::new(&first),&mut io::Cursor::new(changed)).is_err());
  assert!(require_same_input_facts(&mut io::Cursor::new(b"{}"),&mut io::Cursor::new(first)).is_err());
 }

}
