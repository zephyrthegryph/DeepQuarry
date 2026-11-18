//! Ordinary generation syntax and text over the existing resident native GEN.
use super::{capture_command,generation_stdout,bounded,OUTER_WATCHDOG,MAX_STDERR,MAX_GENERATION_OUTPUT,MAX_BATCH_HEADER};
use std::{io::{self,Write},path::PathBuf,process::Command};
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
#[derive(Debug)]struct DeliveryFailure{actual:io::Error,committed:Option<bool>}
impl std::fmt::Display for DeliveryFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"{}",self.actual)?;match self.committed{Some(true)=>write!(f,"; generation outputs were committed"),Some(false)=>Ok(()),None=>write!(f,"; generation commit status is unknown; outputs may have changed")}}}
impl std::error::Error for DeliveryFailure{fn source(&self)->Option<&(dyn std::error::Error+'static)>{Some(&self.actual)}}
fn delivery(actual:io::Error,committed:Option<bool>)->io::Error{io::Error::new(actual.kind(),DeliveryFailure{actual,committed})}
fn incomplete_exit(code:Option<i32>,diagnostics:&mut impl Write)->io::Result<u8>{diagnostics.write_all(b"analyze gen: native generation ended without a completed terminal; commit status is unknown; outputs may have changed\n").map_err(|actual|delivery(actual,None))?;Ok(if code==Some(75){75}else{2})}
#[derive(Debug,PartialEq,Eq)]struct Invocation{program:PathBuf,root:PathBuf,cache:Option<PathBuf>,check:bool,names:Vec<String>}
fn options(args:&[String],usage:bool)->io::Result<Invocation>{
 if usage{return Err(io::Error::new(io::ErrorKind::Unsupported,"native generation has no qualified DQ_ALLOW_USAGE export"))}
 let(mut program,mut root,mut cache,mut check)=(None,None,None,false);let mut names=Vec::new();let mut at=0;
 while at<args.len(){let arg=&args[at];at+=1;match arg.as_str(){
  "--native-dmbc"|"--root"|"--cache-root"=>{let value=PathBuf::from(args.get(at).filter(|value|!value.is_empty()&&!value.starts_with("--")).ok_or_else(||invalid("generation path option needs a value"))?);at+=1;let slot=match arg.as_str(){"--native-dmbc"=>&mut program,"--root"=>&mut root,_=>&mut cache};if slot.replace(value).is_some(){return Err(invalid("duplicate generation path option"))}},
  "--check"=>check=true,
  value if value.starts_with("--")=>return Err(io::Error::new(io::ErrorKind::Unsupported,format!("ordinary native generation has no qualified implementation for {value}"))),
  value=>names.push(value.to_owned()),
 }}
 let program=program.ok_or_else(||invalid("native generation requires --native-dmbc ABSOLUTE_EXE"))?;if !program.is_absolute(){return Err(invalid("native compiler path must be absolute"))}if cache.as_ref().is_some_and(|path|!path.is_absolute()){return Err(invalid("generation cache must be absolute"))}
 let root=std::path::absolute(crate::cli_arguments::find_root(root))?;Ok(Invocation{program,root,cache,check,names})
}
#[derive(serde::Deserialize)]#[serde(deny_unknown_fields)]struct Header{schema:String,status:String,clean:bool,committed:bool,length:u64,hash:crate::selected_exclusions_wire::Hex128}
fn text<'a>(bytes:&'a[u8],code:i32)->io::Result<(&'a[u8],bool)>{
 let end=bytes.iter().take(MAX_BATCH_HEADER).position(|byte|*byte==b'\n').ok_or_else(||invalid("ordinary generation terminal absent"))?;
 let header:Header=serde_json::from_slice(&bytes[..end]).map_err(io::Error::other)?;let body=&bytes[end+1..];
 if !matches!(code,0|1)||header.schema!="native-ordinary-generation-v1"||header.status!="completed"||header.clean!=(code==0)||header.length!=body.len()as u64||body.len()>MAX_GENERATION_OUTPUT||header.hash.0!=xxhash_rust::xxh3::xxh3_128(body){return Err(invalid("ordinary generation text differs from its complete sealed report"))}Ok((body,header.committed))
}
fn run(args:&[String],output:&mut impl Write,diagnostics:&mut impl Write)->io::Result<u8>{
 let invocation=options(args,std::env::var_os("DQ_ALLOW_USAGE").is_some())?;let mut command=Command::new(invocation.program);command.arg("generate-ordinary").arg("--workspace").arg(invocation.root);if let Some(cache)=invocation.cache{command.arg("--cache-root").arg(cache);}if invocation.check{command.arg("--check");}command.args(invocation.names);
 let(status,bytes,stderr)=capture_command(command,OUTER_WATCHDOG,generation_stdout,|input|bounded(input,MAX_STDERR)).map_err(|actual|delivery(actual,None))?;diagnostics.write_all(&stderr).map_err(|actual|delivery(actual,None))?;
 let Some(code @ (0|1))=status.code()else{return incomplete_exit(status.code(),diagnostics)};let(body,committed)=text(&bytes,code).map_err(|actual|delivery(actual,None))?;output.write_all(body).map_err(|actual|delivery(actual,Some(committed)))?;Ok(code as u8)
}
pub(super)fn cli(args:&[String])->std::process::ExitCode{match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>std::process::ExitCode::from(code),Err(error)=>{eprintln!("analyze gen: {error}");std::process::ExitCode::from(2)}}}
#[cfg(test)]mod tests{
 use super::*;
 fn args()->Vec<String>{vec!["--native-dmbc".into(),if cfg!(windows){"E:/compiler/dmbc.exe".into()}else{"/compiler/dmbc".into()},"--root".into(),"actual-relative-root".into()]}
 #[test]fn ordinary_gen_client_preserves_names_check_and_explicitly_denies_unqualified_modes(){let mut a=args();a.extend(["reads".into(),"--check".into(),"deps".into(),"reads".into()]);let parsed=options(&a,false).unwrap();assert!(parsed.root.is_absolute());assert!(parsed.check);assert_eq!(parsed.names,["reads","deps","reads"]);for flag in ["--timing","--selftest","--no-selftest","--changed-only"]{let mut a=args();a.push(flag.into());assert_eq!(options(&a,false).unwrap_err().kind(),io::ErrorKind::Unsupported)}assert_eq!(options(&args(),true).unwrap_err().kind(),io::ErrorKind::Unsupported);}
 #[test]fn ordinary_gen_text_requires_complete_status_and_exact_bytes_before_delivery(){let body=b"fresh /actual/deps.dm\n";let encode=|clean:bool|{let mut bytes=serde_json::to_vec(&serde_json::json!({"schema":"native-ordinary-generation-v1","status":"completed","clean":clean,"committed":false,"length":body.len(),"hash":crate::selected_exclusions_wire::Hex128(xxhash_rust::xxh3::xxh3_128(body))})).unwrap();bytes.push(b'\n');bytes.extend_from_slice(body);bytes};let mut bytes=encode(true);assert_eq!(text(&bytes,0).unwrap().0,body);assert!(text(&bytes,1).is_err());assert!(text(&bytes,2).is_err());*bytes.last_mut().unwrap()^=1;assert!(text(&bytes,0).is_err());bytes=encode(false);assert_eq!(text(&bytes,1).unwrap().0,body);}
 #[test]fn ordinary_gen_no_terminal_exit_preserves_status_and_unknown_commit_with_first_io(){for code in [Some(2),Some(75),None]{let mut text=Vec::new();assert_eq!(incomplete_exit(code,&mut text).unwrap(),if code==Some(75){75}else{2});assert!(String::from_utf8(text).unwrap().contains("commit status is unknown; outputs may have changed"));}struct Stop;impl Write for Stop{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no flush")}}let error=incomplete_exit(Some(2),&mut Stop).unwrap_err();let failure=error.get_ref().unwrap().downcast_ref::<DeliveryFailure>().unwrap();assert_eq!(failure.actual.raw_os_error(),Some(1450));assert_eq!(failure.committed,None);}
}
