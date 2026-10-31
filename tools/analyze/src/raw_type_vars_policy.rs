//! Existing dx own-var matching policy, emitted as ephemeral callbacks.
//! This is a source-only generator projection, not another DM parser/model.
use crate::{
    pat,
    util::{py_lstrip, py_rstrip, py_strip},
};
fn absolute()->&'static crate::pat::Pat{pat!(r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b")}
fn header()->&'static crate::pat::Pat{pat!(r"^(/[\w/]+)\s*$")}
fn system()->&'static crate::pat::Pat{pat!(r"^SYSTEM_DEF\((\w+)\)\s*$")}
fn group()->&'static crate::pat::Pat{pat!(r"^(\s+)var\s*$")}
fn variable()->&'static crate::pat::Pat{pat!(r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)")}
pub fn visit(clean:&str,mut declare:impl FnMut(&str,&str)){visit_with(clean,&mut crate::key_policy_control::Compatibility,&mut|ty,name|{declare(ty,name);Ok(())}).unwrap_or_else(|never|match never{})}
/// SAME lexical scanner with direct control before each source line/materialization.
pub fn visit_with<C:crate::key_policy_control::Control>(clean:&str,c:&mut C,declare:&mut impl FnMut(&str,&str)->Result<(),C::Error>)->Result<(),C::Error>{
    crate::key_policy_control::reserve(c,||{let groups=[absolute(),header(),system(),group(),variable()].into_iter().map(|p|p.capture_group_count()).max().unwrap_or(0);groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+128)})?;
    let mut current: Option<String> = None;
    let mut group_indent: Option<usize> = None;
    for line in clean.lines() {
        c.checkpoint()?;
        if let Some(m) =
            absolute()
                .captures(line)
        {
            declare(m.s(1), m.s(2))?;
            current = None;
            continue;
        }
        if let Some(h) = header().captures(py_rstrip(line)) {
            current = Some(crate::key_policy_control::own(c,h.s(1))?);
            group_indent = None;
            continue;
        }
        // SYSTEM_DEF(x) declares /datum/system/x through a macro: its indented body is that type's block.
        if let Some(h) = system().captures(py_rstrip(line)) {
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
                if let Some(name) = pat!(r"\A[A-Za-z_]\w*").find(last) {
                    declare(cur, name.as_str())?;
                }
                continue;
            }
            group_indent = None;
        }
        if let Some(g) = group().captures(line) {
            group_indent = Some(g.s(1).len());
            continue;
        }
        if let Some(v) = variable().captures(line) {
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
