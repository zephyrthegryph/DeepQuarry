//! Allocation-only adapter to the EXISTING checked collection/format helpers.
//! The issuer retains its same work credit through every owned result.
use std::{fmt,io};
use crate::{policy_finish::admitted::Work,key_policy_control::{self as kc,Control}};
pub(crate) struct Operation<'a>(pub(crate) &'a dyn Work);
impl Control for Operation<'_>{
 type Error=io::Error;const CHECKED:bool=true;
 fn checkpoint(&mut self)->io::Result<()>{self.0.checkpoint()}
 fn reserve(&mut self,n:usize)->io::Result<()>{self.0.reserve(n)}
 fn overflow(&mut self)->io::Error{self.0.overflow()}
 fn allocation_failed(&mut self)->io::Error{self.0.overflow()}
}
pub(crate) fn own(work:Option<&dyn Work>,text:&str)->io::Result<String>{match work{Some(work)=>kc::own(&mut Operation(work),text),None=>Ok(text.to_owned())}}
pub(crate) fn format(work:Option<&dyn Work>,args:fmt::Arguments<'_>)->io::Result<String>{match work{Some(work)=>kc::format(&mut Operation(work),args),None=>Ok(fmt::format(args))}}
pub(crate) fn row<T>(work:Option<&dyn Work>,rows:&mut Vec<T>)->io::Result<()>{match work{Some(work)=>kc::row(&mut Operation(work),rows),None=>Ok(())}}

pub(crate) fn checkpoint(work:Option<&dyn Work>)->io::Result<()>{match work{Some(work)=>work.checkpoint(),None=>Ok(())}}
pub(crate) fn size(work:Option<&dyn Work>,bytes:Option<usize>)->io::Result<usize>{bytes.ok_or_else(||work.map_or_else(||io::ErrorKind::OutOfMemory.into(),|work|work.overflow()))}
pub(crate) fn string_capacity(work:Option<&dyn Work>,capacity:usize)->io::Result<String>{
 if let Some(work)=work{work.checkpoint()?;work.reserve(capacity)?;}
 let mut value=String::new();value.try_reserve_exact(capacity).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
 if let Some(work)=work{if value.capacity()>capacity{return Err(work.overflow())}}
 Ok(value)
}
pub(crate) fn vec_capacity<T>(work:Option<&dyn Work>,capacity:usize)->io::Result<Vec<T>>{
 if let Some(work)=work{work.checkpoint()?;work.reserve(capacity.checked_mul(std::mem::size_of::<T>()).ok_or_else(||work.overflow())?)?;}
 let mut value=Vec::new();value.try_reserve_exact(capacity).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
 if let Some(work)=work{if value.capacity()>capacity{return Err(work.overflow())}}
 Ok(value)
}
pub(crate) fn extend<T>(work:Option<&dyn Work>,out:&mut Vec<T>,values:impl IntoIterator<Item=T>)->io::Result<()>{for value in values{row(work,out)?;out.push(value);}Ok(())}
pub(crate) fn map_get_mut<'a,K,Q:?Sized,V>(rows:&'a mut [(K,V)],key:&Q)->Option<&'a mut V>where K:std::borrow::Borrow<Q>,Q:Ord{let at=rows.binary_search_by(|(candidate,_)|candidate.borrow().cmp(key)).ok()?;Some(&mut rows[at].1)}
pub(crate) fn map_insert<K:Ord,V>(work:Option<&dyn Work>,rows:&mut Vec<(K,V)>,key:K,value:V)->io::Result<Option<V>>{match rows.binary_search_by(|(candidate,_)|candidate.cmp(&key)){Ok(at)=>Ok(Some(std::mem::replace(&mut rows[at].1,value))),Err(at)=>{row(work,rows)?;rows.insert(at,(key,value));Ok(None)}}}
pub(crate) fn set_insert<T:Ord>(work:Option<&dyn Work>,rows:&mut Vec<T>,value:T)->io::Result<bool>{match rows.binary_search(&value){Ok(_)=>Ok(false),Err(at)=>{row(work,rows)?;rows.insert(at,value);Ok(true)}}}
pub(crate) fn stable_sort_by<T>(work:Option<&dyn Work>,rows:&mut [T],compare:impl FnMut(&T,&T)->std::cmp::Ordering)->io::Result<()>{if let Some(work)=work{work.checkpoint()?;work.reserve(rows.len().checked_mul(std::mem::size_of::<T>()).ok_or_else(||work.overflow())?)?;}rows.sort_by(compare);checkpoint(work)}
pub(crate) fn push_str(work:Option<&dyn Work>,out:&mut String,text:&str)->io::Result<()>{checkpoint(work)?;let needed=size(work,out.len().checked_add(text.len()))?;if needed>out.capacity(){let capacity=needed.max(out.capacity().saturating_mul(2));if let Some(work)=work{work.reserve(capacity)?;}out.try_reserve_exact(capacity-out.len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;if let Some(work)=work{if out.capacity()>capacity{return Err(work.overflow())}}}out.push_str(text);Ok(())}
