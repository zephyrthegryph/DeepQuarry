//! Admitted forward regex program and operation-local search executor.
//! Uses the existing syntax/Thompson/Pike algorithms, without meta Regex's
//! hidden per-thread scratch pool. No lender/hook is stored in the program.
use alloc::vec::Vec;
use regex_syntax::native_admission::{Hook,Refused};
use crate::{Input,PatternID,nfa::thompson::{NFA,BuildError,pikevm::{PikeVM,AdmittedCache}},util::primitives::NonMaxUsize};

#[derive(Clone,Debug)]
/// Typed failure; no unadmitted formatted error string is manufactured.
pub enum CompileError{
 /// The actual hook retains its first operational error.
 Refused(Refused),
 /// The unchanged syntax kernel rejected the pattern.
 Syntax(regex_syntax::Error),
 /// The unchanged Thompson invariants or size limit rejected construction.
 Build(BuildError),
}
impl From<Refused> for CompileError{fn from(actual:Refused)->Self{Self::Refused(actual)}}

#[derive(Clone,Debug)]
/// Immutable compiled forward program; it retains no search scratch or lender.
pub struct Regex{actual:PikeVM}
impl Regex{
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn retained_bytes(&self)->Option<usize>{self.actual.get_nfa().native_retained_bytes()}

 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn compile(pattern:&str,size_limit:Option<usize>,hook:&Hook<'_>)->Result<Self,CompileError>{
  if !hook.active(){return Err(CompileError::Refused(hook.allocation_failed()))}
  hook.checkpoint()?;
  let mut phase=hook.retained_phase()?;
  // The HIR, parser and Thompson/UTF8 compiler owners are physically gone
  // before settlement; only the returned immutable NFA remains live.
  let compiled=(||{
   let hir=regex_syntax::ParserBuilder::new().parse_admitted(pattern,hook)?.map_err(CompileError::Syntax)?;
   // The successful parser returned this sole HIR. Its AST, native translator
   // and ParserBuilder temporary are physically gone before the next compiler
   // begins. Keep their exact HIR product, not every dead growth frontier.
   let retained=hir.native_retained_bytes_admitted(hook)?;
   phase.checkpoint(hook,retained)?;
   let nfa=NFA::from_hir_admitted_with_retained(&hir,size_limit,hook,&mut phase,retained).map_err(CompileError::Build)?;
   let actual=PikeVM::new_from_nfa_admitted(nfa,hook).map_err(CompileError::Build)?;
   hook.checkpoint()?;Ok::<Self,CompileError>(Self{actual})
  })();
  let compiled=match compiled{
   Ok(compiled)=>compiled,
   Err(CompileError::Syntax(error))=>{
    // The parser/AST/translator closure is physically gone. Its SAME typed
    // semantic error retains only its actual pattern backing. Operational
    // failures and unsupported error payloads remain conservative.
    hook.checkpoint()?;
    if let Some(retained)=error.native_retained_bytes(){phase.settle(hook,retained)?;}
    return Err(CompileError::Syntax(error));
   }
   Err(first)=>return Err(first),
  };
  let retained=compiled.retained_bytes().ok_or_else(||hook.overflow())?;
  phase.settle(hook,retained)?;Ok(compiled)
 }
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn capture_len(&self)->usize{self.actual.get_nfa().group_info().group_len(PatternID::ZERO)}
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn capture_name(&self,index:usize)->Option<&str>{self.actual.get_nfa().group_info().to_name(PatternID::ZERO,index)}
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn capture_index(&self,name:&str)->Option<usize>{self.actual.get_nfa().group_info().to_index(PatternID::ZERO,name)}
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn executor<'r,'h>(&'r self,hook:&Hook<'h>)->Result<Executor<'r,'h>,Refused>{
  if !hook.active(){return Err(hook.allocation_failed())}
  let mut slots=Vec::new();hook.resize(&mut slots,self.actual.get_nfa().group_info().slot_len(),None)?;
  let cache=AdmittedCache::new(&self.actual,hook.clone())?;
  Ok(Executor{program:self,slots,cache})
 }
}
/// Borrowed operation-local search scratch; it cannot outlive the program.
#[derive(Debug)]
pub struct Executor<'r,'h>{program:&'r Regex,slots:Vec<Option<NonMaxUsize>>,cache:AdmittedCache<'h>}
impl Executor<'_,'_>{
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn search<'s>(&'s mut self,input:&Input<'_>)->Result<Option<Slots<'s>>,Refused>{
  self.slots.fill(None);
  if self.program.actual.search_slots_admitted(&mut self.cache,input,&mut self.slots)?.is_none(){return Ok(None)}
  Ok(Some(Slots{actual:&self.slots}))
 }
}
#[derive(Clone,Copy,Debug)]
/// Borrow of the actual capture slots from one completed engine search.
pub struct Slots<'a>{actual:&'a[Option<NonMaxUsize>]}
impl Slots<'_>{
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn len(&self)->usize{self.actual.len()/2}
 /// Uses the existing engine with the same preadmitted program or scratch.
 pub fn get(&self,index:usize)->Option<(usize,usize)>{
  let at=index.checked_mul(2)?;
  let start=self.actual.get(at)?.as_ref()?.get();let end=self.actual.get(at.checked_add(1)?)?.as_ref()?.get();Some((start,end))
 }
}
