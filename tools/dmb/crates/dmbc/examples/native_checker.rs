//! Nondefault standalone qualification adapter. One owned host, not a claim of
//! cross-process daemon reuse. Production transport must call the same core
//! through the EXISTING daemon/session before any default activation.
use dmbc::{native_checker::{self,Request},runner_host::BuildHost};
fn main(){
 let cache=match dm_cache::Cache::default_root(){Ok(path)=>path,Err(error)=>{eprintln!("native Checker unavailable: {error}");std::process::exit(2)}};
 let request=match Request::from_arguments(&std::env::args().skip(1).collect::<Vec<_>>(),cache){Ok(request)=>request,Err(error)=>{eprintln!("native Checker unavailable: {error}");std::process::exit(2)}};
 let mut host=BuildHost::default();let(stdout,stderr)=(std::io::stdout(),std::io::stderr());
 match native_checker::run(request,&mut host,&mut stdout.lock(),&mut stderr.lock()){
  Ok(result)=>std::process::exit(result.exit_code),Err(actual)=>{eprintln!("native Checker unavailable: {actual}");std::process::exit(2)},
 }
}
