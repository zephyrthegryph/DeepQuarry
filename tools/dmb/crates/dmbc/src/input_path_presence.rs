//! Metadata-only path facts on the SAME snapshot. A persistent AVL owner keeps
//! captured snapshots immutable without copying the complete map on every probe.
//! No source acquisition, payload digest, CODE EOF or semantic grant is issued.
use super::*;
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaControlCredit,SourceArenaWork};
use std::sync::Arc;
struct Key{path:PathBuf,_credit:Option<SourceArenaControlCredit>}
/// Exact admitted key storage lent by the same recorder's opened fact.
/// This carries only a path allocation and its existing resource credit.
pub(super) struct SharedOriginalPathKey(Arc<Key>);

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
 loop{if let Some(owner)=next.take(){if let Some(mut node)=Arc::into_inner(owner){let left=node.left.0.take();let right=node.right.0.take();if let Some(right)=right{assert!(count<pending.len());pending[count]=Some(right);count+=1;}next=left;
 // Arc::into_inner removed the last physical node backing. Move its
 // existing control out and drop the node payload before retiring bytes.
 let credit=node._credit.take();
 drop(node);
 if let Some(credit)=credit {
  crate::query_db::retire_path_fact_node(&credit,arc_bytes::<Node<V>>().expect("existing fact node layout"));
 }
 continue}}
 if count==0{break}count-=1;next=pending[count].take();}
}}
impl<V:ImmutableFactValue+std::fmt::Debug> std::fmt::Debug for ImmutablePathFacts<V>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_map().entries(self.iter()).finish()}}
impl<V:ImmutableFactValue> PartialEq for ImmutablePathFacts<V>{fn eq(&self,other:&Self)->bool{self.len()==other.len()&&self.iter().eq(other.iter())}}impl<V:ImmutableFactValue> Eq for ImmutablePathFacts<V>{}
impl<V:ImmutableFactValue+Serialize> Serialize for ImmutablePathFacts<V>{fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeMap;let mut map=s.serialize_map(Some(self.len()))?;for(path,value)in self.iter(){map.serialize_entry(path,value)?}map.end()}}
impl<'de,V:ImmutableFactValue+Deserialize<'de>>Deserialize<'de> for ImmutablePathFacts<V>{fn deserialize<D:serde::Deserializer<'de>>(d:D)->Result<Self,D::Error>{let facts=BTreeMap::<PathBuf,V>::deserialize(d)?;let mut out=Self::default();for(path,present)in facts{out.record_data(&path,present).map_err(serde::de::Error::custom)?;}Ok(out)}}
fn capacity_error() -> io::Error { io::ErrorKind::OutOfMemory.into() }
fn arc_bytes<T>() -> io::Result<usize> {
    use std::alloc::Layout;
    let (layout, _) = Layout::new::<[usize; 2]>().extend(Layout::new::<T>())
        .map_err(|_| capacity_error())?;
    Ok(layout.pad_to_align().size())
}
fn path_bytes(path: &Path) -> io::Result<usize> {
    path.as_os_str().len().checked_mul(4)
        .and_then(|n| n.checked_add(arc_bytes::<Key>().ok()?))
        .ok_or_else(capacity_error)
}

/// One insertion-local check over the already funded construction envelope.
/// Every attempted new physical node is counted before allocation, including
/// copies used only to build a later rotation. Old immutable subtrees remain
/// covered by their original credits and never enter this total.
struct InsertFunding<'a> {
    credit: Option<&'a SourceArenaControlCredit>,
    constructed: usize,
}
impl InsertFunding<'_> {
    fn admit(&mut self, bytes: usize) -> io::Result<()> {
        if let Some(credit) = self.credit {
            self.constructed = self.constructed.checked_add(bytes)
                .filter(|total| *total <= credit.reserved_bytes())
                .ok_or_else(capacity_error)?;
        }
        Ok(())
    }
}
fn owned_path(path:&Path)->io::Result<PathBuf>{let mut copy=PathBuf::new();copy.try_reserve_exact(path.as_os_str().len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;copy.push(path);if copy.capacity()>path_bytes(path)?{return Err(io::ErrorKind::OutOfMemory.into())}Ok(copy)}
pub(crate) struct Iter<'a,V:ImmutableFactValue>{stack:[Option<&'a Node<V>>;usize::BITS as usize*2],len:usize}
impl<'a,V:ImmutableFactValue>Iter<'a,V>{fn descend(&mut self,mut row:Option<&'a Node<V>>){while let Some(node)=row{assert!(self.len<self.stack.len());self.stack[self.len]=Some(node);self.len+=1;row=node.left.0.as_deref();}}}
impl<'a,V:ImmutableFactValue>Iterator for Iter<'a,V>{type Item=(&'a PathBuf,&'a V);fn next(&mut self)->Option<Self::Item>{if self.len==0{return None}self.len-=1;let row=self.stack[self.len].take()?;self.descend(row.right.0.as_deref());Some((&row.key.path,&row.present))}}
impl<V:ImmutableFactValue> ImmutablePathFacts<V>{
 fn height(&self)->usize{self.0.as_deref().map_or(0,|n|n.height)}
 fn admitted(&self)->bool{self.0.as_deref().is_some_and(|n|n.admitted)}
 pub(crate) fn len(&self)->usize{self.0.as_deref().map_or(0,|n|n.len)}
 pub(crate) fn is_empty(&self)->bool{self.0.is_none()}
 pub(crate) fn get(&self,path:&Path)->Option<V>{self.get_ref(path).cloned()}
 fn find(&self,path:&Path)->Option<&Node<V>>{
  let mut row=self.0.as_deref();
  while let Some(node)=row{
   match path.cmp(&node.key.path){
    std::cmp::Ordering::Less=>row=node.left.0.as_deref(),
    std::cmp::Ordering::Greater=>row=node.right.0.as_deref(),
    std::cmp::Ordering::Equal=>return Some(node),
   }
  }
  None
 }
 pub(crate) fn get_ref(&self,path:&Path)->Option<&V>{self.find(path).map(|node|&node.present)}
 pub(super) fn admitted_original_key(&self,path:&Path)->Option<SharedOriginalPathKey>{
  let node=self.find(path)?;
  (node.key._credit.is_some()&&node.key.path.as_os_str()==path.as_os_str())
   .then(||SharedOriginalPathKey(Arc::clone(&node.key)))
 }
 pub(crate) fn iter(&self)->Iter<'_,V>{let mut rows=Iter{stack:std::array::from_fn(|_|None),len:0};rows.descend(self.0.as_deref());rows}
 pub(crate) fn keys(&self)->impl Iterator<Item=&PathBuf>{self.iter().map(|(path,_)|path)}
 pub(crate) fn probe_pregrant(&self,path:&Path)->io::Result<usize>{
  // One copied spine plus <=two rotations per level; this deliberately pays
  // for old/new physical overlap before IO, not a reported heap-size guess.
  let node = arc_bytes::<Node<V>>()?;
  self.height().checked_add(1).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(8)).and_then(|n|n.checked_mul(node)).and_then(|n|n.checked_add(path_bytes(path).ok()?)).ok_or_else(capacity_error)
 }
 fn node(left:Self,key:Arc<Key>,present:V,right:Self,funding:&mut InsertFunding<'_>)->io::Result<Self>{let height=left.height().max(right.height()).checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;let len=left.len().checked_add(right.len()).and_then(|n|n.checked_add(1)).ok_or(io::ErrorKind::OutOfMemory)?;if height>=usize::BITS as usize*2{return Err(io::ErrorKind::OutOfMemory.into())}funding.admit(arc_bytes::<Node<V>>()?)?;let admitted=funding.credit.is_some()||left.admitted()||right.admitted();Ok(Self(Some(Arc::new(Node{left,key,present,right,height,len,admitted,_credit:funding.credit.cloned()}))))}
 fn balanced(left:Self,key:Arc<Key>,present:V,right:Self,funding:&mut InsertFunding<'_>)->io::Result<Self>{
  if left.height()>right.height()+1{let l=left.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;if l.left.height()>=l.right.height(){let new_right=Self::node(l.right.clone(),key,present,right,funding)?;return Self::node(l.left.clone(),l.key.clone(),l.present.clone(),new_right,funding)}let mid=l.right.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;let new_left=Self::node(l.left.clone(),l.key.clone(),l.present.clone(),mid.left.clone(),funding)?;let new_right=Self::node(mid.right.clone(),key,present,right,funding)?;return Self::node(new_left,mid.key.clone(),mid.present.clone(),new_right,funding)}
  if right.height()>left.height()+1{let r=right.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;if r.right.height()>=r.left.height(){let new_left=Self::node(left,key,present,r.left.clone(),funding)?;return Self::node(new_left,r.key.clone(),r.present.clone(),r.right.clone(),funding)}let mid=r.left.0.as_deref().ok_or(io::ErrorKind::InvalidData)?;let new_left=Self::node(left,key,present,mid.left.clone(),funding)?;let new_right=Self::node(mid.right.clone(),r.key.clone(),r.present.clone(),r.right.clone(),funding)?;return Self::node(new_left,mid.key.clone(),mid.present.clone(),new_right,funding)}Self::node(left,key,present,right,funding)
 }
 fn insert(&self,key:Arc<Key>,present:V,funding:&mut InsertFunding<'_>)->io::Result<Self>{let Some(node)=self.0.as_deref()else{return Self::node(Self::default(),key,present,Self::default(),funding)};match key.path.cmp(&node.key.path){std::cmp::Ordering::Less=>Self::balanced(node.left.insert(key,present,funding)?,node.key.clone(),node.present.clone(),node.right.clone(),funding),std::cmp::Ordering::Greater=>Self::balanced(node.left.clone(),node.key.clone(),node.present.clone(),node.right.insert(key,present,funding)?,funding),std::cmp::Ordering::Equal=>if node.present==present{Ok(self.clone())}else{Err(invalid("path presence changed during capture"))}}}
 pub(crate) fn record_data(&mut self,path:&Path,present:V)->io::Result<()>{
  if let Some(old)=self.get(path){return if old==present{Ok(())}else{Err(invalid("path presence changed during capture"))}}
  if self.admitted(){return Err(io::Error::new(io::ErrorKind::NotConnected,"admitted path facts require their resource host"))}
  let key=Arc::new(Key{path:owned_path(path)?,_credit:None});
  *self=self.insert(key,present,&mut InsertFunding{credit:None,constructed:0})?;
  Ok(())
 }

 /// A reused immutable subtree cannot contain any of this insertion's
 /// freshly funded nodes. Walking only the new spine/rotation branches
 /// counts the surviving nodes without a second snapshot or a full tree scan.
 fn retained_insert_nodes(&self, credit: &SourceArenaControlCredit) -> io::Result<usize> {
  let Some(node) = self.0.as_deref() else { return Ok(0) };
  if !node._credit.as_ref().is_some_and(|owner| std::ptr::addr_eq(owner.owner(), credit.owner())) {
   return Ok(0);
  }
  let left = node.left.retained_insert_nodes(credit)?;
  let right = node.right.retained_insert_nodes(credit)?;
  left.checked_add(right).and_then(|n| n.checked_add(1)).ok_or_else(capacity_error)
 }

 /// The caller reserved a fresh insertion grant before the SAME actual
 /// provider probe. Construction keeps its full peak while the old tree and
 /// temporary copies coexist. Only this insertion's unused/transient bytes
 /// are refunded after the new root exists and before publication.
 pub(crate) fn recorded_using(&self,path:&Path,present:V,prepaid:SourceArenaCredit,work:&dyn SourceArenaWork)->io::Result<Self>{
  self.recorded_original_using(path,present,prepaid,work,None)
 }
 pub(crate) fn recorded_original_using(&self,path:&Path,present:V,prepaid:SourceArenaCredit,work:&dyn SourceArenaWork,bank:Option<&std::sync::Mutex<Option<SourceArenaControlCredit>>>)->io::Result<Self>{
  self.recorded_original_with_key_using(path,present,prepaid,work,bank,None)
 }
 /// The only shared-key caller lends the key of the SAME actual opened
 /// operation. Keep equal-but-differently spelled paths on the owned path.
 pub(super) fn recorded_original_with_key_using(&self,path:&Path,present:V,mut prepaid:SourceArenaCredit,work:&dyn SourceArenaWork,bank:Option<&std::sync::Mutex<Option<SourceArenaControlCredit>>>,shared:Option<SharedOriginalPathKey>)->io::Result<Self>{
  work.checkpoint()?;
  if let Some(old)=self.get(path){return if old==present{Ok(self.clone())}else{Err(invalid("path presence changed during capture"))}}
  let needed=self.probe_pregrant(path)?;
  if prepaid.reserved_bytes()<needed{let extra=needed-prepaid.reserved_bytes();work.grow(&mut prepaid,extra)?;}
  let credit=prepaid.control();
  let mut funding=InsertFunding{credit:Some(&credit),constructed:0};
  let (key,key_bytes)=match shared{
   Some(SharedOriginalPathKey(key)) if key.path.as_os_str()==path.as_os_str()=>(key,0),
   _=>{
    let path=owned_path(path)?;
    let key_bytes=arc_bytes::<Key>()?.checked_add(path.capacity()).ok_or_else(capacity_error)?;
    funding.admit(key_bytes)?;
    (Arc::new(Key{path,_credit:Some(credit.clone())}),key_bytes)
   }
  };
  let next=self.insert(key,present,&mut funding)?;
  let retained=next.retained_insert_nodes(&credit)?
   .checked_mul(arc_bytes::<Node<V>>()?).and_then(|n|n.checked_add(key_bytes))
   .filter(|bytes|*bytes<=funding.constructed)
   .ok_or_else(||invalid("retained path facts exceed their actual insertion storage"))?;
  // All abandoned temporary nodes have already dropped. The new key/nodes
  // still share the same live control; old snapshot aliases keep their
  // separately funded controls. Cleanup performs no provider or parser work.
  let unused=prepaid.reserved_bytes().checked_sub(retained).ok_or_else(capacity_error)?;
  if unused!=0 {work.shrink(&mut prepaid,unused)?;}
  if !match bank {Some(bank)=>work.bank_original_path_fact(&mut prepaid,bank)?,None=>false}{
   crate::query_db::seal_path_fact_control(prepaid);
  }
  Ok(next)
 }
 pub(crate) fn from_observed_data<'a>(rows:impl IntoIterator<Item=(&'a Path,V)>)->io::Result<Self>{let mut out=Self::default();for(path,present)in rows{out.record_data(path,present)?;}Ok(out)}
 pub(crate) fn same_owner(&self,other:&Self)->bool{match(&self.0,&other.0){(None,None)=>true,(Some(a),Some(b))=>Arc::ptr_eq(a,b),_=>false}}
 pub(crate) fn merge_data(&mut self,other:&Self)->io::Result<()>{if other.is_empty()||self.same_owner(other){return Ok(())}if self.is_empty(){*self=other.clone();return Ok(())}let mut covers=true;for(path,present)in other.iter(){match self.get(path){Some(old)if old!=present.clone()=>return Err(invalid("retained path presence conflicts with capture")),Some(_)=>(),None=>covers=false}}if covers{return Ok(())}if self.iter().all(|(path,present)|other.get(path)==Some(present.clone())){*self=other.clone();return Ok(())}if self.admitted()||other.admitted(){return Err(io::Error::new(io::ErrorKind::NotConnected,"disjoint admitted path facts require merge_using"))}for(path,present)in other.iter(){self.record_data(path,present.clone())?;}Ok(())}
 pub(crate) fn merge_using(&mut self,other:&Self,work:&dyn SourceArenaWork)->io::Result<()>{let mut out=self.clone();for(path,present)in other.iter(){if let Some(old)=out.get(path){if old!=present.clone(){return Err(invalid("retained path presence conflicts with capture"))}continue}let prepaid=work.reserve(out.probe_pregrant(path)?)?;out=out.recorded_using(path,present.clone(),prepaid,work)?;}*self=out;Ok(())}
 /// Real nodes/keys/credit controls, never conservative reservation bytes.
 /// Visitor deduplicates shared node, key and resource control addresses.
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let mut rows=Iter{stack:std::array::from_fn(|_|None),len:0};rows.descend(self.0.as_deref());while rows.len!=0{rows.len-=1;let node=rows.stack[rows.len].take().unwrap();rows.descend(node.right.0.as_deref());visit(node as *const Node<V> as usize,arc_bytes::<Node<V>>().expect("existing fact node layout"),arc_bytes::<Node<V>>().expect("existing fact node layout"));node.present.visit_fact_storage(&mut visit);visit(Arc::as_ptr(&node.key)as usize,arc_bytes::<Key>().expect("existing fact key layout"),arc_bytes::<Key>().expect("existing fact key layout"));visit(node.key.path.as_os_str().as_encoded_bytes().as_ptr()as usize,node.key.path.capacity(),node.key.path.capacity());if let Some(credit)=&node._credit{credit.visit_storage(&mut |p,n|visit(p,n,n));}if let Some(credit)=&node.key._credit{credit.visit_storage(&mut |p,n|visit(p,n,n));}}}
}

#[cfg(test)]mod generic_value_tests{
 use super::*;
 #[derive(Clone,Debug,Eq,PartialEq,Serialize,Deserialize)]enum Status{Readable,SourceFailure{kind:u8,code:Option<i32>}}
 impl ImmutableFactValue for Status{}
 #[test]fn sorted_nonboolean_status_values_keep_balanced_immutable_aliases_and_exact_roundtrip(){
  let mut facts=ImmutablePathFacts::<Status>::default();for at in 0..1024{let path=PathBuf::from(format!("E:/fact-fixture/{at:04}.dm"));facts.record_data(&path,if at%2==0{Status::Readable}else{Status::SourceFailure{kind:1,code:Some(5)}}).unwrap();}assert_eq!(facts.len(),1024);assert!(facts.height()<24,"sorted metadata observations cannot become an unbounded linked tree");let alias=facts.clone();for at in 1024..2048{facts.record_data(&PathBuf::from(format!("E:/fact-fixture/{at:04}.dm")),Status::Readable).unwrap();}assert_eq!(alias.len(),1024);assert_eq!(facts.len(),2048);assert!(facts.height()<24);assert_eq!(alias.get(Path::new("E:/fact-fixture/0001.dm")),Some(Status::SourceFailure{kind:1,code:Some(5)}));assert!(alias.get(Path::new("E:/fact-fixture/1024.dm")).is_none());let restored:ImmutablePathFacts<Status>=serde_json::from_slice(&serde_json::to_vec(&alias).unwrap()).unwrap();assert_eq!(restored,alias);drop((facts,alias,restored));
 }
}

#[cfg(test)]
mod exact_fact_credit_tests {
    use super::*;
    use crate::query_db::QueryDb;

    fn node_credits(
        tree: &PathPresenceFacts,
        seen: &mut std::collections::BTreeSet<usize>,
        owners: &mut BTreeMap<usize, (SourceArenaControlCredit, usize)>,
    ) {
        fn add(owners: &mut BTreeMap<usize, (SourceArenaControlCredit, usize)>,
               credit: &SourceArenaControlCredit, bytes: usize) {
            let addr = std::ptr::from_ref(credit.owner()).cast::<()>() as usize;
            owners.entry(addr).or_insert_with(|| (credit.clone(), 0)).1 += bytes;
        }
        let Some(node) = &tree.0 else { return; };
        if !seen.insert(Arc::as_ptr(node) as usize) { return; }
        if seen.insert(Arc::as_ptr(&node.key) as usize) {
            add(owners,node.key._credit.as_ref().unwrap(),
                arc_bytes::<Key>().unwrap() + node.key.path.capacity());
        }
        add(owners,node._credit.as_ref().unwrap(),arc_bytes::<Node<bool>>().unwrap());
        node_credits(&node.left,seen,owners);
        node_credits(&node.right,seen,owners);
    }

    fn assert_exact(roots: &[&PathPresenceFacts]) {
        let mut seen = std::collections::BTreeSet::new();
        let mut owners = BTreeMap::new();
        for root in roots { node_credits(root, &mut seen, &mut owners); }
        for (credit, bytes) in owners.into_values() {
            assert_eq!(credit.reserved_bytes(), bytes, "only physically live keys/nodes keep bytes");
        }
    }

    #[test]
    fn original_recorder_path_bank_refunds_last_nodes_and_keeps_detached_snapshot() {
        let db=QueryDb::default();
        let baseline=db.raw_source_input_charge_locked().unwrap();
        let bank=std::sync::Mutex::new(None);
        let mut tree=PathPresenceFacts::default();
        let mut old=None;
        for i in 0..64 {
            let path=PathBuf::from(format!("E:/facts/{i:04}.dm"));
            let prepaid=db.reserve(tree.probe_pregrant(&path).unwrap()).unwrap();
            tree=tree.recorded_original_using(&path,true,prepaid,&db,Some(&bank)).unwrap();
            if i==31{old=Some(tree.clone());}
        }
        let old=old.unwrap();
        assert_exact(&[&tree,&old]);
        let aliased=db.raw_source_input_charge_locked().unwrap();
        std::thread::scope(|threads| {
            for _ in 0..4 {
                let alias=old.clone();
                threads.spawn(move||drop(alias));
            }
            drop(old);
        });
        assert_exact(&[&tree]);
        let one=db.raw_source_input_charge_locked().unwrap();
        assert!(one<aliased);
        // The immutable snapshot, not the recorder, keeps the exact bank.
        drop(bank);
        assert_eq!(db.raw_source_input_charge_locked().unwrap(),one);
        let other=QueryDb::default();
        let mut ordinary=PathPresenceFacts::default();
        for i in 0..64 {
            let path=PathBuf::from(format!("E:/facts/{i:04}.dm"));
            let prepaid=other.reserve(ordinary.probe_pregrant(&path).unwrap()).unwrap();
            ordinary=ordinary.recorded_using(&path,true,prepaid,&other).unwrap();
        }
        assert_eq!(ordinary,tree);
        let ordinary_bytes=other.raw_source_input_charge_locked().unwrap();
        let bank_bytes=std::mem::size_of::<std::sync::atomic::AtomicUsize>()
            +3*std::mem::size_of::<usize>();
        assert_eq!(ordinary_bytes-one,63*256-bank_bytes,"one shared bank ledger row and Arc");
        drop(tree);
        assert_eq!(db.raw_source_input_charge_locked().unwrap(),baseline);
    }

    #[test]
    fn actual_path_fact_credits_follow_last_nodes_through_rotations_and_concurrent_alias_drop() {
        let db = QueryDb::default();
        let empty = db.raw_source_input_charge_locked().unwrap();
        let mut tree = PathPresenceFacts::default();
        let mut snapshot = None;
        for i in 0..384 {
            let path = PathBuf::from(format!("E:/facts/{i:04}.dm"));
            let prepaid = db.reserve(tree.probe_pregrant(&path).unwrap()).unwrap();
            tree = tree.recorded_using(&path,true,prepaid,&db).unwrap();
            if i == 191 { snapshot = Some(tree.clone()); }
        }
        let snapshot = snapshot.unwrap();
        assert_exact(&[&tree,&snapshot]);
        let with_snapshot = db.raw_source_input_charge_locked().unwrap();
        std::thread::scope(|threads| {
            for _ in 0..4 {
                let alias = snapshot.clone();
                threads.spawn(move || drop(alias));
            }
            drop(snapshot);
        });
        assert_eq!(tree.len(),384);
        assert!(tree.height() < 20);
        assert_exact(&[&tree]);
        assert!(db.raw_source_input_charge_locked().unwrap() < with_snapshot);
        drop(tree);
        assert_eq!(db.raw_source_input_charge_locked().unwrap(),empty);
    }
}
