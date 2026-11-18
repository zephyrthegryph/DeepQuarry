//! Typed utility DATA only. The backend must prepare/validate its actual
//! model/raw/config/physical closure; these fields issue no source authority.
use serde::{Deserialize,Serialize};
use std::{io,path::PathBuf};
use crate::selected_exclusions_wire::{Frame,RawSelectedFrame,Seal,MAX_STREAM};
#[derive(Clone,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FrozenOracleBinding{pub image:PathBuf,pub sha256:String}
impl FrozenOracleBinding{pub fn validate(&self)->io::Result<()>{if !self.image.is_absolute()||self.sha256.len()!=64||!self.sha256.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"parity requires an explicit absolute frozen legacy Analyze executable and its lowercase SHA-256"))}Ok(())}}
#[derive(Clone,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub enum Question{
 CodemodList,
 Codemod{ name:String,apply:bool,revert:bool,write_residue:bool,sites:bool,paths:Vec<String> },
 Fixture{ lint:String,bless:bool },
 Parity{selectors:Vec<String>,fixtures_only:bool,bless:bool,oracle:FrozenOracleBinding},
}
#[derive(Clone,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Binding{pub schema:Schema,pub root:PathBuf,pub question:Question}
impl Binding{
 pub fn validate(&self)->io::Result<()>{
  if !self.root.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native utility needs its actual absolute caller root"))}
  // Lint selectors are DATA here (real names include sem/keys and sys/...).
  // Backend captured-config validation precedes actual registry selection,
  // which must precede deriving a physical fixture directory from that name.
  let valid=|s:&str|!s.is_empty()&&(s.len() as u64)<=MAX_STREAM&&!s.as_bytes().contains(&0);
  match &self.question{
   Question::CodemodList=>(),
   Question::Codemod{name,paths,..}=>{
    if !crate::codemod_spec::ALL.iter().any(|spec|spec.name==name.as_str()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"unknown native codemod question"))}
    if paths.len()>4096||paths.iter().any(|p|p.len()>32768||p.bytes().any(|b|b==0||b<32)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"invalid native codemod prefix DATA"))}
   },
   Question::Parity{selectors,oracle,..}=>{oracle.validate()?;if selectors.len()>4096||selectors.iter().any(|s|!valid(s)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"invalid parity selector DATA"))}},
   Question::Fixture{lint,..}=>if !valid(lint){return Err(io::Error::new(io::ErrorKind::InvalidInput,"invalid native fixture lint DATA"))},
  }Ok(())
 }
}
/// Canonical request identity DATA, using the existing bounded metadata shape.
/// A digest never issues a source/currentness or filesystem write capability.
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RequestBinding{pub bytes:u64,pub hash:crate::selected_exclusions_wire::Hex128}
impl Binding{
 pub fn fingerprint(&self)->io::Result<RequestBinding>{self.fingerprint_using(&mut||Ok(()))}
 pub fn fingerprint_using(&self,checkpoint:&mut dyn FnMut()->io::Result<()>)->io::Result<RequestBinding>{
  self.validate()?;
  struct Fingerprint<'a>{checkpoint:&'a mut dyn FnMut()->io::Result<()>,bytes:u64,hash:xxhash_rust::xxh3::Xxh3,first:Option<io::Error>}
  impl std::io::Write for Fingerprint<'_>{fn write(&mut self,part:&[u8])->io::Result<usize>{
   if let Some(first)=&self.first{return Err(first.kind().into())}
   let actual:io::Result<usize>=(||{(self.checkpoint)()?;self.bytes=self.bytes.checked_add(part.len()as u64).filter(|n|*n<=crate::native_check_cli_wire::MAX_REQUEST as u64).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"utility binding exceeds existing request metadata bound"))?;self.hash.update(part);Ok(part.len())})();
   match actual{Ok(n)=>Ok(n),Err(first)=>{let proxy=first.kind().into();self.first=Some(first);Err(proxy)}}
  }fn flush(&mut self)->io::Result<()>{Ok(())}}
  let mut actual=Fingerprint{checkpoint,bytes:0,hash:xxhash_rust::xxh3::Xxh3::new(),first:None};actual.hash.update(b"native-codemod-fixture-request-v2\0");let encoded=serde_json::to_writer(&mut actual,self);if let Some(first)=actual.first.take(){return Err(first)}encoded.map_err(|error|io::Error::new(error.io_error_kind().unwrap_or(io::ErrorKind::InvalidData),error))?;Ok(RequestBinding{bytes:actual.bytes,hash:crate::selected_exclusions_wire::Hex128(actual.hash.digest128())})
 }
}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub enum OriginalCompleteness{Complete,PrimaryPrefix}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub enum SourceFrame{Parity{checks:u64,check_frames:Seal,callbacks:u64,callback_frames:Seal},Selected(crate::full_registry_check_wire::CheckFrame),Model(Frame),Raw(RawSelectedFrame),Semantic{semantic:u128,source:u128,completeness:OriginalCompleteness}}
#[derive(Clone,Copy,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
pub enum Schema{#[serde(rename="native-codemod-fixture-v2")]V2}
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal{
 pub schema:Schema,
 pub requested:RequestBinding,
 pub complete:bool,
 pub frame:Option<SourceFrame>,
 pub committed:usize,
 pub exit:i32,
 pub stdout:Seal,
 pub stderr:Seal,
}
impl Terminal{
 pub fn require(&self,expected:&Binding)->io::Result<()>{
  expected.validate()?;
  let writes=matches!(&expected.question,Question::Codemod{apply:true,..}|Question::Codemod{revert:true,..}|Question::Codemod{write_residue:true,..}|Question::Fixture{bless:true,..}|Question::Parity{bless:true,..});
  let needs_source=!matches!(&expected.question,Question::CodemodList|Question::Codemod{revert:true,..});
  if let Question::Parity{fixtures_only,bless,..}=&expected.question{
   let Some(SourceFrame::Parity{checks,check_frames,callbacks,callback_frames})=&self.frame else{return Err(io::Error::new(io::ErrorKind::InvalidData,"parity terminal lacks actual per-case producer frames"))};
   if *checks>32768||*callbacks>4096||(!fixtures_only&&*checks<4)||check_frames.length>MAX_STREAM||callback_frames.length>MAX_STREAM||(!bless&&self.committed!=0){return Err(io::Error::new(io::ErrorKind::InvalidData,"parity terminal has impossible case coverage or write result"))}
  }
  if let Question::Fixture{bless,..}=&expected.question{
   if !matches!(self.frame,Some(SourceFrame::Selected(_)))||self.committed>1||(!bless&&self.committed!=0)||(self.exit==0&&*bless&&self.committed!=1){return Err(io::Error::new(io::ErrorKind::InvalidData,"fixture terminal lacks its actual selected frame or fixed-target write result"))}
  }
  if !self.complete||self.requested!=expected.fingerprint()?||!matches!(self.exit,0|1|2)||(!writes&&self.committed!=0)||(needs_source&&self.frame.is_none())||self.stdout.length.checked_add(self.stderr.length).is_none_or(|n|n>MAX_STREAM){return Err(io::Error::new(io::ErrorKind::InvalidData,"native codemod/fixture terminal differs from its actual operation"))}Ok(())
 }
}

#[cfg(test)]mod parity_scalar_controls{
 use super::*;
 #[test]fn parity_case_observation_is_fixed_bounded_data_not_unbounded_vectors(){let frame=SourceFrame::Parity{checks:u64::MAX,check_frames:Seal{length:MAX_STREAM,hash:crate::selected_exclusions_wire::Hex128(u128::MAX)},callbacks:u64::MAX,callback_frames:Seal{length:MAX_STREAM,hash:crate::selected_exclusions_wire::Hex128(u128::MAX)}};assert!(serde_json::to_vec(&frame).unwrap().len()<512);}
}

#[cfg(test)]mod request_fingerprint_v2_controls{
 use super::*;
 fn actual()->Binding{Binding{schema:Schema::V2,root:PathBuf::from(if cfg!(windows){"E:/actual/root"}else{"/actual/root"}),question:Question::Parity{selectors:vec!["scheduler".into()],fixtures_only:false,bless:false,oracle:FrozenOracleBinding{image:PathBuf::from(if cfg!(windows){"E:/frozen/reference.exe"}else{"/frozen/reference"}),sha256:"a".repeat(64)}}}}
 fn terminal(binding:&Binding)->Terminal{Terminal{schema:Schema::V2,requested:binding.fingerprint().unwrap(),complete:true,frame:Some(SourceFrame::Parity{checks:4,check_frames:Seal{length:2,hash:crate::selected_exclusions_wire::Hex128(1)},callbacks:1,callback_frames:Seal{length:2,hash:crate::selected_exclusions_wire::Hex128(2)}}),committed:0,exit:0,stdout:Seal{length:0,hash:crate::selected_exclusions_wire::Hex128(3)},stderr:Seal{length:0,hash:crate::selected_exclusions_wire::Hex128(3)}}}
 #[test]fn actual_long_paths_and_selectors_remain_request_data_and_fit_unchanged_terminal_header(){let mut binding=actual();let Question::Parity{selectors,oracle,..}=&mut binding.question else{unreachable!()};oracle.image=PathBuf::from(if cfg!(windows){format!("E:/{}.exe","reference/".repeat(500))}else{format!("/{}oracle","reference/".repeat(500))});*selectors=(0..500).map(|i|format!("lint_{i}")).collect();let terminal=terminal(&binding);terminal.require(&binding).unwrap();assert!(serde_json::to_vec(&binding).unwrap().len()>crate::selected_exclusions_wire::MAX_HEADER);assert!(serde_json::to_vec(&terminal).unwrap().len()<crate::selected_exclusions_wire::MAX_HEADER);}
 #[test]fn exact_root_flags_reference_version_and_schema_cannot_impersonate_the_held_request(){let binding=actual();let terminal=terminal(&binding);terminal.require(&binding).unwrap();let mut changed=binding.clone();changed.root.push("different");assert!(terminal.require(&changed).is_err());for flag in[0,1,2]{let mut changed=binding.clone();let Question::Parity{fixtures_only,bless,oracle,..}=&mut changed.question else{unreachable!()};match flag{0=>*fixtures_only=true,1=>*bless=true,_=>oracle.sha256="b".repeat(64)}assert!(terminal.require(&changed).is_err());}let mut wrong=serde_json::to_value(&terminal).unwrap();wrong["schema"]=serde_json::json!("native-codemod-fixture-v1");assert!(serde_json::from_value::<Terminal>(wrong).is_err());}
 #[test]fn first_metadata_checkpoint_error_is_preserved_before_any_output_or_mutation(){let binding=actual();let mut visited=0;let first=binding.fingerprint_using(&mut||{visited+=1;Err(io::Error::from_raw_os_error(1450))}).unwrap_err();assert_eq!(first.raw_os_error(),Some(1450));assert_eq!(visited,1);}
}

#[cfg(test)]mod request_version_controls{use super::*;#[test]fn immutable_v1_request_cannot_reach_a_v2_writer(){let root=if cfg!(windows){"E:/actual/root"}else{"/actual/root"};let old=serde_json::json!({"root":root,"question":"CodemodList"});assert!(serde_json::from_value::<Binding>(old.clone()).is_err(),"missing version rejected before backend operation");let mut old=old;old["schema"]=serde_json::json!("native-codemod-fixture-v1");assert!(serde_json::from_value::<Binding>(old.clone()).is_err());old["schema"]=serde_json::json!("native-codemod-fixture-v2");let binding=serde_json::from_value::<Binding>(old).unwrap();binding.validate().unwrap();}}

#[cfg(test)]mod maximal_v2_header_control{
 use super::*;
 #[test]fn actual_largest_selected_producer_frame_and_request_fingerprint_fit_existing_header(){use crate::{selected_exclusions_wire::Hex128,full_registry_check_wire::CheckFrame};let terminal=Terminal{schema:Schema::V2,requested:RequestBinding{bytes:crate::native_check_cli_wire::MAX_REQUEST as u64,hash:Hex128(u128::MAX)},complete:true,frame:Some(SourceFrame::Selected(CheckFrame::SourceHandlers{query_revision:Hex128(u128::MAX),source_revision:Hex128(u128::MAX),policy_revision:Hex128(u128::MAX),handler_query_revision:Hex128(u128::MAX),partial_source_revision:Some(Hex128(u128::MAX)),full_source_revision:Some(Hex128(u128::MAX)),full_semantic_revision:Some(Hex128(u128::MAX)),full_policy_revision:Some(Hex128(u128::MAX))})),committed:usize::MAX,exit:2,stdout:Seal{length:MAX_STREAM,hash:Hex128(u128::MAX)},stderr:Seal{length:MAX_STREAM,hash:Hex128(u128::MAX)}};let bytes=serde_json::to_vec(&terminal).unwrap();assert!(bytes.len()<crate::selected_exclusions_wire::MAX_HEADER,"{} bytes",bytes.len());}
}
