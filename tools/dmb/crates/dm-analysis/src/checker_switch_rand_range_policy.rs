//! Pure range policy over already evaluated original numeric DATA.
//! Source identity, constant evaluation, diagnostic ordering and publication
//! belong to the existing authenticated checker body traversal, not this module.
//!
//! Algorithm/wording: DreamChecker (GPL-3.0), SpacemanDMM commit
//! 0290db5c752fa292f9824521515b603a2afd11dc, switch_rand_range.rs
//! SHA256 e29bbe76766a3245999977267ede3363d60292de9ea1fc2ab325902613b1284d.
use std::{fmt,mem::size_of};
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct Bounds{pub start:i32,pub end:i32}
/// None means the original simple evaluator did not produce a number. No
/// dynamic/global evaluator or alternative constant semantics may fill it in.
pub fn rand_bounds(arguments:&[Option<f32>])->Option<Bounds>{
 let(min,max)=match arguments{[Some(max)]=>(0.,*max),[Some(min),Some(max)]=>(*min,*max),_=>return None};
 Some(Bounds{start:min.ceil()as i32,end:max.floor()as i32})
}
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Finding{
 Outside{case:usize,start:i32,end:i32,random:Bounds},
 Gap{random:Bounds,first_uncovered:i32},
}
impl fmt::Display for Finding{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{match self{
 Self::Outside{start,end,random,..}=>write!(f,"Case range '{start} to {end}' will never trigger as it is outside the rand() range {} to {}",random.start,random.end),
 Self::Gap{random,first_uncovered}=>write!(f,"Switch branches on rand() with range {} to {} but no case branch triggers for {first_uncovered}",random.start,random.end),
}}}
/// Operation-scoped hooks use the caller's existing budget and typed failure.
/// Findings are staged by the caller until its complete traversal succeeds.
pub trait Control{
 type Error;
 fn checkpoint(&mut self)->Result<(),Self::Error>;
 fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>;
 fn allocation_failed(&mut self)->Self::Error;
 fn emit(&mut self,finding:Finding)->Result<(),Self::Error>;
}
/// Every iterator row corresponds to one actual case expression/range, in source
/// order. The ordinal is DATA used to join the existing real case cursor later.
/// `None` preserves the old simple-evaluation error/unsupported skip.
pub fn judge<C:Control>(random:Option<Bounds>,case_values:usize,cases:impl IntoIterator<Item=(usize,Option<(f32,f32)>)>,has_default:bool,control:&mut C)->Result<(),C::Error>{
 control.checkpoint()?;let Some(random)=random else{return Ok(())};
 // One Vec plus stable sort scratch, with bounded capacity headroom. No
 // source/String/model is retained or allocated in this numeric policy.
 let reserve=case_values.checked_mul(size_of::<(i32,i32)>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)).ok_or_else(||control.allocation_failed())?;
 control.reserve(reserve)?;let mut covered=Vec::new();covered.try_reserve_exact(case_values).map_err(|_|control.allocation_failed())?;
 if covered.capacity()>case_values.saturating_mul(4).max(4){return Err(control.allocation_failed())}
 let mut seen=0usize;
 for(case,value)in cases{
  control.checkpoint()?;seen=seen.checked_add(1).ok_or_else(||control.allocation_failed())?;if seen>case_values{return Err(control.allocation_failed())}
  let Some((start,end))=value else{continue};let start=start.ceil()as i32;let end=end.floor()as i32;
  if start<=random.end&&end>=random.start{covered.push((start,end));}else{control.emit(Finding::Outside{case,start,end,random})?;}
 }
 control.checkpoint()?;if has_default{return Ok(())}
 covered.sort_by(|a,b|a.0.cmp(&b.0));let mut first_uncovered=random.start;
 for(start,end)in covered{control.checkpoint()?;if start>first_uncovered{break}first_uncovered=first_uncovered.max(end.wrapping_add(1));}
 if first_uncovered<=random.end{control.emit(Finding::Gap{random,first_uncovered})?;}
 control.checkpoint()
}
#[cfg(test)]mod tests{
 use super::*;
 #[derive(Default)]struct Work{rows:Vec<Finding>,polls:usize,limit:usize,used:usize,stop:Option<usize>}
 impl Control for Work{type Error=&'static str;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.stop==Some(self.polls){Err("actual input IO failure")}else{Ok(())}}fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>{if self.limit!=0&&bytes>self.limit{return Err("actual budget refusal")}self.used+=bytes;Ok(())}fn allocation_failed(&mut self)->Self::Error{"actual allocation refusal"}fn emit(&mut self,finding:Finding)->Result<(),Self::Error>{self.rows.push(finding);Ok(())}}
 #[test]fn original_numeric_bounds_keep_one_argument_zero_and_original_rounding(){assert_eq!(rand_bounds(&[Some(2.8)]),Some(Bounds{start:0,end:2}));assert_eq!(rand_bounds(&[Some(-2.8),Some(3.8)]),Some(Bounds{start:-2,end:3}));for values in [&[][..],&[None][..],&[Some(1.),None][..],&[Some(1.),Some(2.),Some(3.)][..]]{assert_eq!(rand_bounds(values),None)}}
 #[test]fn outside_rows_keep_source_order_before_gap_and_default_only_suppresses_gap(){let bounds=Bounds{start:1,end:3};for default in [false,true]{let mut w=Work::default();judge(Some(bounds),3,[(5,Some((8.,8.))),(6,Some((-2.,-1.))),(7,Some((1.,1.)))],default,&mut w).unwrap();assert_eq!(w.rows[0],Finding::Outside{case:5,start:8,end:8,random:bounds});assert_eq!(w.rows[1],Finding::Outside{case:6,start:-2,end:-1,random:bounds});assert_eq!(w.rows.len(),if default{2}else{3});if !default{assert_eq!(w.rows[2],Finding::Gap{random:bounds,first_uncovered:2});}}}
 #[test]fn overlapping_fractional_and_unknown_cases_preserve_original_coverage(){let mut w=Work::default();let bounds=Bounds{start:0,end:4};judge(Some(bounds),5,[(0,Some((3.,8.))),(1,None),(2,Some((0.,1.))),(3,Some((1.1,3.8))),(4,Some((-1.,0.)))],false,&mut w).unwrap();assert!(w.rows.is_empty());assert!(w.used>0);}
 #[test]fn real_budget_and_first_io_fail_before_partial_result_and_fresh_work_recovers(){let bounds=Bounds{start:1,end:3};let mut w=Work{limit:1,..Work::default()};let mut read=false;let cases=std::iter::once_with(||{read=true;(0,Some((1.,3.)))});assert_eq!(judge(Some(bounds),1,cases,false,&mut w),Err("actual budget refusal"));assert!(!read);assert!(w.rows.is_empty());let mut w=Work{stop:Some(2),..Work::default()};assert_eq!(judge(Some(bounds),1,[(0,Some((1.,3.)))],false,&mut w),Err("actual input IO failure"));assert!(w.rows.is_empty());let mut w=Work::default();judge(Some(bounds),1,[(0,Some((1.,3.)))],false,&mut w).unwrap();assert!(w.rows.is_empty());}
 #[test]fn release_reference_extreme_end_keeps_original_wrapping_then_max_rule(){let random=Bounds{start:i32::MAX,end:i32::MAX};let mut w=Work::default();judge(Some(random),1,[(0,Some((i32::MAX as f32,i32::MAX as f32)))],false,&mut w).unwrap();assert_eq!(w.rows,[Finding::Gap{random,first_uncovered:i32::MAX}]);}
 #[test]fn original_warning_wording_is_written_without_owning_a_message(){let random=Bounds{start:1,end:3};assert_eq!(Finding::Outside{case:0,start:5,end:5,random}.to_string(),"Case range '5 to 5' will never trigger as it is outside the rand() range 1 to 3");assert_eq!(Finding::Gap{random,first_uncovered:2}.to_string(),"Switch branches on rand() with range 1 to 3 but no case branch triggers for 2");}

}
