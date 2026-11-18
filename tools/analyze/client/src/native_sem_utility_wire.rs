//! Utility request/result DATA only; native preparation, currentness and write authority remain backend-owned.
use serde::{Deserialize,Serialize};
use std::{io,path::PathBuf};
use crate::selected_exclusions_wire::{Seal,MAX_STREAM};
use crate::selected_exclusions_wire::Hex128;
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]pub enum OriginalCompleteness{Complete,PrimaryPrefix}
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]#[serde(deny_unknown_fields)]pub struct Frame{pub semantic_revision:Hex128,pub source_revision:Hex128,pub policy_revision:Hex128,pub original:OriginalCompleteness}
#[derive(Clone,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(tag="kind",rename_all="snake_case",deny_unknown_fields)]
pub enum Question{
 Reads{owner:String,procedure:String},
 ReadsUsage,
 Help,
 Closure{write:bool},
 ClothingDump,
 BaseVarsDead{tsv:bool,few:bool},
}
impl Question{
 pub fn validate(&self)->io::Result<()>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"native utility request exceeds existing argument bound");
  let names: &[&str]=match self{Self::Reads{owner,procedure}=>&[owner,procedure],_=>&[]};
  if names.iter().any(|s|s.len() as u64>MAX_STREAM||s.as_bytes().contains(&0)){return Err(invalid())}Ok(())
 }
 pub fn may_write(&self)->bool{matches!(self,Self::Closure{write:true})}
}
#[derive(Clone,Debug,Eq,PartialEq,Ord,PartialOrd,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Binding{pub root:PathBuf,pub question:Question}
impl Binding{pub fn validate(&self)->io::Result<()>{self.question.validate()?;if !self.root.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native utility workspace must be absolute"))}Ok(())}}
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]
pub enum Schema{#[serde(rename="native-sem-utility-v1")]V1}
#[derive(Clone,Debug,Serialize,Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal{
 pub schema:Schema,pub complete:bool,pub binding:Binding,
 pub frame:Frame,
 pub stdout:Seal,pub stderr:Seal,pub exit:u8,pub committed:bool,
}
impl Terminal{
 pub fn require(&self,binding:&Binding)->io::Result<()>{
  binding.validate()?;let invalid=||io::Error::new(io::ErrorKind::InvalidData,"native utility terminal differs from actual request/current output");
  if !self.complete||self.binding!=*binding||self.exit>3||(!binding.question.may_write()&&self.committed)||self.stdout.length.checked_add(self.stderr.length).is_none_or(|n|n>MAX_STREAM){return Err(invalid())}Ok(())
 }
}
// The renderer emits actual utility text. These DATA seals never turn a failed parse/IO into a completed terminal.
