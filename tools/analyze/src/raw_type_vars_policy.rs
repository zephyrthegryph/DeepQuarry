//! Existing dx own-var matching policy, emitted as ephemeral callbacks.
//! This is a source-only generator projection, not another DM parser/model.
use crate::{
    pat,
    util::{py_lstrip, py_rstrip, py_strip},
};
const ABSOLUTE_SOURCE:&str=r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b";
const HEADER_SOURCE:&str=r"^(/[\w/]+)\s*$";
const SYSTEM_SOURCE:&str=r"^SYSTEM_DEF\((\w+)\)\s*$";
const GROUP_SOURCE:&str=r"^(\s+)var\s*$";
const VARIABLE_SOURCE:&str=r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)";
fn absolute()->&'static crate::pat::Pat{pat!(r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b")}
fn header()->&'static crate::pat::Pat{pat!(r"^(/[\w/]+)\s*$")}
fn system()->&'static crate::pat::Pat{pat!(r"^SYSTEM_DEF\((\w+)\)\s*$")}
fn group()->&'static crate::pat::Pat{pat!(r"^(\s+)var\s*$")}
fn variable()->&'static crate::pat::Pat{pat!(r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)")}
pub fn visit(clean:&str,mut declare:impl FnMut(&str,&str)){visit_with(clean,&mut crate::key_policy_control::Compatibility,&mut|ty,name|{declare(ty,name);Ok(())}).unwrap_or_else(|never|match never{})}
/// SAME lexical scanner with direct control before each source line/materialization.
pub fn visit_with<C:crate::key_policy_control::Control>(clean:&str,c:&mut C,declare:&mut impl FnMut(&str,&str)->Result<(),C::Error>)->Result<(),C::Error>{
    #[cfg(feature="native-policy")]let native=c.native_patterns().is_some();
    #[cfg(not(feature="native-policy"))]let native=false;
    let mut maximum=0usize;
    #[cfg(feature="native-policy")]if native{for source in [ABSOLUTE_SOURCE,HEADER_SOURCE,SYSTEM_SOURCE,GROUP_SOURCE,VARIABLE_SOURCE]{let width=c.native_patterns().expect("same scoped provider").capture_len(crate::native_pattern::Spec{pattern:source,mode:crate::native_pattern::Mode::Search});maximum=maximum.max(width.map_err(|actual|c.native_pattern_failed(actual))?);}}
    if !native{maximum=[absolute(),header(),system(),group(),variable()].into_iter().map(|p|p.capture_group_count()).max().unwrap_or(0);}
    crate::key_policy_control::reserve(c,||maximum.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+128))?;
    let mut current: Option<String> = None;
    let mut group_indent: Option<usize> = None;
    for line in clean.lines() {
        c.checkpoint()?;
        if let Some(m) =
            capture_fixed(c,ABSOLUTE_SOURCE,line,maximum,absolute)?
        {
            declare(m.s(1), m.s(2))?;
            current = None;
            continue;
        }
        if let Some(h) = capture_fixed(c,HEADER_SOURCE,py_rstrip(line),maximum,header)? {
            current = Some(crate::key_policy_control::own(c,h.s(1))?);
            group_indent = None;
            continue;
        }
        // SYSTEM_DEF(x) declares /datum/system/x through a macro: its indented body is that type's block.
        if let Some(h) = capture_fixed(c,SYSTEM_SOURCE,py_rstrip(line),maximum,system)? {
            current = Some(crate::key_policy_control::format(c,format_args!("/datum/system/{}",h.s(1)))?);
            group_indent = None;
            continue;
        }
        if !line.is_empty() && !line.starts_with([' ', '\t']) {
            current = None;
            continue;
        }
        let Some(cur) = &current else { continue };
        if let Some(gi) = group_indent {
            let indent = line.len() - py_lstrip(line).len();
            if !py_strip(line).is_empty() && indent > gi {
                let t = py_strip(line);
                let last = if !line.contains('=') {
                    t.rsplit('/').next().unwrap_or("")
                } else {
                    py_strip(line.split('=').next().unwrap_or(""))
                        .rsplit('/')
                        .next()
                        .unwrap_or("")
                };
                if let Some(name) = crate::key_policy_control::find_static(c,r"\A[A-Za-z_]\w*",last,0,||pat!(r"\A[A-Za-z_]\w*"))? {
                    declare(cur, name.as_str())?;
                }
                continue;
            }
            group_indent = None;
        }
        if let Some(g) = capture_fixed(c,GROUP_SOURCE,line,maximum,group)? {
            group_indent = Some(g.s(1).len());
            continue;
        }
        if let Some(v) = capture_fixed(c,VARIABLE_SOURCE,line,maximum,variable)? {
            declare(cur, v.s(1))?;
        }
    }
    c.checkpoint()?;Ok(())
}

#[cfg(test)]#[path="raw_type_vars_frozen_original.rs"]mod original_raw_vars;
#[cfg(test)]mod controlled_tests{
 use super::*;use super::original_raw_vars as original;
 struct Checked{left:usize,polls:usize,fail:usize}impl crate::key_policy_control::Control for Checked{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.fail{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.left=self.left.checked_sub(n).ok_or(std::io::ErrorKind::OutOfMemory)?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{self.overflow()}}
 #[test]fn controlled_original_raw_type_var_scanner_preserves_every_legacy_pair_and_order(){let text="/obj/direct/var/static/list/items = list()\n/obj/block\n    var\n        first\n        list/second = list()\n    proc/reset()\n        var/local\nSYSTEM_DEF(clock)\n    var/tick = 1\n/proc/root()\n    var/local\n/obj/block/var/last\n";let mut old=Vec::new();original::visit(text,|t,n|old.push((t.to_owned(),n.to_owned())));let mut now=Vec::new();visit_with(text,&mut Checked{left:1024*1024,polls:0,fail:usize::MAX},&mut|t,n|{now.push((t.to_owned(),n.to_owned()));Ok(())}).unwrap();assert_eq!(now,old);assert!(!old.is_empty());}
 #[test]fn controlled_original_raw_type_var_scanner_returns_actual_io_before_later_rows_then_recovers(){let text="/obj/a\n    var/first\n    var/second\n";let mut c=Checked{left:1024*1024,polls:0,fail:3};let error=visit_with(text,&mut c,&mut|_,_|Ok(())).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(c.polls,3);let mut rows=Vec::new();visit_with(text,&mut Checked{left:1024*1024,polls:0,fail:usize::MAX},&mut|t,n|{rows.push((t.to_owned(),n.to_owned()));Ok(())}).unwrap();assert_eq!(rows.len(),2);}
 #[test]fn native_capture_group_reservation_is_once_per_file_not_per_source_line(){let source=format!("/obj/a\n{}","    var/value\n".repeat(20000));let mut control=Checked{left:4096,polls:0,fail:usize::MAX};let mut count=0usize;visit_with(&source,&mut control,&mut|_,_|{count+=1;Ok(())}).unwrap();assert_eq!(count,20000);assert!(control.left>2048,"only fixedmaxCaps and currenttype storage are admitted");}

}

fn capture_fixed<'h,C:crate::key_policy_control::Control>(c:&mut C,source:&'static str,text:&'h str,maximum:usize,legacy:fn()->&'static crate::pat::Pat)->Result<Option<crate::pat::Caps<'h>>,C::Error>{
 #[cfg(feature="native-policy")]if let Some(provider)=c.native_patterns(){
  let spec=crate::native_pattern::Spec{pattern:source,mode:crate::native_pattern::Mode::Search};let count=provider.capture_len(spec).map_err(|actual|c.native_pattern_failed(actual))?;
  if count>maximum{return Err(c.native_pattern_failed(std::io::Error::new(std::io::ErrorKind::InvalidData,"same raw-variable program exceeds its admitted fixed capture roster")))}
  let mut groups=Vec::new();groups.try_reserve_exact(count).map_err(|_|c.allocation_failed())?;if groups.capacity()>maximum{return Err(c.allocation_failed())}
  let pending=c.native_patterns().expect("same operation provider remains borrowed").capture(spec,text,0,&mut|row|{if row.len()>groups.capacity(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"raw-variable capture exceeds its actual program width"))}groups.extend_from_slice(row);Ok(())});let found=pending.map_err(|actual|c.native_pattern_failed(actual))?;return Ok(found.then_some(crate::pat::Caps{hay:text,groups}))
 }
 let _=(source,maximum);Ok(legacy().captures(text))
}

#[cfg(all(test,feature="native-policy"))]mod native_width_failure_controls{
 use super::*;use std::{io,sync::atomic::{AtomicBool,Ordering}};
 struct Refuse(AtomicBool);impl crate::native_pattern::Provider for Refuse{
  fn capture_len(&self,_:crate::native_pattern::Spec)->io::Result<usize>{self.0.store(true,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}
  fn find(&self,_:crate::native_pattern::Spec,_:&str,_:usize,_:&mut dyn FnMut((usize,usize))->io::Result<()>)->io::Result<bool>{panic!("no search after actual width failure")}
  fn capture(&self,_:crate::native_pattern::Spec,_:&str,_:usize,_:&mut dyn FnMut(&[Option<(usize,usize)>])->io::Result<()>)->io::Result<bool>{panic!("no capture after actual width failure")}
 }
 struct Work<'a>(&'a Refuse);impl crate::key_policy_control::Control for Work<'_>{type Error=io::Error;const CHECKED:bool=true;fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{Some(self.0)}fn native_pattern_failed(&mut self,actual:io::Error)->io::Error{actual}fn checkpoint(&mut self)->io::Result<()>{if self.0.0.load(Ordering::SeqCst){Err(io::ErrorKind::Interrupted.into())}else{Ok(())}}fn reserve(&mut self,_:usize)->io::Result<()>{Ok(())}fn overflow(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{self.overflow()}}
 #[test]fn actual_native_typevar_width_failure_is_not_reclassified_or_followed_by_legacy_fallback(){let provider=Refuse(AtomicBool::new(false));let mut rows=0;let error=visit_with("/obj/a\n    var/x\n",&mut Work(&provider),&mut|_,_|{rows+=1;Ok(())}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(rows,0);}
}
