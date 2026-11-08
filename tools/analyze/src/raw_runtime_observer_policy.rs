//! SAME lexical runtime observe(...) marker scan, with optional allocation/work control.
use crate::{raw_marker_policy::{matching_paren,split_args},key_policy_control as kc};
pub const RUNTIME_OBSERVE:&str="RUNTIME_OBSERVE";
#[derive(Debug,PartialEq,Eq)]pub struct Projection{pub line:u32,pub args:Vec<String>,pub body:String,pub body_offset:usize}
pub fn visit<C:kc::Control>(text:&str,starts:&[u32],control:&mut C,emit:&mut impl FnMut(&mut C,Projection)->Result<(),C::Error>)->Result<(),C::Error>{
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        control.checkpoint()?;
        if bytes[i] == b'"' {
            i += 1;
            while i < bytes.len() {
                control.checkpoint()?;
                if bytes[i] == b'\\' {
                    i += 2;
                    continue;
                }
                if bytes[i] == b'"' {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }
        let start = i;
        if !bytes[i].is_ascii_alphabetic() && bytes[i] != b'_' {
            i += 1;
            continue;
        }
        while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
            control.checkpoint()?;i += 1;
        }
        if &text[start..i] != "observe"
            || (start > 0
                && (bytes[start - 1].is_ascii_alphanumeric()
                    || matches!(bytes[start - 1], b'_' | b'.' | b'/' | b':')))
        {
            continue;
        }
        let mut open = i;
        while open < bytes.len() && bytes[open].is_ascii_whitespace() {
            control.checkpoint()?;
            open += 1;
        }
        if bytes.get(open) != Some(&b'(') {
            continue;
        }
        let Some(close) = matching_paren(text, open) else {
            continue;
        };
        let width=close-open-1;kc::temporary(control,0,||kc::split_bound(width))?;kc::temporary(control,1,||width.checked_add(64))?;
        let body = text[open + 1..close].to_string();
        let args = split_args(&body);
        if args.len() < 4 {
            continue;
        }
        let line = match starts.binary_search(&(start as u32)) {
            Ok(n) => n as u32 + 1,
            Err(n) => n as u32,
        };
        emit(control,Projection{line,args,body,body_offset:open+1})?;
    }
    control.checkpoint()?;Ok(())
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::Arc;use crate::tree::SourceFile;
 struct Marker{name:String,rel:String,line:u32,args:Vec<String>,body:String,body_offset:usize,line_starts:Arc<Vec<u32>>}
 #[derive(Default)]struct FileDecls{markers:Vec<Marker>}
 fn scan_runtime_observers(f: &SourceFile, text: &str, starts: &Arc<Vec<u32>>, fd: &mut FileDecls) {
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'"' {
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'\\' {
                    i += 2;
                    continue;
                }
                if bytes[i] == b'"' {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }
        let start = i;
        if !bytes[i].is_ascii_alphabetic() && bytes[i] != b'_' {
            i += 1;
            continue;
        }
        while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
            i += 1;
        }
        if &text[start..i] != "observe"
            || (start > 0
                && (bytes[start - 1].is_ascii_alphanumeric()
                    || matches!(bytes[start - 1], b'_' | b'.' | b'/' | b':')))
        {
            continue;
        }
        let mut open = i;
        while open < bytes.len() && bytes[open].is_ascii_whitespace() {
            open += 1;
        }
        if bytes.get(open) != Some(&b'(') {
            continue;
        }
        let Some(close) = matching_paren(text, open) else {
            continue;
        };
        let body = text[open + 1..close].to_string();
        let args = split_args(&body);
        if args.len() < 4 {
            continue;
        }
        let line = match starts.binary_search(&(start as u32)) {
            Ok(n) => n as u32 + 1,
            Err(n) => n as u32,
        };
        fd.markers.push(Marker {
            name: RUNTIME_OBSERVE.to_string(),
            rel: f.rel.clone(),
            line,
            args,
            body,
            body_offset: open + 1,
            line_starts: starts.clone(),
        });
    }
}
 fn old(text:&str,starts:&Arc<Vec<u32>>)->Vec<Projection>{let file=SourceFile::from_text("code/probe.dm",text);let mut fd=FileDecls::default();scan_runtime_observers(&file,text,starts,&mut fd);fd.markers.into_iter().map(|m|{assert_eq!(m.name,RUNTIME_OBSERVE);assert_eq!(m.rel,"code/probe.dm");assert!(Arc::ptr_eq(&m.line_starts,starts));Projection{line:m.line,args:m.args,body:m.body,body_offset:m.body_offset}}).collect()}
 #[test]fn complete_frozen_observe_projection_matches_order_and_lexical_quirks(){
  let cases=["observe(src, /datum/notice/x, src, then(PROC_REF(p)))", "    observe(src, /datum/notice/x, src, then(PROC_REF(p)))\n    observe(src, /datum/act/x, src, needs(PROC_REF(q)))", "xobserve(a,b,c,d); src.observe(a,b,c,d); /observe(a,b,c,d); ::observe(a,b,c,d)", "\"observe(a,b,c,d)\"; observe(a,b,c)", "observe(a,b,c,then(observe(d,e,f,g)))", "éobserve(a,b,c,d)"];
  for text in cases{let mut starts=vec![0];for(i,b)in text.bytes().enumerate(){if b==b'\n'{starts.push((i+1)as u32)}}let starts=Arc::new(starts);let expected=old(text,&starts);let mut got=Vec::new();visit(text,&starts,&mut kc::Compatibility,&mut|_,row|{got.push(row);Ok(())}).unwrap();assert_eq!(got,expected,"{text:?}");}
 }
 struct Guard{left:usize,stop:bool}
 impl kc::Control for Guard{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{if self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.left=self.left.checked_sub(n).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn actual_operational_refusal_emits_no_row_and_same_input_recovers(){let text="observe(a,b,c,then(PROC_REF(p)))";for(mut control,kind)in [(Guard{left:0,stop:false},std::io::ErrorKind::OutOfMemory),(Guard{left:65536,stop:true},std::io::ErrorKind::Other)]{let mut rows=Vec::new();let error=visit(text,&[0],&mut control,&mut|_,row|{rows.push(row);Ok(())}).unwrap_err();assert!(rows.is_empty());if kind==std::io::ErrorKind::Other{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),kind)}}let mut rows=Vec::new();visit(text,&[0],&mut Guard{left:65536,stop:false},&mut|_,row|{rows.push(row);Ok(())}).unwrap();assert_eq!(rows,old(text,&Arc::new(vec![0])));}
}
