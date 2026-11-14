//! Exact physical UTF8 acquisition/mapping for normalized tracked-fix DATA.
//! No source receipt is minted here: caller supplies original recorded identity
//! and independently authenticates bytes against its actual moved input ledger.
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use dq_analyze::captured_tracked_fix::ListMacroFixData;
use crate::input_snapshot::SnapshotProvider;
use std::{io::{self,Read},fs::File,path::Path};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,s)}
pub(crate) struct Physical{pub bytes:Vec<u8>,_credit:SourceArenaCredit}
pub(crate) struct Output{pub bytes:Vec<u8>,_credit:SourceArenaCredit}
pub(crate) fn read(path:&Path,stamp:&crate::input_snapshot::Stamp,work:&dyn SourceArenaWork)->io::Result<Physical>{
 work.checkpoint()?;let size=usize::try_from(stamp.size).map_err(|_|invalid("physical authored size overflow"))?;
 let capacity=size.checked_add(1).ok_or_else(||invalid("physical read bound overflow"))?;
 let credit=work.reserve(capacity.checked_mul(4).and_then(|n|n.checked_add(8192)).ok_or_else(||invalid("physical read backing overflow"))?)?;
 let mut bytes=Vec::new();bytes.try_reserve_exact(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
 if bytes.capacity()>capacity.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}bytes.resize(capacity,0);
 let mut file=File::open(path)?;if &crate::input_snapshot::stamp_handle(&file)?!=stamp{return Err(invalid("authored physical read identity changed"))}
 let mut at=0;while at<capacity{work.checkpoint()?;let end=capacity.min(at+8192);let n=file.read(&mut bytes[at..end])?;if n==0{break}at+=n;}
 if at!=size||&crate::input_snapshot::stamp_handle(&file)?!=stamp||crate::input_snapshot::FileSystemInputs.stamp(path)?!=*stamp{return Err(invalid("authored physical source changed during read"))}
 bytes.truncate(size);Ok(Physical{bytes,_credit:credit})
}
fn same_bytes(a:&[u8],b:&[u8],work:&dyn SourceArenaWork)->io::Result<bool>{if a.len()!=b.len(){return Ok(false)}for (a,b) in a.chunks(8192).zip(b.chunks(8192)){work.checkpoint()?;if a!=b{return Ok(false)}}Ok(true)}
pub(crate) fn map(physical:&[u8],data:&ListMacroFixData,work:&dyn SourceArenaWork)->io::Result<Output>{map_edits(physical,data.preimage(),data.edits(),work)}
fn map_edits(physical:&[u8],preimage:&str,edits:&[dq_analyze::captured_tracked_fix::Edit],work:&dyn SourceArenaWork)->io::Result<Output>{
 use crate::input_snapshot::SnapshotProvider;
 work.checkpoint()?;let source=std::str::from_utf8(physical).map_err(|_|invalid("authored fix requires actual UTF8 bytes"))?;
 if source.starts_with('\u{feff}'){return Err(io::Error::new(io::ErrorKind::Unsupported,"authored BOM mapping has not been qualified"))}
 let normalized=preimage.as_bytes();let mut capacity=physical.len();
 for edit in edits{work.checkpoint()?;capacity=capacity.checked_add(edit.text.len().saturating_sub(edit.was.len())).ok_or_else(||invalid("physical fix output overflow"))?;}
 let credit=work.reserve(capacity.checked_mul(4).and_then(|n|n.checked_add(8192)).ok_or_else(||invalid("physical fix output backing overflow"))?)?;
 let mut output=Vec::new();output.try_reserve_exact(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
 if output.capacity()>capacity.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}
 let(mut physical_at,mut normalized_at,mut line,mut index)=(0usize,0usize,1usize,0usize);
 loop{
  let mut end=physical_at;while end<physical.len(){work.checkpoint()?;let width=(physical.len()-end).min(8192);if let Some(off)=physical[end..end+width].iter().position(|c|matches!(c,b'\r'|b'\n')){end+=off;break}end+=width;}
  let content=&physical[physical_at..end];let normal_end=normalized_at.checked_add(content.len()).ok_or_else(||invalid("normalized line overflow"))?;
  let expected=normalized.get(normalized_at..normal_end).ok_or_else(||invalid("normalized preimage line absent"))?;
  if !same_bytes(content,expected,work)?{return Err(invalid("physical authored bytes differ from normalized captured preimage"))}
  let mut column=0;
  while let Some(edit)=edits.get(index){
   if (edit.line as usize)<line{return Err(invalid("normalized fix line order changed"))}if edit.line as usize!=line{break}
   let start=edit.start.checked_sub(normalized_at).ok_or_else(||invalid("normalized edit precedes its line"))?;
   let finish=edit.end.checked_sub(normalized_at).ok_or_else(||invalid("normalized edit end precedes line"))?;
   if start<column||finish<start||finish>content.len()||source.get(physical_at+start..physical_at+finish)!=Some(edit.was.as_str())||normalized.get(edit.start..edit.end)!=Some(edit.was.as_bytes())||edit.text.contains(['\r','\n']){return Err(invalid("normalized edit does not match exact physical single-line span"))}
   output.extend_from_slice(&content[column..start]);output.extend_from_slice(edit.text.as_bytes());column=finish;index+=1;
  }
  output.extend_from_slice(&content[column..]);
  if end==physical.len(){if normal_end!=normalized.len(){return Err(invalid("normalized captured source has unmatched tail"))}break}
  if normalized.get(normal_end)!=Some(&b'\n'){return Err(invalid("normalized captured newline differs"))}
  let width=if physical[end]==b'\r'&&physical.get(end+1)==Some(&b'\n'){2}else{1};output.extend_from_slice(&physical[end..end+width]);physical_at=end+width;normalized_at=normal_end+1;line=line.checked_add(1).ok_or_else(||invalid("physical line number overflow"))?;
 }
 if index!=edits.len()||output.len()>capacity{return Err(invalid("physical fix edit coverage differs"))}Ok(Output{bytes:output,_credit:credit})
}

#[cfg(test)]mod controls{
 use super::*;use dq_analyze::captured_tracked_fix::Edit;
 fn edit(source:&str,was:&str,replacement:&str,line:u32)->Edit{let start=source.find(was).unwrap();Edit{start,end:start+was.len(),was:was.into(),text:replacement.into(),line}}
 #[test]fn actual_physical_mapper_keeps_crlf_lone_cr_lf_and_utf8_without_a_second_parser(){
  let physical="// é retained\r\n/obj/box\r    LAZYSET(items, key, value) // 一\n    LAZYREMOVE(items, other)\r\n";
  let normalized=dq_analyze::util::universal_newlines(physical.into());let edits=[edit(&normalized,"LAZYSET(items, key, value)","set_items_at(key, value)",3),edit(&normalized,"LAZYREMOVE(items, other)","remove_items(other)",4)];let work=crate::query_db::QueryDb::default();let actual=map_edits(physical.as_bytes(),&normalized,&edits,&work).unwrap();assert_eq!(actual.bytes,"// é retained\r\n/obj/box\r    set_items_at(key, value) // 一\n    remove_items(other)\r\n".as_bytes());
 }
 #[test]fn actual_physical_mapper_denies_stale_bytes_wrong_line_overlap_bom_and_unissued_encoding(){
  let physical=b"/obj/box\r\n    LAZYADD(items, value)\r\n";let normalized="/obj/box\n    LAZYADD(items, value)\n";let good=edit(normalized,"LAZYADD(items, value)","add_items(value)",2);let work=crate::query_db::QueryDb::default();
  let mut changed=physical.to_vec();changed[1]=b'x';assert!(map_edits(&changed,normalized,&[good],&work).is_err());
  let mut wrong=edit(normalized,"LAZYADD(items, value)","add_items(value)",1);assert!(map_edits(physical,normalized,&[wrong],&work).is_err());wrong=edit(normalized,"LAZYADD(items, value)","add_items(value)",2);assert!(map_edits(physical,normalized,&[wrong,edit(normalized,"LAZYADD(items, value)","add_items(value)",2)],&work).is_err());
  assert!(map_edits(&[0xff],"",&[],&work).is_err());assert_eq!(map_edits("\u{feff}/obj".as_bytes(),"/obj",&[],&work).err().unwrap().kind(),io::ErrorKind::Unsupported);
 }
 #[test]fn actual_physical_mapper_funding_denial_then_released_credit_recovery(){
  let work=crate::query_db::QueryDb::default();let limit=work.transformed_source_address_limit().unwrap();let source="x".repeat(160*1024);let pressure=work.reserve(limit-512*1024).unwrap();let error=map_edits(source.as_bytes(),&source,&[],&work).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);drop(pressure);assert_eq!(map_edits(source.as_bytes(),&source,&[],&work).unwrap().bytes,source.as_bytes());
 }
}
