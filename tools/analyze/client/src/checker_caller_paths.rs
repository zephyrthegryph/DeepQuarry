//! Caller-side CLI DATA selection. No source receipt, model or completion grant.
use std::{io,path::{Path,PathBuf}};
#[derive(Debug,PartialEq,Eq)]pub enum Action{Check(Resolved),Unknown(String)}
#[derive(Debug,PartialEq,Eq)]pub struct Resolved{pub project:PathBuf,pub display:PathBuf,pub caller_directory:Option<PathBuf>,pub configuration:Option<PathBuf>,pub json:bool}
fn invalid(message:&str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
/// Reuses the reference's actual directory iteration order. The default is only
/// a fallback; no sorting, parent search or guessed checkout project is applied.
pub fn detect_environment(cwd:&Path)->io::Result<Option<PathBuf>>{
 let mut selected=None;for entry in std::fs::read_dir(cwd)?.flatten(){let name=entry.file_name();let text=name.to_string_lossy();if text.ends_with(".dme"){selected=Some(PathBuf::from(&name));if text!="tgstation.dme"{break}}}Ok(selected)
}
/// Pure original-order selection, before even requesting the caller cwd.
/// Native executable syntax is consumed only by the thin client. All ordinary
/// values retain their roles and repeated -e/-c values use the final value.
#[derive(Debug,PartialEq,Eq)]pub enum Selection{Check(Arguments),Unknown(String)}
#[derive(Debug,PartialEq,Eq)]pub struct Arguments{pub program:Option<PathBuf>,pub ordinary:Vec<String>,display:Option<PathBuf>,configuration:Option<PathBuf>,json:bool}
pub fn select(arguments:&[String],allow_native:bool)->io::Result<Selection>{
 let(mut program,mut ordinary,mut display,mut configuration,mut json)=(None,Vec::new(),None,None,false);let mut args=arguments.iter();
 while let Some(arg)=args.next(){match arg.as_str(){
  "--native-dmbc" if allow_native=>{let path=PathBuf::from(args.next().ok_or_else(||invalid("--native-dmbc needs an absolute executable"))?);if !path.is_absolute()||program.replace(path).is_some(){return Err(invalid("Checker needs one absolute native executable"))}},
  "-e"|"-c"=>{let value=args.next().ok_or_else(||invalid("Checker option needs its actual value"))?;ordinary.push(arg.clone());ordinary.push(value.clone());if arg=="-e"{display=Some(PathBuf::from(value))}else{configuration=Some(PathBuf::from(value))}},
  "--json"=>{json=true;ordinary.push(arg.clone());},
  "--parse-only"|"--version"|"-V"=>return Err(io::Error::new(io::ErrorKind::Unsupported,"this native Checker has not issued that reference CLI mode")),
  other=>return Ok(Selection::Unknown(other.to_owned())),
 }}
 Ok(Selection::Check(Arguments{program,ordinary,display,configuration,json}))
}
/// Fetch the actual caller directory only for an argument that needs it.
/// Absolute explicit project/config paths add no cwd dependency.
pub fn resolve_selected_using(arguments:Arguments,cwd:impl FnOnce()->io::Result<PathBuf>)->io::Result<Resolved>{
 let needs_cwd=arguments.display.as_ref().is_none_or(|path|!path.is_absolute())||arguments.configuration.as_ref().is_some_and(|path|!path.is_absolute());
 let caller=if needs_cwd{let actual=cwd()?;if !actual.is_absolute(){return Err(invalid("Checker caller directory must be absolute"))}Some(actual)}else{None};
 let display=match arguments.display{Some(path)=>path,None=>detect_environment(caller.as_deref().ok_or_else(||invalid("Checker autodetection requires its actual caller directory"))?)?.ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"no .dme found"))?};
 let requested=if display.is_absolute(){display.clone()}else{caller.as_ref().ok_or_else(||invalid("relative Checker project requires its actual caller directory"))?.join(&display)};let project=std::fs::canonicalize(&requested)?;
 let configuration=arguments.configuration.map(|path|if path.is_absolute(){Ok(path)}else{caller.as_ref().map(|cwd|cwd.join(path)).ok_or_else(||invalid("relative Checker config requires its actual caller directory"))}).transpose()?;
 if display.as_os_str().len()>65536||caller.as_ref().is_some_and(|cwd|cwd.as_os_str().len()>65536)||configuration.as_ref().is_some_and(|p|p.as_os_str().len()>65536){return Err(invalid("Checker caller path exceeds existing path bound"))}
 let caller_directory=if display.is_absolute(){None}else{Some(std::fs::canonicalize(caller.as_ref().ok_or_else(||invalid("relative Checker display requires its actual caller directory"))?)?)};
 Ok(Resolved{project,display,caller_directory,configuration,json:arguments.json})
}
pub fn resolve_selected(arguments:Arguments,cwd:&Path)->io::Result<Resolved>{resolve_selected_using(arguments,||Ok(cwd.to_owned()))}
pub fn resolve(arguments:&[String],cwd:&Path)->io::Result<Action>{match select(arguments,false)?{Selection::Check(arguments)=>resolve_selected(arguments,cwd).map(Action::Check),Selection::Unknown(arg)=>Ok(Action::Unknown(arg))}}
impl Resolved{pub fn requested_source(&self)->Option<PathBuf>{if self.display.is_absolute(){Some(self.display.clone())}else{self.caller_directory.as_ref().map(|cwd|cwd.join(&self.display))}}}

#[cfg(test)]mod tests{use super::*;
 #[test]fn checker_caller_unknown_and_missing_values_do_not_touch_filesystem(){let absent=Path::new(if cfg!(windows){"E:/absent-checker-caller"}else{"/absent-checker-caller"});assert_eq!(resolve(&["--unknown".into(),"-e".into()],absent).unwrap(),Action::Unknown("--unknown".into()));assert_eq!(resolve(&["-e".into()],absent).unwrap_err().kind(),io::ErrorKind::InvalidInput);for flag in ["--parse-only","--version","-V"]{assert_eq!(resolve(&[flag.into()],absent).unwrap_err().kind(),io::ErrorKind::Unsupported)}}
}

#[cfg(test)]mod actual_caller_controls{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};static NEXT:AtomicUsize=AtomicUsize::new(0);
 fn fixture()->PathBuf{let base=if cfg!(windows){PathBuf::from("E:/dq-cache/test-scratch")}else{std::env::temp_dir()};let path=base.join(format!("checker-caller-{}-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));std::fs::create_dir_all(&path).unwrap();std::fs::canonicalize(path).unwrap()}
 #[test]fn actual_checker_caller_relative_project_config_and_last_values_keep_display(){
  let root=fixture();std::fs::write(root.join("chosen.dme"),"/proc/p()\n    return\n").unwrap();std::fs::write(root.join("config.toml"),"").unwrap();
  let Action::Check(actual)=resolve(&["-e".into(),"missing.dme".into(),"-c".into(),"missing.toml".into(),"-e".into(),"./chosen.dme".into(),"-c".into(),"config.toml".into(),"--json".into()],&root).unwrap()else{panic!("real selection")};assert_eq!(actual.display,PathBuf::from("./chosen.dme"));assert_eq!(actual.project,std::fs::canonicalize(root.join("chosen.dme")).unwrap());assert_eq!(actual.configuration,Some(root.join("config.toml")));assert_eq!(actual.caller_directory,Some(root.clone()));assert!(actual.json);assert_eq!(std::fs::canonicalize(actual.requested_source().unwrap()).unwrap(),actual.project);std::fs::remove_dir_all(root).unwrap();
 }
 #[test]fn actual_checker_caller_autodetect_default_then_real_alternative_and_no_parent_search(){
  let root=fixture();assert_eq!(resolve(&[],&root).unwrap_err().kind(),io::ErrorKind::NotFound);std::fs::write(root.join("tgstation.dme"),"").unwrap();let Action::Check(default)=resolve(&[],&root).unwrap()else{panic!()};assert_eq!(default.display,PathBuf::from("tgstation.dme"));std::fs::write(root.join("chosen.dme"),"").unwrap();std::fs::write(root.join("UPPER.DME"),"").unwrap();let Action::Check(chosen)=resolve(&[],&root).unwrap()else{panic!()};assert_eq!(chosen.display,PathBuf::from("chosen.dme"));let child=root.join("empty");std::fs::create_dir(&child).unwrap();assert_eq!(resolve(&[],&child).unwrap_err().kind(),io::ErrorKind::NotFound);std::fs::remove_dir_all(root).unwrap();
 }
 #[test]fn actual_checker_caller_switch_looking_value_is_consumed_before_later_unknown(){
  let root=fixture();std::fs::write(root.join("--json"),"").unwrap();let Action::Check(actual)=resolve(&["-e".into(),"--json".into()],&root).unwrap()else{panic!()};assert!(!actual.json);assert_eq!(actual.display,PathBuf::from("--json"));assert_eq!(resolve(&["-e".into(),"missing.dme".into(),"--bad".into()],&root).unwrap(),Action::Unknown("--bad".into()));std::fs::remove_dir_all(root).unwrap();
 }
}

#[cfg(test)]mod selective_caller_directory_controls{use super::*;
 #[test]fn actual_absolute_project_with_relative_config_requests_cwd_once_but_retains_no_display_caller(){
  let base=if cfg!(windows){PathBuf::from("E:/dq-cache/test-scratch")}else{std::env::temp_dir()};std::fs::create_dir_all(&base).unwrap();let root=std::fs::canonicalize(base).unwrap();let path=root.join(format!("checker-relative-config-{}-{}.dme",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));std::fs::write(&path,b"/proc/p()\n    return\n").unwrap();
  let Selection::Check(selected)=select(&["-e".into(),path.to_string_lossy().into_owned(),"-c".into(),"relative.toml".into()],false).unwrap()else{panic!()};let mut calls=0;let actual=resolve_selected_using(selected,||{calls+=1;Ok(root.clone())}).unwrap();assert_eq!(calls,1);assert_eq!(actual.caller_directory,None);assert_eq!(actual.configuration,Some(root.join("relative.toml")));std::fs::remove_file(path).unwrap();
 }
}
