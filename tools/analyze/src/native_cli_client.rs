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
struct Response{status:ExitStatus,stdout:Vec<u8>,stderr:Vec<u8>,policy_work:Option<NativeReportWork>}
struct StreamOutput{bytes:Vec<u8>,policy_work:Option<NativeReportWork>}
impl StreamOutput{fn plain(bytes:Vec<u8>)->Self{Self{bytes,policy_work:None}}}
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
 thread::Builder::new().name("native-query-stdout".into()).spawn(move||{let _=out_send.send((true,match mode{Mode::Query=>cli_stdout(stdout).map(StreamOutput::plain),Mode::Generate=>generation_stdout(stdout).map(StreamOutput::plain),Mode::Check|Mode::Baseline=>policy_stdout_work(stdout)}));})?;
 thread::Builder::new().name("native-query-stderr".into()).spawn(move||{let _=send.send((false,bounded(stderr,MAX_STDERR).map(StreamOutput::plain)));})?;
 let until=Instant::now()+watchdog;let mut out=None;let mut err=None;let mut status=None;
 loop{
  loop{match receive.try_recv(){Ok((is_out,result))=>{let bytes=result?;if is_out{out=Some(bytes)}else{err=Some(bytes)}},Err(mpsc::TryRecvError::Empty)=>break,Err(mpsc::TryRecvError::Disconnected)=>{if out.is_none()||err.is_none(){return Err(io::Error::new(io::ErrorKind::BrokenPipe,"native client output reader ended without a complete response"));}break}}}
  if status.is_none(){status=running.child.try_wait()?;}
  if status.is_some()&&out.is_some()&&err.is_some(){running.finished=true;let out=out.unwrap();let err=err.unwrap();return Ok(Response{status:status.unwrap(),stdout:out.bytes,stderr:err.bytes,policy_work:out.policy_work});}
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
const EXCLUSIVE_TREE_REPORT_NAMES:[&str;54]=["sys/hygiene","sys/resolvers","sys/tables","system_boundary","sem/keys","check_grep","sem/reads","untracked_inputs","cooldown","declaration_block","duplicate_input_key","interactions","latent","pollers","read_back","cap_bits","sys/dx_manual_fingerprint_log","sys/sfx","sys/requirements","sys/dx_string_names","sys/dx_constructor_shadow","sys/dx_look_side_effects","sys/expiry","sys/ui","tracked","tracked_tests","state_schema","lifecycle","sys/loot","instance_list","cache","sys/dx_ownership_forms","api","sys/fields","sys/appearance","decl","init","base_vars","requirement_bool","pool","player_link","untyped_member","weak_raw_read","rel_write_undeclared","untyped","doc_snippets","stored_refs","ownership","engine_layering","ui_actions","setter_publishes","op_order","sys/dx_reactive","lifeforms"];
struct LintName;
impl<'de> serde::de::Visitor<'de> for LintName{
 type Value=usize;
 fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("an admitted explicit native report name")}
 fn visit_str<E:serde::de::Error>(self,value:&str)->Result<usize,E>{crate::native_policy_roster::RAW_FILE_LINT_NAMES.iter().position(|name|*name==value).or_else(||EXCLUSIVE_TREE_REPORT_NAMES.iter().position(|name|*name==value).map(|index|crate::native_policy_roster::RAW_FILE_LINT_NAMES.len()+index)).ok_or_else(||E::custom("unadmitted native report lint"))}
}
impl<'de> serde::de::DeserializeSeed<'de> for LintName{type Value=usize;fn deserialize<D:serde::Deserializer<'de>>(self,d:D)->Result<usize,D::Error>{d.deserialize_str(self)}}
struct ReportLints{cohort:bool}
impl<'de> serde::de::Visitor<'de> for ReportLints{
 type Value=Self;fn expecting(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("unique explicit native report lints")}
 fn visit_seq<A:serde::de::SeqAccess<'de>>(self,mut seq:A)->Result<Self,A::Error>{
  use crate::native_policy_roster::{RAW_FILE_LINT_NAMES,SEMANTIC_READ_REPORT_COHORT};
  let tree=RAW_FILE_LINT_NAMES.len();
  let mut seen=[false;RAW_FILE_LINT_NAMES.len()+EXCLUSIVE_TREE_REPORT_NAMES.len()];
  let mut count=0;
  let mut tree_count=0;
  while let Some(index)=seq.next_element_seed(LintName)?{
   if seen[index]{return Err(serde::de::Error::custom("duplicate native report lint"))}
   seen[index]=true;
   count+=1;
   if index>=tree{tree_count+=1;}
  }
  if count==0{return Err(serde::de::Error::custom("empty native report lints"))}
  let cohort=count==SEMANTIC_READ_REPORT_COHORT.len()&&SEMANTIC_READ_REPORT_COHORT.iter().all(|name|{
   EXCLUSIVE_TREE_REPORT_NAMES.iter().position(|candidate|candidate==name).is_some_and(|index|seen[tree+index])
  });
  if tree_count!=0&&count!=1&&!cohort{return Err(serde::de::Error::custom("unissued mixed native report selection"))}
  Ok(Self{cohort})
 }
}
impl<'de> serde::Deserialize<'de> for ReportLints{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{d.deserialize_seq(Self{cohort:false})}}
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
// SAME existing metadata allowance; physical old/new backing and later parser
// scratch are admitted before growth. This is not a native/source counter.
struct NativeReportWork{slots:std::cell::RefCell<[usize;3]>,denied:std::cell::Cell<bool>}
impl NativeReportWork{fn new()->Self{Self{slots:std::cell::RefCell::new([0;3]),denied:std::cell::Cell::new(false)}}fn for_buffer(capacity:usize)->io::Result<Self>{let work=Self::new();crate::policy_finish::admitted::Work::temporary(&work,1,capacity)?;Ok(work)}}
impl crate::policy_finish::admitted::Work for NativeReportWork{
 fn checkpoint(&self)->io::Result<()>{if self.denied.get(){Err(io::ErrorKind::OutOfMemory.into())}else{Ok(())}}
 fn reserve(&self,n:usize)->io::Result<()>{let current=self.slots.borrow()[2];self.temporary(2,current.checked_add(n).ok_or_else(||self.overflow())?)}
 fn temporary(&self,slot:usize,n:usize)->io::Result<()>{self.checkpoint()?;let mut slots=self.slots.borrow_mut();if slot>=slots.len(){return Err(self.overflow())}let previous=slots[slot];let required=n.max(previous);let other=slots.iter().enumerate().filter(|(i,_)|*i!=slot).try_fold(0usize,|sum,(_,n)|sum.checked_add(*n)).ok_or_else(||self.overflow())?;if required.checked_add(other).is_none_or(|n|n>MAX_POLICY_OUTPUT){return Err(self.overflow())}slots[slot]=required;Ok(())}
 fn overflow(&self)->io::Error{self.denied.set(true);io::Error::new(io::ErrorKind::OutOfMemory,"native report physical transient envelope exhausted")}
}
fn policy_stdout_work(mut input:impl Read)->io::Result<StreamOutput>{use crate::policy_finish::admitted::Work;let work=NativeReportWork::new();let mut bytes=Vec::new();let mut chunk=[0u8;8192];loop{let count=input.read(&mut chunk)?;if count==0{return Ok(StreamOutput{bytes,policy_work:Some(work)})}let needed=bytes.len().checked_add(count).filter(|n|*n<=MAX_POLICY_OUTPUT).ok_or_else(||work.overflow())?;if needed>bytes.capacity(){let target=needed.max(bytes.capacity().saturating_mul(2)).max(8192);let peak=target.checked_mul(4).and_then(|n|n.checked_add(bytes.capacity())).and_then(|n|n.checked_add(64)).ok_or_else(||work.overflow())?;work.temporary(1,peak)?;bytes.try_reserve_exact(target-bytes.len()).map_err(|_|work.overflow())?;if bytes.capacity()>target.saturating_mul(4){return Err(work.overflow())}}bytes.extend_from_slice(&chunk[..count]);}}
#[cfg(test)]fn policy_stdout(input:impl Read)->io::Result<Vec<u8>>{policy_stdout_work(input).map(|out|out.bytes)}
#[cfg(test)]fn validate_policy(bytes:&[u8],code:i32,baseline:bool)->io::Result<()>{let work=NativeReportWork::for_buffer(bytes.len())?;validate_policy_work(bytes,code,baseline,&work)}
fn validate_policy_work(bytes:&[u8],code:i32,baseline:bool,work:&NativeReportWork)->io::Result<()>{
 use crate::policy_finish::admitted::Work;
 work.temporary(0,bytes.len().checked_mul(4).and_then(|n|n.checked_add(65_536)).ok_or_else(||work.overflow())?)?;
 if crate::policy_finish::derived_wire::has_derived_schema(bytes,work)?{if baseline||!matches!(code,0|1){return Err(invalid("native Derived analysis did not return a complete matching report"))}crate::policy_finish::derived_wire::validate(bytes,code==0,work)?;return Ok(())}
 validate_legacy_policy(bytes,code,baseline).map(|_|())
}
fn validate_legacy_policy(bytes:&[u8],code:i32,baseline:bool)->io::Result<ReportLints>{
 let refused=||io::Error::new(io::ErrorKind::InvalidData,"native analysis did not return a complete matching report");
 if !matches!(code,0|1)||bytes.len()>MAX_POLICY_OUTPUT{return Err(refused())}
 let line=bytes.strip_suffix(b"\n").unwrap_or(bytes);if line.contains(&b'\n'){return Err(refused())}
 let report:PolicyDocument=serde_json::from_slice(line).map_err(|_|refused())?;
 if !report.complete||report.full_policy_parity||report.baseline!=baseline||report.clean!=(code==0)||(baseline&&report.lints.cohort){return Err(refused())}
 let _=(report.schema,report.semantic_revision,report.source_revision,report.policy_revision,report.text,report.allow_usage);Ok(report.lints)
}
fn deliver_policy(response:Response,stdout:&mut impl Write,stderr:&mut impl Write,baseline:bool)->io::Result<u8>{
 stderr.write_all(&response.stderr)?;
 match response.status.code(){Some(code @ (0|1))=>{let work=response.policy_work.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"native report lost its actual output allowance"))?;validate_policy_work(&response.stdout,code,baseline,work)?;stdout.write_all(&response.stdout)?;Ok(code as u8)},_=>Ok(2)}
}
/// Explicit report routes only. The actual dmbc client owns request admission,
/// source capture and exact page pins; this thin process client never parses it.
pub fn policy_cli(args:&[String],baseline:bool)->std::process::ExitCode{
 let result=(||->io::Result<u8>{let opts=options(args)?;let mode=if baseline{Mode::Baseline}else{Mode::Check};let mut command=Command::new(&opts.program);command.args(arguments_for(mode,&opts.request));let response=execute_command_for(command,OUTER_WATCHDOG,mode)?;deliver_policy(response,&mut io::stdout().lock(),&mut io::stderr().lock(),baseline)})();
 match result{Ok(code)=>std::process::ExitCode::from(code),Err(error)=>{eprintln!("analyze native report: {error}");std::process::ExitCode::from(2)}}
}

#[derive(Debug)]
struct WorkspaceCheck {
    program: PathBuf,
    root: PathBuf,
    ci: bool,
    raw: bool,
}

fn workspace_check_options(args: &[String]) -> io::Result<WorkspaceCheck> {
    if args.first().map(String::as_str) != Some("check") {
        return Err(invalid("--native-dmbc is supported only for check"));
    }
    let mut program = None;
    let mut root_seen = false;
    let mut ordinary = vec!["analyze".to_owned(), "check".to_owned()];
    let mut rest = args[1..].iter();
    while let Some(arg) = rest.next() {
        match arg.as_str() {
            "--native-dmbc" => {
                let value = rest.next().ok_or_else(|| invalid("--native-dmbc requires an absolute executable"))?;
                let path = PathBuf::from(value);
                if !path.is_absolute() || program.replace(path).is_some() {
                    return Err(invalid("--native-dmbc requires exactly one absolute executable"));
                }
            }
            "--root" => {
                let value = rest.next().filter(|s| !s.is_empty() && !s.starts_with("--"))
                    .ok_or_else(|| invalid("--root requires a directory"))?;
                if root_seen {
                    return Err(invalid("--root accepts one directory"));
                }
                root_seen = true;
                ordinary.extend([arg.clone(), value.clone()]);
            }
            _ => ordinary.push(arg.clone()),
        }
    }
    let args = crate::cli_arguments::parse(ordinary);
    if !crate::native_policy_roster::is_semantic_read_report_cohort(&args.lints) {
        return Err(invalid("--native-dmbc requires exactly sem/reads, untracked_inputs and setter_publishes"));
    }
    let mut selftests_disabled = false;
    let mut ci = false;
    let mut raw = false;
    for flag in args.flags {
        let selected = match flag.as_str() {
            "--no-selftest" => &mut selftests_disabled,
            "--ci" => &mut ci,
            "--raw" => &mut raw,
            _ => return Err(invalid("native workspace check supports only --lint, --root, --ci, --raw and --no-selftest")),
        };
        if std::mem::replace(selected, true) {
            return Err(invalid("duplicate native workspace check option"));
        }
    }
    if !selftests_disabled {
        return Err(invalid("native workspace check requires explicit --no-selftest"));
    }
    // Resolve against cwd without resolving symlinks. The native request
    // owner separately resolves and validates the physical source root.
    let root = std::path::absolute(crate::cli_arguments::find_root(args.root))?;
    let program = program.ok_or_else(|| invalid("expected --native-dmbc ABSOLUTE_EXE"))?;
    Ok(WorkspaceCheck { program, root, ci, raw })
}

fn workspace_check_text(bytes: &[u8], code: i32, work: &NativeReportWork) -> io::Result<String> {
    use crate::policy_finish::admitted::Work;
    // Fund the decoded text and parser scratch before either pass. This is the
    // same physical allowance as the explicit JSON report client.
    work.temporary(0, bytes.len().checked_mul(4).and_then(|n| n.checked_add(65_536))
        .ok_or_else(|| work.overflow())?)?;
    if !validate_legacy_policy(bytes, code, false)?.cohort {
        return Err(invalid("native workspace check did not return the requested policy cohort"));
    }
    #[derive(serde::Deserialize)]
    struct Text {
        text: String,
    }
    serde_json::from_slice::<Text>(bytes).map(|report| report.text).map_err(io::Error::other)
}

fn run_workspace_check(args: &[String], stdout: &mut impl Write, stderr: &mut impl Write) -> io::Result<u8> {
    let options = workspace_check_options(args)?;
    let mut command = Command::new(&options.program);
    command.args(["analyze-check", "--workspace"]).arg(options.root).arg("--jsonl");
    if options.ci {
        command.arg("--ci");
    }
    if options.raw {
        command.arg("--raw");
    }
    let response = execute_command_for(command, OUTER_WATCHDOG, Mode::Check)?;
    stderr.write_all(&response.stderr)?;
    let Some(code @ (0 | 1)) = response.status.code() else {
        return Ok(2);
    };
    let work = response.policy_work.as_ref()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "native report lost its actual output allowance"))?;
    let text = workspace_check_text(&response.stdout, code, work)?;
    stdout.write_all(text.as_bytes())?;
    Ok(code as u8)
}

/// An explicit opt-in to one resident policy cohort. A recognized opt-in
/// returns a verdict or a refusal before the legacy engine can start.
pub fn workspace_check(args: &[String]) -> Option<std::process::ExitCode> {
    if !args.iter().any(|arg| arg == "--native-dmbc" || arg.starts_with("--native-dmbc=")) {
        return None;
    }
    let result = run_workspace_check(args, &mut io::stdout().lock(), &mut io::stderr().lock());
    Some(match result {
        Ok(code) => std::process::ExitCode::from(code),
        Err(error) => {
            eprintln!("analyze native workspace check: {error}");
            std::process::ExitCode::from(2)
        }
    })
}

#[cfg(test)]
mod workspace_check_tests {
    use super::*;

    #[test]
    fn normal_check_only_accepts_the_exact_opt_in_cohort_and_supported_flags() {
        let root = std::env::current_dir().unwrap();
        let mut args = vec![
            "check".into(), "--lint".into(), "setter_publishes,sem/reads".into(),
            "untracked_inputs".into(), "--no-selftest".into(), "--ci".into(),
            "--raw".into(), "--native-dmbc".into(), root.join("dmbc binary").to_string_lossy().into_owned(),
            "--root".into(), root.to_string_lossy().into_owned(),
        ];
        let parsed = workspace_check_options(&args).unwrap();
        assert_eq!(parsed.root, root);
        assert_eq!(parsed.program, root.join("dmbc binary"));
        assert!(parsed.ci && parsed.raw);
        for unsupported in ["--changed-only", "--timing", "--no-cache", "--unused"] {
            args.push(unsupported.into());
            assert!(workspace_check_options(&args).is_err(), "{unsupported}");
            args.pop();
        }
        let mut bad = args.clone();
        bad.remove(4);
        assert!(workspace_check_options(&bad).is_err(), "legacy selftests must be explicitly disabled");
        let mut bad = args.clone();
        bad[0] = "baseline".into();
        assert!(workspace_check_options(&bad).is_err());
        let mut bad = args.clone();
        bad[3] = "scheduler".into();
        assert!(workspace_check_options(&bad).is_err());
        args.pop();
        assert!(workspace_check_options(&args).is_err(), "missing root cannot be silently inferred");
        assert!(workspace_check(&["check".into()]).is_none());
    }

    #[test]
    fn normal_check_decodes_only_a_valid_complete_matching_text_report() {
        let text = "line 1\nquoted \"field\"\tα\n";
        let mut row = serde_json::json!({
            "schema": "native-analyze-report-v1", "complete": true, "full_policy_parity": false,
            "baseline": false, "clean": false, "semantic_revision": "a".repeat(32),
            "source_revision": "b".repeat(32), "policy_revision": "c".repeat(32),
            "lints": ["sem/reads", "untracked_inputs", "setter_publishes"],
            "text": text, "allow_usage": []
        });
        let bytes = serde_json::to_vec(&row).unwrap();
        assert_eq!(workspace_check_text(&bytes, 1, &NativeReportWork::new()).unwrap(), text);
        assert!(workspace_check_text(&bytes, 0, &NativeReportWork::new()).is_err());
        row["lints"] = serde_json::json!(["sem/reads"]);
        let bytes = serde_json::to_vec(&row).unwrap();
        assert!(workspace_check_text(&bytes, 1, &NativeReportWork::new()).is_err());
    }
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
  assert_eq!(deliver_generation(Response{status:generation_status(1),stdout:wire.clone(),stderr:b"cleanup notice".to_vec(),policy_work:None},&mut out,&mut err).unwrap(),1);assert_eq!(out,wire);assert_eq!(err,b"cleanup notice");
  out.clear();err.clear();assert_eq!(deliver_generation(Response{status:generation_status(2),stdout:generation_wire(true,false),stderr:b"typed failure".to_vec(),policy_work:None},&mut out,&mut err).unwrap(),2);assert!(out.is_empty());assert_eq!(err,b"typed failure");
  let error=deliver_generation(Response{status:generation_status(0),stdout:b"{}\n".to_vec(),stderr:Vec::new(),policy_work:None},&mut out,&mut err).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::InvalidData);assert!(out.is_empty());
 }

#[cfg(test)]mod policy_client_tests{
 use super::*;
 fn wire(clean:bool,baseline:bool)->Vec<u8>{let row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":baseline,"clean":clean,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["scheduler"],"text":"an actual ordered report\nwith retained α text", "allow_usage":[["scheduler","0123456789012345678901234567890123456789",2]]});format!("{row}\n").into_bytes()}
 #[test]fn native_policy_client_accepts_only_the_complete_check_only_semantic_read_cohort(){
  let mut row:serde_json::Value=serde_json::from_slice(&wire(false,false)).unwrap();
  for names in [["sem/reads","untracked_inputs","setter_publishes"],["setter_publishes","sem/reads","untracked_inputs"]]{
   row["lints"]=serde_json::json!(names);
   validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).unwrap();
  }
  row["baseline"]=true.into();
  assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,true).is_err());
  row["baseline"]=false.into();
  for names in [
   serde_json::json!(["sem/reads","setter_publishes"]),
   serde_json::json!(["sem/reads","untracked_inputs","scheduler"]),
   serde_json::json!(["sem/reads","untracked_inputs","setter_publishes","lifeforms"]),
   serde_json::json!(["sem/reads","sem/reads","untracked_inputs"]),
  ]{
   row["lints"]=names;
   assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());
  }
 }
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
  assert_eq!(deliver_policy(Response{status:super::generation_status(1),stdout:failed.clone(),stderr:b"exact diagnostics".to_vec(),policy_work:Some(NativeReportWork::for_buffer(failed.capacity()).unwrap())},&mut out,&mut err,false).unwrap(),1);assert_eq!(out,failed);assert_eq!(err,b"exact diagnostics");
  out.clear();err.clear();assert_eq!(deliver_policy(Response{status:super::generation_status(2),stdout:wire(true,false),stderr:b"typed operational error".to_vec(),policy_work:None},&mut out,&mut err,false).unwrap(),2);assert!(out.is_empty());assert_eq!(err,b"typed operational error");
  assert!(deliver_policy(Response{status:super::generation_status(0),stdout:b"{}\n".to_vec(),stderr:Vec::new(),policy_work:Some(NativeReportWork::for_buffer(3).unwrap())},&mut out,&mut err,false).is_err());assert!(out.is_empty());
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
  for names in [serde_json::json!(["sem/keys","scheduler"]),serde_json::json!(["scheduler","sem/keys"]),serde_json::json!(["sem/keys","sys/hygiene"]),serde_json::json!(["sem/keys","sem/keys"]),serde_json::json!(["sem/keys_unported"]),serde_json::json!(["sem/reads_unported"]),serde_json::json!(["SEM/KEYS"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).is_err());}
  assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"sem/keys"));assert!(matches!(crate::keys_policy::metadata().policy,crate::lint::Policy::Hard));
  assert_eq!((MAX_OUTPUT,MAX_POLICY_OUTPUT,MAX_STDERR),(524_288,64*1024*1024,4_194_304));
 }

 #[test]fn native_policy_client_check_grep_is_exact_exclusive_with_same_report_schema(){
  let mut row:serde_json::Value=serde_json::from_slice(&wire(false,false)).unwrap();row["lints"]=serde_json::json!(["check_grep"]);validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).unwrap();row["clean"]=true.into();row["baseline"]=true.into();validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).unwrap();
  for names in [serde_json::json!(["check_grep","scheduler"]),serde_json::json!(["scheduler","check_grep"]),serde_json::json!(["check_grep","sem/keys"]),serde_json::json!(["check_grep","check_grep"]),serde_json::json!(["check-grep"]),serde_json::json!(["check_grep/missing"]),serde_json::json!(["CHECK_GREP"]),serde_json::json!(["sem/reads_unported"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,true).is_err());}
  assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"check_grep"));
 }



#[test]fn complete_collectors_use_only_exclusive_existing_whole_report_route(){for name in ["tracked","tracked_tests","state_schema","lifecycle","sys/loot","instance_list","cache","sys/dx_ownership_forms","api","sys/fields","sys/appearance"]{assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&name));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&name));let mut value:serde_json::Value=serde_json::from_slice(&wire(false,false)).unwrap();value["lints"]=serde_json::json!([name]);validate_policy(&serde_json::to_vec(&value).unwrap(),1,false).unwrap();for names in [serde_json::json!([name,"scheduler"]),serde_json::json!(["scheduler",name]),serde_json::json!([name,name]),serde_json::json!([format!("{name}_unported")])]{value["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&value).unwrap(),0,false).is_err());}}}

#[test]fn exact_raw_tree_names_use_exclusive_report_domain_without_expanding_raw_file_authority(){for name in ["cooldown","declaration_block","duplicate_input_key","interactions","latent","pollers","read_back","cap_bits","sys/dx_manual_fingerprint_log","sys/sfx","sys/requirements","sys/dx_string_names","sys/dx_constructor_shadow","sys/dx_look_side_effects","sys/expiry","sys/ui"]{assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&name));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&name));let mut row:serde_json::Value=serde_json::from_slice(&wire(false,false)).unwrap();row["lints"]=serde_json::json!([name]);validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).unwrap();for names in [serde_json::json!([name,"scheduler"]),serde_json::json!(["scheduler",name]),serde_json::json!([name,name]),serde_json::json!([format!("{name}_unported")])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),0,false).is_err());}}}
}

}

#[cfg(test)]mod semantic_report_tests{use super::*;#[test]fn exact_semantic_reports_are_exclusive_and_do_not_expand_raw_roles(){for name in ["sem/reads","untracked_inputs"]{assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&name));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&name));}assert!(matches!(crate::sem_reads_policy::metadata().policy,crate::lint::Policy::Hard));assert!(matches!(crate::untracked_inputs_policy::metadata().policy,crate::lint::Policy::Hard));}}

#[cfg(test)]mod decl_report_tests{use super::*;#[test]fn exact_decl_report_is_exclusive_and_does_not_promote_raw_or_hard_roles(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"decl"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"decl"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["decl"],"text":"actual completed declaration report\n","allow_usage":[]});row["lints"]=serde_json::json!(["decl"]);assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["decl","scheduler"]),serde_json::json!(["scheduler","decl"]),serde_json::json!(["decl","sem/reads"]),serde_json::json!(["decl","decl"]),serde_json::json!(["BASE_VARS"]),serde_json::json!(["decl/unported"]) ]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod init_report_tests{use super::*;#[test]fn exact_init_report_is_exclusive_and_does_not_promote_raw_or_hard_roles(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"init"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"init"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["init"],"text":"actual completed initaration report\n","allow_usage":[]});row["lints"]=serde_json::json!(["init"]);assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["init","scheduler"]),serde_json::json!(["scheduler","init"]),serde_json::json!(["init","sem/reads"]),serde_json::json!(["init","init"]),serde_json::json!(["BASE_VARS"]),serde_json::json!(["init/unported"]) ]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod base_vars_report_tests{use super::*;#[test]fn exact_base_vars_report_is_exclusive_and_does_not_promote_raw_or_hard_roles(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"base_vars"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"base_vars"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["base_vars"],"text":"actual completed base_varsaration report\n","allow_usage":[]});row["lints"]=serde_json::json!(["base_vars"]);assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["base_vars","scheduler"]),serde_json::json!(["scheduler","base_vars"]),serde_json::json!(["base_vars","sem/reads"]),serde_json::json!(["base_vars","base_vars"]),serde_json::json!(["BASE_VARS"]),serde_json::json!(["base_vars/unported"]) ]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod requirement_bool_report_tests{use super::*;#[test]fn exact_requirement_bool_report_is_exclusive_and_does_not_promote_raw_or_hard_roles(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"requirement_bool"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"requirement_bool"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["requirement_bool"],"text":"actual completed requirement_boolaration report\n","allow_usage":[]});row["lints"]=serde_json::json!(["requirement_bool"]);assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["requirement_bool","scheduler"]),serde_json::json!(["scheduler","requirement_bool"]),serde_json::json!(["requirement_bool","sem/reads"]),serde_json::json!(["requirement_bool","requirement_bool"]),serde_json::json!(["REQUIREMENT_BOOL"]),serde_json::json!(["requirement_bool/unported"]) ]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod player_link_report_tests{use super::*;#[test]fn exact_player_link_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"player_link"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"player_link"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["player_link"],"text":"actual completed player-link report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["player_link","scheduler"]),serde_json::json!(["scheduler","player_link"]),serde_json::json!(["player_link","sem/reads"]),serde_json::json!(["player_link","player_link"]),serde_json::json!(["PLAYER_LINK"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod untyped_member_report_tests{use super::*;#[test]fn exact_untyped_member_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"untyped_member"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"untyped_member"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["untyped_member"],"text":"actual completed untyped-member report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["untyped_member","scheduler"]),serde_json::json!(["scheduler","untyped_member"]),serde_json::json!(["untyped_member","sem/reads"]),serde_json::json!(["untyped_member","untyped_member"]),serde_json::json!(["UNTYPED_MEMBER"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod weak_raw_read_report_tests{use super::*;#[test]fn exact_weak_raw_read_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"weak_raw_read"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"weak_raw_read"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["weak_raw_read"],"text":"actual completed weak-raw-read report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["weak_raw_read","scheduler"]),serde_json::json!(["scheduler","weak_raw_read"]),serde_json::json!(["weak_raw_read","sem/reads"]),serde_json::json!(["weak_raw_read","weak_raw_read"]),serde_json::json!(["WEAK_RAW_READ"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod rel_write_undeclared_report_tests{use super::*;#[test]fn exact_rel_write_undeclared_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"rel_write_undeclared"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"rel_write_undeclared"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["rel_write_undeclared"],"text":"actual completed rel-write report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["rel_write_undeclared","scheduler"]),serde_json::json!(["scheduler","rel_write_undeclared"]),serde_json::json!(["rel_write_undeclared","sem/reads"]),serde_json::json!(["rel_write_undeclared","rel_write_undeclared"]),serde_json::json!(["REL_WRITE"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod untyped_report_tests{use super::*;#[test]fn exact_untyped_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"untyped"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"untyped"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["untyped"],"text":"actual completed untyped report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["untyped","scheduler"]),serde_json::json!(["scheduler","untyped"]),serde_json::json!(["untyped","sem/reads"]),serde_json::json!(["untyped","untyped"]),serde_json::json!(["UNTYPED"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod stored_refs_report_tests{use super::*;#[test]fn exact_stored_refs_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"stored_refs"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"stored_refs"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["stored_refs"],"text":"actual completed stored_refs report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["stored_refs","engine_layering"]),serde_json::json!(["stored_refs","scheduler"]),serde_json::json!(["scheduler","stored_refs"]),serde_json::json!(["stored_refs","sem/reads"]),serde_json::json!(["stored_refs","stored_refs"]),serde_json::json!(["STORED_REFS"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod engine_layering_report_tests{use super::*;#[test]fn exact_engine_layering_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"engine_layering"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"engine_layering"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["engine_layering"],"text":"actual completed engine_layering report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["engine_layering","scheduler"]),serde_json::json!(["scheduler","engine_layering"]),serde_json::json!(["engine_layering","sem/reads"]),serde_json::json!(["engine_layering","engine_layering"]),serde_json::json!(["ENGINE_LAYERING"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod ui_actions_report_tests{use super::*;
 #[test]fn ui_actions_completed_report_is_exactly_exclusive_and_never_raw_file(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"ui_actions"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"ui_actions"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["ui_actions"],"text":"whole actual original UI report\n","allow_usage":[]});validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).unwrap();for names in [serde_json::json!(["ui_actions","scheduler"]),serde_json::json!(["scheduler","ui_actions"]),serde_json::json!(["ui_actions","ui_actions"]),serde_json::json!(["UI_ACTIONS"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}
}

#[cfg(test)]mod setter_publishes_report_tests{use super::*;#[test]fn exact_setter_publishes_report_is_exclusive_hard_and_never_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"setter_publishes"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"setter_publishes"));assert!(matches!(crate::setter_publication_policy::metadata().policy,crate::lint::Policy::Hard));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["setter_publishes"],"text":"actual completed setter report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in[serde_json::json!(["setter_publishes","sem/reads"]),serde_json::json!(["setter_publishes","scheduler"]),serde_json::json!(["scheduler","setter_publishes"]),serde_json::json!(["setter_publishes","setter_publishes"]),serde_json::json!(["SETTER_PUBLISHES"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}


#[cfg(test)]mod op_order_report_tests{use super::*;
#[test]fn exact_op_order_ceiling_report_is_exclusive_and_does_not_expand_raw_file_authority(){
 assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"op_order"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"op_order"));
 assert!(matches!(crate::op_order_policy::META.policy,crate::lint::Policy::Ceilings{..}));assert_eq!(crate::captured_raw_tree_pages::Policy::OpOrder.source_visits(),2);
 assert!(!crate::captured_raw_tree_pages::Policy::OpOrder.selected_source_phase(0));assert!(crate::captured_raw_tree_pages::Policy::OpOrder.selected_source_phase(1));
}
}

#[cfg(test)]mod sys_reactive_report_tests{use super::*;#[test]fn exact_sys_reactive_sites_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"sys/dx_reactive"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"sys/dx_reactive"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["sys/dx_reactive"],"text":"actual completed Sys reactive report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["sys/dx_reactive","scheduler"]),serde_json::json!(["scheduler","sys/dx_reactive"]),serde_json::json!(["sys/dx_reactive","sem/reads"]),serde_json::json!(["sys/dx_reactive","sys/dx_reactive"]),serde_json::json!(["SYS/DX_REACTIVE"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod lifeforms_report_tests{use super::*;#[test]fn exact_lifeforms_hard_report_is_exclusive_and_not_raw(){assert!(EXCLUSIVE_TREE_REPORT_NAMES.contains(&"lifeforms"));assert!(!crate::native_policy_roster::RAW_FILE_LINT_NAMES.contains(&"lifeforms"));let mut row=serde_json::json!({"schema":"native-analyze-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32),"lints":["lifeforms"],"text":"actual completed Lifeforms report\n","allow_usage":[]});assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_ok());for names in [serde_json::json!(["lifeforms","scheduler"]),serde_json::json!(["scheduler","lifeforms"]),serde_json::json!(["lifeforms","sem/reads"]),serde_json::json!(["lifeforms","lifeforms"]),serde_json::json!(["LIFEFORMS"])]{row["lints"]=names;assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}}}

#[cfg(test)]mod derived_report_client_controls{
 use super::*;
 fn wire(failed:bool)->Vec<u8>{let preparation=if failed{serde_json::json!({"kind":"failed_root_one_shot","failure":{"kind":"Infrastructure","message":"actual root open failed"},"io_kind":"NotFound","os_code":2})}else{serde_json::json!({"kind":"current","semantic_revision":"a".repeat(32),"source_revision":"b".repeat(32),"policy_revision":"c".repeat(32)})};let row=serde_json::json!({"schema":"native-analyze-derived-report-v1","complete":true,"full_policy_parity":false,"baseline":false,"clean":false,"preparation":preparation,"lints":["derived_reads"],"text":"an exact selected report\n","allow_usage":[["derived_reads","0123456789012345678901234567890123456789",2]]});format!("{row}\n").into_bytes()}
 #[test]fn thin_client_accepts_only_honest_exclusive_current_or_failed_root_derived_data(){for failed in [false,true]{let bytes=wire(failed);validate_policy(&bytes,1,false).unwrap();assert!(validate_policy(&bytes,0,false).is_err());assert!(validate_policy(&bytes,1,true).is_err());let mut row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();row["lints"]=serde_json::json!(["derived_reads","scheduler"]);assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());row["lints"]=serde_json::json!(["derived_reads"]);row["preparation"]["kind"]="foreign".into();assert!(validate_policy(&serde_json::to_vec(&row).unwrap(),1,false).is_err());}assert!(!EXCLUSIVE_TREE_REPORT_NAMES.contains(&"derived_reads"),"no old-schema or default roster promotion");}
 #[test]fn thin_client_report_quota_precedes_decode_and_fresh_operation_recovers_without_reset(){use crate::policy_finish::admitted::Work;let bytes=wire(false);let denied=NativeReportWork::for_buffer(MAX_POLICY_OUTPUT).unwrap();assert_eq!(validate_policy_work(&bytes,1,false,&denied).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(denied.checkpoint().is_err());validate_policy(&bytes,1,false).unwrap();}
}
