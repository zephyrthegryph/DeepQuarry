//! Explicit opt-in full native CHECK client. It starts only the existing dmbc
//! client and never a parser, model, daemon, registry or compatibility fallback.
use super::{capture_command,policy_stdout_work,bounded,NativeReportWork,OUTER_WATCHDOG,MAX_STDERR};
use crate::{full_registry_check_wire::{Options,Terminal},selected_exclusions_wire::MAX_HEADER,full_registry_check_selection_wire::SelectionBinding,report_work::Work};
use std::{io::{self,Write},path::PathBuf,process::Command};
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
#[derive(Debug,PartialEq,Eq)]struct Invocation{program:PathBuf,root:PathBuf,options:Options,selectors:Vec<String>,selftests:bool,changed:bool,timing:bool,timing_only:bool}
fn options(args:&[String])->io::Result<Invocation>{options_using(args,std::env::var("DQ_ALLOW_USAGE").is_ok())}
fn options_using(args:&[String],usage_export:bool)->io::Result<Invocation>{
 let mut ordinary=vec!["analyze".to_owned()];let(mut program,mut explicit)=(None,false);let mut at=0;
 while at<args.len(){let arg=&args[at];at+=1;match arg.as_str(){
  "--native-full-registry"=>explicit=true,
  "--native-dmbc"=>{let path=PathBuf::from(args.get(at).ok_or_else(||invalid("--native-dmbc needs one absolute existing compiler executable"))?);at+=1;if !path.is_absolute()||program.replace(path).is_some(){return Err(invalid("--native-dmbc needs exactly one absolute executable"))}},
  _=>ordinary.push(arg.clone()),
 }}
 if !explicit{return Err(invalid("full registry native check needs explicit --native-full-registry"))}
 let parsed=crate::cli_arguments::parse(ordinary);if !matches!(parsed.cmd.as_str(),"check"|"report"|"timing"){return Err(invalid("full registry adapter serves check/report/timing only"))}let report=parsed.cmd=="report";let timing_only=parsed.cmd=="timing";
 for flag in &parsed.flags{if !matches!(flag.as_str(),"--raw"|"--ci"|"--unused"|"--no-unused"|"--no-selftest"|"--no-cache"|"--rehash"|"--changed-only"|"--timing"){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("full native check has no exact implementation for {flag}; no compatibility fallback")))}}


 let root=std::path::absolute(crate::cli_arguments::find_root(parsed.root))?;
 let has=|name:&str|parsed.flags.iter().any(|flag|flag==name);
 Ok(Invocation{program:program.ok_or_else(||invalid("full native check needs --native-dmbc ABSOLUTE_EXE"))?,root,options:Options{raw:report||has("--raw"),ci:has("--ci"),unused:!report&&!timing_only&&!usage_export&&!has("--no-unused"),no_cache:has("--no-cache"),rehash:has("--rehash")},selectors:parsed.lints,selftests:!report&&!timing_only&&!has("--no-selftest"),changed:has("--changed-only"),timing:timing_only||has("--timing"),timing_only})
}
struct Text<'a>{diagnostics:&'a[u8],report:&'a[u8],usage:Option<&'a[u8]>}
fn text<'a>(bytes:&'a[u8],status:i32,expected:Options,selection:SelectionBinding,work:&NativeReportWork)->io::Result<Text<'a>>{ text_selftests(bytes,status,expected,selection,false,work) }
fn text_selftests<'a>(bytes:&'a[u8],status:i32,expected:Options,selection:SelectionBinding,selftests:bool,work:&NativeReportWork)->io::Result<Text<'a>>{
 let line=header_line(bytes,work)?;let terminal:Terminal=serde_json::from_slice(&bytes[..line]).map_err(io::Error::other)?;terminal.require_selftests(expected,selection,selftests)?;text_payload(&bytes[line+1..],status,&terminal,None,false)
}
fn header_line(bytes:&[u8],work:&NativeReportWork)->io::Result<usize>{let line=bytes.iter().take(MAX_HEADER).position(|b|*b==b'\n').ok_or_else(||invalid("full native CHECK lacks a bounded terminal header"))?;work.temporary(0,MAX_HEADER.checked_mul(8).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;Ok(line)}
fn text_cli<'a>(bytes:&'a[u8],status:i32,expected:Options,selection:SelectionBinding,selftests:bool,requested:&crate::native_check_cli_wire::Request,work:&NativeReportWork)->io::Result<Text<'a>>{
 let line=header_line(bytes,work)?;let terminal:crate::native_check_cli_wire::Terminal=serde_json::from_slice(&bytes[..line]).map_err(io::Error::other)?;terminal.require(expected,selection,selftests,requested)?;text_payload(&bytes[line+1..],status,&terminal.terminal,terminal.usage,requested.timing_only)
}
fn text_payload<'a>(body:&'a[u8],status:i32,terminal:&Terminal,usage:Option<crate::selected_exclusions_wire::Seal>,timing_only:bool)->io::Result<Text<'a>>{
 if !matches!(status,0|1)||if timing_only{status!=0}else{terminal.clean!=(status==0)}{return Err(invalid("native CHECK process status differs from its completed requested output"))}
 let width=|n|usize::try_from(n).map_err(|_|invalid("native CHECK payload length cannot fit this address space"));
 let diagnostic_length=width(terminal.diagnostics.as_ref().map_or(0,|seal|seal.length))?;let report_length=width(terminal.report.length)?;let usage_length=width(usage.as_ref().map_or(0,|seal|seal.length))?;
 if diagnostic_length.checked_add(report_length).and_then(|n|n.checked_add(usage_length))!=Some(body.len()){return Err(invalid("native CHECK aggregate payload differs from its terminal"))}
 let(diagnostics,tail)=body.split_at(diagnostic_length);let(report,usage_bytes)=tail.split_at(report_length);
 let differs=|seal:&crate::selected_exclusions_wire::Seal,bytes:&[u8]|seal.hash.0!=xxhash_rust::xxh3::xxh3_128(bytes);
 if terminal.diagnostics.as_ref().is_some_and(|seal|differs(seal,diagnostics))||differs(&terminal.report,report)||usage.as_ref().is_some_and(|seal|differs(seal,usage_bytes)){return Err(invalid("native CHECK payload differs from its sealed diagnostic/report/usage bytes"))}
 Ok(Text{diagnostics,report,usage:usage.map(|_|usage_bytes)})
}

fn require_separate_operational_stderr(stderr:&[u8])->io::Result<()>{if stderr.is_empty(){Ok(())}else{Err(io::Error::new(io::ErrorKind::Unsupported,"native CHECK preserved operational stderr; semantic subprocess transcript is not yet qualified"))}}
fn run(args:&[String],output:&mut impl Write,diagnostics:&mut impl Write)->io::Result<u8>{
 // Read the original UTF-8 environment once. Presence, including empty, disables
 // whole-unused judgment; only a nonempty value requests the actual append log.
 let usage_environment=std::env::var("DQ_ALLOW_USAGE").ok();let invocation=options_using(args,usage_environment.is_some())?;
 let usage_path=usage_environment.as_deref().filter(|value|!value.is_empty()&&!invocation.timing_only).map(PathBuf::from);
 let selection=SelectionBinding::for_selectors(&invocation.selectors)?;let metadata=NativeReportWork::new();
 let cli=if invocation.changed||invocation.timing||usage_environment.is_some(){Some(crate::native_check_cli_wire::Request{changed:if invocation.changed{Some(super::changed_paths::collect(&invocation.root,diagnostics,&metadata)?)}else{None},timing:invocation.timing,timing_only:invocation.timing_only,allow_usage:usage_path.is_some()})}else{None};
 if let Some(cli)=&cli{cli.qualify(invocation.options,invocation.selftests)?;}
 let mut command=Command::new(&invocation.program);command.arg("analyze-full-check").arg("--workspace").arg(&invocation.root);if !invocation.selftests{command.arg("--no-selftest");}
 if invocation.options.raw{command.arg("--raw");}if invocation.options.ci{command.arg("--ci");}if !invocation.options.unused{command.arg("--no-unused");}if invocation.options.no_cache{command.arg("--no-cache");}if invocation.options.rehash{command.arg("--rehash");}if !invocation.selectors.is_empty(){command.arg("--lint").args(&invocation.selectors);}
 let(status,captured,stderr,input_error)=if let Some(cli)=&cli{let input=super::funded_check_input(cli,&metadata)?;command.arg("--cli-stdin");super::capture_command_with_input(command,input,OUTER_WATCHDOG,move|reader|super::policy_stdout_work_using(reader,metadata),|reader|bounded(reader,MAX_STDERR))?}else{let(status,out,err)=capture_command(command,OUTER_WATCHDOG,policy_stdout_work,|reader|bounded(reader,MAX_STDERR))?;(status,out,err,None)};
 if let Some(first)=input_error{let _=diagnostics.write_all(&stderr);return Err(first)}diagnostics.write_all(&stderr)?;
 let Some(code @ (0|1))=status.code()else{return Ok(if status.code()==Some(75){75}else{2})};
 let work=captured.policy_work.as_ref().ok_or_else(||invalid("full native CHECK lost its physical output allowance"))?;require_separate_operational_stderr(&stderr)?;
 let text=if let Some(cli)=&cli{text_cli(&captured.bytes,code,invocation.options,selection,invocation.selftests,cli,work)?}else{text_selftests(&captured.bytes,code,invocation.options,selection,invocation.selftests,work)?};
 diagnostics.write_all(text.diagnostics)?;
 if let Some(path)=usage_path{let usage=text.usage.ok_or_else(||invalid("requested ALLOW usage append lacks its actual completed producer payload"))?;let mut file=std::fs::OpenOptions::new().create(true).append(true).open(path)?;file.write_all(usage)?;file.flush()?;}
 output.write_all(text.report)?;Ok(code as u8)
}

pub(super)fn cli(args:&[String])->std::process::ExitCode{match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>std::process::ExitCode::from(code),Err(error)=>{eprintln!("analyze native full check: {error}");std::process::ExitCode::from(2)}}}
#[cfg(test)]mod tests{
 use super::*;use crate::{full_registry_check_wire::{Schema,Scope},selected_exclusions_wire::{Seal,Hex128},full_registry_check_wire::CheckFrame};
 #[test]fn adapter_preserves_supported_flags_and_explicitly_refuses_unimplemented_modes(){
  let mut args=vec!["check".into(),"--native-full-registry".into(),"--native-dmbc".into(),if cfg!(windows){"E:/compiler/dmbc.exe".into()}else{"/compiler/dmbc".into()},"--root".into(),"actual-relative-root".into(),"--no-selftest".into(),"--raw".into(),"--ci".into(),"--no-unused".into(),"--no-cache".into(),"--rehash".into()];
  let parsed=options_using(&args,false).unwrap();assert_eq!(parsed.options,Options{raw:true,ci:true,unused:false,no_cache:true,rehash:true});assert!(parsed.root.is_absolute());
  for flag in["--drop-declared"]{args.push(flag.into());assert_eq!(options_using(&args,false).unwrap_err().kind(),io::ErrorKind::Unsupported);args.pop();}
  args.extend(["--lint".into(),"scheduler".into()]);assert_eq!(options_using(&args,false).unwrap().selectors,["scheduler"]);
 }
 #[test]fn completed_transport_requires_exact_flags_status_hash_length_and_no_partial_body(){
  let body=b"actual sealed report\n";let expected=Options::default();let terminal=Terminal{schema:Schema::V2,scope:Scope::FullRegistry,complete:true,full_policy_parity:false,options:expected,selection:SelectionBinding::for_selectors(&[]).unwrap(),selected:1,registered:1,frame:CheckFrame::Model{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,selftests:None,diagnostics:None,report:Seal{length:body.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(body))}};
  // These are codec DATA controls, never a native source/completion issuer.
  let mut wire=serde_json::to_vec(&terminal).unwrap();wire.push(b'\n');wire.extend_from_slice(body);assert_eq!(text(&wire,1,expected,SelectionBinding::for_selectors(&[]).unwrap(),&NativeReportWork::new()).unwrap().report,body);
  assert!(text(&wire,0,expected,SelectionBinding::for_selectors(&[]).unwrap(),&NativeReportWork::new()).is_err());assert!(text(&wire,2,expected,SelectionBinding::for_selectors(&[]).unwrap(),&NativeReportWork::new()).is_err());wire.pop();assert!(text(&wire,1,expected,SelectionBinding::for_selectors(&[]).unwrap(),&NativeReportWork::new()).is_err());
 }
 #[test]fn diagnostic_payload_is_independently_sealed_and_cannot_be_replaced_by_operational_stderr(){
  let diagnostics=b"actual semantic diagnostic\n";let report=b"actual selected report\n";let expected=Options::default();let selection=SelectionBinding::for_selectors(&["scheduler".into()]).unwrap();
  let terminal=Terminal{schema:Schema::V2,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options:expected,selection,selected:1,registered:2,frame:CheckFrame::Source{query_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,selftests:None,diagnostics:Some(Seal{length:diagnostics.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(diagnostics))}),report:Seal{length:report.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(report))}};
  let mut wire=serde_json::to_vec(&terminal).unwrap();wire.push(b'\n');let start=wire.len();wire.extend_from_slice(diagnostics);wire.extend_from_slice(report);let text=text(&wire,1,expected,selection,&NativeReportWork::new()).unwrap();assert_eq!(text.diagnostics,diagnostics);assert_eq!(text.report,report);
  wire[start]^=1;assert!(super::text(&wire,1,expected,selection,&NativeReportWork::new()).is_err());wire[start]^=1;wire.push(0);assert!(super::text(&wire,1,expected,selection,&NativeReportWork::new()).is_err());wire.pop();
  require_separate_operational_stderr(b"").unwrap();assert_eq!(require_separate_operational_stderr(b"preserved native trace\n").unwrap_err().kind(),io::ErrorKind::Unsupported);
  let mut missing=serde_json::to_value(&terminal).unwrap();missing.as_object_mut().unwrap().remove("diagnostics");assert!(serde_json::from_value::<Terminal>(missing).is_err(),"diagnostic field must be explicit even when null");
 }

}

#[cfg(test)]mod report_alias_controls{
 use super::*;use crate::{full_registry_check_wire::{Schema,Scope,CheckFrame},selected_exclusions_wire::{Seal,Hex128}};
 fn args()->Vec<String>{vec!["report".into(),"--native-full-registry".into(),"--native-dmbc".into(),if cfg!(windows){"E:/not-started/dmbc.exe".into()}else{"/not-started/dmbc".into()},"--root".into(),"actual-relative-root".into(),"--no-selftest".into()]}
 #[test]fn native_report_alias_forces_raw_even_with_ci_and_never_requests_whole_unused(){
  let mut arguments=args();arguments.extend(["--ci".into(),"--unused".into(),"--no-cache".into(),"--rehash".into(),"--lint".into(),"scheduler,-tracked,scheduler".into()]);let report=options_using(&arguments,false).unwrap();assert_eq!(report.options,Options{raw:true,ci:true,unused:false,no_cache:true,rehash:true});assert_eq!(report.selectors,["scheduler","-tracked","scheduler"]);
  arguments.push("--no-unused".into());assert_eq!(options_using(&arguments,false).unwrap().options,report.options);arguments[0]="check".into();assert!(!options_using(&arguments,false).unwrap().options.raw,"check must keep its existing independent raw flag");
  arguments=args();arguments.retain(|arg|arg!="--no-selftest");assert!(!options_using(&arguments,false).unwrap().selftests,"ordinary report never runs selftests");for mode in ["--changed-only","--timing"]{let mut arguments=args();arguments.push(mode.into());let parsed=options_using(&arguments,false).unwrap();assert!(!parsed.selftests&&parsed.options.raw&&!parsed.options.unused);assert_eq!(parsed.changed,mode=="--changed-only");assert_eq!(parsed.timing,mode=="--timing");}assert!(!options_using(&args(),true).unwrap().options.unused);
 }
 #[test]fn native_report_terminal_requires_effective_raw_ci_no_audit_and_both_exact_streams(){
  let mut arguments=args();arguments.extend(["--ci".into(),"--unused".into(),"--lint".into(),"scheduler".into()]);let invocation=options_using(&arguments,false).unwrap();let selection=SelectionBinding::for_selectors(&invocation.selectors).unwrap();let diagnostics=b"actual registered diagnostic\n";let report=b"::group::scheduler\nactual finding\n::endgroup::\nRatchet lints failed: scheduler\n";
  let terminal=Terminal{schema:Schema::V2,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options:invocation.options,selection,selected:1,registered:2,frame:CheckFrame::Source{query_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,selftests:None,diagnostics:Some(Seal{length:diagnostics.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(diagnostics))}),report:Seal{length:report.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(report))}};
  let encode=|terminal:&Terminal|{let mut bytes=serde_json::to_vec(terminal).unwrap();bytes.push(b'\n');bytes.extend_from_slice(diagnostics);bytes.extend_from_slice(report);bytes};let wire=encode(&terminal);let work=NativeReportWork::new();let actual=text(&wire,1,invocation.options,selection,&work).unwrap();assert_eq!(actual.diagnostics,diagnostics);assert_eq!(actual.report,report);
  for mode in 0..3{let mut wrong=terminal.clone();match mode{0=>wrong.options.raw=false,1=>wrong.options.unused=true,_=>wrong.options.ci=false}assert!(text(&encode(&wrong),1,invocation.options,selection,&work).is_err())}assert!(text(&wire,0,invocation.options,selection,&work).is_err());let mut corrupt=wire;*corrupt.last_mut().unwrap()^=1;assert!(text(&corrupt,1,invocation.options,selection,&work).is_err());
 }
}

#[cfg(test)]mod native_callback_mode_controls{
 use super::*;use crate::full_registry_check_wire::{Schema,Scope,CheckFrame,Selftests};use crate::selected_exclusions_wire::{Seal,Hex128};
 fn args()->Vec<String>{vec!["check".into(),"--native-full-registry".into(),"--native-dmbc".into(),if cfg!(windows){"E:/not-started/dmbc.exe".into()}else{"/not-started/dmbc".into()},"--root".into(),if cfg!(windows){"E:/actual-root".into()}else{"/actual-root".into()}]}
 #[test]fn native_check_requests_callbacks_but_report_and_explicit_no_selftest_do_not(){let mut a=args();assert!(options_using(&a,false).unwrap().selftests);a.push("--no-selftest".into());assert!(!options_using(&a,false).unwrap().selftests);a.pop();a[0]="report".into();assert!(!options_using(&a,false).unwrap().selftests);}
 #[test]fn native_callback_terminal_still_authenticates_every_report_byte_and_failure_status(){let options=Options::default();let selection=SelectionBinding::for_selectors(&["ui_actions".into()]).unwrap();let report=b"selftest FAILED: ui_actions: actual assertion\nactual policy output\nRatchet lints failed: ui_actions --selftest\n";let terminal=Terminal{schema:Schema::V3,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options,selection,selected:1,registered:2,frame:CheckFrame::Source{query_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,selftests:Some(Selftests{completed:1,failed:1}),diagnostics:None,report:Seal{length:report.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(report))}};let mut bytes=serde_json::to_vec(&terminal).unwrap();bytes.push(b'\n');bytes.extend_from_slice(report);let work=NativeReportWork::new();assert_eq!(text_selftests(&bytes,1,options,selection,true,&work).unwrap().report,report);assert!(text(&bytes,1,options,selection,&work).is_err());assert!(text_selftests(&bytes,0,options,selection,true,&work).is_err());*bytes.last_mut().unwrap()^=1;assert!(text_selftests(&bytes,1,options,selection,true,&work).is_err());}
}

#[cfg(test)]mod cli_observation_payload_controls{
 use super::*;use crate::{full_registry_check_wire::{Schema,Scope,CheckFrame},selected_exclusions_wire::{Seal,Hex128}};
 fn options()->Options{Options{unused:false,..Default::default()}}
 fn request(timing_only:bool)->crate::native_check_cli_wire::Request{crate::native_check_cli_wire::Request{changed:Some(vec!["code/actual.dm".into()]),timing:timing_only,timing_only,allow_usage:!timing_only}}
 fn encode(request:&crate::native_check_cli_wire::Request,usage:&[u8])->Vec<u8>{let report=b"actual completed policy output\n";let diagnostics=b"actual source notice\n";let terminal=Terminal{schema:Schema::V2,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options:options(),selection:SelectionBinding::for_selectors(&["scheduler".into()]).unwrap(),selected:1,registered:2,frame:CheckFrame::Source{query_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,selftests:None,diagnostics:Some(Seal{length:diagnostics.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(diagnostics))}),report:Seal{length:report.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(report))}};let outer=crate::native_check_cli_wire::Terminal{schema:crate::native_check_cli_wire::Schema::V1,requested:request.binding().unwrap(),terminal,usage:request.allow_usage.then_some(Seal{length:usage.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(usage))})};let mut bytes=serde_json::to_vec(&outer).unwrap();bytes.push(b'\n');bytes.extend_from_slice(diagnostics);bytes.extend_from_slice(report);if request.allow_usage{bytes.extend_from_slice(usage)}bytes}
 #[test]fn sealed_cli_payload_requires_exact_filter_and_each_usage_byte_including_empty_requested_union(){let selection=SelectionBinding::for_selectors(&["scheduler".into()]).unwrap();let request=request(false);for usage in [&b""[..],&b"scheduler\tactual\t3\n"[..]]{let bytes=encode(&request,usage);let work=NativeReportWork::new();let text=text_cli(&bytes,1,options(),selection,false,&request,&work).unwrap();assert_eq!(text.usage,Some(usage));let mut changed=request.clone();changed.changed=Some(vec![]);assert!(text_cli(&bytes,1,options(),selection,false,&changed,&work).is_err());assert!(text_selftests(&bytes,1,options(),selection,false,&work).is_err());let mut corrupt=bytes;*corrupt.last_mut().unwrap()^=1;assert!(text_cli(&corrupt,1,options(),selection,false,&request,&work).is_err());}}
 #[test]fn timing_command_process_success_keeps_actual_failing_policy_verdict_bound(){let request=request(true);let bytes=encode(&request,b"");let selection=SelectionBinding::for_selectors(&["scheduler".into()]).unwrap();let work=NativeReportWork::new();assert!(text_cli(&bytes,0,options(),selection,false,&request,&work).is_ok());assert!(text_cli(&bytes,1,options(),selection,false,&request,&work).is_err());let mut ordinary=request;ordinary.timing_only=false;assert!(text_cli(&bytes,0,options(),selection,false,&ordinary,&work).is_err());}
 #[test]fn ordinary_timing_command_and_usage_presence_have_distinct_actual_callback_and_unused_contracts(){let exe=if cfg!(windows){"E:/not-started/dmbc.exe"}else{"/not-started/dmbc"};let args=vec!["timing".into(),"--native-full-registry".into(),"--native-dmbc".into(),exe.into(),"--root".into(),"fixture".into()];let timing=options_using(&args,false).unwrap();assert!(timing.timing&&timing.timing_only&&!timing.selftests&&!timing.options.unused);let mut args=args;args[0]="check".into();let observed=options_using(&args,true).unwrap();assert!(!observed.options.unused&&observed.selftests&&!observed.timing_only);}
}
