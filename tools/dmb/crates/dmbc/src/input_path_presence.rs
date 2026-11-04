//! Metadata-only path facts on the SAME snapshot. A persistent AVL owner keeps
//! captured snapshots immutable without copying the complete map on every probe.
//! No source acquisition, payload digest, CODE EOF or semantic grant is issued.
use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaControlCredit,SourceArenaWork};
use std::sync::Arc;
struct Key{path:PathBuf,_credit:Option<SourceArenaControlCredit>}
struct Node<V:ImmutableFactValue>{left:ImmutablePathFacts<V>,key:Arc<Key>,present:V,right:ImmutablePathFacts<V>,height:usize,len:usize,admitted:bool,_credit:Option<SourceArenaControlCredit>}
/// Implementations must clone without allocating (bool or aliasing a separately
/// funded immutable owner), never a hidden String/Vec deep copy.
pub(crate) trait ImmutableFactValue:Clone+Eq{fn visit_fact_storage(&self,_visit:&mut dyn FnMut(usize,usize,usize)){} }
impl ImmutableFactValue for bool{}
pub(crate) type PathPresenceFacts=ImmutablePathFacts<bool>;
pub(crate) struct ImmutablePathFacts<V:ImmutableFactValue>(Option<Arc<Node<V>>>);
impl<V:ImmutableFactValue>Default for ImmutablePathFacts<V>{fn default()->Self{Self(None)}}
impl<V:ImmutableFactValue>Clone for ImmutablePathFacts<V>{fn clone(&self)->Self{Self(self.0.clone())}}
impl<V:ImmutableFactValue> Drop for ImmutablePathFacts<V>{fn drop(&mut self){
 // An AVL with a usize-sized count cannot reach this stack bound. Tear down
 // both child handles explicitly, so last-alias cleanup never recurses.
 let mut pending:[Option<Arc<Node<V>>>;usize::BITS as usize*2]=std::array::from_fn(|_|None);let mut count=0usize;let mut next=self.0.take();
 loop{if let Some(owner)=next.take(){if let Some(mut node)=Arc::into_inner(owner){let left=node.left.0.take();let right=node.right.0.take();if let Some(right)=right{assert!(count<pending.len());pending[count]=Some(right);count+=1;}next=left;drop(node);continue}}
 if count==0{break}count-=1;next=pending[count].take();}
}}
impl<V:ImmutableFactValue+std::fmt::Debug> std::fmt::Debug for ImmutablePathFacts<V>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_map().entries(self.iter()).finish()}}
impl<V:ImmutableFactValue> PartialEq for ImmutablePathFacts<V>{fn eq(&self,other:&Self)->bool{self.len()==other.len()&&self.iter().eq(other.iter())}}impl<V:ImmutableFactValue> Eq for ImmutablePathFacts<V>{}
impl<V:ImmutableFactValue+Serialize> Serialize for ImmutablePathFacts<V>{fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeMap;let mut map=s.serialize_map(Some(self.len()))?;for(path,value)in self.iter(){map.serialize_entry(path,value)?}map.end()}}
impl<'de,V:ImmutableFactValue+Deserialize<'de>>Deserialize<'de> for ImmutablePathFacts<V>{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{let facts=BTreeMap::<PathBuf,V>::deserialize(d)?;let mut out=Self::default();for(path,present)in facts{out.record_data(&path,present).map_err(serde::de::Error::custom)?;}Ok(out)}}
fn path_bytes(path:&Path)->io::Result<usize>{path.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<Key>()+2*std::mem::size_of::<usize>())).ok_or_else(||io::ErrorKind::OutOfMemory.into())}
fn owned_path(path:&Path)->io::Result<PathBuf>{let mut copy=PathBuf::new();copy.try_reserve_exact(path.as_os_str().len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;copy.push(path);if copy.capacity()>path_bytes(path)?{return Err(io::ErrorKind::OutOfMemory.into())}Ok(copy)}
pub(crate) struct Iter<'a,V:ImmutableFactValue>{stack:[Option<&'a Node<V>>;usize::BITS as usize*2],len:usize}
impl<'a,V:ImmutableFactValue>Iter<'a,V>{fn descend(&mut self,mut row:Option<&'a Node<V>>){while let Some(node)=row{assert!(self.len<self.stack.len());self.stack[self.len]=Some(node);self.len+=1;row=node.left.0.as_deref();}}}
impl<'a,V:ImmutableFactValue>Iterator for Iter<'a,V>{type Item=(&'a PathBuf,&'a V);fn next(&mut self)->Option<Self::Item>{if self.len==0{return None}self.len-=1;let row=self.stack[self.len].take()?;self.descend(row.right.0.as_deref());Some((&row.key.path,&row.present))}}
impl<V:ImmutableFactValue> ImmutablePathFacts<V>{
 fn height(&self)->usize{self.0.as_deref().map_or(0,|n|n.height)}
 fn admitted(&self)->bool{self.0.as_deref().is_some_and(|n|n.admitted)}
 pub(crate) fn len(&self)->usize{self.0.as_deref().map_or(0,|n|n.len)}
 pub(crate) fn is_empty(&self)->bool{self.0.is_none()}
 pub(crate) fn get(&self,path:&Path)->Option<V>{let mut row=self.0.as_deref();while let Some(node)=row{match path.cmp(&node.key.path){std::cmp::Ordering::Less=>row=node.left.0.as_deref(),std::cmp::Ordering::Greater=>row=node.right.0.as_deref(),std::cmp::Ordering::Equal=>return Some(node.present.clone())}}None}
 pub(crate) fn iter(&self)->Iter<'_,V>{let mut rows=Iter{stack:std::array::from_fn(|_|None),len:0};rows.descend(self.0.as_deref());rows}
 pub(crate) fn keys(&self)->impl Iterator<Item=&PathBuf>{self.iter().map(|(path,_)|path)}
 pub(crate) fn probe_pregrant(&self,path:&Path)->io::Result<usize>{
  // One copied spine plus <=two rotations per level; this deliberately pays
  // for old/new physical overlap before IO, not a reported heap-size guess.
  self.height().checked_add(1).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(8)).and_then(|n|n.checked_mul(std::mem::size_of::<Node<V>>()+2*std::mem::size_of::<usize>())).and_then(|n|n.checked_add(path_bytes(path).ok()?)).ok_or_else(||io::ErrorKind::OutOfMemory.into())
 }
 fn node(left:Self,key:Arc<Key>,present:V,right:Self,credit:&Option<SourceArenaControlCredit>)->io::Result<Self>{let height=left.height().max(right.height()).checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;let len=left.len().checked_add(right.len()).and_then(|n|n.checked_add(1)).ok_or(io::ErrorKind::OutOfMemory)?;if height>=usize::BITS as usize*2{return Err(io::ErrorKind::OutOfMemory.into())}let admitted=credit.is_some()||left.admitted()||right.admitted();Ok(Self(Some(Arc::new(Node{left,key,present,right,height,len,admitted,_credit:credit.clone()}))))}
 fn balanced(left:Self,key:Arc<Key>,present:V,right:Self,credit:&Option<SourceArenaControlCredit>)->io::Result<Self>{
  if left.height()>right.height()+1{let l=left.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;if l.left.height()>=l.right.height(){let new_right=Self::node(l.right.clone(),key,present,right,credit)?;return Self::node(l.left.clone(),l.key.clone(),l.present.clone(),new_right,credit)}let mid=l.right.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;let new_left=Self::node(l.left.clone(),l.key.clone(),l.present.clone(),mid.left.clone(),credit)?;let new_right=Self::node(mid.right.clone(),key,present,right,credit)?;return Self::node(new_left,mid.key.clone(),mid.present.clone(),new_right,credit)}
  if right.height()>left.height()+1{let r=right.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;if r.right.height()>=r.left.height(){let new_left=Self::node(left,key,present,r.left.clone(),credit)?;return Self::node(new_left,r.key.clone(),r.present.clone(),r.right.clone(),credit)}let mid=r.left.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;let new_left=Self::node(left,key,present,mid.left.clone(),credit)?;let new_right=Self::node(mid.right.clone(),r.key.clone(),r.present.clone(),r.right.clone(),credit)?;return Self::node(new_left,mid.key.clone(),mid.present.clone(),new_right,credit)}Self::node(left,key,present,right,credit)
 }
 fn insert(&self,key:Arc<Key>,present:V,credit:&Option<SourceArenaControlCredit>)->io::Result<Self>{let Some(node)=self.0.as_deref()else{return Self::node(Self::default(),key,present,Self::default(),credit)};match key.path.cmp(&node.key.path){std::cmp::Ordering::Less=>Self::balanced(node.left.insert(key,present,credit)?,node.key.clone(),node.present.clone(),node.right.clone(),credit),std::cmp::Ordering::Greater=>Self::balanced(node.left.clone(),node.key.clone(),node.present.clone(),node.right.insert(key,present,credit)?,credit),std::cmp::Ordering::Equal=>if node.present==present{Ok(self.clone())}else{Err(invalid("path presence changed during capture"))}}}
 pub(crate) fn record_data(&mut self,path:&Path,present:V)->io::Result<()>{if let Some(old)=self.get(path){return if old==present{Ok(())}else{Err(invalid("path presence changed during capture"))}}if self.admitted(){return Err(io::Error::new(io::ErrorKind::NotConnected,"admitted path facts require their resource host"))}let key=Arc::new(Key{path:owned_path(path)?,_credit:None});*self=self.insert(key,present,&None)?;Ok(())}
 /// Prepaid before the SAME actual provider probe. Every new physical node and
 /// key keeps an alias of this one resource-only control until its last alias.
 pub(crate) fn recorded_using(&self,path:&Path,present:V,mut prepaid:SourceArenaCredit,work:&dyn SourceArenaWork)->io::Result<Self>{work.checkpoint()?;if let Some(old)=self.get(path){return if old==present{Ok(self.clone())}else{Err(invalid("path presence changed during capture"))}}let needed=self.probe_pregrant(path)?;if prepaid.reserved_bytes()<needed{let extra=needed-prepaid.reserved_bytes();work.grow(&mut prepaid,extra)?;}let credit=Some(prepaid.into_control());let key=Arc::new(Key{path:owned_path(path)?,_credit:credit.clone()});self.insert(key,present,&credit)}
 pub(crate) fn from_observed_data<'a>(rows:impl IntoIterator<Item=(&'a Path,V)>)->io::Result<Self>{let mut out=Self::default();for(path,present)in rows{out.record_data(path,present)?;}Ok(out)}
 pub(crate) fn same_owner(&self,other:&Self)->bool{match(&self.0,&other.0){(None,None)=>true,(Some(a),Some(b))=>Arc::ptr_eq(a,b),_=>false}}
 pub(crate) fn merge_data(&mut self,other:&Self)->io::Result<()>{if other.is_empty()||self.same_owner(other){return Ok(())}if self.is_empty(){*self=other.clone();return Ok(())}let mut covers=true;for(path,present)in other.iter(){match self.get(path){Some(old)if old!=present.clone()=>return Err(invalid("retained path presence conflicts with capture")),Some(_)=>(),None=>covers=false}}if covers{return Ok(())}if self.iter().all(|(path,present)|other.get(path)==Some(present.clone())){*self=other.clone();return Ok(())}if self.admitted()||other.admitted(){return Err(io::Error::new(io::ErrorKind::NotConnected,"disjoint admitted path facts require merge_using"))}for(path,present)in other.iter(){self.record_data(path,present.clone())?;}Ok(())}
 pub(crate) fn merge_using(&mut self,other:&Self,work:&dyn SourceArenaWork)->io::Result<()>{let mut out=self.clone();for(path,present)in other.iter(){if let Some(old)=out.get(path){if old!=present.clone(){return Err(invalid("retained path presence conflicts with capture"))}continue}let prepaid=work.reserve(out.probe_pregrant(path)?)?;out=out.recorded_using(path,present.clone(),prepaid,work)?;}*self=out;Ok(())}
 /// Real nodes/keys/credit controls, never conservative reservation bytes.
 /// Visitor deduplicates shared node, key and resource control addresses.
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let mut rows=Iter{stack:std::array::from_fn(|_|None),len:0};rows.descend(self.0.as_deref());while rows.len!=0{rows.len-=1;let node=rows.stack[rows.len].take().unwrap();rows.descend(node.right.0.as_deref());visit(node as *const Node<V> as usize,std::mem::size_of::<Node<V>>()+2*std::mem::size_of::<usize>(),std::mem::size_of::<Node<V>>()+2*std::mem::size_of::<usize>());node.present.visit_fact_storage(&mut visit);visit(Arc::as_ptr(&node.key)as usize,std::mem::size_of::<Key>()+2*std::mem::size_of::<usize>(),std::mem::size_of::<Key>()+2*std::mem::size_of::<usize>());visit(node.key.path.as_os_str().as_encoded_bytes().as_ptr()as usize,node.key.path.capacity(),node.key.path.capacity());if let Some(credit)=&node._credit{credit.visit_storage(&mut |p,n|visit(p,n,n));}if let Some(credit)=&node.key._credit{credit.visit_storage(&mut |p,n|visit(p,n,n));}}}
}

#[cfg(test)]mod generic_value_tests{
 use super::*;
 #[derive(Clone,Debug,Eq,PartialEq,Serialize,Deserialize)]enum Status{Readable,SourceFailure{kind:u8,code:Option<i32>}}
 impl ImmutableFactValue for Status{}
 #[test]fn sorted_nonboolean_status_values_keep_balanced_immutable_aliases_and_exact_roundtrip(){
  let mut facts=ImmutablePathFacts::<Status>::default();for at in 0..1024{let path=PathBuf::from(format!("E:/fact-fixture/{at:04}.dm"));facts.record_data(&path,if at%2==0{Status::Readable}else{Status::SourceFailure{kind:1,code:Some(5)}}).unwrap();}assert_eq!(facts.len(),1024);assert!(facts.height()<24,"sorted metadata observations cannot become an unbounded linked tree");let alias=facts.clone();for at in 1024..2048{facts.record_data(&PathBuf::from(format!("E:/fact-fixture/{at:04}.dm")),Status::Readable).unwrap();}assert_eq!(alias.len(),1024);assert_eq!(facts.len(),2048);assert!(facts.height()<24);assert_eq!(alias.get(Path::new("E:/fact-fixture/0001.dm")),Some(Status::SourceFailure{kind:1,code:Some(5)}));assert!(alias.get(Path::new("E:/fact-fixture/1024.dm")).is_none());let restored:ImmutablePathFacts<Status>=serde_json::from_slice(&serde_json::to_vec(&alias).unwrap()).unwrap();assert_eq!(restored,alias);drop((facts,alias,restored));
 }
}
