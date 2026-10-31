//! Exact lexical setter-call policy shared by old and native source consumers.
//! Source acquisition and comment/string stripping belong to the existing caller.
use crate::key_policy_control::{self as kc,Control};
pub const LIST_CALL:&str="[]";
pub const PREFIXES:&[&str]=&["set_","add_","include_","remove_","clear_","insert_","swap_","cut_"];
pub const AUTO_REL:&str="code/engine/_generated/auto_tracked.dm";
pub fn wants_file(relative:&str,text:&str)->bool{relative!=AUTO_REL&&PREFIXES.iter().any(|prefix|text.contains(prefix))}
fn append<C:Control>(control:&mut C,out:&mut Vec<String>,pattern:&crate::pat::Pat,line:&str,list:bool)->Result<(),C::Error>{
 let mut state=(control,out);
 pattern.try_for_each_capture(line,&mut state,|state,groups|{
  kc::reserve(state.0,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64))
 },|state,m|{
  state.0.checkpoint()?;
  let name=if list{let v=if m.s(1).is_empty(){m.s(2)}else{m.s(1)};kc::format(state.0,format_args!("{}{}",v,LIST_CALL))?}else{kc::own(state.0,m.s(1))?};
  kc::row(state.0,state.1)?;state.1.push(name);Ok(())
 })
}
pub fn collect_file<'a,C:Control>(control:&mut C,relative:&str,text:&str,code:impl FnOnce()->&'a str)->Result<Vec<String>,C::Error>{
 control.checkpoint()?;
 let mut out=Vec::new();
 if !wants_file(relative,text){return Ok(out)}
 let code=code();
 let call=crate::pat!(r"(?:^|[^\w/])set_(\w+)\s*\(");
 let list_call=crate::pat!(r"(?:^|[^\w/])(?:(?:add|include|remove|clear|insert|swap|cut)_(\w+)|set_(\w+)_at)\s*\(");
 for line in code.lines(){
  control.checkpoint()?;
  if !line.starts_with(char::is_whitespace)||line.contains("proc/set_")||line.trim_start().starts_with('#'){continue}
  if line.contains("set_"){append(control,&mut out,&call,line,false)?;}
  if ["add_","include_","remove_","clear_","insert_","swap_","cut_"].iter().any(|prefix|line.contains(prefix))||(line.contains("set_")&&line.contains("_at")){append(control,&mut out,&list_call,line,true)?;}
 }
 control.checkpoint()?;out.sort();out.dedup();control.checkpoint()?;Ok(out)
}

#[cfg(test)]mod tests{
use super::*;
const SETTER_PREFIXES:&[&str]=PREFIXES;
fn original(relative:&str,text:&str,code:&str)->Vec<String>{
            let mut out: Vec<String> = Vec::new();
            if relative == AUTO_REL || !SETTER_PREFIXES.iter().any(|p| text.contains(p)) {
                return out;
            }
            let call = crate::pat!(r"(?:^|[^\w/])set_(\w+)\s*\(");
            let list_call = crate::pat!(r"(?:^|[^\w/])(?:(?:add|include|remove|clear|insert|swap|cut)_(\w+)|set_(\w+)_at)\s*\(");
            for line in code.lines() {
                if !line.starts_with(char::is_whitespace) || line.contains("proc/set_") || line.trim_start().starts_with('#') {
                    continue;
                }
                for m in call.captures_iter(line) {
                    out.push(m.s(1).to_string());
                }
                for m in list_call.captures_iter(line) {
                    let v = if m.s(1).is_empty() { m.s(2) } else { m.s(1) };
                    out.push(format!("{}{}", v, LIST_CALL));
                }
            }
            out.sort();
            out.dedup();
            out
}

#[test]fn complete_old_setter_call_results_preserve_lexical_quirks(){
 let cases=[("code/probe.dm","    set_x(1)\n    add_x(2)\n"),("code/probe.dm","/datum/proc/set_x(value)\n    return value\n"),("code/probe.dm","    #define F set_x(2)\n    set_x(3)\n    set_x(4)\n"),("code/probe.dm","    Q.set_a_at(2,3)\n    include_b(2)\n    clear_c()\n    cut_d(1)\n    swap_e(2,3)\n    insert_f(1)\n    remove_g(2)\n"),(AUTO_REL,"    set_x(1)\n"),("code/probe.dm","set_x(1)\n"),("code/probe.dm","    proc/set_x(v)\n    x = 1\n")];
 for (relative,code) in cases{assert_eq!(collect_file(&mut kc::Compatibility,relative,code,||code).unwrap(),original(relative,code,code),"{relative}: {code:?}");}
}
#[test]fn excluded_files_never_acquire_or_strip_code(){for (relative,text) in [(AUTO_REL,"    set_x(1)"),("code/a.dm","    return 1")]{assert!(collect_file(&mut kc::Compatibility,relative,text,||panic!("excluded code acquisition")).unwrap().is_empty());}}
struct Probe{left:usize,stop:bool}
impl Control for Probe{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{if self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.left=self.left.checked_sub(n).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
#[test]fn actual_cancellation_and_output_admission_refuse_then_retry(){let code="    set_x(1)\n    add_y(2)\n";let e=collect_file(&mut Probe{left:4096,stop:true},"code/a.dm",code,||code).unwrap_err();assert_eq!(e.raw_os_error(),Some(1450));assert!(collect_file(&mut Probe{left:0,stop:false},"code/a.dm",code,||code).is_err());assert_eq!(collect_file(&mut Probe{left:4096,stop:false},"code/a.dm",code,||code).unwrap(),vec!["x","y[]"]);}
}
