//! Same forward Thompson compiler used by the existing Pat semantics.
use super::*;
use regex_syntax::native_admission::Hook;
use crate::nfa::thompson::{builder::native::NativeBuilder,literal_trie::native::NativeLiteralTrie};
#[path="native_utf8.rs"]mod native_utf8;
use native_utf8::{NativeUtf8Compiler,NativeUtf8State};
// Diagnostics cannot replace the actual operational error or panic in Drop.
#[cfg(feature="std")]
fn native_frontier_trace(args:core::fmt::Arguments<'_>){let _=std::io::Write::write_fmt(&mut std::io::stderr().lock(),format_args!("{}\n",args));}
struct NativeCompiler<'a>{config:Config,builder:RefCell<NativeBuilder<'a>>,utf8_state:RefCell<NativeUtf8State>,hook:Hook<'a>}
// Narrow opt-in observation only. Counts are actual vector capacities, NOT a
// complete heap/admission census, and never grant or refund resource bytes.
impl NativeCompiler<'_>{
 fn native_frontier(&self,stage:&str){
  #[cfg(feature="std")]
  if std::env::var_os("DMB_ORIGINAL_TRACE_PATTERN_FRONTIER").is_some(){
   match(self.builder.try_borrow(),self.utf8_state.try_borrow()){
    (Ok(builder),Ok(utf8))=>native_frontier_trace(format_args!("NATIVE_PATTERN_OWNED_FRONTIER stage={} builder_vectors={:?} utf8_vectors={:?}",stage,builder.native_frontier_backing(),utf8.native_frontier_backing())),
    _=>native_frontier_trace(format_args!("NATIVE_PATTERN_OWNED_FRONTIER stage={} vectors=unavailable_borrowed",stage)),
   }
  }
 }
}
struct NativeFrontier<'a,'h>{compiler:&'a NativeCompiler<'h>,stage:&'static str}
impl Drop for NativeFrontier<'_,'_>{fn drop(&mut self){self.compiler.native_frontier(self.stage);}}

pub(in crate::nfa::thompson) fn compile(expr:&Hir,limit:Option<usize>,hook:&Hook<'_>)->Result<NFA,BuildError>{compile_using(expr,limit,hook,None)}
pub(in crate::nfa::thompson) fn compile_with_retained<'h>(expr:&Hir,limit:Option<usize>,hook:&Hook<'h>,phase:&mut regex_syntax::native_admission::RetainedPhase<'h>,hir_retained:usize)->Result<NFA,BuildError>{compile_using(expr,limit,hook,Some((phase,hir_retained)))}
fn compile_using<'h>(expr:&Hir,limit:Option<usize>,hook:&Hook<'h>,phase:Option<(&mut regex_syntax::native_admission::RetainedPhase<'h>,usize)>)->Result<NFA,BuildError>{
    if !hook.active(){return Err(BuildError::native_refused())}hook.checkpoint()?;
    let actual=NativeCompiler{config:Config::default().nfa_size_limit(limit),builder:RefCell::new(NativeBuilder::new(hook)?),utf8_state:RefCell::new(NativeUtf8State::new()),hook:hook.clone()};
    let result=actual.compile(&[expr],phase);hook.checkpoint()?;result
}
impl<'a> NativeCompiler<'a>{
    fn compile<H: Borrow<Hir>>(&self, exprs: &[H],phase:Option<(&mut regex_syntax::native_admission::RetainedPhase<'a>,usize)>) -> Result<NFA, BuildError> {
        if exprs.len() > PatternID::LIMIT {
            return Err(BuildError::too_many_patterns(exprs.len()));
        }
        if self.config.get_reverse()
            && self.config.get_which_captures().is_any()
        {
            return Err(BuildError::unsupported_captures());
        }

        self.builder.borrow_mut().clear();
        self.builder.borrow_mut().set_utf8(self.config.get_utf8());
        self.builder.borrow_mut().set_reverse(self.config.get_reverse());
        self.builder
            .borrow_mut()
            .set_look_matcher(self.config.get_look_matcher());
        self.builder
            .borrow_mut()
            .set_size_limit(self.config.get_nfa_size_limit())?;

        // We always add an unanchored prefix unless we were specifically told
        // not to (for tests only), or if we know that the regex is anchored
        // for all matches. When an unanchored prefix is not added, then the
        // NFA's anchored and unanchored start states are equivalent.
        let all_anchored = exprs.iter().all(|e| {
            let props = e.borrow().properties();
            if self.config.get_reverse() {
                props.look_set_suffix().contains(hir::Look::End)
            } else {
                props.look_set_prefix().contains(hir::Look::Start)
            }
        });
        let anchored = !self.config.get_unanchored_prefix() || all_anchored;
        let unanchored_prefix = if anchored {
            self.c_empty()?
        } else {
            let any=Hir::dot_admitted(hir::Dot::AnyByte,&self.hook)?;
            self.c_at_least(&any,false,0)?
        };

        let compiled = self.c_alt_iter(exprs.iter().map(|e| {
            let _ = self.start_pattern()?;
            let one = self.c_cap(0, None, e.borrow())?;
            let match_state_id = self.add_match()?;
            self.patch(one.end, match_state_id)?;
            let _ = self.finish_pattern(one.start)?;
            Ok(ThompsonRef { start: one.start, end: match_state_id })
        }))?;
        self.patch(unanchored_prefix.end, compiled.start)?;
        // All class lookups and Daciuk construction have finished. The SAME
        // memo has no readers during final builder copy/remap; destroy its
        // actual backing before claiming any FrozenBuilder checkpoint.
        let retired_utf8=self.utf8_state.replace(NativeUtf8State::new());
        drop(retired_utf8);
        if let Some((phase,hir_retained))=phase{
            let builder=self.builder.borrow().native_retained_bytes().ok_or_else(||self.hook.overflow())?;
            let retained=hir_retained.checked_add(builder).ok_or_else(||self.hook.overflow())?;
            phase.checkpoint_builder(&self.hook,retained)?;
        }
        self.native_frontier("before_final_builder_copy");
        let _frontier=NativeFrontier{compiler:self,stage:"after_final_builder_copy_or_error"};
        let nfa = self
            .builder
            .borrow_mut()
            .build(compiled.start, unanchored_prefix.start)?;

        debug!("HIR-to-NFA compilation complete, config: {:?}", self.config);
        Ok(nfa)
    }

    fn c(&self, expr: &Hir) -> Result<ThompsonRef, BuildError> {
        self.hook.checkpoint()?;
        use regex_syntax::hir::{Class, HirKind::*};

        match *expr.kind() {
            Empty => self.c_empty(),
            Literal(hir::Literal(ref bytes)) => self.c_literal(bytes),
            Class(Class::Bytes(ref c)) => self.c_byte_class(c),
            Class(Class::Unicode(ref c)) => self.c_unicode_class(c),
            Look(ref look) => self.c_look(look),
            Repetition(ref rep) => self.c_repetition(rep),
            Capture(ref c) => self.c_cap(c.index, c.name.as_deref(), &c.sub),
            Concat(ref es) => self.c_concat(es.iter().map(|e| self.c(e))),
            Alternation(ref es) => self.c_alt_slice(es),
        }
    }

    fn c_concat<I>(&self, mut it: I) -> Result<ThompsonRef, BuildError>
    where
        I: DoubleEndedIterator<Item = Result<ThompsonRef, BuildError>>,
    {
        let first = if self.is_reverse() { it.next_back() } else { it.next() };
        let ThompsonRef { start, mut end } = match first {
            Some(result) => result?,
            None => return self.c_empty(),
        };
        loop {
            let next =
                if self.is_reverse() { it.next_back() } else { it.next() };
            let compiled = match next {
                Some(result) => result?,
                None => break,
            };
            self.patch(end, compiled.start)?;
            end = compiled.end;
        }
        Ok(ThompsonRef { start, end })
    }

    fn c_alt_slice(&self, exprs: &[Hir]) -> Result<ThompsonRef, BuildError> {
        // self.c_alt_iter(exprs.iter().map(|e| self.c(e)))
        let literal_count = exprs
            .iter()
            .filter(|e| {
                matches!(*e.kind(), hir::HirKind::Literal(hir::Literal(_)))
            })
            .count();
        if literal_count <= 1 || literal_count < exprs.len() {
            return self.c_alt_iter(exprs.iter().map(|e| self.c(e)));
        }

        let mut trie=NativeLiteralTrie::new(self.is_reverse(),&self.hook)?;
        for expr in exprs.iter() {
            let literal = match *expr.kind() {
                hir::HirKind::Literal(hir::Literal(ref bytes)) => bytes,
                _ => unreachable!(),
            };
            trie.add(literal)?;
        }
        trie.compile(&mut self.builder.borrow_mut())
    }

    fn c_alt_iter<I>(&self, mut it: I) -> Result<ThompsonRef, BuildError>
    where
        I: Iterator<Item = Result<ThompsonRef, BuildError>>,
    {
        let first = match it.next() {
            None => return self.c_fail(),
            Some(result) => result?,
        };
        let second = match it.next() {
            None => return Ok(first),
            Some(result) => result?,
        };

        let union = self.add_union()?;
        let end = self.add_empty()?;
        self.patch(union, first.start)?;
        self.patch(first.end, end)?;
        self.patch(union, second.start)?;
        self.patch(second.end, end)?;
        for result in it {
            self.hook.checkpoint()?;
            let compiled = result?;
            self.patch(union, compiled.start)?;
            self.patch(compiled.end, end)?;
        }
        Ok(ThompsonRef { start: union, end })
    }

    fn c_cap(
        &self,
        index: u32,
        name: Option<&str>,
        expr: &Hir,
    ) -> Result<ThompsonRef, BuildError> {
        match self.config.get_which_captures() {
            // No capture states means we always skip them.
            WhichCaptures::None => return self.c(expr),
            // Implicit captures states means we only add when index==0 since
            // index==0 implies the group is implicit.
            WhichCaptures::Implicit if index > 0 => return self.c(expr),
            _ => {}
        }

        let start = self.add_capture_start(index, name)?;
        let inner = self.c(expr)?;
        let end = self.add_capture_end(index)?;
        self.patch(start, inner.start)?;
        self.patch(inner.end, end)?;
        Ok(ThompsonRef { start, end })
    }

    fn c_repetition(
        &self,
        rep: &hir::Repetition,
    ) -> Result<ThompsonRef, BuildError> {
        match (rep.min, rep.max) {
            (0, Some(1)) => self.c_zero_or_one(&rep.sub, rep.greedy),
            (min, None) => self.c_at_least(&rep.sub, rep.greedy, min),
            (min, Some(max)) if min == max => self.c_exactly(&rep.sub, min),
            (min, Some(max)) => self.c_bounded(&rep.sub, rep.greedy, min, max),
        }
    }

    fn c_bounded(
        &self,
        expr: &Hir,
        greedy: bool,
        min: u32,
        max: u32,
    ) -> Result<ThompsonRef, BuildError> {
        let prefix = self.c_exactly(expr, min)?;
        if min == max {
            return Ok(prefix);
        }

        // It is tempting here to compile the rest here as a concatenation
        // of zero-or-one matches. i.e., for `a{2,5}`, compile it as if it
        // were `aaa?a?a?`. The problem here is that it leads to this program:
        //
        //     >000000: 61 => 01
        //      000001: 61 => 02
        //      000002: union(03, 04)
        //      000003: 61 => 04
        //      000004: union(05, 06)
        //      000005: 61 => 06
        //      000006: union(07, 08)
        //      000007: 61 => 08
        //      000008: MATCH
        //
        // And effectively, once you hit state 2, the epsilon closure will
        // include states 3, 5, 6, 7 and 8, which is quite a bit. It is better
        // to instead compile it like so:
        //
        //     >000000: 61 => 01
        //      000001: 61 => 02
        //      000002: union(03, 08)
        //      000003: 61 => 04
        //      000004: union(05, 08)
        //      000005: 61 => 06
        //      000006: union(07, 08)
        //      000007: 61 => 08
        //      000008: MATCH
        //
        // So that the epsilon closure of state 2 is now just 3 and 8.
        let empty = self.add_empty()?;
        let mut prev_end = prefix.end;
        for _ in min..max {
            let union = if greedy {
                self.add_union()
            } else {
                self.add_union_reverse()
            }?;
            let compiled = self.c(expr)?;
            self.patch(prev_end, union)?;
            self.patch(union, compiled.start)?;
            self.patch(union, empty)?;
            prev_end = compiled.end;
        }
        self.patch(prev_end, empty)?;
        Ok(ThompsonRef { start: prefix.start, end: empty })
    }

    fn c_at_least(
        &self,
        expr: &Hir,
        greedy: bool,
        n: u32,
    ) -> Result<ThompsonRef, BuildError> {
        if n == 0 {
            // When the expression cannot match the empty string, then we
            // can get away with something much simpler: just one 'alt'
            // instruction that optionally repeats itself. But if the expr
            // can match the empty string... see below.
            if expr.properties().minimum_len().map_or(false, |len| len > 0) {
                let union = if greedy {
                    self.add_union()
                } else {
                    self.add_union_reverse()
                }?;
                let compiled = self.c(expr)?;
                self.patch(union, compiled.start)?;
                self.patch(compiled.end, union)?;
                return Ok(ThompsonRef { start: union, end: union });
            }

            // What's going on here? Shouldn't x* be simpler than this? It
            // turns out that when implementing leftmost-first (Perl-like)
            // match semantics, x* results in an incorrect preference order
            // when computing the transitive closure of states if and only if
            // 'x' can match the empty string. So instead, we compile x* as
            // (x+)?, which preserves the correct preference order.
            //
            // See: https://github.com/rust-lang/regex/issues/779
            let compiled = self.c(expr)?;
            let plus = if greedy {
                self.add_union()
            } else {
                self.add_union_reverse()
            }?;
            self.patch(compiled.end, plus)?;
            self.patch(plus, compiled.start)?;

            let question = if greedy {
                self.add_union()
            } else {
                self.add_union_reverse()
            }?;
            let empty = self.add_empty()?;
            self.patch(question, compiled.start)?;
            self.patch(question, empty)?;
            self.patch(plus, empty)?;
            Ok(ThompsonRef { start: question, end: empty })
        } else if n == 1 {
            let compiled = self.c(expr)?;
            let union = if greedy {
                self.add_union()
            } else {
                self.add_union_reverse()
            }?;
            self.patch(compiled.end, union)?;
            self.patch(union, compiled.start)?;
            Ok(ThompsonRef { start: compiled.start, end: union })
        } else {
            let prefix = self.c_exactly(expr, n - 1)?;
            let last = self.c(expr)?;
            let union = if greedy {
                self.add_union()
            } else {
                self.add_union_reverse()
            }?;
            self.patch(prefix.end, last.start)?;
            self.patch(last.end, union)?;
            self.patch(union, last.start)?;
            Ok(ThompsonRef { start: prefix.start, end: union })
        }
    }

    fn c_zero_or_one(
        &self,
        expr: &Hir,
        greedy: bool,
    ) -> Result<ThompsonRef, BuildError> {
        let union =
            if greedy { self.add_union() } else { self.add_union_reverse() }?;
        let compiled = self.c(expr)?;
        let empty = self.add_empty()?;
        self.patch(union, compiled.start)?;
        self.patch(union, empty)?;
        self.patch(compiled.end, empty)?;
        Ok(ThompsonRef { start: union, end: empty })
    }

    fn c_exactly(
        &self,
        expr: &Hir,
        n: u32,
    ) -> Result<ThompsonRef, BuildError> {
        let it = (0..n).map(|_| self.c(expr));
        self.c_concat(it)
    }

    fn c_byte_class(
        &self,
        cls: &hir::ClassBytes,
    ) -> Result<ThompsonRef, BuildError> {
        let end = self.add_empty()?;
        let mut trans=Vec::new();self.hook.room(&mut trans,cls.ranges().len())?;
        for r in cls.iter() {
            self.hook.push(&mut trans,Transition {
                start: r.start(),
                end: r.end(),
                next: end,
            })?;
        }
        Ok(ThompsonRef { start: self.add_sparse(trans)?, end })
    }

    fn c_unicode_class(
        &self,
        cls: &hir::ClassUnicode,
    ) -> Result<ThompsonRef, BuildError> {
        self.native_frontier("unicode_class_enter");
        let _frontier=NativeFrontier{compiler:self,stage:"unicode_class_return_or_error"};
        // If all we have are ASCII ranges wrapped in a Unicode package, then
        // there is zero reason to bring out the big guns. We can fit all ASCII
        // ranges within a single sparse state.
        if cls.is_ascii() {
            let end = self.add_empty()?;
            let mut trans=Vec::new();self.hook.room(&mut trans,cls.ranges().len())?;
            for r in cls.iter() {
                // The unwraps below are OK because we've verified that this
                // class only contains ASCII codepoints.
                self.hook.push(&mut trans,Transition {
                    // FIXME(1.59): use the 'TryFrom<char> for u8' impl.
                    start: u8::try_from(u32::from(r.start())).unwrap(),
                    end: u8::try_from(u32::from(r.end())).unwrap(),
                    next: end,
                })?;
            }
            Ok(ThompsonRef { start: self.add_sparse(trans)?, end })
        } else if self.is_reverse(){unreachable!("native Pat factory seals forward search")} else {
            // In the forward direction, we always shrink our UTF-8 automata
            // because we can stream it right into the UTF-8 compiler. There
            // is almost no downside (in either memory or time) to using this
            // approach.
            let mut builder = self.builder.borrow_mut();
            let mut utf8_state = self.utf8_state.borrow_mut();
            let mut utf8c =
                NativeUtf8Compiler::new(&mut *builder,&mut *utf8_state,&self.hook)?;
            for rng in cls.iter() {
                self.hook.checkpoint()?;
                for seq in Utf8Sequences::new(rng.start(), rng.end()) {
                    utf8c.add(seq.as_slice())?;
                }
            }
            utf8c.finish()
        }

        // For reference, the code below is the "naive" version of compiling a
        // UTF-8 automaton. It is deliciously simple (and works for both the
        // forward and reverse cases), but will unfortunately produce very
        // large NFAs. When compiling a forward automaton, the size difference
        // can sometimes be an order of magnitude. For example, the '\w' regex
        // will generate about ~3000 NFA states using the naive approach below,
        // but only 283 states when using the approach above. This is because
        // the approach above actually compiles a *minimal* (or near minimal,
        // because of the bounded hashmap for reusing equivalent states) UTF-8
        // automaton.
        //
        // The code below is kept as a reference point in order to make it
        // easier to understand the higher level goal here. Although, it will
        // almost certainly bit-rot, so keep that in mind. Also, if you try to
        // use it, some of the tests in this module will fail because they look
        // for terser byte code produce by the more optimized handling above.
        // But the integration test suite should still pass.
        //
        // One good example of the substantial difference this can make is to
        // compare and contrast performance of the Pike VM when the code below
        // is active vs the code above. Here's an example to try:
        //
        //   regex-cli find match pikevm -b -p '(?m)^\w{20}' non-ascii-file
        //
        // With Unicode classes generated below, this search takes about 45s on
        // my machine. But with the compressed version above, the search takes
        // only around 1.4s. The NFA is also 20% smaller. This is in part due
        // to the compression, but also because of the utilization of 'sparse'
        // NFA states. They lead to much less state shuffling during the NFA
        // search.
        /*
        let it = cls
            .iter()
            .flat_map(|rng| Utf8Sequences::new(rng.start(), rng.end()))
            .map(|seq| {
                let it = seq
                    .as_slice()
                    .iter()
                    .map(|rng| self.c_range(rng.start, rng.end));
                self.c_concat(it)
            });
        self.c_alt_iter(it)
        */
    }

    fn c_look(&self, anchor: &hir::Look) -> Result<ThompsonRef, BuildError> {
        let look = match *anchor {
            hir::Look::Start => Look::Start,
            hir::Look::End => Look::End,
            hir::Look::StartLF => Look::StartLF,
            hir::Look::EndLF => Look::EndLF,
            hir::Look::StartCRLF => Look::StartCRLF,
            hir::Look::EndCRLF => Look::EndCRLF,
            hir::Look::WordAscii => Look::WordAscii,
            hir::Look::WordAsciiNegate => Look::WordAsciiNegate,
            hir::Look::WordUnicode => Look::WordUnicode,
            hir::Look::WordUnicodeNegate => Look::WordUnicodeNegate,
            hir::Look::WordStartAscii => Look::WordStartAscii,
            hir::Look::WordEndAscii => Look::WordEndAscii,
            hir::Look::WordStartUnicode => Look::WordStartUnicode,
            hir::Look::WordEndUnicode => Look::WordEndUnicode,
            hir::Look::WordStartHalfAscii => Look::WordStartHalfAscii,
            hir::Look::WordEndHalfAscii => Look::WordEndHalfAscii,
            hir::Look::WordStartHalfUnicode => Look::WordStartHalfUnicode,
            hir::Look::WordEndHalfUnicode => Look::WordEndHalfUnicode,
        };
        let id = self.add_look(look)?;
        Ok(ThompsonRef { start: id, end: id })
    }

    fn c_literal(&self, bytes: &[u8]) -> Result<ThompsonRef, BuildError> {
        self.c_concat(bytes.iter().copied().map(|b| self.c_range(b, b)))
    }

    fn c_range(&self, start: u8, end: u8) -> Result<ThompsonRef, BuildError> {
        let id = self.add_range(start, end)?;
        Ok(ThompsonRef { start: id, end: id })
    }

    fn c_empty(&self) -> Result<ThompsonRef, BuildError> {
        let id = self.add_empty()?;
        Ok(ThompsonRef { start: id, end: id })
    }

    fn c_fail(&self) -> Result<ThompsonRef, BuildError> {
        let id = self.add_fail()?;
        Ok(ThompsonRef { start: id, end: id })
    }

    // The below helpers are meant to be simple wrappers around the
    // corresponding Builder methods. For the most part, they let us write
    // 'self.add_foo()' instead of 'self.builder.borrow_mut().add_foo()', where
    // the latter is a mouthful. Some of the methods do inject a little bit
    // of extra logic. e.g., Flipping look-around operators when compiling in
    // reverse mode.

    fn patch(&self, from: StateID, to: StateID) -> Result<(), BuildError> {
        self.builder.borrow_mut().patch(from, to)
    }

    fn start_pattern(&self) -> Result<PatternID, BuildError> {
        self.builder.borrow_mut().start_pattern()
    }

    fn finish_pattern(
        &self,
        start_id: StateID,
    ) -> Result<PatternID, BuildError> {
        self.builder.borrow_mut().finish_pattern(start_id)
    }

    fn add_empty(&self) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_empty()
    }

    fn add_range(&self, start: u8, end: u8) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_range(Transition {
            start,
            end,
            next: StateID::ZERO,
        })
    }

    fn add_sparse(
        &self,
        ranges: Vec<Transition>,
    ) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_sparse(ranges)
    }

    fn add_look(&self, mut look: Look) -> Result<StateID, BuildError> {
        if self.is_reverse() {
            look = look.reversed();
        }
        self.builder.borrow_mut().add_look(StateID::ZERO, look)
    }

    fn add_union(&self) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_union(vec![])
    }

    fn add_union_reverse(&self) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_union_reverse(vec![])
    }

    fn add_capture_start(
        &self,
        capture_index: u32,
        name: Option<&str>,
    ) -> Result<StateID, BuildError> {
        let name=if let Some(name)=name{
            self.hook.reserve(||name.len().checked_add(2*core::mem::size_of::<usize>())?.checked_add(core::mem::align_of::<usize>()-1)?.checked_add(64))?;
            Some(Arc::<str>::from(name))
        }else{None};
        self.builder.borrow_mut().add_capture_start(
            StateID::ZERO,
            capture_index,
            name,
        )
    }

    fn add_capture_end(
        &self,
        capture_index: u32,
    ) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_capture_end(StateID::ZERO, capture_index)
    }

    fn add_fail(&self) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_fail()
    }

    fn add_match(&self) -> Result<StateID, BuildError> {
        self.builder.borrow_mut().add_match()
    }

    fn is_reverse(&self) -> bool {
        self.config.get_reverse()
    }
}

#[cfg(test)]mod frozen_builder_physical_controls{
 use super::*;use core::sync::atomic::{AtomicUsize,Ordering};
 struct Observe{stage:AtomicUsize,frozen:AtomicUsize}
 impl regex_syntax::native_admission::Admission for Observe{
  fn checkpoint(&self)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}fn reserve(&self,_:usize)->Result<(),regex_syntax::native_admission::Refused>{Ok(())}fn overflow(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}fn allocation_failed(&self)->regex_syntax::native_admission::Refused{regex_syntax::native_admission::Refused}
  fn begin_retained_phase(&self)->Result<Option<u64>,regex_syntax::native_admission::Refused>{Ok(Some(1))}
  fn checkpoint_retained_phase(&self,_:u64,_:usize)->Result<(),regex_syntax::native_admission::Refused>{assert_eq!(self.stage.swap(1,Ordering::SeqCst),0);Ok(())}
  fn checkpoint_retained_builder_phase(&self,_:u64,n:usize)->Result<(),regex_syntax::native_admission::Refused>{assert_eq!(self.stage.swap(2,Ordering::SeqCst),1);self.frozen.store(n,Ordering::SeqCst);Ok(())}
 }
 #[test]fn actual_frozen_builder_drops_utf8_memo_keeps_complete_named_builder_and_unchanged_final_nfa(){
  let hir=regex_syntax::Parser::new().parse(r"(?P<name>\w+)|[\p{Greek}\p{Cyrillic}]+(\s*)").unwrap();let observer=Arc::new(Observe{stage:AtomicUsize::new(0),frozen:AtomicUsize::new(0)});let hook=Hook(Some(observer.clone()));let mut phase=hook.retained_phase().unwrap();let retained=hir.native_retained_bytes_admitted(&hook).unwrap();phase.checkpoint(&hook,retained).unwrap();
  let actual=NativeCompiler{config:Config::default(),builder:RefCell::new(NativeBuilder::new(&hook).unwrap()),utf8_state:RefCell::new(NativeUtf8State::new()),hook:hook.clone()};let nfa=actual.compile(&[&hir],Some((&mut phase,retained))).unwrap();assert_eq!(actual.utf8_state.borrow().native_frontier_backing(),Some(((0,0,0),0,0)),"the actual old memo buffers were destroyed before final copy");let frozen=actual.builder.borrow().native_retained_bytes().unwrap();assert!(frozen>0);assert_eq!(observer.frozen.load(Ordering::SeqCst),retained+frozen);let subtotal=actual.builder.borrow().native_frontier_backing().unwrap();assert!(frozen>subtotal.0+subtotal.1+subtotal.2+subtotal.3,"named Arc and allocation envelopes remain funded, not telemetry scalars");let expected=NFA::compiler().build_from_hir(&hir).unwrap();assert_eq!(alloc::format!("{:?}",nfa.states()),alloc::format!("{:?}",expected.states()));assert_eq!(nfa.group_info().to_name(PatternID::ZERO,1),Some("name"));
 }
 #[test]fn actual_public_hir_builder_keeps_old_conservative_phase_contract(){
  let hir=regex_syntax::Parser::new().parse(r"(\w+)\s*").unwrap();let observer=Arc::new(Observe{stage:AtomicUsize::new(0),frozen:AtomicUsize::new(0)});let hook=Hook(Some(observer.clone()));let actual=NFA::from_hir_admitted(&hir,None,&hook).unwrap();let expected=NFA::compiler().build_from_hir(&hir).unwrap();assert_eq!(observer.stage.load(Ordering::SeqCst),0);assert_eq!(observer.frozen.load(Ordering::SeqCst),0);assert_eq!(alloc::format!("{:?}",actual.states()),alloc::format!("{:?}",expected.states()));
 }
}
