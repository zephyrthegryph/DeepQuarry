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
  self.run_program_using(program,args,timeout,trace_original,None)
 }
 pub(crate) fn run_program_in(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,caller:&Path)->std::io::Result<std::process::Output>{self.run_program_using(program,args,timeout,false,Some(caller))}
 fn run_program_using(&self,program:&Path,args:&[&std::ffi::OsStr],timeout:std::time::Duration,trace_original:bool,caller:Option<&Path>)->std::io::Result<std::process::Output>{
  use std::{fs::File,io,process::{Command,Stdio},time::Instant};
  let stdout=self.root.join("transport.stdout");let stderr=self.root.join("transport.stderr");
  let mut command=Command::new(program);
  command.args(args).stdin(Stdio::null()).stdout(File::create(&stdout)?).stderr(File::create(&stderr)?)
   .env("DMB_DAEMON_NAMESPACE",&self.namespace).env("DMB_DAEMON_DIR",self.root.join("daemon"))
   .env("DMB_DAEMON_AUTOSTART","1").env("DMB_FORWARDED","1")
   .env("DMB_DAEMON_IDLE_EXIT_SECS","120").env("RAYON_NUM_THREADS","1")
   .env_remove("DMB_UNIFIED_ANALYSIS").env_remove("DQ_ALLOW_USAGE");
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
impl Drop for LibraryTransport<'_>{
 fn drop(&mut self){
  let _=self.run(&[std::ffi::OsStr::new("--daemon-retire")],std::time::Duration::from_secs(20));
 }
}

