//! Bounded process client for the existing dmbc typed query protocol. This
//! module owns no compiler, semantic model, source receipt or generator cache.
use std::{ffi::OsString,io::{self,Read,Write},path::PathBuf,process::{Child,Command,ExitStatus,Stdio},sync::mpsc,thread,time::{Duration,Instant}};
// Independent outer watchdog covers process startup, generation handshake,
// queueing and cleanup. Only dmbc starts/interprets the typed request deadline.
const OUTER_WATCHDOG:Duration=Duration::from_secs(30*60);
const MAX_OUTPUT:usize=524_288;
// dmbc --jsonl emits one fixed metadata line before reply.jsonl. This
// allowance does not increase the daemon source-row body bound.
const MAX_BATCH_HEADER:usize=4096;
// Existing daemon frame bound also bounds a typed rejected-request message.
const MAX_STDERR:usize=4_194_304;
#[derive(Debug,PartialEq,Eq)]struct Options{program:PathBuf,request:PathBuf}
fn invalid(why:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,why)}
fn options(args:&[String])->io::Result<Options>{
 let mut program=None;let mut request=None;let mut at=0;
 while at<args.len(){let arg=&args[at];at+=1;match arg.as_str(){
  "--dmbc"=>{let value=args.get(at).ok_or_else(||invalid("--dmbc requires an absolute executable path"))?;at+=1;if program.replace(PathBuf::from(value)).is_some(){return Err(invalid("--dmbc may be supplied only once"));}},
  "--jsonl"=>{},
  value if value.starts_with("--")=>return Err(invalid("native-query accepts only --dmbc, --jsonl and one request JSON path; generation is not selected")),
  value=>{if request.replace(PathBuf::from(value)).is_some(){return Err(invalid("native-query requires exactly one request JSON path"));}}
 }}
 let program=program.ok_or_else(||invalid("native-query requires explicit --dmbc absolute executable path"))?;
 if !program.is_absolute(){return Err(invalid("--dmbc executable path must be absolute"));}
 let request=request.ok_or_else(||invalid("native-query requires a request JSON path"))?;
 Ok(Options{program,request})
}
fn bounded(mut input:impl Read,limit:usize)->io::Result<Vec<u8>>{
 let capacity=limit.checked_add(1).ok_or_else(||invalid("native client limit overflow"))?;
 let mut bytes=Vec::new();bytes.try_reserve_exact(capacity).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;
 input.by_ref().take(capacity as u64).read_to_end(&mut bytes)?;
 if bytes.len()>limit{return Err(io::Error::new(io::ErrorKind::InvalidData,"native client response exceeds existing bounded transport"));}
 Ok(bytes)
}
fn cli_stdout(input:impl Read)->io::Result<Vec<u8>>{
 let mut input=io::BufReader::new(input);let mut header=Vec::new();header.try_reserve_exact(MAX_BATCH_HEADER+1).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;
 loop{let mut byte=[0u8;1];if input.read(&mut byte)?==0{return Ok(header)}header.push(byte[0]);if header.len()>MAX_BATCH_HEADER{return Err(io::Error::new(io::ErrorKind::InvalidData,"native query client batch header exceeds fixed metadata allowance"));}if byte[0]==b'\n'{break}}
 let body=bounded(input,MAX_OUTPUT)?;header.try_reserve_exact(body.len()).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;header.extend_from_slice(&body);Ok(header)
}
fn arguments(request:&std::path::Path)->[OsString;3]{["query".into(),request.as_os_str().to_owned(),"--jsonl".into()]}
struct Running{child:Child,finished:bool}
impl Drop for Running{fn drop(&mut self){if !self.finished{let _=self.child.kill();let _=self.child.wait();}}}
struct Response{status:ExitStatus,stdout:Vec<u8>,stderr:Vec<u8>}
fn execute(options:&Options,watchdog:Duration)->io::Result<Response>{
 let mut command=Command::new(&options.program);command.args(arguments(&options.request));
 execute_command(command,watchdog)
}
fn execute_command(mut command:Command,watchdog:Duration)->io::Result<Response>{
 command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
 #[cfg(windows)]{use std::os::windows::process::CommandExt;const CREATE_NO_WINDOW:u32=0x0800_0000;const BELOW_NORMAL_PRIORITY_CLASS:u32=0x0000_4000;command.creation_flags(CREATE_NO_WINDOW|BELOW_NORMAL_PRIORITY_CLASS);}
 let child=command.spawn()?;
 let mut running=Running{child,finished:false};
 let stdout=running.child.stdout.take().ok_or_else(||io::Error::other("native client stdout pipe unavailable"))?;
 let stderr=running.child.stderr.take().ok_or_else(||io::Error::other("native client stderr pipe unavailable"))?;
 let (send,receive)=mpsc::channel();let out_send=send.clone();
 thread::Builder::new().name("native-query-stdout".into()).spawn(move||{let _=out_send.send((true,cli_stdout(stdout)));})?;
 thread::Builder::new().name("native-query-stderr".into()).spawn(move||{let _=send.send((false,bounded(stderr,MAX_STDERR)));})?;
 let until=Instant::now()+watchdog;let mut out=None;let mut err=None;let mut status=None;
 loop{
  loop{match receive.try_recv(){Ok((is_out,result))=>{let bytes=result?;if is_out{out=Some(bytes)}else{err=Some(bytes)}},Err(mpsc::TryRecvError::Empty)=>break,Err(mpsc::TryRecvError::Disconnected)=>{if out.is_none()||err.is_none(){return Err(io::Error::new(io::ErrorKind::BrokenPipe,"native client output reader ended without a complete response"));}break}}}
  if status.is_none(){status=running.child.try_wait()?;}
  if status.is_some()&&out.is_some()&&err.is_some(){running.finished=true;return Ok(Response{status:status.unwrap(),stdout:out.unwrap(),stderr:err.unwrap()});}
  if Instant::now()>=until{return Err(io::Error::new(io::ErrorKind::TimedOut,"native query client exceeded its separate outer startup/queue/cleanup watchdog"));}
  thread::sleep(Duration::from_millis(10));
 }
}
/// Delegates only to the existing dmbc client, which talks to the SAME retained
/// daemon and validates concrete typed requests/replies. No legacy fallback.
pub fn run(args:&[String],stdout:&mut impl Write,stderr:&mut impl Write)->io::Result<i32>{
 let options=options(args)?;
 // The actual typed dmbc client opens and validates the request once.
 // This thin client neither parses it nor claims identity with a prior read.
 let response=execute(&options,OUTER_WATCHDOG)?;
 deliver(response,stdout,stderr)
}
fn deliver(response:Response,stdout:&mut impl Write,stderr:&mut impl Write)->io::Result<i32>{
 stderr.write_all(&response.stderr)?;
 if response.status.success(){stdout.write_all(&response.stdout)?;}
 Ok(response.status.code().unwrap_or(2))
}
pub fn cli(args:&[String])->std::process::ExitCode{
 match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>match u8::try_from(code){Ok(code)=>std::process::ExitCode::from(code),Err(_)=>std::process::exit(code)},Err(actual)=>{eprintln!("analyze native-query: {actual}");std::process::ExitCode::from(2)}}
}
pub fn generation_unavailable()->std::process::ExitCode{eprintln!("native generation is not selected: the complete stage-0 preparation, generator server route, revision advance and installation protocol are not available; refusing legacy fallback");std::process::ExitCode::from(2)}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn native_client_preserves_literal_arguments_and_refuses_unsupported_routes(){let root=std::env::current_dir().unwrap();let program=root.join("dmbc client.exe");let request=root.join("request [pinned] α.json");let opts=options(&["--dmbc".into(),program.to_string_lossy().into_owned(),request.to_string_lossy().into_owned(),"--jsonl".into()]).unwrap();assert_eq!(opts,Options{program,request:request.clone()});assert_eq!(arguments(&request),[OsString::from("query"),request.into_os_string(),OsString::from("--jsonl")]);for args in [vec!["--native".into()],vec!["--dmbc".into(),"relative.exe".into(),"request.json".into()],vec!["--check".into()],vec!["gen".into(),"reads".into()]]{assert!(options(&args).is_err());}}
 #[test]fn native_client_bounds_actual_output_without_parsing_request_deadlines(){assert_eq!(bounded(&b"row\n"[..],4).unwrap(),b"row\n");assert_eq!(bounded(&b"row\nx"[..],4).unwrap_err().kind(),io::ErrorKind::InvalidData);assert_eq!((MAX_OUTPUT,MAX_STDERR),(524288,4194304));assert_eq!(OUTER_WATCHDOG,Duration::from_secs(1800));}
 fn fixture_command(mode:&str)->Command{let mut command=Command::new(std::env::current_exe().unwrap());command.args(["--exact","native_cli_client::tests::native_client_process_fixture","--nocapture"]).env("DQ_NATIVE_CLIENT_PROCESS_FIXTURE",mode);command}
 #[test]fn native_client_process_fixture(){let Ok(mode)=std::env::var("DQ_NATIVE_CLIENT_PROCESS_FIXTURE")else{return};if mode=="startup"{thread::sleep(Duration::from_millis(120));let _typed_request_started_after_handshake=Instant::now();println!("PINNED_REPLY_AFTER_HANDSHAKE");}else if mode=="failure"{eprintln!("EXACT_TYPED_CLIENT_FAILURE");std::process::exit(7);}else if mode=="overflow"{let mut out=io::stdout().lock();let _=out.write_all(b"{\"row\":\"query_batch\"}\n");let _=out.write_all(&vec![b'x';MAX_OUTPUT+1]);}}
 #[test]fn native_client_keeps_startup_separate_from_typed_request_and_watchdogs_only_its_owned_child(){let response=execute_command(fixture_command("startup"),Duration::from_secs(5)).unwrap();assert!(response.status.success());assert!(response.stdout.windows(b"PINNED_REPLY_AFTER_HANDSHAKE".len()).any(|bytes|bytes==b"PINNED_REPLY_AFTER_HANDSHAKE"));let failure=execute_command(fixture_command("startup"),Duration::from_millis(20)).err().unwrap();assert_eq!(failure.kind(),io::ErrorKind::TimedOut);let response=execute_command(fixture_command("startup"),Duration::from_secs(5)).unwrap();assert!(response.status.success(),"timed out child cannot poison later client operations");}
 #[test]fn native_client_actual_pipe_overflow_refuses_complete_delivery_then_recovers(){let failure=execute_command(fixture_command("overflow"),Duration::from_secs(5)).err().unwrap();assert_eq!(failure.kind(),io::ErrorKind::InvalidData);assert!(execute_command(fixture_command("startup"),Duration::from_secs(5)).unwrap().status.success());}
 #[test]fn native_client_preserves_full_daemon_body_limit_with_separate_cli_batch_header(){let mut wire=b"{\"row\":\"query_batch\"}\n".to_vec();wire.resize(wire.len()+MAX_OUTPUT,b'x');assert_eq!(cli_stdout(wire.as_slice()).unwrap(),wire);wire.push(b'x');assert_eq!(cli_stdout(wire.as_slice()).unwrap_err().kind(),io::ErrorKind::InvalidData);assert_eq!(cli_stdout(vec![b'x';MAX_BATCH_HEADER+1].as_slice()).unwrap_err().kind(),io::ErrorKind::InvalidData);}

 #[test]fn native_client_preserves_actual_child_failure_stderr_exit_and_discards_partial_stdout(){let response=execute_command(fixture_command("failure"),Duration::from_secs(5)).unwrap();assert_eq!(response.status.code(),Some(7));let expected=response.stderr.clone();assert!(expected.windows(b"EXACT_TYPED_CLIENT_FAILURE".len()).any(|part|part==b"EXACT_TYPED_CLIENT_FAILURE"));let mut out=Vec::new();let mut err=Vec::new();assert_eq!(deliver(response,&mut out,&mut err).unwrap(),7);assert!(out.is_empty());assert_eq!(err,expected);assert!(cli_stdout(&b""[..]).unwrap().is_empty(),"a typed rejected request need not emit stdout");}

}
