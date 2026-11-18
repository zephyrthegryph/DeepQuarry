//! Operation-local controls for the unchanged unique keys algorithm.
//! No cache, source authority, or semantic model lives here.
use std::{convert::Infallible,fmt};
pub trait Control {
    #[cfg(feature="native-policy")]
    fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{None}
    #[cfg(feature="native-policy")]
    fn native_pattern_failed(&mut self,_actual:std::io::Error)->Self::Error{self.allocation_failed()}
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
pub(crate) fn split_bound(width:usize)->Option<usize>{
    width.checked_add(1)?.checked_mul(3*std::mem::size_of::<String>())?
        .checked_add(width.checked_mul(4)?)?.checked_add(256)
}
pub fn split<C:Control>(c:&mut C,width:usize)->Result<(),C::Error>{
    reserve(c,||split_bound(width))
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
pub trait Gate{fn checked(&self)->bool;fn checkpoint(&self)->bool;fn reserve(&self,bytes:Option<usize>)->bool;fn allocation_failed(&self);
 /// SAME operation control lends exact static recipe questions. The default is
 /// the original compatibility engine; native Controlled uses its real lender.
 fn captures_pattern<'h>(&self,_source:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Option<crate::pat::Caps<'h>>{legacy().captures(text)}
 fn captures_pattern_rows<'h>(&self,_source:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Vec<crate::pat::Caps<'h>>{legacy().captures_iter(text)}
 fn matches_pattern(&self,_source:&'static str,text:&str,legacy:fn()->&'static crate::pat::Pat)->bool{legacy().is_match(text)}
}
pub struct Controlled<C:crate::key_policy_control::Control>{control:std::cell::RefCell<C>,error:std::cell::RefCell<Option<C::Error>>}
impl<C:crate::key_policy_control::Control> Controlled<C>{
 pub fn new(control:C)->Self{Self{control:std::cell::RefCell::new(control),error:std::cell::RefCell::new(None)}}
 fn perform(&self,f:impl FnOnce(&mut C)->Result<(),C::Error>)->bool{if self.error.borrow().is_some(){return false}match f(&mut*self.control.borrow_mut()){Ok(())=>true,Err(actual)=>{*self.error.borrow_mut()=Some(actual);false}}}
 fn value<T>(&self,f:impl FnOnce(&mut C)->Result<T,C::Error>)->Option<T>{if self.error.borrow().is_some(){return None}let pending=f(&mut*self.control.borrow_mut());match pending{Ok(value)=>Some(value),Err(actual)=>{self.error.borrow_mut().get_or_insert(actual);None}}}
 pub fn finish<T>(self,value:T)->Result<T,C::Error>{match self.error.into_inner(){Some(actual)=>Err(actual),None=>Ok(value)}}
}
impl<C:crate::key_policy_control::Control> Gate for Controlled<C>{
 fn captures_pattern<'h>(&self,source:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Option<crate::pat::Caps<'h>>{self.value(|c|captures_static(c,source,text,0,legacy)).flatten()}
 fn captures_pattern_rows<'h>(&self,source:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Vec<crate::pat::Caps<'h>>{self.value(|c|captures_all_static(c,source,text,legacy)).unwrap_or_default()}
 fn matches_pattern(&self,source:&'static str,text:&str,legacy:fn()->&'static crate::pat::Pat)->bool{self.value(|c|is_match_static(c,source,text,legacy)).unwrap_or(false)}
fn checked(&self)->bool{C::CHECKED}fn checkpoint(&self)->bool{self.perform(|c|c.checkpoint())}fn reserve(&self,bytes:Option<usize>)->bool{self.perform(|c|{c.checkpoint()?;if C::CHECKED{let n=bytes.ok_or_else(||c.overflow())?;c.reserve(n)?;}Ok(())})}fn allocation_failed(&self){self.perform(|c|Err(c.allocation_failed()));}}

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

/// SAME checked String-growth primitive used by operation-local DATA builders.
pub fn append<C:Control>(control:&mut C,text:&mut String,value:&str)->Result<(),C::Error>{
 if !C::CHECKED{text.push_str(value);return Ok(())}
 let need=text.len().checked_add(value.len()).ok_or_else(||control.overflow())?;
 if need>text.capacity(){let cap=need.max(text.capacity().saturating_mul(2)).max(64);reserve(control,||cap.checked_add(64))?;text.try_reserve_exact(cap-text.len()).map_err(|_|control.allocation_failed())?;}
 text.push_str(value);Ok(())
}

/// Same checked control and a borrowed same-Db pattern loan. All owned capture
/// rows are admitted on this actual control before the provider lends slots.
pub fn captures_static<'h,C:Control>(c:&mut C,pattern:&'static str,text:&'h str,start:usize,legacy:fn()->&'static crate::pat::Pat)->Result<Option<crate::pat::Caps<'h>>,C::Error>{captures_static_mode(c,pattern,text,start,false,legacy)}
pub fn captures_match_static<'h,C:Control>(c:&mut C,pattern:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Result<Option<crate::pat::Caps<'h>>,C::Error>{captures_static_mode(c,pattern,text,0,true,legacy)}
fn captures_static_mode<'h,C:Control>(c:&mut C,pattern:&str,text:&'h str,start:usize,anchored:bool,legacy:fn()->&'static crate::pat::Pat)->Result<Option<crate::pat::Caps<'h>>,C::Error>{
 #[cfg(feature="native-policy")]
 if c.native_patterns().is_some(){
  let spec=crate::native_pattern::Spec{pattern,mode:if anchored{crate::native_pattern::Mode::Match}else{crate::native_pattern::Mode::Search}};
  c.checkpoint()?;
  let count_result=c.native_patterns().unwrap().capture_len(spec);
  let count=count_result.map_err(|actual|c.native_pattern_failed(actual))?;
  reserve(c,||count.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(64))?;
  let mut groups=Vec::new();groups.try_reserve_exact(count).map_err(|_|c.allocation_failed())?;
  if groups.capacity()>count{return Err(c.allocation_failed())}
  let result=c.native_patterns().unwrap().capture(spec,text,start,&mut|actual|{
   if actual.len()>groups.capacity(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual pattern capture roster exceeds its preadmitted same-program extent"))}
   groups.extend_from_slice(actual);Ok(())
  });
  let found=result.map_err(|actual|c.native_pattern_failed(actual))?;
  c.checkpoint()?;return Ok(found.then_some(crate::pat::Caps{hay:text,groups}))
 }
 let _=(pattern,anchored);let actual=legacy();reserve(c,||actual.capture_group_count().checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;Ok(actual.captures_at(text,start))
}
pub fn find_static<'h,C:Control>(c:&mut C,pattern:&'static str,text:&'h str,start:usize,legacy:fn()->&'static crate::pat::Pat)->Result<Option<crate::pat::M<'h>>,C::Error>{find_static_mode(c,pattern,text,start,false,legacy)}
fn find_static_mode<'h,C:Control>(c:&mut C,pattern:&'static str,text:&'h str,start:usize,anchored:bool,legacy:fn()->&'static crate::pat::Pat)->Result<Option<crate::pat::M<'h>>,C::Error>{
 #[cfg(feature="native-policy")]
 if c.native_patterns().is_some(){
  c.checkpoint()?;let mut bounds=None;
  let spec=crate::native_pattern::Spec{pattern,mode:if anchored{crate::native_pattern::Mode::Match}else{crate::native_pattern::Mode::Search}};
  let result=c.native_patterns().unwrap().find(spec,text,start,&mut|actual|{bounds=Some(actual);Ok(())});
  result.map_err(|actual|c.native_pattern_failed(actual))?;c.checkpoint()?;
  return Ok(bounds.map(|(start,end)|crate::pat::M{hay:text,start,end}))
 }
 let _=(pattern,anchored);Ok(legacy().find_at(text,start))
}
pub fn is_match_static<C:Control>(c:&mut C,pattern:&'static str,text:&str,legacy:fn()->&'static crate::pat::Pat)->Result<bool,C::Error>{Ok(find_static(c,pattern,text,0,legacy)?.is_some())}
pub fn is_match_match_static<C:Control>(c:&mut C,pattern:&'static str,text:&str,legacy:fn()->&'static crate::pat::Pat)->Result<bool,C::Error>{Ok(find_static_mode(c,pattern,text,0,true,legacy)?.is_some())}
pub fn replace_static<C:Control>(c:&mut C,pattern:&'static str,text:&str,replacement:&str,legacy:fn()->&'static crate::pat::Pat)->Result<String,C::Error>{
 #[cfg(feature="native-policy")]
 if c.native_patterns().is_some(){
  let mut out=String::new();let(mut pos,mut last)=(0,0);
  while pos<=text.len(){let Some(row)=find_static(c,pattern,text,pos,legacy)? else{break};
   append(c,&mut out,&text[last..row.start])?;append(c,&mut out,replacement)?;last=row.end;
   pos=if row.start==row.end{row.end+text[row.end..].chars().next().map_or(1,char::len_utf8)}else{row.end};
  }append(c,&mut out,&text[last..])?;return Ok(out)
 }
 let _=pattern;legacy().replace_all_using(text,replacement,c)
}

/// SAME Pat nonoverlapping UTF-8 progression, with each exposed row and group
/// vector admitted before construction under the existing operation control.
pub fn captures_all_static<'h,C:Control>(c:&mut C,pattern:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Result<Vec<crate::pat::Caps<'h>>,C::Error>{
 #[cfg(feature="native-policy")]if c.native_patterns().is_some(){
  let(mut pos,mut rows)=(0,Vec::new());while pos<=text.len(){
   let Some(actual)=captures_static(c,pattern,text,pos,legacy)?else{break};let(start,end)=actual.groups[0].expect("real regex whole group");
   pos=if start==end{end+text[end..].chars().next().map_or(1,char::len_utf8)}else{end};row(c,&mut rows)?;rows.push(actual);
  }return Ok(rows)
 }
 let _=pattern;Ok(legacy().captures_iter(text))
}
pub fn find_all_static<'h,C:Control>(c:&mut C,pattern:&'static str,text:&'h str,legacy:fn()->&'static crate::pat::Pat)->Result<Vec<crate::pat::M<'h>>,C::Error>{
 #[cfg(feature="native-policy")]if c.native_patterns().is_some(){
  let(mut pos,mut rows)=(0,Vec::new());while pos<=text.len(){let Some(actual)=find_static(c,pattern,text,pos,legacy)?else{break};
   pos=if actual.start==actual.end{actual.end+text[actual.end..].chars().next().map_or(1,char::len_utf8)}else{actual.end};row(c,&mut rows)?;rows.push(actual);
  }return Ok(rows)
 }
 let _=pattern;Ok(legacy().find_iter(text))
}

/// Dynamic source recipe remains DATA. The actual provider owns program and
/// execution scratch; this native-only question has no compatibility fallback.
#[cfg(feature="native-policy")]
pub fn captures_recipe<'h,C:Control>(c:&mut C,pattern:&str,text:&'h str,start:usize)->Result<Option<crate::pat::Caps<'h>>,C::Error>{
 if c.native_patterns().is_none(){return Err(c.native_pattern_failed(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native pattern recipe requires its actual scoped provider")))}
 captures_static_mode(c,pattern,text,start,false,||panic!("native recipe cannot compile a private compatibility program"))
}

/// Existing pinned regex-syntax escape_into writes into caller-preadmitted
/// storage. At most one ASCII slash is added per input byte; no engine/cache.
#[cfg(feature="native-policy")]
pub fn escape_native<C:Control>(c:&mut C,text:&str)->Result<String,C::Error>{
 let bound=text.len().checked_mul(2).ok_or_else(||c.overflow())?;reserve(c,||bound.checked_add(64))?;let mut out=String::new();out.try_reserve_exact(bound).map_err(|_|c.allocation_failed())?;if out.capacity()>bound{return Err(c.allocation_failed())}regex_syntax::escape_into(text,&mut out);Ok(out)
}

/// Preserve the original streaming admit/capture/visitor chronology. No later
/// match is requested before the current visitor has completed successfully.
pub fn try_for_each_capture_static<'h,C:Control>(source:&'static str,legacy:fn()->&'static crate::pat::Pat,text:&'h str,c:&mut C,admit:impl FnMut(&mut C,usize)->Result<(),C::Error>,visit:impl FnMut(&mut C,crate::pat::Caps<'h>)->Result<(),C::Error>)->Result<(),C::Error>{try_for_each_capture_static_mode(source,legacy,text,c,false,admit,visit)}
pub fn try_for_each_capture_match_static<'h,C:Control>(source:&'static str,legacy:fn()->&'static crate::pat::Pat,text:&'h str,c:&mut C,admit:impl FnMut(&mut C,usize)->Result<(),C::Error>,visit:impl FnMut(&mut C,crate::pat::Caps<'h>)->Result<(),C::Error>)->Result<(),C::Error>{try_for_each_capture_static_mode(source,legacy,text,c,true,admit,visit)}
fn try_for_each_capture_static_mode<'h,C:Control>(source:&'static str,legacy:fn()->&'static crate::pat::Pat,text:&'h str,c:&mut C,anchored:bool,mut admit:impl FnMut(&mut C,usize)->Result<(),C::Error>,mut visit:impl FnMut(&mut C,crate::pat::Caps<'h>)->Result<(),C::Error>)->Result<(),C::Error>{
 let mut at=0;while at<=text.len(){
  let count={#[cfg(feature="native-policy")]{if let Some(provider)=c.native_patterns(){let pending=provider.capture_len(crate::native_pattern::Spec{pattern:source,mode:if anchored{crate::native_pattern::Mode::Match}else{crate::native_pattern::Mode::Search}});pending.map_err(|actual|c.native_pattern_failed(actual))?}else{legacy().capture_group_count()}}#[cfg(not(feature="native-policy"))]{legacy().capture_group_count()}};
  admit(c,count)?;let Some(found)=captures_static_mode(c,source,text,at,anchored,legacy)?else{break};let(start,end)=found.groups[0].expect("actual regex has whole capture");at=if start==end{end.checked_add(text[end..].chars().next().map_or(1,char::len_utf8)).ok_or_else(||c.overflow())?}else{end};visit(c,found)?;
 }Ok(())
}

/// Actual same-image program width; no private native constructor or source role.
pub fn capture_len_static<C:Control>(c:&mut C,source:&'static str,mode:bool,legacy:fn()->&'static crate::pat::Pat)->Result<usize,C::Error>{
 #[cfg(feature="native-policy")]if c.native_patterns().is_some(){let pending=c.native_patterns().unwrap().capture_len(crate::native_pattern::Spec{pattern:source,mode:if mode{crate::native_pattern::Mode::Match}else{crate::native_pattern::Mode::Search}});return pending.map_err(|actual|c.native_pattern_failed(actual))}
 let _=(source,mode);Ok(legacy().capture_group_count())
}
