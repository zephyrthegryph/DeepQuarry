//! One primary traversal + the existing native formal-signature producer.
//! Prepared results and the SAME SymbolTable move to the ordered adapter; no
//! signature parser/cache/model is duplicated and no partial input is promotable.
use super::{ParsedSignature,SignatureError};
use super::header::HeaderView;
use super::header_input::{OriginalHeaderFailure,OriginalProcedureHeaders,parts_from_primary_view};
use dm_ir::SymbolTable;
use dm_preprocess::SourceText;
use dm_syntax::{Item,Span,SettingAdmission,OriginalDeclarationHeaderObserver,OriginalPrimaryHeader,OriginalHeaderFlow};
use std::sync::Arc;
fn header_work_bytes(tokens:usize,text:usize)->std::io::Result<usize>{
  let token_unit=std::mem::size_of::<dm_ir::Parameter>().checked_add(std::mem::size_of::<super::HeaderTypeDeclaration>()).and_then(|n|n.checked_add(2*std::mem::size_of::<super::OriginalFormalNotice>())).and_then(|n|n.checked_add(std::mem::size_of::<dm_syntax::ParameterClauseSpans>())).and_then(|n|n.checked_add(std::mem::size_of::<dm_ir::ExpressionToken>())).and_then(|n|n.checked_add(std::mem::size_of::<dm_syntax::SpanToken>())).and_then(|n|n.checked_add(std::mem::size_of::<String>()+16*std::mem::size_of::<usize>())).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;
  let bytes=tokens.checked_mul(token_unit).and_then(|n|n.checked_mul(4)).and_then(|n|Some(text).and_then(|text|text.checked_mul(4)).and_then(|text|n.checked_add(text))).and_then(|n|n.checked_add(1024)).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;
 Ok(bytes)
}
// The original fixed allowance covers the lease Arc and the later
// ProcedureMetadata wrapper. Preserve it in addition to measured payloads.
fn retained_signature_bytes(signature: &ParsedSignature) -> std::io::Result<usize> {
    use std::mem::{align_of, size_of};
    let overflow = || std::io::Error::from(std::io::ErrorKind::OutOfMemory);
    fn arc_payload<T>(len: usize) -> Option<usize> {
        len.checked_mul(size_of::<T>())?
            .checked_add(2 * size_of::<usize>())?
            .checked_add(align_of::<T>() - 1)
    }
    fn vec_payload<T>(vec: &Vec<T>) -> Option<usize> {
        vec.capacity().checked_mul(size_of::<T>())
    }
    let mut bytes = 1024usize;
    let mut add = |part: Option<usize>| -> std::io::Result<()> {
        bytes = bytes.checked_add(part.ok_or_else(overflow)?).ok_or_else(overflow)?;
        Ok(())
    };
    add(vec_payload(&signature.declarations))?;
    add(vec_payload(&signature.original_clauses))?;
    add(arc_payload::<dm_ir::Parameter>(signature.signature.parameters.len()))?;
    for parameter in signature.signature.parameters.iter() {
        for expression in [&parameter.default, &parameter.input_annotation, &parameter.source_expression].into_iter().flatten() {
            add(arc_payload::<dm_ir::ExpressionToken>(expression.tokens.len()))?;
        }
        if let Some(array) = &parameter.array {
            add(arc_payload::<dm_ir::ArrayDeclaration>(1))?;
            add(arc_payload::<Option<dm_ir::SymbolicExpression>>(array.dimensions.len()))?;
            for expression in array.dimensions.iter().flatten() {
                add(arc_payload::<dm_ir::ExpressionToken>(expression.tokens.len()))?;
            }
        }
    }
    if let Some(expression) = &signature.signature.return_annotation {
        add(arc_payload::<dm_ir::ExpressionToken>(expression.tokens.len()))?;
    }
    Ok(bytes)
}
fn checkpoint(a:&SettingAdmission<'_>)->std::io::Result<()>{let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual)}status}
/// Output only: the caller already authenticated the SAME live value and cursor.
fn write_input_failure(out:&mut dyn std::fmt::Write,value:dm_syntax::OriginalTokenValue<&str>,expected:dm_syntax::OriginalInputExpected)->std::fmt::Result{
 dm_syntax::write_original_input_failure(out,Some(value),expected)
}
struct Row{producer:Option<dm_syntax::OriginalPrimaryProducerIdentity>,header:Span,argument_offset:usize,signature:Option<ParsedSignature>,_lease:Arc<dm_syntax::SettingRootLease>}
struct EarlyFormals{live:dm_syntax::OriginalPrimaryLiveHeader,accumulator:super::FormalParameterAccumulator,next_start:usize,closed:Option<Span>,head_assignment:Option<Span>,head_bytes:usize,symbol_shape:dm_ir::LocalSymbolStorage,credit:dm_syntax::SettingRootLease}
struct PendingInput{live:dm_syntax::OriginalPrimaryLiveHeader,parameter:usize,marker:Span,input:dm_syntax::RetainedParameterInput}
struct PendingDefault{live:dm_syntax::OriginalPrimaryLiveHeader,root:super::DemandedFormalRoot}
pub(crate) struct OriginalSignatureObserver<'a,'b>{a:&'a SettingAdmission<'b>,symbols:SymbolTable,rows:Vec<Row>,row_storage:Option<dm_syntax::SettingRootLease>,failure:Option<SignatureError>,failure_storage:Option<dm_syntax::SettingRootLease>,unsupported:Option<String>,early:Option<EarlyFormals>,defaults:Vec<PendingDefault>,inputs:Vec<PendingInput>,input_storage:Option<dm_syntax::SettingRootLease>,default_storage:Option<dm_syntax::SettingRootLease>,stream_failed:bool,failure_live:Option<dm_syntax::OriginalPrimaryLiveHeader>,failure_head_data:Option<(Span,dm_syntax::OriginalLiteralData)>,notices:Option<super::original_formal_notices::FormalNotices>,notices_complete:bool}
/// Borrowed accounting from existing unique observer leases. The floor is
/// the existing post-header reconciliation, including its fixed allowance,
/// not a claim about allocator bytes or releasable memory.
#[cfg(debug_assertions)]
#[derive(Debug, Default)]
struct SignatureRetentionTrace {
    rows: usize,
    row_capacity: usize,
    row_buffer_bytes: usize,
    completed_header_bytes: usize,
    reconciliation_floor_bytes: usize,
    above_floor_rows: usize,
    above_floor_bytes: usize,
    unavailable_floor_rows: usize,
    largest_header_bytes: usize,
    largest_header_start: Option<usize>,
    active_header_bytes: usize,
    failure_header_bytes: usize,
    pending_defaults: usize,
    pending_default_buffer_bytes: usize,
    pending_default_root_bytes: usize,
    pending_inputs: usize,
    pending_input_buffer_bytes: usize,
    pending_input_root_bytes: usize,
    formal_notice_bytes: usize,
}

#[cfg(debug_assertions)]
impl OriginalSignatureObserver<'_, '_> {
    fn retention_for_trace(&self) -> SignatureRetentionTrace {
        let bytes = |lease: Option<&dm_syntax::SettingRootLease>| lease.map_or(0, |l| l.bytes());
        let mut trace = SignatureRetentionTrace {
            rows: self.rows.len(),
            row_capacity: self.rows.capacity(),
            row_buffer_bytes: bytes(self.row_storage.as_ref()),
            active_header_bytes: bytes(self.early.as_ref().map(|e| &e.credit)),
            failure_header_bytes: bytes(self.failure_storage.as_ref()),
            pending_defaults: self.defaults.len(),
            pending_default_buffer_bytes: bytes(self.default_storage.as_ref()),
            pending_default_root_bytes: self.defaults.iter().fold(0usize, |n, d| {
                n.saturating_add(d.root.syntax.retained_bytes_for_trace())
            }),
            pending_inputs: self.inputs.len(),
            pending_input_buffer_bytes: bytes(self.input_storage.as_ref()),
            pending_input_root_bytes: self.inputs.iter().fold(0usize, |n, i| {
                n.saturating_add(i.input.retained_bytes_for_trace())
            }),
            formal_notice_bytes: self.notices.as_ref().map_or(0, |n| n.retained_bytes_for_trace()),
            ..Default::default()
        };
        for row in &self.rows {
            let retained = row._lease.bytes();
            trace.completed_header_bytes = trace.completed_header_bytes.saturating_add(retained);
            if retained > trace.largest_header_bytes {
                trace.largest_header_bytes = retained;
                trace.largest_header_start = Some(row.header.start);
            }
            if let Some(floor) = row.signature.as_ref().and_then(|s| retained_signature_bytes(s).ok()) {
                trace.reconciliation_floor_bytes = trace.reconciliation_floor_bytes.saturating_add(floor);
                if retained > floor {
                    trace.above_floor_rows += 1;
                    trace.above_floor_bytes = trace.above_floor_bytes.saturating_add(retained - floor);
                }
            } else {
                trace.unavailable_floor_rows += 1;
            }
        }
        trace
    }

    /// Only called on failure. Unwound producer, recursion and temporary
    /// owners are excluded; the admission error already carries its own
    /// allocation-time sample. Do not replace that error or open another query.
    pub(crate) fn trace_failed_stream_retention(&self, stage: &'static str) {
        if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_none() {
            return;
        }
        use std::io::Write as _;
        let trace = self.retention_for_trace();
        let counter_after_unwind = self.a.retained_bytes_for_trace();
        let _ = writeln!(
            std::io::stderr().lock(),
            "ORIGINAL_RETAINED_STAGE={stage} counter_after_unwind={counter_after_unwind} observer={trace:?}"
        );
    }
}

impl OriginalDeclarationHeaderObserver for OriginalSignatureObserver<'_,'_>{
 fn header(&mut self,event:OriginalPrimaryHeader<'_>)->std::io::Result<OriginalHeaderFlow>{let result=self.header_using(event);if result.is_err(){self.stream_failed=true}result}
}
/// Fund the replacement Vec while its old buffer still owns its credit.
/// This accounts for storage only; each moved row keeps its payload leases.
fn grow_funded_rows<T>(
    rows: &mut Vec<T>,
    storage: &mut Option<dm_syntax::SettingRootLease>,
    a: &SettingAdmission<'_>,
) -> std::io::Result<()> {
    use std::{alloc::{alloc, Layout}, io::{Error, ErrorKind}, ptr::NonNull};
    let capacity = rows.capacity().max(2).checked_mul(2).ok_or(ErrorKind::OutOfMemory)?;
    let layout = Layout::array::<T>(capacity).map_err(|_| Error::from(ErrorKind::OutOfMemory))?;
    if layout.size() == 0 || storage.as_ref().is_some_and(|credit| !a.matches_lease_domain(credit)) {
        return Err(ErrorKind::InvalidInput.into());
    }
    let next_storage = a.reserve(layout.size()).map_err(|error| a.take_operational_error().unwrap_or(error))?;
    // SAFETY: T is nonzero-sized and capacity is positive. The checked
    // layout is funded above; the Global allocation becomes a standard Vec
    // with the same layout. No element is initialized yet.
    let raw = unsafe { alloc(layout) };
    let raw = NonNull::new(raw.cast::<T>()).ok_or_else(|| Error::new(ErrorKind::OutOfMemory, "native prepared row allocation denied"))?;
    let mut next = unsafe { Vec::from_raw_parts(raw.as_ptr(), 0, capacity) };
    checkpoint(a)?;
    next.append(rows);
    drop(std::mem::replace(rows, next));
    *storage = Some(next_storage);
    Ok(())
}

impl OriginalSignatureObserver<'_,'_>{
 fn grow_rows(&mut self) -> std::io::Result<()> {
    grow_funded_rows(&mut self.rows, &mut self.row_storage, self.a)
 }
 fn header_using(&mut self,event:OriginalPrimaryHeader<'_>)->std::io::Result<OriginalHeaderFlow>{
  checkpoint(self.a)?;
  if self.stream_failed||self.failure.is_some()||self.unsupported.is_some(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual signature observer already stopped"))}
  let bytes=header_work_bytes(event.token_window().len(),event.span().end.checked_sub(event.span().start).ok_or(std::io::ErrorKind::InvalidInput)?)?;
  // Keep metadata funding on its owning observer across EVERY fallible path.
  // The shared SymbolTable retains interned strings even when a clause fails.
  let early=self.early.take();let completed_live=early.as_ref().map(|early|early.live.clone());
  let prior_symbols=early.as_ref().map_or_else(||self.symbols.local_storage(),|early|early.symbol_shape);
  let (formals,closed)=match early{Some(early)=>{self.failure_storage=Some(early.credit);(Some(early.accumulator),early.closed)},None=>{self.failure_storage=Some(self.a.reserve(bytes)?);(None,None)}};
  if completed_live.as_ref().is_some_and(|live|live.start()!=event.span().start){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"completed header differs from actual live formal owner"))}
  let view=HeaderView::from_primary_header(&event);
  let parts=match parts_from_primary_view(view,0,view.text(),event.prior_outer_block()){Ok(parts)=>parts,Err(actual)=>{self.unsupported=Some(actual);self.failure_live=completed_live;return Ok(OriginalHeaderFlow::Stop)}};
  let argument_offset=parts.argument_offset;
  let parsed=if let Some(formals)=formals{
   let live=completed_live.as_ref().expect("actual early owner");if live.argument_start()!=event.span().start.checked_add(argument_offset).ok_or(std::io::ErrorKind::InvalidInput)?||closed!=Some(parts.closing_span()){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"completed formal cursor differs from actual primary header"))}
   let credit=self.failure_storage.as_mut().expect("actual header credit");if bytes>credit.bytes(){let extra=bytes-credit.bytes();self.a.grow(credit,extra)?}
   parts.finish_formals(formals.finish(),&mut self.symbols)
  }else{parts.parse_original(&mut self.symbols)};
  let mut signature=match parsed{Ok(actual)=>actual,Err(mut actual)=>{self.notices_complete&=actual.formal_notices_complete;let origin=event.span().start.checked_add(argument_offset).ok_or(std::io::ErrorKind::InvalidInput)?;for notice in std::mem::take(&mut actual.formal_notices){self.record_formal_notice(event.span().start,notice.checked_shift(origin)?)?;}self.failure=Some(actual);self.failure_live=completed_live;return Ok(OriginalHeaderFlow::Stop)}};
  self.notices_complete&=signature.formal_notices_complete;let origin=event.span().start.checked_add(argument_offset).ok_or(std::io::ErrorKind::InvalidInput)?;for notice in std::mem::take(&mut signature.formal_notices){self.record_formal_notice(event.span().start,notice.checked_shift(origin)?)?;}
  checkpoint(self.a)?;
  if self.rows.len() == self.rows.capacity() {
   self.grow_rows()?;
  }
  // Formal notices have moved to their own charged ledger. The remaining
  // payload may move to clause roots and detached IR aliases. They still share
  // this lease. Demanded syntax and retained input roots have their own leases.
  // The same observer owns all early and completed intern calls. A header
  // that can have grown/reallocated the bucket table keeps its full envelope.
  if let Some(spellings)=self.symbols.local_storage().spelling_delta_without_bucket_growth(prior_symbols) {
   let retained=retained_signature_bytes(&signature)?.checked_add(spellings).ok_or(std::io::ErrorKind::OutOfMemory)?;
   let credit=self.failure_storage.as_mut().expect("actual successful header credit");
   let unused=credit.bytes().checked_sub(retained).ok_or(std::io::ErrorKind::OutOfMemory)?;
   if unused!=0 { self.a.shrink(credit,unused).map_err(|proxy|self.a.take_operational_error().unwrap_or(proxy))?; }
  }
  let header_lease=self.failure_storage.take().expect("actual successful header credit");
  self.rows.push(Row{producer:completed_live.map(dm_syntax::OriginalPrimaryLiveHeader::into_producer_identity),header:event.span(),argument_offset,signature:Some(signature),_lease:Arc::new(header_lease)});
  Ok(OriginalHeaderFlow::Continue)
 }
}
/// One procedure's encoding scratch is released before the next row. The
/// final immutable byte allocation remains funded separately.
struct ProcedureCanonicalWork<'a, 'op> {
    admission: &'a SettingAdmission<'op>,
    scratch: dm_syntax::SettingRootLease,
}

impl dm_ir::CanonicalWork for ProcedureCanonicalWork<'_, '_> {
    fn poll(&mut self) -> std::io::Result<()> {
        checkpoint(self.admission)
    }

    fn reserve(&mut self, bytes: usize) -> std::io::Result<()> {
        self.admission.grow(&mut self.scratch, bytes)
            .map_err(|proxy| self.admission.take_operational_error().unwrap_or(proxy))
    }
}

fn append_procedure_canonical(
    header: Arc<[u8]>,
    procedure: &dm_ir::ProcedureMetadata,
    held: &mut Option<dm_syntax::SettingRootLease>,
    a: &SettingAdmission<'_>,
) -> std::io::Result<Arc<[u8]>> {
    use dm_ir::CanonicalWork as _;
    use std::alloc::Layout;
    use std::io::{Error, ErrorKind};
    use std::sync::atomic::AtomicUsize;

    let reserve = |bytes| a.reserve(bytes)
        .map_err(|proxy| a.take_operational_error().unwrap_or(proxy));
    let mut work = ProcedureCanonicalWork { admission: a, scratch: reserve(0)? };
    let header_bound = header.len().checked_mul(4).ok_or(ErrorKind::OutOfMemory)?;
    work.reserve(header_bound)?;
    let mut joined = Vec::new();
    joined.try_reserve_exact(header.len()).map_err(|actual| Error::new(ErrorKind::OutOfMemory, actual))?;
    if joined.capacity() > header_bound {
        return Err(ErrorKind::OutOfMemory.into());
    }
    joined.extend_from_slice(&header);
    drop(header);
    let encoded = procedure.canonical_bytes_using(&mut work)?;
    let len = joined.len().checked_add(encoded.len()).ok_or(ErrorKind::OutOfMemory)?;
    // Preserve the Arc accounting convention used by the signature roots:
    // one inline byte slice and its two reference count words.
    let bytes = Layout::array::<u8>(len).map_err(|_| ErrorKind::OutOfMemory)?;
    let (layout, _) = Layout::new::<[AtomicUsize; 2]>().extend(bytes)
        .map_err(|_| ErrorKind::OutOfMemory)?;
    let mut retained = reserve(layout.pad_to_align().size())?;

    // The joining Vec overlaps the already-funded encoded bytes and final Arc.
    let join_bound = len.checked_mul(4).ok_or(ErrorKind::OutOfMemory)?;
    if len > joined.capacity() {
        work.reserve(join_bound)?;
        joined.try_reserve_exact(encoded.len()).map_err(|actual| Error::new(ErrorKind::OutOfMemory, actual))?;
        if joined.capacity() > join_bound {
            return Err(ErrorKind::OutOfMemory.into());
        }
    }
    joined.extend_from_slice(&encoded);
    let result: Arc<[u8]> = joined.into();
    drop(encoded);
    drop(work);
    if let Some(owner) = held {
        a.absorb(owner, &mut retained)?;
    } else {
        *held = Some(retained);
    }
    Ok(result)
}

/// Weak observations of the actual observer's local spelling allocations.
#[derive(Default)]
pub(crate) struct OriginalSignatureSpellings {
    rows: Vec<std::sync::Weak<str>>,
    storage: Option<dm_syntax::SettingRootLease>,
}

impl OriginalSignatureSpellings {
    fn capture(symbols: &SymbolTable, a: &SettingAdmission<'_>) -> std::io::Result<Self> {
        let mut result = Self::default();
        symbols.try_visit_local_spellings(|spelling| {
            checkpoint(a)?;
            if result.rows.len() == result.rows.capacity() {
                grow_funded_rows(&mut result.rows, &mut result.storage, a)?;
            }
            result.rows.push(Arc::downgrade(spelling));
            Ok::<_, std::io::Error>(())
        })?;
        Ok(result)
    }

    pub(crate) fn live(&self) -> bool {
        self.rows.iter().any(|row| row.strong_count() != 0)
    }

    pub(crate) fn admitted_by(&self, a: &SettingAdmission<'_>) -> bool {
        self.storage.as_ref().is_none_or(|credit| a.matches_lease_domain(credit))
    }

    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        if self.rows.capacity() != 0 {
            visit(self.rows.as_ptr() as usize, self.rows.capacity() * std::mem::size_of::<std::sync::Weak<str>>(),
                std::mem::align_of::<std::sync::Weak<str>>());
        }
    }
}

/// Unique once-consumed metadata results, bound to the exact native header owner.
/// Coordinate/source equality cannot substitute another header owner.
pub(crate) struct PreparedOriginalSignatures{headers:Arc<OriginalProcedureHeaders>,rows:Vec<Row>,row_storage:Option<dm_syntax::SettingRootLease>,input_failure_message:Option<(super::OriginalInputParameterFatal,String)>,spellings:OriginalSignatureSpellings,failure_storage:Option<Arc<dm_syntax::SettingRootLease>>,interrupted_storage:Option<Arc<dm_syntax::SettingRootLease>>,canonical_storage:Option<dm_syntax::SettingRootLease>}
impl PreparedOriginalSignatures{
 pub(crate) fn append_procedure_canonical(&mut self,header:Arc<[u8]>,procedure:&dm_ir::ProcedureMetadata,a:&SettingAdmission<'_>)->std::io::Result<Arc<[u8]>>{
  append_procedure_canonical(header,procedure,&mut self.canonical_storage,a)
 }
 pub(crate) fn take_canonical_storage(&mut self)->Option<dm_syntax::SettingRootLease>{self.canonical_storage.take()}
 pub(crate) fn actual_headers(&self)->&OriginalProcedureHeaders{&self.headers}
 pub(crate) fn retain_input_failure_message(&mut self,reason:super::OriginalInputParameterFatal,message:String)->std::io::Result<()>{let mut in_source=false;self.headers.visit_source(|source|in_source=reason.token_span().end<=source.len());if self.input_failure_message.is_some()||self.failure_storage.as_ref().is_none_or(|credit|credit.bytes()<message.capacity())||!in_source{return Err(std::io::ErrorKind::InvalidInput.into())}self.input_failure_message=Some((reason,message));Ok(())}
 pub(crate) fn input_failure_message(&self,reason:super::OriginalInputParameterFatal)->Option<&str>{self.input_failure_message.as_ref().filter(|(actual,_)|*actual==reason).map(|(_,message)|message.as_str())}

 pub(crate) fn take_spellings(&mut self)->OriginalSignatureSpellings{std::mem::take(&mut self.spellings)}
 pub(crate) fn visit_signature_reservations(&self,mut visit:impl FnMut(&Arc<dm_syntax::SettingRootLease>)){
  for row in &self.rows{visit(&row._lease)}
  // A fatal or interrupted header can intern a prefix of real symbols before
  // publishing a Row. Keep the same envelope on any detached spelling alias.
  if !self.spellings.rows.is_empty() {
   if let Some(credit)=&self.failure_storage{visit(credit);}
   if let Some(credit)=&self.interrupted_storage{visit(credit);}
  }
 }
 pub(crate) fn require_consumed(&self)->Result<(),&'static str>{if self.rows.iter().any(|row|row.signature.is_some()){Err("actual primary formal metadata was not consumed by native adapter")}else{Ok(())}}
 /// Alias capture now owns the per-header reservations. The consumed
 /// allocation itself has no aliases and can be dropped before graph use.
 pub(crate) fn release_consumed_rows(&mut self) {
  debug_assert!(self.require_consumed().is_ok());
  drop(std::mem::take(&mut self.rows));
  self.row_storage = None;
 }

 pub(crate) fn visit_retained_failure_storage(&self, mut visit: impl FnMut(usize,usize,usize)) {
  debug_assert_eq!(self.rows.capacity(), 0);
  if let Some((_, message)) = &self.input_failure_message {
   if message.capacity() != 0 {
    visit(message.as_ptr() as usize, message.capacity(), 1);
   }
  }
 }

 pub(crate) fn take(&mut self,header:Span,offset:usize,headers:&OriginalProcedureHeaders)->Result<(ParsedSignature,usize),String>{
  if !std::ptr::eq(self.headers.as_ref(),headers){return Err("prepared formal signature belongs to another primary header owner".into())}
  let local=Span::new(header.start.checked_sub(offset).ok_or("prepared header before current source")?,header.end.checked_sub(offset).ok_or("prepared header before current source")?);
  let index=self.rows.binary_search_by_key(&local.start,|row|row.header.start).map_err(|_|"primary prepared signature row absent")?;
  let row=&mut self.rows[index];if row.header!=local{return Err("primary prepared signature header differs".into())}
  let parsed=row.signature.take().ok_or("primary prepared signature was already consumed")?;Ok((parsed,row.argument_offset))
 }
 #[cfg(test)]pub(crate) fn remaining(&self)->usize{self.rows.iter().filter(|row|row.signature.is_some()).count()}
}
#[cfg(test)]
mod signature_row_storage_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[cfg(debug_assertions)]
    #[test]
    fn failed_primary_trace_reads_existing_header_leases_without_funding_or_releasing() {
        struct FailThird<'a, 'op> {
            observer: OriginalSignatureObserver<'a, 'op>,
            seen: usize,
        }
        impl OriginalDeclarationHeaderObserver for FailThird<'_, '_> {
            fn header(&mut self, event: OriginalPrimaryHeader<'_>) -> std::io::Result<OriginalHeaderFlow> {
                self.seen += 1;
                if self.seen == 3 {
                    return Err(std::io::Error::from_raw_os_error(1450));
                }
                self.observer.header(event)
            }
        }

        let source = "/proc/first(value=1)\n    return\n/proc/reused(value=1)\n    return\n/proc/last()\n    return\n";
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 32 << 20, &|| Ok(()));
        let mut consumer = FailThird { observer: OriginalSignatureObserver::new(&a).unwrap(), seen: 0 };
        let result = dm_syntax::parse_original_declaration_skeleton_with_observer_using(
            source, &a, Some(&mut consumer),
        );
        assert_eq!(result.err().unwrap().raw_os_error(), Some(1450));
        let before = used.load(Ordering::Acquire);
        let observed = consumer.observer.retention_for_trace();
        assert_eq!(observed.rows, 2);
        assert_eq!(observed.row_capacity, 4);
        assert_eq!(observed.row_buffer_bytes, 4 * std::mem::size_of::<Row>());
        assert_eq!(observed.above_floor_rows, 1, "first symbol spelling grows, reuse reconciles");
        assert_eq!(observed.completed_header_bytes,
            observed.reconciliation_floor_bytes + observed.above_floor_bytes);
        assert_eq!(observed.largest_header_start, Some(0));
        assert_eq!(observed.unavailable_floor_rows, 0);
        assert_eq!(a.retained_bytes_for_trace(), before);
        assert_eq!(before, observed.row_buffer_bytes + observed.completed_header_bytes);
        drop(consumer);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn pending_row_replacement_preserves_actual_peak_and_first_io() {
        use std::cell::Cell;
        struct Payload(Arc<AtomicUsize>);
        impl Drop for Payload {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::Relaxed);
            }
        }

        let used = Arc::new(AtomicUsize::new(0));
        let dropped = Arc::new(AtomicUsize::new(0));
        let item = std::mem::size_of::<Payload>();
        let healthy = SettingAdmission::new(&used, 32 << 20, &|| Ok(()));
        let mut storage = None;
        let mut rows = Vec::new();
        grow_funded_rows(&mut rows, &mut storage, &healthy).unwrap();
        for _ in 0..4 {
            rows.push(Payload(Arc::clone(&dropped)));
        }
        let old = rows.as_ptr();
        let at = Cell::new(0);
        let fault = || {
            at.set(at.get() + 1);
            if at.get() == 2 {
                assert_eq!(used.load(Ordering::Acquire), (4 + 8) * item);
                return Err(std::io::Error::from_raw_os_error(1450));
            }
            Ok(())
        };
        let failed = SettingAdmission::new(&used, 12 * item, &fault);
        assert_eq!(grow_funded_rows(&mut rows, &mut storage, &failed)
            .unwrap_err().raw_os_error(), Some(1450));
        assert_eq!(rows.as_ptr(), old);
        assert_eq!(rows.len(), 4);
        assert_eq!(used.load(Ordering::Acquire), 4 * item);
        assert_eq!(dropped.load(Ordering::Relaxed), 0);

        let too_small = SettingAdmission::new(&used, 12 * item - 1, &|| Ok(()));
        assert_eq!(grow_funded_rows(&mut rows, &mut storage, &too_small)
            .unwrap_err().kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(rows.as_ptr(), old);
        assert_eq!(used.load(Ordering::Acquire), 4 * item);

        let exact = SettingAdmission::new(&used, 12 * item, &|| Ok(()));
        grow_funded_rows(&mut rows, &mut storage, &exact).unwrap();
        assert_ne!(rows.as_ptr(), old);
        assert_eq!((rows.len(), rows.capacity()), (4, 8));
        assert_eq!(storage.as_ref().unwrap().bytes(), 8 * item);
        assert_eq!(used.load(Ordering::Acquire), 8 * item);
        assert_eq!(dropped.load(Ordering::Relaxed), 0);
        drop(rows);
        drop(storage);
        assert_eq!(dropped.load(Ordering::Relaxed), 4);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn row_growth_funds_both_exact_allocations_and_preserves_old_rows_on_failure() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 32 << 20, &|| Ok(()));
        let source = "/proc/first()\n    return\n/proc/second()\n    return\n/proc/third()\n    return\n/proc/fourth()\n    return\n";
        let mut observer = OriginalSignatureObserver::new(&a).unwrap();
        let primary = dm_syntax::parse_original_declaration_skeleton_with_observer_using(source, &a, Some(&mut observer)).unwrap();
        assert_eq!((observer.rows.len(), observer.rows.capacity()), (4, 4));
        let row_bytes = std::mem::size_of::<Row>();
        assert_eq!(observer.row_storage.as_ref().unwrap().bytes(), 4 * row_bytes);
        let retained = used.load(Ordering::Acquire);
        let old = observer.rows.as_ptr();
        let tight = SettingAdmission::new(&used, retained + 8 * row_bytes - 1, &|| Ok(()));
        observer.a = &tight;
        assert_eq!(observer.grow_rows().unwrap_err().kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(observer.rows.as_ptr(), old);
        assert_eq!(observer.rows.len(), 4);
        assert_eq!(used.load(Ordering::Acquire), retained);
        let exact = SettingAdmission::new(&used, retained + 8 * row_bytes, &|| Ok(()));
        observer.a = &exact;
        observer.grow_rows().unwrap();
        assert_ne!(observer.rows.as_ptr(), old);
        assert_eq!((observer.rows.len(), observer.rows.capacity()), (4, 8));
        assert_eq!(observer.row_storage.as_ref().unwrap().bytes(), 8 * row_bytes);
        assert_eq!(used.load(Ordering::Acquire), retained + 4 * row_bytes);
        drop((observer, primary));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}
/// Deliberately not ColdFrontend/Tree/compiled input. The partial-model owner
/// must retain its genuine parser/signature leases and honor all outcomes.
pub(crate) struct OriginalSignatureInput{
 pub(crate) items:Vec<Item>,pub(crate) diagnostics:Vec<dm_syntax::Diagnostic>,
 pub(crate) comma_fatal:Option<dm_syntax::OriginalDeclarationFatal>,
 pub(crate) unavailable:Option<&'static str>,pub(crate) observer_stop:Option<Span>,
 pub(crate) signature_failure:Option<SignatureError>,pub(crate) signature_unsupported:Option<String>,
 pub(crate) source:SourceText,pub(crate) headers:Arc<OriginalProcedureHeaders>,
 pub(crate) symbols:SymbolTable,pub(crate) prepared:PreparedOriginalSignatures,
 pub(crate) primary_lease:dm_syntax::SettingRootLease,
}
impl<'a,'b> OriginalSignatureObserver<'a,'b>{
 /// SAME signature producer state, created before genuine token demand starts.
 /// This allocates no header products or symbols speculatively.
 pub(crate) fn new(a:&'a SettingAdmission<'b>)->std::io::Result<Self>{checkpoint(a)?;Ok(Self{a,symbols:SymbolTable::default(),rows:Vec::new(),row_storage:None,failure_storage:None,failure:None,unsupported:None,early:None,defaults:Vec::new(),inputs:Vec::new(),input_storage:None,default_storage:None,stream_failed:false,failure_live:None,failure_head_data:None,notices:None,notices_complete:true})}
 /// Consume the actual stream-issued primary product exactly once. The source
 /// and neutral literal binding are authenticated together; no parse/expand or
 /// alternate SymbolTable is introduced at this handoff.
 pub(crate) fn finish_primary(mut self,source:SourceText,primary:dm_syntax::OriginalDeclarationSkeleton,literal_source:Option<&dm_preprocess::regions::OriginalLiteralSourceBinding>)->Result<OriginalSignatureInput,OriginalHeaderFailure>{
 let a=self.a;
 if self.stream_failed{return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"failed actual formal stream cannot issue a primary model")))}
 let observer_stop=primary.observer_stop();
 for row in &mut self.rows{
  match row.producer.take(){Some(producer)if primary.same_primary_producer(&producer)=>(),Some(_)=>return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"completed signature belongs to a foreign actual primary owner"))),None if literal_source.is_some()=>return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"streamed signature lacks its actual live primary owner"))),None=>()}
 }
 match self.failure_live.take(){Some(live)if primary.same_primary_header(&live)=>(),Some(_)=>return Err(OriginalHeaderFailure::Operational(std::io::ErrorKind::InvalidInput.into())),None if self.failure.is_some()&&literal_source.is_some()=>return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"streamed signature failure lacks actual primary ownership"))),None=>()}
 for pending in &self.defaults{checkpoint(a)?;if !primary.same_primary_header(&pending.live){return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"demanded default belongs to another actual primary producer")))}}
 for input in &self.inputs{checkpoint(a)?;if !primary.same_primary_header(&input.live){return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"input annotation belongs to another actual primary owner")))}}
 if let Some(early)=&self.early{if !primary.same_primary_header(&early.live){return Err(OriginalHeaderFailure::Operational(std::io::ErrorKind::InvalidInput.into()))}}
 let(syntax,comma_fatal,unavailable,primary_lease)=primary.into_parts();
 if !a.matches_lease_domain(&primary_lease){return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"streamed primary belongs to another actual resource owner")))}
 let headers=OriginalProcedureHeaders::for_declaration_profile_tokens(source.clone(),&syntax.items,0,syntax.tokens,a,true)?;
 if let Some(binding)=literal_source{
  let view=binding.checked_view(&source,Span::new(0,source.len()),binding,a).map_err(OriginalHeaderFailure::Operational)?;
  headers.retain_original_literal_facts(Some(view),Some(binding),a)?;
  if let Some((span,data))=self.failure_head_data.take(){let facts=headers.original_literal_facts()?.ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual rejected head has no final neutral-value binding")))?;let(rows,origin)=facts.raw_parts();let span=Span::new(span.start.checked_add(origin).ok_or_else(||std::io::Error::from(std::io::ErrorKind::InvalidInput))?,span.end.checked_add(origin).ok_or_else(||std::io::Error::from(std::io::ErrorKind::InvalidInput))?);let at=rows.partition_point(|(p,_)|p.start<span.start);if rows.get(at).filter(|(p,_)|*p==span).is_none_or(|(_,actual)|!data.same_owner(actual)){return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"rejected formal VALUE belongs to another actual primary occurrence")))}}

  let mut roots=headers.new_default_roots(self.defaults.len(),binding,a).map_err(OriginalHeaderFailure::Operational)?;
  for row in &mut self.rows{checkpoint(a)?;let signature=row.signature.as_mut().ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual formal metadata was consumed before clause publication")))?;if !signature.original_clauses_complete{return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"streamed formal expression clauses lack their actual native producer")))}let clauses=std::mem::take(&mut signature.original_clauses);headers.add_produced_clauses(&mut roots,row.header,row.argument_offset,&signature.signature.parameters,clauses,Arc::clone(&row._lease),a).map_err(OriginalHeaderFailure::Operational)?;}

  for pending in self.defaults{
   checkpoint(a)?;let found=self.rows.binary_search_by_key(&pending.live.start(),|row|row.header.start);
   let row=match found{Ok(index)=>&self.rows[index],Err(_)if observer_stop.is_some_and(|span|span.start==pending.live.start())=>continue,Err(_)=>return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"demanded default has no actual completed header or genuine stop frontier")))};
   let signature=row.signature.as_ref().ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual default metadata was consumed before primary publication")))?;let parameter=signature.signature.parameters.get(pending.root.parameter).ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual demanded parameter slot is absent")))?;
   headers.add_default_root(&mut roots,row.header,row.argument_offset,parameter,&self.symbols,pending.root,a).map_err(OriginalHeaderFailure::Operational)?;
  }
  // The default IntoIter freed its moved buffer; root payloads own their leases.
  self.default_storage = None;
  for pending in self.inputs{
   checkpoint(a)?;let index=match self.rows.binary_search_by_key(&pending.live.start(),|row|row.header.start){Ok(index)=>index,Err(_)if observer_stop.is_some_and(|span|span.start==pending.live.start())=>continue,Err(_)=>return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"input annotation has no actual completed header or genuine stop frontier")))};let row=&self.rows[index];let parameter=row.signature.as_ref().and_then(|signature|signature.signature.parameters.get(pending.parameter)).ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual native input parameter metadata absent")))?;
   headers.add_input_root(&mut roots,row.header,row.argument_offset,parameter,&self.symbols,pending.parameter,pending.marker,pending.input,a).map_err(OriginalHeaderFailure::Operational)?;
  }
  self.input_storage = None;
  headers.install_default_roots(roots,a).map_err(OriginalHeaderFailure::Operational)?;
 }else if !self.defaults.is_empty()||!self.inputs.is_empty()||self.failure_head_data.is_some(){return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"demanded default stream has no genuine final literal/source binding")))}
 if self.notices.is_none(){self.notices=Some(super::original_formal_notices::FormalNotices::new(a)?)}
 headers.install_original_formal_notices(self.notices.take().expect("actual formal event ledger"),self.notices_complete,a).map_err(OriginalHeaderFailure::Operational)?;
 headers.install_parameter_signatures(a).map_err(OriginalHeaderFailure::Operational)?;
 drop(self.default_storage);drop(self.input_storage);
 checkpoint(a)?;
 let spellings=OriginalSignatureSpellings::capture(&self.symbols,a).map_err(OriginalHeaderFailure::Operational)?;
 let interrupted_storage=self.early.take().and_then(|early|{
    let changed= self.symbols.local_storage().spelling_delta_without_bucket_growth(early.symbol_shape)!=Some(0);
    if changed { Some(Arc::new(early.credit)) } else { None }
 });
 let prepared=PreparedOriginalSignatures{headers:Arc::clone(&headers),rows:self.rows,row_storage:self.row_storage,spellings,
   failure_storage:self.failure_storage.map(Arc::new),interrupted_storage,input_failure_message:None,canonical_storage:None};
 Ok(OriginalSignatureInput{items:syntax.items,diagnostics:syntax.diagnostics,comma_fatal,unavailable,observer_stop,signature_failure:self.failure,signature_unsupported:self.unsupported,source,headers,symbols:self.symbols,prepared,primary_lease})
 }
}
pub(crate) fn parse_original_signatures_using(source:SourceText,a:&SettingAdmission<'_>)->Result<OriginalSignatureInput,OriginalHeaderFailure>{
 let mut observer=OriginalSignatureObserver::new(a)?;
 let primary=dm_syntax::parse_original_declaration_skeleton_with_observer_using(&source,a,Some(&mut observer))?;
 observer.finish_primary(source,primary,None)
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 fn prepared(source:SourceText,a:&SettingAdmission<'_>)->OriginalSignatureInput{match parse_original_signatures_using(source,a){Ok(actual)=>actual,Err(OriginalHeaderFailure::Source(actual))=>panic!("unexpected native signature source preparation refusal: {actual}"),Err(OriginalHeaderFailure::Operational(actual))=>panic!("unexpected native signature operational preparation refusal: {actual}")}}

 #[test]fn genuine_primary_signature_fatal_precedes_future_type_parent_prescan_and_keeps_actual_prefix(){
  let source:SourceText="/datum/kept\n    var/value=1\n/proc/good(obj/value)\n    return value\n/proc/bad(value=)\n    return 1\n/datum/later\n    parent_type=/datum/missing\n".into();let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,1<<26,&||Ok(()));
  let before=super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get());let mut input=prepared(source.clone(),&a);assert_eq!(super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before+2,"same genuine signature producer runs once per encountered formal header");
  assert_eq!(input.items.len(),2);assert_eq!(input.items[0].header,"/datum/kept");assert_eq!(input.items[1].header,"/proc/good(obj/value)");assert!(input.comma_fatal.is_none());assert!(input.unavailable.is_none());assert!(input.signature_unsupported.is_none());let error=input.signature_failure.as_ref().unwrap();assert_eq!(error.message,"missing expression");let fatal=error.original_fatal.as_ref().unwrap();let at=source.find("value=)").unwrap()+"value=".len();assert_eq!(fatal.at,Span::new(at,at+1));assert_eq!(fatal.following,super::super::OriginalParameterFollowing::MissingDefault(')'));assert!(input.observer_stop.is_some());
  let header=input.items[1].header_span;let(parsed,argument_offset)=input.prepared.take(header,0,&input.headers).unwrap();assert_eq!(argument_offset,"/proc/good(".len());assert_eq!(input.symbols.text(parsed.signature.parameters[0].name),Some("value"));assert_eq!(input.prepared.remaining(),0);assert!(input.prepared.take(header,0,&input.headers).is_err(),"prepared formal metadata cannot be replayed");assert_eq!(super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before+2);
 }
 #[test]fn no_callable_headers_allocate_no_signature_product_or_row_geometry(){
  let source:SourceText=format!("// {}\n/datum/value\n    var/item=1\n","unrelated declaration comment ".repeat(2048)).into();let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,1<<27,&||Ok(()));let before=super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get());let input=prepared(source,&a);assert_eq!(super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before);assert!(input.prepared.rows.is_empty());assert_eq!(input.prepared.rows.capacity(),0);assert!(input.prepared.row_storage.is_none());assert!(input.prepared.failure_storage.is_none());assert!(input.headers.checker_body_profile());
 }
 #[test]fn demanded_header_admission_refuses_before_signature_interpretation_and_releases_primary(){
  struct Block<'a,'b>{inner:OriginalSignatureObserver<'a,'b>,entered:bool,held:Option<dm_syntax::SettingRootLease>}
  impl OriginalDeclarationHeaderObserver for Block<'_,'_>{fn header(&mut self,event:OriginalPrimaryHeader<'_>)->std::io::Result<OriginalHeaderFlow>{self.entered=true;self.held=Some(self.inner.a.reserve(96<<10)?);self.inner.header(event)}}
  let source="/proc/required(value=1)\n    return value\n";let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,128<<10,&||Ok(()));let before=super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get());let inner=OriginalSignatureObserver::new(&a).unwrap();let mut block=Block{inner,entered:false,held:None};
  let actual=dm_syntax::parse_original_declaration_skeleton_with_observer_using(source,&a,Some(&mut block)).err().unwrap();assert!(block.entered,"genuine primary parser reached the actual formal header");assert!(block.held.is_some(),"fault reservation itself succeeded; demanded signature funding is the rejected allocation");assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before);assert!(block.inner.rows.is_empty());assert!(block.inner.failure.is_none());assert_eq!(counter.load(Ordering::Acquire),block.held.as_ref().unwrap().bytes(),"failed primary dropped every own allocation reservation");drop(block);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn primary_signature_prepared_metadata_rejects_foreign_header_owner_and_typed_fault(){
  let source:SourceText="/proc/good(value=1)\n    return value\n".into();let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,1<<26,&||Ok(()));let mut first=prepared(source.clone(),&a);let second=prepared(source,&a);assert!(first.prepared.take(first.items[0].header_span,0,&second.headers).is_err());assert_eq!(first.prepared.remaining(),1);
  drop(first);drop(second);assert_eq!(counter.load(Ordering::Acquire),0);let fault=||Err(std::io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&counter,1<<26,&fault);let Err(OriginalHeaderFailure::Operational(actual))=parse_original_signatures_using("/proc/p()\n    return\n".into(),&a)else{panic!("exact typed native signature preparation failure")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod single_stream_handoff_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]
 fn successful_unchanged_symbol_headers_keep_only_live_signature_allocations() {
  let source:SourceText="/proc/empty()\n    return\n/proc/first(value[2]=1 as num)\n    return\n/proc/reused(value[2]=1 as num)\n    return\n".into();
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,1<<24,&||Ok(()));
  let actual=parse_original_signatures_using(source,&a).unwrap();
  assert!(actual.signature_failure.is_none());
  assert!(actual.signature_unsupported.is_none());
  let rows=&actual.prepared.rows;
  assert_eq!(rows.len(),3);
  let retained=|row:&Row|retained_signature_bytes(row.signature.as_ref().unwrap()).unwrap();
  assert_eq!(rows[0]._lease.bytes(),retained(&rows[0]));
  assert!(rows[1]._lease.bytes()>retained(&rows[1]),"new spellings keep their original envelope");
  assert_eq!(rows[2]._lease.bytes(),retained(&rows[2]));
  assert!(rows[2]._lease.bytes()>rows[0]._lease.bytes(),"arrays, defaults and input tokens remain funded");
  drop(actual);
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn same_primary_signature_observer_moves_actual_products_without_second_formal_parse(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<24,&||Ok(()));let source:SourceText="/proc/first(value=1)\n    return value\n/proc/second(other=2)\n    return other\n".into();let before=super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get());let mut observer=OriginalSignatureObserver::new(&a).unwrap();let primary=dm_syntax::parse_original_declaration_skeleton_with_observer_using(&source,&a,Some(&mut observer)).unwrap();let parsed=super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get());assert_eq!(parsed,before+2);let mut actual=observer.finish_primary(source.clone(),primary,None).unwrap();assert_eq!(super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get()),parsed);assert!(actual.source.same_view(&source));for header in actual.items.iter().map(|item|item.header_span){actual.prepared.take(header,0,&actual.headers).unwrap();}actual.prepared.require_consumed().unwrap();assert_eq!(super::super::SIGNATURE_INTERPRETATIONS.with(|n|n.get()),parsed);drop(actual);assert_eq!(used.load(Ordering::Acquire),0);}
}

impl OriginalSignatureObserver<'_,'_>{
 pub(crate) fn begin_formals(&mut self,live:dm_syntax::OriginalPrimaryLiveHeader)->std::io::Result<()>{
  checkpoint(self.a)?;if self.stream_failed||self.early.is_some()||!matches!(live.kind(),dm_syntax::ItemKind::Proc|dm_syntax::ItemKind::Verb){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual formal owner is already active or is not callable"))}
  let credit=self.a.reserve(1024)?;let next_start=live.argument_start();self.early=Some(EarlyFormals{live,accumulator:super::FormalParameterAccumulator::new_original(),next_start,closed:None,head_assignment:None,head_bytes:0,symbol_shape:self.symbols.local_storage(),credit});Ok(())
 }
 /// Admit/intern the actual native declaration head ONCE before any RHS
 /// source pull. The completed formal consumes this same retained head.
 pub(crate) fn admit_formal_head(&mut self,source:&str,tokens:&[dm_syntax::SpanToken],span:Span,assignment:dm_syntax::SpanToken)->std::io::Result<OriginalHeaderFlow>{
  checkpoint(self.a)?;let early=self.early.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;
  let marker=source.get(assignment.span.range()).ok_or(std::io::ErrorKind::InvalidInput)?;
  if early.closed.is_some()||(early.head_assignment.is_some()&&marker=="=")||span.start!=early.next_start||span.end!=assignment.span.start||!matches!(marker,"="|"["|"as"|"in"|";"){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual formal head does not end at its consumed native marker"))}
  let view=HeaderView::original(source,tokens,span).map_err(|_|std::io::Error::new(std::io::ErrorKind::InvalidData,"formal head escaped actual source/token loan"))?;
  let bytes=header_work_bytes(tokens.len(),span.end-span.start)?.checked_sub(1024).ok_or(std::io::ErrorKind::OutOfMemory)?;let extra=bytes.checked_sub(early.head_bytes).ok_or(std::io::ErrorKind::InvalidData)?;self.a.grow(&mut early.credit,extra)?;
  let start=span.start.checked_sub(early.live.argument_start()).ok_or(std::io::ErrorKind::InvalidInput)?;
  let result=if marker=="["{early.accumulator.prepare_dimension_head(view,start,&mut self.symbols)}else{early.accumulator.admit_prepared_head(view,start,&mut self.symbols)};
  match result{Ok(())=>{if marker=="="{early.head_assignment=Some(assignment.span)}early.head_bytes=bytes;self.drain_live_head_notices()?;Ok(OriginalHeaderFlow::Continue)},Err(error)=>{self.failure=Some(error);self.failure_live=Some(early.live.clone());let early=self.early.take().expect("active failed formal");self.failure_storage=Some(early.credit);Ok(OriginalHeaderFlow::Stop)}}
 }
 /// SAME native declaration head failure at the first actual token. No future
 /// source pull or prefix replay occurs. The scalar's exact producer owner is
 /// retained until final primary/source binding authenticates it.
 pub(crate) fn reject_first_formal_head(&mut self,source:&str,tokens:&[dm_syntax::SpanToken],token:dm_syntax::SpanToken,data:Option<&dm_syntax::OriginalLiteralData>)->std::io::Result<OriginalHeaderFlow>{
  use super::OriginalFormalHeadFollowing as Following;
  checkpoint(self.a)?;let early=self.early.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;
  if early.closed.is_some()||early.head_assignment.is_some()||early.next_start>token.span.start{return Err(std::io::ErrorKind::InvalidInput.into())}
  let before=source.get(early.next_start..token.span.start).ok_or(std::io::ErrorKind::InvalidInput)?;
  if tokens.iter().any(|part|part.span.start<token.span.start&&!matches!(part.kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment))||!before.trim().is_empty(){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual first formal head context has preceding syntax"))}
  if tokens.last().is_none_or(|actual|*actual!=token){return Err(std::io::ErrorKind::InvalidInput.into())}
  let spelling=source.get(token.span.range()).ok_or(std::io::ErrorKind::InvalidInput)?;
  let following=if spelling=="="&&matches!(token.kind,dm_syntax::TokenKind::Punctuation|dm_syntax::TokenKind::Operator){if data.is_some(){return Err(std::io::ErrorKind::InvalidInput.into())}Following::Assignment}else if token.kind==dm_syntax::TokenKind::Number{
   let data=data.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"first numeric formal token has no actual typed value"))?;if data.raw()!=spelling{return Err(std::io::ErrorKind::InvalidInput.into())}
   match data.value(){dm_syntax::OriginalTokenValue::Int(n)=>Following::Integer(n),dm_syntax::OriginalTokenValue::Float(n)=>Following::Float(n.to_bits()),_=>return Err(std::io::ErrorKind::InvalidInput.into())}
  }else{return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"first formal token's original grammar rejection is not issued"))};
  let start=token.span.start.checked_sub(early.live.argument_start()).ok_or(std::io::ErrorKind::InvalidInput)?;let end=token.span.end.checked_sub(early.live.argument_start()).ok_or(std::io::ErrorKind::InvalidInput)?;
  let view=HeaderView::original(source,tokens,token.span).map_err(|_|std::io::ErrorKind::InvalidInput)?;
  let bytes=header_work_bytes(tokens.len(),token.span.end-token.span.start)?.checked_sub(1024).ok_or(std::io::ErrorKind::OutOfMemory)?;self.a.grow(&mut early.credit,bytes)?;
  let mut failure=match early.accumulator.prepare_head(view,start,&mut self.symbols){Err(actual)=>actual,Ok(())=>return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual native formal grammar accepted the purported required-head failure"))};
  let receipt=super::OriginalParameterFatal{at:token.span,following:super::OriginalParameterFollowing::Head(following),prior_outer_block:early.live.prior_outer_block().is_some_and(|at|at<token.span.start)};
  failure.message=receipt.message();failure.source_span=Some(Span::new(start,end));failure.original_fatal=Some(receipt);failure.after_header=false;
  self.failure=Some(failure);self.failure_live=Some(early.live.clone());self.failure_head_data=data.map(|actual|(token.span,actual.clone()));
  let early=self.early.take().expect("actual failed head owner");self.failure_storage=Some(early.credit);Ok(OriginalHeaderFlow::Stop)
 }
 pub(crate) fn formal_default_using(&self,source:&mut dyn dm_syntax::NativeExpressionTokenDemand,clauses:&mut dm_syntax::ParameterClauseCursor)->std::io::Result<super::DemandedFormalDefault>{
  let early=self.early.as_ref().filter(|state|state.closed.is_none()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual live formal owner is absent or closed"))?;if early.head_assignment!=clauses.spans().assignment||early.head_assignment.is_none(){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual native formal head was not admitted before RHS demand"))}early.accumulator.default_using(source,clauses,self.a)
 }
 fn record_formal_notice(&mut self,header:usize,notice:super::OriginalFormalNotice)->std::io::Result<()>{if self.notices.is_none(){self.notices=Some(super::original_formal_notices::FormalNotices::new(self.a)?)}self.notices.as_mut().expect("actual notice owner").push(header,notice,self.a)}
 fn drain_live_head_notices(&mut self)->std::io::Result<()>{let early=self.early.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;let header=early.live.start();let origin=early.live.argument_start();let rows=early.accumulator.take_formal_notices();for notice in rows{self.record_formal_notice(header,notice.checked_shift(origin)?)?;}Ok(())}
 pub(crate) fn observed_input_identifier(&mut self,at:Span,text:&str)->std::io::Result<()>{if !super::original_formal_notices::original_input_name(text){let header=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?.live.start();self.record_formal_notice(header,super::OriginalFormalNotice::new(at,super::original_formal_notices::Kind::BadInput))?;}Ok(())}
 pub(crate) fn observed_trailing_semicolon(&mut self,at:Span)->std::io::Result<()>{let early=self.early.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;let header=early.live.start();let origin=early.live.argument_start();let relative=Span::new(at.start.checked_sub(origin).ok_or(std::io::ErrorKind::InvalidInput)?,at.end.checked_sub(origin).ok_or(std::io::ErrorKind::InvalidInput)?);early.accumulator.mark_semicolon_observed(relative).map_err(|_|std::io::Error::new(std::io::ErrorKind::InvalidData,"actual semicolon producer was repeated"))?;self.record_formal_notice(header,super::OriginalFormalNotice::new(at,super::original_formal_notices::Kind::Semicolon))}
 pub(crate) fn observed_input_after_source(&mut self,at:Span)->std::io::Result<()>{let header=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?.live.start();self.record_formal_notice(header,super::OriginalFormalNotice::new(at,super::original_formal_notices::Kind::InBeforeAs))}
 pub(crate) fn formal_source_using(&self,source:&mut dyn dm_syntax::NativeExpressionTokenDemand,clauses:&mut dm_syntax::ParameterClauseCursor)->std::io::Result<super::DemandedFormalDefault>{let early=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;if !early.accumulator.has_prepared_head(){return Err(std::io::ErrorKind::InvalidInput.into())}early.accumulator.source_using(source,clauses,self.a)}
 pub(crate) fn formal_dimension_using(&self,source:&mut dyn dm_syntax::NativeExpressionTokenDemand,clauses:&mut dm_syntax::ParameterClauseCursor,opening:Span,ordinal:usize)->std::io::Result<super::DemandedFormalDimension>{let early=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;if !early.accumulator.has_prepared_head(){return Err(std::io::ErrorKind::InvalidInput.into())}early.accumulator.dimension_using(source,clauses,opening,ordinal,self.a)}
 pub(crate) fn retain_formal_input(&mut self,marker:Span,input:dm_syntax::RetainedParameterInput)->std::io::Result<()>{
  checkpoint(self.a)?;let early=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;let live=early.live.clone();let parameter=early.accumulator.parameter_ordinal();if !input.is_admitted_by(self.a)||self.inputs.last().is_some_and(|previous|(previous.live.start(),previous.parameter,previous.marker.start)>=(live.start(),parameter,marker.start)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"input annotation is foreign or repeated"))}
  if self.inputs.len() == self.inputs.capacity() {
   grow_funded_rows(&mut self.inputs, &mut self.input_storage, self.a)?;
  }
  self.inputs.push(PendingInput{live,parameter,marker,input});self.early.as_mut().expect("active input formal").accumulator.mark_input_observed();Ok(())
 }
 /// The same Pratt cursor has already rejected the empty default.
 /// A visible semicolon is a genuine boundary, not actual EOF.
 pub(crate) fn reject_empty_semicolon_default(
    &mut self,
    source: &dyn dm_preprocess::regions::OriginalFormalTokenStream,
    failure: &super::DemandedFormalTermFailure,
 )->std::io::Result<OriginalHeaderFlow>{
    let Some(boundary)=failure.boundary.as_ref().filter(|token|token.text==";") else{return Err(std::io::ErrorKind::InvalidInput.into())};
    if failure.expected.token_span().is_some() || !failure.syntax.tokens().is_empty() {
        return Err(std::io::ErrorKind::InvalidInput.into());
    }
    let actual=dm_syntax::SpanToken{kind:boundary.kind,span:boundary.span};
    self.reject_semicolon_frontier(source, actual, super::OriginalParameterFollowing::MissingDefault(';'))
 }
 /// Only an end delivered by the real primary receiver may reject a missing
 /// close delimiter after the just-observed semicolon.
 pub(crate) fn reject_end_after_semicolon(
    &mut self,
    source: &dyn dm_preprocess::regions::OriginalFormalTokenStream,
    semicolon: dm_syntax::SpanToken,
 )->std::io::Result<OriginalHeaderFlow>{
    let early=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;
    let end=source.actual_end()?.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"Original formal EOF has no actual consumed end"))?;
    source.with_current_source(&mut|text,_|{
        if !end.closes(&early.live,text.len()){return Err(std::io::ErrorKind::InvalidInput.into());}
        Ok(())
    })?;
    self.reject_semicolon_frontier(source, semicolon, super::OriginalParameterFollowing::ConsumedEnd)
 }
 fn reject_semicolon_frontier(
    &mut self,
    source: &dyn dm_preprocess::regions::OriginalFormalTokenStream,
    semicolon: dm_syntax::SpanToken,
    following: super::OriginalParameterFollowing,
 )->std::io::Result<OriginalHeaderFlow>{
    checkpoint(self.a)?;
    let early=self.early.as_mut().filter(|state|state.closed.is_none()).ok_or(std::io::ErrorKind::InvalidInput)?;
    if semicolon.span.start<early.next_start || semicolon.span.end.checked_sub(semicolon.span.start)!=Some(1)
       || !matches!(source.current_header_value(semicolon)?,dm_syntax::OriginalTokenValue::Punct(";")) {
        return Err(std::io::ErrorKind::InvalidInput.into());
    }
    let at=semicolon.span;
    let reason=super::OriginalParameterFatal{at,following,prior_outer_block:early.live.prior_outer_block().is_some_and(|start|start<at.start)};
    let message=dm_syntax::admitted_message_using(self.a,&mut early.credit,|out|reason.write_message(out))?;
    let base=early.live.argument_start();
    let relative=Span::new(at.start.checked_sub(base).ok_or(std::io::ErrorKind::InvalidInput)?,at.end.checked_sub(base).ok_or(std::io::ErrorKind::InvalidInput)?);
    self.failure=Some(super::SignatureError{message,source_span:Some(relative),after_header:false,missing_default_end:None,original_fatal:Some(reason),original_input_fatal:None,formal_notices:Vec::new(),formal_notices_complete:true});
    self.failure_live=Some(early.live.clone());
    self.failure_storage=Some(self.early.take().expect("actual failed formal").credit);
    Ok(OriginalHeaderFlow::Stop)
 }
 /// Bind the SAME actual required-input cursor state to the actual live
 /// primary token. No error text is parsed, no source token is pulled here.
 pub(crate) fn reject_input_failure_using(&mut self,source:&dyn dm_preprocess::regions::OriginalFormalTokenStream,native:dm_syntax::OriginalInputFailure,token:dm_syntax::SpanToken)->std::io::Result<OriginalHeaderFlow>{
  checkpoint(self.a)?;if native.token_span()!=Some(token.span){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual input EOF/following-boundary failure binding is unissued"))}
  let early=self.early.as_mut().filter(|state|state.closed.is_none()).ok_or(std::io::ErrorKind::InvalidInput)?;
  if token.span.start<early.next_start||token.span.start>=token.span.end{return Err(std::io::ErrorKind::InvalidInput.into())}
  let value=source.current_header_value(token)?;let mut checked=false;
  source.with_current_source(&mut|text,tokens|{if checked||tokens.last()!=Some(token)||text.get(token.span.range()).is_none(){return Err(std::io::ErrorKind::InvalidInput.into())}checked=true;Ok(())})?;if !checked{return Err(std::io::ErrorKind::InvalidInput.into())}
  let reason=super::OriginalInputParameterFatal{native,at:token.span,prior_outer_block:early.live.prior_outer_block().is_some_and(|at|at<token.span.start)};
  let message=dm_syntax::admitted_message_using(self.a,&mut early.credit,|out|write_input_failure(out,value,native.expected()))?;
  let base=early.live.argument_start();let at=Span::new(token.span.start.checked_sub(base).ok_or(std::io::ErrorKind::InvalidInput)?,token.span.end.checked_sub(base).ok_or(std::io::ErrorKind::InvalidInput)?);
  self.failure=Some(super::SignatureError{message,source_span:Some(at),after_header:false,missing_default_end:None,original_fatal:None,original_input_fatal:Some(reason),formal_notices:Vec::new(),formal_notices_complete:true});self.failure_live=Some(early.live.clone());let early=self.early.take().expect("actual failed input owner");self.failure_storage=Some(early.credit);Ok(OriginalHeaderFlow::Stop)
 }
 pub(crate) fn reject_expression_input_failure_using(&mut self,source:&dyn dm_preprocess::regions::OriginalFormalTokenStream,actual:super::DemandedFormalDefault)->std::io::Result<Option<OriginalHeaderFlow>>{
  let syntax=match &actual{super::DemandedFormalDefault::Complete{root,..}=>&root.syntax,super::DemandedFormalDefault::ExpectedTerm(failure)=>&failure.syntax,super::DemandedFormalDefault::NativeSyntax{syntax,..}=>syntax};let Some(native)=syntax.parsed().original_input_failure()else{return Ok(None)};let at=native.token_span().ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual intrinsic input EOF frontier is unissued"))?;let token=syntax.tokens().iter().find(|token|token.span==at).map(|token|dm_syntax::SpanToken{kind:token.kind,span:token.span}).ok_or(std::io::ErrorKind::InvalidData)?;
  // Keep the actual failed Pratt owner alive through rendering its latest VALUE.
  // The retained message receives its own admitted output bytes; no AST retry.
  let result=self.reject_input_failure_using(source,native,token).map(Some);drop(actual);result
 }
 pub(crate) fn observe_expression_notices(&mut self,syntax:&dm_syntax::DemandedExpression)->std::io::Result<()>{let early=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;let header=early.live.start();let notices=syntax.parsed().original_input_notices().ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual Original expression parser notice producer is unissued"))?;if !notices.is_admitted_by(self.a){return Err(std::io::ErrorKind::InvalidInput.into())}for notice in notices.as_slice(){checkpoint(self.a)?;let span=notice.span();if syntax.tokens().first().is_none_or(|token|token.span.start>span.start)||syntax.tokens().last().is_none_or(|token|token.span.end<span.end){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual primitive parser notice escapes its produced expression"))}self.record_formal_notice(header,super::OriginalFormalNotice::from_primitive(*notice))?;}Ok(())}
 pub(crate) fn observe_stream_expression_notices(&mut self,source:&dyn dm_preprocess::regions::OriginalFormalTokenStream,syntax:&dm_syntax::DemandedExpression)->std::io::Result<()>{
  let early=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?;let header=early.live.start();let argument_start=early.live.argument_start();let notices=syntax.parsed().original_input_notices().ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual Original expression notice owner is unissued"))?;if !notices.is_admitted_by(self.a){return Err(std::io::ErrorKind::InvalidInput.into())}let rows=notices.as_slice();let mut emitted=0;
  let primitive=|this:&mut Self,notice:dm_syntax::OriginalInputNotice|->std::io::Result<()>{checkpoint(this.a)?;let span=notice.span();if syntax.tokens().first().is_none_or(|token|token.span.start>span.start)||syntax.tokens().last().is_none_or(|token|token.span.end<span.end){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual primitive notice escapes its expression"))}this.record_formal_notice(header,super::OriginalFormalNotice::from_primitive(notice))};
  source.visit_member_recoveries(&mut|recovery|{
   let before=recovery.preceding_primitive_notices();if before<emitted||before>rows.len(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"formal recovery/primitive event order differs"))}for notice in &rows[emitted..before]{primitive(self,*notice)?;}emitted=before;
   let separator=recovery.separator_span();let following=recovery.following_span();if separator.start<argument_start||separator.start>=separator.end||following.start<separator.end||following.start>=following.end{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual member recovery escapes active formal source"))}
   let notice=super::OriginalFormalNotice::new(following,super::original_formal_notices::Kind::MissingMember);if self.notices.is_none(){self.notices=Some(super::original_formal_notices::FormalNotices::new(self.a)?)}let value=recovery.actual_value();if matches!(value,dm_syntax::OriginalTokenValue::Ident{..}){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"hidden formal boundary is an actual valid member identifier"))}self.notices.as_mut().expect("actual formal notice owner").push_rendered(header,notice,self.a,|out|dm_syntax::write_original_input_failure(out,Some(value),dm_syntax::OriginalInputExpected::Identifier))
  })?;for notice in &rows[emitted..]{primitive(self,*notice)?;}Ok(())
 }
 pub(crate) fn observe_formal_outcome_notices(&mut self,source:&dyn dm_preprocess::regions::OriginalFormalTokenStream,actual:&super::DemandedFormalDefault)->std::io::Result<()>{match actual{super::DemandedFormalDefault::Complete{root,..}=>self.observe_stream_expression_notices(source,&root.syntax),super::DemandedFormalDefault::ExpectedTerm(failure)=>self.observe_stream_expression_notices(source,&failure.syntax),super::DemandedFormalDefault::NativeSyntax{syntax,..}=>self.observe_stream_expression_notices(source,syntax)}}
 pub(crate) fn retain_formal_expression(&mut self,root:super::DemandedFormalRoot)->std::io::Result<()>{let live=self.early.as_ref().ok_or(std::io::ErrorKind::InvalidInput)?.live.clone();self.retain_default(live,root)}
 fn retain_default(&mut self,live:dm_syntax::OriginalPrimaryLiveHeader,root:super::DemandedFormalRoot)->std::io::Result<()>{
  checkpoint(self.a)?;if self.defaults.last().is_some_and(|row|(row.live.start(),row.root.parameter,row.root.role)>=(live.start(),root.parameter,root.role)){return Err(std::io::ErrorKind::InvalidInput.into())}
  if self.defaults.len() == self.defaults.capacity() {
   grow_funded_rows(&mut self.defaults, &mut self.default_storage, self.a)?;
  }
  self.defaults.push(PendingDefault{live,root});Ok(())
 }
 /// No source borrow survives this call. The actual driver supplies a completed
 /// formal and already-consumed delimiter while the SAME live owner is active.
 pub(crate) fn complete_formal(&mut self,source:&str,tokens:&[dm_syntax::SpanToken],span:Span,following:dm_syntax::SpanToken,default:Option<super::DemandedFormalDefault>)->std::io::Result<OriginalHeaderFlow>{self.complete_formal_using(source,tokens,span,following,default,None)}
 pub(crate) fn complete_formal_produced(&mut self,source:&str,tokens:&[dm_syntax::SpanToken],span:Span,following:dm_syntax::SpanToken,default:Option<super::DemandedFormalDefault>,clauses:dm_syntax::ParameterClauseSpans)->std::io::Result<OriginalHeaderFlow>{self.complete_formal_using(source,tokens,span,following,default,Some(clauses))}
 fn complete_formal_using(&mut self,source:&str,tokens:&[dm_syntax::SpanToken],span:Span,following:dm_syntax::SpanToken,default:Option<super::DemandedFormalDefault>,clauses:Option<dm_syntax::ParameterClauseSpans>)->std::io::Result<OriginalHeaderFlow>{
  checkpoint(self.a)?;let early=self.early.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;
  let following_text=source.get(following.span.range()).ok_or(std::io::ErrorKind::InvalidInput)?;
  if early.closed.is_some()||span.start!=early.next_start||span.end!=following.span.start||following.kind!=dm_syntax::TokenKind::Punctuation||!matches!(following_text,","|")"){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"formal boundary differs from actual live primary cursor"))}
  let view=HeaderView::original(source,tokens,span).map_err(|_|std::io::Error::new(std::io::ErrorKind::InvalidData,"formal source/token loan escapes the actual consumed clause"))?;
  let bytes=header_work_bytes(tokens.len(),span.end.checked_sub(span.start).ok_or(std::io::ErrorKind::InvalidInput)?)?.checked_sub(1024).ok_or(std::io::ErrorKind::OutOfMemory)?;let extra=bytes.checked_sub(early.head_bytes).ok_or(std::io::ErrorKind::InvalidData)?;self.a.grow(&mut early.credit,extra)?;
  let empty_failure=match &default{Some(super::DemandedFormalDefault::ExpectedTerm(failure))=>failure.expected.token_span().is_none()&&failure.syntax.tokens().is_empty()&&failure.boundary.as_ref().is_some_and(|token|token.span==following.span&&token.kind==following.kind&&token.text==following_text),Some(super::DemandedFormalDefault::NativeSyntax{..})=>return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual Original default grammar failure provenance is not issued")),_=>false};
  if matches!(&default,Some(super::DemandedFormalDefault::ExpectedTerm(_)))&&!empty_failure{return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"nonempty default needs its genuine Original Pratt failure branch"))}
  // Metadata consumes the trimmed HeaderView. Its structured missing-default
  // endpoint is that exact trimmed end, not the following token after spacing.
  let missing_metadata_end=view.trim().span().end;
  let base=early.live.argument_start();let start=span.start.checked_sub(base).ok_or(std::io::ErrorKind::InvalidInput)?;let stop=span.end.checked_sub(base).ok_or(std::io::ErrorKind::InvalidInput)?;
  let consumed=match clauses{Some(actual)=>early.accumulator.consume_produced(view,start,stop,following_text==",",&mut self.symbols,actual),None=>early.accumulator.consume(view,start,stop,following_text==",",&mut self.symbols)};self.drain_live_head_notices()?;let early=self.early.as_mut().ok_or(std::io::ErrorKind::InvalidInput)?;
  match consumed{
   Err(mut error)=>{
    if empty_failure&&error.missing_default_end.and_then(|end|end.checked_add(base))==Some(missing_metadata_end){error.original_fatal=Some(super::OriginalParameterFatal{at:following.span,following:super::OriginalParameterFollowing::MissingDefault(if following_text==","{','}else{')'}),prior_outer_block:early.live.prior_outer_block().is_some_and(|at|at<following.span.start)});}
    self.failure=Some(error);self.failure_live=Some(early.live.clone());let early=self.early.take().expect("active failed formal");self.failure_storage=Some(early.credit);Ok(OriginalHeaderFlow::Stop)
   }
   Ok(())=>{
    if empty_failure{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual empty Pratt default did not produce the same native formal failure"))}
    let retained=if let Some(super::DemandedFormalDefault::Complete{root,boundary})=default{let mark=boundary.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"native default lacks its consumed actual boundary"))?;let matches=if matches!(mark.text.as_str(),","|")"){mark.span==following.span&&mark.kind==following.kind&&mark.text==following_text}else{matches!(mark.text.as_str(),"as"|"in")&&mark.kind==dm_syntax::TokenKind::Ident&&mark.span.start>=root.syntax.parsed().expr.as_ref().ok_or(std::io::ErrorKind::InvalidData)?.span.end&&mark.span.end<=span.end&&source.get(mark.span.range())==Some(mark.text.as_str())};if !matches{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"native default delimiter differs from actual formal cursor"))}Some((early.live.clone(),root))}else{None};
    early.head_assignment=None;early.head_bytes=0;early.next_start=following.span.end;if following_text==")"{early.closed=Some(following.span)}if let Some((live,root))=retained{self.retain_default(live,root)?;}Ok(OriginalHeaderFlow::Continue)
   }
  }
 }
}

#[path="original_stream_consumer.rs"]mod original_stream_consumer;

#[cfg(test)]mod live_formal_scope_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 fn push(primary:&mut dm_syntax::OriginalPrimaryDemand<'_,'_,'_>,source:&str,token:&dm_syntax::Token){primary.token(dm_syntax::SpanToken{kind:token.kind,span:token.span}).unwrap();primary.advance(&source[..token.span.end],false).unwrap();}
 #[test]fn genuine_empty_default_stops_at_actual_comma_before_requesting_future_tokens_and_keeps_same_primary_fatal(){
  let source="/proc/p(value=, BAD(1))\n    return\n";let used=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&used,8<<20,&poll);let mut observer=OriginalSignatureObserver::new(&a).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let mut tokens=dm_syntax::lex(source).tokens.into_iter();let mut live=None;let mut clauses=None;
  loop{let token=tokens.next().unwrap();push(&mut primary,source,&token);if token.text=="("{let found=primary.live_callable_header(&source[..token.span.end]).unwrap().unwrap();observer.begin_formals(found.clone()).unwrap();clauses=Some(dm_syntax::ParameterClauseCursor::new(found.argument_start()));live=Some(found);}else if let Some(cursor)=&mut clauses{cursor.push(token.kind,token.span,&token.text);if token.text=="="{let live=live.as_ref().unwrap();let span=Span::new(live.argument_start(),token.span.start);let current=primary.span_tokens();let begin=current.partition_point(|t|t.span.end<=span.start);let end=current.partition_point(|t|t.span.start<span.end);assert!(matches!(observer.admit_formal_head(&source[..token.span.end],&current.range(begin,end).unwrap().iter().collect::<Vec<_>>(),span,dm_syntax::SpanToken{kind:token.kind,span:token.span}).unwrap(),OriginalHeaderFlow::Continue));break;}}}
  let mut feed=||{let token=tokens.next();if let Some(token)=&token{assert_ne!(token.text,"BAD","actual native default asked for future token after genuine empty RHS");push(&mut primary,source,token);}Ok(token)};
  let default=observer.formal_default_using(&mut feed,clauses.as_mut().unwrap()).unwrap();drop(feed);let boundary=match &default{super::super::DemandedFormalDefault::ExpectedTerm(failure)=>failure.boundary.as_ref().unwrap(),_=>panic!("actual expected native term")};let following=dm_syntax::SpanToken{kind:boundary.kind,span:boundary.span};let prefix=&source[..following.span.end];let live=live.unwrap();let span=Span::new(live.argument_start(),following.span.start);let current=primary.span_tokens();let begin=current.partition_point(|t|t.span.end<=span.start);let end=current.partition_point(|t|t.span.start<span.end);assert!(matches!(observer.complete_formal(prefix,&current.range(begin,end).unwrap().iter().collect::<Vec<_>>(),span,following,Some(default)).unwrap(),OriginalHeaderFlow::Stop));primary.observer_stop_live_header(&live).unwrap();let actual=primary.finish(prefix,false).unwrap();assert!(actual.same_primary_header(&live));let input=observer.finish_primary(SourceText::from(prefix),actual,None).unwrap();let fatal=input.signature_failure.as_ref().unwrap().original_fatal.unwrap();assert_eq!(fatal.token_span(),following.span);assert_eq!(fatal.message(),"got ',', expected one of: operator, literal, variable, proc call");assert!(input.items.is_empty());drop(input);drop(live);assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn genuine_empty_default_joins_trimmed_spacing_to_actual_close_or_comma_and_refuses_unissued_boundaries(){
  for source in["/proc/p(value=)\n","/proc/p(value= \t )\n","/proc/p(var/static/value= \t , BAD(1))\n"]{for mode in["actual","foreign_primary","zero","hypothetical_eof"]{
   let used=Arc::new(AtomicUsize::new(0));{
    let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let mut observer=OriginalSignatureObserver::new(&a).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let mut tokens=dm_syntax::lex(source).tokens.into_iter();let mut live=None;let mut clauses=None;
    loop{let token=tokens.next().unwrap();push(&mut primary,source,&token);if token.text=="("{let found=primary.live_callable_header(&source[..token.span.end]).unwrap().unwrap();observer.begin_formals(found.clone()).unwrap();clauses=Some(dm_syntax::ParameterClauseCursor::new(found.argument_start()));live=Some(found);}else if let Some(cursor)=&mut clauses{cursor.push(token.kind,token.span,&token.text);if token.text=="="{let live=live.as_ref().unwrap();let span=Span::new(live.argument_start(),token.span.start);let current=primary.span_tokens();let begin=current.partition_point(|t|t.span.end<=span.start);let end=current.partition_point(|t|t.span.start<span.end);observer.admit_formal_head(&source[..token.span.end],&current.range(begin,end).unwrap().iter().collect::<Vec<_>>(),span,dm_syntax::SpanToken{kind:token.kind,span:token.span}).unwrap();break;}}}
    let mut feed=||{let token=tokens.next();if let Some(token)=&token{assert_ne!(token.text,"BAD","real empty default must stop before following parameter tokens");push(&mut primary,source,token);}Ok(token)};
    let actual=observer.formal_default_using(&mut feed,clauses.as_mut().unwrap()).unwrap();drop(feed);let boundary=match &actual{super::super::DemandedFormalDefault::ExpectedTerm(failure)=>{assert!(failure.expected.token_span().is_none());assert!(failure.syntax.tokens().is_empty());failure.boundary.as_ref().unwrap()},_=>panic!("real native empty expected-term failure")};let following=dm_syntax::SpanToken{kind:boundary.kind,span:boundary.span};let prefix=&source[..following.span.end];let live=live.unwrap();let span=Span::new(live.argument_start(),following.span.start);let current=primary.span_tokens();let begin=current.partition_point(|t|t.span.end<=span.start);let end=current.partition_point(|t|t.span.start<span.end);
    let supplied=match mode{"zero"=>dm_syntax::SpanToken{kind:following.kind,span:Span::new(following.span.start,following.span.start)},"hypothetical_eof"=>dm_syntax::SpanToken{kind:dm_syntax::TokenKind::Newline,span:Span::new(prefix.len(),prefix.len())},_=>following};
    let outcome=observer.complete_formal_produced(prefix,&current.range(begin,end).unwrap().iter().collect::<Vec<_>>(),span,supplied,Some(actual),clauses.unwrap().finish(following.span.start));
    if matches!(mode,"zero"|"hypothetical_eof"){assert!(matches!(outcome,Err(ref error)if matches!(error.kind(),std::io::ErrorKind::InvalidInput|std::io::ErrorKind::InvalidData)));assert!(observer.failure.is_none(),"unissued source boundary must not create fatal receipt");}
    else{assert!(matches!(outcome.unwrap(),OriginalHeaderFlow::Stop));let expected=observer.failure.as_ref().unwrap().original_fatal.expect("typed native failure and exact trimmed metadata endpoint must join");assert_eq!(expected.token_span(),following.span);assert!(expected.message().contains(if source.contains(','){"got ','"}else{"got ')'"}));primary.observer_stop_live_header(&live).unwrap();let real=primary.finish(prefix,false).unwrap();
     if mode=="foreign_primary"{let mut foreign=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();for token in dm_syntax::lex_spans(prefix).tokens{foreign.token(token).unwrap()}foreign.advance(prefix,false).unwrap();let foreign_live=foreign.live_callable_header(prefix).unwrap().expect("actual foreign callable header");foreign.observer_stop_live_header(&foreign_live).unwrap();let foreign=foreign.finish(prefix,false).unwrap();assert!(matches!(observer.finish_primary(SourceText::from(prefix),foreign,None),Err(OriginalHeaderFailure::Operational(ref error))if error.kind()==std::io::ErrorKind::InvalidInput));drop(real);}
     else{let input=observer.finish_primary(SourceText::from(prefix),real,None).unwrap();assert_eq!(input.signature_failure.as_ref().unwrap().original_fatal.unwrap().token_span(),following.span);drop(input);}
    }
   }assert_eq!(used.load(Ordering::Acquire),0,"all actual scope/parse/output resources drop for {mode} in {source:?}");
  }}
 }
 #[test]fn completed_formal_rows_reject_equal_source_foreign_primary_even_without_defaults(){
  let source="/proc/p(x)\n";let used=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&used,8<<20,&poll);let mut observer=OriginalSignatureObserver::new(&a).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let mut live=None;
  for token in dm_syntax::lex(source).tokens{if token.kind==dm_syntax::TokenKind::Newline{primary.token(dm_syntax::SpanToken{kind:token.kind,span:token.span}).unwrap();primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap();}else{push(&mut primary,source,&token);}if token.text=="("{let found=primary.live_callable_header(&source[..token.span.end]).unwrap().unwrap();observer.begin_formals(found.clone()).unwrap();live=Some(found);}if token.text==")"{let span=Span::new(live.as_ref().unwrap().argument_start(),token.span.start);let current=primary.span_tokens();let begin=current.partition_point(|t|t.span.end<=span.start);let end=current.partition_point(|t|t.span.start<span.end);observer.complete_formal(&source[..token.span.end],&current.range(begin,end).unwrap().iter().collect::<Vec<_>>(),span,dm_syntax::SpanToken{kind:token.kind,span:token.span},None).unwrap();}}
  // The SAME observer was lent only while the completed physical header
  // committed; the live formal methods had no competing long-lived loan.
  primary.advance_with_observer(source,true,&mut observer).unwrap();let actual=primary.finish(source,true).unwrap();let mut foreign=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();for token in dm_syntax::lex_spans(source).tokens{foreign.token(token).unwrap()}foreign.advance(source,true).unwrap();let foreign=foreign.finish(source,true).unwrap();assert!(matches!(observer.finish_primary(SourceText::from(source),foreign,None),Err(OriginalHeaderFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::InvalidInput));drop(actual);drop(live);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod early_required_head_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_first_assignment_head_stops_before_default_token_and_keeps_real_prefix_fatal(){
  let source="/proc/p(=BAD(1))\n    return\n";let used=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&used,8<<20,&poll);let mut observer=OriginalSignatureObserver::new(&a).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let mut live=None;let mut stop=None;
  for token in dm_syntax::lex(source).tokens{
   assert_ne!(token.text,"BAD","native head failure requested future token");let actual=dm_syntax::SpanToken{kind:token.kind,span:token.span};primary.token(actual).unwrap();primary.advance(&source[..token.span.end],false).unwrap();
   if token.text=="("{let header=primary.live_callable_header(&source[..token.span.end]).unwrap().unwrap();observer.begin_formals(header.clone()).unwrap();live=Some(header)}
   if token.text=="="{let live=live.as_ref().unwrap();let all=primary.span_tokens();let first=all.partition_point(|t|t.span.end<=live.argument_start());let before=super::super::PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get());assert_eq!(observer.reject_first_formal_head(&source[..token.span.end],&all.range(first,all.len()).unwrap().iter().collect::<Vec<_>>(),actual,None).unwrap(),OriginalHeaderFlow::Stop);assert_eq!(super::super::PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get()),before+1);stop=Some(actual);break}
  }
  let token=stop.unwrap();let live=live.unwrap();primary.observer_stop_live_header(&live).unwrap();let prefix=&source[..token.span.end];let actual=primary.finish(prefix,false).unwrap();let input=observer.finish_primary(SourceText::from(prefix),actual,None).unwrap();let receipt=input.signature_failure.as_ref().unwrap().original_fatal.unwrap();assert_eq!(receipt.token_span(),token.span);assert_eq!(receipt.message(),"got '=', expected one of: ')', ',', '...', '/'");assert_eq!(input.signature_failure.as_ref().unwrap().message,receipt.message());assert!(input.items.is_empty());drop(input);drop(live);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_numeric_head_uses_same_typed_value_and_cannot_publish_without_final_source_binding(){
  let source="/proc/p(1=BAD(1))\n";let used=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=SettingAdmission::new(&used,8<<20,&poll);let mut observer=OriginalSignatureObserver::new(&a).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let mut live=None;let mut stop=None;
  for token in dm_syntax::lex(source).tokens{
   assert_ne!(token.text,"=","numeric required-head error requested a later token");let actual=dm_syntax::SpanToken{kind:token.kind,span:token.span};
   if token.kind==dm_syntax::TokenKind::Number{let data=dm_syntax::OriginalLiteralData::from_value_using(token.text.clone(),dm_syntax::OriginalTokenValue::Int(1),&a).unwrap();primary.token_with_original_literal(actual,data).unwrap()}else{primary.token(actual).unwrap()};primary.advance(&source[..token.span.end],false).unwrap();
   if token.text=="("{let header=primary.live_callable_header(&source[..token.span.end]).unwrap().unwrap();observer.begin_formals(header.clone()).unwrap();live=Some(header)}
   if token.kind==dm_syntax::TokenKind::Number{let live=live.as_ref().unwrap();let all=primary.span_tokens();let first=all.partition_point(|t|t.span.end<=live.argument_start());let data=primary.original_literal_for_span(token.span).unwrap().unwrap();assert_eq!(observer.reject_first_formal_head(&source[..token.span.end],&all.range(first,all.len()).unwrap().iter().collect::<Vec<_>>(),actual,Some(data)).unwrap(),OriginalHeaderFlow::Stop);assert_eq!(observer.failure.as_ref().unwrap().original_fatal.unwrap().message(),"got '1', expected one of: ')', ',', '...', '/'");stop=Some(actual);break}
  }
  let live=live.unwrap();let prefix=&source[..stop.unwrap().span.end];primary.observer_stop_live_header(&live).unwrap();let actual=primary.finish(prefix,false).unwrap();assert!(matches!(observer.finish_primary(SourceText::from(prefix),actual,None),Err(OriginalHeaderFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::Unsupported));drop(live);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod original_absolute_primary_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn genuine_original_primary_selects_absolute_parameter_profile_once_and_prior_absolute_does_not_hide_later_fatal(){
  for text in ["/datum/a\n/proc/p(/datum/a/value)\n    return value\n","/proc/p(/foo)\n    return foo\n"]{let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let input=parse_original_signatures_using(SourceText::from(text),&a).unwrap();assert!(input.signature_failure.is_none());let row=input.prepared.rows.iter().find(|row|row.signature.as_ref().is_some_and(|signature|signature.signature.parameters.len()==1)).unwrap();assert!(row.signature.as_ref().unwrap().declarations.is_empty());drop(input);assert_eq!(used.load(Ordering::Acquire),0);}
  let text="/datum/a\n/proc/p(/datum/a/value, other=, BAD(1))\n    return value\n/proc/future()\n    return\n";let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let input=parse_original_signatures_using(SourceText::from(text),&a).unwrap();let failure=input.signature_failure.as_ref().unwrap();assert_eq!(failure.original_fatal.unwrap().message(),"got ',', expected one of: operator, literal, variable, proc call");assert!(input.observer_stop.is_some());assert!(input.items.iter().all(|item|!item.header.contains("future")));drop(input);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod formal_notice_producer_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn same_original_head_producer_retains_var_static_and_semicolon_registrations_once(){
  let text="/proc/p(var/static/x;)\n    return\n";let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let input=parse_original_signatures_using(SourceText::from(text),&a).unwrap();assert!(input.signature_failure.is_none());let rows=input.headers.all_formal_notices().unwrap().collect::<Vec<_>>();assert_eq!(rows.len(),3);assert_eq!(rows.iter().map(|row|row.registration().0).collect::<Vec<_>>(),[Some("var_in_proc_parameter"),Some("static_in_proc_parameter"),Some("semicolon_in_proc_parameter")]);assert_eq!(rows.iter().map(|row|row.span().start).collect::<Vec<_>>(),[8,8,text.find(';').unwrap()]);assert_eq!(rows[0].static_message(),Some("'var/' is unnecessary here"));assert_eq!(rows[1].registration().1,super::super::OriginalFormalNoticeLevel::Warning);assert!(input.prepared.rows[0].signature.as_ref().unwrap().signature.parameters[0].input_annotation.is_none());drop(input);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_prior_head_notices_survive_later_same_header_fatal_without_future_proc(){
  let text="/proc/p(var/static/value=)\n    return\n/proc/future()\n    return\n";let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let input=parse_original_signatures_using(SourceText::from(text),&a).unwrap();assert!(input.signature_failure.as_ref().unwrap().original_fatal.is_some());let rows=input.headers.all_formal_notices().unwrap().collect::<Vec<_>>();assert_eq!(rows.len(),2);assert_eq!(rows[0].registration().0,Some("var_in_proc_parameter"));assert_eq!(rows[1].registration().0,Some("static_in_proc_parameter"));assert!(input.items.iter().all(|item|!item.header.contains("future")));drop(input);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]
mod body_static_scope_primary_regression {
 use super::*;
 use std::sync::{Arc,atomic::AtomicUsize};
 #[test]
 fn actual_static_scope_call_inside_body_never_issues_a_second_callable_signature(){
  let source:SourceText="/datum/probe\n    var/charge\n/datum/probe/proc/set_charge(value, datum/probe/other)\n    charge = value\n    /datum/probe::probe(set_other())\n".into();
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,16<<20,&||Ok(()));
  let input=parse_original_signatures_using(source,&a).unwrap();
  assert!(input.signature_failure.is_none(),"body call became a signature failure: {:?}",input.signature_failure);
  assert!(input.signature_unsupported.is_none(),"body call became an unsupported callable signature: {:?}",input.signature_unsupported);
  assert!(input.unavailable.is_none(),"valid body source became unavailable");
  assert_eq!(input.prepared.remaining(),1,"only the authored set_charge declaration issues formal metadata");
 }
}

#[cfg(test)]mod original_input_fatal_retention_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 fn actual_failure(a:&SettingAdmission<'_>,text:&str)->dm_syntax::OriginalInputFailure{
  let mut cursor=dm_syntax::ParameterInputCursor::new(a,false).unwrap();
  for token in dm_syntax::lex(text).tokens{match cursor.feed(token.kind,token.span,&token.text){Err(dm_syntax::ParameterInputFailure::Syntax{receipt,..})=>return receipt,Err(dm_syntax::ParameterInputFailure::Operational(error))=>panic!("{error}"),Ok(_)=>()}}
  panic!("fixture must fail through actual consuming input cursor")
 }
 #[test]fn same_input_failure_writer_uses_actual_cursor_expectation_and_typed_value(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(text,value,wanted)in[("1",dm_syntax::OriginalTokenValue::Int(i32::MAX),"got '2.14748e+009', expected one of: '(', identifier"),("(mob)",dm_syntax::OriginalTokenValue::Ident{spelling:"mob",whitespace:false},"got 'mob', expected one of: ')'"),("mob|1",dm_syntax::OriginalTokenValue::String("a\"b"),"got '{\"a\"b\"}', expected one of: identifier")]{
   let failure=actual_failure(&a,text);let mut credit=a.reserve(0).unwrap();let message=dm_syntax::admitted_message_using(&a,&mut credit,|out|write_input_failure(out,value,failure.expected())).unwrap();assert_eq!(message,wanted);assert!(credit.bytes()>=message.capacity());drop(message);drop(credit);
  }assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn prepared_owner_keeps_actual_input_failure_message_until_report_borrow_ends(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut input=parse_original_signatures_using(SourceText::from("/datum/kept\n"),&a).unwrap();let failure=actual_failure(&a,"1");let reason=super::super::OriginalInputParameterFatal{native:failure,at:failure.token_span().unwrap(),prior_outer_block:false};
  let mut credit=a.reserve(0).unwrap();let message=dm_syntax::admitted_message_using(&a,&mut credit,|out|write_input_failure(out,dm_syntax::OriginalTokenValue::Int(i32::MAX),failure.expected())).unwrap();let address=message.as_ptr();input.prepared.failure_storage=Some(Arc::new(credit));input.prepared.retain_input_failure_message(reason,message).unwrap();
  assert_eq!(input.prepared.input_failure_message(reason).unwrap().as_ptr(),address,"retain the actual produced allocation, never regenerate display");let wrong=super::super::OriginalInputParameterFatal{at:Span::new(1,2),..reason};assert!(input.prepared.input_failure_message(wrong).is_none());assert!(used.load(Ordering::Acquire)>0);drop(input);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn input_failure_message_writer_preserves_first_io_and_quota_without_hidden_buffer(){
  let used=Arc::new(AtomicUsize::new(0));let tiny=SettingAdmission::new(&used,1,&||Ok(()));let mut credit=tiny.reserve(0).unwrap();assert_eq!(dm_syntax::admitted_message_using(&tiny,&mut credit,|out|write_input_failure(out,dm_syntax::OriginalTokenValue::String("large"),dm_syntax::OriginalInputExpected::Identifier)).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);drop(credit);assert_eq!(used.load(Ordering::Acquire),0);
  let fail=||Err(std::io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&used,8<<20,&fail);let mut credit=dm_syntax::SettingRootLease::reserve(&used,8<<20,0).unwrap();assert_eq!(dm_syntax::admitted_message_using(&a,&mut credit,|out|write_input_failure(out,dm_syntax::OriginalTokenValue::Int(1),dm_syntax::OriginalInputExpected::Identifier)).unwrap_err().raw_os_error(),Some(1450));drop(credit);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]
mod procedure_canonical_allocation_tests {
    use super::*;
    use std::{cell::Cell, sync::atomic::{AtomicUsize, Ordering}};

    #[test]
    fn prepared_canonical_reconciles_per_call_scratch_and_preserves_first_io() {
        let proc = dm_ir::ProcedureMetadata {
            signature: dm_ir::ProcedureSignature {
                parameters: Arc::from([]),
                variadic: false,
                return_annotation: None,
            },
            settings: Arc::from([]),
        };
        let header: Arc<[u8]> = Arc::from(b"existing lexical canonical".as_slice());
        let mut expected = header.to_vec();
        expected.extend_from_slice(&proc.canonical_bytes());
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 32 << 20, &|| Ok(()));
        let mut held = None;
        let first = append_procedure_canonical(Arc::clone(&header), &proc, &mut held, &a).unwrap();
        assert_eq!(first.as_ref(), expected.as_slice());
        let retained = held.as_ref().unwrap().bytes();
        assert_eq!(used.load(Ordering::Acquire), retained);
        assert_eq!(retained, (2 * std::mem::size_of::<AtomicUsize>() + expected.len())
            .next_multiple_of(std::mem::align_of::<AtomicUsize>()));

        let polls = Cell::new(0);
        let error = || {
            polls.set(polls.get() + 1);
            if polls.get() == 6 {
                return Err(std::io::Error::from_raw_os_error(1450));
            }
            Ok(())
        };
        let failed = SettingAdmission::new(&used, 32 << 20, &error);
        assert_eq!(append_procedure_canonical(Arc::clone(&header), &proc, &mut held, &failed)
            .unwrap_err().raw_os_error(), Some(1450));
        assert_eq!(used.load(Ordering::Acquire), retained);
        assert_eq!(held.as_ref().unwrap().bytes(), retained);

        let too_small = SettingAdmission::new(&used, retained, &|| Ok(()));
        assert_eq!(append_procedure_canonical(Arc::clone(&header), &proc, &mut held, &too_small)
            .unwrap_err().kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(used.load(Ordering::Acquire), retained);
        let second = append_procedure_canonical(Arc::clone(&header), &proc, &mut held, &a).unwrap();
        assert_eq!(second, first);
        assert_eq!(used.load(Ordering::Acquire), retained * 2);
        drop((first, second, held));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}
