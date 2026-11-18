//! Explicit thin Checker client: existing native daemon, no local DM model.
use super::{capture_command,policy_stdout_work,bounded,NativeReportWork,OUTER_WATCHDOG,MAX_STDERR};use crate::{native_checker_wire::Terminal,selected_exclusions_wire::MAX_HEADER,report_work::Work};use std::{io::{self,Write},path::PathBuf,process::Command};
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
#[derive(Debug)]struct Invocation{program:PathBuf,arguments:Vec<String>,project:PathBuf,json:bool,parse_only:bool,version:bool,unknown:Option<String>}
fn invocation(arguments:&[String])->io::Result<Invocation>{invocation_using(arguments,std::env::current_dir)}
fn invocation_using(arguments:&[String],cwd:impl FnOnce()->io::Result<PathBuf>)->io::Result<Invocation>{
 match super::checker_caller_paths::select(arguments,true)?{
  super::checker_caller_paths::Selection::Version=>Ok(Invocation{program:PathBuf::new(),arguments:Vec::new(),project:PathBuf::new(),json:false,parse_only:false,version:true,unknown:None}),
  super::checker_caller_paths::Selection::Unknown(arg)=>Ok(Invocation{program:PathBuf::new(),arguments:Vec::new(),project:PathBuf::new(),json:false,parse_only:false,version:false,unknown:Some(arg)}),
  super::checker_caller_paths::Selection::Check(mut selected)=>{let program=selected.program.take().ok_or_else(||invalid("Checker needs --native-dmbc ABSOLUTE_EXE"))?;let ordinary=std::mem::take(&mut selected.ordinary);let actual=super::checker_caller_paths::resolve_selected_using(selected,cwd)?;Ok(Invocation{program,arguments:ordinary,project:actual.project,json:actual.json,parse_only:actual.parse_only,version:false,unknown:None})}
 }
}
struct Delivered<'a>{diagnostics:&'a[u8],output:&'a[u8]}
fn text<'a>(bytes:&'a[u8],status:i32,project:&std::path::Path,work:&NativeReportWork,operational:&[u8],json:bool,parse_only:bool)->io::Result<Delivered<'a>>{
 if !matches!(status,0|1){return Err(invalid("Checker child did not complete"))}if !operational.is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,"preserved native operational stderr has no qualified semantic transcript route"))}
 let line=bytes.iter().take(MAX_HEADER).position(|b|*b==b'\n').ok_or_else(||invalid("Checker lacks bounded terminal"))?;work.temporary(0,MAX_HEADER.checked_mul(8).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;let terminal:Terminal=serde_json::from_slice(&bytes[..line]).map_err(io::Error::other)?;terminal.require(project)?;if terminal.json!=json||terminal.parser.is_some()!=parse_only{return Err(invalid("Checker terminal mode differs from actual request"))}
 let payload=&bytes[line+1..];let diagnostics=usize::try_from(terminal.diagnostics.as_ref().map_or(0,|s|s.length)).map_err(|_|invalid("Checker diagnostic extent overflow"))?;let output=usize::try_from(terminal.output.length).map_err(|_|invalid("Checker stdout extent overflow"))?;
 if i32::from(terminal.exit_code)!=status||diagnostics.checked_add(output)!=Some(payload.len()){return Err(invalid("Checker aggregate extent/status differs"))}let(diagnostics,output)=payload.split_at(diagnostics);
 if terminal.diagnostics.as_ref().is_some_and(|s|s.hash.0!=xxhash_rust::xxh3::xxh3_128(diagnostics))||terminal.output.hash.0!=xxhash_rust::xxh3::xxh3_128(output)||!valid_summary(output,terminal.emitted,json){return Err(invalid("Checker stdout/diagnostics seals or summary count differ"))}Ok(Delivered{diagnostics,output})
}
fn valid_summary(output:&[u8],emitted:u64,json:bool)->bool{
 let footer=format!("Found {emitted} diagnostics\n");if !json{return output.ends_with(footer.as_bytes())}
 let Some(start)=output.windows(footer.len()).rposition(|row|row==footer.as_bytes())else{return false};
 let suffix=&output[start+footer.len()..];let Ok(counts)=serde_json::from_slice::<Counts>(suffix)else{return false};
 counts.error.checked_add(counts.warning).and_then(|n|n.checked_add(counts.info))==Some(emitted)
}
#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Counts{hint:u64,info:u64,warning:u64,error:u64}
pub(super) fn run(arguments:&[String],stdout:&mut impl Write,stderr:&mut impl Write)->io::Result<u8>{let invocation=invocation(arguments)?;if invocation.version{super::checker_caller_paths::write_version(stdout,env!("CARGO_PKG_NAME"),env!("CARGO_PKG_VERSION"),option_env!("VERGEN_GIT_SHA"))?;return Ok(0)}if let Some(arg)=invocation.unknown{writeln!(stderr,"unknown argument: {arg}")?;return Ok(0)}let mut command=Command::new(invocation.program);command.arg("checker-text").args(&invocation.arguments);let(status,captured,operational)=capture_command(command,OUTER_WATCHDOG,policy_stdout_work,|input|bounded(input,MAX_STDERR))?;stderr.write_all(&operational)?;let Some(code @ (0|1))=status.code()else{return Ok(if status.code()==Some(75){75}else{2})};let work=captured.policy_work.as_ref().ok_or_else(||invalid("Checker lost physical output allowance"))?;let delivered=text(&captured.bytes,code,&invocation.project,work,&operational,invocation.json,invocation.parse_only)?;stderr.write_all(delivered.diagnostics)?;stdout.write_all(delivered.output)?;Ok(code as u8)}
pub(super)fn cli(arguments:&[String])->std::process::ExitCode{match run(arguments,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>std::process::ExitCode::from(code),Err(error)=>{eprintln!("native Checker: {error}");std::process::ExitCode::from(2)}}}

#[cfg(test)]mod tests{use super::*;use crate::{native_checker_wire::{Schema,Frame},selected_exclusions_wire::{Hex128,Seal}};
 #[test]fn resident_checker_client_requires_both_seals_status_count_and_keeps_logs_distinct(){
  let project=if cfg!(windows){std::path::Path::new("E:/actual/project.dme")}else{std::path::Path::new("/actual/project.dme")};let diagnostic=b"error: real semantic row\n";let output=b"Found 1 diagnostics\n";let mut terminal=Terminal{schema:Schema::V2,complete:true,full_checker_parity:false,json:false,parser:None,project:project.into(),emitted:1,visited_bodies:1,exit_code:1,frame:Frame{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},diagnostics:Some(Seal{length:diagnostic.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(diagnostic))}),output:Seal{length:output.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(output))}};
  let encode=|t:&Terminal|{let mut bytes=serde_json::to_vec(t).unwrap();bytes.push(b'\n');bytes.extend_from_slice(diagnostic);bytes.extend_from_slice(output);bytes};let work=NativeReportWork::new();let wire=encode(&terminal);let got=text(&wire,1,project,&work,&[],false,false).unwrap();assert_eq!(got.diagnostics,diagnostic);assert_eq!(got.output,output);assert!(text(&wire,0,project,&work,&[],false,false).is_err());assert!(text(&wire,2,project,&work,&[],false,false).is_err());assert!(text(&wire[..wire.len()-1],1,project,&work,&[],false,false).is_err());assert_eq!(text(&wire,1,project,&work,b"preserved actual native trace\n",false,false).err().unwrap().kind(),io::ErrorKind::Unsupported);terminal.emitted=2;assert!(text(&encode(&terminal),1,project,&work,&[],false,false).is_err());terminal.emitted=1;terminal.diagnostics.as_mut().unwrap().hash=Hex128(0);assert!(text(&encode(&terminal),1,project,&work,&[],false,false).is_err());terminal.diagnostics.as_mut().unwrap().hash=Hex128(xxhash_rust::xxh3::xxh3_128(diagnostic));terminal.visited_bodies=0;terminal.parser=Some(crate::native_checker_wire::ParserCounts{good:1,bad:1,fatal:false});assert!(text(&encode(&terminal),1,project,&work,&[],false,false).is_err());assert!(text(&encode(&terminal),1,project,&work,&[],false,true).is_ok());
 }
 #[test]fn resident_checker_client_rejects_missing_native_or_environment_before_process_start(){for arguments in[vec![],vec!["--native-dmbc".into(),"relative.exe".into()],vec!["--native-dmbc".into(),if cfg!(windows){"E:/not-started.exe".into()}else{"/not-started.exe".into()},"-e".into()]]{assert!(invocation(&arguments).is_err())}}
}

#[cfg(test)]mod json_summary_controls{use super::*;#[test]fn requested_json_summary_requires_exact_four_counts_and_visible_sum(){assert!(valid_summary(b"Found 2 diagnostics\n{\"error\":1,\"hint\":9,\"info\":1,\"warning\":0}",2,true));assert!(!valid_summary(b"Found 2 diagnostics\n{\"error\":1,\"hint\":9,\"info\":0,\"warning\":0}",2,true));assert!(!valid_summary(b"Found 2 diagnostics\n",2,true));assert!(!valid_summary(b"Found 2 diagnostics\n{\"error\":1,\"info\":1,\"warning\":0}",2,true));assert!(!valid_summary(b"Found 2 diagnostics\n{\"error\":1,\"hint\":9,\"info\":1,\"warning\":0}trailing",2,true));assert!(!valid_summary(b"Found 0 diagnostics\n{\"error\":18446744073709551615,\"hint\":0,\"info\":1,\"warning\":0}",0,true));assert!(!valid_summary(b"Found 0 diagnostics\n{\"error\":0,\"hint\":0,\"info\":0,\"warning\":0}",0,false));}}

#[cfg(test)]mod early_argument_action_controls{use super::*;
 #[test]fn actual_thin_checker_unknown_stops_before_later_missing_value_cwd_and_backend(){
  let program=if cfg!(windows){"E:/nonexistent-checker-not-started.exe"}else{"/nonexistent-checker-not-started"};let arguments=["--native-dmbc".into(),program.into(),"--unknown".into(),"-e".into()];
  let selected=invocation_using(&arguments,||panic!("unknown action must not request cwd")).unwrap();assert_eq!(selected.unknown.as_deref(),Some("--unknown"));
  let(mut stdout,mut stderr)=(Vec::new(),Vec::new());assert_eq!(run(&arguments,&mut stdout,&mut stderr).unwrap(),0);assert!(stdout.is_empty(),"argument action cannot mint Checker completion");assert_eq!(stderr,b"unknown argument: --unknown\n");
 }
}

#[cfg(test)]mod absolute_no_caller_directory_controls{use super::*;
 #[test]fn actual_thin_checker_absolute_project_and_absolute_or_absent_config_never_requests_cwd(){
  let root={let base=if cfg!(windows){PathBuf::from("E:/dq-cache/test-scratch")}else{std::env::temp_dir()};std::fs::create_dir_all(&base).unwrap();std::fs::canonicalize(base).unwrap()};
  // Use an existing physical file for canonical project resolution; invocation
  // does not parse its bytes or launch this explicitly nonexistent backend.
  let project=root.join(format!("checker-absolute-no-cwd-{}-{}.dme",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));std::fs::write(&project,b"/proc/p()\n    return\n").unwrap();let project=std::fs::canonicalize(project).unwrap();
  let program=if cfg!(windows){"E:/nonexistent-checker-not-started.exe"}else{"/nonexistent-checker-not-started"};
  for config in [None,Some(root.join("absolute-config.toml"))]{
   let mut arguments=vec!["--native-dmbc".into(),program.into(),"-e".into(),project.to_string_lossy().into_owned()];if let Some(config)=config{arguments.extend(["-c".into(),config.to_string_lossy().into_owned()]);}
   let actual=invocation_using(&arguments,||panic!("absolute explicit paths must not obtain cwd")).unwrap();assert_eq!(actual.project,project);assert!(actual.unknown.is_none());
  }std::fs::remove_file(project).unwrap();
 }
}

#[cfg(test)]mod actual_version_early_controls{use super::*;
 #[test]fn actual_thin_version_avoids_cwd_and_backend_even_with_absent_project(){let args=["-e".into(),"absent.dme".into(),"-V".into()];let invocation=invocation_using(&args,||panic!("version must precede cwd")).unwrap();assert!(invocation.version);assert!(invocation.program.as_os_str().is_empty());let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(run(&args,&mut out,&mut err).unwrap(),0);assert!(String::from_utf8(out).unwrap().contains("DeepQuarry native Checker"));assert!(err.is_empty());}
}
