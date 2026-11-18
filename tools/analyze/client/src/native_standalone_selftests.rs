//! Explicit standalone callback client over the same resident daemon.
use super::{capture_command,policy_stdout_work,bounded,OUTER_WATCHDOG,MAX_STDERR,NativeReportWork};
use crate::{native_selftest_wire::Terminal,selected_exclusions_wire::MAX_HEADER,report_work::Work};
use std::{io::{self,Write},path::PathBuf,process::Command};
fn invalid(s:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,s)}
fn invocation(args:&[String])->io::Result<(PathBuf,Vec<String>,crate::full_registry_check_selection_wire::SelectionBinding)>{
 let mut ordinary=vec!["analyze".to_owned()];let(mut program,mut at)=(None,0);
 while let Some(arg)=args.get(at){at+=1;if arg=="--native-dmbc"{let path=PathBuf::from(args.get(at).ok_or_else(||invalid("selftest compiler value missing"))?);at+=1;if !path.is_absolute()||program.replace(path).is_some(){return Err(invalid("selftest requires one absolute compiler executable"))}}else{ordinary.push(arg.clone())}}
 let parsed=crate::cli_arguments::parse(ordinary);if parsed.cmd!="selftest"{return Err(invalid("standalone route requires selftest command"))}
 let root=std::fs::canonicalize(crate::cli_arguments::find_root(parsed.root))?;
 let mut child=vec!["analyze-selftest".into(),"--workspace".into(),root.to_string_lossy().into_owned()];
 let selection=crate::full_registry_check_selection_wire::SelectionBinding::for_selectors(&parsed.lints)?;
 if !parsed.lints.is_empty(){child.push("--lint".into());child.extend(parsed.lints)}
 // Other original selftest flags are inert; callback selection/root are the
 // entire requested behavior. No full CHECK is executed or discarded.
 Ok((program.ok_or_else(||invalid("selftest requires --native-dmbc ABSOLUTE_EXE"))?,child,selection))
}
fn text<'a>(bytes:&'a[u8],code:i32,selection:crate::full_registry_check_selection_wire::SelectionBinding,work:&NativeReportWork)->io::Result<&'a[u8]>{
 let end=bytes.iter().take(MAX_HEADER).position(|byte|*byte==b'\n').ok_or_else(||invalid("standalone selftest terminal missing"))?;
 work.temporary(0,MAX_HEADER.checked_mul(8).and_then(|n|n.checked_add(65536)).ok_or_else(||work.overflow())?)?;
 let terminal:Terminal=serde_json::from_slice(&bytes[..end]).map_err(io::Error::other)?;terminal.require(selection)?;
 let payload=&bytes[end+1..];if !matches!(code,0|1)||(code==0)!=(terminal.failed==0)||terminal.report.length!=payload.len()as u64||terminal.report.hash.0!=xxhash_rust::xxh3::xxh3_128(payload)||!payload.ends_with(b"\n")||std::str::from_utf8(payload).is_err(){return Err(invalid("standalone transcript differs from actual sealed callback terminal"))}Ok(payload)
}
fn run(args:&[String],out:&mut impl Write,err:&mut impl Write)->io::Result<u8>{
 let(program,child,selection)=invocation(args)?;
 let mut command=Command::new(program);command.args(child);let(status,captured,diagnostics)=capture_command(command,OUTER_WATCHDOG,policy_stdout_work,|r|bounded(r,MAX_STDERR))?;
 err.write_all(&diagnostics)?;let Some(code @ (0|1))=status.code()else{return Ok(if status.code()==Some(75){75}else{2})};
 if !diagnostics.is_empty(){return Err(io::Error::new(io::ErrorKind::Unsupported,"standalone selftest operational stderr has no completed semantic transcript"))}
 let work=captured.policy_work.as_ref().ok_or_else(||invalid("standalone transcript lost allowance"))?;let payload=text(&captured.bytes,code,selection,work)?;out.write_all(payload)?;Ok(code as u8)
}
pub(super)fn cli(args:&[String])->std::process::ExitCode{match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>std::process::ExitCode::from(code),Err(e)=>{eprintln!("analyze selftest: {e}");std::process::ExitCode::from(2)}}}
