//! Bounded process client for the existing dmbc typed query and generation protocols. This
//! module owns no compiler, semantic model, source receipt or generator cache.
use std::{ffi::OsString,io::{self,Read,Write},path::PathBuf,process::{Child,Command,ExitStatus,Stdio},sync::mpsc,thread,time::{Duration,Instant}};
// Independent outer watchdog covers process startup, generation handshake,
// queueing and cleanup. Only dmbc starts/interprets the typed request deadline.
const OUTER_WATCHDOG:Duration=Duration::from_secs(30*60);
const MAX_OUTPUT:usize=524_288;
// Same metadata-document ceiling as the generation server; query limits stay unchanged.
const MAX_GENERATION_OUTPUT:usize=64*1024*1024;
#[derive(Clone,Copy,Debug,PartialEq,Eq)]enum Mode{Query,Generate,Check,Baseline}
impl Mode{fn command(self)->&'static str{match self{Self::Query=>"query",Self::Generate=>"generate",Self::Check=>"analyze-check",Self::Baseline=>"analyze-baseline"}}}
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
  value if value.starts_with("--")=>return Err(invalid("native-query accepts only --dmbc, --jsonl and one request JSON path; generation uses the explicit native-gen command")),
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
fn arguments(request:&std::path::Path)->[OsString;3]{arguments_for(Mode::Query,request)}
fn arguments_for(mode:Mode,request:&std::path::Path)->[OsString;3]{[mode.command().into(),request.as_os_str().to_owned(),"--jsonl".into()]}
fn growing_bounded(mut input:impl Read,limit:usize)->io::Result<Vec<u8>>{
 let mut bytes=Vec::new();let mut chunk=[0u8;8192];
 loop{let count=input.read(&mut chunk)?;if count==0{return Ok(bytes)}
  let next=bytes.len().checked_add(count).ok_or_else(||invalid("native generation output length overflow"))?;
  if next>limit{return Err(io::Error::new(io::ErrorKind::InvalidData,"native generation response exceeds server metadata limit"));}
  if next>bytes.capacity(){let target=bytes.capacity().max(8192).checked_mul(2).unwrap_or(limit).min(limit).max(next);
   bytes.try_reserve_exact(target-bytes.len()).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;}
  bytes.extend_from_slice(&chunk[..count]);
 }
}
fn generation_stdout(input:impl Read)->io::Result<Vec<u8>>{growing_bounded(input,MAX_GENERATION_OUTPUT+MAX_BATCH_HEADER+2)}
struct Running{child:Child,finished:bool}
impl Drop for Running{fn drop(&mut self){if !self.finished{let _=self.child.kill();let _=self.child.wait();}}}
struct Response{status:ExitStatus,stdout:Vec<u8>,stderr:Vec<u8>}
fn execute(options:&Options,watchdog:Duration)->io::Result<Response>{
 let mut command=Command::new(&options.program);command.args(arguments(&options.request));
 execute_command(command,watchdog)
}
fn execute_command(command:Command,watchdog:Duration)->io::Result<Response>{execute_command_for(command,watchdog,Mode::Query)}
fn execute_command_for(mut command:Command,watchdog:Duration,mode:Mode)->io::Result<Response>{
 command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
 #[cfg(windows)]{use std::os::windows::process::CommandExt;const CREATE_NO_WINDOW:u32=0x0800_0000;const BELOW_NORMAL_PRIORITY_CLASS:u32=0x0000_4000;command.creation_flags(CREATE_NO_WINDOW|BELOW_NORMAL_PRIORITY_CLASS);}
 let child=command.spawn()?;
 let mut running=Running{child,finished:false};
 let stdout=running.child.stdout.take().ok_or_else(||io::Error::other("native client stdout pipe unavailable"))?;
 let stderr=running.child.stderr.take().ok_or_else(||io::Error::other("native client stderr pipe unavailable"))?;
 let (send,receive)=mpsc::channel();let out_send=send.clone();
 thread::Builder::new().name("native-query-stdout".into()).spawn(move||{let _=out_send.send((true,match mode{Mode::Query=>cli_stdout(stdout),Mode::Generate=>generation_stdout(stdout),Mode::Check|Mode::Baseline=>policy_stdout(stdout)}));})?;
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
/// Explicit generation route. The child validates the request, fragmented reply,
/// terminal hash and installation outcome; this client owns no source or cache.
pub fn generation_cli(args:&[String])->std::process::ExitCode{
 let result=(||{let options=options(args)?;let mut command=Command::new(&options.program);command.args(arguments_for(Mode::Generate,&options.request));
  let response=execute_command_for(command,OUTER_WATCHDOG,Mode::Generate)?;
  deliver_generation(response,&mut io::stdout().lock(),&mut io::stderr().lock())})();
 match result{Ok(code)=>std::process::ExitCode::from(code),Err(actual)=>{eprintln!("analyze native-gen: {actual}");std::process::ExitCode::from(2)}}
}
#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct GenerationHeader{schema:String,row:String,status:String,clean:bool,committed:bool,cleanup_warnings:u32}
#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct GenerationDocument{schema:String,clean:bool,committed:bool,rows:serde::de::IgnoredAny,diagnostics:serde::de::IgnoredAny,changed:serde::de::IgnoredAny,cleanup:serde::de::IgnoredAny}
fn validate_generation(bytes:&[u8],code:i32)->io::Result<()>{
 let invalid_report=||io::Error::new(io::ErrorKind::InvalidData,"native generation did not return a complete matching report");
 let header_end=bytes.iter().position(|byte|*byte==b'\n').ok_or_else(invalid_report)?;
 if header_end>MAX_BATCH_HEADER||bytes.len().saturating_sub(header_end+1)>MAX_GENERATION_OUTPUT+1{return Err(invalid_report())}
 let mut rows=bytes.split(|byte|*byte==b'\n');
 let header:GenerationHeader=serde_json::from_slice(rows.next().ok_or_else(invalid_report)?).map_err(|_|invalid_report())?;
 let document:GenerationDocument=serde_json::from_slice(rows.next().ok_or_else(invalid_report)?).map_err(|_|invalid_report())?;
 if rows.any(|row|!row.is_empty())||header.schema!="native-generation-batch-v1"||header.row!="generation_batch"||header.status!="completed"||document.schema!="native-generation-v1"||header.committed!=document.committed||header.clean!=document.clean||header.clean!=(code==0){return Err(invalid_report())}
 let _=(header.cleanup_warnings,document.rows,document.diagnostics,document.changed,document.cleanup);Ok(())
}
fn deliver_generation(response:Response,stdout:&mut impl Write,stderr:&mut impl Write)->io::Result<u8>{
 stderr.write_all(&response.stderr)?;
 match response.status.code(){Some(code @ (0|1))=>{validate_generation(&response.stdout,code)?;stdout.write_all(&response.stdout)?;Ok(code as u8)},_=>Ok(2)}
}


// Report metadata is data-only. These visitors retain no report text, row Vec,
// source model or request fields; serde reuses at most its one token scratch.
const MAX_POLICY_OUTPUT:usize=64*1024*1024;
struct ReportString<const RULE:u8>;
impl<'de,const RULE:u8> serde::de::Visitor<'de> for ReportString<RULE>{
 type Value=Self;
 fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("validated native report text")}
 fn visit_str<E:serde::de::Error>(self,value:&str)->Result<Self,E>{
  let hex=|length|value.len()==length&&value.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b));
  let valid=match RULE{0=>true,1=>value=="native-analyze-report-v1",2=>hex(32),3=>!value.is_empty(),4=>value.is_empty()||hex(40),_=>false};
  if valid{Ok(self)}else{Err(E::custom("invalid native report string"))}
 }
}
impl<'de,const RULE:u8> serde::Deserialize<'de> for ReportString<RULE>{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{d.deserialize_str(Self)}}
const EXCLUSIVE_TREE_REPORT_NAMES:[&str;5]=["sys/hygiene","sys/resolvers","sys/tables","system_boundary","sem/keys"];
struct LintName;
impl<'de> serde::de::Visitor<'de> for LintName{
 type Value=usize;
 fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("an admitted explicit native report name")}
 fn visit_str<E:serde::de::Error>(self,value:&str)->Result<usize,E>{crate::native_policy_roster::RAW_FILE_LINT_NAMES.iter().position(|name|*name==value).or_else(||EXCLUSIVE_TREE_REPORT_NAMES.iter().position(|name|*name==value).map(|index|crate::native_policy_roster::RAW_FILE_LINT_NAMES.len()+index)).ok_or_else(||E::custom("unadmitted native report lint"))}
}
impl<'de> serde::de::DeserializeSeed<'de> for LintName{type Value=usize;fn deserialize<D:serde::Deserializer<'de>>(self,d:D)->Result<usize,D::Error>{d.deserialize_str(self)}}
struct ReportLints;
impl<'de> serde::de::Visitor<'de> for ReportLints{
 type Value=Self;fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("unique explicit native report lints")}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut seq:A)->Result<Self,A::Error>{let tree=crate::native_policy_roster::RAW_FILE_LINT_NAMES.len();let mut seen=[false;crate::native_policy_roster::RAW_FILE_LINT_NAMES.len()+EXCLUSIVE_TREE_REPORT_NAMES.len()];let mut count=0;let mut exclusive=false;while let Some(index)=seq.next_element_seed(LintName)?{if (index>=tree&&count!=0)||exclusive{return Err(serde::de::Error::custom("Tree report must be an exclusive explicit selection"))}exclusive=index>=tree;if seen[index]{return Err(serde::de::Error::custom("duplicate native report lint"))}seen[index]=true;count+=1;}if count==0{return Err(serde::de::Error::custom("empty native report lints"))}Ok(self)}
}
impl<'de> serde::Deserialize<'de> for ReportLints{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{d.deserialize_seq(Self)}}
struct NoReportExtra;
impl<'de> serde::Deserialize<'de> for NoReportExtra{fn deserialize<D:serde::Deserializer<'de>>(_:D)->Result<Self,D::Error>{Err(serde::de::Error::custom("extra native report usage field"))}}
struct ReportUsage;
impl<'de> serde::de::Visitor<'de> for ReportUsage{
 type Value=Self;fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("native report usage name/digest/line")}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut seq:A)->Result<Self,A::Error>{
  seq.next_element::<ReportString<3>>()?.ok_or_else(||serde::de::Error::custom("missing usage name"))?;
  seq.next_element::<ReportString<4>>()?.ok_or_else(||serde::de::Error::custom("missing usage digest"))?;
  let line=seq.next_element::<u32>()?.ok_or_else(||serde::de::Error::custom("missing usage line"))?;if line==0{return Err(serde::de::Error::custom("invalid usage line"))}
  let _:Option<NoReportExtra>=seq.next_element()?;Ok(self)
 }
}
impl<'de> serde::Deserialize<'de> for ReportUsage{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{d.deserialize_tuple(3,Self)}}
struct ReportUsageRows;
impl<'de> serde::de::Visitor<'de> for ReportUsageRows{
 type Value=Self;fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("native report usage rows")}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut seq:A)->Result<Self,A::Error>{while seq.next_element::<ReportUsage>()?.is_some(){}Ok(self)}
}
impl<'de> serde::Deserialize<'de> for ReportUsageRows{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{d.deserialize_seq(Self)}}
#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct PolicyDocument{
 schema:ReportString<1>,complete:bool,full_policy_parity:bool,baseline:bool,clean:bool,
 semantic_revision:ReportString<2>,source_revision:ReportString<2>,policy_revision:ReportString<2>,
 lints:ReportLints,text:ReportString<0>,allow_usage:ReportUsageRows,
}
fn policy_stdout(input:impl Read)->io::Result<Vec<u8>>{growing_bounded(input,MAX_POLICY_OUTPUT)}
fn validate_policy(bytes:&[u8],code:i32,baseline:bool)->io::Result<()>{
 let refused=||io::Error::new(io::ErrorKind::InvalidData,"native analysis did not return a complete matching report");
 if !matches!(code,0|1)||bytes.len()>MAX_POLICY_OUTPUT{return Err(refused())}
 let line=bytes.strip_suffix(b"\n").unwrap_or(bytes);if line.contains(&b'\n'){return Err(refused())}
 let report:PolicyDocument=serde_json::from_slice(line).map_err(|_|refused())?;
 if !report.complete||report.full_policy_parity||report.baseline!=baseline||report.clean!=(code==0){return Err(refused())}
 let _=(report.schema,report.semantic_revision,report.source_revision,report.policy_revision,report.lints,report.text,report.allow_usage);Ok(())
}
fn deliver_policy(response:Response,stdout:&mut impl Write,stderr:&mut impl Write,baseline:bool)->io::Result<u8>{
 stderr.write_all(&response.stderr)?;
 match response.status.code(){Some(code @ (0|1))=>{validate_policy(&response.stdout,code,baseline)?;stdout.write_all(&response.stdout)?;Ok(code as u8)},_=>Ok(2)}
}
/// Explicit report routes only. The actual dmbc client owns request admission,
/// source capture and exact page pins; this thin process client never parses it.
pub fn policy_cli(args:&[String],baseline:bool)->std::process::ExitCode{
 let result=(||->io::Result<u8>{let opts=options(args)?;let mode=if baseline{Mode::Baseline}else{Mode::Check};let mut command=Command::new(&opts.program);command.args(arguments_for(mode,&opts.request));let response=execute_command_for(command,OUTER_WATCHDOG,mode)?;deliver_policy(response,&mut io::stdout().lock(),&mut io::stderr().lock(),baseline)})();
 match result{Ok(code)=>std::process::ExitCode::from(code),Err(error)=>{eprintln!("analyze native report: {error}");std::process::ExitCode::from(2)}}
}

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

 fn generation_wire(clean:bool,committed:bool)->Vec<u8>{format!("{}\n{}\n",serde_json::json!({"schema":"native-generation-batch-v1","row":"generation_batch","status":"completed","clean":clean,"committed":committed,"cleanup_warnings":0}),serde_json::json!({"schema":"native-generation-v1","clean":clean,"committed":committed,"rows":[],"diagnostics":[],"changed":[],"cleanup":[]})).into_bytes()}
 #[test]fn native_generation_client_validates_completed_unclean_without_reparsing_the_request(){
  validate_generation(&generation_wire(true,false),0).unwrap();validate_generation(&generation_wire(false,true),1).unwrap();
  assert!(validate_generation(&generation_wire(false,true),0).is_err());
  let wire=generation_wire(true,false);let newline=wire.iter().position(|byte|*byte==b'\n').unwrap();
  assert!(validate_generation(&wire[..newline],0).is_err());
  let mut extra=wire.clone();extra.extend_from_slice(b"{}\n");assert!(validate_generation(&extra,0).is_err());
  let mismatch=String::from_utf8(wire).unwrap().replacen("\"committed\":false","\"committed\":true",1);assert!(validate_generation(mismatch.as_bytes(),0).is_err());
 }
 #[test]fn native_generation_client_preserves_query_limits_and_grows_only_for_received_metadata(){
  let bytes=vec![b'x';MAX_OUTPUT+1];assert_eq!(generation_stdout(bytes.as_slice()).unwrap(),bytes);
  assert_eq!(cli_stdout(bytes.as_slice()).unwrap_err().kind(),io::ErrorKind::InvalidData);
  assert_eq!(growing_bounded(&b"abcde"[..],4).unwrap_err().kind(),io::ErrorKind::InvalidData);
  assert_eq!(arguments_for(Mode::Generate,std::path::Path::new("literal \u{03b1}.json")),[OsString::from("generate"),OsString::from("literal \u{03b1}.json"),OsString::from("--jsonl")]);
 }

 #[cfg(any(windows,unix))]fn generation_status(code:i32)->ExitStatus{
  #[cfg(windows)]{use std::os::windows::process::ExitStatusExt;ExitStatus::from_raw(code as u32)}
  #[cfg(unix)]{use std::os::unix::process::ExitStatusExt;ExitStatus::from_raw(code<<8)}
 }
 #[cfg(any(windows,unix))]#[test]fn native_generation_client_delivers_complete_exit_one_and_discards_operational_partial_report(){
  let wire=generation_wire(false,true);let mut out=Vec::new();let mut err=Vec::new();
  assert_eq!(deliver_generation(Response{status:generation_status(1),stdout:wire.clone(),stderr:b"cleanup notice".to_vec()},&mut out,&mut err).unwrap(),1);assert_eq!(out,wire);assert_eq!(err,b"cleanup notice");
  out.clear();err.clear();assert_eq!(deliver_generation(Response{status:generation_status(2),stdout:generation_wire(true,false),stderr:b"typed failure".to_vec()},&mut out,&mut err).unwrap(),2);assert!(out.is_empty());assert_eq!(err,b"typed failure");
  let error=deliver_generation(Response{status:generation_status(0),stdout:b"{}\n".to_vec(),stderr:Vec::new()},&mut out,&mut err).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::InvalidData);assert!(out.is_empty());
 }

#[cfg(test)]mod policy_client_tests{
 use super::*;
 fn wire(clean:bool,baseline:bool)->Vec<u8>{let row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":baseline,"clean":clean,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["scheduler"],"text":"an actual ordered report\nwith retained α text", "allow_usage":[["scheduler","0123456789012345678901234567890123456789",2]]});format!("{row}\n").into_bytes()}
 #[test]fn native_policy_client_streams_exact_report_shapes_and_literal_command_routes(){
  validate_policy(&wire(true,false),0,false).unwrap();validate_policy(&wire(false,false),1,false).unwrap();validate_policy(&wire(true,true),0,true).unwrap();
  assert!(validate_policy(&wire(true,false),1,false).is_err());assert!(validate_policy(&wire(false,false),2,false).is_err());assert!(validate_policy(&wire(true,true),0,false).is_err());
  for(mode,command)in[(Mode::Check,"analyze-check"),(Mode::Baseline,"analyze-baseline")]{assert_eq!(arguments_for(mode,std::path::Path::new("literal α [request].json")),[OsString::from(command),OsString::from("literal α [request].json"),OsString::from("--jsonl")]);}
  assert_eq!(MAX_OUTPUT,524_288);assert_eq!(MAX_POLICY_OUTPUT,MAX_GENERATION_OUTPUT);
 }
 #[test]fn native_policy_client_refuses_incomplete_foreign_extra_unpinned_and_malformed_usage_without_inner_dom(){
  let valid:serde_json::Value=serde_json::from_slice(&wire(true,false)).unwrap();
  for change in 0..12{let mut row=valid.clone();match change{
   0=>row["complete"]=false.into(),1=>row["full_policy_parity"]=true.into(),2=>row["schema"]="foreign".into(),3=>row["source_revision"]="B".repeat(32).into(),4=>{row.as_object_mut().unwrap().remove("policy_revision");},5=>row["extra"]=true.into(),6=>row["lints"]=serde_json::json!([]),7=>row["lints"]=serde_json::json!(["scheduler","scheduler"]),8=>row["lints"]=serde_json::json!(["unported"]),9=>row["allow_usage"]=serde_json::json!([["scheduler","no digest",1]]),10=>row["allow_usage"]=serde_json::json!([["scheduler","",0]]),_=>row["allow_usage"]=serde_json::json!([["scheduler","",1,{}]])};assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,false).is_err(),"mutation {change}");}
  let mut extra=wire(true,false);extra.extend_from_slice(b"{}\n");assert!(validate_policy(&extra,0,false).is_err());
  let mut duplicate=String::from_utf8(wire(true,false)).unwrap();duplicate=duplicate.replacen("\"complete\":true","\"complete\":true,\"complete\":true",1);assert!(validate_policy(duplicate.as_bytes(),0,false).is_err());
 }
 #[test]fn native_policy_client_accepts_wide_usage_without_retaining_a_second_row_collection(){
  let mut row:serde_json::Value=serde_json::from_slice(&wire(true,false)).unwrap();row["allow_usage"]=serde_json::json!(vec![serde_json::json!(["scheduler","0123456789012345678901234567890123456789",2]);20_000]);let bytes=serde_json::to_vec(&row).unwrap();assert!(bytes.len()>MAX_OUTPUT);validate_policy(&bytes,0,false).unwrap();assert_eq!(policy_stdout(bytes.as_slice()).unwrap(),bytes);
  assert_eq!(cli_stdout(bytes.as_slice()).unwrap_err().kind(),io::ErrorKind::InvalidData);
 }
 #[cfg(any(windows,unix))]#[test]fn native_policy_client_delivers_validated_failures_and_never_operational_or_invalid_prefixes(){
  let failed=wire(false,false);let mut out=Vec::new();let mut err=Vec::new();
  assert_eq!(deliver_policy(Response{status:super::generation_status(1),stdout:failed.clone(),stderr:b"exact diagnostics".to_vec()},&mut out,&mut err,false).unwrap(),1);assert_eq!(out,failed);assert_eq!(err,b"exact diagnostics");
  out.clear();err.clear();assert_eq!(deliver_policy(Response{status:super::generation_status(2),stdout:wire(true,false),stderr:b"typed operational error".to_vec()},&mut out,&mut err,false).unwrap(),2);assert!(out.is_empty());assert_eq!(err,b"typed operational error");
  assert!(deliver_policy(Response{status:super::generation_status(0),stdout:b"{}\n".to_vec(),stderr:Vec::new()},&mut out,&mut err,false).is_err());assert!(out.is_empty());
 }
 #[test]fn native_policy_client_accepts_only_exclusive_hygiene_without_expanding_raw_roster(){
  let mut row:serde_json::Value=serde_json::from_slice(&wire(true,false)).unwrap();row["lints"]=serde_json::json!(["sys/hygiene"]);validate_policy(&serde_json::to_vec(&row).unwrap(),0,false).unwrap();
  row["baseline"]=true.into();validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).unwrap();
  for lints in [serde_json::json!(["sys/hygiene","scheduler"]),serde_json::json!(["scheduler","sys/hygiene"]),serde_json::json!(["sys/hygiene","sys/hygiene"]),serde_json::json!(["sys/hygiene_unported"])]{row["lints"]=lints;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).is_err());}
  assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"sys/hygiene"));assert_eq!(MAX_OUTPUT,524_288);assert_eq!(MAX_POLICY_OUTPUT,MAX_GENERATION_OUTPUT);
 }
 #[test]fn native_policy_client_admits_each_exact_exclusive_tree_report_and_rejects_every_mixed_order(){
  for name in EXCLUSIVE_TREE_REPORT_NAMES{let mut row:serde_json::Value=serde_json::from_slice(&wire(true,false)).unwrap();row["lints"]=serde_json::json!([name]);validate_policy(&serde_json::to_vec(&row).unwrap(),0,false).unwrap();row["baseline"]=true.into();validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).unwrap();
   for other in EXCLUSIVE_TREE_REPORT_NAMES.into_iter().chain(["scheduler"]){for names in [serde_json::json!([name,other]),serde_json::json!([other,name])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).is_err());}}
   assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&name));
  }assert_eq!(MAX_OUTPUT,524_288);assert_eq!(MAX_POLICY_OUTPUT,MAX_GENERATION_OUTPUT);
 }
 #[test]fn native_policy_client_keys_is_exact_exclusive_hard_report_without_raw_authority(){
  let mut row:serde_json::Value=serde_json::from_slice(&wire(false,false)).unwrap();row["lints"]=serde_json::json!(["sem/keys"]);validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).unwrap();row["clean"]=true.into();row["baseline"]=true.into();validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).unwrap();
  for names in [serde_json::json!(["sem/keys","scheduler"]),serde_json::json!(["scheduler","sem/keys"]),serde_json::json!(["sem/keys","sys/hygiene"]),serde_json::json!(["sem/keys","sem/keys"]),serde_json::json!(["sem/keys_unported"]),serde_json::json!(["sem/reads"]),serde_json::json!(["SEM/KEYS"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).is_err());}
  assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"sem/keys"));assert!(matches!(crate::keys_policy::metadata().policy,crate::lint::Policy::Hard));
  assert_eq!((MAX_OUTPUT,MAX_POLICY_OUTPUT,MAX_STDERR),(524_288,64*1024*1024,4_194_304));
 }

}

}
