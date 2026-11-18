//! Same forward Daciuk UTF8 compiler and bounded suffix-sharing map.
use super::*;
use regex_syntax::native_admission::Hook;
use crate::nfa::thompson::builder::native::NativeBuilder;
// Native-only storage for the SAME pending Daciuk nodes. The first completed
// transition is inline; a second transition promotes under the SAME Hook.
// Legacy Utf8State/Utf8Node and the configured bounded cache are unchanged.
pub(super) struct NativeUtf8State{compiled:Utf8BoundedMap,uncompiled:Vec<NativeUtf8Node>}
impl NativeUtf8State{
 pub(super) fn new()->Self{Self{compiled:Utf8BoundedMap::new(10_000),uncompiled:Vec::new()}}
 pub(super) fn native_frontier_backing(&self)->Option<((usize,usize,usize),usize,usize)>{
  let stack=self.uncompiled.capacity().checked_mul(core::mem::size_of::<NativeUtf8Node>())?;
  let transitions=self.uncompiled.iter().try_fold(0usize,|n,node|n.checked_add(match &node.trans{NativeTransitions::Many(rows)=>rows.capacity().checked_mul(core::mem::size_of::<Transition>())?,_=>0}))?;
  Some((self.compiled.native_frontier_backing()?,stack,transitions))
 }
}
enum NativeTransitions{Empty,One(Transition),Many(Vec<Transition>)}
impl NativeTransitions{
 fn as_slice(&self)->&[Transition]{match self{Self::Empty=>&[],Self::One(one)=>core::slice::from_ref(one),Self::Many(rows)=>rows}}
 fn push(&mut self,value:Transition,hook:&Hook<'_>)->Result<(),BuildError>{
  hook.checkpoint()?;
  match self{
   Self::Empty=>*self=Self::One(value),
   Self::One(first)=>{let mut rows=Vec::new();hook.room(&mut rows,2)?;rows.push(*first);rows.push(value);*self=Self::Many(rows);}
   Self::Many(rows)=>hook.push(rows,value)?,
  }Ok(())
 }
}
struct NativeUtf8Node{trans:NativeTransitions,last:Option<Utf8LastTransition>}
impl NativeUtf8Node{
 fn set_last_transition(&mut self,next:StateID,hook:&Hook<'_>)->Result<(),BuildError>{
  if let Some(last)=&self.last{self.trans.push(Transition{start:last.start,end:last.end,next},hook)?;self.last=None;}Ok(())
 }
}
pub(super) struct NativeUtf8Compiler<'a,'h>{builder:&'a mut NativeBuilder<'h>,state:&'a mut NativeUtf8State,target:StateID,hook:Hook<'h>}
impl<'a,'h> NativeUtf8Compiler<'a,'h>{

    pub(super) fn new(
        builder: &'a mut NativeBuilder<'h>,
        state: &'a mut NativeUtf8State,
        hook:&Hook<'h>,
    ) -> Result<NativeUtf8Compiler<'a,'h>,BuildError> {
        let target = builder.add_empty()?;
        state.compiled.clear_admitted(hook)?;state.uncompiled.clear();
        let mut utf8c=NativeUtf8Compiler{builder,state,target,hook:hook.clone()};
        utf8c.add_empty()?;
        Ok(utf8c)
    }

    pub(super) fn finish(&mut self) -> Result<ThompsonRef, BuildError> {
        self.compile_from(0)?;
        let node = self.pop_root();
        let start = self.compile(node)?;
        Ok(ThompsonRef { start, end: self.target })
    }

    pub(super) fn add(&mut self, ranges: &[Utf8Range]) -> Result<(), BuildError> {
        self.hook.checkpoint()?;
        let prefix_len = ranges
            .iter()
            .zip(&self.state.uncompiled)
            .take_while(|&(range, node)| {
                node.last.as_ref().map_or(false, |t| {
                    (t.start, t.end) == (range.start, range.end)
                })
            })
            .count();
        assert!(prefix_len < ranges.len());
        self.compile_from(prefix_len)?;
        self.add_suffix(&ranges[prefix_len..])?;
        Ok(())
    }

    fn compile_from(&mut self, from: usize) -> Result<(), BuildError> {
        let mut next = self.target;
        while from + 1 < self.state.uncompiled.len() {
            self.hook.checkpoint()?;
            let node = self.pop_freeze(next)?;
            next = self.compile(node)?;
        }
        self.top_last_freeze(next)?;
        Ok(())
    }

    fn compile(
        &mut self,
        node: NativeTransitions,
    ) -> Result<StateID, BuildError> {
        let hash = self.state.compiled.hash(node.as_slice());
        if let Some(id) = self.state.compiled.get_native(node.as_slice(), hash,|id,key|self.builder.matches_utf8_key(id,key)) {
            return Ok(id);
        }
        // Move the only transition Vec into the SAME sparse builder state.
        // This bounded cache borrows equality DATA by its stable ordinal until
        // this class finishes; next new() clears before any later lookup.
        let id=match node{NativeTransitions::One(one)=>self.builder.add_range(one)?,NativeTransitions::Many(rows)=>self.builder.add_sparse(rows)?,NativeTransitions::Empty=>self.builder.add_sparse(Vec::new())?};
        self.state.compiled.set_native_state_admitted(hash,id,&self.hook)?;
        Ok(id)
    }

    fn add_suffix(&mut self, ranges: &[Utf8Range]) -> Result<(),BuildError> {
        assert!(!ranges.is_empty());
        let last = self
            .state
            .uncompiled
            .len()
            .checked_sub(1)
            .expect("non-empty nodes");
        assert!(self.state.uncompiled[last].last.is_none());
        self.state.uncompiled[last].last = Some(Utf8LastTransition {
            start: ranges[0].start,
            end: ranges[0].end,
        });
        for r in &ranges[1..] {
            self.hook.push(&mut self.state.uncompiled,NativeUtf8Node {
                trans: NativeTransitions::Empty,
                last: Some(Utf8LastTransition { start: r.start, end: r.end }),
            })?;
        }
            Ok(())
    }

    fn add_empty(&mut self) -> Result<(),BuildError> {
        self.hook.push(&mut self.state.uncompiled,NativeUtf8Node { trans: NativeTransitions::Empty, last: None })?;
            Ok(())
    }

    fn pop_freeze(&mut self, next: StateID) -> Result<NativeTransitions,BuildError> {
        let mut uncompiled = self.state.uncompiled.pop().unwrap();
        uncompiled.set_last_transition(next,&self.hook)?;
        Ok(uncompiled.trans)
    }

    fn pop_root(&mut self) -> NativeTransitions {
        assert_eq!(self.state.uncompiled.len(), 1);
        assert!(self.state.uncompiled[0].last.is_none());
        self.state.uncompiled.pop().expect("non-empty nodes").trans
    }

    fn top_last_freeze(&mut self, next: StateID) -> Result<(),BuildError> {
        let last = self
            .state
            .uncompiled
            .len()
            .checked_sub(1)
            .expect("non-empty nodes");
        self.state.uncompiled[last].set_last_transition(next,&self.hook)?;
            Ok(())
    }

}

#[cfg(test)]mod inline_pending_transition_controls{
 use super::*;use core::sync::atomic::{AtomicBool,AtomicUsize,Ordering};
 struct Observe{calls:AtomicUsize,bytes:AtomicUsize,deny:AtomicBool}
 impl regex_syntax::native_admission::Admission for Observe{
  fn checkpoint(&self)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}
  fn reserve(&self,n:usize)->Result<(),regex_syntax::native_admission::Refused>{self.calls.fetch_add(1,Ordering::SeqCst);if self.deny.load(Ordering::SeqCst){return Err(regex_syntax::native_admission::Refused)}self.bytes.fetch_add(n,Ordering::SeqCst);Ok(())}
  fn overflow(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}fn allocation_failed(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
 }
 fn observed()->(alloc::sync::Arc<Observe>,Hook<'static>){let observer=alloc::sync::Arc::new(Observe{calls:AtomicUsize::new(0),bytes:AtomicUsize::new(0),deny:AtomicBool::new(false)});let hook=Hook(Some(observer.clone()));(observer,hook)}
 #[test]fn actual_singleton_pending_transition_owns_no_vec_and_second_transition_is_preadmitted(){
  let(observer,hook)=observed();let one=Transition{start:1,end:2,next:StateID::ZERO};let two=Transition{start:3,end:4,next:StateID::ZERO};let mut rows=NativeTransitions::Empty;
  rows.push(one,&hook).unwrap();assert_eq!(rows.as_slice(),[one]);assert_eq!(observer.calls.load(Ordering::SeqCst),0);assert!(matches!(rows,NativeTransitions::One(_)),"singleton has no allocated transition backing");
  observer.deny.store(true,Ordering::SeqCst);assert!(rows.push(two,&hook).is_err());assert_eq!(rows.as_slice(),[one]);assert!(matches!(rows,NativeTransitions::One(_)),"denied promotion cannot replace the old inline payload");
  observer.deny.store(false,Ordering::SeqCst);rows.push(two,&hook).unwrap();assert_eq!(rows.as_slice(),[one,two]);let NativeTransitions::Many(actual)=rows else{panic!("second transition must use real admitted backing")};assert_eq!(actual.capacity(),4);assert_eq!(observer.bytes.load(Ordering::SeqCst),4*core::mem::size_of::<Transition>()+64);
 }
 #[test]fn actual_native_pending_stack_charges_new_layout_and_singleton_cache_hit_keeps_exact_state(){
  let(observer,hook)=observed();let mut pending=Vec::new();hook.push(&mut pending,NativeUtf8Node{trans:NativeTransitions::Empty,last:None}).unwrap();assert_eq!(observer.bytes.load(Ordering::SeqCst),4*core::mem::size_of::<NativeUtf8Node>()+64);drop(pending);
  let mut builder=NativeBuilder::new(&hook).unwrap();let mut state=NativeUtf8State::new();let mut compiler=NativeUtf8Compiler::new(&mut builder,&mut state,&hook).unwrap();let one=Transition{start:1,end:2,next:compiler.target};let first=compiler.compile(NativeTransitions::One(one)).unwrap();let calls=observer.calls.load(Ordering::SeqCst);let same=compiler.compile(NativeTransitions::One(one)).unwrap();assert_eq!(same,first);assert_eq!(observer.calls.load(Ordering::SeqCst),calls,"exact singleton cache hit makes no transition copy or builder state");
  assert!(compiler.builder.matches_utf8_key(first,&[one]));let other=Transition{start:3,end:4,next:compiler.target};let changed=compiler.compile(NativeTransitions::One(other)).unwrap();assert_ne!(changed,first);assert!(compiler.builder.matches_utf8_key(changed,&[other]));
 }
}
