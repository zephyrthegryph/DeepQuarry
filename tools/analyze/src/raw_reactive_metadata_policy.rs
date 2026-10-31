//! Exact original tracked/relation line policy, not a DM declaration parser.
//! Input is the SAME existing comment-masked/string-preserving raw view.
use crate::pat_match;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub enum Event<'a>{Tracked{owner:&'a str,name:&'a str},Relation{owner:&'a str,name:&'a str}}
pub fn visit_line<E>(text:&str,mut emit:impl FnMut(Event<'_>)->Result<(),E>)->Result<(),E>{
 let t=text.trim_start();if t.is_empty()||t.starts_with('#'){return Ok(())}
 if let Some(m)=pat_match!(r"(?:TRACKED|TRACKED_DATA|SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(t){emit(Event::Tracked{owner:m.s(1),name:m.s(2)})?;}
 // One first legacy match per line, exactly as the original Option collector.
 crate::relation_decl_policy::try_visit_legacy_line(t,|owner,name|emit(Event::Relation{owner,name}))?;
 let om=pat_match!(r"(?:OM_FIELD|OM_FLAG_FIELD|OM_FLAG_FIELD_BITS|OM_FIELD_SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(t)
  .or_else(||pat_match!(r"OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*[\w/]+\s*,\s*(\w+)").captures(t));
 if let Some(m)=om{emit(Event::Tracked{owner:m.s(1),name:m.s(2)})?;}
 Ok(())
}
