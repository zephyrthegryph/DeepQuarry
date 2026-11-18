//! Fixture DATA over the existing source-view and finding-storage admission.
//! This does not grant source authority or bound opaque regex/compiler heaps.
use crate::{lint::Sink, tree::SourceFile};
use std::ops::Deref;

pub struct Fixture<'a> {
    #[cfg(feature="native-policy")]
    native: Option<Native<'a>>,
    _lifetime: std::marker::PhantomData<&'a ()>,
}
#[cfg(feature="native-policy")]
struct Native<'a> {
    budget: &'a std::sync::Arc<crate::captured_generator_budget::Budget>,
    poll: &'a dyn Fn()->std::io::Result<()>,
    first: std::sync::Mutex<Option<std::io::Error>>,
    scan_error:std::cell::RefCell<Option<String>>,
    patterns:Option<&'a dyn crate::native_pattern::Provider>,
    views: std::cell::RefCell<Vec<crate::tree::CapturedViewStatus>>,
}
/// Own the actual file until its final view-error check. No cloned source,
/// escaped view, retained cache entry or silent empty-view success is made.
pub struct File<'s,'a> { actual: SourceFile, _fixture: &'s Fixture<'a> }
impl Deref for File<'_,'_> { type Target=SourceFile; fn deref(&self)->&SourceFile{&self.actual} }
impl Drop for File<'_,'_> {
    fn drop(&mut self){
        #[cfg(feature="native-policy")]
        if self._fixture.native.is_some(){if let Err(message)=self.actual.require_view_budget(){self._fixture.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message));}}
    }
}
impl<'a> Fixture<'a> {
    pub fn legacy()->Self{Self{
        #[cfg(feature="native-policy")]native:None,
        _lifetime:std::marker::PhantomData,
    }}
    #[cfg(feature="native-policy")]
    pub(crate) fn native(budget:&'a std::sync::Arc<crate::captured_generator_budget::Budget>,poll:&'a dyn Fn()->std::io::Result<()>)->Self{
        Self{native:Some(Native{budget,poll,patterns:None,first:std::sync::Mutex::new(None),scan_error:std::cell::RefCell::new(None),views:std::cell::RefCell::new(Vec::new())}),_lifetime:std::marker::PhantomData}
    }
    #[cfg(feature="native-policy")]
    pub(crate) fn native_patterns(budget:&'a std::sync::Arc<crate::captured_generator_budget::Budget>,poll:&'a dyn Fn()->std::io::Result<()>,patterns:&'a dyn crate::native_pattern::Provider)->Self{
        let mut actual=Self::native(budget,poll);actual.native.as_mut().unwrap().patterns=Some(patterns);actual
    }
    /// Same actual reader budget and borrowed provider; no new allowance,
    /// source role, model, cache or callback result owner is created here.
    #[cfg(feature="native-policy")]
    pub(crate) fn scanned(budget:&'a std::sync::Arc<crate::captured_generator_budget::Budget>,poll:&'a dyn Fn()->std::io::Result<()>,patterns:&'a dyn crate::native_pattern::Provider,file:&SourceFile)->Result<Self,crate::derived_selftest_policy::Failure>{
        let actual=Self::native_patterns(budget,poll,patterns);
        let status=file.captured_view_status().ok_or_else(||crate::derived_selftest_policy::Failure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"source scan requires its actual captured view status")))?;
        status.require().map_err(|message|crate::derived_selftest_policy::Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;
        actual.checkpoint().map_err(|_|crate::derived_selftest_policy::Failure::Operational(actual.native.as_ref().unwrap().first.lock().unwrap_or_else(|error|error.into_inner()).take().expect("actual checkpoint retained first IO")))?;
        let native=actual.native.as_ref().unwrap();
        native.budget.charge(4*std::mem::size_of::<crate::tree::CapturedViewStatus>()+64).map_err(|message|crate::derived_selftest_policy::Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;
        native.views.borrow_mut().try_reserve_exact(4).map_err(|_|crate::derived_selftest_policy::Failure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;
        if native.views.borrow().capacity()>4{return Err(crate::derived_selftest_policy::Failure::Operational(std::io::ErrorKind::OutOfMemory.into()))}
        native.views.borrow_mut().push(status);
        Ok(actual)
    }
    #[cfg(feature="native-policy")]
    pub(crate) fn scan_budget(&self)->&std::sync::Arc<crate::captured_generator_budget::Budget>{self.native.as_ref().expect("actual scoped scan").budget}
    /// An infallible legacy scan port can record its actual checked-kernel
    /// failure without converting an operational error into an empty result.
    pub(crate) fn note_scan(&self,result:Result<(),String>){
        #[cfg(feature="native-policy")]
        if let Some(native)=&self.native{if let Err(message)=result{native.scan_error.borrow_mut().get_or_insert(message);}return}
        result.expect("legacy scan has no allocation refusal");
    }
    #[cfg(feature="native-policy")]
    pub(crate) fn note_scan_admission(&self,message:String){self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message));}
    #[cfg(feature="native-policy")]
    pub(crate) fn finish_scan(&self)->Result<(),crate::derived_selftest_policy::Failure>{
        use crate::derived_selftest_policy::Failure;
        let native=self.native.as_ref().expect("only actual scoped scan can finish native resources");
        if let Some(first)=native.first.lock().unwrap_or_else(|error|error.into_inner()).take(){return Err(Failure::Operational(first))}
        if self.checkpoint().is_err(){return Err(Failure::Operational(native.first.lock().unwrap_or_else(|error|error.into_inner()).take().expect("actual checkpoint retains its first IO")))}
        if let Some(message)=native.scan_error.borrow_mut().take(){return Err(Failure::Assertion(message))}Ok(())
    }
    #[cfg(feature="native-policy")]
    fn fail(&self,actual:std::io::Error)->String{
        if let Some(native)=&self.native{native.first.lock().unwrap_or_else(|error|error.into_inner()).get_or_insert(actual);}
        "native fixture operation failed; original error retained".into()
    }
    #[cfg(feature="native-policy")]
    fn checkpoint(&self)->Result<(),String>{
        let Some(native)=&self.native else{return Ok(())};
        if native.first.lock().unwrap_or_else(|error|error.into_inner()).is_some(){return Err("native fixture already failed".into())}
        // Observe local source-view denial at its real chronological boundary,
        // before a later allocation or cancellation checkpoint can run.
        for view in native.views.borrow().iter(){
            view.require().map_err(|m|self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
        }
        // Budget denial is sticky and precedes any later callback checkpoint.
        native.budget.require().map_err(|m|self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
        (native.poll)().map_err(|e|self.fail(e))
    }
    pub fn file<'s>(&'s self,rel:&str,text:&str)->Result<File<'s,'a>,String>{
        #[cfg(feature="native-policy")]
        if let Some(native)=&self.native{
            self.checkpoint()?;
            // This is an ENFORCED finite sublimit, not a claim that estimating
            // source length accounts for arbitrary policy/regex allocations.
            // The existing captured-view builder admits its real allocations
            // under this paid window and refuses any capacity exceeding it.
            let path=std::path::Path::new(rel);
            let limit=SourceFile::raw_policy_view_extra_bound(rel,path,text)
                .and_then(|n|n.checked_add(SourceFile::raw_policy_clean_bound(text)?))
                .and_then(|n|n.checked_add(text.len().checked_mul(4)?))
                .and_then(|n|n.checked_add(8192))
                .ok_or_else(||self.fail(std::io::Error::from(std::io::ErrorKind::OutOfMemory)))?;
            native.budget.charge(limit).map_err(|m|self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
            // Keep original universal-newline semantics. Admission precedes the
            // owned copy/normalization and the existing SourceText conversion.
            let owned=crate::util::universal_newlines(text.to_owned());
            let actual=SourceFile::from_shared_budgeted(rel,path.to_path_buf(),owned.into(),limit)
                .map_err(|m|self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
            let status=actual.captured_view_status().ok_or_else(||self.fail(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual fixture source has no captured-view budget")))?;
            let (length,capacity)={let held=native.views.borrow();(held.len(),held.capacity())};
            if length==capacity{
                let next=capacity.checked_mul(2).map(|n|n.max(4)).ok_or_else(||self.fail(std::io::Error::from(std::io::ErrorKind::OutOfMemory)))?;
                let bytes=next.checked_mul(std::mem::size_of::<crate::tree::CapturedViewStatus>()).and_then(|n|n.checked_add(64)).ok_or_else(||self.fail(std::io::Error::from(std::io::ErrorKind::OutOfMemory)))?;
                native.budget.charge(bytes).map_err(|m|self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;
                native.views.borrow_mut().try_reserve_exact(next-length).map_err(|_|self.fail(std::io::Error::from(std::io::ErrorKind::OutOfMemory)))?;
                if native.views.borrow().capacity()>next{return Err(self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"view-status capacity exceeds prior admission")))}
            }
            native.views.borrow_mut().push(status);
            return Ok(File{actual,_fixture:self});
        }
        Ok(File{actual:SourceFile::from_text(rel,text),_fixture:self})
    }
    /// Closed image metadata must still match its actual source table before
    /// an admitted literal can substitute for an old lazy formatted pattern.
    pub fn require_pattern_binding(&self,actual:bool)->Result<(),String>{
        #[cfg(feature="native-policy")]
        if self.native.as_ref().is_some_and(|native|native.patterns.is_some()){self.checkpoint()?;if !actual{return Err(self.fail(std::io::Error::new(std::io::ErrorKind::InvalidData,"native static pattern differs from its actual image table")))}}
        let _=actual;Ok(())
    }
    pub fn sink(&self)->Result<Sink<'_>,String>{
        #[cfg(feature="native-policy")]
        if let Some(native)=&self.native{
            self.checkpoint()?;
            return Sink::bounded_budget(native.budget).map(|sink|sink.with_pattern_loan(self.sink_pattern_loan()))
                .map_err(|m|self.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)));
        }
        Ok(Sink::new())
    }
    #[cfg(feature="native-policy")]
    pub(crate) fn finish(&self,actual:Result<String,String>)->Result<String,crate::derived_selftest_policy::Failure>{
        use crate::derived_selftest_policy::Failure;
        let native=self.native.as_ref().expect("only native adapter finishes a resource loan");
        if let Some(first)=native.first.lock().unwrap_or_else(|error|error.into_inner()).take(){return Err(Failure::Operational(first))}
        if self.checkpoint().is_err(){return Err(Failure::Operational(native.first.lock().unwrap_or_else(|error|error.into_inner()).take().expect("native checkpoint retains its actual first error")))}
        // The caller's actual catalog window remains live while adopting this
        // result. This is no independently escaping/unfunded host message API.
        match actual{
            Ok(message)=>{native.budget.charge(message.capacity()).map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;Ok(message)},
            Err(message)=>{native.budget.charge(message.capacity()).map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;Err(Failure::Assertion(message))},
        }
    }
}

#[cfg(feature="native-policy")]
struct Allocation<'s,'a>(&'s Fixture<'a>);
#[cfg(feature="native-policy")]
impl crate::key_policy_control::Control for Allocation<'_,'_>{
 #[cfg(feature="native-policy")]fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{self.0.native.as_ref().and_then(|native|native.patterns)}
 #[cfg(feature="native-policy")]fn native_pattern_failed(&mut self,actual:std::io::Error)->String{self.0.fail(actual)}

 type Error=String;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),String>{self.0.checkpoint()}
 fn reserve(&mut self,bytes:usize)->Result<(),String>{let native=self.0.native.as_ref().expect("native allocation loan");native.budget.charge(bytes).map_err(|m|self.0.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))}
 fn overflow(&mut self)->String{self.0.fail(std::io::Error::from(std::io::ErrorKind::OutOfMemory))}
 fn allocation_failed(&mut self)->String{self.0.fail(std::io::Error::from(std::io::ErrorKind::OutOfMemory))}
}
impl Fixture<'_>{
 pub fn check(&self)->Result<(),String>{
  #[cfg(feature="native-policy")]return self.checkpoint();
  #[cfg(not(feature="native-policy"))]Ok(())
 }
 pub fn push<T>(&self,rows:&mut Vec<T>,value:T)->Result<(),String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){crate::key_policy_control::row(&mut Allocation(self),rows)?;}
  rows.push(value);Ok(())
 }
 pub fn collect<T>(&self,items:impl IntoIterator<Item=T>)->Result<Vec<T>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){let mut rows=Vec::new();for value in items{self.push(&mut rows,value)?;}return Ok(rows)}
  Ok(items.into_iter().collect())
 }
 pub fn own(&self,value:&str)->Result<String,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::key_policy_control::own(&mut Allocation(self),value)}
  Ok(value.to_owned())
 }
 pub fn detail(&self,args:std::fmt::Arguments<'_>)->Result<String,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::key_policy_control::format(&mut Allocation(self),args)}
  Ok(std::fmt::format(args))
 }
 pub fn join(&self,rows:&[&str],separator:&str)->Result<String,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){
   struct Joined<'a>{rows:&'a [&'a str],separator:&'a str}
   impl std::fmt::Display for Joined<'_>{fn fmt(&self,out:&mut std::fmt::Formatter<'_>)->std::fmt::Result{for(i,row)in self.rows.iter().enumerate(){if i!=0{out.write_str(self.separator)?;}out.write_str(row)?;}Ok(())}}
   return self.detail(format_args!("{}",Joined{rows,separator}));
  }
  Ok(rows.join(separator))
 }
 pub fn map_insert<V>(&self,rows:&mut crate::scopes::ScopeMap<V>,key:String,value:V)->Result<Option<V>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return rows.insert_using(key,value,&mut Allocation(self))}
  Ok(rows.insert(key,value))
 }
 pub fn captures<'h,P:PatternApi+?Sized>(&self,pattern:&P,text:&'h str)->Result<Option<crate::pat::Caps<'h>>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){crate::key_policy_control::reserve(&mut Allocation(self),||pattern.capture_group_count().checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;}
  Ok(pattern.captures(text))
 }
 pub fn captures_iter<'h,P:PatternApi+?Sized>(&self,pattern:&P,text:&'h str)->Result<Vec<crate::pat::Caps<'h>>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){
   let mut rows=Vec::new();
   pattern.try_for_each_capture(text,&mut rows,
    |_,groups|crate::key_policy_control::reserve(&mut Allocation(self),||groups.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128)),
    |rows,capture|self.push(rows,capture))?;
   return Ok(rows);
  }
  Ok(pattern.captures_iter(text))
 }
 pub fn find_iter<'h,P:PatternApi+?Sized>(&self,pattern:&P,text:&'h str)->Result<Vec<crate::pat::M<'h>>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){let mut rows=Vec::new();pattern.try_for_each_match(text,&mut rows,|_|self.check(),|rows,value|self.push(rows,value))?;return Ok(rows)}
  Ok(pattern.find_iter(text))
 }
 pub fn lower(&self,value:&str)->Result<String,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){crate::key_policy_control::reserve(&mut Allocation(self),||value.len().checked_mul(6)?.checked_add(64))?;}
  Ok(value.to_lowercase())
 }
 pub fn args(&self,text:&str,open:usize)->Result<Option<Vec<String>>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::dm::dx::call_args_using(text,open,&mut Allocation(self))}
  Ok(crate::dm::dx::call_args(text,open))
 }
 pub fn cap_facts(&self,file:&SourceFile,writers:&[String],exempt:&[String])->Result<crate::raw_tree_cap_bits_policy::Facts,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::raw_tree_cap_bits_policy::facts_of_using(file,writers,exempt,&mut Allocation(self),&mut Allocation(self))}
  Ok(crate::raw_tree_cap_bits_policy::facts_of(file,writers,exempt))
 }
 pub fn cap_assemble<'p>(&self,pairs:impl IntoIterator<Item=(&'p str,&'p crate::raw_tree_cap_bits_policy::Facts)>,registry:&[String],out:&mut Sink)->Result<(),String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::raw_tree_cap_bits_policy::assemble_using(pairs,registry,out,&mut Allocation(self))}
  crate::raw_tree_cap_bits_policy::assemble(pairs,registry,out);Ok(())
 }
 pub fn procs(&self,file:&SourceFile)->Result<Vec<crate::dm::dx::Proc>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::dm::dx::procs_in_using(file,&mut Allocation(self))}
  Ok(crate::dm::dx::procs_in(file))
 }
 pub fn site(&self,out:&mut Sink,rule:&str,line:usize)->Result<(),String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){crate::key_policy_control::reserve(&mut Allocation(self),||rule.len().checked_add(out.cur.len())?.checked_mul(4)?.checked_add(256))?;}
  out.site(rule,line);Ok(())
 }
 pub fn set_insert<K:Eq+std::hash::Hash>(&self,rows:&mut std::collections::HashSet<K>,value:K)->Result<(),String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){self.check()?;if !rows.contains(&value){crate::key_policy_control::set_room(&mut Allocation(self),rows)?;}}
  rows.insert(value);Ok(())
 }
 pub fn sort_ord<T:Ord>(&self,rows:&mut [T])->Result<(),String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::key_policy_control::sort_data(rows,&mut|a,b|{self.check()?;Ok(a.cmp(b))})}
  rows.sort();Ok(())
 }
 pub fn stable_by_key<T,K:Ord>(&self,mut rows:Vec<T>,mut key:impl FnMut(&T)->K)->Result<Vec<T>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){
   let mut decorated=self.collect(rows.into_iter().enumerate())?;
   crate::key_policy_control::sort_data(&mut decorated,&mut|a,b|{self.check()?;Ok::<_,String>(key(&a.1).cmp(&key(&b.1)).then(a.0.cmp(&b.0)))})?;
   return self.collect(decorated.into_iter().map(|(_,value)|value));
  }
  rows.sort_by_key(key);Ok(rows)
 }
 pub fn pick_arg(&self,args:&[String],index:Option<usize>,name:&str)->Result<Option<String>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::dm::dx::pick_arg_using(args,index,name,&mut Allocation(self))}
  Ok(crate::dm::dx::pick_arg(args,index,name))
 }
 pub fn arg_spans(&self,text:&str,open:usize)->Result<Option<Vec<(usize,usize)>>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::dm::dx::call_arg_spans_using(text,open,&mut Allocation(self))}
  Ok(crate::dm::dx::call_arg_spans(text,open))
 }
}

#[cfg(all(test,feature="native-policy"))]
mod controls {
    use super::*;
    use crate::{captured_generator_budget::Budget,derived_selftest_policy::Failure};
    #[test]fn actual_fixture_source_views_are_funded_normalized_and_refund_the_same_parent(){
        let parent=Budget::new(8*1024*1024).unwrap();let before=parent.used();
        {
            let scratch=Budget::scoped_temporaries(&parent).unwrap();
            let fixture=Fixture::native(&scratch,&||Ok(()));
            for text in ["/datum/x\r\n\tvar/a = 1\r",&"// large fixture\r\n".repeat(4096)]{
                let file=fixture.file("code/fixture.dm",text).unwrap();
                assert!(file.is_captured_input());assert!(!file.text().contains('\r'));
                let _=file.clean();let _=file.code();file.require_view_budget().unwrap();
            }
            fixture.finish(Ok(String::new())).unwrap();
            assert!(parent.used()>before);
        }
        assert_eq!(parent.used(),before+(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()));
    }
    #[test]fn actual_fixture_quota_denies_before_copy_then_first_io_and_recovery_are_real(){
        let tight=Budget::new(1024).unwrap();let fixture=Fixture::native(&tight,&||Ok(()));
        assert!(fixture.file("code/x.dm","x").is_err());
        assert!(matches!(fixture.finish(Ok(String::new())),Err(Failure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));
        let healthy=Budget::new(8*1024*1024).unwrap();let calls=std::cell::Cell::new(0);
        let stop=||{calls.set(calls.get()+1);Err(std::io::Error::from_raw_os_error(1450))};
        let fixture=Fixture::native(&healthy,&stop);assert!(fixture.file("code/x.dm","x").is_err());
        assert!(matches!(fixture.finish(Err("later semantic error".into())),Err(Failure::Operational(e))if e.raw_os_error()==Some(1450)));
        assert_eq!(calls.get(),1);
        let fixture=Fixture::native(&healthy,&||Ok(()));drop(fixture.file("code/x.dm","x").unwrap());fixture.finish(Ok(String::new())).unwrap();
    }
    #[test]fn actual_finding_sink_denial_and_cancel_do_not_publish_an_empty_fixture_pass(){
        let budget=Budget::new(2048).unwrap();let fixture=Fixture::native(&budget,&||Ok(()));
        let mut sink=fixture.sink().unwrap();sink.cur="code/x.dm".into();
        sink.site_msg("rule",1,"x".repeat(8192));drop(sink);
        assert!(matches!(fixture.finish(Ok(String::new())),Err(Failure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));
        let budget=Budget::new(65536).unwrap();let stop=||Err(std::io::Error::from(std::io::ErrorKind::Interrupted));
        let fixture=Fixture::native(&budget,&stop);assert!(fixture.file("x.dm","x").is_err());
        assert!(matches!(fixture.finish(Ok(String::new())),Err(Failure::Operational(e))if e.kind()==std::io::ErrorKind::Interrupted));
    }
}

#[cfg(all(test,feature="native-policy"))]mod checked_container_controls{
 use super::*;
 use crate::{captured_generator_budget::Budget,derived_selftest_policy::Failure};
 #[test]fn actual_local_view_denial_precedes_later_allocation_poll_and_never_becomes_semantic_failure(){
  let budget=Budget::new(8*1024*1024).unwrap();let polls=std::cell::Cell::new(0);
  let later=||{polls.set(polls.get()+1);Err(std::io::Error::from_raw_os_error(1450))};
  let fixture=Fixture::native(&budget,&later);
  let text="x".repeat(10000);let path=std::path::Path::new("code/view.dm");
  let limit=SourceFile::raw_clean_view_extra_bound("code/view.dm",path,&text).unwrap()+text.len()+512;
  budget.charge(limit+4*std::mem::size_of::<crate::tree::CapturedViewStatus>()+64).unwrap();
  let actual=SourceFile::from_shared_budgeted("code/view.dm",path.to_path_buf(),text.into(),limit).unwrap();
  fixture.native.as_ref().unwrap().views.borrow_mut().push(actual.captured_view_status().unwrap());
  let _=actual.clean();assert!(actual.require_view_budget().is_err());
  assert!(fixture.detail(format_args!("later assertion detail")).is_err());
  assert!(matches!(fixture.finish(Err("later semantic failure".into())),Err(Failure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));
  assert_eq!(polls.get(),0,"the later1450 poll must not run past real earlier source-view denial");
 }
 #[test]fn actual_collection_string_scope_and_failure_detail_growth_use_the_same_refundable_owner(){
  let parent=Budget::new(8*1024*1024).unwrap();let before=parent.used();
  {
   let scratch=Budget::scoped_temporaries(&parent).unwrap();let fixture=Fixture::native(&scratch,&||Ok(()));
   let values=fixture.collect((0..1024).map(|n|n as u64)).unwrap();assert_eq!(values.len(),1024);
   let mut scope=crate::scopes::ScopeMap::default();
   fixture.map_insert(&mut scope,fixture.own("writers").unwrap(),fixture.collect([fixture.own("code/test.dm").unwrap()]).unwrap()).unwrap();
   let details=fixture.detail(format_args!("retained failure {:?} {:?}",values,scope)).unwrap();
   assert!(scratch.used()>=values.capacity()*std::mem::size_of::<u64>()+details.capacity());
   assert!(matches!(fixture.finish(Err(details)),Err(Failure::Assertion(_))));
  }
  assert_eq!(parent.used(),before+(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()));
 }
}

#[cfg(all(test,feature="native-policy"))]mod container_boundary_controls{
 use super::*;
 use crate::{captured_generator_budget::Budget,derived_selftest_policy::Failure};
 #[test]fn actual_container_growth_preserves_first_io_then_recovers_and_refunds(){
  let parent=Budget::new(8*1024*1024).unwrap();let before=parent.used();
  {
   let scratch=Budget::scoped_temporaries(&parent).unwrap();
   let calls=std::cell::Cell::new(0);let stop=||{calls.set(calls.get()+1);Err(std::io::Error::from_raw_os_error(1450))};
   let fixture=Fixture::native(&scratch,&stop);let mut rows:Vec<u64>=Vec::new();
   assert!(fixture.push(&mut rows,7).is_err());assert_eq!(rows.capacity(),0);assert_eq!(calls.get(),1);
   assert!(matches!(fixture.finish(Err("later assertion".into())),Err(Failure::Operational(e))if e.raw_os_error()==Some(1450)));
  }
  assert_eq!(parent.used(),before+(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()));
  {
   let scratch=Budget::scoped_temporaries(&parent).unwrap();let fixture=Fixture::native(&scratch,&||Ok(()));
   let rows=fixture.collect((0..16384).map(|n|n as u64)).unwrap();assert_eq!(rows[16383],16383);
   fixture.finish(Ok(String::new())).unwrap();
  }
  assert_eq!(parent.used(),before+2*(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()));
 }
 #[test]fn actual_container_quota_denies_before_capacity_and_stable_sort_keeps_tie_order(){
  let budget=Budget::new(512).unwrap();let fixture=Fixture::native(&budget,&||Ok(()));let mut denied:Vec<[u8;1024]>=Vec::new();
  assert!(fixture.push(&mut denied,[0;1024]).is_err());assert_eq!(denied.capacity(),0);
  assert!(matches!(fixture.finish(Ok(String::new())),Err(Failure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));
  let budget=Budget::new(65536).unwrap();let fixture=Fixture::native(&budget,&||Ok(()));
  let rows=fixture.collect([(2,0),(1,1),(2,2),(1,3)]).unwrap();let rows=fixture.stable_by_key(rows,|r|r.0).unwrap();
  assert_eq!(rows,[(1,1),(1,3),(2,0),(2,2)]);fixture.finish(Ok(String::new())).unwrap();
 }
}

#[derive(Clone,Copy)]pub enum PatternMode{Search,Match,Full}
impl Fixture<'_>{
 #[cfg(feature="native-policy")]
 fn capture_spec(&self,pattern:&str,mode:PatternMode,text:&str,start:usize,visit:&mut dyn FnMut(&[Option<(usize,usize)>])->std::io::Result<()>)->Result<bool,String>{
  self.checkpoint()?;let native=self.native.as_ref().expect("native-only capture port");
  let provider=native.patterns.ok_or_else(||self.fail(std::io::Error::new(std::io::ErrorKind::NotConnected,"native pattern requires its actual same-Db provider")))?;
  let mode=match mode{PatternMode::Search=>crate::native_pattern::Mode::Search,PatternMode::Match=>crate::native_pattern::Mode::Match,PatternMode::Full=>crate::native_pattern::Mode::Full};
  provider.capture(crate::native_pattern::Spec{pattern,mode},text,start,visit).map_err(|actual|self.fail(actual))
 }
 #[cfg(feature="native-policy")]
 fn find_spec(&self,pattern:&str,mode:PatternMode,text:&str,start:usize)->Result<Option<(usize,usize)>,String>{
  self.checkpoint()?;let native=self.native.as_ref().expect("native-only find port");
  let provider=native.patterns.ok_or_else(||self.fail(std::io::Error::new(std::io::ErrorKind::NotConnected,"native find requires its actual same-Db provider")))?;
  let mode=match mode{PatternMode::Search=>crate::native_pattern::Mode::Search,PatternMode::Match=>crate::native_pattern::Mode::Match,PatternMode::Full=>crate::native_pattern::Mode::Full};
  let mut bounds=None;provider.find(crate::native_pattern::Spec{pattern,mode},text,start,&mut|actual|{bounds=Some(actual);Ok(())}).map_err(|actual|self.fail(actual))?;Ok(bounds)
 }
 pub fn captures_spec<'h,'p>(&self,pattern:&str,mode:PatternMode,text:&'h str,legacy:impl FnOnce()->&'p crate::pat::Pat)->Result<Option<crate::pat::Caps<'h>>,String>{
  #[cfg(feature="native-policy")]if self.native.as_ref().is_some_and(|native|native.patterns.is_some()){
   let mut result=None;self.capture_spec(pattern,mode,text,0,&mut|actual|{
    let groups=self.collect(actual.iter().copied()).map_err(std::io::Error::other)?;
    result=Some(crate::pat::Caps{hay:text,groups});Ok(())
   })?;return Ok(result)
  }let _=(pattern,mode);Ok(legacy().captures(text))
 }
 pub fn captures_iter_spec<'h,'p>(&self,pattern:&str,mode:PatternMode,text:&'h str,legacy:impl FnOnce()->&'p crate::pat::Pat)->Result<Vec<crate::pat::Caps<'h>>,String>{
  #[cfg(feature="native-policy")]if self.native.as_ref().is_some_and(|native|native.patterns.is_some()){
   let mut out=Vec::new();let mut pos=0;
   while pos<=text.len(){let mut bounds=None;
    let found=self.capture_spec(pattern,mode,text,pos,&mut|actual|{
     bounds=actual.first().copied().flatten();
     let groups=self.collect(actual.iter().copied()).map_err(std::io::Error::other)?;
     self.push(&mut out,crate::pat::Caps{hay:text,groups}).map_err(std::io::Error::other)?;Ok(())
    })?;
    if !found{break}let(start,end)=bounds.ok_or_else(||self.fail(std::io::Error::new(std::io::ErrorKind::InvalidData,"native pattern lacks actual whole capture")))?;
    pos=if end==start{end.checked_add(text[end..].chars().next().map_or(1,char::len_utf8)).ok_or_else(||self.fail(std::io::ErrorKind::OutOfMemory.into()))?}else{end};
   }return Ok(out)
  }let _=(pattern,mode);Ok(legacy().captures_iter(text))
 }
 pub fn find_iter_spec<'h,'p>(&self,pattern:&str,mode:PatternMode,text:&'h str,legacy:impl FnOnce()->&'p crate::pat::Pat)->Result<Vec<crate::pat::M<'h>>,String>{
  #[cfg(feature="native-policy")]if self.native.as_ref().is_some_and(|native|native.patterns.is_some()){
   let mut out=Vec::new();let mut pos=0;
   while pos<=text.len(){
    let Some((start,end))=self.find_spec(pattern,mode,text,pos)? else{break};
    self.push(&mut out,crate::pat::M{hay:text,start,end})?;
    pos=if end==start{end.checked_add(text[end..].chars().next().map_or(1,char::len_utf8)).ok_or_else(||self.fail(std::io::ErrorKind::OutOfMemory.into()))?}else{end};
   }return Ok(out)
  }let _=(pattern,mode);Ok(legacy().find_iter(text))
 }
}

/// Literal DATA plus an unevaluated original constructor. The native path
/// never calls this constructor or publishes a process-static program.
pub struct Pattern<'f,'a>{fixture:&'f Fixture<'a>,literal:std::borrow::Cow<'f,str>,mode:PatternMode,legacy:fn()->&'static crate::pat::Pat}
impl<'a> Fixture<'a>{
 pub fn pattern<'f>(&'f self,literal:&'static str,mode:PatternMode,legacy:fn()->&'static crate::pat::Pat)->Pattern<'f,'a>{Pattern{fixture:self,literal:std::borrow::Cow::Borrowed(literal),mode,legacy}}
}
/// Existing matching progression, shared by original Pat and admitted handles.
/// Native handle failures latch their actual first IO in the enclosing Fixture;
/// finish() refuses before any semantic success can be published.
pub trait PatternApi{
 fn capture_group_count(&self)->usize;
 fn captures_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::Caps<'h>>;
 fn find_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::M<'h>>;
 fn captures<'h>(&self,text:&'h str)->Option<crate::pat::Caps<'h>>{self.captures_at(text,0)}
 fn find<'h>(&self,text:&'h str)->Option<crate::pat::M<'h>>{self.find_at(text,0)}
 fn is_match(&self,text:&str)->bool{self.find(text).is_some()}
 fn try_for_each_capture<'h,S,E>(&self,text:&'h str,state:&mut S,mut admit:impl FnMut(&mut S,usize)->Result<(),E>,mut visit:impl FnMut(&mut S,crate::pat::Caps<'h>)->Result<(),E>)->Result<(),E>{
  let mut pos=0;while pos<=text.len(){admit(state,self.capture_group_count())?;let Some(row)=self.captures_at(text,pos) else{break};let(start,end)=row.groups[0].unwrap();pos=if end==start{end+text[end..].chars().next().map_or(1,char::len_utf8)}else{end};visit(state,row)?}Ok(())
 }
 fn try_for_each_match<'h,S,E>(&self,text:&'h str,state:&mut S,mut admit:impl FnMut(&mut S)->Result<(),E>,mut visit:impl FnMut(&mut S,crate::pat::M<'h>)->Result<(),E>)->Result<(),E>{
  let mut pos=0;while pos<=text.len(){admit(state)?;let Some(row)=self.find_at(text,pos) else{break};pos=if row.end==row.start{row.end+text[row.end..].chars().next().map_or(1,char::len_utf8)}else{row.end};visit(state,row)?}Ok(())
 }
 fn captures_iter<'h>(&self,text:&'h str)->Vec<crate::pat::Caps<'h>>;
 fn find_iter<'h>(&self,text:&'h str)->Vec<crate::pat::M<'h>>;
}
impl PatternApi for crate::pat::Pat{
 fn capture_group_count(&self)->usize{self.capture_group_count()}
 fn captures_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::Caps<'h>>{self.captures_at(text,start)}
 fn find_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::M<'h>>{self.find_at(text,start)}
 fn captures_iter<'h>(&self,text:&'h str)->Vec<crate::pat::Caps<'h>>{self.captures_iter(text)}
 fn find_iter<'h>(&self,text:&'h str)->Vec<crate::pat::M<'h>>{self.find_iter(text)}
}
impl<T:PatternApi+?Sized> PatternApi for &T{
 fn capture_group_count(&self)->usize{(**self).capture_group_count()}
 fn captures_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::Caps<'h>>{(**self).captures_at(text,start)}
 fn find_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::M<'h>>{(**self).find_at(text,start)}
 fn captures_iter<'h>(&self,text:&'h str)->Vec<crate::pat::Caps<'h>>{(**self).captures_iter(text)}
 fn find_iter<'h>(&self,text:&'h str)->Vec<crate::pat::M<'h>>{(**self).find_iter(text)}
}
impl PatternApi for Pattern<'_,'_>{
 fn capture_group_count(&self)->usize{
  #[cfg(feature="native-policy")]if let Some(provider)=self.fixture.native.as_ref().and_then(|native|native.patterns){
   if self.fixture.checkpoint().is_err(){return 0}
   let mode=match self.mode{PatternMode::Search=>crate::native_pattern::Mode::Search,PatternMode::Match=>crate::native_pattern::Mode::Match,PatternMode::Full=>crate::native_pattern::Mode::Full};
   return match provider.capture_len(crate::native_pattern::Spec{pattern:&self.literal,mode}){Ok(n)=>n,Err(actual)=>{self.fixture.fail(actual);0}}
  }(self.legacy)().capture_group_count()
 }
 fn captures_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::Caps<'h>>{
  #[cfg(feature="native-policy")]if self.fixture.native.as_ref().is_some_and(|native|native.patterns.is_some()){
   let mut row=None;let result=self.fixture.capture_spec(&self.literal,self.mode,text,start,&mut|actual|{
    let groups=self.fixture.collect(actual.iter().copied()).map_err(std::io::Error::other)?;row=Some(crate::pat::Caps{hay:text,groups});Ok(())
   });return if result.is_ok(){row}else{None}
  }(self.legacy)().captures_at(text,start)
 }
 fn find_at<'h>(&self,text:&'h str,start:usize)->Option<crate::pat::M<'h>>{
  #[cfg(feature="native-policy")]if self.fixture.native.as_ref().is_some_and(|native|native.patterns.is_some()){
   return self.fixture.find_spec(&self.literal,self.mode,text,start).ok().flatten().map(|(start,end)|crate::pat::M{hay:text,start,end})
  }(self.legacy)().find_at(text,start)
 }
 fn captures_iter<'h>(&self,text:&'h str)->Vec<crate::pat::Caps<'h>>{self.fixture.captures_iter_spec(&self.literal,self.mode,text,self.legacy).unwrap_or_default()}
 fn find_iter<'h>(&self,text:&'h str)->Vec<crate::pat::M<'h>>{self.fixture.find_iter_spec(&self.literal,self.mode,text,self.legacy).unwrap_or_default()}
}

#[cfg(all(test,feature="native-policy"))]mod pattern_order_controls{
 use super::*;
 use crate::{captured_generator_budget::Budget,derived_selftest_policy::Failure};
 use std::{io,sync::atomic::{AtomicUsize,Ordering}};
 struct LaterIo(AtomicUsize);
 impl crate::native_pattern::Provider for LaterIo{
  fn find(&self,_:crate::native_pattern::Spec,_:&str,_:usize,_:&mut dyn FnMut((usize,usize))->io::Result<()>)->io::Result<bool>{self.0.fetch_add(1,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}
  fn capture_len(&self,_:crate::native_pattern::Spec)->io::Result<usize>{self.0.fetch_add(1,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}
  fn capture(&self,_:crate::native_pattern::Spec,_:&str,_:usize,_:&mut dyn FnMut(&[Option<(usize,usize)>])->io::Result<()>)->io::Result<bool>{self.0.fetch_add(1,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}
 }
 #[test]fn actual_local_view_denial_precedes_pattern_metadata_io_and_never_initializes_legacy_constructor(){
  let budget=Budget::new(8*1024*1024).unwrap();let provider=LaterIo(AtomicUsize::new(0));
  let fixture=Fixture::native_patterns(&budget,&||Ok(()),&provider);
  let text="x".repeat(10000);let path=std::path::Path::new("code/pattern-view.dm");
  let limit=SourceFile::raw_clean_view_extra_bound("code/pattern-view.dm",path,&text).unwrap()+text.len()+512;
  budget.charge(limit+4*std::mem::size_of::<crate::tree::CapturedViewStatus>()+64).unwrap();
  let file=SourceFile::from_shared_budgeted("code/pattern-view.dm",path.to_path_buf(),text.into(),limit).unwrap();
  fixture.native.as_ref().unwrap().views.borrow_mut().push(file.captured_view_status().unwrap());
  let _=file.clean();assert!(file.require_view_budget().is_err());
  let pattern=fixture.pattern("x",PatternMode::Search,||panic!("native path evaluated legacy constructor"));
  assert_eq!(pattern.capture_group_count(),0);assert!(!pattern.is_match("x"));
  assert_eq!(provider.0.load(Ordering::SeqCst),0,"the later1450 provider must not run past actual earlier view OOM");
  assert!(matches!(fixture.finish(Ok(String::new())),Err(Failure::Operational(actual))if actual.kind()==io::ErrorKind::OutOfMemory));
 }
}

impl Fixture<'_>{
 /// Same literal replacement kernel; any native failure remains in this actual
 /// operation's first-IO latch and cannot become reusable clean findings.
 pub fn replace_static(&self,pattern:&'static str,text:&str,replacement:&str,legacy:fn()->&'static crate::pat::Pat)->Result<String,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::key_policy_control::replace_static(&mut Allocation(self),pattern,text,replacement,legacy)}
  let _=pattern;Ok(legacy().replace_all(text,replacement))
 }
}

#[cfg(feature="native-policy")]
impl<'a> Fixture<'a>{
 /// Only this actual live provider can construct an owned formatted descriptor.
 /// Formatting uses the same checked String kernel before allocation; the
 /// descriptor borrows this fixture until its source String has dropped.
 pub fn formatted_pattern<'f>(&'f self,args:std::fmt::Arguments<'_>,mode:PatternMode)->Result<Pattern<'f,'a>,String>{
  self.checkpoint()?;
  if !self.native.as_ref().is_some_and(|native|native.patterns.is_some()){return Err(self.fail(std::io::Error::new(std::io::ErrorKind::InvalidInput,"formatted native pattern requires its actual scoped provider")))}
  let source=self.detail(args)?;
  Ok(Pattern{fixture:self,literal:std::borrow::Cow::Owned(source),mode,legacy:||panic!("owned native descriptor cannot enter an unissued legacy constructor")})
 }
}

impl Fixture<'_>{
 pub fn cooldown_lines<P:PatternApi>(&self,file:&SourceFile,patterns:&crate::raw_tree_cooldown_policy::Patterns<P>,kept:impl FnMut(usize)->bool)->Result<Vec<u32>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::raw_tree_cooldown_policy::judge_using(file,patterns,kept,&mut Allocation(self))}
  Ok(crate::raw_tree_cooldown_policy::judge(file,patterns,kept))
 }
}

impl Fixture<'_>{
 pub fn declared_input_keys<P:PatternApi>(&self,file:&SourceFile,patterns:&crate::raw_tree_duplicate_input_key_policy::Patterns<P>,visit:impl FnMut(&str,&str,usize))->Result<(),String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){return crate::raw_tree_duplicate_input_key_policy::declared_using(file,patterns,visit,&mut Allocation(self))}
  crate::raw_tree_duplicate_input_key_policy::declared(file,patterns,visit);Ok(())
 }
}

impl Fixture<'_>{
 /// Resource dispatch only; this boolean cannot authorize source or completion.
 pub fn has_native_patterns(&self)->bool{
  #[cfg(feature="native-policy")]return self.native.as_ref().is_some_and(|native|native.patterns.is_some());
  #[cfg(not(feature="native-policy"))]false
 }
 /// The pinned regex-syntax escape_into algorithm, streamed through the
 /// existing admitted formatter before String growth. No opaque builder runs.
 pub fn escape_pattern(&self,value:&str)->Result<String,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){
   struct Escaped<'a>(&'a str);
   impl std::fmt::Display for Escaped<'_>{fn fmt(&self,out:&mut std::fmt::Formatter<'_>)->std::fmt::Result{
    use std::fmt::Write as _;
    for ch in self.0.chars(){if regex_syntax::is_meta_character(ch){out.write_char('\\')?;}out.write_char(ch)?;}Ok(())
   }}
   return self.detail(format_args!("{}",Escaped(value)))
  }
  Ok(regex::escape(value))
 }
}

impl Fixture<'_>{
 pub fn formatted_is_match<'p>(&self,args:std::fmt::Arguments<'_>,text:&str,legacy:impl FnOnce()->&'p crate::pat::Pat)->Result<bool,String>{
  #[cfg(feature="native-policy")]if self.has_native_patterns(){let pattern=self.formatted_pattern(args,PatternMode::Search)?;let actual=pattern.is_match(text);self.check()?;return Ok(actual)}
  let _=args;Ok(legacy().is_match(text))
 }
 pub fn formatted_captures_iter<'h,'p>(&self,args:std::fmt::Arguments<'_>,text:&'h str,legacy:impl FnOnce()->&'p crate::pat::Pat)->Result<Vec<crate::pat::Caps<'h>>,String>{
  #[cfg(feature="native-policy")]if self.has_native_patterns(){let pattern=self.formatted_pattern(args,PatternMode::Search)?;let actual=self.captures_iter(&pattern,text)?;self.check()?;return Ok(actual)}
  let _=args;Ok(legacy().captures_iter(text))
 }
}

impl Fixture<'_>{
 pub fn append(&self,body:&mut String,value:&str)->Result<(),String>{
  #[cfg(feature="native-policy")]if let Some(native)=&self.native{self.checkpoint()?;if !native.budget.string(body,value){return Err(self.fail(std::io::ErrorKind::OutOfMemory.into()))}return Ok(())}
  body.push_str(value);Ok(())
 }
}

impl Fixture<'_>{
 pub fn formatted_any_match<'p>(&self,args:std::fmt::Arguments<'_>,lines:&[String],legacy:impl FnOnce()->&'p crate::pat::Pat)->Result<bool,String>{
  #[cfg(feature="native-policy")]if self.has_native_patterns(){let pattern=self.formatted_pattern(args,PatternMode::Search)?;let actual=lines.iter().any(|line|pattern.is_match(line));self.check()?;return Ok(actual)}
  let _=args;let pattern=legacy();Ok(lines.iter().any(|line|pattern.is_match(line)))
 }
}

#[cfg(feature="native-policy")]
impl Fixture<'_>{
 /// Take only an already-issued native scanner failure. This deliberately does
 /// no new poll: an earlier typed producer failure must precede later cancel.
 pub(crate) fn take_scan_failure(&self)->Option<crate::derived_selftest_policy::Failure>{
  use crate::derived_selftest_policy::Failure;
  let native=self.native.as_ref()?;
  if let Some(actual)=native.first.lock().unwrap_or_else(|error|error.into_inner()).take(){return Some(Failure::Operational(actual))}
  for status in native.views.borrow().iter(){if let Err(message)=status.require(){return Some(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}}
  if let Err(message)=native.budget.require(){return Some(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}
  native.scan_error.borrow_mut().take().map(Failure::Assertion)
 }
}

#[cfg(feature="native-policy")]
impl Fixture<'_>{
 pub(crate) fn sink_pattern_loan(&self)->Option<crate::lint::SinkPatternLoan<'_>>{
  let native=self.native.as_ref()?;Some(crate::lint::SinkPatternLoan{provider:native.patterns?,first:&native.first,budget:native.budget})
 }
}

#[cfg(all(test,feature="native-policy"))]
mod native_sink_pattern_controls{
 use super::*;use crate::{native_pattern::{Provider,Spec},captured_generator_budget::Budget,derived_selftest_policy::Failure};
 use std::{io,sync::atomic::{AtomicUsize,Ordering}};
 struct FirstIo(AtomicUsize);
 impl Provider for FirstIo{
  fn capture_len(&self,_:Spec)->io::Result<usize>{self.0.fetch_add(1,Ordering::SeqCst);Err(io::Error::from_raw_os_error(1450))}
  fn find(&self,_:Spec,_:&str,_:usize,_:&mut dyn FnMut((usize,usize))->io::Result<()>)->io::Result<bool>{panic!("first capture-length error must stop later matching")}
  fn capture(&self,_:Spec,_:&str,_:usize,_:&mut dyn FnMut(&[Option<(usize,usize)>])->io::Result<()>)->io::Result<bool>{panic!("first capture-length error must stop capture")}
 }
 #[test]fn actual_sink_annotation_io_uses_same_fixture_first_error_before_later_cancel(){
  let budget=Budget::new(8*1024*1024).unwrap();let calls=std::cell::Cell::new(0);
  let poll=||{calls.set(calls.get()+1);if calls.get()>2{Err(io::ErrorKind::Interrupted.into())}else{Ok(())}};
  let provider=FirstIo(AtomicUsize::new(0));let fixture=Fixture::native_patterns(&budget,&poll,&provider);
  let file=crate::tree::SourceFile::from_text("code/annotation.dm","work() // ALLOW(scheduler): the original blocking external operation
");
  let mut sink=fixture.sink().unwrap();assert!(sink.allowed(&file,1,"scheduler"));assert!(sink.allowed(&file,1,"scheduler"));
  assert_eq!(provider.0.load(Ordering::SeqCst),1);assert_eq!(calls.get(),1);assert!(sink.allow_used.is_empty());drop(sink);
  assert!(matches!(fixture.finish(Err("later semantic error".into())),Err(Failure::Operational(actual))if actual.raw_os_error()==Some(1450)));assert_eq!(calls.get(),1);
 }
}

impl Fixture<'_>{
 /// Same shared Sys usage trace through the actual operation's pattern/control loan.
 /// Infallible original judges suppress later semantic rows on scanner failure;
 /// their captured caller returns take_scan_failure before any later poll/result.
 pub fn kept_recorded_scan(&self,file:&SourceFile,number:usize,name:&str)->bool{
  #[cfg(feature="native-policy")]if self.native.is_some(){return match crate::dm::sys::kept_recorded_using(file,number,name,&mut Allocation(self)){
   Ok(kept)=>kept,Err(message)=>{self.note_scan(Err(message));true}
  }}
  crate::dm::sys::kept_recorded(file,number,name)
 }
}

impl Fixture<'_>{
 pub fn hash_insert<K:Eq+std::hash::Hash,V>(&self,rows:&mut std::collections::HashMap<K,V>,key:K,value:V)->Result<Option<V>,String>{
  #[cfg(feature="native-policy")]if self.native.is_some(){self.check()?;if !rows.contains_key(&key){crate::key_policy_control::hash_room(&mut Allocation(self),rows)?;}}
  Ok(rows.insert(key,value))
 }
}

impl Fixture<'_>{
 /// Join an earlier real operational callback failure into this same scanner
 /// latch before a later pattern question can run. The original IO is moved.
 #[cfg(feature="native-policy")]pub(crate) fn note_operational(&self,actual:std::io::Error){let _=self.fail(actual);}
}

impl Pattern<'_,'_>{
 /// Borrow only this exact regex recipe under the next actual operation scratch
 /// loan. A recipe is DATA; it cannot retain a provider, source or compiled owner.
 pub fn with_fixture<'b,'budget>(&'b self,fixture:&'b Fixture<'budget>)->Result<Pattern<'b,'budget>,String>{
  if !fixture.has_native_patterns(){return Err(fixture.missing_native_pattern("native pattern recipe requires its actual scoped provider"))}
  Ok(Pattern{fixture,literal:std::borrow::Cow::Borrowed(self.literal.as_ref()),mode:self.mode,legacy:self.legacy})
 }
}

impl<'a> Fixture<'a>{
 #[cfg(feature="native-policy")]pub(crate) fn native_provider(&self)->Option<&dyn crate::native_pattern::Provider>{self.native.as_ref().and_then(|native|native.patterns)}
 pub(crate) fn recipe_pattern<'f>(&'f self,source:&'f str,mode:PatternMode)->Result<Pattern<'f,'a>,String>{
  if !self.has_native_patterns(){return Err(self.missing_native_pattern("native recipe requires its same-operation provider"))}
  Ok(Pattern{fixture:self,literal:std::borrow::Cow::Borrowed(source),mode,legacy:||panic!("native recipe cannot enter legacy matcher")})
 }
}

impl Fixture<'_>{fn missing_native_pattern(&self,message:&str)->String{
 #[cfg(feature="native-policy")]return self.fail(std::io::Error::new(std::io::ErrorKind::NotConnected,message.to_owned()));
 #[cfg(not(feature="native-policy"))]message.to_owned()
}}
#[cfg(not(feature="native-policy"))]impl<'a> Fixture<'a>{
 pub fn formatted_pattern<'f>(&'f self,_:std::fmt::Arguments<'_>,_:PatternMode)->Result<Pattern<'f,'a>,String>{Err("native formatted recipe requires native-policy and its actual provider".into())}
}
