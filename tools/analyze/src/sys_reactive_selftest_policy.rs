//! Original Sys reactive assertions, never semantic/source completion authority.
use crate::{derived_selftest_policy::Failure,key_policy_control::{self as kc,Control}};
pub const FIXTURE:&str=include_str!("../fixtures/sys__dx_reactive/code/selftest.dm");
pub fn assert_rows<'a,I:Iterator<Item=(&'a str,usize)>+Clone,C:Control<Error=Failure>>(rows:I,c:&mut C)->Result<String,Failure>{
 let checks:[(&str,&[&str]);4]=[
 ("dx_untracked_read",&["when = cell.rigged","when = cell.label_text","return cell?.maxcharge","return cell.rigged","when = C.rigged"]),
 ("dx_reactive_write",&["holder.last_ui = world.time","last_holder = holder","changed(holder)","holder.verbs.Remove","holder.set_dir(NORTH)","\tlevel++","src.cell.set_charge(5)"]),
 ("dx_caps_instance_read",&[". += cap_gauge(level = level)","cap_lock(access = src.req_access)"]),
 ("dx_timed_write",&["\temp_disabled = FALSE","M.emp_disabled = TRUE"]),
 ];
 for(rule,snippets)in checks{
  let mut got=Vec::new();for(found,line)in rows.clone(){c.checkpoint()?;if found==rule{kc::row(c,&mut got)?;got.push(line)}}kc::sort_data(&mut got,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(a.cmp(b))})?;
  let mut want=Vec::new();for snippet in snippets{kc::row(c,&mut want)?;want.push(FIXTURE.split('\n').position(|line|line.contains(snippet)).map_or(0,|n|n+1));}kc::sort_data(&mut want,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(a.cmp(b))})?;
  if got!=want{return Err(Failure::Assertion(kc::format(c,format_args!("dx_reactive selftest {}: got {:?}, want {:?}",rule,got,want))?))}
 }
 kc::own(c,"dx_reactive")
}
