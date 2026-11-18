//! Explicit ordinary-syntax entry; enabling the production default is separate.
//! Uses the build helper's existing published-image layout and explicit
//! DQ_DMBC_BIN override. Never builds/publishes an image or selects a daemon.
use std::{io,path::{Path,PathBuf},process::ExitCode};
fn compiler_from_directory(explicit:Option<std::ffi::OsString>,directory:&Path)->io::Result<PathBuf>{
 let image=if let Some(explicit)=explicit.filter(|value|!value.is_empty()){
  let path=PathBuf::from(explicit);
  if !path.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"DQ_DMBC_BIN must name an absolute executable"))}path
 }else{
  // Same <bin>/current -> <bin>/v/<16 lowercase hex>/dmbc layout as
  // tools/build/lib/dmbc_cache.ts. Read each time; retain no pointer/image cache.
  let executable=if cfg!(windows){"dmbc.exe"}else{"dmbc"};
  match std::fs::read_to_string(directory.join("current")){
   Ok(pointer)=>{let id=pointer.trim();if id.len()!=16||!id.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(io::Error::new(io::ErrorKind::InvalidData,"published compiler pointer is not a 16-digit lowercase content ID"))}directory.join("v").join(id).join(executable)},
   Err(actual)if actual.kind()==io::ErrorKind::NotFound=>directory.join(executable),
   Err(actual)=>return Err(actual),
  }
 };
 if !image.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"published compiler directory must be absolute"))}
 if !std::fs::metadata(&image)?.is_file(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"selected compiler is not a file"))}Ok(image)
}
fn compiler()->io::Result<PathBuf>{
 let explicit=std::env::var_os("DQ_DMBC_BIN").filter(|value|!value.is_empty());
 if explicit.is_some(){return compiler_from_directory(explicit,Path::new(""))}
 let directory=match std::env::var_os("DQ_DMBC_BIN_DIR").filter(|value|!value.is_empty()){
  Some(path)=>{let path=PathBuf::from(path);if path.is_absolute(){path}else{std::env::current_dir()?.join(path)}},
  None if cfg!(windows)&&Path::new("E:/dq-cache").is_dir()=>PathBuf::from("E:/dq-cache/dmb-bin"),
  None=>std::env::var_os(if cfg!(windows){"USERPROFILE"}else{"HOME"}).map(PathBuf::from).ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"cannot locate the published compiler directory"))?.join(".cache/dq/dmb-bin"),
 };
 compiler_from_directory(None,&directory)
}
fn arguments(args:&[String],compiler:&Path)->io::Result<Vec<String>>{
 if !compiler.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"resolved native compiler must be absolute"))}
 let cmd=args.first().map(String::as_str).unwrap_or("help");
 if !matches!(cmd,"check"|"report"|"timing"|"baseline"|"gen"|"fix"|"selftest"|"list"|"sem"|"base-vars-dead"){return Err(io::Error::new(io::ErrorKind::Unsupported,"ordinary native command has no implemented route; no legacy fallback"))}
 if args.iter().any(|a|a=="--native-dmbc"||a.starts_with("--native-dmbc=")){return Err(io::Error::new(io::ErrorKind::InvalidInput,"ordinary route compiler is supplied exactly once by the actual resolver"))}
 let mut result=args.to_vec();result.extend(["--native-dmbc".into(),compiler.to_string_lossy().into_owned()]);
 if matches!(cmd,"check"|"report"|"timing"){if args.iter().any(|a|a.starts_with("--native-full-registry")){return Err(io::Error::new(io::ErrorKind::InvalidInput,"ordinary route registry mode is supplied once"))}result.push("--native-full-registry".into())}Ok(result)
}
pub(super)fn cli(args:&[String])->ExitCode{
 if matches!(args.first().map(String::as_str),None|Some("help"|"--help"|"-h")){return super::metadata_utility_cli(args).expect("closed help action")}
 let run=compiler().and_then(|compiler|arguments(args,&compiler));
 match run{Err(e)=>{eprintln!("analyze: {e}");ExitCode::from(2)},Ok(args)=>{if matches!(args[0].as_str(),"sem"|"base-vars-dead"){return super::sem_utility_cli(&args)}if args[0]=="selftest"{return super::standalone_selftest_cli(&args)}if args[0]=="list"{return super::metadata_utility_cli(&args).expect("closed list action")}super::workspace_check(&args).unwrap_or_else(||{eprintln!("analyze: native ordinary dispatcher did not accept its exact route");ExitCode::from(2)})}}
}

#[cfg(test)]mod controls{
 use super::*;
 struct Images(PathBuf);
 impl Images{fn new()->Self{static NEXT:std::sync::atomic::AtomicUsize=std::sync::atomic::AtomicUsize::new(0);let root=std::env::temp_dir().join(format!("dq-published-client-{}-{}",std::process::id(),NEXT.fetch_add(1,std::sync::atomic::Ordering::Relaxed)));std::fs::create_dir(&root).unwrap();Self(std::fs::canonicalize(root).unwrap())}fn image(&self,version:Option<&str>)->PathBuf{let parent=version.map_or_else(||self.0.clone(),|id|self.0.join("v").join(id));std::fs::create_dir_all(&parent).unwrap();let image=parent.join(if cfg!(windows){"dmbc.exe"}else{"dmbc"});std::fs::write(&image,b"not executed: resolver fixture only").unwrap();image}}
 impl Drop for Images{fn drop(&mut self){std::fs::remove_dir_all(&self.0).unwrap();}}
 #[test]fn published_pointer_is_read_again_and_explicit_image_wins_without_a_daemon_or_publication(){
  let images=Images::new();let first=images.image(Some("0123456789abcdef"));let next=images.image(Some("fedcba9876543210"));let pointer=images.0.join("current");
  std::fs::write(&pointer,"0123456789abcdef\n").unwrap();assert_eq!(compiler_from_directory(None,&images.0).unwrap(),first);
  std::fs::write(&pointer,"fedcba9876543210\n").unwrap();assert_eq!(compiler_from_directory(None,&images.0).unwrap(),next,"no retained stale pointer");
  std::fs::write(&pointer,"invalid pointer").unwrap();assert_eq!(compiler_from_directory(Some(first.clone().into_os_string()),&images.0).unwrap(),first,"explicit image wins even if the published pointer is invalid");
  assert_eq!(compiler_from_directory(None,&images.0).unwrap_err().kind(),io::ErrorKind::InvalidData);
 }
 #[test]fn absent_pointer_uses_existing_layout_but_missing_version_never_silently_downgrades(){
  let images=Images::new();let legacy=images.image(None);assert_eq!(compiler_from_directory(None,&images.0).unwrap(),legacy);
  std::fs::write(images.0.join("current"),"0123456789abcdef").unwrap();assert_eq!(compiler_from_directory(None,&images.0).unwrap_err().kind(),io::ErrorKind::NotFound);
  assert_eq!(compiler_from_directory(Some("relative-dmbc".into()),&images.0).unwrap_err().kind(),io::ErrorKind::InvalidInput);
 }
 #[test]fn explicit_ordinary_routes_use_one_supplied_compiler_and_keep_unknowns_out_of_legacy(){
  let compiler=Path::new(if cfg!(windows){"E:/actual/dmbc.exe"}else{"/actual/dmbc"});
  for cmd in ["check","report","timing","baseline","gen","fix","selftest","list","sem","base-vars-dead"]{let out=arguments(&[cmd.into(),"--root".into(),"actual-root".into()],compiler).unwrap();assert_eq!(out.iter().filter(|a|a.as_str()=="--native-dmbc").count(),1);assert_eq!(out.last().is_some_and(|a|a=="--native-full-registry"),matches!(cmd,"check"|"report"|"timing"));}
  assert!(arguments(&["check".into()],Path::new("relative")).is_err());assert_eq!(arguments(&["codemod".into()],compiler).unwrap_err().kind(),io::ErrorKind::Unsupported);assert!(arguments(&["check".into(),"--native-dmbc".into(),"other".into()],compiler).is_err());
 }
}
