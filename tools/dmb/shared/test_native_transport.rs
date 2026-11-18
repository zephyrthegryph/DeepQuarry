use std::path::Path;
/// Opt-in transport control. Use the binary Cargo actually built and retire
/// only this private namespace after the run. Files prevent pipe backpressure
/// while the caller polls the bounded child.
pub(crate) struct LibraryTransport<'a>{pub(crate) root:&'a Path,pub(crate) namespace:String}
impl LibraryTransport<'_>{
 pub(crate) fn run(&self,args:&[&std::ffi::OsStr],timeout:std::time::Duration)->std::io::Result<std::process::Output>{
  self.run_program(Path::new(env!("CARGO_BIN_EXE_dmbc")),args,timeout)
 }
 pub(crate) fn run_program(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration)->std::io::Result<std::process::Output>{
  self.run_program_with_trace(program,args,timeout,false)
 }
 pub(crate) fn run_program_with_trace(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,trace_original:bool)->std::io::Result<std::process::Output>{
  self.run_program_using(program,args,timeout,trace_original,None,None,None)
 }
 pub(crate) fn run_program_in(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,caller:&Path)->std::io::Result<std::process::Output>{self.run_program_using(program,args,timeout,false,Some(caller),None,None)}
 pub(crate) fn run_program_with_input(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,input:&[u8])->std::io::Result<std::process::Output>{
  if input.len()>4*1024*1024+4{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"test input exceeds the existing framed metadata bound"))}
  self.run_program_using(program,args,timeout,false,None,Some(input),None)
 }
 pub(crate) fn run_program_with_usage(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,usage:&Path)->std::io::Result<std::process::Output>{self.run_program_using(program,args,timeout,false,None,None,Some(usage))}
 fn run_program_using(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,trace_original:bool,caller:Option<&Path>,input:Option<&[u8]>,usage:Option<&Path>)->std::io::Result<std::process::Output>{
  use std::{fs::File,io,process::{Command,Stdio},time::Instant};
  let stdout=self.root.join("transport.stdout");let stderr=self.root.join("transport.stderr");
  let stdin=if let Some(bytes)=input{use std::io::Write;let path=self.root.join("transport.stdin");let mut file=File::create(&path)?;file.write_all(bytes)?;file.flush()?;drop(file);Stdio::from(File::open(path)?)}else{Stdio::null()};
  let mut command=Command::new(program);
  command.args(args).stdin(stdin).stdout(File::create(&stdout)?).stderr(File::create(&stderr)?)
   .env("DMB_DAEMON_NAMESPACE",&self.namespace).env("DMB_DAEMON_DIR",self.root.join("daemon"))
   .env("DMB_DAEMON_AUTOSTART","1").env("DMB_FORWARDED","1")
   .env("DMB_DAEMON_IDLE_EXIT_SECS","120").env("RAYON_NUM_THREADS","1")
   .env_remove("DMB_UNIFIED_ANALYSIS").env_remove("DQ_ALLOW_USAGE");
  if let Some(usage)=usage{command.env("DQ_ALLOW_USAGE",usage);}
  if let Some(caller)=caller{command.current_dir(caller);}
  if trace_original { command.env("DMB_ORIGINAL_TRACE_STAGES","1"); }
  #[cfg(windows)]{use std::os::windows::process::CommandExt;command.creation_flags(0x0800_0000|0x0000_4000);}
  let mut child=command.spawn()?;
  let start=Instant::now();
  let status=loop{
   match child.try_wait(){
    Ok(Some(status))=>break status,
    Ok(None)if start.elapsed()<timeout=>std::thread::sleep(std::time::Duration::from_millis(20)),
    result=>{let _=child.kill();let _=child.wait();return Err(result.err().unwrap_or_else(||io::Error::new(io::ErrorKind::TimedOut,"owned library transport child exceeded its watchdog")));}
   }
  };
  Ok(std::process::Output{status,stdout:std::fs::read(stdout)?,stderr:std::fs::read(stderr)?})
 }
}

impl LibraryTransport<'_>{
 /// Retire ONLY this transport's private namespace, and observe its actual
 /// process exit. The protocol acknowledgement alone is not exit proof.
 pub(crate) fn retire_and_wait(&self)->std::io::Result<()>{
  use std::{io,time::{Duration,Instant}};
  let mut processes=Vec::new();let live=self.root.join("daemon/live");
  match std::fs::read_dir(live){
   Ok(entries)=>for entry in entries{
    let entry=entry?;if entry.path().extension()!=Some(std::ffi::OsStr::new("json")){continue}
    let row:serde_json::Value=serde_json::from_slice(&std::fs::read(entry.path())?)?;
    if row["namespace"].as_str()!=Some(self.namespace.as_str()){return Err(io::Error::new(io::ErrorKind::InvalidData,"private test daemon record belongs to another namespace"))}
    let pid=row["pid"].as_u64().and_then(|v|u32::try_from(v).ok()).filter(|v|*v!=0).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"private test daemon has no valid PID"))?;
    // On Windows retain the original process handle BEFORE requesting retire,
    // so a recycled PID can never impersonate completion of this process.
    processes.push(OwnedDaemonExit::open(pid)?);
   },
   Err(error)if error.kind()==io::ErrorKind::NotFound=>{},Err(error)=>return Err(error),
  }
  let output=self.run(&[std::ffi::OsStr::new("--daemon-retire")],Duration::from_secs(20))?;
  if !output.status.success(){return Err(io::Error::new(io::ErrorKind::Other,format!("private test daemon refused retirement: {}",String::from_utf8_lossy(&output.stderr))))}
  let deadline=Instant::now()+Duration::from_secs(20);
  for process in processes{process.wait(deadline.saturating_duration_since(Instant::now()))?;}
  Ok(())
 }
}
#[cfg(windows)]
struct OwnedDaemonExit(*mut std::ffi::c_void);
#[cfg(windows)]
#[link(name="kernel32")]
unsafe extern "system"{
 fn OpenProcess(access:u32,inherit:i32,pid:u32)->*mut std::ffi::c_void;
 fn WaitForSingleObject(handle:*mut std::ffi::c_void,millis:u32)->u32;
 fn CloseHandle(handle:*mut std::ffi::c_void)->i32;
}
#[cfg(windows)]
impl OwnedDaemonExit{
 fn open(pid:u32)->std::io::Result<Self>{
  let handle=unsafe{OpenProcess(0x0010_0000,0,pid)};
  if handle.is_null(){let error=std::io::Error::last_os_error();if error.raw_os_error()!=Some(87){return Err(error)}}
  Ok(Self(handle))
 }
 fn wait(&self,timeout:std::time::Duration)->std::io::Result<()>{
  if self.0.is_null(){return Ok(())}
  match unsafe{WaitForSingleObject(self.0,timeout.as_millis().min(u32::MAX as u128-1)as u32)}{
   0=>Ok(()),258=>Err(std::io::Error::new(std::io::ErrorKind::TimedOut,"private test daemon acknowledged retirement but did not exit")),_=>Err(std::io::Error::last_os_error()),
  }
 }
}
#[cfg(windows)]impl Drop for OwnedDaemonExit{fn drop(&mut self){if !self.0.is_null(){unsafe{CloseHandle(self.0);}}}}
#[cfg(not(windows))]
struct OwnedDaemonExit(u32);
#[cfg(not(windows))]
impl OwnedDaemonExit{
 fn open(pid:u32)->std::io::Result<Self>{Ok(Self(pid))}
 fn wait(&self,timeout:std::time::Duration)->std::io::Result<()>{
  let deadline=std::time::Instant::now()+timeout;let path=std::path::PathBuf::from(format!("/proc/{}",self.0));
  loop{match std::fs::metadata(&path){Err(error)if error.kind()==std::io::ErrorKind::NotFound=>return Ok(()),Err(error)=>return Err(error),Ok(_)=>{}}
   if std::time::Instant::now()>=deadline{return Err(std::io::Error::new(std::io::ErrorKind::TimedOut,"private test daemon acknowledged retirement but did not exit"))}
   std::thread::sleep(std::time::Duration::from_millis(20));
  }
 }
}
impl Drop for LibraryTransport<'_>{
 fn drop(&mut self){
  if let Err(error)=self.retire_and_wait(){
   if std::thread::panicking(){eprintln!("private test daemon cleanup failed during unwind: {error}");}
   else{panic!("private test daemon cleanup failed: {error}");}
  }
 }
}
