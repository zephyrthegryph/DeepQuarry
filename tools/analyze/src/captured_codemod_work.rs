//! One actual operation loan. No new allowance, source role, parser or memo.
//! Retained output can be borrowed only while its SAME physical credit lives.
use std::{cell::RefCell,io};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use crate::{native_pattern::Provider,policy_finish::admitted::Work,key_policy_control::Control};
pub(crate) struct Phase<'a>{
 work:&'a dyn SourceArenaWork,
 budget:&'a crate::captured_generator_budget::Budget,
 patterns:&'a dyn Provider,
 peaks:RefCell<[usize;16]>,
 credit:RefCell<SourceArenaCredit>,
}
pub(crate) struct Funded<T>{data:T,_credit:SourceArenaCredit}
impl<T>Funded<T>{pub(crate) fn borrow(&self)->&T{&self.data}}
impl<'a>Phase<'a>{
 pub(crate) fn new(work:&'a dyn SourceArenaWork,budget:&'a crate::captured_generator_budget::Budget,patterns:&'a dyn Provider)->io::Result<Self>{budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;work.checkpoint()?;Ok(Self{work,budget,patterns,peaks:RefCell::new([0;16]),credit:RefCell::new(work.reserve(0)?)})}
 pub(crate) fn finish<T>(self,data:T)->io::Result<Funded<T>>{
  // Metadata is actual containing geometry, not a guessed text multiplier.
  // It stays conservatively paid even if the caller keeps this wrapper inline.
  let work=self.work;let budget=self.budget;
  let mut funded=Funded{data,_credit:self.credit.into_inner()};
  // On ANY final failure, the whole keeper drops payload BEFORE credit.
  budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  work.grow(&mut funded._credit,std::mem::size_of::<Funded<T>>())?;
  work.checkpoint()?;Ok(funded)
 }
}
impl Work for Phase<'_>{
 fn checkpoint(&self)->io::Result<()>{self.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;self.work.checkpoint()}
 fn reserve(&self,bytes:usize)->io::Result<()>{
  Work::checkpoint(self)?;
  let mut credit=self.credit.try_borrow_mut().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"codemod allocation work already borrowed"))?;
  self.work.grow(&mut credit,bytes)
 }
 fn temporary(&self,slot:usize,bytes:usize)->io::Result<()>{
  let mut peaks=self.peaks.try_borrow_mut().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"codemod temporary work already borrowed"))?;
  let peak=peaks.get_mut(slot).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"unknown codemod temporary slot"))?;
  if bytes>*peak{Work::reserve(self,bytes-*peak)?;*peak=bytes;}Ok(())
 }
 fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}
}
impl Control for Phase<'_>{
 type Error=io::Error;const CHECKED:bool=true;
 fn native_patterns(&self)->Option<&dyn Provider>{Some(self.patterns)}
 fn native_pattern_failed(&mut self,actual:io::Error)->io::Error{actual}
 fn checkpoint(&mut self)->io::Result<()>{Work::checkpoint(self)}
 fn reserve(&mut self,bytes:usize)->io::Result<()>{Work::reserve(self,bytes)}
 fn temporary(&mut self,slot:usize,bytes:usize)->io::Result<()>{Work::temporary(self,slot,bytes)}
 fn overflow(&mut self)->io::Error{Work::overflow(self)}
 fn allocation_failed(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}
}
