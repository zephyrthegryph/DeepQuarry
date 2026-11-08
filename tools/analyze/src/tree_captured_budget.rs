//! Capture-only admission for the EXISTING source views. No lexer/parser/model.
//! Reservations cover builder high-water; completed owners are charged by the
//! same live allocation census used elsewhere. Legacy SourceFiles have no budget.
use super::{PolicyStorageClass as K, PolicyStorageKey, View};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

pub(super) const OWNER_METADATA: usize = 8192;
struct State {
    limit: usize,
    base: usize,
    reserved: usize,
    owners: BTreeMap<PolicyStorageKey, usize>,
    error: Option<String>,
    demand: Demand,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum Demand {
    General,
    RawClean,
    RawCode,
}
pub(super) struct Budget(Mutex<State>);
pub(super) struct Reservation<'a> {
    budget: &'a Budget,
    amount: usize,
}

impl Budget {
    pub(super) fn new(limit: usize, metadata: usize) -> Result<Arc<Self>, String> {
        let base = metadata
            .checked_add(OWNER_METADATA)
            .ok_or("captured view metadata overflow")?;
        if base > limit {
            return Err("captured source metadata exceeds available input budget".into());
        }
        Ok(Arc::new(Self(Mutex::new(State {
            limit,
            base,
            reserved: 0,
            owners: BTreeMap::new(),
            error: None, demand: Demand::General,
        }))))
    }
    fn used(s: &State) -> Option<usize> {
        s.owners
            .values()
            .try_fold(s.base, |n, bytes| n.checked_add(*bytes))
    }
    pub(super) fn charge(&self) -> usize {
        let s = self.0.lock().unwrap_or_else(|e| e.into_inner());
        Self::used(&s).unwrap_or(usize::MAX)
    }
    pub(super) fn scoped(&self) -> bool {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).limit != usize::MAX
    }
    pub(super) fn error(&self) -> Option<String> {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .error
            .clone()
    }
    pub(super) fn restrict(&self, demand: Demand) {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).demand = demand;
    }
    pub(super) fn require_view(&self, demand: Demand) -> bool {
        let mut state = self.0.lock().unwrap_or_else(|e| e.into_inner());
        if state.demand != Demand::General && state.demand != demand {
            state.error.get_or_insert_with(|| "this captured loan did not fund the requested derived view".into());
        }
        state.error.is_none()
    }
    pub(super) fn reserve(&self, bytes: Option<usize>) -> Option<Reservation<'_>> {
        let mut s = self.0.lock().unwrap_or_else(|e| e.into_inner());
        if s.error.is_some() {
            return None;
        }
        let fits = bytes
            .and_then(|bytes| Self::used(&s)?.checked_add(s.reserved)?.checked_add(bytes))
            .is_some_and(|n| n <= s.limit);
        if !fits {
            s.error = Some(
                "captured source view allocation exceeds remaining input-family budget".into(),
            );
            return None;
        }
        let amount = bytes.expect("checked above");
        s.reserved += amount;
        Some(Reservation {
            budget: self,
            amount,
        })
    }
    pub(super) fn fail(&self, error: String) {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .error
            .get_or_insert(error);
    }
    fn remember_locked(
        s: &mut State,
        collect: impl FnOnce(&mut dyn FnMut(PolicyStorageKey, usize)),
    ) {
        collect(&mut |key, bytes| {
            s.owners
                .entry(key)
                .and_modify(|old| *old = (*old).max(bytes))
                .or_insert(bytes);
        });
        if Self::used(&s)
            .and_then(|n| n.checked_add(s.reserved))
            .is_none_or(|n| n > s.limit)
        {
            s.error.get_or_insert_with(|| {
                "captured source actual retained capacity exceeds input-family budget".into()
            });
        }
    }
    pub(super) fn remember(&self, collect: impl FnOnce(&mut dyn FnMut(PolicyStorageKey, usize))) {
        let mut s = self.0.lock().unwrap_or_else(|e| e.into_inner());
        Self::remember_locked(&mut s, collect);
    }
}
impl Reservation<'_> {
    pub(super) fn complete(
        mut self,
        collect: impl FnOnce(&mut dyn FnMut(PolicyStorageKey, usize)),
    ) {
        let mut s = self.budget.0.lock().unwrap_or_else(|e| e.into_inner());
        s.reserved -= self.amount;
        self.amount = 0;
        Budget::remember_locked(&mut s, collect);
    }
}
impl Drop for Reservation<'_> {
    fn drop(&mut self) {
        if self.amount != 0 {
            let mut s = self.budget.0.lock().unwrap_or_else(|e| e.into_inner());
            s.reserved = s.reserved.saturating_sub(self.amount);
        }
    }
}

pub(super) fn source_storage(
    source: &dm_preprocess::SourceText,
    visit: &mut dyn FnMut(PolicyStorageKey, usize),
) {
    let mut backing = 0;
    source.visit_storage(|id, header, storage| {
        backing = id;
        visit(
            PolicyStorageKey(K::TextBacking, id),
            header.saturating_add(2 * std::mem::size_of::<usize>()),
        );
        match storage {
            dm_preprocess::SourceTextStorage::Original(value) => visit(
                PolicyStorageKey(K::OriginalPayload, value.as_ptr() as usize),
                value.len().saturating_add(2 * std::mem::size_of::<usize>()),
            ),
            dm_preprocess::SourceTextStorage::Transformed(value) if value.capacity() > 0 => visit(
                PolicyStorageKey(K::TransformedPayload, value.as_ptr() as usize),
                value.capacity(),
            ),
            dm_preprocess::SourceTextStorage::Reserved { text, committed } if committed != 0 => visit(
                PolicyStorageKey(K::TransformedPayload, text.as_ptr() as usize),
                committed,
            ),
            dm_preprocess::SourceTextStorage::Transformed(_)
            | dm_preprocess::SourceTextStorage::Reserved { .. } => (),
        }
    });
    source.visit_fingerprint_storage(|_, _, capacity| {
        visit(PolicyStorageKey(K::FingerprintMemo, backing), capacity)
    });
}
pub(super) fn view_storage(view: &View, visit: &mut dyn FnMut(PolicyStorageKey, usize)) {
    source_storage(&view.text, visit);
    if view.starts.capacity() > 0 {
        visit(
            PolicyStorageKey(K::LineStarts, view.starts.as_ptr() as usize),
            view.starts
                .capacity()
                .saturating_mul(std::mem::size_of::<u32>()),
        );
    }
}
pub(crate) fn visit_source_storage(
    source: &dm_preprocess::SourceText,
    mut visit: impl FnMut(PolicyStorageKey, usize),
) {
    source_storage(source, &mut visit)
}

/// Existing transformations never increase newline count. Their output buffers
/// may grow on malformed quotes, so reserve ample temporary space (including
/// lossy conversion), not an assumed same-length string. Each lazy pays only
/// when it is demanded; completed capacities replace the reservation.
pub(super) fn transform_bound(raw: &str, multiplier: usize) -> Option<usize> {
    let lines = raw.bytes().filter(|b| *b == b'\n').count().checked_add(1)?;
    raw.len()
        .checked_mul(multiplier)?
        .checked_add(lines.checked_mul(4)?)?
        .checked_add(4096)
}
/// Actual strip::code_only allocation proof (the strip algorithm is unchanged):
/// - starts with Vec<u8>::with_capacity(n), never creates a char/string table;
/// - copied code consumes one byte per output byte, erased comments/resources
///   cannot increase output, and a quote replacement emits two ASCII bytes for
///   at least one consumed byte. Escaped newlines each consume two input bytes.
///   Hence the output is at most2n, including unterminated quotes on EVERY line.
/// - at most one geometric growth from n to2n: old+new overlap at most3n.
/// - copied runs and all quote/comment boundaries preserve valid UTF8; into_string
///   takes String::from_utf8's successful ownership path, and SourceText::from(String)
///   moves the same buffer. No lossy second output or Arc<str> copy is constructed.
/// - indexed() reserves exactly the original newline count, which cannot increase.
/// Existing4096 covers the tiny Vec minimum allocation, Arc/header and allocator
/// alignment. This is a tighter reservation of SAME live work, not a raised cap.
pub(super) fn code_transform_bound(raw:&str)->Option<usize>{transform_bound(raw,3)}
/// Marker starts with exact b.to_vec() and only overwrites bytes; conversion takes
/// that buffer, or drops it and returns an empty String. There is no buffer growth.
pub(super) fn marker_transform_bound(raw:&str)->Option<usize>{transform_bound(raw,1)}
pub(super) fn empty_view() -> View {
    View::shared(String::new().into())
}

pub(super) fn indexed(text: dm_preprocess::SourceText) -> Result<View, String> {
    if text.len() > u32::MAX as usize {
        return Err("captured view exceeds native line-index range".into());
    }
    let count = line_count(&text).ok_or("captured view line count overflow")?;
    indexed_with_count(text, count)
}

pub(super) fn line_count(text: &str) -> Option<usize> {
    text.bytes().filter(|b| *b == b'\n').count().checked_add(1)
}

/// Use the exact count already measured on this same immutable text to fund
/// the raw index. This does not accept counts from a caller outside tree.
pub(super) fn indexed_with_count(
    text: dm_preprocess::SourceText,
    count: usize,
) -> Result<View, String> {
    if text.len() > u32::MAX as usize {
        return Err("captured view exceeds native line-index range".into());
    }
    let mut starts = Vec::new();
    starts
        .try_reserve_exact(count)
        .map_err(|_| "captured view line-index allocation refused")?;
    // try_reserve_exact has no amortized growth; still verify actual capacity.
    if starts.capacity() > count {
        return Err("captured view allocator exceeded reserved index capacity".into());
    }
    starts.push(0u32);
    starts.extend(
        text.bytes()
            .enumerate()
            .filter_map(|(i, b)| (b == b'\n').then_some((i + 1) as u32)),
    );
    Ok(View { text, starts })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn denied_reservation_is_sticky_and_does_not_allocate_a_view() {
        let b = Budget::new(OWNER_METADATA + 32, 0).unwrap();
        assert!(b.reserve(Some(33)).is_none());
        assert!(b.error().is_some());
        assert!(b.reserve(Some(0)).is_none());
    }
    #[test]
    fn same_live_text_is_charged_once_and_reservation_releases_on_error() {
        let b = Budget::new(65536, 0).unwrap();
        let text: dm_preprocess::SourceText = "a\nb\n".to_owned().into();
        b.remember(|v| source_storage(&text, v));
        let before = b.charge();
        b.remember(|v| source_storage(&text, v));
        assert_eq!(before, b.charge());
        {
            let _r = b.reserve(Some(4096)).unwrap();
        }
        assert!(b.reserve(Some(65536 - before)).is_some());
    }
}

#[cfg(test)]mod real_transform_bound_tests{
 use super::*;
 #[test]fn same_strip_algorithm_malformed_quotes_unicode_comments_and_interpolation_fit_actual_envelopes(){
  let tokens=["a","é","漢","\"","'","/","*","\\","[","]","\n"];
  for count in 0..=4u32{for mut ordinal in 0..tokens.len().pow(count){let mut text=String::new();for _ in 0..count{let at=ordinal%tokens.len();ordinal/=tokens.len();text.push_str(tokens[at]);}
   let code=crate::strip::code_only(&text);let marker=crate::raw_marker_policy::strip_comments_keep_strings(&text);
   assert!(code.len()<=text.len()*2,"{text:?} -> {code:?}");assert!(code.capacity()<=text.len().saturating_mul(2).max(8),"{text:?}: {}",code.capacity());assert!(!code.contains('�'),"valid original UTF8 may not enter lossy fallback: {text:?}");
   assert!(code.bytes().filter(|b|*b==b'\n').count()<=text.bytes().filter(|b|*b==b'\n').count());assert!(marker.is_empty()||marker.len()==text.len());assert!(marker.capacity()<=text.len());
   assert!(code_transform_bound(&text).unwrap()>=code.capacity());assert!(marker_transform_bound(&text).unwrap()>=marker.capacity());
  }}
  for text in ["\"\n".repeat(8192),"{\"\n\"}".repeat(2048),"\"[a[\"é\"]]\"\n".repeat(2048),"/*漢\n*/code\n".repeat(2048)]{let code=crate::strip::code_only(&text);assert!(code.len()<=text.len()*2);assert!(code.capacity()<=text.len()*2);}
 }
 #[test]fn actual_captured_lazy_view_denial_remains_sticky_and_does_not_credit_a_failed_owner(){
  let text:dm_preprocess::SourceText="\"\n".repeat(4096).into();let mut bytes=0;source_storage(&text,&mut|_,n|bytes+=n);let raw_index=(text.bytes().filter(|b|*b==b'\n').count()+1)*4;
  let limit=bytes+raw_index+OWNER_METADATA+2048;let file=crate::tree::SourceFile::from_shared_budgeted("code/denied.dm",std::path::PathBuf::from("code/denied.dm"),text,limit).unwrap();let _=file.code();assert!(file.require_view_budget().is_err());assert!(file.code().text.is_empty());assert!(file.require_view_budget().is_err());
  let text:dm_preprocess::SourceText="\"\n".repeat(4096).into();let file=crate::tree::SourceFile::from_shared_budgeted("code/recovered.dm",std::path::PathBuf::from("code/recovered.dm"),text,1024*1024).unwrap();assert!(!file.code().text.is_empty());assert!(file.require_view_budget().is_ok());
 }
}

#[cfg(all(test,feature="native-policy"))]mod largest_raw_source_bound_tests{
 use super::*;
 #[test]fn actual_ten_mb_source_views_fit_unchanged_sixty_four_mib_and_typed_denial_recovers(){
  use crate::{captured_generator_budget::Budget as Outer,captured_reactive_reads::Failure};
  let root=std::env::current_dir().unwrap().join("large-original-code-projection");let path=root.join("code/engine/_generated/declare.dm");
  let mut text=String::from("/datum/large/proc/generated()\n");let line="    return list(\"[nested[call(\"é漢\")]]\", null) // original source projection\n";while text.len()<9_609_633{text.push_str(line);}let source:dm_preprocess::SourceText=text.into();
  let tiny=Outer::new(1024).unwrap();let reached=std::cell::Cell::new(false);let denied=crate::captured_raw_file::with_original_policy_file(&root,&path,source.clone(),0,&tiny,&mut|_,_|{reached.set(true);Ok(true)});assert!(matches!(denied,Err(Failure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));assert!(!reached.get());
  let budget=Outer::new(64*1024*1024).unwrap();let fixed=budget.used();let mut seen=0;crate::captured_raw_file::with_original_policy_file(&root,&path,source.clone(),0,&budget,&mut|_,views|{assert!(!views.code()?.text.is_empty());assert_eq!(views.marker()?.len(),source.len());seen+=1;Ok(true)}).unwrap();assert_eq!(seen,1);assert!(budget.used()<fixed+512,"the physical File and all views must release their scope, not retain a result/source cache");
 }
}
