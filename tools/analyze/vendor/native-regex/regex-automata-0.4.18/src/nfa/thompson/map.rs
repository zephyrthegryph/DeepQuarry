// This module contains a couple simple and purpose built hash maps. The key
// trade off they make is that they serve as caches rather than true maps. That
// is, inserting a new entry may cause eviction of another entry. This gives
// us two things. First, there's less overhead associated with inserts and
// lookups. Secondly, it lets us control our memory usage.
//
// These maps are used in some fairly hot code when generating NFA states for
// large Unicode character classes.
//
// Instead of exposing a rich hashmap entry API, we just permit the caller to
// produce a hash of the key directly. The hash can then be reused for both
// lookups and insertions at the cost of leaking abstraction a bit. But these
// are for internal use only, so it's fine.
//
// The Utf8BoundedMap is used for Daciuk's algorithm for constructing a
// (almost) minimal DFA for large Unicode character classes in linear time.
// (Daciuk's algorithm is always used when compiling forward NFAs. For reverse
// NFAs, it's only used when the compiler is configured to 'shrink' the NFA,
// since there's a bit more expense in the reverse direction.)
//
// The Utf8SuffixMap is used when compiling large Unicode character classes for
// reverse NFAs when 'shrink' is disabled. Specifically, it augments the naive
// construction of UTF-8 automata by caching common suffixes. This doesn't
// get the same space savings as Daciuk's algorithm, but it's basically as
// fast as the naive approach and typically winds up using less memory (since
// it generates smaller NFAs) despite the presence of the cache.
//
// These maps effectively represent caching mechanisms for sparse and
// byte-range NFA states, respectively. The former represents a single NFA
// state with many transitions of equivalent priority while the latter
// represents a single NFA state with a single transition. (Neither state ever
// has or is an epsilon transition.) Thus, they have different key types. It's
// likely we could make one generic map, but the machinery didn't seem worth
// it. They are simple enough.

use alloc::{vec, vec::Vec};

use crate::{
    nfa::thompson::Transition,
    util::{
        int::{Usize, U64},
        primitives::StateID,
    },
};

// Basic FNV-1a hash constants as described in:
// https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
const PRIME: u64 = 1099511628211;
const INIT: u64 = 14695981039346656037;

/// A bounded hash map where the key is a sequence of NFA transitions and the
/// value is a pre-existing NFA state ID.
///
/// std's hashmap can be used for this, however, this map has two important
/// advantages. Firstly, it has lower overhead. Secondly, it permits us to
/// control our memory usage by limited the number of slots. In general, the
/// cost here is that this map acts as a cache. That is, inserting a new entry
/// may remove an old entry. We are okay with this, since it does not impact
/// correctness in the cases where it is used. The only effect that dropping
/// states from the cache has is that the resulting NFA generated may be bigger
/// than it otherwise would be.
///
/// This improves benchmarks that compile large Unicode character classes,
/// since it makes the generation of (almost) minimal UTF-8 automaton faster.
/// Specifically, one could observe the difference with std's hashmap via
/// something like the following benchmark:
///
///   hyperfine "regex-cli debug thompson -qr --captures none '\w{90} ecurB'"
///
/// But to observe that difference, you'd have to modify the code to use
/// std's hashmap.
///
/// It is quite possible that there is a better way to approach this problem.
/// For example, if there happens to be a very common state that collides with
/// a lot of less frequent states, then we could wind up with very poor caching
/// behavior. Alas, the effectiveness of this cache has not been measured.
/// Instead, ad hoc experiments suggest that it is "good enough." Additional
/// smarts (such as an LRU eviction policy) have to be weighed against the
/// amount of extra time they cost.
#[derive(Clone, Debug)]
pub struct Utf8BoundedMap {
    /// The current version of this map. Only entries with matching versions
    /// are considered during lookups. If an entry is found with a mismatched
    /// version, then the map behaves as if the entry does not exist.
    ///
    /// This makes it possible to clear the map by simply incrementing the
    /// version number instead of actually deallocating any storage.
    version: u16,
    /// The total number of entries this map can store.
    capacity: usize,
    /// The actual entries, keyed by hash. Collisions between different states
    /// result in the old state being dropped.
    map: Vec<Utf8BoundedEntry>,
    /// SAME bounded hash slots, pointing only to physically occupied rows.
    /// Empty slots no longer own ten thousand empty Vec headers. This is the
    /// representation of this map, not a second cache or a smaller capacity.
    slots: Vec<usize>,
}

/// An entry in this map.
#[derive(Clone, Debug, Default)]
struct Utf8BoundedEntry {
    /// The version of the map used to produce this entry. If this entry's
    /// version does not match the current version of the map, then the map
    /// should behave as if this entry does not exist.
    version: u16,
    /// The key, which is a sorted sequence of non-overlapping NFA transitions.
    key: Option<Vec<Transition>>,
    /// The state ID corresponding to the state containing the transitions in
    /// this entry.
    val: StateID,
}

impl Utf8BoundedMap {
    /// Diagnostic DATA only: actual vector backing, not allocator/RSS/admission.
    #[cfg(feature="native-admission")]
    pub(super) fn native_frontier_backing(&self)->Option<(usize,usize,usize)>{
        let slots=self.slots.capacity().checked_mul(core::mem::size_of::<usize>())?;
        let rows=self.map.capacity().checked_mul(core::mem::size_of::<Utf8BoundedEntry>())?;
        let keys=self.map.iter().try_fold(0usize,|n,e|n.checked_add(e.key.as_ref().map_or(0,|k|k.capacity()).checked_mul(core::mem::size_of::<Transition>())?))?;
        Some((slots,rows,keys))
    }

    #[cfg(feature="native-admission")]
    pub fn clear_admitted(&mut self,hook:&regex_syntax::native_admission::Hook<'_>)->Result<(),regex_syntax::native_admission::Refused>{
        hook.checkpoint()?;
        // Pre-admit the SAME configured slot roster. Occupied entry rows
        // grow separately through set_admitted before publication; key Vecs
        // arrive already owned/funded by the caller, exactly as before.
        hook.resize(&mut self.slots,self.capacity,usize::MAX)?;
        self.clear();Ok(())
    }

    /// Create a new bounded map with the given capacity. The map will never
    /// grow beyond the given size.
    ///
    /// Note that this does not allocate. Instead, callers must call `clear`
    /// before using this map. `clear` will allocate space if necessary.
    ///
    /// This avoids the need to pay for the allocation of this map when
    /// compiling regexes that lack large Unicode character classes.
    pub fn new(capacity: usize) -> Utf8BoundedMap {
        assert!(capacity > 0);
        Utf8BoundedMap { version: 0, capacity, map: vec![], slots:vec![] }
    }

    /// Clear this map of all entries, but permit the reuse of allocation
    /// if possible.
    ///
    /// This must be called before the map can be used.
    pub fn clear(&mut self) {
        if self.slots.is_empty() {
            self.slots = vec![usize::MAX; self.capacity];
        } else {
            self.slots.fill(usize::MAX);
            self.version = self.version.wrapping_add(1);
        }
        // All old entries were semantically absent after clear before too.
        // Drop their actually owned transition keys now, retaining only the
        // entry buffer for reuse. Native phase credit remains conservative
        // until the complete compiler's real retained settlement.
        self.map.clear();
    }

    /// Return a hash of the given transitions.
    pub fn hash(&self, key: &[Transition]) -> usize {
        let mut h = INIT;
        for t in key {
            h = (h ^ u64::from(t.start)).wrapping_mul(PRIME);
            h = (h ^ u64::from(t.end)).wrapping_mul(PRIME);
            h = (h ^ t.next.as_u64()).wrapping_mul(PRIME);
        }
        (h % self.capacity.as_u64()).as_usize()
    }

    /// Retrieve the cached state ID corresponding to the given key. The hash
    /// given must have been computed with `hash` using the same key value.
    ///
    /// If there is no cached state with the given transitions, then None is
    /// returned.
    pub fn get(&mut self, key: &[Transition], hash: usize) -> Option<StateID> {
        let index = self.slots[hash];
        if index == usize::MAX { return None; }
        let entry = &self.map[index];
        if entry.version != self.version {
            return None;
        }
        // There may be a hash collision, so we need to confirm real equality.
        if entry.key.as_deref() != Some(key) {
            return None;
        }
        Some(entry.val)
    }

    /// Native compilation already stores this immutable key in its SAME
    /// builder state. The callback borrows that existing state; no key copy,
    /// second roster or hash-only equality replaces exact transitions.
    #[cfg(feature="native-admission")]
    pub fn get_native(&mut self,key:&[Transition],hash:usize,matches:impl FnOnce(StateID,&[Transition])->bool)->Option<StateID>{
        let index=self.slots[hash];if index==usize::MAX{return None}let entry=&self.map[index];
        if entry.version!=self.version{return None}
        let equal=match &entry.key{Some(owned)=>owned.as_slice()==key,None=>matches(entry.val,key)};
        equal.then_some(entry.val)
    }
    #[cfg(feature="native-admission")]
    pub fn set_native_state_admitted(&mut self,hash:usize,state_id:StateID,hook:&regex_syntax::native_admission::Hook<'_>)->Result<(),regex_syntax::native_admission::Refused>{
        self.set_entry_admitted(None,hash,state_id,hook)
    }

    /// Add a cached state to this map with the given key. Callers should
    /// ensure that `state_id` points to a state that contains precisely the
    /// NFA transitions given.
    ///
    /// `hash` must have been computed using the `hash` method with the same
    /// key.
    pub fn set(
        &mut self,
        key: Vec<Transition>,
        hash: usize,
        state_id: StateID,
    ) {
        let entry=Utf8BoundedEntry { version: self.version, key:Some(key), val: state_id };
        let index=self.slots[hash];
        if index==usize::MAX {
            self.slots[hash]=self.map.len();
            self.map.push(entry);
        }else{self.map[index]=entry;}
    }

    #[cfg(feature="native-admission")]
    pub fn set_admitted(&mut self,key:Vec<Transition>,hash:usize,state_id:StateID,hook:&regex_syntax::native_admission::Hook<'_>)->Result<(),regex_syntax::native_admission::Refused>{
        self.set_entry_admitted(Some(key),hash,state_id,hook)
    }
    #[cfg(feature="native-admission")]
    fn set_entry_admitted(&mut self,key:Option<Vec<Transition>>,hash:usize,state_id:StateID,hook:&regex_syntax::native_admission::Hook<'_>)->Result<(),regex_syntax::native_admission::Refused>{
        hook.checkpoint()?;
        let index=self.slots[hash];
        let entry=Utf8BoundedEntry { version:self.version,key,val:state_id };
        if index==usize::MAX {
            // One entry per configured hash slot: semantic capacity is unchanged.
            // Fund full replacement backing/overlap with the existing Hook.
            hook.room(&mut self.map,1)?;
            let index=self.map.len();self.map.push(entry);self.slots[hash]=index;
        }else{self.map[index]=entry;}
        Ok(())
    }
}

/// A cache of suffixes used to modestly compress UTF-8 automata for large
/// Unicode character classes.
#[derive(Clone, Debug)]
pub struct Utf8SuffixMap {
    /// The current version of this map. Only entries with matching versions
    /// are considered during lookups. If an entry is found with a mismatched
    /// version, then the map behaves as if the entry does not exist.
    version: u16,
    /// The total number of entries this map can store.
    capacity: usize,
    /// The actual entries, keyed by hash. Collisions between different states
    /// result in the old state being dropped.
    map: Vec<Utf8SuffixEntry>,
}

/// A key that uniquely identifies an NFA state. It is a triple that represents
/// a transition from one state for a particular byte range.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Utf8SuffixKey {
    pub from: StateID,
    pub start: u8,
    pub end: u8,
}

/// An entry in this map.
#[derive(Clone, Debug, Default)]
struct Utf8SuffixEntry {
    /// The version of the map used to produce this entry. If this entry's
    /// version does not match the current version of the map, then the map
    /// should behave as if this entry does not exist.
    version: u16,
    /// The key, which consists of a transition in a particular state.
    key: Utf8SuffixKey,
    /// The identifier that the transition in the key maps to.
    val: StateID,
}

impl Utf8SuffixMap {

    #[cfg(feature="native-admission")]
    pub fn clear_admitted(&mut self,hook:&regex_syntax::native_admission::Hook<'_>)->Result<(),regex_syntax::native_admission::Refused>{
        hook.checkpoint()?;
        // The unchanged bounded engine map allocates exactly its configured
        // fixed entry roster only on first use or version wrap. Entry default
        // vectors are empty; owned keys are admitted by the caller before set.
        if self.map.is_empty()||self.version.wrapping_add(1)==0{
            hook.reserve(||self.capacity.checked_mul(core::mem::size_of::<Utf8SuffixEntry>())?.checked_add(64))?;
        }
        self.clear();Ok(())
    }

    /// Create a new bounded map with the given capacity. The map will never
    /// grow beyond the given size.
    ///
    /// Note that this does not allocate. Instead, callers must call `clear`
    /// before using this map. `clear` will allocate space if necessary.
    ///
    /// This avoids the need to pay for the allocation of this map when
    /// compiling regexes that lack large Unicode character classes.
    pub fn new(capacity: usize) -> Utf8SuffixMap {
        assert!(capacity > 0);
        Utf8SuffixMap { version: 0, capacity, map: vec![] }
    }

    /// Clear this map of all entries, but permit the reuse of allocation
    /// if possible.
    ///
    /// This must be called before the map can be used.
    pub fn clear(&mut self) {
        if self.map.is_empty() {
            self.map = vec![Utf8SuffixEntry::default(); self.capacity];
        } else {
            self.version = self.version.wrapping_add(1);
            if self.version == 0 {
                self.map = vec![Utf8SuffixEntry::default(); self.capacity];
            }
        }
    }

    /// Return a hash of the given transition.
    pub fn hash(&self, key: &Utf8SuffixKey) -> usize {
        // Basic FNV-1a hash as described:
        // https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
        const PRIME: u64 = 1099511628211;
        const INIT: u64 = 14695981039346656037;

        let mut h = INIT;
        h = (h ^ key.from.as_u64()).wrapping_mul(PRIME);
        h = (h ^ u64::from(key.start)).wrapping_mul(PRIME);
        h = (h ^ u64::from(key.end)).wrapping_mul(PRIME);
        (h % self.map.len().as_u64()).as_usize()
    }

    /// Retrieve the cached state ID corresponding to the given key. The hash
    /// given must have been computed with `hash` using the same key value.
    ///
    /// If there is no cached state with the given key, then None is returned.
    pub fn get(
        &mut self,
        key: &Utf8SuffixKey,
        hash: usize,
    ) -> Option<StateID> {
        let entry = &self.map[hash];
        if entry.version != self.version {
            return None;
        }
        if key != &entry.key {
            return None;
        }
        Some(entry.val)
    }

    /// Add a cached state to this map with the given key. Callers should
    /// ensure that `state_id` points to a state that contains precisely the
    /// NFA transition given.
    ///
    /// `hash` must have been computed using the `hash` method with the same
    /// key.
    pub fn set(&mut self, key: Utf8SuffixKey, hash: usize, state_id: StateID) {
        self.map[hash] =
            Utf8SuffixEntry { version: self.version, key, val: state_id };
    }
}

#[cfg(all(test,feature="native-admission"))]
mod native_occupied_entry_controls{
 use super::*;
 use alloc::sync::Arc;
 use core::sync::atomic::{AtomicUsize,Ordering};
 use regex_syntax::native_admission::{Admission,Hook,Refused};
 struct Probe{left:AtomicUsize,used:AtomicUsize,fail:AtomicUsize,first:AtomicUsize}
 impl Admission for Probe{
  fn checkpoint(&self)->Result<(),Refused>{if self.fail.load(Ordering::Acquire)!=0{self.first.compare_exchange(0,1450,Ordering::AcqRel,Ordering::Acquire).ok();Err(Refused)}else{Ok(())}}
  fn reserve(&self,n:usize)->Result<(),Refused>{self.checkpoint()?;self.left.fetch_update(Ordering::AcqRel,Ordering::Acquire,|left|left.checked_sub(n)).map_err(|_|Refused)?;self.used.fetch_add(n,Ordering::AcqRel);Ok(())}
  fn overflow(&self)->Refused{Refused}fn allocation_failed(&self)->Refused{Refused}
 }
 fn key(byte:u8)->Vec<Transition>{vec![Transition{start:byte,end:byte,next:StateID::must(0)}]}
 #[test]fn native_utf8_occupied_entries_preserve_bounded_collisions_clear_and_wrap(){
  let hook=Hook::default();let mut native=Utf8BoundedMap::new(1);let mut legacy=Utf8BoundedMap::new(1);native.clear_admitted(&hook).unwrap();legacy.clear();
  for byte in[1,2,3,1]{let row=key(byte);let hash=native.hash(&row);assert_eq!(hash,legacy.hash(&row));let id=StateID::must(byte as usize);native.set_admitted(row.clone(),hash,id,&hook).unwrap();legacy.set(row.clone(),hash,id);assert_eq!(native.get(&row,hash),legacy.get(&row,hash));assert_eq!(native.get(&row,hash),Some(id));assert_eq!(native.map.len(),1);let other=key(if byte==1{2}else{1});assert_eq!(native.get(&other,native.hash(&other)),None);}
  native.version=u16::MAX;legacy.version=u16::MAX;native.clear_admitted(&hook).unwrap();legacy.clear();assert_eq!(native.version,0);assert_eq!(native.map.len(),0);assert_eq!(native.get(&key(1),0),None);assert_eq!(native.get(&key(1),0),legacy.get(&key(1),0));
 }

 #[test]fn native_utf8_denial_preserves_empty_roster_and_existing_rows_before_real_growth(){
  let denied=Arc::new(Probe{left:AtomicUsize::new(1),used:AtomicUsize::new(0),fail:AtomicUsize::new(0),first:AtomicUsize::new(0)});let hook=Hook(Some(denied));let mut empty=Utf8BoundedMap::new(10_000);assert_eq!(empty.clear_admitted(&hook),Err(Refused));assert_eq!(empty.slots.capacity(),0);assert_eq!(empty.map.capacity(),0);
  let paid=Arc::new(Probe{left:AtomicUsize::new(1<<20),used:AtomicUsize::new(0),fail:AtomicUsize::new(0),first:AtomicUsize::new(0)});let hook=Hook(Some(paid.clone()));let mut map=Utf8BoundedMap::new(10_000);map.clear_admitted(&hook).unwrap();
  let mut rows=Vec::new();for byte in 0..=255{let row=key(byte);let hash=map.hash(&row);if rows.iter().any(|(_,prior)|*prior==hash){continue}rows.push((row,hash));if rows.len()==5{break}}
  assert_eq!(rows.len(),5);for(row,hash)in &rows[..4]{map.set_admitted(row.clone(),*hash,StateID::must(*hash),&hook).unwrap();}assert_eq!(map.map.len(),map.map.capacity(),"four occupied rows fill the first actual entry backing");let slots=map.slots.clone();let capacity=map.map.capacity();paid.left.store(0,Ordering::Release);
  assert_eq!(map.set_admitted(rows[4].0.clone(),rows[4].1,StateID::must(9),&hook),Err(Refused));assert_eq!(map.map.capacity(),capacity);assert_eq!(map.map.len(),4);assert_eq!(map.slots,slots);for(row,hash)in &rows[..4]{assert_eq!(map.get(row,*hash),Some(StateID::must(*hash)));}
 }
 #[test]fn native_utf8_sparse_entries_remove_real_empty_headers_and_refuse_before_growth(){
  let capacity=10_000;let old=capacity*core::mem::size_of::<Utf8BoundedEntry>();let probe=Arc::new(Probe{left:AtomicUsize::new(old-1),used:AtomicUsize::new(0),fail:AtomicUsize::new(0),first:AtomicUsize::new(0)});let hook=Hook(Some(probe.clone()));let mut map=Utf8BoundedMap::new(capacity);
  map.clear_admitted(&hook).unwrap();assert_eq!(map.slots.len(),capacity);assert_eq!(map.map.capacity(),0,"unoccupied slots have no entry backing");let row=key(7);let hash=map.hash(&row);map.set_admitted(row,hash,StateID::must(7),&hook).unwrap();
  let actual=map.slots.capacity()*core::mem::size_of::<usize>()+map.map.capacity()*core::mem::size_of::<Utf8BoundedEntry>();assert!(actual<old);assert!(probe.used.load(Ordering::Acquire)<old,"old eager full-row allocation cannot fit this unchanged test headroom");
  probe.fail.store(1,Ordering::Release);let prior=map.map.len();let new=key(9);let hash=map.hash(&new);assert_eq!(map.set_admitted(new,hash,StateID::must(9),&hook),Err(Refused));assert_eq!(map.map.len(),prior);assert_eq!(probe.first.load(Ordering::Acquire),1450,"transport refusal retains actual first failure with owner");assert_eq!(map.clear_admitted(&hook),Err(Refused));assert_eq!(map.map.len(),prior);
 }
}
