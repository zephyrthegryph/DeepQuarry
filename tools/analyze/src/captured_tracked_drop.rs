//! Removal proposals over the SAME authentic native dependency/metadata rows.
//! This is edit DATA; physical source/recovery/publication remain the existing FIX operation.
use crate::{captured_tracked_fix::ListMacroFixData,captured_raw_file::Config,reactive_global_source::Source,reactive_dependency_view::Analysis,captured_reactive_reads::Failure,captured_allow_annotations::Operation,key_policy_control::{self as kc,Control}};
use std::io;
struct Line{number:usize,owner:String,var:String,read:bool,asked:bool}
fn read_related(source:&dyn Source,analysis:Analysis<'_>,owner:&str,var:&str)->Result<bool,Failure>{for(o,v)in analysis.reads(){source.checkpoint()?;if v==var&&(o==owner||source.is_subtype(owner,o)?||source.is_subtype(o,owner)?){return Ok(true)}}Ok(false)}
pub(crate) fn collect_source(source:&dyn Source,analysis:Analysis<'_>,config:&Config,relative:&str,poll:&dyn Fn()->io::Result<()>)->Result<ListMacroFixData,Failure>{
 let b=source.budget();let mut work=Operation{budget:b,poll};work.checkpoint()?;let mut result=ListMacroFixData::new(relative,b,poll)?;result.begin_declarations();
 if !relative.starts_with("code/")||relative==crate::auto_setter_calls_policy::AUTO_REL||relative=="code/defines/engine/capabilities.dm"{return Err("drop-declared accepts only ordinary legacy CODE_DM candidate files".into())}
 kc::reserve(&mut work,||Some(65536))?;let pattern=crate::pat::Pat::try_new(r"^(\s*)TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)\s*(?://.*)?$").map_err(|_|work.allocation_failed())?;
 let defs=crate::auto_tracking_native::setter_defs(source)?;let calls=crate::auto_tracking_native::set_calls(source)?;let typed=crate::auto_typed_set_calls_native::collect_from(source)?;
 let mut lines=Vec::new();let complete=source.with_policy_files(&mut|path,views|{if path!=relative{return Ok(true)}let file=views.source_file()?;result.source(file,b,poll)?;
  for(number,line)in file.raw().text.split('\n').enumerate(){work.checkpoint()?;let Some(found)=pattern.captures(line.trim_end_matches('\r'))else{continue};let owner=found.s(2);let var=found.s(3);let read=read_related(source,analysis,owner,var)?;let called=crate::auto_tracking_native::declared_called_here(source,&defs,&calls,&typed,owner,var)?;
   let included=config.with_auto_tracked_lists(|include,_|include.iter().any(|key|key.strip_prefix(owner).and_then(|tail|tail.strip_prefix("::"))==Some(var)));
   kc::row(&mut work,&mut lines)?;lines.push(Line{number:number+1,owner:kc::own(&mut work,owner)?,var:kc::own(&mut work,var)?,read,asked:read||called||included});
  }Ok(true)})?;if !complete{return Err("drop declaration candidate phase omitted actual CODE_DM EOF".into())}
 let decided=config.with_auto_tracked_lists(|_,exclude|crate::auto_tracking_native::decide_rows(source,&defs,lines.iter().filter(|line|line.asked).map(|line|(line.owner.as_str(),line.var.as_str())),exclude))?;
 let complete=source.with_policy_files(&mut|path,views|{if path!=relative{return Ok(true)}let file=views.source_file()?;for line in &lines{work.checkpoint()?;
  let generated=decided.tracked.iter().any(|row|row.ty==line.owner&&row.var==line.var)||decided.blocked.iter().any(|(owner,var,why)|owner==&line.owner&&var==&line.var&&why=="an ancestor tracks it");
  let named=calls.contains(&line.var)||calls.iter().any(|name|name.strip_suffix("[]")==Some(line.var.as_str()));
  let builtin=source.variable(&line.owner,&line.var)?.is_none_or(|v|v.file.is_none_or(|file|file.is_empty()));
  let mut unknown=false;if named&&!generated&&!line.asked&&!line.read&&!builtin{for action in [crate::tracked_policy::FixAction::Set,crate::tracked_policy::FixAction::Add,crate::tracked_policy::FixAction::Include,crate::tracked_policy::FixAction::Remove,crate::tracked_policy::FixAction::SetAt,crate::tracked_policy::FixAction::Clear,crate::tracked_policy::FixAction::Insert,crate::tracked_policy::FixAction::Swap,crate::tracked_policy::FixAction::Cut]{work.checkpoint()?;kc::reserve(&mut work,||line.var.len().checked_mul(4)?.checked_add(128))?;let name=action.method(&line.var).expect("actual setter action");if typed.contains(&name,crate::typed_set_calls_policy::UNTYPED){unknown=true;break}}}
  let idle=!line.read&&!builtin&&(!named||!unknown)&&!line.asked;
  let reason=decided.blocked.iter().find(|(owner,var,_)|owner==&line.owner&&var==&line.var).map_or("nothing asks the generator for it",|(_,_,why)|why.as_str());
  result.declaration(file,line.number,line.read,generated,generated||idle,reason,b,poll)?;if generated||idle{result.drop_line(file,line.number,b,poll)?;}
 }Ok(true)})?;if !complete{return Err("drop declaration result phase omitted actual CODE_DM EOF".into())}result.set_schema_count(lines.len());result.finish(b,poll)?;source.require()?;Ok(result)
}
