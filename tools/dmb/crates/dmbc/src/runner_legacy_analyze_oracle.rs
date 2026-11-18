//! Explicit immutable legacy Analyze reference process, never a production
//! parser, default fallback or sibling compiler daemon. Every call is typed.
use std::{fs::{File,OpenOptions},io::{self,Read,Seek,SeekFrom},path::{Path,PathBuf},process::{Child,Command,Stdio},time::Duration};
use sha2::{Digest,Sha256};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use crate::{input_snapshot::{SnapshotProvider,FileSystemInputs,Stamp},selected_report_spool::{Stage,Verified}};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,s)}
pub(crate)use dq_analyze::native_codemod_fixture_wire::FrozenOracleBinding as Binding;
pub(crate)enum Question<'a>{Help,List,Checks{names:&'a[String],raw:bool},Check{lint:&'a str,raw:bool},Fixture{lint:&'a str},Selftest{lint:&'a str}}
pub(crate)enum OwnedQuestion<'a>{FixtureBless{lint:&'a str},Baseline{names:&'a[String],mode:dq_analyze::native_baseline_update_wire::Mode}}
enum Invocation<'a>{Read(Question<'a>),Owned(OwnedQuestion<'a>)}
pub(crate)struct Oracle{image:PathBuf,file:std::sync::Mutex<File>,stamp:Stamp,digest:[u8;32],_credit:SourceArenaCredit}
pub(crate)struct Output{pub(crate)code:i32,pub(crate)stdout:Verified,pub(crate)stderr:Verified}
impl Oracle{
 pub(crate)fn open(binding:&Binding,work:&dyn SourceArenaWork)->io::Result<Self>{
  binding.validate()?;work.checkpoint()?;
  let mut credit=work.reserve(std::mem::size_of::<Self>())?;
  let image=dm_preprocess::regions::copy_path_into_credit(&binding.image,work,&mut credit)?;
  let mut options=OpenOptions::new();options.read(true);
  #[cfg(windows)]{use std::os::windows::fs::OpenOptionsExt;options.share_mode(1);}
  let mut file=options.open(&image)?;if !file.metadata()?.is_file(){return Err(invalid("parity oracle is not an ordinary executable file"))}
  #[cfg(unix)]fs2::FileExt::try_lock_shared(&file)?;
  let stamp=crate::input_snapshot::stamp_handle(&file)?;let current=FileSystemInputs.stamp(&std::env::current_exe()?)?;
  if stamp.file_id.is_none()||stamp.file_id==current.file_id{return Err(invalid("the current compiler/test image cannot be the independent parity oracle"))}
  let(digest,legacy,native,binary)=hash_and_markers(&mut file,work)?;
  if !legacy||native||!binary{return Err(invalid("explicit oracle is not the frozen legacy Analyze executable; native clients/wrappers are forbidden"))}
  if digest!=parse_digest(&binding.sha256)?{return Err(invalid("explicit oracle bytes differ from the requested SHA-256 version"))}
  let actual=Self{image,file:std::sync::Mutex::new(file),stamp,digest,_credit:credit};actual.require_current(work)?;Ok(actual)
 }
 pub(crate)fn require_current(&self,work:&dyn SourceArenaWork)->io::Result<()>{
  work.checkpoint()?;let mut file=self.file.lock().map_err(|_|invalid("frozen reference image cursor poisoned"))?;if crate::input_snapshot::stamp_handle(&file)?!=self.stamp||FileSystemInputs.stamp(&self.image)?!=self.stamp{return Err(io::Error::new(io::ErrorKind::Interrupted,"frozen parity oracle identity changed"))}
  // Same open-file lease remains held; re-read the selected version, not a
  // path-derived version counter or the current native compiler's pointer.
  let(digest,legacy,native,binary)=hash_and_markers(&mut file,work)?;if digest!=self.digest||!legacy||native||!binary{return Err(io::Error::new(io::ErrorKind::Interrupted,"frozen parity oracle content/version changed"))}Ok(())
 }
 pub(crate)fn run_many(&self,root:&Path,cache:&Path,names:&[String],raw:bool,work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn std::error::Error>>)->Result<Output,Box<dyn std::error::Error>>{self.run_using(root,cache,Invocation::Read(Question::Checks{names,raw}),work,current)}
 pub(crate)fn run(&self,root:&Path,cache:&Path,question:Question<'_>,work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn std::error::Error>>)->Result<Output,Box<dyn std::error::Error>>{
  self.run_using(root,cache,Invocation::Read(question),work,current)
 }
 /// The mutating reference is available ONLY with the owned sandbox type.
 /// It can never receive the caller's actual root as a free Path argument.
 pub(crate)fn run_owned(&self,sandbox:&mut super::full_registry_check::parity_scratch::Sandbox,cache:&Path,question:OwnedQuestion<'_>,work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn std::error::Error>>)->Result<Output,Box<dyn std::error::Error>>{
  sandbox.current(work)?;current()?;
  let attempt=self.run_using(sandbox.root(),cache,Invocation::Owned(question),work,current);
  // Enroll fixed outputs after EVERY attempt, before cleanup can touch them.
  // A reader/process/OS error remains the first error, never false success.
  let enrolled=sandbox.enroll_outputs(work);
  match attempt{Err(first)=>{let _=enrolled;Err(first)},Ok(output)=>{enrolled?;sandbox.current(work)?;current()?;Ok(output)}}
 }
 fn run_using(&self,root:&Path,cache:&Path,question:Invocation<'_>,work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn std::error::Error>>)->Result<Output,Box<dyn std::error::Error>>{
  self.require_current(work)?;current()?;
  if !root.is_absolute()||!cache.is_absolute()||cache.starts_with(root){return Err(invalid("parity reference requires actual source root and existing external cache").into())}
  let mut command=OwnedCommand::new(&self.image,work)?;command.current_dir(root)?;
  command.env("DQ_ANALYZE_CACHE",cache)?;command.env("TMP",cache)?;command.env("TEMP",cache)?;command.env("TMPDIR",cache)?;
  command.env("RAYON_NUM_THREADS","2")?;command.env("PYTHONIOENCODING","utf-8")?;command.env("PYTHONUTF8","1")?;
  command.env_remove("DQ_ANALYZE_TRACE")?;command.env_remove("DQ_ANALYZE_TRACE_SPANS")?;command.env_remove("DQ_ALLOW_USAGE")?;
  apply_question(&mut command,question,root)?;
  #[cfg(windows)]{use std::os::windows::process::CommandExt;command.actual.creation_flags(0x08000000|0x00004000);}
  command.actual.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
  let(code,stdout,stderr)=run_bounded(command,cache,work)?;
  self.require_current(work)?;current()?;Ok(Output{code,stdout,stderr})
 }
}
fn apply_question(command:&mut OwnedCommand<'_>,question:Invocation<'_>,root:&Path)->Result<(),Box<dyn std::error::Error>>{
 match question{
  Invocation::Read(Question::Help)=>{command.arg("--help")?;},Invocation::Read(Question::List)=>{command.arg("list")?;},
  Invocation::Read(Question::Checks{names,raw})=>{if names.is_empty(){return Err(invalid("reference requires actual resolved native selectors").into())}command.args(["check","--lint"])?;for name in names{lint_name(name)?;command.arg(name)?;}command.args(["--no-cache","--no-selftest","--no-unused"])?;if raw{command.arg("--raw")?;}},
  Invocation::Read(Question::Check{lint,raw})=>{lint_name(lint)?;command.args(["check","--lint",lint,"--no-cache","--no-selftest","--no-unused"])?;if raw{command.arg("--raw")?;}},
  Invocation::Read(Question::Fixture{lint})=>{lint_name(lint)?;command.args(["fixture",lint])?;},
  Invocation::Read(Question::Selftest{lint})=>{lint_name(lint)?;command.args(["selftest","--lint",lint,"--no-cache"])?;},
  Invocation::Owned(OwnedQuestion::FixtureBless{lint})=>{lint_name(lint)?;command.args(["fixture",lint,"--bless"])?;},
  Invocation::Owned(OwnedQuestion::Baseline{names,mode})=>{
   if names.is_empty(){return Err(invalid("reference baseline requires actual canonical selectors").into())}
   let mode=match mode{dq_analyze::native_baseline_update_wire::Mode::Update=>"--update",dq_analyze::native_baseline_update_wire::Mode::Seed=>"--seed",dq_analyze::native_baseline_update_wire::Mode::Migrate=>return Err(invalid("parity compares only update and seed modes").into())};
   command.args(["baseline",mode,"--lint"])?;for name in names{lint_name(name)?;command.arg(name)?;}command.args(["--no-cache","--no-selftest","--no-unused"])?;command.env("DQ_BASELINE_NO_GEN","1")?;
  },
 }command.arg("--root")?;command.arg(root)?;Ok(())
}
/// SAME-work named allocator frontiers for inserted program/argv/env/cwd DATA.
/// std/OS process internals remain under the EXISTING owned Job/process-count,
/// deadline and output limits: this is not a claim to census opaque std fields.
/// Field spellings and row frontiers are funded BEFORE insertion. There is no
/// new process budget and no root.len()*N or fixed catchall metadata padding.
struct OwnedCommand<'a>{actual:Command,work:&'a dyn SourceArenaWork,_credit:SourceArenaCredit}
impl<'a> OwnedCommand<'a>{
 fn field(&mut self,text:&std::ffi::OsStr,row:usize)->io::Result<()>{Self::fund_field(self.work,&mut self._credit,text,row)}
 fn fund_field(work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit,text:&std::ffi::OsStr,row:usize)->io::Result<()>{work.checkpoint()?;let width=text.len().checked_add(1).and_then(|n|n.checked_add(row)).and_then(|n|n.checked_mul(4)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;work.grow(credit,width)}
 fn new(image:&Path,work:&'a dyn SourceArenaWork)->io::Result<Self>{let mut credit=work.reserve(std::mem::size_of::<Self>())?;Self::fund_field(work,&mut credit,image.as_os_str(),std::mem::size_of::<std::ffi::OsString>())?;Self::fund_field(work,&mut credit,image.as_os_str(),std::mem::size_of::<std::ffi::OsString>())?;Ok(Self{actual:Command::new(image),work,_credit:credit})}
 fn arg(&mut self,value:impl AsRef<std::ffi::OsStr>)->io::Result<()>{let value=value.as_ref();self.field(value,std::mem::size_of::<std::ffi::OsString>())?;self.actual.arg(value);Ok(())}
 fn args<I,S>(&mut self,values:I)->io::Result<()>where I:IntoIterator<Item=S>,S:AsRef<std::ffi::OsStr>{for value in values{self.arg(value)?;}Ok(())}
 fn current_dir(&mut self,path:&Path)->io::Result<()>{self.field(path.as_os_str(),std::mem::size_of::<PathBuf>())?;self.actual.current_dir(path);Ok(())}
 fn env(&mut self,key:impl AsRef<std::ffi::OsStr>,value:impl AsRef<std::ffi::OsStr>)->io::Result<()>{let key=key.as_ref();let value=value.as_ref();self.field(key,std::mem::size_of::<(std::ffi::OsString,Option<std::ffi::OsString>)>())?;self.field(value,0)?;self.actual.env(key,value);Ok(())}
 fn env_remove(&mut self,key:impl AsRef<std::ffi::OsStr>)->io::Result<()>{let key=key.as_ref();self.field(key,std::mem::size_of::<(std::ffi::OsString,Option<std::ffi::OsString>)>())?;self.actual.env_remove(key);Ok(())}
 fn before_spawn(&mut self)->io::Result<()>{
  fn units(value:&std::ffi::OsStr)->usize{#[cfg(windows)]{use std::os::windows::ffi::OsStrExt;value.encode_wide().count()}#[cfg(not(windows))]{value.len()}}
  // Windows may quote every UTF16 unit and double backslashes. Unix C argv
  // uses at most this same named frontier; inherited OS environment stays
  // outside source heap under the existing single-owned-process boundary.
  let mut width=0usize;let mut count=0usize;for arg in std::iter::once(self.actual.get_program()).chain(self.actual.get_args()){self.work.checkpoint()?;width=width.checked_add(units(arg).checked_mul(2).and_then(|n|n.checked_add(3)).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?;count=count.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}
  for(key,value)in self.actual.get_envs(){width=width.checked_add(units(key)).and_then(|n|n.checked_add(value.map_or(0,units))).and_then(|n|n.checked_add(2)).ok_or(io::ErrorKind::OutOfMemory)?;}
  let encoded=width.checked_mul(std::mem::size_of::<u16>()).and_then(|n|n.checked_add(count.checked_add(1)?.checked_mul(std::mem::size_of::<*const u8>())?)).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;self.work.grow(&mut self._credit,encoded)
 }
}
struct OwnedChild{child:Child,finished:bool,tree:Option<ProcessTree>}
impl OwnedChild{fn stop_tree(&mut self){if let Some(tree)=self.tree.take(){drop(tree)}if !self.finished{let _=self.child.kill();let _=self.child.wait();self.finished=true;}}}
impl Drop for OwnedChild{fn drop(&mut self){self.stop_tree()}}
#[cfg(windows)]struct ProcessTree(*mut std::ffi::c_void);
#[cfg(windows)]impl ProcessTree{
 fn attach(child:&Child)->io::Result<Self>{
  use std::os::windows::io::AsRawHandle;
  #[repr(C)]#[derive(Default)]struct Basic{process_time:i64,job_time:i64,flags:u32,min:usize,max:usize,active:u32,affinity:usize,priority:u32,scheduling:u32}
  #[repr(C)]#[derive(Default)]struct Io{read_ops:u64,write_ops:u64,other_ops:u64,read_bytes:u64,write_bytes:u64,other_bytes:u64}
  #[repr(C)]#[derive(Default)]struct Limits{basic:Basic,io:Io,process_memory:usize,job_memory:usize,peak_process:usize,peak_job:usize}
  #[link(name="kernel32")]unsafe extern "system"{fn CreateJobObjectW(a:*const std::ffi::c_void,n:*const u16)->*mut std::ffi::c_void;fn SetInformationJobObject(j:*mut std::ffi::c_void,c:i32,p:*const std::ffi::c_void,n:u32)->i32;fn AssignProcessToJobObject(j:*mut std::ffi::c_void,p:*mut std::ffi::c_void)->i32;}
  let job=unsafe{CreateJobObjectW(std::ptr::null(),std::ptr::null())};if job.is_null(){return Err(io::Error::last_os_error())}let owned=Self(job);let mut limits=Limits::default();limits.basic.flags=0x2000;
  if unsafe{SetInformationJobObject(job,9,&limits as *const _ as *const _,std::mem::size_of::<Limits>()as u32)}==0{return Err(io::Error::last_os_error())}
  if unsafe{AssignProcessToJobObject(job,child.as_raw_handle())}==0{return Err(io::Error::last_os_error())}Ok(owned)
 }
}
#[cfg(windows)]impl Drop for ProcessTree{fn drop(&mut self){#[link(name="kernel32")]unsafe extern "system"{fn CloseHandle(h:*mut std::ffi::c_void)->i32;}unsafe{CloseHandle(self.0);}}}
#[cfg(unix)]struct ProcessTree(i32);
#[cfg(unix)]impl ProcessTree{fn attach(child:&Child)->io::Result<Self>{Ok(Self(i32::try_from(child.id()).map_err(|_|invalid("owned reference process group is out of range"))?))}}
#[cfg(unix)]impl Drop for ProcessTree{fn drop(&mut self){unsafe extern "C"{fn kill(pid:i32,signal:i32)->i32;}unsafe{kill(-self.0,9);}}}
fn remember(first:&std::sync::Mutex<Option<io::Error>>,error:io::Error){let mut first=first.lock().unwrap_or_else(|e|e.into_inner());if first.is_none(){*first=Some(error)}}
fn read_bounded(mut pipe:impl Read,cache:&Path,work:&dyn SourceArenaWork,total:&std::sync::atomic::AtomicU64)->io::Result<Stage>{
 let mut stage=Stage::new(cache)?;let mut block=[0u8;8192];loop{work.checkpoint()?;let n=pipe.read(&mut block)?;if n==0{return Ok(stage)}
  total.fetch_update(std::sync::atomic::Ordering::AcqRel,std::sync::atomic::Ordering::Acquire,|old|old.checked_add(n as u64).filter(|n|*n<=dq_analyze::selected_exclusions_wire::MAX_STREAM)).map_err(|_|io::Error::new(io::ErrorKind::OutOfMemory,"reference streams exceed the existing aggregate report bound"))?;
  std::io::Write::write_all(&mut stage,&block[..n])?;
 }
}
fn run_bounded(mut command:OwnedCommand<'_>,cache:&Path,work:&dyn SourceArenaWork)->io::Result<(i32,Verified,Verified)>{
 let thread_rows=2usize.checked_mul(std::mem::size_of::<std::thread::ScopedJoinHandle<'static,Option<Stage>>>()+std::mem::size_of::<crate::daemon::control::WorkerContext>()).and_then(|n|n.checked_add("parity-reference-stdout".len()+"parity-reference-stderr".len()+2)).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;
 let _readers=work.reserve((2*256*1024usize).checked_add(thread_rows).ok_or(io::ErrorKind::OutOfMemory)?)?;
 #[cfg(unix)]{use std::os::unix::process::CommandExt;command.actual.process_group(0);}
 let mut child=OwnedChild{child:{command.before_spawn()?;command.actual.spawn()?},finished:false,tree:None};child.tree=Some(ProcessTree::attach(&child.child)?);
 let out=child.child.stdout.take().ok_or_else(||invalid("reference stdout pipe absent"))?;let err=child.child.stderr.take().ok_or_else(||invalid("reference stderr pipe absent"))?;
 let context=crate::daemon::control::WorkerContext::capture_for_checkpoints().ok_or_else(||invalid("reference requires the active original request deadline"))?;
 let first=std::sync::Mutex::new(None);let total=std::sync::atomic::AtomicU64::new(0);
 let (status,out,err)=std::thread::scope(|scope|->io::Result<_>{
  // Keep the owned process tree INSIDE the scope. It is stopped before reader
  // joins, including failed spawn, cancellation and actual IO errors.
  let mut child=child;let first=&first;let total=&total;let context_out=context.clone();let context_err=context.clone();
  let output=std::thread::Builder::new().name("parity-reference-stdout".into()).stack_size(256*1024).spawn_scoped(scope,move||{let _context=context_out.enter();let result=read_bounded(out,cache,work,total);match result{Err(error)=>{remember(first,error);None},Ok(stage)=>Some(stage)}})?;
  let errors=match std::thread::Builder::new().name("parity-reference-stderr".into()).stack_size(256*1024).spawn_scoped(scope,move||{let _context=context_err.enter();let result=read_bounded(err,cache,work,total);match result{Err(error)=>{remember(first,error);None},Ok(stage)=>Some(stage)}}){Ok(thread)=>Some(thread),Err(error)=>{remember(first,error);None}};
  let status=loop{
   if first.lock().unwrap_or_else(|e|e.into_inner()).is_some(){break None}
   if let Err(error)=work.checkpoint(){remember(first,error);break None}
   match child.child.try_wait(){Ok(Some(status))=>{child.finished=true;break Some(status)},Ok(None)=>{},Err(error)=>{remember(first,error);break None}}
   std::thread::sleep(Duration::from_millis(25));
  };
  child.stop_tree();
  let out=match output.join(){Ok(value)=>value,Err(_)=>{remember(first,io::Error::other("reference stdout reader panicked"));None}};
  let err=match errors{Some(thread)=>match thread.join(){Ok(value)=>value,Err(_)=>{remember(first,io::Error::other("reference stderr reader panicked"));None}},None=>None};
  if let Some(first)=first.lock().unwrap_or_else(|e|e.into_inner()).take(){return Err(first)}
  Ok((status.ok_or_else(||invalid("reference status absent"))?,out.ok_or_else(||invalid("reference stdout stage absent"))?,err.ok_or_else(||invalid("reference stderr stage absent"))?))
 })?;
 let code=status.code().filter(|code|matches!(code,0|1|2)).ok_or_else(||invalid("legacy reference did not finish with an ordinary Analyze exit"))?;
 let finish=|stage:Stage|->io::Result<Verified>{let length=stage.length();let(output,n)=stage.seal_allow_empty()?.validate(|r|io::copy(r,&mut io::sink()))?;if n!=length{return Err(invalid("reference output omitted bytes while sealing"))}Ok(output)};
 Ok((code,finish(out)?,finish(err)?))
}
fn lint_name(name:&str)->io::Result<()>{if name.is_empty()||name.len()>256||!name.as_bytes()[0].is_ascii_alphanumeric()||!name.bytes().all(|b|b.is_ascii_alphanumeric()||matches!(b,b'_'|b'-'|b'/'|b'.')){return Err(invalid("reference needs an actual exact registered lint name"))}Ok(())}
fn parse_digest(text:&str)->io::Result<[u8;32]>{if text.len()!=64{return Err(invalid("bad frozen oracle SHA-256 version"))}let mut out=[0;32];for(i,pair)in text.as_bytes().chunks_exact(2).enumerate(){let digit=|c:u8|match c{b'0'..=b'9'=>Ok(c-b'0'),b'a'..=b'f'=>Ok(c-b'a'+10),_=>Err(invalid("bad frozen oracle SHA-256 version"))};out[i]=(digit(pair[0])?<<4)|digit(pair[1])?;}Ok(out)}
fn hash_and_markers(file:&mut File,work:&dyn SourceArenaWork)->io::Result<([u8;32],bool,bool,bool)>{
 const LEGACY:&[u8]=b"analyze: DeepQuarry's lint/analysis engine";const NATIVE:&[u8]=b"native-analyze-client-v";const KEEP:usize=LEGACY.len()-1;
 let _stack=work.reserve(std::mem::size_of::<[u8;65536+KEEP]>()+std::mem::size_of::<Sha256>())?;
 file.seek(SeekFrom::Start(0))?;let mut hash=Sha256::new();let mut block=[0u8;65536+KEEP];let(mut kept,mut legacy,mut native,mut binary,mut first)=(0usize,false,false,false,true);
 loop{work.checkpoint()?;let n=file.read(&mut block[kept..kept+65536])?;if n==0{break}if first{binary=block[kept..kept+n].starts_with(b"MZ")||block[kept..kept+n].starts_with(b"\x7fELF");first=false;}hash.update(&block[kept..kept+n]);let total=kept+n;legacy|=block[..total].windows(LEGACY.len()).any(|w|w==LEGACY);native|=block[..total].windows(NATIVE.len()).any(|w|w==NATIVE);let next=total.min(KEEP);block.copy_within(total-next..total,0);kept=next;}
 file.seek(SeekFrom::Start(0))?;Ok((hash.finalize().into(),legacy,native,binary))
}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn explicit_oracle_binding_has_no_default_and_rejects_missing_relative_or_unversioned_images(){for binding in[Binding{image:"relative.exe".into(),sha256:"0".repeat(64)},Binding{image:std::env::current_exe().unwrap(),sha256:String::new()},Binding{image:std::env::current_exe().unwrap(),sha256:"A".repeat(64)}]{assert!(binding.validate().is_err())}}
 #[test]fn a_hash_never_turns_current_compiler_image_into_an_independent_reference(){let host=crate::runner_host::BuildHost::default();let binding=Binding{image:std::fs::canonicalize(std::env::current_exe().unwrap()).unwrap(),sha256:"0".repeat(64)};let error=match Oracle::open(&binding,host.source_arena_work()){Err(e)=>e,Ok(_)=>panic!("current process image must refuse before reference execution")};assert_eq!(error.kind(),io::ErrorKind::InvalidInput);assert!(error.to_string().contains("current compiler/test"));}
 #[test]fn image_marker_detection_crosses_actual_reader_blocks_and_preserves_full_sha(){let root=crate::test_scratch::dir("parity-image-markers");let path=root.join("marked.bin");let mut bytes=vec![b'x';65520];bytes[..2].copy_from_slice(b"MZ");bytes.extend_from_slice(b"analyze: DeepQuarry's lint/analysis engine");let digest:[u8;32]=Sha256::digest(&bytes).into();std::fs::write(&path,&bytes).unwrap();let host=crate::runner_host::BuildHost::default();let(hash,legacy,native,binary)=hash_and_markers(&mut File::open(&path).unwrap(),host.source_arena_work()).unwrap();assert_eq!(hash,digest);assert!(legacy&&!native&&binary);}
 #[test]#[ignore="requires Root's explicitly frozen independent oracle; no build or fallback"]fn actual_frozen_legacy_executable_is_hashed_before_and_after_metadata_execution(){let image=PathBuf::from(std::env::var_os("DQ_TEST_FROZEN_ANALYZE_ORACLE").expect("explicit frozen image"));let sha256=std::env::var("DQ_TEST_FROZEN_ANALYZE_ORACLE_SHA256").expect("explicit exact image version");let host=crate::runner_host::BuildHost::default();let oracle=Oracle::open(&Binding{image,sha256},host.source_arena_work()).unwrap();let root=std::fs::canonicalize(crate::test_scratch::dir("parity-reference-help-root")).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir("parity-reference-help-cache")).unwrap();let _context=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+Duration::from_secs(30));let output=oracle.run(&root,&cache,Question::Help,host.source_arena_work(),&mut||Ok(())).unwrap();assert_eq!(output.code,0);assert!(output.stdout.length()>0);oracle.require_current(host.source_arena_work()).unwrap();}
}

#[cfg(test)]mod native_reference_version_controls{use super::*;#[test]fn every_native_client_version_is_rejected_as_an_independent_reference(){let root=crate::test_scratch::dir("parity-native-reference-markers");let path=root.join("marker.bin");let host=crate::runner_host::BuildHost::default();for marker in[b"native-analyze-client-v1" as &[u8],b"native-analyze-client-v2" as &[u8]]{let mut bytes=b"MZanalyze: DeepQuarry's lint/analysis engine ".to_vec();bytes.extend_from_slice(marker);std::fs::write(&path,&bytes).unwrap();let(_,legacy,native,binary)=hash_and_markers(&mut File::open(&path).unwrap(),host.source_arena_work()).unwrap();assert!(legacy&&native&&binary);}}}

#[cfg(test)]mod actual_owned_invocation_controls{
 use super::*;
 #[test]fn owned_fixture_and_baseline_invocations_construct_the_actual_reference_modes(){
  let work=crate::query_db::QueryDb::default();let mut fixture=OwnedCommand::new(Path::new("not-executed-source-control"),&work).unwrap();apply_question(&mut fixture,Invocation::Owned(OwnedQuestion::FixtureBless{lint:"scheduler"}),Path::new("actual-root-data")).unwrap();assert_eq!(fixture.actual.get_args().map(|part|part.to_string_lossy().into_owned()).collect::<Vec<_>>(),["fixture","scheduler","--bless","--root","actual-root-data"]);
  let names=vec!["scheduler".into(),"sem/reads".into()];for(mode,flag)in[(dq_analyze::native_baseline_update_wire::Mode::Update,"--update"),(dq_analyze::native_baseline_update_wire::Mode::Seed,"--seed")]{let work=crate::query_db::QueryDb::default();let mut command=OwnedCommand::new(Path::new("not-executed-source-control"),&work).unwrap();apply_question(&mut command,Invocation::Owned(OwnedQuestion::Baseline{names:&names,mode}),Path::new("actual-root-data")).unwrap();let args=command.actual.get_args().map(|part|part.to_string_lossy().into_owned()).collect::<Vec<_>>();assert_eq!(&args[..5],["baseline",flag,"--lint","scheduler","sem/reads"]);assert!(command.actual.get_envs().any(|(key,value)|key=="DQ_BASELINE_NO_GEN"&&value.is_some_and(|value|value=="1")));}
 }
}

#[cfg(test)]mod original_command_position_controls{use super::*;#[test]fn real_original_parser_sees_command_before_root_in_every_reference_family(){let names=vec!["scheduler".into()];for(question,word)in[(Invocation::Read(Question::Check{lint:"scheduler",raw:false}),"check"),(Invocation::Read(Question::Checks{names:&names,raw:true}),"check"),(Invocation::Read(Question::Fixture{lint:"scheduler"}),"fixture"),(Invocation::Read(Question::Selftest{lint:"scheduler"}),"selftest"),(Invocation::Owned(OwnedQuestion::Baseline{names:&names,mode:dq_analyze::native_baseline_update_wire::Mode::Update}),"baseline")]{let work=crate::query_db::QueryDb::default();let mut command=OwnedCommand::new(Path::new("not-executed-source-control"),&work).unwrap();apply_question(&mut command,question,Path::new("actual-root-data")).unwrap();let args=command.actual.get_args().map(|part|part.to_string_lossy().into_owned()).collect::<Vec<_>>();assert_eq!(args.first().map(String::as_str),Some(word));assert_eq!(&args[args.len()-2..],["--root","actual-root-data"]);let parsed=dq_analyze::cli_arguments::parse(std::iter::once("analyze".to_owned()).chain(args).collect());assert_eq!(parsed.cmd,word);assert_eq!(parsed.root,Some(PathBuf::from("actual-root-data")));}}}

#[cfg(test)]mod command_admission_controls{
 use super::*;
 struct Denied;impl SourceArenaWork for Denied{fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,_:usize)->io::Result<SourceArenaCredit>{Err(io::Error::from_raw_os_error(1450))}fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("no field insertion after initial denial")}fn shrink(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{panic!("no settlement after denial")}}
 #[test]fn actual_command_custody_denial_keeps_first_io_before_any_child_can_spawn(){let first=OwnedCommand::new(Path::new("never-spawned"),&Denied).err().unwrap();assert_eq!(first.raw_os_error(),Some(1450));}
}

#[cfg(all(test,windows))]mod actual_long_argv_bless_control{
 use super::*;
 #[test]fn actual_windows_spawn_error_prevents_fixture_bless_and_keeps_original_os_channel(){
  let real=std::fs::canonicalize(crate::test_scratch::dir("parity-long-argv-source")).unwrap();let cache=std::fs::canonicalize(crate::test_scratch::dir("parity-long-argv-cache")).unwrap();let fixture=real.join("tools/analyze/fixtures/scheduler");std::fs::create_dir_all(fixture.join("code")).unwrap();std::fs::create_dir_all(real.join("tools/ci")).unwrap();std::fs::write(real.join("tools/ci/lint_scopes.toml"),b"").unwrap();std::fs::write(fixture.join("code/probe.dm"),b"/proc/parity_long_argv()\n    sleep(1)\n").unwrap();std::fs::write(fixture.join("expected.txt"),b"preserve authored expectation\n").unwrap();
  let crate::request::Command::Build(build)=crate::cli::parse(&["prepare-query".into(),real.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual native request factory changed")};let mut request=*build;request.cache_root=Some(cache.clone());request.exact_inputs=true;request.no_cache=true;request.timeout_seconds=Some(120);request.engine_template=None;request.bootstrap_catalog=false;request.workers=1;request.progress_enabled=false;use crate::policy_request::{PolicyInputRequest,WorkspacePolicyRequest,AnalysisContext,WorkspaceAuxiliaryQuestion as Q};request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:real.clone(),recursive_roots:vec![real.join("code"),real.join("maps")],configuration:real.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::SemReads],..Default::default()});
  let mut host=crate::runner_host::BuildHost::default();let mut entered=false;let result=host.stage_native_parity_fixture(request,&real,"scheduler",true,&mut|_,_,_,_,_,_,work|{entered=true;let mut command=OwnedCommand::new(&std::env::current_exe()?,work)?;command.arg("x".repeat(40000))?;run_bounded(command,&cache,work)?;Ok(true)});assert!(entered);let error=match result{Err(error)=>error,Ok(_)=>panic!("overlong actual Windows command cannot bless")};let mut current:Option<&(dyn std::error::Error+'static)>=Some(error.as_ref());let mut code=None;while let Some(error)=current{if let Some(actual)=error.downcast_ref::<io::Error>().and_then(io::Error::raw_os_error){code=Some(actual);break}current=error.source();}assert_eq!(code,Some(206));assert_eq!(std::fs::read(fixture.join("expected.txt")).unwrap(),b"preserve authored expectation\n");
 }
}
