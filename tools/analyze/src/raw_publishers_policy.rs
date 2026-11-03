//! Unique original PUBLISH_CHANGE lexical producer; no source authority.
use crate::key_policy_control as kc;
fn pattern()->&'static crate::pat::Pat{crate::pat!(r"PUBLISH_CHANGE\(\s*[^,()]+,\s*([\w#]+)\s*\)")}
pub(crate) fn visit_line<C:kc::Control>(line:&str,control:&mut C,mut emit:impl FnMut(&str)->Result<(),C::Error>)->Result<(),C::Error>{control.checkpoint()?;if !line.contains("PUBLISH_CHANGE("){return Ok(())}kc::reserve(control,||pattern().capture_group_count().checked_mul(4*std::mem::size_of::<Option<(usize,usize)>>()).and_then(|n|n.checked_add(128)))?;for found in pattern().captures_iter(line){control.checkpoint()?;emit(found.s(1).trim_start_matches('#'))?;}control.checkpoint()?;Ok(())}
