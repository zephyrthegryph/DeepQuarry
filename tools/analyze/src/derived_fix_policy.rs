//! Exact historical derived selftest edit kernel over borrowed source DATA.
//! It parses no source and issues no filesystem/report/completion authority.
use std::{collections::BTreeMap,fmt};
use crate::{derived_reads_judge::Finding,derived_reads_collect_policy::proc_kind,derived_reads_policy::kind_call,pat::Pat,key_policy_control::{self as kc,Control}};
pub(crate) struct Procedure<'a>{pub relative:&'a str,pub owner:&'a str,pub name:&'a str,pub start:usize,pub body:Vec<usize>}
pub(crate) trait Source{
 fn procedures(&self)->&[Procedure<'_>];fn raw_text(&self,relative:&str)->Option<&str>;
 fn derived(&self,owner:&str)->Option<&Procedure<'_>>{self.procedures().iter().rev().find(|p|p.owner==owner&&p.name=="derived")}
}
enum Op{Merge(String),After(String),Before(Vec<String>)}
struct Names<'a>(&'a[String]);
impl fmt::Display for Names<'_>{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{for(i,name)in self.0.iter().enumerate(){if i!=0{f.write_str(", ")?}write!(f,"nameof({name})")?;}Ok(())}}
fn raw_lines<C:Control>(source:&impl Source,relative:&str,c:&mut C)->Result<Vec<String>,C::Error>{let mut rows=Vec::new();if let Some(text)=source.raw_text(relative){for line in text.split('\n'){c.checkpoint()?;kc::row(c,&mut rows)?;rows.push(kc::own(c,line)?);}}Ok(rows)}
fn edit<C:Control>(edits:&mut BTreeMap<String,Vec<(usize,Op)>>,relative:&str,line:usize,op:Op,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;if !edits.contains_key(relative){kc::reserve(c,||Some(2048))?;edits.insert(kc::own(c,relative)?,Vec::new());}let rows=edits.get_mut(relative).expect("inserted edit DATA");kc::row(c,rows)?;rows.push((line,op));Ok(())}
fn pattern<C:Control>(c:&mut C,text:String)->Result<Pat,C::Error>{kc::reserve(c,||text.len().checked_mul(64)?.checked_add(4096))?;Ok(Pat::new_match(&text))}
pub(crate) fn fix_texts<C:Control>(source:&impl Source,findings:&[Finding],c:&mut C)->Result<BTreeMap<String,String>,C::Error>{
 type Key=(String,String,Option<String>);let mut wanted:Vec<(Key,Vec<String>)>=Vec::new();
 for f in findings{c.checkpoint()?;if f.rule!="undeclared_read"{continue}
  let kind=kc::own(c,f.kind.as_deref().unwrap_or_default())?;let derive_name=if kind=="derive"{Some(kc::own(c,&f.proc["derive_".len()..])?)}else{None};let key=(kc::own(c,&f.owner)?,kind,derive_name);
  let pos=if let Some(pos)=wanted.iter().position(|(k,_)|*k==key){pos}else{kc::row(c,&mut wanted)?;wanted.push((key,Vec::new()));wanted.len()-1};
  let var=f.var.as_deref().unwrap_or_default();if !wanted[pos].1.iter().any(|name|name==var){kc::row(c,&mut wanted[pos].1)?;wanted[pos].1.push(kc::own(c,var)?);}
 }
 type Want=(String,Option<String>,Vec<String>);let mut by_owner:Vec<(String,Vec<Want>)>=Vec::new();
 for((owner,kind,derive_name),names)in wanted{c.checkpoint()?;if let Some((_,rows))=by_owner.iter_mut().find(|(o,_)|*o==owner){kc::row(c,rows)?;rows.push((kind,derive_name,names));}else{let mut rows=Vec::new();kc::row(c,&mut rows)?;rows.push((kind,derive_name,names));kc::row(c,&mut by_owner)?;by_owner.push((owner,rows));}}
 let mut edits=BTreeMap::new();
 for(owner,wants)in &by_owner{c.checkpoint()?;
  if let Some(block)=source.derived(owner){let lines=raw_lines(source,block.relative,c)?;
   for(kind,derive_name,names)in wants{c.checkpoint()?;let call=if kind=="derive"{"derive"}else{kind_call(kind).unwrap_or("")};let text=kc::format(c,format_args!(r"(\s*\. \+= ({})\()(.*)\)\s*$",call))?;let head=pattern(c,text)?;let mut target=None;
    for number in block.body.iter().copied(){c.checkpoint()?;let text=lines.get(number-1).map(|s|s.as_str()).unwrap_or("");kc::temporary(c,0,||head.capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64))?;
     if let Some(m)=head.captures(text){let ok=if kind!="derive"{true}else{let text=kc::format(c,format_args!(r"nameof\(\s*(?:/[\w/]+::)?{}\s*\)",derive_name.as_deref().unwrap_or("")))?;pattern(c,text)?.is_match(m.s(3))};if ok{target=Some((number,kc::own(c,m.s(1))?,kc::own(c,m.s(3))?));break}}
    }
    let extra=Names(names);if let Some((number,g1,g3))=target{let value=kc::format(c,format_args!("{}{}, {})",g1,g3,extra))?;edit(&mut edits,block.relative,number,Op::Merge(value),c)?;}else{
     let value=match kind_call(kind){Some(call)=>kc::format(c,format_args!("\t. += {}({})",call,extra))?,None=>kc::format(c,format_args!("\t. += derive(nameof({}), {})",derive_name.as_deref().unwrap_or(""),extra))?};edit(&mut edits,block.relative,*block.body.last().expect("actual declared block body"),Op::After(value),c)?;
    }
   }
  }else{
   let first=source.procedures().iter().filter(|p|p.owner==*owner&&(proc_kind(p.name).is_some()||p.name.starts_with("derive_"))).min_by(|a,b|(a.relative,a.start).cmp(&(b.relative,b.start)));let Some(first)=first else{continue};let mut lines=Vec::new();kc::row(c,&mut lines)?;lines.push(kc::format(c,format_args!("{}/derived()",owner))?);kc::row(c,&mut lines)?;lines.push(kc::own(c,"\t. = ..()")?);
   for(kind,derive_name,names)in wants{c.checkpoint()?;let extra=Names(names);let line=if kind=="derive"{kc::format(c,format_args!("\t. += derive(nameof({}), {})",derive_name.as_deref().unwrap_or(""),extra))?}else{kc::format(c,format_args!("\t. += {}({})",kind_call(kind).unwrap_or(""),extra))?};kc::row(c,&mut lines)?;lines.push(line);}
   kc::row(c,&mut lines)?;lines.push(String::new());edit(&mut edits,first.relative,first.start,Op::Before(lines),c)?;
  }
 }
 let mut out=BTreeMap::new();
 for(relative,mut todo)in edits{c.checkpoint()?;let mut lines=raw_lines(source,&relative,c)?;kc::sort_data(&mut todo,&mut|a,b|{c.checkpoint()?;Ok::<_,C::Error>(b.0.cmp(&a.0))})?;
  for(number,op)in todo{c.checkpoint()?;match op{Op::Merge(value)=>lines[number-1]=value,Op::After(value)=>{let at=number.min(lines.len());kc::row(c,&mut lines)?;lines.insert(at,value);},Op::Before(values)=>{let at=(number-1).min(lines.len());for(offset,value)in values.into_iter().enumerate(){kc::row(c,&mut lines)?;lines.insert(at+offset,value);}}}}
  struct Joined<'a>(&'a[String]);impl fmt::Display for Joined<'_>{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{for(i,row)in self.0.iter().enumerate(){if i!=0{f.write_str("\n")?}f.write_str(row)?;}Ok(())}}
  let value=kc::format(c,format_args!("{}",Joined(&lines)))?;kc::reserve(c,||Some(2048))?;out.insert(relative,value);
 }
 c.checkpoint()?;Ok(out)
}

#[cfg(all(test,feature="native-policy"))]mod controls{
 use super::*;
 struct Input{procs:Vec<Procedure<'static>>,text:&'static str}
 impl Source for Input{fn procedures(&self)->&[Procedure<'_>]{&self.procs}fn raw_text(&self,relative:&str)->Option<&str>{(relative=="code/a.dm").then_some(self.text)}}
 fn finding()->Finding{Finding{rel:"code/a.dm".into(),line:2,rule:"undeclared_read",owner:"/obj/a".into(),proc:"draw".into(),var:Some("glow".into()),kind:Some("drawn".into())}}
 fn input()->Input{Input{procs:vec![Procedure{relative:"code/a.dm",owner:"/obj/a",name:"derived",start:1,body:vec![2,3]}],text:"/obj/a/derived()\n\t. = ..()\n\t. += drawn_from(nameof(value))\n"}}
 #[test]fn shared_derived_fixture_edits_preserve_exact_merge_create_and_stability_bytes(){
  let mut c=kc::Compatibility;let result=fix_texts(&input(),&[finding()],&mut c).unwrap();assert_eq!(result["code/a.dm"],"/obj/a/derived()\n\t. = ..()\n\t. += drawn_from(nameof(value), nameof(glow))\n");assert!(fix_texts(&input(),&[],&mut c).unwrap().is_empty());
  let source=Input{procs:vec![Procedure{relative:"code/a.dm",owner:"/obj/a",name:"draw",start:1,body:vec![2]}],text:"/obj/a/draw()\n\treturn glow\n"};let result=fix_texts(&source,&[finding()],&mut c).unwrap();assert_eq!(result["code/a.dm"],"/obj/a/derived()\n\t. = ..()\n\t. += drawn_from(nameof(glow))\n\n/obj/a/draw()\n\treturn glow\n");
 }
 #[test]fn admitted_derived_fixture_kernel_preserves_actual_first_io_quota_and_recovery(){
  use crate::{captured_generator_budget::Budget,captured_allow_annotations::Operation,captured_reactive_reads::Failure};
  let budget=Budget::new(8*1024*1024).unwrap();let mut stop=Operation{budget:&budget,poll:&||Err(std::io::Error::from_raw_os_error(1450))};assert!(matches!(fix_texts(&input(),&[finding()],&mut stop),Err(Failure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let tiny=Budget::new(fixed).unwrap();let mut work=Operation{budget:&tiny,poll:&||Ok(())};assert!(matches!(fix_texts(&input(),&[finding()],&mut work),Err(Failure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));
  let mut work=Operation{budget:&budget,poll:&||Ok(())};assert!(!fix_texts(&input(),&[finding()],&mut work).unwrap().is_empty());
 }
}
