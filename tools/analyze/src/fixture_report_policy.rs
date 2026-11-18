//! Shared exact fixture output over borrowed actual Run/finding DATA.
//! No source reader, parser, semantic model, file writer or completion grant.
use crate::{lint::Site,parity_types::Finding,derived_selftest_policy::Failure,key_policy_control::{self as kc,Control}};
use std::io::{self,Write};
/// Stable old rule/file/line order without cloning Site strings or allocating
/// sort scratch: ordinal makes unstable sorting exactly the old stable order.
pub fn write_sites<C:Control>(sites:&[Site],control:&mut C,out:&mut impl Write)->Result<(),C::Error> where C::Error:From<io::Error>{
 control.checkpoint()?;
 let upper=sites.len().checked_mul(4).ok_or_else(||control.overflow())?;
 kc::reserve(control,||upper.checked_mul(std::mem::size_of::<(usize,&Site)>()))?;
 let mut order=Vec::new();if C::CHECKED{order.try_reserve_exact(sites.len()).map_err(|_|control.allocation_failed())?;if order.capacity()>upper{return Err(control.overflow())}}else{order.reserve(sites.len())}
 for(i,site)in sites.iter().enumerate(){control.checkpoint()?;order.push((i,site))}
 order.sort_unstable_by(|(a,x),(b,y)|(x.rule.as_str(),x.rel.as_str(),x.line,a).cmp(&(y.rule.as_str(),y.rel.as_str(),y.line,b)));
 for(_,row)in order{control.checkpoint()?;writeln!(out,"{}\t{}\t{}\t{}",row.rule,row.rel,row.line,row.msg).map_err(C::Error::from)?;}
 control.checkpoint()?;writeln!(out,"{} findings",sites.len()).map_err(C::Error::from)
}
/// Findings are the actual normalized/sorted producer projection. This function
/// only preserves the original expected.txt bytes; it does not normalize them.
pub fn write_expected<C:Control>(findings:&[Finding],control:&mut C,out:&mut impl Write)->Result<(),C::Error> where C::Error:From<io::Error>{
 for row in findings{control.checkpoint()?;writeln!(out,"{}\t{}\t{}",row.rule,row.rel,row.line).map_err(C::Error::from)?;}Ok(())
}
#[cfg(test)]mod controls{
 use super::*;
 #[test]fn shared_fixture_rows_keep_message_tabs_duplicates_stable_order_and_exact_expected_bytes(){
  let rows=[("z","b.dm",2,"last"),("a","a.dm",1,"first\tmessage"),("a","a.dm",1,"same site second message")].map(|(rule,rel,line,msg)|Site{rule:rule.into(),rel:rel.into(),line,msg:msg.into(),key:String::new(),ident:String::new()});let mut out=Vec::new();write_sites(&rows,&mut crate::derived_selftest_policy::LegacyAssertions,&mut out).unwrap();assert_eq!(String::from_utf8(out).unwrap(),"a\ta.dm\t1\tfirst\tmessage\na\ta.dm\t1\tsame site second message\nz\tb.dm\t2\tlast\n3 findings\n");let findings=[Finding{rule:"a".into(),rel:"a.dm".into(),line:1},Finding{rule:"a".into(),rel:"a.dm".into(),line:1}];let mut out=Vec::new();write_expected(&findings,&mut crate::derived_selftest_policy::LegacyAssertions,&mut out).unwrap();assert_eq!(out,b"a\ta.dm\t1\na\ta.dm\t1\n");
 }
 #[test]fn admitted_fixture_rows_stop_at_actual_first_writer_1450_without_later_poll(){
  struct Stop;impl Write for Stop{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no later flush")}}
  let row=Site{rule:"actual".into(),rel:"code/a.dm".into(),line:1,msg:String::new(),key:String::new(),ident:String::new()};let budget=crate::captured_generator_budget::Budget::new(4096).unwrap();let polls=std::cell::Cell::new(0);let poll=||{polls.set(polls.get()+1);Ok(())};let mut c=crate::derived_selftest_policy::NativeAssertions{budget:&budget,poll:&poll};let error=write_sites(&[row],&mut c,&mut Stop).unwrap_err();assert!(matches!(error,Failure::Operational(e)if e.raw_os_error()==Some(1450)));
 }
}

/// Default parity normalization is identity, preserving duplicate sites. Sort
/// borrowed rows rather than clone production strings just for expected.txt.
pub fn write_identity_expected<C:Control>(sites:&[Site],control:&mut C,out:&mut impl Write)->Result<(),C::Error> where C::Error:From<io::Error>{
 control.checkpoint()?;kc::reserve(control,||sites.len().checked_mul(4)?.checked_mul(std::mem::size_of::<&Site>()))?;
 let mut order=Vec::new();order.try_reserve_exact(sites.len()).map_err(|_|control.allocation_failed())?;
 if order.capacity()>sites.len().checked_mul(4).ok_or_else(||control.overflow())?{return Err(control.overflow())}
 for site in sites{control.checkpoint()?;order.push(site)}
 order.sort_unstable_by(|x,y|(x.rule.as_str(),x.rel.as_str(),x.line).cmp(&(y.rule.as_str(),y.rel.as_str(),y.line)));
 for row in order{control.checkpoint()?;writeln!(out,"{}\t{}\t{}",row.rule,row.rel,row.line).map_err(C::Error::from)?;}Ok(())
}


#[cfg(test)]mod generic_expected_error_controls{
 use super::*;
 use crate::reactive_reads_native::Failure as ReactiveFailure;
 struct Reactive{polls:usize}
 impl Control for Reactive{
  type Error=ReactiveFailure;const CHECKED:bool=false;
  fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;Ok(())}
  fn reserve(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}
  fn overflow(&mut self)->Self::Error{ReactiveFailure::Operational(io::ErrorKind::OutOfMemory.into())}
  fn allocation_failed(&mut self)->Self::Error{self.overflow()}
 }
 #[test]fn same_expected_writer_preserves_both_error_roles_and_identical_bytes(){
  let rows=[Finding{rule:"rule".into(),rel:"a.dm".into(),line:7},Finding{rule:"rule".into(),rel:"a.dm".into(),line:7}];
  let(mut legacy,mut native)=(Vec::new(),Vec::new());write_expected(&rows,&mut crate::derived_selftest_policy::LegacyAssertions,&mut legacy).unwrap();let mut c=Reactive{polls:0};write_expected(&rows,&mut c,&mut native).unwrap();assert_eq!(native,legacy);assert_eq!(native,b"rule\ta.dm\t7\nrule\ta.dm\t7\n");assert_eq!(c.polls,2);
 }
 #[test]fn same_expected_writer_moves_first_raw_io_without_later_checkpoint(){
  struct Stop;impl Write for Stop{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("no subsequent flush")}}
  let rows=[Finding{rule:"rule".into(),rel:"a.dm".into(),line:7},Finding{rule:"later".into(),rel:"b.dm".into(),line:8}];let mut c=Reactive{polls:0};let error=write_expected(&rows,&mut c,&mut Stop).unwrap_err();let ReactiveFailure::Operational(actual)=error else{panic!("writer IO cannot become semantic Unsupported")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(c.polls,1);
 }
}
