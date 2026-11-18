//! Same literal trie/chunk preference algorithm with actual growth hooks.
use super::*;
use regex_syntax::native_admission::Hook;
use crate::nfa::thompson::builder::native::NativeBuilder;
pub(in crate::nfa::thompson) struct NativeLiteralTrie<'a>{states:Vec<State>,rev:bool,hook:Hook<'a>}
impl<'a> NativeLiteralTrie<'a>{
    pub(in crate::nfa::thompson) fn new(reverse:bool,hook:&Hook<'a>)->Result<Self,BuildError>{
        if !hook.active(){return Err(BuildError::native_refused())}
        let mut states=Vec::new();hook.push(&mut states,State::default())?;
        Ok(Self{states,rev:reverse,hook:hook.clone()})
    }
    pub(crate) fn add(&mut self, bytes: &[u8]) -> Result<(), BuildError> {
        let mut prev = StateID::ZERO;
        let mut it = bytes.iter().copied();
        while let Some(b) = if self.rev { it.next_back() } else { it.next() } {
            self.hook.checkpoint()?;prev = self.get_or_add_state(prev, b)?;
        }
        let target=&mut self.states[prev];
        if !(target.transitions.is_empty()&&!target.chunks.is_empty()){self.hook.room(&mut target.chunks,1)?;}
        target.add_match();
        Ok(())
    }

    fn get_or_add_state(
        &mut self,
        from: StateID,
        byte: u8,
    ) -> Result<StateID, BuildError> {
        let active = self.states[from].active_chunk();
        match active.binary_search_by_key(&byte, |t| t.byte) {
            Ok(i) => Ok(active[i].next),
            Err(i) => {
                // Add a new state and get its ID.
                let next = StateID::new(self.states.len()).map_err(|_| {
                    BuildError::too_many_states(self.states.len())
                })?;
                self.hook.push(&mut self.states,State::default())?;
                // Offset our position to account for all transitions and not
                // just the ones in the active chunk.
                let i = self.states[from].active_chunk_start() + i;
                let t = Transition { byte, next };
                self.hook.room(&mut self.states[from].transitions,1)?;
                self.states[from].transitions.insert(i,t);
                Ok(next)
            }
        }
    }

    pub(crate) fn compile(
        &self,
        builder: &mut NativeBuilder<'_>,
    ) -> Result<ThompsonRef, BuildError> {
        // Compilation proceeds via depth-first traversal of the trie.
        //
        // This is overall pretty brutal. The recursive version of this is
        // deliciously simple. (See 'compile_to_hir' below for what it might
        // look like.) But recursion on a trie means your call stack grows
        // in accordance with the longest literal, which just does not seem
        // appropriate. So we push the call stack to the heap. But as a result,
        // the trie traversal becomes pretty brutal because we essentially
        // have to encode the state of a double for-loop into an explicit call
        // frame. If someone can simplify this without using recursion, that'd
        // be great.

        // 'end' is our match state for this trie, but represented in the the
        // NFA. Any time we see a match in the trie, we insert a transition
        // from the current state we're in to 'end'.
        let end = builder.add_empty()?;
        let mut stack = vec![];
        let mut f = Frame::new(&self.states[StateID::ZERO]);
        loop {
            self.hook.checkpoint()?;
            if let Some(t) = f.transitions.next() {
                if self.states[t.next].is_leaf() {
                    self.hook.push(&mut f.sparse,thompson::Transition {
                        start: t.byte,
                        end: t.byte,
                        next: end,
                    })?;
                } else {
                    self.hook.push(&mut f.sparse,thompson::Transition {
                        start: t.byte,
                        end: t.byte,
                        // This is a little funny, but when the frame we create
                        // below completes, it will pop this parent frame off
                        // and modify this transition to point to the correct
                        // state.
                        next: StateID::ZERO,
                    })?;
                    self.hook.push(&mut stack,f)?;
                    f = Frame::new(&self.states[t.next]);
                }
                continue;
            }
            // At this point, we have visited all transitions in f.chunk, so
            // add it as a sparse NFA state. Unless the chunk was empty, in
            // which case, we don't do anything.
            if !f.sparse.is_empty() {
                let chunk_id = if f.sparse.len() == 1 {
                    builder.add_range(f.sparse.pop().unwrap())?
                } else {
                    let sparse = mem::replace(&mut f.sparse, vec![]);
                    builder.add_sparse(sparse)?
                };
                self.hook.push(&mut f.union,chunk_id)?;
            }
            // Now we need to look to see if there are other chunks to visit.
            if let Some(chunk) = f.chunks.next() {
                // If we're here, it means we're on the second (or greater)
                // chunk, which implies there is a match at this point. So
                // connect this state to the final end state.
                self.hook.push(&mut f.union,end)?;
                // Advance to the next chunk.
                f.transitions = chunk.iter();
                continue;
            }
            // Now that we are out of chunks, we have completely visited
            // this state. So turn our union of chunks into an NFA union
            // state, and add that union state to the parent state's current
            // sparse state. (If there is no parent, we're done.)
            let start = builder.add_union(f.union)?;
            match stack.pop() {
                None => {
                    return Ok(ThompsonRef { start, end });
                }
                Some(mut parent) => {
                    // OK because the only way a frame gets pushed on to the
                    // stack (aside from the root) is when a transition has
                    // been added to 'sparse'.
                    parent.sparse.last_mut().unwrap().next = start;
                    f = parent;
                }
            }
        }
    }

}
