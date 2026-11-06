//! Neutral facts on the SAME primary product. No public constructor, Weak,
//! parser, body cache, current-source grant, or independently rebased roster.
use super::*;
use std::{alloc::{alloc,Layout},io,mem,ops::Range,ptr::NonNull,sync::Arc};

type LiteralRow = (Span, crate::OriginalLiteralData);
type BorrowedLiteralRow<'a> = (Span, &'a crate::OriginalLiteralData);
const LITERAL_PAGE_LEN: usize = 256;

// Valid literal spans are nonempty. A maximal start can therefore only be
// represented via a page-local wide ordinal; the packed end is its index.
struct PackedLiteralRow {
    start: u32,
    end: u32,
    data: crate::OriginalLiteralData,
}

struct LiteralPage {
    rows: Vec<PackedLiteralRow>,
    credit: crate::SettingRootLease,
    wide: Vec<Span>,
    wide_credit: Option<crate::SettingRootLease>,
}
struct LiteralPages {
    pages: Vec<LiteralPage>,
    len: usize,
    directory_credit: crate::SettingRootLease,
}

fn allocate_literal_rows<T>(capacity: usize, a: &crate::SettingAdmission<'_>)
    -> io::Result<(Vec<T>, crate::SettingRootLease)>
{
    let layout = Layout::array::<T>(capacity).map_err(|_| io::ErrorKind::OutOfMemory)?;
    assert_ne!(layout.size(), 0);
    let credit = a.reserve(layout.size()).map_err(|e| a.take_operational_error().unwrap_or(e))?;
    let raw = NonNull::new(unsafe { alloc(layout) }.cast::<T>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    // The pointer is an exact funded Global layout, with no initialized rows.
    Ok((unsafe { Vec::from_raw_parts(raw.as_ptr(), 0, capacity) }, credit))
}

impl LiteralPage {
    fn get(&self, index: usize) -> Option<BorrowedLiteralRow<'_>> {
        let row = self.rows.get(index)?;
        let span = if row.start == u32::MAX {
            self.wide[row.end as usize]
        } else {
            Span::new(row.start as usize, row.end as usize)
        };
        Some((span, &row.data))
    }

    fn push(&mut self, (span, data): LiteralRow, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        assert!(self.rows.len() < self.rows.capacity());
        let (start, end) = match (u32::try_from(span.start), u32::try_from(span.end)) {
            (Ok(start), Ok(end)) => (start, end),
            _ => {
                if self.wide.len() == self.wide.capacity() {
                    let capacity = self.wide.capacity().max(1) * 2;
                    debug_assert!(capacity <= LITERAL_PAGE_LEN);
                    let (mut rows, credit) = allocate_literal_rows(capacity, a)?;
                    rows.append(&mut self.wide);
                    drop(mem::replace(&mut self.wide, rows));
                    self.wide_credit = Some(credit);
                }
                let index = u32::try_from(self.wide.len()).expect("wide ordinals fit one literal page");
                self.wide.push(span);
                (u32::MAX, index)
            }
        };
        self.rows.push(PackedLiteralRow { start, end, data });
        Ok(())
    }
}

impl LiteralPages {
    fn get(&self, index: usize) -> Option<BorrowedLiteralRow<'_>> {
        self.pages.get(index / LITERAL_PAGE_LEN)?.get(index % LITERAL_PAGE_LEN)
    }

    fn last(&self) -> Option<BorrowedLiteralRow<'_>> {
        self.get(self.len.checked_sub(1)?)
    }

    fn window(&self) -> OriginalLiteralRows<'_> {
        OriginalLiteralRows { storage: LiteralRowStorage::Pages(self), first: 0, last: self.len }
    }

    fn push(&mut self, row: LiteralRow, a: &crate::SettingAdmission<'_>) -> io::Result<()> {
        let len = self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        if self.len % LITERAL_PAGE_LEN == 0 {
            let (rows, credit) = allocate_literal_rows(LITERAL_PAGE_LEN, a)?;
            let mut page = LiteralPage {
                rows, credit, wide: Vec::new(),
                wide_credit: None,
            };
            page.push(row, a)?;
            if self.pages.len() == self.pages.capacity() {
                let capacity = self.pages.capacity().max(2).checked_mul(2)
                    .ok_or(io::ErrorKind::OutOfMemory)?;
                let (mut pages, directory_credit) = allocate_literal_rows(capacity, a)?;
                pages.append(&mut self.pages);
                drop(mem::replace(&mut self.pages, pages));
                self.directory_credit = directory_credit;
            }
            self.pages.push(page);
        } else {
            self.pages.last_mut().expect("funded literal page").push(row, a)?;
        }
        self.len = len;
        Ok(())
    }

    #[cfg(debug_assertions)]
    fn reservation_bytes(&self) -> usize {
        self.pages.iter().fold(self.directory_credit.bytes(), |bytes, page|
            bytes.saturating_add(page.credit.bytes()).saturating_add(page.wide_credit.as_ref().map_or(0, |credit| credit.bytes())))
    }

    fn visit_storage(&self, visit: &mut impl FnMut(usize,usize,usize)) {
        if self.pages.capacity() != 0 {
            visit(self.pages.as_ptr() as usize, self.pages.len() * mem::size_of::<LiteralPage>(),
                self.pages.capacity() * mem::size_of::<LiteralPage>());
        }
        for page in &self.pages {
            let bytes=page.rows.capacity()*mem::size_of::<PackedLiteralRow>();
            debug_assert_eq!(page.credit.bytes(),bytes);
            visit(page.rows.as_ptr() as usize, page.rows.len()*mem::size_of::<PackedLiteralRow>(),bytes);
            if page.wide.capacity() != 0 {
                let bytes = page.wide.capacity() * mem::size_of::<Span>();
                debug_assert_eq!(page.wide_credit.as_ref().map_or(0, |credit| credit.bytes()), bytes);
                visit(page.wide.as_ptr() as usize, page.wide.len() * mem::size_of::<Span>(), bytes);
            }
            for row in &page.rows {
                row.data.visit_storage(&mut *visit);
            }
        }
        self.directory_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));
    }
}

#[derive(Clone, Copy)]
enum LiteralRowStorage<'a> {
    Pages(&'a LiteralPages),
    Slice(&'a [LiteralRow]),
}

/// A bounded borrowed interval of literal DATA. Creating an interval carries
/// no source or issuance authority. The actual parser/source role still
/// requires an OriginalLiteralFactsView from the authenticated owner.
#[derive(Clone, Copy)]
pub struct OriginalLiteralRows<'a> {
    storage: LiteralRowStorage<'a>,
    first: usize,
    last: usize,
}
impl<'a> OriginalLiteralRows<'a> {
    #[doc(hidden)]
    pub fn from_slice(rows: &'a [(Span,crate::OriginalLiteralData)]) -> Self {
        Self { storage: LiteralRowStorage::Slice(rows), first: 0, last: rows.len() }
    }

    pub fn len(self) -> usize { self.last - self.first }
    pub fn is_empty(self) -> bool { self.len() == 0 }

    pub fn get(self, ordinal: usize) -> Option<(Span, &'a crate::OriginalLiteralData)> {
        if ordinal >= self.len() { return None; }
        let index = self.first + ordinal;
        match self.storage {
            LiteralRowStorage::Pages(rows) => rows.get(index),
            LiteralRowStorage::Slice(rows) => rows.get(index).map(|(span,data)| (*span,data)),
        }
    }

    pub fn iter(self) -> impl DoubleEndedIterator<Item=(Span, &'a crate::OriginalLiteralData)> + ExactSizeIterator {
        (0..self.len()).map(move |index| self.get(index).expect("issued literal fact ordinal"))
    }

    pub fn partition_point(self, mut before: impl FnMut((Span, &'a crate::OriginalLiteralData)) -> bool) -> usize {
        let (mut start, mut end) = (0, self.len());
        while start < end {
            let mid = start + (end - start) / 2;
            if before(self.get(mid).expect("issued literal fact ordinal")) {
                start = mid + 1;
            } else {
                end = mid;
            }
        }
        start
    }

    pub fn range(self, range: Range<usize>) -> Option<Self> {
        if range.start > range.end || range.end > self.len() { return None; }
        Some(Self { storage: self.storage, first: self.first + range.start, last: self.first + range.end })
    }
}

struct Payload{rows:LiteralPages,colons:Vec<(Span,bool)>,extent:Option<usize>,colon_credit:crate::SettingRootLease,fixed_credit:crate::SettingRootLease}
pub struct OriginalPrimaryLiteralFacts(Option<Arc<Payload>>);
impl Clone for OriginalPrimaryLiteralFacts{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live primary facts").clone()))}}
impl Drop for OriginalPrimaryLiteralFacts{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
/// DATA projection only. Actual source-view/backing authorization belongs to
/// the sealed preprocessing/header installer, not these numeric bounds.
pub struct OriginalLiteralFactsView<'a>{rows:OriginalLiteralRows<'a>,colons:&'a[(Span,bool)],origin:usize,owner:&'a Payload}
impl<'a>OriginalLiteralFactsView<'a>{pub fn raw_colons(&self)->(&'a[(Span,bool)],usize){(self.colons,self.origin)}pub fn admitted_by(&self,a:&crate::SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.owner.colon_credit)&&a.matches_lease_domain(&self.owner.rows.directory_credit)&&a.matches_lease_domain(&self.owner.fixed_credit)}pub fn raw_parts(&self)->(OriginalLiteralRows<'a>,usize){(self.rows,self.origin)}pub fn len(&self)->usize{self.rows.len()}pub fn is_empty(&self)->bool{self.rows.is_empty()}}
impl OriginalPrimaryLiteralFacts{
 fn payload(&self)->&Payload{self.0.as_deref().expect("live primary facts")}
 pub(super) fn new(a:&crate::SettingAdmission<'_>)->io::Result<Self>{let fixed_credit=a.reserve(std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;let rows_credit=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;let colon_credit=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self(Some(Arc::new(Payload{rows:LiteralPages{pages:Vec::new(),len:0,directory_credit:rows_credit},colons:Vec::new(),extent:None,colon_credit,fixed_credit}))))}
 pub(super) fn append_actual(&mut self,span:Span,data:crate::OriginalLiteralData,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.extent.is_some()||!a.matches_lease_domain(&owner.rows.directory_credit)||!a.matches_lease_domain(&owner.fixed_credit)||span.start>=span.end||owner.rows.last().is_some_and(|(prior,_)|prior.end>span.start)||owner.colons.last().is_some_and(|(prior,_)|prior.end>span.start){return Err(io::ErrorKind::InvalidInput.into())}
  owner.rows.push((span,data),a)
 }
 pub(super) fn append_actual_colon(&mut self,span:Span,close:bool,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.extent.is_some()||span.end.checked_sub(span.start)!=Some(1)||owner.colons.last().is_some_and(|(prior,_)|prior.end>span.start)||owner.rows.last().is_some_and(|(prior,_)|prior.end>span.start){return Err(io::ErrorKind::InvalidInput.into())}
  if owner.colons.len()==owner.colons.capacity(){let capacity=owner.colons.capacity().checked_mul(2).or_else(||owner.colons.len().checked_add(1)).ok_or(io::ErrorKind::OutOfMemory)?.max(4);let bytes=capacity.checked_mul(std::mem::size_of::<(Span,bool)>()).ok_or(io::ErrorKind::OutOfMemory)?;let credit=a.reserve(bytes).map_err(|e|a.take_operational_error().unwrap_or(e))?;let layout=std::alloc::Layout::array::<(Span,bool)>(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
   // EXACT admitted Global tuple layout; null checked before Vec ownership.
   let raw=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)}).ok_or(io::ErrorKind::OutOfMemory)?;let mut colons=unsafe{Vec::from_raw_parts(raw.as_ptr().cast::<(Span,bool)>(),0,capacity)};colons.append(&mut owner.colons);let old_rows=std::mem::replace(&mut owner.colons,colons);let old_credit=std::mem::replace(&mut owner.colon_credit,credit);drop(old_rows);drop(old_credit);
  }owner.colons.push((span,close));Ok(())
 }

 pub(super) fn seal_actual_frontier(&mut self,extent:usize,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;if owner.extent.is_some()||owner.rows.last().is_some_and(|(span,_)|span.end>extent)||owner.colons.last().is_some_and(|(span,_)|span.end>extent){return Err(io::ErrorKind::InvalidInput.into())}owner.extent=Some(extent);Ok(())
 }
 pub fn is_admitted_by(&self,a:&crate::SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.payload().rows.directory_credit)&&a.matches_lease_domain(&self.payload().colon_credit)&&a.matches_lease_domain(&self.payload().fixed_credit)}
 pub fn consumed_extent(&self)->Option<usize>{self.payload().extent}
 pub fn rows(&self)->OriginalLiteralRows<'_>{self.payload().rows.window()}
 pub fn colon_rows(&self)->&[(Span,bool)]{&self.payload().colons}
 /// Bounds are DATA, not source authorization. Source installer must first
 /// match the SAME real source backing/view, then borrow this no-copy window.
 pub fn checked_data_window(&self,window:Span)->io::Result<OriginalLiteralFactsView<'_>>{
  let owner=self.payload();let extent=owner.extent.ok_or(io::ErrorKind::NotConnected)?;if window.start>window.end||window.end>extent{return Err(io::ErrorKind::InvalidInput.into())}
  let rows=owner.rows.window();let first=rows.partition_point(|(span,_)|span.end<=window.start);let last=rows.partition_point(|(span,_)|span.start<window.end);
  if first<last&&(rows.get(first).unwrap().0.start<window.start||rows.get(last-1).unwrap().0.end>window.end){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source view cuts an issued literal occurrence"))}
  let cf=owner.colons.partition_point(|(span,_)|span.end<=window.start);let cl=owner.colons.partition_point(|(span,_)|span.start<window.end);
  if cf<cl&&(owner.colons[cf].0.start<window.start||owner.colons[cl-1].0.end>window.end){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source view cuts an issued colon occurrence"))}
  Ok(OriginalLiteralFactsView{rows:rows.range(first..last).ok_or(io::ErrorKind::InvalidData)?,colons:&owner.colons[cf..cl],origin:window.start,owner})
 }
 #[cfg(debug_assertions)]
 pub(crate) fn trace_retention(&self)->impl std::fmt::Debug{
  #[derive(Default)]
  struct Census{exclusive_payload_rows:usize,exclusive_payload_reserved:usize,shared_payload_references:usize,shared_payload_reserved_per_reference_upper:usize}
  let owner=self.payload();let mut census=Census::default();
  for (_,data) in owner.rows.window().iter(){
   let (exclusive,bytes)=data.trace_payload();
   if exclusive {
    census.exclusive_payload_rows=census.exclusive_payload_rows.saturating_add(1);
    census.exclusive_payload_reserved=census.exclusive_payload_reserved.saturating_add(bytes);
   } else {
    census.shared_payload_references=census.shared_payload_references.saturating_add(1);
    census.shared_payload_reserved_per_reference_upper=census.shared_payload_reserved_per_reference_upper.saturating_add(bytes);
   }
  }
  // Use a named Debug builder so this snapshot has no owned text or alloc.
  struct Snapshot{rows:usize,colons:usize,fixed:usize,row_capacity:usize,colon_capacity:usize,census:Census}
  impl std::fmt::Debug for Snapshot{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{
   f.debug_struct("PrimaryLiteralCensus").field("rows",&self.rows).field("colons",&self.colons)
    .field("fixed_reserved",&self.fixed).field("row_capacity",&self.row_capacity).field("colon_capacity",&self.colon_capacity)
    .field("exclusive_payload_rows",&self.census.exclusive_payload_rows).field("exclusive_payload_reserved",&self.census.exclusive_payload_reserved)
    .field("shared_payload_references",&self.census.shared_payload_references).field("shared_payload_reserved_per_reference_upper",&self.census.shared_payload_reserved_per_reference_upper).finish()
  }}
  Snapshot{rows:owner.rows.len,colons:owner.colons.len(),fixed:owner.fixed_credit.bytes(),row_capacity:owner.rows.reservation_bytes(),colon_capacity:owner.colon_credit.bytes(),census}
 }
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().expect("live primary facts");let fixed=std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);owner.rows.visit_storage(&mut visit);let n=owner.colons.capacity()*std::mem::size_of::<(Span,bool)>();if n!=0{visit(owner.colons.as_ptr()as usize,n,n)}owner.colon_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));owner.fixed_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[cfg(debug_assertions)]
 #[test]
 fn failed_primary_literal_census_never_counts_shared_payload_as_exclusive(){
  let used=Arc::new(AtomicUsize::new(0));
  let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();
  let data=crate::OriginalLiteralData::from_value_using("7".to_owned(),crate::OriginalTokenValue::Int(7),&a).unwrap();
  let (exclusive,bytes)=data.trace_payload();assert!(exclusive);
  facts.append_actual(Span::new(0,1),data.clone(),&a).unwrap();
  facts.append_actual_colon(Span::new(1,2),false,&a).unwrap();
  facts.append_actual(Span::new(2,3),data,&a).unwrap();
  let before=used.load(Ordering::Acquire);
  let census=format!("{:?}",facts.trace_retention());
  assert!(census.contains("rows: 2, colons: 1"));
  assert!(census.contains("exclusive_payload_rows: 0, exclusive_payload_reserved: 0"));
  assert!(census.contains(&format!("shared_payload_references: 2, shared_payload_reserved_per_reference_upper: {}",2*bytes)));
  assert_eq!(used.load(Ordering::Acquire),before);
  drop(facts);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_same_roster_window_never_copies_or_cuts_literals_and_last_alias_keeps_real_credit(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();let data=crate::OriginalLiteralData::from_value_using("123".to_owned(),crate::OriginalTokenValue::Int(123),&a).unwrap();facts.append_actual(Span::new(5,8),data,&a).unwrap();assert!(facts.checked_data_window(Span::new(0,10)).is_err());facts.seal_actual_frontier(12,&a).unwrap();let view=facts.checked_data_window(Span::new(4,10)).unwrap();let(rows,origin)=view.raw_parts();assert_eq!(origin,4);assert!(std::ptr::eq(rows.get(0).unwrap().1,facts.rows().get(0).unwrap().1));assert_eq!(rows.get(0).unwrap().0,Span::new(5,8));assert!(facts.checked_data_window(Span::new(6,10)).is_err());assert!(facts.checked_data_window(Span::new(0,7)).is_err());assert!(facts.checked_data_window(Span::new(0,13)).is_err());let alias=facts.clone();drop(facts);assert!(used.load(Ordering::Acquire)>0);assert_eq!(alias.rows().len(),1);drop(alias);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod full_slice_parser_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn scalar_facts(raw:&str,value:crate::OriginalTokenValue<&str>,origin:usize,a:&crate::SettingAdmission<'_>)->OriginalPrimaryLiteralFacts{let mut facts=OriginalPrimaryLiteralFacts::new(a).unwrap();let data=crate::OriginalLiteralData::from_value_using(raw.into(),value,a).unwrap();facts.append_actual(Span::new(origin,origin+raw.len()),data,a).unwrap();facts.seal_actual_frontier(origin+raw.len(),a).unwrap();facts}
 #[test]fn actual_full_slice_setting_parser_lends_exact_typed_value_across_checked_tu_window_without_reparse(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let raw="1.23457";let exact=f32::from_bits(0x3f9e0651);let facts=scalar_facts(raw,crate::OriginalTokenValue::Float(exact),113,&a);let lex=crate::lex_spans(raw);
  let root=crate::prepare_setting_expression_with_original_literal_facts(raw,&lex.tokens,Span::new(0,raw.len()),&a,Some(facts.checked_data_window(Span::new(113,113+raw.len())).unwrap())).unwrap();
  let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::Float(value))if value.to_bits()==exact.to_bits()));assert!(literal.original_data().unwrap().same_owner(facts.rows().get(0).unwrap().1));assert_eq!(literal.original_origin(),Some(0));drop(root);assert!(counter.load(Ordering::Acquire)>0);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_full_slice_static_string_uses_one_lexical_value_without_bracket_child_parse_or_runtime_grant(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let raw="\"[missing.field]\"";let facts=scalar_facts(raw,crate::OriginalTokenValue::String("[missing.field]"),0,&a);let lex=crate::lex_spans(raw);
  let root=crate::prepare_setting_expression_with_original_literal_facts(raw,&lex.tokens,Span::new(0,raw.len()),&a,Some(facts.checked_data_window(Span::new(0,raw.len())).unwrap())).unwrap();let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::String("[missing.field]"))));assert!(literal.syntax_parts().unwrap().is_none());drop(root);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_full_slice_missing_fact_and_first_io_do_not_publish_raw_spelling_fallback_or_partial_root(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.seal_actual_frontier(1,&a).unwrap();let lex=crate::lex_spans("1");let result=crate::prepare_setting_expression_with_original_literal_facts("1",&lex.tokens,Span::new(0,1),&a,Some(facts.checked_data_window(Span::new(0,1)).unwrap()));assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==io::ErrorKind::Unsupported));let actual=a.take_operational_error().unwrap();assert_eq!(actual.kind(),io::ErrorKind::Unsupported);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
  let fault=||Err(io::Error::from_raw_os_error(1450));let failed=crate::SettingAdmission::new(&counter,1<<24,&fault);let result=crate::prepare_setting_expression_with_original_literal_facts("1",&lex.tokens,Span::new(0,1),&failed,None);assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==io::Error::from_raw_os_error(1450).kind()));assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 }
 struct BodySource<'a>{source:&'a str,tokens:&'a[crate::SpanToken],facts:&'a OriginalPrimaryLiteralFacts,a:&'a crate::SettingAdmission<'a>}
 impl crate::SettingSyntaxProvider for BodySource<'_>{
  fn setting(&self,_:&crate::Item)->Result<crate::SettingStatement,crate::Diagnostic>{panic!("no initial settings in fixture")}
  fn original_expression(&self,source:&str,offset:usize)->io::Result<Option<crate::ParsedExpr>>{
   if self.source.get(offset..offset+source.len())!=Some(source){return Err(io::ErrorKind::InvalidData.into())}let end=offset+source.len();let first=self.tokens.partition_point(|token|token.span.end<=offset);let last=self.tokens.partition_point(|token|token.span.start<end);
   Ok(Some(crate::parse_expression_original_token_view(self.source,&self.tokens[first..last],offset,self.a,Some(self.facts.checked_data_window(Span::new(0,self.source.len()))?))))
  }
 }
 #[test]fn actual_same_body_statement_parser_lends_one_primary_numeric_fact_to_its_original_root_and_coordinates(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let source="/proc/p()\n    return 1.23457\n";let start=source.find("1.23457").unwrap();let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();let data=crate::OriginalLiteralData::from_value_using("1.23457".into(),crate::OriginalTokenValue::Float(f32::from_bits(0x3f9e0651)),&a).unwrap();facts.append_actual(Span::new(start,start+7),data,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let tokens=crate::lex_spans(source);let ast=crate::parse(source);let provider=BodySource{source,tokens:&tokens.tokens,facts:&facts,a:&a};let parsed=crate::parse_body_items_with_context_and_settings(&ast.items[0].children,source,&|_|None,&provider,&a);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);
  let crate::StatementKind::Return(Some(root))=&parsed.statements[0].kind else{panic!("return")};assert_eq!(root.span,Span::new(start,start+7));let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::Float(value))if value.to_bits()==0x3f9e0651));assert!(literal.original_data().unwrap().same_owner(facts.rows().get(0).unwrap().1));drop(parsed);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod archived_template_source_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn input(prefix:usize,a:&SettingAdmission<'_>)->(String,Vec<SpanToken>,OriginalPrimaryLiteralFacts){
  let raw="\"a[1]b\"";let source=format!("{}{raw}"," ".repeat(prefix));let mut facts=OriginalPrimaryLiteralFacts::new(a).unwrap();
  for(start,end,value)in [(0,3,OriginalTokenValue::InterpBegin("a")),(3,4,OriginalTokenValue::Int(1)),(4,7,OriginalTokenValue::InterpEnd("b"))]{let mode=if start==3{OriginalStringMode::Unknown}else{OriginalStringMode::Normal};let data=OriginalLiteralData::from_value_with_mode_using(raw[start..end].into(),value,mode,a).unwrap();facts.append_actual(Span::new(prefix+start,prefix+end),data,a).unwrap();}
  facts.seal_actual_frontier(source.len(),a).unwrap();let tokens=vec![SpanToken{kind:TokenKind::Interpolation,span:Span::new(prefix,prefix+3)},SpanToken{kind:TokenKind::Number,span:Span::new(prefix+3,prefix+4)},SpanToken{kind:TokenKind::Interpolation,span:Span::new(prefix+4,prefix+7)}];(source,tokens,facts)
 }
 #[test]fn archived_template_borrows_exact_source_and_same_issued_parts_across_shifted_views(){
  for prefix in [0,7]{let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let(source,tokens,facts)=input(prefix,&a);let before=crate::literal::literal_child_parses_for_test();let parsed=crate::parse_expression_original_token_view(&source,&tokens,prefix,&a,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);assert!(a.take_operational_error().is_none());let root=parsed.expr.as_ref().expect("actual typed template");assert_eq!(root.span,Span::new(0,7));let ExprKind::Literal(value)=&root.kind else{panic!("template")};let parts=value.syntax_parts().unwrap().unwrap();assert_eq!(parts.expressions.len(),1);assert_eq!(parts.expressions[0].span,Span::new(3,4));assert!(parts.fragments[0].original.as_ref().unwrap().same_owner(facts.rows().get(0).unwrap().1));assert!(parts.fragments[1].original.as_ref().unwrap().same_owner(facts.rows().get(2).unwrap().1));assert_eq!(crate::literal::literal_child_parses_for_test(),before);drop(parsed);drop(facts);assert_eq!(used.load(Ordering::Acquire),0);}
 }
 #[test]fn archived_template_rejects_missing_facts_and_changed_source_without_guessing_a_template(){
  for missing in [false,true]{let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let(mut source,tokens,facts)=input(0,&a);if !missing{source.replace_range(1..2,"z");}let view=(!missing).then(||facts.checked_data_window(Span::new(0,source.len())).unwrap());let parsed=crate::parse_expression_original_token_view(&source,&tokens,0,&a,view);assert!(parsed.expr.is_none());let failure=a.take_operational_error().expect("explicit unavailable/mismatched data");assert_eq!(failure.kind(),if missing{io::ErrorKind::Unsupported}else{io::ErrorKind::InvalidData});drop(parsed);drop(facts);assert_eq!(used.load(Ordering::Acquire),0);}
 }
}

#[cfg(test)]mod colon_ledger_controls{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn whole_original_colon_uses_same_fact_not_authored_spacing_and_keeps_scalar_rows_separate(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let source="value : key";let tokens=crate::lex_spans(source).tokens;
  for(close,allowed)in[(true,true),(false,false)]{let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.append_actual_colon(Span::new(6,7),close,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();assert!(facts.rows().is_empty());assert_eq!(facts.colon_rows(),[(Span::new(6,7),close)]);let parsed=crate::parse_expression_original_token_view(source,&tokens,0,&a,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert_eq!(parsed.diagnostics.is_empty(),allowed);if allowed{assert!(matches!(parsed.expr.as_ref().unwrap().kind,crate::ExprKind::Member{via_colon:true,..}));}drop(parsed);drop(facts);assert_eq!(used.load(Ordering::Acquire),0);}
  assert!(crate::parse_expression(source).diagnostics.is_empty(),"ordinary compiler path unchanged");
 }
 #[test]fn whole_colon_reuses_exact_fact_window_and_offset_under_shifted_body_input(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let source="prefix value:key";let start=7;let tokens=crate::lex_spans(source).tokens.into_iter().filter(|t|t.span.start>=start).collect::<Vec<_>>();let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.append_actual_colon(Span::new(12,13),true,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let view=facts.checked_data_window(Span::new(0,source.len())).unwrap();let parsed=crate::parse_expression_original_token_view(source,&tokens,start,&a,Some(view));assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);assert_eq!(parsed.expr.as_ref().unwrap().span,Span::new(0,9));assert!(matches!(parsed.expr.as_ref().unwrap().kind,crate::ExprKind::Member{via_colon:true,..}));drop(parsed);let charged=used.load(Ordering::Acquire);let alias=facts.clone();drop(facts);assert_eq!(used.load(Ordering::Acquire),charged);assert_eq!(alias.colon_rows().len(),1);drop(alias);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn whole_colon_missing_and_foreign_facts_are_operational_refusals_not_ordinary_heuristic_fallback(){let one=Arc::new(AtomicUsize::new(0));let two=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&one,8<<20,&||Ok(()));let source="value:key";let tokens=crate::lex_spans(source).tokens;let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let parsed=crate::parse_expression_original_token_view(source,&tokens,0,&a,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert!(parsed.expr.is_none());assert_eq!(a.take_operational_error().unwrap().kind(),io::ErrorKind::Unsupported);drop((parsed,facts));assert_eq!(one.load(Ordering::Acquire),0);
  let fresh=crate::SettingAdmission::new(&one,8<<20,&||Ok(()));let foreign=crate::SettingAdmission::new(&two,8<<20,&||Ok(()));let mut facts=OriginalPrimaryLiteralFacts::new(&fresh).unwrap();facts.append_actual_colon(Span::new(5,6),true,&fresh).unwrap();facts.seal_actual_frontier(source.len(),&fresh).unwrap();let parsed=crate::parse_expression_original_token_view(source,&tokens,0,&foreign,Some(facts.checked_data_window(Span::new(0,source.len())).unwrap()));assert!(parsed.expr.is_none());assert_eq!(foreign.take_operational_error().unwrap().kind(),io::ErrorKind::InvalidInput);drop((parsed,facts));assert_eq!(one.load(Ordering::Acquire),0);assert_eq!(two.load(Ordering::Acquire),0);
 }
 #[test]fn colon_ledger_quota_first_io_and_overlap_refuse_without_leaking_credit(){let used=Arc::new(AtomicUsize::new(0));let good=||Ok(());let a=crate::SettingAdmission::new(&used,8<<20,&good);let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.append_actual_colon(Span::new(2,3),true,&a).unwrap();assert_eq!(facts.append_actual_colon(Span::new(2,3),false,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);let stopped=||Err(io::Error::from_raw_os_error(1450));let fail=crate::SettingAdmission::new(&used,8<<20,&stopped);assert_eq!(facts.append_actual_colon(Span::new(4,5),false,&fail).unwrap_err().raw_os_error(),Some(1450));drop(facts);assert_eq!(used.load(Ordering::Acquire),0);let tiny=crate::SettingAdmission::new(&used,1,&good);assert_eq!(OriginalPrimaryLiteralFacts::new(&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);}
}

#[cfg(test)]
mod literal_page_controls {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn literal_fact_pages_retain_exact_rows_and_refuse_growth_without_flattening() {
        let used=Arc::new(AtomicUsize::new(0));
        let healthy=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut facts=OriginalPrimaryLiteralFacts::new(&healthy).unwrap();
        let data=crate::OriginalLiteralData::from_value_using("12".into(),crate::OriginalTokenValue::Int(12),&healthy).unwrap();
        for row in 0..LITERAL_PAGE_LEN {
            facts.append_actual(Span::new(row*3,row*3+2),data.clone(),&healthy).unwrap();
        }
        let first=facts.rows().get(0).unwrap().1 as *const crate::OriginalLiteralData;
        let retained=used.load(Ordering::Acquire);
        let page_bytes=LITERAL_PAGE_LEN*mem::size_of::<PackedLiteralRow>();
        #[cfg(target_pointer_width = "64")]
        assert_eq!(mem::size_of::<LiteralRow>() - mem::size_of::<PackedLiteralRow>(), 8);
        let next=Span::new(LITERAL_PAGE_LEN*3,LITERAL_PAGE_LEN*3+2);
        let tight=crate::SettingAdmission::new(&used,retained+page_bytes-1,&||Ok(()));
        assert_eq!(facts.append_actual(next,data.clone(),&tight).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
        assert_eq!(facts.rows().len(),LITERAL_PAGE_LEN);
        assert_eq!(used.load(Ordering::Acquire),retained);
        let fault=crate::SettingAdmission::new(&used,retained+page_bytes,&||Err(io::Error::from_raw_os_error(1450)));
        assert_eq!(facts.append_actual(next,data.clone(),&fault).unwrap_err().raw_os_error(),Some(1450));
        let exact=crate::SettingAdmission::new(&used,retained+page_bytes,&||Ok(()));
        facts.append_actual(next,data.clone(),&exact).unwrap();
        assert_eq!(facts.rows().get(0).unwrap().1 as *const crate::OriginalLiteralData,first);
        assert_eq!(used.load(Ordering::Acquire),retained+page_bytes);
        facts.seal_actual_frontier(next.end,&exact).unwrap();

        let previous=Span::new(next.start-3,next.start-1);
        let (window,origin)=facts.checked_data_window(Span::new(previous.start,next.end)).unwrap().raw_parts();
        assert_eq!(origin,previous.start);
        assert_eq!(window.iter().map(|row|row.0).collect::<Vec<_>>(),[previous,next]);
        assert_eq!(window.partition_point(|row|row.0.start<next.start),1);
        assert!(window.get(1).unwrap().1.same_owner(&data));
        assert!(window.range(1..2).unwrap().get(0).unwrap().1.same_owner(&data));
        assert!(window.range(1..3).is_none());
        assert!(facts.checked_data_window(Span::new(next.start+1,next.end)).is_err());

        let alias=facts.clone();
        drop(facts);
        assert_eq!(used.load(Ordering::Acquire),retained+page_bytes);
        drop((alias,data));
        assert_eq!(used.load(Ordering::Acquire),0);
    }
    #[cfg(target_pointer_width = "64")]
    #[test]
    fn literal_fact_pages_preserve_wide_spans_and_refuse_unfunded_fallback() {
        let used = Arc::new(AtomicUsize::new(0));
        let healthy = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut facts = OriginalPrimaryLiteralFacts::new(&healthy).unwrap();
        let data = crate::OriginalLiteralData::from_value_using(
            "7".into(), crate::OriginalTokenValue::Int(7), &healthy,
        ).unwrap();
        let edge = u32::MAX as usize;
        let narrow = Span::new(edge - 1, edge);
        let crossing = Span::new(edge, edge + 1);
        let wide = Span::new(edge + 2, edge + 3);
        facts.append_actual(narrow, data.clone(), &healthy).unwrap();
        let narrow_data = facts.rows().get(0).unwrap().1 as *const crate::OriginalLiteralData;
        let before = used.load(Ordering::Acquire);
        let denied = crate::SettingAdmission::new(&used, before + 2 * mem::size_of::<Span>() - 1, &|| Ok(()));
        assert_eq!(facts.append_actual(crossing, data.clone(), &denied).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(used.load(Ordering::Acquire), before);
        assert_eq!(facts.rows().len(), 1);

        facts.append_actual(crossing, data.clone(), &healthy).unwrap();
        facts.append_actual(wide, data.clone(), &healthy).unwrap();
        assert_eq!(used.load(Ordering::Acquire), before + 2 * mem::size_of::<Span>());
        assert_eq!(facts.rows().get(0).unwrap().1 as *const crate::OriginalLiteralData, narrow_data);
        facts.seal_actual_frontier(wide.end, &healthy).unwrap();
        let (all, _) = facts.checked_data_window(Span::new(narrow.start, wide.end)).unwrap().raw_parts();
        assert!(all.iter().all(|(_, retained)| retained.same_owner(&data)));
        assert_eq!(all.iter().map(|(span, _)| span).collect::<Vec<_>>(), [narrow, crossing, wide]);
        assert_eq!(all.partition_point(|(span, _)| span.start < wide.start), 2);
        let mut visited_wide = false;
        facts.visit_storage(|ptr, len, capacity| {
            if ptr == facts.payload().rows.pages[0].wide.as_ptr() as usize {
                visited_wide = true;
                assert_eq!(len, 2 * mem::size_of::<Span>());
                assert_eq!(capacity, len);
            }
        });
        assert!(visited_wide);
        drop((facts, data));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}
