//! Same intermediate NFA builder with explicit preallocation hooks.
use super::*;
use alloc::boxed::Box;
use regex_syntax::native_admission::Hook;
#[derive(Debug)]
pub(in crate::nfa::thompson) struct NativeBuilder<'a>{
    hook:Hook<'a>,

    pattern_id: Option<PatternID>,
    states: Vec<State>,
    start_pattern: Vec<StateID>,
    captures: Vec<Vec<Option<Arc<str>>>>,
    memory_states: usize,
    utf8: bool,
    reverse: bool,
    look_matcher: LookMatcher,
    size_limit: Option<usize>,
}
impl<'a> NativeBuilder<'a>{

    pub fn new(hook:&Hook<'a>)->Result<Self,BuildError>{
        if !hook.active(){return Err(BuildError::native_refused())}hook.checkpoint()?;let original=super::Builder::new();
        Ok(Self{hook:hook.clone(),pattern_id:original.pattern_id,states:original.states,start_pattern:original.start_pattern,captures:original.captures,memory_states:original.memory_states,utf8:original.utf8,reverse:original.reverse,look_matcher:original.look_matcher,size_limit:original.size_limit})
    }

    pub fn clear(&mut self) {
        self.pattern_id = None;
        self.states.clear();
        self.start_pattern.clear();
        self.captures.clear();
        self.memory_states = 0;
    }

    pub fn build(
        &self,
        start_anchored: StateID,
        start_unanchored: StateID,
    ) -> Result<NFA, BuildError> {
        assert!(self.pattern_id.is_none(), "must call 'finish_pattern' first");
        debug!(
            "intermediate NFA compilation via builder is complete, \
             intermediate NFA size: {} states, {} bytes on heap",
            self.states.len(),
            self.memory_usage(),
        );

        let mut nfa = nfa::Inner::new_admitted(&self.hook)?;
        nfa.set_utf8(self.utf8);
        nfa.set_reverse(self.reverse);
        nfa.set_look_matcher(self.look_matcher.clone());
        // A set of compiler internal state IDs that correspond to states
        // that are exclusively epsilon transitions, i.e., goto instructions,
        // combined with the state that they point to. This is used to
        // record said states while transforming the compiler's internal NFA
        // representation to the external form.
        let mut empties = vec![];
        // A map used to re-map state IDs when translating this builder's
        // internal NFA state representation to the final NFA representation.
        let mut remap = vec![];
        self.hook.resize(&mut remap,self.states.len(),StateID::ZERO)?;

        nfa.set_starts_admitted(start_anchored,start_unanchored,&self.start_pattern,&self.hook)?;
        nfa.set_captures_admitted(&self.captures,&self.hook).map_err(BuildError::native_captures)?;
        // The idea here is to convert our intermediate states to their final
        // form. The only real complexity here is the process of converting
        // transitions, which are expressed in terms of state IDs. The new
        // set of states will be smaller because of partial epsilon removal,
        // so the state IDs will not be the same.
        for (sid, state) in self.states.iter().with_state_ids() {
            self.hook.checkpoint()?;
            match *state {
                State::Empty { next } => {
                    // Since we're removing empty states, we need to handle
                    // them later since we don't yet know which new state this
                    // empty state will be mapped to.
                    self.hook.push(&mut empties,(sid, next))?;
                }
                State::ByteRange { trans } => {
                    remap[sid] = nfa.add_admitted(nfa::State::ByteRange { trans },&self.hook)?;
                }
                State::Sparse { ref transitions } => {
                    remap[sid] = match transitions.len() {
                        0 => nfa.add_admitted(nfa::State::Fail,&self.hook)?,
                        1 => nfa.add_admitted(nfa::State::ByteRange {
                            trans: transitions[0],
                        },&self.hook)?,
                        _ => {
                            let transitions =
                                self.copy_boxed(transitions)?;
                            let sparse = SparseTransitions { transitions };
                            nfa.add_admitted(nfa::State::Sparse(sparse),&self.hook)?
                        }
                    }
                }
                State::Look { look, next } => {
                    remap[sid] = nfa.add_admitted(nfa::State::Look { look, next },&self.hook)?;
                }
                State::CaptureStart { pattern_id, group_index, next } => {
                    // We can't remove this empty state because of the side
                    // effect of capturing an offset for this capture slot.
                    let slot = nfa
                        .group_info()
                        .slot(pattern_id, group_index.as_usize())
                        .expect("invalid capture index");
                    let slot =
                        SmallIndex::new(slot).expect("a small enough slot");
                    remap[sid] = nfa.add_admitted(nfa::State::Capture {
                        next,
                        pattern_id,
                        group_index,
                        slot,
                    },&self.hook)?;
                }
                State::CaptureEnd { pattern_id, group_index, next } => {
                    // We can't remove this empty state because of the side
                    // effect of capturing an offset for this capture slot.
                    // Also, this always succeeds because we check that all
                    // slot indices are valid for all capture indices when they
                    // are initially added.
                    let slot = nfa
                        .group_info()
                        .slot(pattern_id, group_index.as_usize())
                        .expect("invalid capture index")
                        .checked_add(1)
                        .unwrap();
                    let slot =
                        SmallIndex::new(slot).expect("a small enough slot");
                    remap[sid] = nfa.add_admitted(nfa::State::Capture {
                        next,
                        pattern_id,
                        group_index,
                        slot,
                    },&self.hook)?;
                }
                State::Union { ref alternates } => {
                    if alternates.is_empty() {
                        remap[sid] = nfa.add_admitted(nfa::State::Fail,&self.hook)?;
                    } else if alternates.len() == 1 {
                        self.hook.push(&mut empties,(sid, alternates[0]))?;
                        remap[sid] = alternates[0];
                    } else if alternates.len() == 2 {
                        remap[sid] = nfa.add_admitted(nfa::State::BinaryUnion {
                            alt1: alternates[0],
                            alt2: alternates[1],
                        },&self.hook)?;
                    } else {
                        let alternates =
                            self.copy_boxed(alternates)?;
                        remap[sid] = nfa.add_admitted(nfa::State::Union { alternates },&self.hook)?;
                    }
                }
                State::UnionReverse { ref alternates } => {
                    if alternates.is_empty() {
                        remap[sid] = nfa.add_admitted(nfa::State::Fail,&self.hook)?;
                    } else if alternates.len() == 1 {
                        self.hook.push(&mut empties,(sid, alternates[0]))?;
                        remap[sid] = alternates[0];
                    } else if alternates.len() == 2 {
                        remap[sid] = nfa.add_admitted(nfa::State::BinaryUnion {
                            alt1: alternates[1],
                            alt2: alternates[0],
                        },&self.hook)?;
                    } else {
                        let mut alternates =
                            self.copy_boxed(alternates)?;
                        alternates.reverse();
                        remap[sid] = nfa.add_admitted(nfa::State::Union { alternates },&self.hook)?;
                    }
                }
                State::Fail => {
                    remap[sid] = nfa.add_admitted(nfa::State::Fail,&self.hook)?;
                }
                State::Match { pattern_id } => {
                    remap[sid] = nfa.add_admitted(nfa::State::Match { pattern_id },&self.hook)?;
                }
            }
        }
        // Some of the new states still point to empty state IDs, so we need to
        // follow each of them and remap the empty state IDs to their non-empty
        // state IDs.
        //
        // We also keep track of which states we've already mapped. This helps
        // avoid quadratic behavior in a long chain of empty states. For
        // example, in 'a{0}{50000}'.
        let mut remapped=Vec::new();self.hook.resize(&mut remapped,self.states.len(),false)?;
        for &(empty_id, empty_next) in empties.iter() {
            self.hook.checkpoint()?;
            if remapped[empty_id] {
                continue;
            }
            // empty states can point to other empty states, forming a chain.
            // So we must follow the chain until the end, which must end at
            // a non-empty state, and therefore, a state that is correctly
            // remapped. We are guaranteed to terminate because our compiler
            // never builds a loop among only empty states.
            let mut new_next = empty_next;
            while let Some(next) = self.states[new_next].goto() {
                new_next = next;
            }
            remap[empty_id] = remap[new_next];
            remapped[empty_id] = true;

            // Now that we've remapped the main 'empty_id' above, we re-follow
            // the chain from above and remap every empty state we found along
            // the way to our ultimate non-empty target. We are careful to set
            // 'remapped' to true for each such state. We thus will not need
            // to re-compute this chain for any subsequent empty states in
            // 'empties' that are part of this chain.
            let mut next2 = empty_next;
            while let Some(next) = self.states[next2].goto() {
                remap[next2] = remap[new_next];
                remapped[next2] = true;
                next2 = next;
            }
        }
        // Finally remap all of the state IDs.
        nfa.remap(&remap);
        let final_nfa = nfa.into_nfa_admitted(&self.hook)?;
        debug!(
            "NFA compilation via builder complete, \
             final NFA size: {} states, {} bytes on heap, \
             has empty? {:?}, utf8? {:?}",
            final_nfa.states().len(),
            final_nfa.memory_usage(),
            final_nfa.has_empty(),
            final_nfa.is_utf8(),
        );
        Ok(final_nfa)
    }

    pub fn start_pattern(&mut self) -> Result<PatternID, BuildError> {
        assert!(self.pattern_id.is_none(), "must call 'finish_pattern' first");

        let proposed = self.start_pattern.len();
        let pid = PatternID::new(proposed)
            .map_err(|_| BuildError::too_many_patterns(proposed))?;
        self.pattern_id = Some(pid);
        // This gets filled in when 'finish_pattern' is called.
        self.hook.push(&mut self.start_pattern,StateID::ZERO)?;
        Ok(pid)
    }

    pub fn finish_pattern(
        &mut self,
        start_id: StateID,
    ) -> Result<PatternID, BuildError> {
        let pid = self.current_pattern_id();
        self.start_pattern[pid] = start_id;
        self.pattern_id = None;
        Ok(pid)
    }

    pub fn current_pattern_id(&self) -> PatternID {
        self.pattern_id.expect("must call 'start_pattern' first")
    }

    pub fn pattern_len(&self) -> usize {
        self.start_pattern.len()
    }

    pub fn add_empty(&mut self) -> Result<StateID, BuildError> {
        self.add(State::Empty { next: StateID::ZERO })
    }

    pub fn add_union(
        &mut self,
        alternates: Vec<StateID>,
    ) -> Result<StateID, BuildError> {
        self.add(State::Union { alternates })
    }

    pub fn add_union_reverse(
        &mut self,
        alternates: Vec<StateID>,
    ) -> Result<StateID, BuildError> {
        self.add(State::UnionReverse { alternates })
    }

    pub fn add_range(
        &mut self,
        trans: Transition,
    ) -> Result<StateID, BuildError> {
        self.add(State::ByteRange { trans })
    }

    /// Borrow exact transitions while NativeUtf8Compiler exclusively owns
    /// this builder. Sparse states cannot be patched; Range endpoints are not
    /// exposed as class exits (the exit is a separate Empty state). No final
    /// remapping happens until build(), after the UTF8 cache's last lookup.
    pub(in crate::nfa::thompson) fn matches_utf8_key(&self,id:StateID,key:&[Transition])->bool{
        match self.states.get(id.as_usize()){
            Some(State::ByteRange{trans})=>key==core::slice::from_ref(trans),
            Some(State::Sparse{transitions})=>key==transitions.as_slice(),
            _=>false,
        }
    }

    pub fn add_sparse(
        &mut self,
        transitions: Vec<Transition>,
    ) -> Result<StateID, BuildError> {
        self.add(State::Sparse { transitions })
    }

    pub fn add_look(
        &mut self,
        next: StateID,
        look: Look,
    ) -> Result<StateID, BuildError> {
        self.add(State::Look { look, next })
    }

    pub fn add_capture_start(
        &mut self,
        next: StateID,
        group_index: u32,
        name: Option<Arc<str>>,
    ) -> Result<StateID, BuildError> {
        let pid = self.current_pattern_id();
        let group_index = match SmallIndex::try_from(group_index) {
            Err(_) => {
                return Err(BuildError::invalid_capture_index(group_index))
            }
            Ok(group_index) => group_index,
        };
        // Make sure we have space to insert our (pid,index)|-->name mapping.
        if pid.as_usize() >= self.captures.len() {
            for _ in 0..=(pid.as_usize() - self.captures.len()) {
                self.hook.push(&mut self.captures,Vec::new())?;
            }
        }
        // In the case where 'group_index < self.captures[pid].len()', it means
        // that we are adding a duplicate capture group. This is somewhat
        // weird, but permissible because the capture group itself can be
        // repeated in the syntax. For example, '([a-z]){4}' will produce 4
        // capture groups. In practice, only the last will be set at search
        // time when a match occurs. For duplicates, we don't need to push
        // anything other than a CaptureStart NFA state.
        if group_index.as_usize() >= self.captures[pid].len() {
            // For discontiguous indices, push placeholders for earlier capture
            // groups that weren't explicitly added.
            for _ in 0..(group_index.as_usize() - self.captures[pid].len()) {
                self.hook.push(&mut self.captures[pid],None)?;
            }
            self.hook.push(&mut self.captures[pid],name)?;
        }
        self.add(State::CaptureStart { pattern_id: pid, group_index, next })
    }

    pub fn add_capture_end(
        &mut self,
        next: StateID,
        group_index: u32,
    ) -> Result<StateID, BuildError> {
        let pid = self.current_pattern_id();
        let group_index = match SmallIndex::try_from(group_index) {
            Err(_) => {
                return Err(BuildError::invalid_capture_index(group_index))
            }
            Ok(group_index) => group_index,
        };
        self.add(State::CaptureEnd { pattern_id: pid, group_index, next })
    }

    pub fn add_fail(&mut self) -> Result<StateID, BuildError> {
        self.add(State::Fail)
    }

    pub fn add_match(&mut self) -> Result<StateID, BuildError> {
        let pattern_id = self.current_pattern_id();
        let sid = self.add(State::Match { pattern_id })?;
        Ok(sid)
    }

    fn add(&mut self, state: State) -> Result<StateID, BuildError> {
        self.hook.checkpoint()?;
        let id = StateID::new(self.states.len())
            .map_err(|_| BuildError::too_many_states(self.states.len()))?;
        self.memory_states += state.memory_usage();
        self.hook.push(&mut self.states,state)?;
        self.check_size_limit()?;
        Ok(id)
    }

    pub fn patch(
        &mut self,
        from: StateID,
        to: StateID,
    ) -> Result<(), BuildError> {
        let old_memory_states = self.memory_states;
        match self.states[from] {
            State::Empty { ref mut next } => {
                *next = to;
            }
            State::ByteRange { ref mut trans } => {
                trans.next = to;
            }
            State::Sparse { .. } => {
                panic!("cannot patch from a sparse NFA state")
            }
            State::Look { ref mut next, .. } => {
                *next = to;
            }
            State::Union { ref mut alternates } => {
                self.hook.push(&mut *alternates,to)?;
                self.memory_states += mem::size_of::<StateID>();
            }
            State::UnionReverse { ref mut alternates } => {
                self.hook.push(&mut *alternates,to)?;
                self.memory_states += mem::size_of::<StateID>();
            }
            State::CaptureStart { ref mut next, .. } => {
                *next = to;
            }
            State::CaptureEnd { ref mut next, .. } => {
                *next = to;
            }
            State::Fail => {}
            State::Match { .. } => {}
        }
        if old_memory_states != self.memory_states {
            self.check_size_limit()?;
        }
        Ok(())
    }

    pub fn set_utf8(&mut self, yes: bool) {
        self.utf8 = yes;
    }

    pub fn get_utf8(&self) -> bool {
        self.utf8
    }

    pub fn set_reverse(&mut self, yes: bool) {
        self.reverse = yes;
    }

    pub fn get_reverse(&self) -> bool {
        self.reverse
    }

    pub fn set_look_matcher(&mut self, m: LookMatcher) {
        self.look_matcher = m;
    }

    pub fn get_look_matcher(&self) -> &LookMatcher {
        &self.look_matcher
    }

    pub fn set_size_limit(
        &mut self,
        limit: Option<usize>,
    ) -> Result<(), BuildError> {
        self.size_limit = limit;
        self.check_size_limit()
    }

    pub fn get_size_limit(&self) -> Option<usize> {
        self.size_limit
    }

    /// Complete owned frozen-builder allocation envelope; no telemetry subtotal.
    /// The builder has flat states and ordinary Vec/Arc drops (no allocating
    /// recursive cleanup); HIR cleanup remains separately retained by caller.
    pub(in crate::nfa::thompson) fn native_retained_bytes(&self)->Option<usize>{
        fn backing<T>(capacity:usize)->Option<usize>{if capacity==0{Some(0)}else{capacity.checked_mul(core::mem::size_of::<T>())?.checked_add(64)}}
        let mut bytes=backing::<State>(self.states.capacity())?.checked_add(backing::<StateID>(self.start_pattern.capacity())?)?.checked_add(backing::<Vec<Option<Arc<str>>>>(self.captures.capacity())?)?;
        for state in &self.states{let child=match state{State::Sparse{transitions}=>backing::<Transition>(transitions.capacity())?,State::Union{alternates}|State::UnionReverse{alternates}=>backing::<StateID>(alternates.capacity())?,_=>0};bytes=bytes.checked_add(child)?;}
        for captures in &self.captures{
            bytes=bytes.checked_add(backing::<Option<Arc<str>>>(captures.capacity())?)?;
            for name in captures.iter().flatten(){
                // Same padded Arc<str> header/body envelope admitted by the
                // real add_capture_start producer before Arc::from(name).
                bytes=bytes.checked_add(name.len().checked_add(2*core::mem::size_of::<usize>())?.checked_add(core::mem::align_of::<usize>()-1)?.checked_add(64)?)?;
            }
        }Some(bytes)
    }

    // Diagnostic DATA only; this visits existing vector owners without allocation.
    // Arc string bodies/allocator headers are NOT included in these backing counts.
    pub(in crate::nfa::thompson) fn native_frontier_backing(&self)->Option<(usize,usize,usize,usize)>{
        let states=self.states.capacity().checked_mul(core::mem::size_of::<State>())?;
        let children=self.states.iter().try_fold(0usize,|n,s|{let bytes=match s{State::Sparse{transitions}=>transitions.capacity().checked_mul(core::mem::size_of::<Transition>())?,State::Union{alternates}|State::UnionReverse{alternates}=>alternates.capacity().checked_mul(core::mem::size_of::<StateID>())?,_=>0};n.checked_add(bytes)})?;
        let starts=self.start_pattern.capacity().checked_mul(core::mem::size_of::<StateID>())?;
        let captures=self.captures.iter().try_fold(self.captures.capacity().checked_mul(core::mem::size_of::<Vec<Option<Arc<str>>>>())?,|n,c|n.checked_add(c.capacity().checked_mul(core::mem::size_of::<Option<Arc<str>>>())?))?;
        Some((states,children,starts,captures))
    }

    pub fn memory_usage(&self) -> usize {
        self.states.len() * mem::size_of::<State>() + self.memory_states
    }

    fn check_size_limit(&self) -> Result<(), BuildError> {
        if let Some(limit) = self.size_limit {
            if self.memory_usage() > limit {
                return Err(BuildError::exceeded_size_limit(limit));
            }
        }
        Ok(())
    }
    fn copy_boxed<T:Clone>(&self,source:&[T])->Result<Box<[T]>,BuildError>{
        let mut rows=Vec::new();self.hook.room(&mut rows,source.len())?;rows.extend_from_slice(source);
        if rows.len()!=rows.capacity(){self.hook.reserve(||rows.len().checked_mul(core::mem::size_of::<T>())?.checked_add(64))?;}
        Ok(rows.into_boxed_slice())
    }

}

#[cfg(test)]mod typing_repair_controls{
 use super::*;
 struct Allowed;
 impl regex_syntax::native_admission::Admission for Allowed{
  fn checkpoint(&self)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}
  fn reserve(&self,_:usize)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}
  fn overflow(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
  fn allocation_failed(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
 }
 #[test]fn actual_native_builder_copies_original_utf8_and_clear_preserves_configuration(){
  let hook=Hook(Some(alloc::sync::Arc::new(Allowed)));let original=super::super::Builder::new();
  let mut actual=NativeBuilder::new(&hook).unwrap();assert_eq!(actual.utf8,original.utf8);
  actual.set_utf8(!original.utf8);actual.clear();assert_eq!(actual.utf8,!original.utf8);
 }
}

#[cfg(test)]mod borrowed_utf8_key_controls{
 use super::*;use crate::nfa::thompson::map::Utf8BoundedMap;
 struct Allowed;impl regex_syntax::native_admission::Admission for Allowed{
  fn checkpoint(&self)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}fn reserve(&self,_:usize)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}
  fn overflow(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}fn allocation_failed(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
 }
 #[test]fn native_utf8_cache_borrows_exact_builder_keys_and_rejects_collisions_or_patched_range(){
  let hook=Hook(Some(alloc::sync::Arc::new(Allowed)));let mut builder=NativeBuilder::new(&hook).unwrap();let mut map=Utf8BoundedMap::new(1);map.clear_admitted(&hook).unwrap();let end=builder.add_empty().unwrap();
  let rows=vec![Transition{start:1,end:2,next:end},Transition{start:4,end:5,next:end}];let address=rows.as_ptr();let wanted=rows.clone();let id=builder.add_sparse(rows).unwrap();
  assert!(matches!(&builder.states[id],State::Sparse{transitions}if transitions.as_ptr()==address),"the SAME Vec backing moves into the builder");
  map.set_native_state_admitted(0,id,&hook).unwrap();assert_eq!(map.get_native(&wanted,0,|id,key|builder.matches_utf8_key(id,key)),Some(id));
  let foreign=[Transition{start:8,end:9,next:end}];assert_eq!(map.get_native(&foreign,0,|id,key|builder.matches_utf8_key(id,key)),None);
  let range=Transition{start:10,end:11,next:end};let rid=builder.add_range(range).unwrap();map.set_native_state_admitted(0,rid,&hook).unwrap();assert_eq!(map.get_native(&wanted,0,|id,key|builder.matches_utf8_key(id,key)),None);
  assert_eq!(map.get_native(&[range],0,|id,key|builder.matches_utf8_key(id,key)),Some(rid));let other=builder.add_empty().unwrap();builder.patch(rid,other).unwrap();
  assert_eq!(map.get_native(&[range],0,|id,key|builder.matches_utf8_key(id,key)),None,"changed real transitions never make a false cache hit");
  map.clear_admitted(&hook).unwrap();assert_eq!(map.get_native(&wanted,0,|id,key|builder.matches_utf8_key(id,key)),None);
 }
}
