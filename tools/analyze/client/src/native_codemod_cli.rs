//! Exact ordinary codemod argument precedence, without a semantic parser.
//! The dispatcher still admits the typed request and resolves the real compiler.
use crate::{codemod_spec,native_codemod_fixture_wire::Question};
pub enum Parsed{Help,List,Operation(Question)}
pub fn parse(args:&[String])->Result<Parsed,String>{
 let name=args.first().map(String::as_str).unwrap_or("help");
 if matches!(name,"help"|"--help"){return Ok(Parsed::Help)}
 if name=="list"{return Ok(Parsed::List)}
 let Some(spec)=codemod_spec::find(name)else{return Err(format!("analyze codemod: no codemod named {:?}; `analyze codemod list`",name))};
 let(mut apply,mut revert,mut write_residue,mut sites)=(false,false,false,false);let mut paths=Vec::new();let mut args=args.iter().skip(1);
 while let Some(arg)=args.next(){match arg.as_str(){
  "--apply"=>apply=true,"--check"=>(),"--revert"=>revert=true,"--write-residue"=>write_residue=true,"--sites"=>sites=true,
  "--path"=>match args.next(){Some(path)=>paths.push(path.replace('\\',"/")),None=>return Err("analyze codemod: --path needs a prefix".into())},
  other=>return Err(format!("analyze codemod: unknown argument {:?}",other)),
 }}
 // The old revert branch precedes the whole-tree residue filter check.
 if !revert&&write_residue&&!paths.is_empty(){return Err("analyze codemod: --write-residue describes the whole tree; drop --path".into())}
 Ok(Parsed::Operation(Question::Codemod{name:spec.name.to_owned(),apply,revert,write_residue,sites,paths}))
}
/// Help/list need no project/configuration/model acquisition. Both executables
/// borrow the exact same original metadata text and checked output formatter.
pub fn write_metadata(parsed:&Parsed,out:&mut dyn std::io::Write)->std::io::Result<bool>{
 match parsed{Parsed::Help=>{writeln!(out,"{}",codemod_spec::HELP)?;Ok(true)},Parsed::List=>{codemod_spec::write_list(out)?;Ok(true)},Parsed::Operation(_)=>Ok(false)}
}

#[cfg(test)]mod controls{
 use super::*;
 fn args(values:&[&str])->Vec<String>{values.iter().map(|v|(*v).to_owned()).collect()}
 #[test]fn ordinary_argument_order_keeps_revert_before_residue_filter_and_real_usage_errors(){
  assert!(matches!(parse(&args(&["list","--ignored-by-original-list"])).unwrap(),Parsed::List));
  let Parsed::Operation(Question::Codemod{revert,apply,paths,..})=parse(&args(&["own_set","--write-residue","--path","code\\probe","--apply","--revert"])).unwrap()else{panic!("actual operation expected")};
  assert!(revert&&apply);assert_eq!(paths,["code/probe"]);
  assert_eq!(parse(&args(&["own_set","--write-residue","--path","code"])).err().unwrap(),"analyze codemod: --write-residue describes the whole tree; drop --path");
  assert_eq!(parse(&args(&["own_set","--path"])).err().unwrap(),"analyze codemod: --path needs a prefix");
  assert_eq!(parse(&args(&["own_set","--other"])).err().unwrap(),"analyze codemod: unknown argument \"--other\"");
 }
 #[test]fn actual_metadata_writer_preserves_original_io_without_acquiring_a_model(){
  struct Denied;impl std::io::Write for Denied{fn write(&mut self,_:&[u8])->std::io::Result<usize>{Err(std::io::Error::from_raw_os_error(1450))}fn flush(&mut self)->std::io::Result<()>{Ok(())}}
  for actual in [Parsed::Help,Parsed::List]{assert_eq!(write_metadata(&actual,&mut Denied).unwrap_err().raw_os_error(),Some(1450));}
 }
}
