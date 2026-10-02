//! Weak, content-addressed sharing across compiler sessions. Payload ownership
//! and budgets remain with callers; only this bounded lookup index is global.
use std::{any::{Any,TypeId},collections::{HashMap,VecDeque},sync::{Arc,Weak,Mutex,OnceLock}};
const LIMIT:usize=2*1024*1024;
type Key=(TypeId,&'static str,String,usize);
#[derive(Default)]
struct Arena { rows:HashMap<Key,Weak<dyn Any+Send+Sync>>, order:VecDeque<Key>, bytes:usize }
fn arena()->&'static Mutex<Arena> {static ARENA:OnceLock<Mutex<Arena>>=OnceLock::new();ARENA.get_or_init(||Mutex::new(Arena::default()))}
// A Weak also keeps the Arc allocation's inline T storage alive after its
// fields are dropped; charge that storage as part of the global index budget.
fn charge(key:&Key)->usize {key.2.capacity().saturating_mul(2).saturating_add(192).saturating_add(key.3)}
pub(crate) fn get<T:Any+Send+Sync>(stage:&'static str,digest:&str)->Option<Arc<T>> {
    let arena=arena().lock().unwrap_or_else(|error|error.into_inner());
    arena.rows.get(&(TypeId::of::<T>(),stage,digest.to_owned(),std::mem::size_of::<T>()))?.upgrade()?.downcast().ok()
}
/// Call only after the exact encoded payload digest and typed invariants have
/// been verified. A shared object's address is never a semantic reuse proof.
pub(crate) fn intern<T:Any+Send+Sync>(stage:&'static str,digest:&str,value:Arc<T>)->Arc<T> {
    let mut arena=arena().lock().unwrap_or_else(|error|error.into_inner());
    let key=(TypeId::of::<T>(),stage,digest.to_owned(),std::mem::size_of::<T>());
    if let Some(existing)=arena.rows.get(&key).and_then(Weak::upgrade).and_then(|value|value.downcast::<T>().ok()) {return existing;}
    // Existing expired keys retain their single FIFO entry and charge.
    if !arena.rows.contains_key(&key) {
        let bytes=charge(&key);
        if bytes>LIMIT {return value;}
        while arena.bytes.saturating_add(bytes)>LIMIT {
            let Some(old)=arena.order.pop_front() else {break;};
            arena.bytes=arena.bytes.saturating_sub(charge(&old));arena.rows.remove(&old);
        }
        arena.bytes+=bytes;arena.order.push_back(key.clone());
    }
    let erased:Arc<dyn Any+Send+Sync>=value.clone();
    arena.rows.insert(key,Arc::downgrade(&erased));value
}
/// Index only: session accounting already charges all strong payload owners.
pub fn resident_bytes()->usize {arena().lock().unwrap_or_else(|error|error.into_inner()).bytes}
pub fn trim()->usize {
    let mut arena=arena().lock().unwrap_or_else(|error|error.into_inner());let bytes=arena.bytes;
    *arena=Arena::default();bytes
}
