//! Parser-free explicit codemod/fixture client. All source/model preparation,
//! write authorization, currentness and completed terminals remain backend-owned.
//! Uses the existing single dmbc process/daemon adapter and bounded framing.
use super::{NativeReportWork,capture_command_with_input,policy_stdout_work_using,bounded,MAX_STDERR,OUTER_WATCHDOG};
use crate::native_codemod_fixture_wire::{Binding,Question,Terminal};
use std::{io::{self,Write},path::PathBuf,process::{Command,ExitCode}};
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
enum Selection{Metadata(crate::native_codemod_cli::Parsed),Usage(String),Operation{program:PathBuf,binding:Binding}}
fn select(args:&[String])->io::Result<Selection>{
 let mut program=None;let mut oracle=None;let mut oracle_hash=None;let mut ordinary=vec!["analyze".to_owned()];let mut at=0;
 while let Some(arg)=args.get(at){at+=1;if arg=="--native-dmbc"{let value=PathBuf::from(args.get(at).ok_or_else(||invalid("native utility executable is missing"))?);at+=1;if program.replace(value).is_some(){return Err(invalid("native utility requires one executable"))}}else if let Some(value)=arg.strip_prefix("--native-dmbc="){if value.is_empty(){return Err(invalid("native utility executable is missing"))}if program.replace(PathBuf::from(value)).is_some(){return Err(invalid("native utility requires one executable"))}}else if arg=="--legacy-oracle"{let value=PathBuf::from(args.get(at).ok_or_else(||invalid("parity frozen oracle executable is missing"))?);at+=1;if oracle.replace(value).is_some(){return Err(invalid("parity requires exactly one frozen legacy oracle executable"))}}else if arg=="--legacy-oracle-sha256"{let value=args.get(at).ok_or_else(||invalid("parity frozen oracle SHA-256 is missing"))?.clone();at+=1;if oracle_hash.replace(value).is_some(){return Err(invalid("parity requires exactly one frozen legacy oracle SHA-256"))}}else{ordinary.push(arg.clone());}}
 let parsed=crate::cli_arguments::parse(ordinary);
 if parsed.cmd!="parity"&&(oracle.is_some()||oracle_hash.is_some()){return Err(invalid("frozen oracle flags apply only to parity"))}
 let question=match parsed.cmd.as_str(){
  "parity"=>{if parsed.lints.is_empty()&&!parsed.flags.iter().any(|flag|flag=="--all"){return Ok(Selection::Usage("analyze parity: name a lint or pass --all".into()))}
   let oracle=crate::native_codemod_fixture_wire::FrozenOracleBinding{image:oracle.ok_or_else(||invalid("parity requires explicit --legacy-oracle ABS_EXE"))?,sha256:oracle_hash.ok_or_else(||invalid("parity requires explicit --legacy-oracle-sha256 HEX"))?};oracle.validate()?;
   Question::Parity{selectors:if parsed.flags.iter().any(|flag|flag=="--all"){Vec::new()}else{parsed.lints.clone()},fixtures_only:parsed.flags.iter().any(|flag|flag=="--fixtures-only"),bless:parsed.flags.iter().any(|flag|flag=="--bless"),oracle}
  },
  "codemod"=>match crate::native_codemod_cli::parse(&parsed.flags){Ok(value @ (crate::native_codemod_cli::Parsed::Help|crate::native_codemod_cli::Parsed::List))=>return Ok(Selection::Metadata(value)),Ok(crate::native_codemod_cli::Parsed::Operation(question))=>question,Err(text)=>return Ok(Selection::Usage(text))},
  "sem" if parsed.flags.first().is_some_and(|name|name=="fixture")=>{let rest=&parsed.flags[1..];let Some(name)=rest.iter().find(|arg|!arg.starts_with("--"))else{return Ok(Selection::Usage("usage: analyze sem fixture LINT [--bless]".into()))};Question::Fixture{lint:name.clone(),bless:rest.iter().any(|arg|arg=="--bless")}},
  _=>return Err(invalid("native codemod/fixture/parity client received another ordinary command")),
 };
 let program=program.filter(|path|path.is_absolute()).ok_or_else(||invalid("native utility requires one absolute --native-dmbc executable"))?;
 let root=std::fs::canonicalize(crate::cli_arguments::find_root(parsed.root))?;let binding=Binding{schema:crate::native_codemod_fixture_wire::Schema::V2,root,question};binding.validate()?;
 Ok(Selection::Operation{program,binding})
}
fn may_write(question:&Question)->bool{match question{Question::CodemodList=>false,Question::Codemod{apply,revert,write_residue,..}=>*apply||*revert||*write_residue,Question::Fixture{bless,..}|Question::Parity{bless,..}=>*bless}}
fn unknown(stderr:&mut impl Write,question:&Question,reason:&str)->io::Result<()>{if may_write(question){writeln!(stderr,"native utility commit status unknown; source may have changed; {reason}")?;}Ok(())}
fn admit<'a>(bytes:&'a[u8],operational:&[u8],binding:&Binding,status:i32,work:&'a NativeReportWork)->io::Result<super::utility_streams::Admitted<'a,Terminal>>{
 super::utility_streams::admit::<Terminal>(bytes,operational,work,&|terminal|{terminal.require(binding)?;if terminal.exit!=status{return Err(invalid("native utility terminal exit differs from child status"))}Ok(())},|terminal|(terminal.stderr,terminal.stdout))
}
pub(super)fn run(args:&[String],stdout:&mut impl Write,stderr:&mut impl Write)->io::Result<u8>{
 let(program,binding)=match select(args)?{Selection::Metadata(parsed)=>{crate::native_codemod_cli::write_metadata(&parsed,stdout)?;return Ok(0)},Selection::Usage(text)=>{writeln!(stderr,"{text}")?;return Ok(2)},Selection::Operation{program,binding}=>(program,binding)};
 let work=NativeReportWork::new();binding.fingerprint()?;let input=super::utility_streams::input(&binding,&work)?;
 let mut command=Command::new(program);command.arg("analyze-codemod-fixture").arg("--root").arg(&binding.root).arg("--binding-stdin");
 let output_work=work.clone();let(status,out,operational,input_error)=match capture_command_with_input(command,input,OUTER_WATCHDOG,move|stream|policy_stdout_work_using(stream,output_work),|stream|bounded(stream,MAX_STDERR)){Ok(actual)=>actual,Err(first)=>{let _=unknown(stderr,&binding.question,"transport ended before a completed terminal was admitted");return Err(first)}};
 if let Some(first)=input_error{let _=stderr.write_all(&operational);let _=unknown(stderr,&binding.question,"request input failed before a completed terminal was admitted");return Err(first)}
 let Some(code @ 0..=2)=status.code()else{stderr.write_all(&operational)?;unknown(stderr,&binding.question,"child did not return a completed utility terminal")?;return Ok(if status.code()==Some(75){75}else{2})};
 let admitted=match admit(&out.bytes,&operational,&binding,code,&work){Ok(value)=>value,Err(first)=>{let _=unknown(stderr,&binding.question,"completed terminal was not admitted");return Err(first)}};
 let committed=admitted.terminal.committed;
 match admitted.publish(stdout,stderr){Ok(terminal)=>Ok(terminal.exit as u8),Err(first)=>{if may_write(&binding.question){let _=writeln!(stderr,"native utility completed with {committed} authenticated mutations; output could not be published");}Err(first)}}
}
pub(super)fn cli(args:&[String])->ExitCode{match run(args,&mut io::stdout().lock(),&mut io::stderr().lock()){Ok(code)=>ExitCode::from(code),Err(first)=>{eprintln!("analyze: {first}");ExitCode::from(2)}}}
#[cfg(test)]mod controls{
 use super::*;
 fn args(values:&[&str])->Vec<String>{values.iter().map(|value|(*value).to_owned()).collect()}
 #[test]fn original_codemod_help_and_list_need_no_root_or_compiler(){for name in ["help","--help","list"]{assert!(matches!(select(&args(&["codemod",name,"--root","definitely-absent-root"])).unwrap(),Selection::Metadata(_)));}}
 #[test]fn original_metadata_bytes_are_delivered_without_any_child_or_model(){let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(run(&args(&["codemod","list"]),&mut out,&mut err).unwrap(),0);let mut expected=Vec::new();crate::codemod_spec::write_list(&mut expected).unwrap();assert_eq!(out,expected);assert!(err.is_empty());}
 #[test]fn usage_preserves_original_codemod_and_fixture_words_before_root_resolution(){let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(run(&args(&["codemod","own_set","--path"]),&mut out,&mut err).unwrap(),2);assert_eq!(err,b"analyze codemod: --path needs a prefix\n");err.clear();assert_eq!(run(&args(&["sem","fixture","--bless"]),&mut out,&mut err).unwrap(),2);assert_eq!(err,b"usage: analyze sem fixture LINT [--bless]\n");assert!(out.is_empty());}
 #[test]fn metadata_output_preserves_first_os_error_without_later_fallback(){struct Fail;impl Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let error=run(&args(&["codemod","list"]),&mut Fail,&mut Vec::new()).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));}
 #[test]fn actual_mutation_flags_are_exhaustive_and_never_downgraded_by_revert_precedence(){assert!(!may_write(&Question::CodemodList));for(apply,revert,write_residue)in[(true,false,false),(false,true,false),(false,false,true),(true,true,true)]{assert!(may_write(&Question::Codemod{name:"own_set".into(),apply,revert,write_residue,sites:false,paths:Vec::new()}));}assert!(may_write(&Question::Fixture{lint:"tracked".into(),bless:true}));}
}

#[cfg(test)]mod parity_controls{
 use super::*;
 fn args(values:&[&str])->Vec<String>{values.iter().map(|value|(*value).to_owned()).collect()}
 #[test]fn parity_original_missing_selection_usage_does_not_require_root_or_oracle(){let(mut out,mut err)=(Vec::new(),Vec::new());assert_eq!(run(&args(&["parity","--fixtures-only"]),&mut out,&mut err).unwrap(),2);assert_eq!(err,b"analyze parity: name a lint or pass --all\n");assert!(out.is_empty());}
 #[test]fn parity_has_no_implicit_oracle_or_reference_build(){for values in[vec!["parity","scheduler"],vec!["parity","--all"]]{let error=select(&args(&values)).err().unwrap();assert!(error.to_string().contains("explicit --legacy-oracle"));}}
 #[test]fn oracle_options_cannot_leak_into_codemod_or_fixture(){for command in[vec!["codemod","list","--legacy-oracle","E:/frozen.exe"],vec!["sem","fixture","tracked","--legacy-oracle-sha256","abc"]]{let error=select(&args(&command)).err().unwrap();assert!(error.to_string().contains("only to parity"));}}
 #[test]fn oracle_pairs_are_unique_and_values_are_not_lint_names(){for values in[vec!["parity","scheduler","--legacy-oracle","E:/one.exe","--legacy-oracle","E:/two.exe"],vec!["parity","scheduler","--legacy-oracle-sha256","a","--legacy-oracle-sha256","b"]]{let error=select(&args(&values)).err().unwrap();assert!(error.to_string().contains("exactly one"));}}
 #[test]fn explicit_oracle_values_are_removed_before_original_selector_parsing(){
  let executable=if cfg!(windows){"E:/frozen legacy Analyze.exe"}else{"/frozen legacy Analyze"};let native=if cfg!(windows){"E:/published dmbc.exe"}else{"/published dmbc"};let hash="a".repeat(64);
  let values=["parity","scheduler,tracked","--fixtures-only","--bless","--legacy-oracle",executable,"--legacy-oracle-sha256",hash.as_str(),"--native-dmbc",native,"--root","."];
  let Selection::Operation{binding,..}=select(&args(&values)).unwrap()else{panic!("explicit native utility operation must be selected")};
  let Question::Parity{selectors,fixtures_only,bless,oracle}=binding.question else{panic!("parity variant")};assert_eq!(selectors,["scheduler","tracked"]);assert!(fixtures_only&&bless);assert_eq!(oracle.image,PathBuf::from(executable));assert_eq!(oracle.sha256,hash);
  let mut all=args(&values);all.push("--all".into());let Selection::Operation{binding,..}=select(&all).unwrap()else{panic!("all operation")};assert!(matches!(binding.question,Question::Parity{selectors,..}if selectors.is_empty()));
 }
 #[test]fn parity_bless_is_the_only_parity_may_write_shape(){let oracle=crate::native_codemod_fixture_wire::FrozenOracleBinding{image:PathBuf::from(if cfg!(windows){"E:/frozen.exe"}else{"/frozen"}),sha256:"a".repeat(64)};for bless in[false,true]{assert_eq!(may_write(&Question::Parity{selectors:vec!["scheduler".into()],fixtures_only:true,bless,oracle:oracle.clone()}),bless);}}
}

#[cfg(test)]mod equals_executable_controls{
 use super::*;
 fn args(values:&[&str])->Vec<String>{values.iter().map(|value|(*value).to_owned()).collect()}
 #[test]fn equals_executable_route_preserves_actual_codemod_question(){
  let image=if cfg!(windows){"E:/published dmbc.exe"}else{"/published dmbc"};let equal=format!("--native-dmbc={image}");
  let Selection::Operation{program,binding}=select(&args(&["codemod","own_set",&equal,"--root","."])).unwrap()else{panic!("explicit codemod route")};
  assert_eq!(program,PathBuf::from(image));assert!(matches!(binding.question,Question::Codemod{name,..}if name=="own_set"));
 }
 #[test]fn equal_and_split_executable_forms_cannot_supply_two_compilers(){
  let values=args(&["codemod","own_set","--native-dmbc=/one","--native-dmbc","/two"]);assert!(select(&values).err().unwrap().to_string().contains("one executable"));
  assert!(select(&args(&["codemod","own_set","--native-dmbc="])).err().unwrap().to_string().contains("missing"));
 }
}
