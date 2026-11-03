//! Operation-local controls for the unchanged unique keys algorithm.
//! No cache, source authority, or semantic model lives here.
use std::{convert::Infallible,fmt};
pub trait Control {
    type Error;
    const CHECKED: bool;
    fn checkpoint(&mut self)->Result<(),Self::Error>;
    fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>;
    /// An operation-local maximum-live scratch envelope. Distinct slots represent
    /// allocations which may coexist. The default stays conservatively cumulative;
    /// only a source-scoped owner may reuse its own funded slot high-water mark.
    fn temporary(&mut self,_slot:usize,bytes:usize)->Result<(),Self::Error>{self.reserve(bytes)}
    fn overflow(&mut self)->Self::Error;
    fn allocation_failed(&mut self)->Self::Error;
}
pub struct Compatibility;
impl Control for Compatibility {
    type Error=Infallible;
    const CHECKED:bool=false;
    fn checkpoint(&mut self)->Result<(),Infallible>{Ok(())}
    fn reserve(&mut self,_:usize)->Result<(),Infallible>{Ok(())}
    fn overflow(&mut self)->Infallible{unreachable!("compatibility never computes native bounds")}
    fn allocation_failed(&mut self)->Infallible{unreachable!("compatibility uses original allocation APIs")}
}
pub fn reserve<C:Control>(c:&mut C,bytes:impl FnOnce()->Option<usize>)->Result<(),C::Error>{
    if !C::CHECKED{return Ok(())}
    c.checkpoint()?;
    let bytes=bytes().ok_or_else(||c.overflow())?;c.reserve(bytes)
}
pub fn temporary<C:Control>(c:&mut C,slot:usize,bytes:impl FnOnce()->Option<usize>)->Result<(),C::Error>{
    if !C::CHECKED{return Ok(())}
    c.checkpoint()?;let bytes=bytes().ok_or_else(||c.overflow())?;c.temporary(slot,bytes)
}
pub fn own<C:Control>(c:&mut C,value:&str)->Result<String,C::Error>{
    reserve(c,||value.len().checked_add(64))?;Ok(value.to_owned())
}
pub fn upper<C:Control>(c:&mut C,value:&str)->Result<String,C::Error>{
    // Full Unicode uppercase expands by at most3 scalars; geometric String
    // growth plus original/current buffers is conservatively reserved first.
    reserve(c,||value.len().checked_mul(6)?.checked_add(64))?;Ok(value.to_uppercase())
}
pub fn row<C:Control,T>(c:&mut C,rows:&mut Vec<T>)->Result<(),C::Error>{
    if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}
    let cap=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;
    reserve(c,||cap.checked_mul(std::mem::size_of::<T>())?.checked_add(64))?;
    rows.try_reserve_exact(cap-rows.len()).map_err(|_|c.allocation_failed())
}
pub fn split<C:Control>(c:&mut C,width:usize)->Result<(),C::Error>{
    reserve(c,||width.checked_add(1)?.checked_mul(3*std::mem::size_of::<String>())?.checked_add(width.checked_mul(4)?)?.checked_add(256))
}
pub fn format<C:Control>(c:&mut C,args:fmt::Arguments<'_>)->Result<String,C::Error>{
    if !C::CHECKED{return Ok(fmt::format(args))}
    struct Writer<'a,C:Control>{control:&'a mut C,text:String,error:Option<C::Error>}
    impl<C:Control> fmt::Write for Writer<'_,C>{
        fn write_str(&mut self,s:&str)->fmt::Result{
            if self.error.is_some(){return Err(fmt::Error)}
            let need=match self.text.len().checked_add(s.len()){Some(n)=>n,None=>{self.error=Some(self.control.overflow());return Err(fmt::Error)}};
            if need>self.text.capacity(){
                let cap=need.max(self.text.capacity().saturating_mul(2)).max(64);
                let result=reserve(self.control,||cap.checked_add(64)).and_then(|_|self.text.try_reserve_exact(cap-self.text.len()).map_err(|_|self.control.allocation_failed()));
                if let Err(actual)=result{self.error=Some(actual);return Err(fmt::Error)}
            }
            self.text.push_str(s);Ok(())
        }
    }
    let mut writer=Writer{control:c,text:String::new(),error:None};
    let result=fmt::write(&mut writer,args);
    if let Some(actual)=writer.error{return Err(actual)}
    if result.is_err(){return Err(writer.control.allocation_failed())}
    writer.control.checkpoint()?;Ok(writer.text)
}
#[cfg(test)]mod tests{
    use super::*;
    struct Probe{left:usize,polls:usize,fail_at:usize}
    impl Control for Probe{
        type Error=std::io::Error;const CHECKED:bool=true;
        fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.fail_at{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}
        fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>{self.checkpoint()?;self.left=self.left.checked_sub(bytes).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}
        fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}
        fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}
    }
    #[test]fn compatibility_does_not_even_evaluate_native_bound_arithmetic(){reserve(&mut Compatibility,||panic!("not part of old policy")).unwrap();assert_eq!(format(&mut Compatibility,format_args!("{} {}","old",7)).unwrap(),"old 7");}
    #[test]fn admitted_formatter_preserves_actual_error_and_never_returns_partial_output(){let mut c=Probe{left:4096,polls:0,fail_at:4};let e=format(&mut c,format_args!("{}{}","x".repeat(100),"y".repeat(100))).unwrap_err();assert_eq!(e.raw_os_error(),Some(1450));}
    #[test]fn exact_growth_and_unicode_output_match_original_under_sufficient_admission(){let mut c=Probe{left:65536,polls:0,fail_at:usize::MAX};assert_eq!(upper(&mut c,"straße ΐ").unwrap(),"straße ΐ".to_uppercase());let mut v:Vec<u64>=Vec::new();row(&mut c,&mut v).unwrap();assert!(v.capacity()>=4);assert_eq!(format(&mut c,format_args!("{}.{}:{}","prefix","op",73)).unwrap(),"prefix.op:73");let mut denied=Probe{left:1,polls:0,fail_at:usize::MAX};assert!(row::<_,u64>(&mut denied,&mut Vec::new()).is_err());}
}

// SAME stateless checked heapsort, also used by the compiler checker.
#[path="../../dmb/shared/fallible_sort.rs"]mod fallible_sort;
pub use fallible_sort::heapsort as sort_data;

// Shared operation-local first-error latch. No cache, budget or source role.
pub trait Gate{fn checked(&self)->bool;fn checkpoint(&self)->bool;fn reserve(&self,bytes:Option<usize>)->bool;fn allocation_failed(&self);}
pub struct Controlled<C:crate::key_policy_control::Control>{control:std::cell::RefCell<C>,error:std::cell::RefCell<Option<C::Error>>}
impl<C:crate::key_policy_control::Control> Controlled<C>{
 pub fn new(control:C)->Self{Self{control:std::cell::RefCell::new(control),error:std::cell::RefCell::new(None)}}
 fn perform(&self,f:impl FnOnce(&mut C)->Result<(),C::Error>)->bool{if self.error.borrow().is_some(){return false}match f(&mut*self.control.borrow_mut()){Ok(())=>true,Err(actual)=>{*self.error.borrow_mut()=Some(actual);false}}}
 pub fn finish<T>(self,value:T)->Result<T,C::Error>{match self.error.into_inner(){Some(actual)=>Err(actual),None=>Ok(value)}}
}
impl<C:crate::key_policy_control::Control> Gate for Controlled<C>{fn checked(&self)->bool{C::CHECKED}fn checkpoint(&self)->bool{self.perform(|c|c.checkpoint())}fn reserve(&self,bytes:Option<usize>)->bool{self.perform(|c|{c.checkpoint()?;if C::CHECKED{let n=bytes.ok_or_else(||c.overflow())?;c.reserve(n)?;}Ok(())})}fn allocation_failed(&self){self.perform(|c|Err(c.allocation_failed()));}}

/// Operation-local real table growth, shared by policy builders. No payload,
/// source grant or counter is retained here; old compatibility uses insert.
pub fn hash_room<C:Control,K:Eq+std::hash::Hash,V>(c:&mut C,rows:&mut std::collections::HashMap<K,V>)->Result<(),C::Error>{
 if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}c.checkpoint()?;
 let goal=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;let bound=goal.checked_mul(4).ok_or_else(||c.overflow())?;
 reserve(c,||bound.checked_mul(std::mem::size_of::<(K,V)>()+2*std::mem::size_of::<usize>())?.checked_add(256))?;
 rows.try_reserve(1).map_err(|_|c.allocation_failed())?;if rows.capacity()>bound{return Err(c.allocation_failed())}Ok(())
}
pub fn set_room<C:Control,K:Eq+std::hash::Hash>(c:&mut C,rows:&mut std::collections::HashSet<K>)->Result<(),C::Error>{
 if !C::CHECKED||rows.len()<rows.capacity(){return Ok(())}c.checkpoint()?;
 let goal=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?;let bound=goal.checked_mul(4).ok_or_else(||c.overflow())?;
 reserve(c,||bound.checked_mul(std::mem::size_of::<K>()+2*std::mem::size_of::<usize>())?.checked_add(256))?;
 rows.try_reserve(1).map_err(|_|c.allocation_failed())?;if rows.capacity()>bound{return Err(c.allocation_failed())}Ok(())
}
