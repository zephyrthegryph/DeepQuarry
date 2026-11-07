//! Retained assembly over the SAME primary layout, frame and commit kernels.
//! This internal DATA owner cannot issue acquisition, EOF or frontend roles.
use super::*;
use crate::span_token_storage::{LoanedTokenPages, PackedTokenBlocks};
use std::io;
use super::committed_items::{OriginalCommittedItems, OriginalItems};
use super::{demand_frames::NativeOriginalPrimaryFrames,demand_layout::NativeDemandLayoutCursor};

/// Owned SAME live primary-header locator. It shares the existing actual
/// layout resource owner (no new nonce/cache), never an arena/token borrow.
/// It is parser DATA only; frontend source/model grants remain separate.
#[derive(Clone)]pub struct OriginalPrimaryLiveHeader{
 owner:super::demand_layout::NativePrimaryLayoutIdentity,
 header:Span,open:Span,open_ordinal:usize,indent:usize,kind:ItemKind,prior_outer:Option<usize>,
}
/// Minimal producer identity retained after a completed formal is checked.
/// Active header coordinates remain on OriginalPrimaryLiveHeader only.
pub struct OriginalPrimaryProducerIdentity(super::demand_layout::NativePrimaryLayoutIdentity);
impl Default for OriginalPrimaryProducerIdentity {
 fn default() -> Self {
  // This sentinel cannot match a real primary or authorize a source fact.
  Self(super::demand_layout::NativePrimaryLayoutIdentity::unbound_completed())
 }
}
impl OriginalPrimaryProducerIdentity {
 /// Move a bound owner out, leaving the compact unbound sentinel in place.
 /// The existing LayoutOwner still frees the Arc before its final lease.
 pub fn take(&mut self) -> Option<Self> { self.0.take_completed().map(Self) }
 pub(super) fn matches_owner(&self,owner:&super::demand_layout::NativePrimaryLayoutIdentity)->bool{self.0.matches_completed(owner)}
}
impl OriginalPrimaryLiveHeader{
 pub fn into_producer_identity(self)->OriginalPrimaryProducerIdentity{OriginalPrimaryProducerIdentity(self.owner)}
 pub fn start(&self)->usize{self.header.start}
 pub fn same_header(&self, other:&Self)->bool{
  self.owner.same(&other.owner)&&self.header==other.header&&self.open_ordinal==other.open_ordinal
 }
 pub(super) fn matches_owner(&self,owner:&super::demand_layout::NativePrimaryLayoutIdentity)->bool{self.owner.same(owner)}
 pub fn header_prefix_span(&self)->Span{self.header}pub fn argument_start(&self)->usize{self.open.end}pub fn open_span(&self)->Span{self.open}pub fn kind(&self)->ItemKind{self.kind}pub fn prior_outer_block(&self)->Option<usize>{self.prior_outer}
}
/// Only ordinals strictly before `next` were checked and found not to open
/// this scope. The opening token itself, if any, is still a candidate.
#[derive(Clone, Copy)]
struct LiveCallablePrefix {
 start:usize,
 indent:usize,
 next:usize,
 non_callable:bool,
}
#[cfg(debug_assertions)]
struct PrimaryTapeTrace<'a>(&'a PrimaryTokenTape);
#[cfg(debug_assertions)]
impl std::fmt::Debug for PrimaryTapeTrace<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.0 {
            PrimaryTokenTape::Packed(tokens) => std::fmt::Debug::fmt(&tokens.trace_retention(), f),
            PrimaryTokenTape::Loaned(tokens) => std::fmt::Debug::fmt(&tokens.trace_retention(), f),
        }
    }
}

/// Observe exact completed BODY lines in output order. The census retains
/// scalars only and does not participate in parsing or owner publication.
#[cfg(debug_assertions)]
#[derive(Default, Debug)]
struct BodyLiteralCandidates {
    next_row: usize,
    body_rows: usize,
    projectable_rows: usize,
    raw_capacity_per_row_upper: usize,
    observed_standalone_rows: usize,
    observed_standalone_payload_bytes: usize,
}
#[cfg(debug_assertions)]
impl BodyLiteralCandidates {
    fn observe(&mut self, line: Span, in_body: bool, source: &str, rows: OriginalLiteralRows<'_>) {
        while let Some((span, data)) = rows.get(self.next_row) {
            if span.end > line.end { break; }
            self.next_row += 1;
            if !in_body || span.start < line.start { continue; }
            self.body_rows += 1;
            if data.is_projected(){continue}
            if source.get(span.range()) != Some(data.raw().expect("full candidate spelling")) { continue; }
            if let Some((raw, standalone)) = data.trace_source_projection() {
                self.projectable_rows += 1;
                self.raw_capacity_per_row_upper = self.raw_capacity_per_row_upper.saturating_add(raw);
                if let Some(bytes) = standalone {
                    self.observed_standalone_rows += 1;
                    self.observed_standalone_payload_bytes = self.observed_standalone_payload_bytes.saturating_add(bytes);
                }
            }
        }
    }
}

enum PrimaryTokenTape {
    Packed(PackedTokenBlocks),
    Loaned(LoanedTokenPages),
}
impl PrimaryTokenTape {
    fn window(&self) -> TokenWindow<'_> {
        match self {
            Self::Packed(tokens) => tokens.window(),
            Self::Loaned(tokens) => TokenWindow::from_loaned(tokens),
        }
    }

    fn push(&mut self, token: SpanToken, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        match self {
            Self::Packed(tokens) => tokens.push(token, a),
            Self::Loaned(tokens) => tokens.push(token, a),
        }
    }

    fn finish(self, a: &crate::SettingAdmission<'_>) -> io::Result<crate::SharedSpanTokens> {
        match self {
            Self::Packed(tokens) => crate::SharedSpanTokens::from_packed_using(tokens, a),
            Self::Loaned(tokens) => crate::SharedSpanTokens::from_loaned_using(tokens, a),
        }
    }
}

pub struct OriginalPrimaryDemand<'a,'observer,'budget>{
 frames:Option<NativeOriginalPrimaryFrames<'a,'budget>>,
 layout:Option<NativeDemandLayoutCursor<'a,'budget>>,
 tokens:PrimaryTokenTape,diagnostics:Vec<Diagnostic>,lexical:Vec<Diagnostic>,literal_facts:OriginalPrimaryLiteralFacts,literal_facts_issued:bool,
 frontier:usize,ended:bool,failed:bool,
 live_callable_prefix:Option<LiveCallablePrefix>,
 #[cfg(debug_assertions)]
 body_literal_candidates: Option<BodyLiteralCandidates>,
 // Physical rows above are destroyed before the actual root below.
 original:OriginalParseState<'a,'observer,'budget>,
}
/// Completed compact rows from the SAME actual primary producer. The caller
/// still supplies the actual emitted source and existing acquisition proof.
pub struct OriginalCommittedPrimary {
 items: OriginalCommittedItems,
 tokens: crate::SharedSpanTokens,
 diagnostics: Vec<Diagnostic>,
 literal_facts: Option<OriginalPrimaryLiteralFacts>,
 primary_owner: demand_layout::NativePrimaryLayoutIdentity,
 fatal: Option<OriginalDeclarationFatal>,
 unavailable: Option<&'static str>,
 observer_stop: Option<Span>,
 lease: crate::SettingRootLease,
}
impl OriginalCommittedPrimary {
 pub fn items<'a>(&'a self,source:&'a str)->io::Result<OriginalItems<'a>>{self.items.view(source)}
 pub fn tokens(&self)->&crate::SharedSpanTokens{&self.tokens}
 pub fn diagnostics(&self)->&[Diagnostic]{&self.diagnostics}
 pub fn observer_stop(&self)->Option<Span>{self.observer_stop}
 pub fn fatal(&self)->Option<OriginalDeclarationFatal>{self.fatal}
 pub fn unavailable(&self)->Option<&'static str>{self.unavailable}
 pub fn same_primary_header(&self,header:&OriginalPrimaryLiveHeader)->bool{header.matches_owner(&self.primary_owner)}
 pub fn same_primary_producer(&self,identity:&OriginalPrimaryProducerIdentity)->bool{identity.matches_owner(&self.primary_owner)}
 pub fn visit_primary_producer_storage(&self,visit:impl FnMut(usize,usize,usize)){self.primary_owner.visit_storage(visit)}
 pub fn take_original_literal_fact_owner_using(&mut self,a:&crate::SettingAdmission<'_>)->io::Result<Option<OriginalPrimaryLiteralFacts>>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  if !a.matches_lease_domain(&self.lease)||self.literal_facts.as_ref().is_some_and(|facts|!facts.is_admitted_by(a)){
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"committed primary fact transfer uses another admission"))
  }
  Ok(self.literal_facts.take())
 }
 pub fn into_parts(self)->(OriginalCommittedItems,crate::SpanTokenStorage,Vec<Diagnostic>,Option<OriginalDeclarationFatal>,Option<&'static str>,crate::SettingRootLease){
  (self.items,self.tokens.into(),self.diagnostics,self.fatal,self.unavailable,self.lease)
 }
}

struct FinishedPrimary<'a,'budget> {
 tokens: crate::SharedSpanTokens,
 diagnostics: Vec<Diagnostic>,
 literal_facts: Option<OriginalPrimaryLiteralFacts>,
 primary_owner: demand_layout::NativePrimaryLayoutIdentity,
 fatal: Option<OriginalDeclarationFatal>,
 unavailable: Option<&'static str>,
 observer_stop: Option<Span>,
 storage: original_storage::Storage<'a,'budget>,
}

impl<'a,'observer,'budget> OriginalPrimaryDemand<'a,'observer,'budget>{
 pub fn new(a:&'a crate::SettingAdmission<'budget>,observer:Option<&'observer mut dyn OriginalDeclarationHeaderObserver>)->io::Result<Self>{
  Self::new_with_mode(a,observer,false)
 }
 pub fn new_committed(a:&'a crate::SettingAdmission<'budget>,observer:Option<&'observer mut dyn OriginalDeclarationHeaderObserver>)->io::Result<Self>{
  Self::new_with_mode(a,observer,true)
 }
 fn new_with_mode(a:&'a crate::SettingAdmission<'budget>,observer:Option<&'observer mut dyn OriginalDeclarationHeaderObserver>,committed:bool)->io::Result<Self>{
  let original=OriginalParseState{storage:original_storage::Storage::new(a)?,fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:observer.map(std::cell::RefCell::new),observer_stop:Default::default(),first_outer_block:Default::default()};
  Ok(Self{frames:Some(NativeOriginalPrimaryFrames::new_with_mode(a,committed)?),layout:Some(NativeDemandLayoutCursor::new(a)?),tokens:PrimaryTokenTape::Packed(PackedTokenBlocks::new(a)?),diagnostics:Vec::new(),lexical:Vec::new(),literal_facts:OriginalPrimaryLiteralFacts::new(a)?,literal_facts_issued:true,frontier:0,ended:false,failed:false,live_callable_prefix:None,
   #[cfg(debug_assertions)]
   body_literal_candidates: std::env::var_os("DMB_ORIGINAL_TRACE_BODY_LITERAL_CANDIDATES").map(|_| BodyLiteralCandidates::default()),
   original})
 }
 /// Enable resource-only spelling projection before any actual token.
 pub fn enable_body_spelling_projection(&mut self,owner:crate::OriginalLiteralProjectionOwner)->io::Result<()>{
  if !self.tokens.window().is_empty(){return Err(io::ErrorKind::InvalidInput.into())}
  self.literal_facts.enable_projection(owner)
 }
 /// Enable immutable token DATA loans before the first actual adoption.
 /// The preprocessor must independently bind its real source/output receipts.
 pub fn enable_original_page_loans(&mut self) -> io::Result<()> {
  if self.failed || self.ended || self.frontier != 0 || !self.tokens.window().is_empty()
      || !matches!(self.tokens, PrimaryTokenTape::Packed(_)) {
   return Err(io::ErrorKind::InvalidInput.into());
  }
  self.tokens=PrimaryTokenTape::Loaned(LoanedTokenPages::new(self.original.storage.a)?);
  Ok(())
 }

 /// Supply one neutral page at its original token ordinal. This does not
 /// advance the visible frontier or authorize a source or an EOF.
 pub fn stage_original_token_page(&mut self, first:usize, loan:crate::OriginalTokenPageLoan) -> io::Result<()> {
  if self.failed || self.ended || self.original.stopped() {
   return Err(io::ErrorKind::InvalidInput.into());
  }
  let PrimaryTokenTape::Loaned(tokens)=&mut self.tokens else { return Err(io::ErrorKind::InvalidInput.into()); };
  let result=tokens.stage(first,loan,self.original.storage.a);
  if result.is_err(){self.failed=true;}
  result
 }

 /// Issue only after actual structural HeaderStart has established the
 /// current frame, and the SAME native token stream reaches callable '('.
 /// No following formal/default/body token is demanded by this operation.
 pub fn live_callable_header(&self,source:&str)->io::Result<Option<OriginalPrimaryLiveHeader>>{
  self.probe_live_callable_header(source,None).map(|(header,_)|header)
 }
 /// Receiver-only DATA fast path. The receiver must supply the same
 /// append-only emitted source it advances with. Independent callers that
 /// cannot promise that should use `live_callable_header`.
 pub fn resume_live_callable_header(&mut self,source:&str)->io::Result<Option<OriginalPrimaryLiveHeader>>{
  let (header,prefix)=self.probe_live_callable_header(source,self.live_callable_prefix)?;
  self.live_callable_prefix=prefix;
  Ok(header)
 }
 fn probe_live_callable_header(&self,source:&str,prefix:Option<LiveCallablePrefix>)
  ->io::Result<(Option<OriginalPrimaryLiveHeader>,Option<LiveCallablePrefix>)>{
  if self.failed||self.ended||self.original.stopped(){return Err(io::ErrorKind::InvalidInput.into())}
  // Keep the actual frame checkpoint and source check even when no new token
  // needs searching. A new scope may become visible after an opening arrived.
  let Some((start,indent,in_body,prior_outer))=self.frames.as_ref().ok_or(io::ErrorKind::InvalidInput)?.live_header_scope(&self.original)?else{return Ok((None,None))};
  if in_body{return Ok((None,None))}
  if source.len()!=self.frontier{return Err(io::ErrorKind::InvalidInput.into())}
  let tokens=self.span_tokens();
  let prefix=prefix.filter(|old|old.start==start&&old.indent==indent);
  if prefix.is_some_and(|old|old.non_callable){return Ok((None,prefix))}
  let first=prefix.map_or_else(||tokens.partition_point(|token|token.span.end<=start),|old|old.next);
  let opening=tokens.iter().enumerate().skip(first).find(|(_,token)|token.span.end>start&&matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator)&&token.text(source)=="(");
  let mut prefix=LiveCallablePrefix{start,indent,next:opening.map_or(tokens.len(),|(ordinal,_)|ordinal),non_callable:false};
  let Some((ordinal,open))=opening else{return Ok((None,Some(prefix)))};
  let header=Span::new(start,open.span.end);let kind=classify_primary_header(source,tokens,header,false);
  if !matches!(kind,ItemKind::Proc|ItemKind::Verb){
   // The judge reads only the immutable range through the first opening.
   prefix.non_callable=true;
   return Ok((None,Some(prefix)))
  }
  let live=OriginalPrimaryLiveHeader{owner:self.layout.as_ref().ok_or(io::ErrorKind::InvalidInput)?.identity(),header,open:open.span,open_ordinal:ordinal,indent,kind,prior_outer};
  Ok((Some(live),Some(prefix)))
 }
 /// Neutral live DATA loan only. The demand-source session first validates
 /// its actual raw-pull ordinalâ†’primary output-span association; this lookup
 /// cannot authenticate an external source/model or manufacture a missing row.
 pub fn original_literal_for_span(&self,span:Span)->io::Result<Option<crate::OriginalLiteralRef<'_>>>{
  if self.failed||self.ended{return Err(io::ErrorKind::InvalidInput.into())}let rows=self.literal_facts.rows();let at=rows.partition_point(|(actual,_)|actual.start<span.start);let data=rows.get(at).filter(|(actual,_)|*actual==span).map(|(_,data)|data);
 if data.is_some_and(|data|data.is_projected()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"live formal cannot borrow projected BODY DATA"))}Ok(data)
 }
 pub fn validate_live_header(&self,header:&OriginalPrimaryLiveHeader)->io::Result<()>{
  if self.failed||self.ended||self.original.stopped()||!self.layout.as_ref().ok_or(io::ErrorKind::InvalidInput)?.matches_identity(&header.owner){return Err(io::Error::new(io::ErrorKind::InvalidInput,"foreign or completed actual primary header owner"))}
  let Some((start,indent,in_body,_))=self.frames.as_ref().ok_or(io::ErrorKind::InvalidInput)?.live_header_scope(&self.original)?else{return Err(io::ErrorKind::InvalidInput.into())};if in_body||start!=header.header.start||indent!=header.indent||self.tokens.window().get(header.open_ordinal).is_none_or(|token|token.span!=header.open){return Err(io::ErrorKind::InvalidInput.into())}Ok(())
 }
 pub fn span_tokens(&self)->TokenWindow<'_>{self.tokens.window()}
 pub fn consumed_frontier(&self)->usize{self.frontier}
 /// Observer control only, never an authored syntax fatal or EOF/model grant.
 /// Actual frontend prefix issuance additionally requires the SAME genuine
 /// signature failure retained by its Tree consumer, as on the whole route.
 pub fn observer_stop_live_header(&mut self,header:&OriginalPrimaryLiveHeader)->io::Result<()>{
  self.validate_live_header(header)?;self.original.observer_stop.set(Some(Span::new(header.start(),self.frontier)));Ok(())
 }
 /// A live formal consumer owns the mutable observer loan while it pulls.
 /// Those actual tokens are inserted once but layout/complete-header callbacks
 /// cannot reenter it. On genuine Stop, seal THAT consumed formal frontier
 /// without running layout, requesting another token or pretending EOF.
 /// This remains control DATA; Tree requires the real private fatal receipt.
 pub fn observer_stop_live_header_at(&mut self,header:&OriginalPrimaryLiveHeader,actual_source:&str)->io::Result<()>{
  let result=(||{self.validate_live_header(header)?;if actual_source.len()<self.frontier||self.tokens.window().last().is_some_and(|token|token.span.end>actual_source.len()){return Err(io::ErrorKind::InvalidInput.into())}self.frontier=actual_source.len();self.original.observer_stop.set(Some(Span::new(header.start(),self.frontier)));Ok(())})();if result.is_err(){self.failed=true}result
 }
 fn failure(&self)->io::Error{self.original.operational.borrow_mut().take().or_else(||self.original.storage.take_failure()).unwrap_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual primary demand has no issued continuation"))}
 // Token issuance is the native cursor owner's responsibility. This private
 // insertion cannot turn arbitrary DATA into a source/current-model grant.
 pub fn token(&mut self,token:SpanToken)->io::Result<()>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot resume"))}if matches!(token.kind,TokenKind::Number|TokenKind::String|TokenKind::Resource|TokenKind::Interpolation){self.literal_facts_issued=false;}let status=self.token_inner(token);if status.is_err(){self.failed=true}status}
 // Called only by the actual final-token owner after constructing its genuine
 // scalar/static DATA. This is the SAME produced token occurrence, not a name
 // or spelling lookup, and no borrowed source/token survives another pull.
 /// Actual final-output producer's separate Colon/CloseColon fact, never a
 /// scalar literal. Source authority still belongs to the sealed source join.
 pub fn token_with_original_colon(&mut self,token:SpanToken,close:bool)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{if !matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator)||token.span.end.checked_sub(token.span.start)!=Some(1){return Err(io::ErrorKind::InvalidInput.into())}self.token_inner(token)?;self.literal_facts.append_actual_colon(token.span,close,self.original.storage.a)})();if result.is_err(){self.failed=true;}result
 }
 pub fn token_with_original_literal(&mut self,token:SpanToken,data:crate::OriginalLiteralData)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{if token.span.start>=token.span.end||!matches!((token.kind,data.kind()),(TokenKind::Number,"Int"|"Float")|(TokenKind::String,"String")|(TokenKind::Resource,"Resource")|(TokenKind::Interpolation,"InterpBegin"|"InterpPart"|"InterpEnd")){return Err(io::ErrorKind::InvalidInput.into())}let span=token.span;self.token_inner(token)?;self.literal_facts.append_actual(span,data,self.original.storage.a)})();if result.is_err(){self.failed=true}result
 }
 fn token_inner(&mut self,token:SpanToken)->io::Result<()>{
  if self.ended||self.original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual primary token demanded after stop"))}
  if self.tokens.window().last().is_some_and(|prior|prior.span.end>token.span.start){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual primary tokens are not a forward cursor"))}
  self.tokens.push(token,self.original.storage.a)
 }
 pub fn lexical(&mut self,span:Span,kind:DiagnosticKind,message:&str)->io::Result<()>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot resume"))}let status=self.lexical_inner(span,kind,message);if status.is_err(){self.failed=true}status}
 fn lexical_inner(&mut self,span:Span,kind:DiagnosticKind,message:&str)->io::Result<()>{
  if self.ended||self.original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"lexical producer advanced after primary stop"))}
  if !self.original.storage.diagnostic_parts(&mut self.lexical,span,kind,message){return Err(self.failure())}Ok(())
 }
 /// Accept a genuinely complete physical layout frontier. A pause is not EOF;
 /// a whole-source parser is never called to rediscover prior declarations.
 pub fn advance(&mut self,source:&str,actual_eof:bool)->io::Result<bool>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot resume"))}let status=self.advance_inner(source,actual_eof,None);if status.is_err(){self.failed=true}status}
 /// Streaming construction uses observer=None; this callback loan ends before
 /// the caller enters its SAME live formal parser. Retained state stays in place.
 pub fn advance_with_observer(&mut self,source:&str,actual_eof:bool,observer:&mut dyn OriginalDeclarationHeaderObserver)->io::Result<bool>{
  if self.failed||self.original.observer.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"scoped primary observer conflicts with retained observer or failed state"))}
  let status=self.advance_inner(source,actual_eof,Some(observer));if status.is_err(){self.failed=true}status
 }
 fn advance_inner(&mut self,source:&str,actual_eof:bool,mut observer:Option<&mut dyn OriginalDeclarationHeaderObserver>)->io::Result<bool>{
  if self.ended||source.len()<self.frontier{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual primary frontier regressed or was sealed"))}
  if self.original.stopped(){return Ok(false)}
  if self.tokens.window().last().is_some_and(|token|token.span.end>source.len()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual native token exceeds current arena frontier"))}
  let tokens = self.tokens.window();
  let mut batch=self.layout.as_mut().ok_or(io::ErrorKind::InvalidInput)?.advance_with_literal_facts(source,tokens,&self.original,actual_eof,Some(self.literal_facts.rows()))?;
  for line in batch.iter(){
   // Line is scalar geometry; no header/source String is copied or reparsed.
   let line=Line{indent:line.indent,header_start:line.header_start,header_end:line.header_end,end:line.end,explicit_block_opener:line.explicit_block_opener,same_line_body:line.same_line_body};
   let line_span = Span::new(line.header_start, line.end);
   let continuing=match observer.as_mut(){Some(actual)=>self.frames.as_mut().ok_or(io::ErrorKind::InvalidInput)?.line_scoped(source,tokens,line,&self.original,&mut self.diagnostics,Some(&mut **actual))?,None=>self.frames.as_mut().ok_or(io::ErrorKind::InvalidInput)?.line(source,tokens,line,&self.original,&mut self.diagnostics)?};
   if !continuing{break}
   let in_body=self.frames.as_ref().is_some_and(|frames|frames.trace_current_body_line(line_span));
   #[cfg(debug_assertions)]
   if let Some(candidates) = &mut self.body_literal_candidates {
    let in_body = self.frames.as_ref().is_some_and(|frames| frames.trace_current_body_line(line_span));
    candidates.observe(line_span, in_body, source, self.literal_facts.rows());
   }
   self.literal_facts.project_body_line(line_span,in_body,source,self.original.storage.a)?;
  }
  let continuing = if !self.original.stopped() {
   if let Some(start) = batch.take_header_start() {
    self.frames.as_mut().ok_or(io::ErrorKind::InvalidInput)?
     .begin_early_header(source, tokens, start, &self.original, &mut self.diagnostics)?
   } else { true }
  } else { false };
  // Resolving the previous frame from a partial header can return false
  // with a stored operational error. Drain it before reporting a stop.
  drop(batch);self.frontier=source.len();self.ended=actual_eof;
  if self.original.operational.borrow().is_some(){return Err(self.failure())}if let Some(actual)=self.original.storage.take_failure(){return Err(actual)}
  Ok(continuing && !self.original.stopped())
 }
 /// Borrow the existing live primary ledger before its failed attempt unwinds.
 #[cfg(debug_assertions)]
 pub fn trace_literal_retention(&self)->impl std::fmt::Debug{self.literal_facts.trace_retention()}
 #[cfg(debug_assertions)]
 pub fn trace_body_literal_candidates(&self) -> Option<impl std::fmt::Debug + '_> {
  self.body_literal_candidates.as_ref()
 }
 #[cfg(debug_assertions)]
 pub fn trace_token_retention(&self)->impl std::fmt::Debug + '_ { PrimaryTapeTrace(&self.tokens) }
 #[cfg(debug_assertions)]
 pub fn trace_item_retention(&self,source:&str)->impl std::fmt::Debug{
  self.frames.as_ref().map(|frames|frames.trace_items(source))
 }
 fn validate_finish(&self,source:&str,actual_eof:bool)->io::Result<()> {
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot seal"))}
  if source.len()!=self.frontier||actual_eof!=self.ended{return Err(io::Error::new(io::ErrorKind::InvalidInput,"primary sealing lacks the exact actual consumed frontier"))}
  if !actual_eof&&!self.original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"temporary input pause is not a primary EOF or authored stop"))}
  Ok(())
 }
 fn finish_parts(mut self,source:&str)->io::Result<FinishedPrimary<'a,'budget>> {
  let primary_owner=self.layout.take().ok_or(io::ErrorKind::InvalidInput)?.finish_identity()?;
  if self.literal_facts_issued{self.literal_facts.seal_actual_frontier(source.len(),self.original.storage.a)?;}
  let diagnostics=std::mem::take(&mut self.diagnostics);for diagnostic in diagnostics{if !self.original.storage.push(&mut self.lexical,diagnostic){return Err(self.failure())}}
  drop(self.diagnostics);
  let tokens=self.tokens.finish(self.original.storage.a)?;
  let OriginalParseState{storage,fatal,unavailable,operational,observer:_,observer_stop,first_outer_block:_}=self.original;
  if let Some(actual)=operational.into_inner(){return Err(actual)}if let Some(actual)=storage.take_failure(){return Err(actual)}
  Ok(FinishedPrimary{tokens,diagnostics:self.lexical,literal_facts:self.literal_facts_issued.then_some(self.literal_facts),
   primary_owner,fatal:fatal.into_inner(),unavailable:unavailable.into_inner(),observer_stop:observer_stop.get(),storage})
 }
 pub fn finish(mut self,source:&str,actual_eof:bool)->io::Result<OriginalDeclarationSkeleton>{
  self.validate_finish(source,actual_eof)?;
  let items=self.frames.take().ok_or(io::ErrorKind::InvalidInput)?.finish(source,self.tokens.window(),&self.original,&mut self.diagnostics,actual_eof)?;
  let FinishedPrimary{tokens,diagnostics,literal_facts,primary_owner,fatal,unavailable,observer_stop,storage}=self.finish_parts(source)?;
  let lease=storage.finish(&items,0,&diagnostics)?;
  Ok(OriginalDeclarationSkeleton{syntax:OriginalDeclarationSyntax{items,tokens:tokens.into(),diagnostics},literal_facts,primary_owner:Some(primary_owner),fatal,unavailable,observer_stop,_lease:lease})
 }
 pub fn finish_committed(mut self,source:&str,actual_eof:bool)->io::Result<OriginalCommittedPrimary>{
  self.validate_finish(source,actual_eof)?;
  let items=self.frames.take().ok_or(io::ErrorKind::InvalidInput)?.finish_committed(source,self.tokens.window(),&self.original,&mut self.diagnostics,actual_eof)?;
  let FinishedPrimary{tokens,diagnostics,literal_facts,primary_owner,fatal,unavailable,observer_stop,storage}=self.finish_parts(source)?;
  let item_bytes=items.bytes(&storage).ok_or_else(||storage.take_failure().unwrap_or_else(||io::ErrorKind::OutOfMemory.into()))?;
  let (item_lease,lease)=storage.finish_committed(item_bytes,&diagnostics)?;
  let items=items.finish(source.len(),item_lease);
  Ok(OriginalCommittedPrimary{items,tokens,diagnostics,literal_facts,primary_owner,fatal,unavailable,observer_stop,lease})
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[cfg(debug_assertions)]
 #[test]
 fn body_literal_candidates_use_actual_body_scope_and_exact_raw_ranges() {
  let source="/proc/p(formal = 7)\n    var/local = \"raw\"\n    return \"a\\t\"\n/obj/initializers\n    name = \"initial\"\n";
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));
  let mut primary=OriginalPrimaryDemand::new_committed(&a,None).unwrap();
  primary.body_literal_candidates=Some(BodyLiteralCandidates::default());
  for token in lex_spans(source).tokens {
   let raw=&source[token.span.range()];
   let value=match token.kind {
    TokenKind::Number=>Some(OriginalTokenValue::Int(7)),
    TokenKind::String=>Some(OriginalTokenValue::String(if raw=="\"a\\t\"" {"a\t"} else {&raw[1..raw.len()-1]})),
    _=>None,
   };
   if let Some(value)=value {
    let data=OriginalLiteralData::from_value_using(raw.to_owned(),value,&a).unwrap();
    primary.token_with_original_literal(token,data).unwrap();
   } else {
    primary.token(token).unwrap();
   }
  }
  assert!(primary.advance(source,true).unwrap());
  let candidates=primary.body_literal_candidates.as_ref().unwrap();
  assert_eq!(candidates.body_rows,2);
  assert_eq!(candidates.projectable_rows,1,"escaped text and initializer/formal values retain full ownership");
  assert_eq!(candidates.observed_standalone_rows,1);
  assert_eq!(candidates.raw_capacity_per_row_upper,"\"raw\"".len());
  let rows=primary.literal_facts.rows();
  let mut foreign=BodyLiteralCandidates::default();
  foreign.observe(Span::new(0,source.len()),true,&" ".repeat(source.len()),rows);
  assert_eq!(foreign.body_rows,4);
  assert_eq!(foreign.projectable_rows,0,"equal geometry alone cannot project spelling");
  drop(primary);
  assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_primary_assembly_retains_one_traversal_across_physical_pauses_and_not_fake_eof(){
  let source="/datum/a\n    var/value=1\n    proc/p()\n        return 2\n/datum/b\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut cursor=crate::NativeTokenCursor::default();let mut end=0;
  for line in source.split_inclusive('\n'){end+=line.len();loop{match cursor.next_available_using(&source[..end],end==source.len(),&a,|_,_,_|true).unwrap(){crate::NativeTokenStep::Token(token)=>primary.token(token).unwrap(),crate::NativeTokenStep::NeedInput|crate::NativeTokenStep::End=>break,crate::NativeTokenStep::Stopped=>panic!("no diagnostic stop")}}assert!(primary.advance(&source[..end],end==source.len()).unwrap());}
  let actual=primary.finish(source,true).unwrap();let expected=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(actual.syntax(),expected.syntax());drop(actual);drop(expected);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_primary_assembly_refuses_pause_sealing_foreign_frontier_and_keeps_first_io(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();assert!(primary.advance("",false).unwrap());assert_eq!(primary.finish("",false).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fault=||Err(io::Error::from_raw_os_error(1450));let a=crate::SettingAdmission::new(&counter,4<<20,&fault);assert_eq!(OriginalPrimaryDemand::new(&a,None).err().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_primary_one_shot_observer_failure_poison_survives_error_drain_and_only_fresh_owner_recovers(){
  struct Once(bool);impl OriginalDeclarationHeaderObserver for Once{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{if !self.0{self.0=true;Err(io::Error::from_raw_os_error(1450))}else{Ok(OriginalHeaderFlow::Continue)}}}
  let source="/proc/p()\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut observer=Once(false);let mut primary=OriginalPrimaryDemand::new(&a,Some(&mut observer)).unwrap();for token in lex_spans(source).tokens{primary.token(token).unwrap();}
  assert_eq!(primary.advance(source,true).err().unwrap().raw_os_error(),Some(1450));assert_eq!(primary.advance(source,true).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(primary.token(SpanToken{kind:TokenKind::Newline,span:Span::new(source.len(),source.len())}).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(primary.finish(source,true).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let mut fresh=OriginalPrimaryDemand::new(&a,Some(&mut observer)).unwrap();for token in lex_spans(source).tokens{fresh.token(token).unwrap()}assert!(fresh.advance(source,true).unwrap());let actual=fresh.finish(source,true).unwrap();assert_eq!(actual.syntax().items.len(),1);drop(actual);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

}

#[cfg(test)]mod early_and_literal_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn actual_first_productive_token_establishes_same_primary_scope_before_newline_and_full_header_joins_once(){
  let source="/datum/a\n    proc/p(value=1)\n";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut saw_early=false;
  for token in lex_spans(source).tokens{let end=token.span.end;primary.token(token).unwrap();assert!(primary.advance(&source[..end],false).unwrap());if end>source.find("proc/p").unwrap()&&end<source.len(){let scope=primary.frames.as_ref().unwrap().live_header_scope(&primary.original).unwrap();if let Some((start,indent,in_body,prior))=scope{assert_eq!(start,source.find("proc/p").unwrap());assert_eq!(indent,4);assert!(!in_body);assert!(prior.is_none());saw_early=true;}}}
  assert!(saw_early);assert!(primary.advance(source,true).unwrap());let actual=primary.finish(source,true).unwrap();let expected=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(actual.syntax(),expected.syntax());assert!(actual.original_literal_facts().is_none(),"untyped number insertion cannot issue a completed zero-literal roster");drop((actual,expected));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn partial_next_header_reports_the_first_operational_error_from_committing_the_previous_frame() {
  use std::cell::Cell;
  let source = "/datum/first\n/datum/next\n";
  let first_end = source.find('\n').unwrap() + 1;
  let next_start = first_end + 1; // The first productive slash, no second complete line.
  let tokens = lex_spans(source).tokens;
  let checkpoints = Cell::new(0usize);
  let fail_at = Cell::new(None);
  let armed = Cell::new(false);
  let poll = || {
   if armed.get() {
    let call = checkpoints.get() + 1;
    checkpoints.set(call);
    if fail_at.get() == Some(call) {
     return Err(io::Error::from_raw_os_error(1450));
    }
   }
   Ok(())
  };

  // Measure only the genuine transition. Its last checkpoint is the first
  // Item Vec allocation's credit handoff in the previous-frame commit.
  let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let mut last_checkpoint = None;
  for inject in [false, true] {
   armed.set(false);
   let a = crate::SettingAdmission::new(&used, 4 << 20, &poll);
   let mut primary = OriginalPrimaryDemand::new(&a, None).unwrap();
   for token in tokens.iter().filter(|token| token.span.end <= first_end) {
    primary.token(*token).unwrap();
   }
   assert!(primary.advance(&source[..first_end], false).unwrap());
   let slash = tokens.iter().find(|token| token.span == Span::new(first_end, next_start)).unwrap();
   primary.token(*slash).unwrap();

   checkpoints.set(0);
   fail_at.set(if inject { last_checkpoint } else { None });
   armed.set(true);
   let result = primary.advance(&source[..next_start], false);
   armed.set(false);
   if inject {
    assert_eq!(result.unwrap_err().raw_os_error(), Some(1450));
    assert_eq!(primary.advance(&source[..next_start], false).unwrap_err().kind(), io::ErrorKind::InvalidInput);
    assert_eq!(primary.finish(&source[..next_start], false).err().unwrap().kind(), io::ErrorKind::InvalidInput);
   } else {
    assert!(result.unwrap());
    assert!(checkpoints.get() > 0);
    last_checkpoint = Some(checkpoints.get());
    for token in tokens.iter().filter(|token| token.span.start >= next_start) {
     primary.token(*token).unwrap();
    }
    assert!(primary.advance(source, true).unwrap());
    let product = primary.finish(source, true).unwrap();
    assert_eq!(product.syntax().items.len(), 2);
    assert_eq!(product.syntax().items[0].header, "/datum/first");
   }
   assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
  }
 }

 #[test]fn genuine_typed_primary_occurrence_retains_same_neutral_roster_and_untyped_literals_keep_none(){
  let source="/datum/a\n    var/value=1\n";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut span=None;
  for token in lex_spans(source).tokens{if token.kind==TokenKind::Number{span=Some(token.span);let data=crate::OriginalLiteralData::from_value_using("1".to_owned(),crate::OriginalTokenValue::Int(1),&a).unwrap();primary.token_with_original_literal(token,data).unwrap();}else{primary.token(token).unwrap();}}
  primary.advance(source,true).unwrap();let product=primary.finish(source,true).unwrap();let rows=product.original_literal_facts().unwrap();assert_eq!(rows.len(),1);assert_eq!(rows.get(0).unwrap().0,span.unwrap());assert!(matches!(rows.get(0).unwrap().1.value().unwrap(),crate::OriginalTokenValue::Int(1)));let(_,_,_,lease,facts)=product.into_parts_with_literal_facts();let facts=facts.unwrap();assert!(facts.is_admitted_by(&a));drop(lease);assert_eq!(facts.rows().len(),1);assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod producer_identity_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn live_header_binds_actual_final_same_layout_owner_and_rejects_equal_source_foreign_primary(){
  let source="/proc/p(value=1)\n";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut live=None;
  for token in lex_spans(source).tokens{let end=token.span.end;primary.token(token).unwrap();primary.advance(&source[..end],false).unwrap();if &source[token.span.range()]=="("{let header=primary.live_callable_header(&source[..end]).unwrap().unwrap();primary.validate_live_header(&header).unwrap();assert_eq!(header.start(),0);assert_eq!(header.argument_start(),"/proc/p(".len());live=Some(header.clone());}}
  let live=live.unwrap();
  assert_eq!(primary.span_tokens().get(live.open_ordinal).unwrap().span,live.open_span());
  assert_eq!(primary.span_tokens().get(live.open_ordinal).unwrap().text(source),"(");
  assert!(primary.validate_live_header(&live).is_err(),"completed live header cannot resume formal input");primary.advance(source,true).unwrap();let actual=primary.finish(source,true).unwrap();assert!(actual.same_primary_header(&live));
  let mut foreign=OriginalPrimaryDemand::new(&a,None).unwrap();for token in lex_spans(source).tokens{foreign.token(token).unwrap()}foreign.advance(source,true).unwrap();let foreign=foreign.finish(source,true).unwrap();assert!(!foreign.same_primary_header(&live));
  let mut slot=live.into_producer_identity();
  assert!(actual.same_primary_producer(&slot));
  let owner=slot.take().expect("the exact live owner");
  assert!(slot.take().is_none());
  assert!(!actual.same_primary_producer(&slot));
  assert!(actual.same_primary_producer(&owner));
  assert!(!foreign.same_primary_producer(&owner));
  assert_eq!(std::mem::size_of::<OriginalPrimaryProducerIdentity>(),std::mem::size_of::<usize>());
  drop((actual,foreign));assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes(),"compact handle retains only its actual fixed producer metadata");drop(owner);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn resumed_live_probe_matches_fresh_scan_and_can_start_after_the_opening() {
  let source="/datum/parent\n    proc/child(datum/act/A)\n        return\n    proc/next()\n";
  let delayed=source.find("datum/act").unwrap()+"datum".len();
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut continuous=OriginalPrimaryDemand::new(&a,None).unwrap();
  let mut late=OriginalPrimaryDemand::new(&a,None).unwrap();
  let mut compared_delayed=false;
  for token in lex_spans(source).tokens {
   let text=&source[..token.span.end];
   for primary in [&mut continuous,&mut late] {
    primary.token(token).unwrap();
    assert!(primary.advance(text,false).unwrap());
   }
   let fresh=continuous.live_callable_header(text).unwrap();
   let resumed=continuous.resume_live_callable_header(text).unwrap();
   assert_eq!(fresh.is_some(),resumed.is_some());
   if let (Some(fresh),Some(resumed))=(fresh,resumed) {
    assert!(fresh.same_header(&resumed));
    assert_eq!(fresh.prior_outer_block(),resumed.prior_outer_block());
   }
   if token.span.end==delayed {
    assert_eq!(token.text(text),"datum");
    let fresh=late.live_callable_header(text).unwrap().expect("already-issued nested header");
    let resumed=late.resume_live_callable_header(text).unwrap().expect("new scope searches prior tokens");
    assert!(fresh.same_header(&resumed));
    assert!(resumed.open_span().end<=token.span.start);
    assert_eq!(late.live_callable_prefix.unwrap().next,resumed.open_ordinal);
    compared_delayed=true;
   }
  }
  assert!(compared_delayed);
  drop((continuous,late));
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn resumed_live_probe_checkpoints_even_after_a_no_open_prefix() {
  let source="/proc/probe(value)\n";
  let pause=source.find("probe").unwrap();
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let stop=std::cell::Cell::new(false);
  let poll=||if stop.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())};
  let a=crate::SettingAdmission::new(&used,8<<20,&poll);
  let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();
  for token in lex_spans(source).tokens {
   let text=&source[..token.span.end];
   primary.token(token).unwrap();
   assert!(primary.advance(text,false).unwrap());
   if token.span.start==pause {
    let checked=primary.live_callable_prefix.expect("earlier partial scope");
    assert_eq!(checked.next+1,primary.span_tokens().len());
    stop.set(true);
    let error=primary.resume_live_callable_header(text).err().expect("frame checkpoint");
    assert_eq!(error.raw_os_error(),Some(1450));
    assert_eq!(primary.live_callable_prefix.unwrap().next,checked.next);
    drop(primary);
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
    return;
   }
   assert!(primary.resume_live_callable_header(text).unwrap().is_none());
  }
  panic!("test fixture did not issue probe identifier");
 }

 #[test]
 fn resumed_live_probe_keeps_the_first_non_callable_opening_until_the_scope_changes() {
  let source="/datum/outer\n    var/list/value = list(helper(), 2)\n    proc/next()\n";
  let initializer=source.find("list(helper").unwrap()+"list(".len();
  let following=source.find("next()").unwrap()+"next(".len();
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();
  let mut excluded=None;
  let mut seen_next=false;
  for token in lex_spans(source).tokens {
   let text=&source[..token.span.end];
   primary.token(token).unwrap();
   assert!(primary.advance(text,false).unwrap());
   let resumed=primary.resume_live_callable_header(text).unwrap();
   if token.span.end==initializer {
    assert!(resumed.is_none());
    let prefix=primary.live_callable_prefix.unwrap();
    assert!(prefix.non_callable);
    excluded=Some(prefix.next);
   }else if token.span.start>=initializer&&token.span.end<=source.find("    proc/next").unwrap()&&token.kind!=TokenKind::Newline {
    let prefix=primary.live_callable_prefix.unwrap();
    assert!(prefix.non_callable);
    assert_eq!(Some(prefix.next),excluded);
   }else if token.span.end==following {
    let live=resumed.expect("the following declaration has a real callable opening");
    assert!(live.same_header(&primary.live_callable_header(text).unwrap().unwrap()));
    seen_next=true;
   }
  }
  assert!(excluded.is_some()&&seen_next);
  drop(primary);
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_scoped_primary_observer_loan_ends_before_same_consumer_is_reused(){
  struct Observer(usize);impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{self.0+=1;Ok(OriginalHeaderFlow::Continue)}}
  let source="/proc/p()\n";let count=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&count,4<<20,&||Ok(()));
  let mut observer=Observer(0);let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();for token in lex_spans(source).tokens{primary.token(token).unwrap()}
  assert!(primary.advance_with_observer(source,true,&mut observer).unwrap());assert_eq!(observer.0,1);observer.0+=1;
  let product=primary.finish(source,true).unwrap();assert_eq!(observer.0,2);assert_eq!(product.syntax().items.len(),1);drop(product);assert_eq!(count.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_scoped_primary_observer_first_io_poison_refuses_retry_and_finish(){
  struct Observer(bool);impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{if !self.0{self.0=true;Err(io::Error::from_raw_os_error(1450))}else{Ok(OriginalHeaderFlow::Continue)}}}
  let source="/proc/p()\n";let count=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&count,4<<20,&||Ok(()));let mut observer=Observer(false);let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();for token in lex_spans(source).tokens{primary.token(token).unwrap()}
  assert_eq!(primary.advance_with_observer(source,true,&mut observer).unwrap_err().raw_os_error(),Some(1450));assert!(observer.0);assert!(primary.advance_with_observer(source,true,&mut observer).is_err());assert!(primary.finish(source,true).is_err());assert_eq!(count.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_scoped_header_keeps_its_registered_outer_probe_through_pending_child_resolution(){
  struct Observer(Vec<Option<usize>>);impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,event:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{self.0.push(event.prior_outer_block);Ok(OriginalHeaderFlow::Continue)}}
  let source="/proc/first()\n    return 1\n/proc/second()\n";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut observer=Observer(Vec::new());let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();
  for token in lex_spans(source).tokens{primary.token(token).unwrap();assert!(primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap());}
  assert!(primary.advance_with_observer(source,true,&mut observer).unwrap());let product=primary.finish(source,true).unwrap();assert_eq!(observer.0,vec![None,Some(source.find('\n').unwrap())]);assert_eq!(product.syntax().items.len(),2);drop(product);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_inline_type_brace_scope_is_already_bound_before_nested_callable_formals(){
  struct Observer;impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}
  let source="/datum/parent{\nproc/child(){\n}\n}\n";let open=source.find("child(").unwrap()+"child(".len();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut observer=Observer;let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let tokens=lex_spans(source).tokens;for token in tokens.iter().filter(|token|token.span.end<=open){primary.token(*token).unwrap();assert!(primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap());}
  let live=primary.live_callable_header(&source[..open]).unwrap().expect("genuine nested callable at current open");assert_eq!(live.start(),source.find("proc/child").unwrap());assert_eq!(live.indent,4);primary.validate_live_header(&live).unwrap();
  for token in tokens.iter().filter(|token|token.span.end>open){primary.token(*token).unwrap();assert!(primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap());}assert!(primary.advance_with_observer(source,true,&mut observer).unwrap());let product=primary.finish(source,true).unwrap();assert!(product.same_primary_header(&live));assert_eq!(product.syntax().items.len(),1);assert_eq!(product.syntax().items[0].children.len(),1);assert_eq!(product.syntax().items[0].children[0].kind,ItemKind::Proc);drop((product,live));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_live_formal_stop_seals_only_inserted_consumed_frontier_without_reentrant_observer_or_eof(){
  struct Observer;impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{panic!("unfinished fatal header must not reenter complete observer")}}
  let source="/proc/bad(value=, BAD())\n";let open=source.find('(').unwrap()+1;let stop=source.find(',').unwrap()+1;let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut observer=Observer;let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let tokens=lex_spans(source).tokens;
  for token in tokens.iter().filter(|token|token.span.end<=open){primary.token(*token).unwrap();primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap();}let live=primary.live_callable_header(&source[..open]).unwrap().unwrap();
  for token in tokens.iter().filter(|token|token.span.start>=open&&token.span.end<=stop){primary.token(*token).unwrap();}assert_eq!(primary.consumed_frontier(),open);primary.observer_stop_live_header_at(&live,&source[..stop]).unwrap();assert_eq!(primary.consumed_frontier(),stop);let actual=primary.finish(&source[..stop],false).unwrap();assert!(actual.syntax().items.is_empty());assert_eq!(actual.observer_stop(),Some(Span::new(0,stop)));assert!(actual.fatal().is_none(),"observer control is not a fabricated authored fatal");drop((actual,live));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}
