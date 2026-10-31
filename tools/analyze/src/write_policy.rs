//! Original typed-write classification judgement over completed policy facts.
use std::collections::{HashMap,HashSet,BTreeSet};
#[derive(Default, serde::Serialize, serde::Deserialize)]
pub struct WriteIndex {
    /// Every written var name, typed or not.
    written: HashSet<String>,
    /// var -> the types that declare a var of that name some typed write reaches.
    typed: HashMap<String, BTreeSet<String>>,
    /// var names some write reaches through a receiver that could not be typed.
    untyped: BTreeSet<String>,
}

/// The receiver of a write that could not be typed.
pub const UNTYPED_WRITE: &str = "?";

impl WriteIndex {
    /// A digest of the written vars (`walk_cache`).
    pub fn digest(&self) -> u128 {
        let mut v: Vec<&String> = self.written.iter().collect();
        v.sort();
        let mut h = blake3::Hasher::new();
        for x in v {
            h.update(x.as_bytes());
            h.update(b"\n");
        }
        let mut t: Vec<(&String, &BTreeSet<String>)> = self.typed.iter().collect();
        t.sort();
        for (var, owners) in t {
            h.update(var.as_bytes());
            for o in owners {
                h.update(b"@");
                h.update(o.as_bytes());
            }
            h.update(b"\n");
        }
        for u in &self.untyped {
            h.update(b"?");
            h.update(u.as_bytes());
        }
        u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
    }

    /// Whether some write names `var`, on whatever type: a name test for callers that have no owner.
    pub fn is_written(&self, var: &str) -> bool {
        self.written.contains(var)
    }

    /// Whether `var`, as `owner` sees it, is written: by a write through a receiver typed as a type that declares it (`owner`'s declaring type,
    /// or one related to it), or by any write whose receiver could not be typed.
    pub(crate) fn is_written_on_checked<E>(&self,owner:&str,var:&str,var_owner:impl FnOnce(&str,&str)->Result<Option<String>,E>,subtype:impl FnMut(&str,&str)->Result<bool,E>)->Result<bool,E>{
        is_written_on(WriteView::Hashed(self),owner,var,var_owner,subtype)
    }
    pub(crate) fn into_rows<C:crate::key_policy_control::Control>(self,c:&mut C)->Result<WriteRows,C::Error>{
        let written=crate::global_policy::names(self.written.into_iter(),c)?;
        let untyped=crate::global_policy::names(self.untyped.into_iter(),c)?;
        let mut typed=Vec::new();for(name,owners)in self.typed{c.checkpoint()?;crate::key_policy_control::row(c,&mut typed)?;typed.push((name,crate::global_policy::names(owners.into_iter(),c)?));}typed.sort_by(|a,b|a.0.cmp(&b.0));
        Ok(WriteRows{written,typed:TypedRows(typed),untyped})
    }

    /// The var names written through a receiver that could not be typed.
    pub fn untyped(&self) -> &BTreeSet<String> {
        &self.untyped
    }

    /// The index of the typed writes `sets` hold (`(declaring type or UNTYPED_WRITE, var)` per proc).
    pub fn from_facts(sets:Vec<Vec<(String,String)>>)->WriteIndex{
        match Self::from_facts_controlled(sets,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}
    }
    pub(crate) fn from_facts_controlled<C:crate::key_policy_control::Control>(sets:Vec<Vec<(String,String)>>,c:&mut C)->Result<WriteIndex,C::Error>{
        use crate::key_policy_control as kc;
        kc::reserve(c,||sets.iter().try_fold(0usize,|n,set|n.checked_add(set.len()))?.checked_mul(1024)?.checked_add(8192))?;
        let mut w=WriteIndex::default();
        for(owner,var)in sets.into_iter().flatten(){
            c.checkpoint()?;
            w.written.insert(kc::own(c,&var)?);
            if owner==UNTYPED_WRITE{w.untyped.insert(var);}else{w.typed.entry(var).or_default().insert(owner);}
        }
        c.checkpoint()?;Ok(w)
    }
}

#[derive(serde::Serialize)]
pub(crate) struct WriteRows{written:Vec<String>,typed:TypedRows,untyped:Vec<String>}
struct TypedRows(Vec<(String,Vec<String>)>);
impl serde::Serialize for TypedRows{
 fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeMap;let mut map=s.serialize_map(Some(self.0.len()))?;for(n,owners)in &self.0{map.serialize_entry(n,owners)?;}map.end()}
}
enum WriteView<'a>{Hashed(&'a WriteIndex),Ordered(&'a WriteRows)}
enum Owners<'a>{Tree(std::collections::btree_set::Iter<'a,String>),Rows(std::slice::Iter<'a,String>)}
impl<'a> Iterator for Owners<'a>{type Item=&'a str;fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(i)=>i.next(),Self::Rows(i)=>i.next()}.map(String::as_str)}}
impl<'a> WriteView<'a>{
 fn written(&self,n:&str)->bool{match self{Self::Hashed(s)=>s.written.contains(n),Self::Ordered(s)=>s.written.binary_search_by(|v|v.as_str().cmp(n)).is_ok()}}
 fn untyped(&self,n:&str)->bool{match self{Self::Hashed(s)=>s.untyped.contains(n),Self::Ordered(s)=>s.untyped.binary_search_by(|v|v.as_str().cmp(n)).is_ok()}}
 fn owners(&self,n:&str)->Option<Owners<'a>>{match self{Self::Hashed(s)=>s.typed.get(n).map(|v|Owners::Tree(v.iter())),Self::Ordered(s)=>s.typed.0.binary_search_by(|v|v.0.as_str().cmp(n)).ok().map(|i|Owners::Rows(s.typed.0[i].1.iter()))}}
}
fn is_written_on<E>(s:WriteView<'_>,owner:&str,var:&str,var_owner:impl FnOnce(&str,&str)->Result<Option<String>,E>,mut subtype:impl FnMut(&str,&str)->Result<bool,E>)->Result<bool,E>{
 if !s.written(var){return Ok(false)}if s.untyped(var){return Ok(true)}let Some(decls)=s.owners(var)else{return Ok(false)};
 let at=var_owner(owner,var)?.unwrap_or_else(||owner.to_owned());for d in decls{if d==at||subtype(d,&at)?||subtype(&at,d)?{return Ok(true)}}Ok(false)
}
impl WriteRows{
 pub(crate) fn is_written_on_checked<E>(&self,owner:&str,var:&str,var_owner:impl FnOnce(&str,&str)->Result<Option<String>,E>,subtype:impl FnMut(&str,&str)->Result<bool,E>)->Result<bool,E>{is_written_on(WriteView::Ordered(self),owner,var,var_owner,subtype)}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){
  crate::global_policy::visit_names(&self.written,&mut visit);crate::global_policy::visit_names(&self.untyped,&mut visit);
  visit(self.typed.0.as_ptr() as usize,self.typed.0.capacity()*std::mem::size_of::<(String,Vec<String>)>());
  for(name,owners)in &self.typed.0{visit(name.as_ptr() as usize,name.capacity());crate::global_policy::visit_names(owners,&mut visit);}
 }
}

#[cfg(test)]mod tests{
 use super::*;
 #[test]
 fn original_declaring_owner_untyped_and_operational_refusal_survive_ordered_storage(){
  let index=WriteIndex::from_facts(vec![vec![("/base".into(),"charge".into()),(UNTYPED_WRITE.into(),"wild".into())]]);
  let rows=index.into_rows(&mut crate::key_policy_control::Compatibility).unwrap();
  let allow=rows.is_written_on_checked("/child","charge",|_,_|Ok::<_,std::io::Error>(Some("/base".into())),|_,_|panic!("exact declaring owner must short-circuit subtype walk")).unwrap();assert!(allow);
  assert!(!rows.is_written_on_checked("/other","charge",|_,_|Ok::<_,std::io::Error>(Some("/other".into())),|_,_|Ok(false)).unwrap());
  assert!(rows.is_written_on_checked("/other","wild",|_,_|->Result<Option<String>,std::io::Error>{panic!("untyped write needs no owner lookup")},|_,_|Ok(false)).unwrap());
  let error=rows.is_written_on_checked("/child","charge",|_,_|Err::<Option<String>,_>(std::io::Error::from_raw_os_error(1450)),|_,_|Ok(false)).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));
  let mut capacity=0;rows.visit_storage(|_,n|capacity+=n);assert!(capacity>0);
 }
}
