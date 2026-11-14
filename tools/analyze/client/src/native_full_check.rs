//! Explicit opt-in full native CHECK client. It starts only the existing dmbc
//! client and never a parser, model, daemon, registry or compatibility fallback.
use super::{capture_command,policy_stdout_work,bounded,NativeReportWork,OUTER_WATCHDOG,MAX_STDERR};
use crate::{full_registry_check_wire::{Options,Terminal},selected_exclusions_wire::MAX_HEADER,report_work::Work};
use std::{io::{self,Write},path::PathBuf,process::Command};
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
#[derive(Debug,PartialEq,Eq)]struct Invocation{program:PathBuf,root:PathBuf,options:Options}
fn options(args:&[String])->io::Result<Invocation>{options_using(args,std::env::var_os("DQ_ALLOW_USAGE").is_some())}
fn options_using(args:&[String],usage_export:bool)->io::Result<Invocation>{
 let mut ordinary=vec!["analyze".to_owned()];let(mut program,mut explicit)=(None,false);let mut at=0;
 while at<args.len(){let arg=&args[at];at+=1;match arg.as_str(){
  "--native-full-registry"=>explicit=true,
  "--native-dmbc"=>{let path=PathBuf::from(args.get(at).ok_or_else(||invalid("--native-dmbc needs one absolute existing compiler executable"))?);at+=1;if !path.is_absolute()||program.replace(path).is_some(){return Err(invalid("--native-dmbc needs exactly one absolute executable"))}},
  _=>ordinary.push(arg.clone()),
 }}
 if !explicit{return Err(invalid("full registry native check needs explicit --native-full-registry"))}
 let parsed=crate::cli_arguments::parse(ordinary);if parsed.cmd!="check"{return Err(invalid("full registry adapter serves check only"))}
 if !parsed.lints.is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,"full native check v1 requires the entire registered selection; arbitrary --lint selection is not yet qualified"))}
 for flag in &parsed.flags{if !matches!(flag.as_str(),"--raw"|"--ci"|"--unused"|"--no-unused"|"--no-selftest"|"--no-cache"|"--rehash"){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("full native check has no exact implementation for {flag}; no compatibility fallback")))}}
 if !parsed.flags.iter().any(|f|f=="--no-selftest"){return Err(io::Error::new(io::ErrorKind::Unsupported,"full native check requires explicit --no-selftest until native fixture selftests are qualified"))}
 if usage_export{return Err(io::Error::new(io::ErrorKind::Unsupported,"full native check has no qualified DQ_ALLOW_USAGE export yet; no fallback"))}
 let root=std::path::absolute(crate::cli_arguments::find_root(parsed.root))?;
 let has=|name:&str|parsed.flags.iter().any(|flag|flag==name);
 Ok(Invocation{program:program.ok_or_else(||invalid("full native check needs --native-dmbc ABSOLUTE_EXE"))?,root,options:Options{raw:has("--raw"),ci:has("--ci"),unused:!has("--no-unused")}})
}
fn text<'a>(bytes:&'a[u8],status:i32,expected:Options,work:&NativeReportWork)->io::Result<&'a[u8]>{
 if !matches!(status,0|1){return Err(invalid("full native check failed before a completed report"))}
 let line=bytes.iter().take(MAX_HEADER).position(|b|*b==b'\n').ok_or_else(||invalid("full native check lacks a bounded terminal header"))?;
 work.temporary(0,MAX_HEADER.checked_mul(8).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;
 let terminal:Terminal=serde_json::from_slice(&bytes[..line]).map_err(io::Error::other)?;terminal.require(expected)?;
 let body=&bytes[line+1..];if terminal.clean!=(status==0)||terminal.report.length!=body.len()as u64||terminal.report.hash.0!=xxhash_rust::xxh3::xxh3_128(body){return Err(invalid("full native check body/status differs from its sealed actual report"))}Ok(body)
}
fn run(args:&[String],output:&mut impl Write,diagnostics:&mut impl Write)->io::Result<u8>{
 let invocation=options(args)?;let mut command=Command::new(invocation.program);command.arg("analyze-full-check").arg("--workspace").arg(invocation.root).arg("--no-selftest");
 if invocation.options.raw{command.arg("--raw");}if invocation.options.ci{command.arg("--ci");}if !invocation.options.unused{command.arg("--no-unused");}
 // Both no-cache and rehash request exact observations in this first native
 // adapter. They never permit a stale read or silently choose the old engine.
 let(status,captured,stderr)=capture_command(command,OUTER_WATCHDOG,policy_stdout_work,|input|bounded(input,MAX_STDERR))?;
 diagnostics.write_all(&stderr)?;
 let Some(code @ (0|1))=status.code()else{return Ok(if status.code()==Some(75){75}else{2})};
 let work=captured.policy_work.as_ref().ok_or_else(||invalid("full native check lost its physical output grant"))?;
 output.write_all(text(&captured.bytes,code,invocation.options,work)?)?;Ok(code as u8)
}
pub(super)fn cli(args:&[String])->std::process::ExitCode{match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>std::process::ExitCode::from(code),Err(error)=>{eprintln!("analyze native full check: {error}");std::process::ExitCode::from(2)}}}
#[cfg(test)]mod tests{
 use super::*;use crate::{full_registry_check_wire::{Schema,Scope},selected_exclusions_wire::{Frame,Seal,Hex128}};
 #[test]fn adapter_preserves_supported_flags_and_explicitly_refuses_unimplemented_modes(){
  let mut args=vec!["check".into(),"--native-full-registry".into(),"--native-dmbc".into(),if cfg!(windows){"E:/compiler/dmbc.exe".into()}else{"/compiler/dmbc".into()},"--root".into(),"actual-relative-root".into(),"--no-selftest".into(),"--raw".into(),"--ci".into(),"--no-unused".into(),"--no-cache".into(),"--rehash".into()];
  let parsed=options_using(&args,false).unwrap();assert_eq!(parsed.options,Options{raw:true,ci:true,unused:false});assert!(parsed.root.is_absolute());
  for flag in["--changed-only","--timing","--drop-declared"]{args.push(flag.into());assert_eq!(options_using(&args,false).unwrap_err().kind(),io::ErrorKind::Unsupported);args.pop();}
  args.extend(["--lint".into(),"scheduler".into()]);assert!(options_using(&args,false).unwrap_err().to_string().contains("registered selection"));
 }
 #[test]fn completed_transport_requires_exact_flags_status_hash_length_and_no_partial_body(){
  let body=b"actual sealed report\n";let expected=Options::default();let terminal=Terminal{schema:Schema::V1,scope:Scope::FullRegistry,complete:true,full_policy_parity:false,options:expected,frame:Frame{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,diagnostics:None,report:Seal{length:body.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(body))}};
  // These are codec DATA controls, never a native source/completion issuer.
  let mut wire=serde_json::to_vec(&terminal).unwrap();wire.push(b'\n');wire.extend_from_slice(body);assert_eq!(text(&wire,1,expected,&NativeReportWork::new()).unwrap(),body);
  assert!(text(&wire,0,expected,&NativeReportWork::new()).is_err());assert!(text(&wire,2,expected,&NativeReportWork::new()).is_err());wire.pop();assert!(text(&wire,1,expected,&NativeReportWork::new()).is_err());
 }
}
