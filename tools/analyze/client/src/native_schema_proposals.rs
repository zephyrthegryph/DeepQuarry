//! Explicit native schema opt-in; no parser/model/fallback in this client.
use super::{capture_command,policy_stdout_work,bounded,NativeReportWork,OUTER_WATCHDOG,MAX_STDERR};use crate::{schema_proposals_wire::Terminal,selected_exclusions_wire::MAX_HEADER,report_work::Work};
use std::{io::{self,Write},path::PathBuf,process::Command};
fn invalid(text:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,text)}
#[derive(Debug,PartialEq,Eq)]struct Invocation{program:PathBuf,root:PathBuf}
fn invocation(args:&[String])->io::Result<Invocation>{let mut ordinary=vec!["analyze".to_owned()];let mut program=None;let mut i=0;while i<args.len(){let arg=&args[i];i+=1;if arg=="--native-dmbc"{let path=PathBuf::from(args.get(i).ok_or_else(||invalid("--native-dmbc needs absolute compiler executable"))?);i+=1;if !path.is_absolute()||program.replace(path).is_some(){return Err(invalid("schema needs exactly one absolute compiler executable"))}}else{ordinary.push(arg.clone())}}
 if ordinary.iter().any(|a|a=="--native-full-registry"||a.starts_with("--native-full-registry=")){return Err(invalid("schema and full-registry check modes cannot be mixed"))}
 let parsed=crate::cli_arguments::parse(ordinary);if parsed.cmd!="fix"||!parsed.flags.iter().any(|f|f=="--propose-schema"){return Err(invalid("native schema adapter needs fix --propose-schema"))}
 // Legacy main dispatch passes only root into propose_cli: flags/lint filters
 // (including --apply) deliberately have no effect in this review-only mode.
 // Preserve that exact full-root/no-write meaning, not a fabricated partial run.
 let root=std::fs::canonicalize(crate::cli_arguments::find_root(parsed.root))?;Ok(Invocation{program:program.ok_or_else(||invalid("native schema needs --native-dmbc ABSOLUTE_EXE"))?,root})
}
fn footer_count(body:&[u8])->io::Result<u64>{
 let suffix=b" proposal(s); nothing was written (--apply does not apply a schema_path base).";
 let before=body.strip_suffix(b"\n").ok_or_else(||invalid("schema report footer is incomplete"))?;let footer=before.rsplit(|b|*b==b'\n').next().unwrap_or(before);let digits=footer.strip_suffix(suffix).ok_or_else(||invalid("schema report footer differs"))?;
 if digits.is_empty()||(digits.len()>1&&digits[0]==b'0'){return Err(invalid("schema report count is not canonical"))}digits.iter().try_fold(0u64,|n,b|{if !b.is_ascii_digit(){return Err(invalid("schema report count is not decimal"))}n.checked_mul(10).and_then(|n|n.checked_add(u64::from(*b-b'0'))).ok_or_else(||invalid("schema report count overflows"))})
}
struct Delivered<'a>{diagnostics:&'a[u8],report:&'a[u8]}
fn text<'a>(bytes:&'a[u8],status:i32,root:&std::path::Path,work:&NativeReportWork,operational_stderr:&[u8])->io::Result<Delivered<'a>>{
 if status!=0{return Err(invalid("schema did not complete read-only proposal report"))}
 if !operational_stderr.is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,"native schema operational stderr has no qualified separate log sink; no completed semantic output is delivered"))}
 let line=bytes.iter().take(MAX_HEADER).position(|b|*b==b'\n').ok_or_else(||invalid("schema lacks bounded completed transport header"))?;
 work.temporary(0,MAX_HEADER.checked_mul(8).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;
 let terminal:Terminal=serde_json::from_slice(&bytes[..line]).map_err(io::Error::other)?;terminal.require(root)?;
 let payload=&bytes[line+1..];let diagnostic_len=usize::try_from(terminal.diagnostics.as_ref().map_or(0,|s|s.length)).map_err(|_|invalid("schema diagnostic extent overflow"))?;
 let report_len=usize::try_from(terminal.report.length).map_err(|_|invalid("schema report extent overflow"))?;
 if diagnostic_len.checked_add(report_len)!=Some(payload.len()){return Err(invalid("schema delivered stream extents differ from terminal"))}
 let(diagnostics,report)=payload.split_at(diagnostic_len);
 if terminal.diagnostics.as_ref().is_some_and(|seal|seal.hash.0!=xxhash_rust::xxh3::xxh3_128(diagnostics))||terminal.report.hash.0!=xxhash_rust::xxh3::xxh3_128(report)||footer_count(report)?!=terminal.count{return Err(invalid("schema delivered streams differ from actual seals/count"))}
 Ok(Delivered{diagnostics,report})
}

fn run(args:&[String],output:&mut impl Write,diagnostics:&mut impl Write)->io::Result<u8>{let invocation=invocation(args)?;let mut command=Command::new(invocation.program);command.arg("analyze-schema-proposals").arg("--workspace").arg(&invocation.root);let(status,captured,stderr)=capture_command(command,OUTER_WATCHDOG,policy_stdout_work,|r|bounded(r,MAX_STDERR))?;diagnostics.write_all(&stderr)?;let Some(0)=status.code()else{return Ok(if status.code()==Some(75){75}else{2})};let work=captured.policy_work.as_ref().ok_or_else(||invalid("schema output lost actual physical allowance"))?;let delivered=text(&captured.bytes,0,&invocation.root,work,&stderr)?;diagnostics.write_all(delivered.diagnostics)?;output.write_all(delivered.report)?;Ok(0)}
pub(super)fn cli(args:&[String])->std::process::ExitCode{match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>std::process::ExitCode::from(code),Err(e)=>{eprintln!("analyze native schema: {e}");std::process::ExitCode::from(2)}}}
#[cfg(test)]mod tests{use super::*;
 #[test]fn schema_client_only_delivers_sealed_completed_zero_exit_report(){
  use crate::{schema_proposals_wire::Schema,selected_exclusions_wire::{Frame,Hex128,Seal}};
  let root=if cfg!(windows){std::path::Path::new("E:/project")}else{std::path::Path::new("/project")};let body=b"0 proposal(s); nothing was written (--apply does not apply a schema_path base).\n";let mut terminal=Terminal{schema:Schema::V1,complete:true,applied:false,full_policy_parity:false,root:root.into(),frame:Frame{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},count:0,diagnostics:None,report:Seal{length:body.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(body))}};
  let encode=|terminal:&Terminal|{let mut bytes=serde_json::to_vec(terminal).unwrap();bytes.push(b'\n');bytes.extend_from_slice(body);bytes};let work=NativeReportWork::new();let wire=encode(&terminal);assert_eq!(text(&wire,0,root,&work,&[]).unwrap().report,body);assert_eq!(text(&wire,0,root,&work,b"actual operational trace\n").err().unwrap().kind(),io::ErrorKind::Unsupported);assert!(text(&wire,0,root,&work,&[]).unwrap().diagnostics.is_empty());assert!(text(&wire,1,root,&work,&[]).is_err());assert!(text(&wire,2,root,&work,&[]).is_err());assert!(text(&wire[..wire.len()-1],0,root,&work,&[]).is_err());terminal.complete=false;assert!(text(&encode(&terminal),0,root,&work,&[]).is_err());terminal.complete=true;terminal.applied=true;assert!(text(&encode(&terminal),0,root,&work,&[]).is_err());terminal.applied=false;terminal.count=1;assert!(text(&encode(&terminal),0,root,&work,&[]).is_err());
 }

 #[test]fn schema_client_authenticates_diagnostics_without_classifying_process_logs(){
  use crate::{schema_proposals_wire::Schema,selected_exclusions_wire::{Frame,Hex128,Seal}};
  let root=if cfg!(windows){std::path::Path::new("E:/project")}else{std::path::Path::new("/project")};let body=b"0 proposal(s); nothing was written (--apply does not apply a schema_path base).\n";let diagnostic=b"actual captured native warning\n";
  let mut terminal=Terminal{schema:Schema::V1,complete:true,applied:false,full_policy_parity:false,root:root.into(),frame:Frame{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},count:0,diagnostics:Some(Seal{length:diagnostic.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(diagnostic))}),report:Seal{length:body.len()as u64,hash:Hex128(xxhash_rust::xxh3::xxh3_128(body))}};
  let encode=|terminal:&Terminal,diagnostic:&[u8]|{let mut wire=serde_json::to_vec(terminal).unwrap();wire.push(b'\n');wire.extend_from_slice(diagnostic);wire.extend_from_slice(body);wire};let work=NativeReportWork::new();let wire=encode(&terminal,diagnostic);let issued=text(&wire,0,root,&work,&[]).unwrap();assert_eq!(issued.diagnostics,diagnostic);assert_eq!(issued.report,body);
  assert!(text(&encode(&terminal,b""),0,root,&work,&[]).is_err());let mut corrupt=diagnostic.to_vec();corrupt[0]^=1;assert!(text(&encode(&terminal,&corrupt),0,root,&work,&[]).is_err());terminal.diagnostics=None;assert!(text(&encode(&terminal,diagnostic),0,root,&work,&[]).is_err());let without=encode(&terminal,b"");assert!(text(&without,0,root,&work,&[]).unwrap().diagnostics.is_empty());
 }
 #[test]fn schema_opt_in_preserves_legacy_review_only_flags_and_refuses_other_command_modes(){let exe=if cfg!(windows){"E:/dmbc.exe"}else{"/dmbc"};let root=std::env::current_dir().unwrap();let mut a=vec!["fix".into(),"--propose-schema".into(),"--apply".into(),"--lint".into(),"untyped".into(),"--changed-only".into(),"--ci".into(),"--native-dmbc".into(),exe.into(),"--root".into(),root.to_string_lossy().into_owned()];let actual=invocation(&a).unwrap();assert_eq!(actual.program,PathBuf::from(exe));assert_eq!(actual.root,std::fs::canonicalize(root).unwrap());a[0]="check".into();assert!(invocation(&a).is_err());a[0]="fix".into();a.push("--native-full-registry".into());assert!(invocation(&a).is_err());}
}
