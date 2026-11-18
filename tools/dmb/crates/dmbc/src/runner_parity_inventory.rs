//! Actual metadata-only fixture inventory. This recorder issues no model or
//! semantic receipt and runs no frontend. Directory absence is never guessed
//! from an unrecorded exists() skip in a claimed complete parity operation.
use std::{io,path::Path};
use dm_preprocess::{SourceProvider,source_arena_credit::{SourceArenaCredit,SourceArenaWork}};
use crate::input_snapshot::{InputSnapshot,RecordingInputs,FileSystemInputs};
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidInput,message)}
pub(crate)struct Row{pub(crate)name:String,pub(crate)present:bool}
pub(crate)struct Inventory{inputs:InputSnapshot,rows:Vec<Row>,_credit:SourceArenaCredit}
impl Inventory{
 pub(crate)fn capture(root:&Path,names:&[String],work:&dyn SourceArenaWork)->Result<Self,Box<dyn std::error::Error>>{
  if !root.is_absolute(){return Err(invalid("fixture inventory root must be absolute").into())}
  let mut credit=work.reserve(std::mem::size_of::<Self>())?;let mut rows=super::super::native_utility_binding::vector(names.len(),work,&mut credit)?;
  let recording=RecordingInputs::new(FileSystemInputs,0);
  for name in names{
   work.checkpoint()?;if name.is_empty()||name.contains(['\\',':'])||name.split('/').any(|p|p.is_empty()||p=="."||p=="..")||name.bytes().any(|b|b<32){return Err(invalid("inventory name is not an actual canonical registry name").into())}
   let name=dm_preprocess::regions::copy_string_into_credit(name,work,&mut credit)?;
   let mut path_credit=work.reserve(0)?;
   let base=dm_preprocess::regions::joined_path_into_credit(root,"tools/analyze/fixtures",work,&mut path_credit)?;
   let width=name.len().checked_add(name.bytes().filter(|b|*b==b'/').count()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;let frontier=width.checked_mul(4).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;work.grow(&mut path_credit,frontier)?;
   let mut directory=String::new();directory.try_reserve_exact(width).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;for character in name.chars(){if character=='/'{directory.push_str("__")}else{directory.push(character)}}if directory.capacity()>frontier{return Err(io::Error::from(io::ErrorKind::OutOfMemory).into())}work.shrink(&mut path_credit,frontier-directory.capacity())?;
   let path=dm_preprocess::regions::joined_path_into_credit(&base,&directory,work,&mut path_credit)?;
   let present=recording.path_presence_admitted(&path,work)?;rows.push(Row{name,present});drop(path);drop(directory);drop(base);drop(path_credit);
  }
  let result=Self{inputs:recording.into_snapshot()?,rows,_credit:credit};result.require_current()?;Ok(result)
 }
 pub(crate)fn rows(&self)->&[Row]{&self.rows}
 pub(crate)fn require_current(&self)->Result<(),Box<dyn std::error::Error>>{crate::request_runner::runner_freshness::require_native_callback_inputs_current(&self.inputs)}
}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn actual_absent_fixture_directory_is_captured_and_invalidated_when_created(){let root=std::fs::canonicalize(crate::test_scratch::dir("parity-inventory-absence")).unwrap();let work=crate::query_db::QueryDb::default();let inventory=Inventory::capture(&root,&["scheduler".into()],&work).unwrap();assert!(!inventory.rows()[0].present);std::fs::create_dir_all(root.join("tools/analyze/fixtures/scheduler")).unwrap();assert!(inventory.require_current().is_err());}
 #[test]fn actual_present_fixture_directory_is_captured_and_invalidated_when_removed(){let root=std::fs::canonicalize(crate::test_scratch::dir("parity-inventory-presence")).unwrap();let fixture=root.join("tools/analyze/fixtures/scheduler");std::fs::create_dir_all(&fixture).unwrap();let work=crate::query_db::QueryDb::default();let inventory=Inventory::capture(&root,&["scheduler".into()],&work).unwrap();assert!(inventory.rows()[0].present);std::fs::remove_dir(&fixture).unwrap();assert!(inventory.require_current().is_err());}
}
