//! Immutable lexical text views; clones share a file arena instead of line buffers.
use std::{
    fmt,
    ops::{Deref, Range},
    sync::{Arc, Mutex, OnceLock, Weak},
};

#[derive(Clone)]
enum TextBacking {
    Original(Arc<str>),
    Transformed(String),
}
impl TextBacking {
    fn text(&self) -> &str {
        match self {
            Self::Original(text) => text,
            Self::Transformed(text) => text,
        }
    }
}
struct Backing {
    text: TextBacking,
    fingerprints: OnceLock<Mutex<Vec<SpanFingerprint>>>,
    // Last: actual text/fingerprint allocations drop before their resource root.
    _source_arena_payload: Option<crate::source_arena_credit::SourceArenaCredit>,
}
#[derive(Clone, Copy)]
struct SpanFingerprint {
    range: (usize, usize),
    digest: u128,
}
impl Backing {
    fn text(&self) -> &str {
        self.text.text()
    }
}
#[derive(Clone)]
pub struct SourceText {
    backing: Arc<Backing>,
    range: Range<usize>,
    _source_arena_control:Option<crate::source_arena_credit::SourceArenaControlCredit>,
}
/// Weak storage lifetime observation; it carries no compiler issuance authority.
#[derive(Clone)]
pub struct WeakSourceText {
    backing: Weak<Backing>,
    range: Range<usize>,
    // Only resource credit, never source payload/identity/model authority.
    _source_arena_control:Option<crate::source_arena_credit::SourceArenaControlCredit>,
}
impl WeakSourceText {
    /// Inventory the actual fixed backing allocation retained by this Weak,
    /// including after payload destruction. Never dereferences a dead owner;
    /// addresses here are census metadata, not a source-identity proof.
    pub fn visit_backing_storage(&self,visit:impl FnOnce(usize,usize,usize)){
        let bytes=std::mem::size_of::<Backing>();
        visit(self.backing.as_ptr() as usize,if self.backing.strong_count()>0{bytes}else{0},bytes);
    }
    /// Resource-control metadata only; observes no source payload and never
    /// upgrades a dead backing or issues a source/currentness grant.
    pub fn visit_derived_resource_storage(&self,mut visit:impl FnMut(usize,usize)){if let Some(credit)=&self._source_arena_control{credit.visit_storage(&mut visit)}}
    pub fn upgrade(&self) -> Option<SourceText> {
        Some(SourceText {
            backing: self.backing.upgrade()?,
            range: self.range.clone(),
            _source_arena_control:self._source_arena_control.clone(),
        })
    }
}
/// Borrow actual backing allocations for a deduplicated retained-owner census.
/// Transformed storage exposes its String capacity without copying its payload.
pub enum SourceTextStorage<'a> {
    Original(&'a Arc<str>),
    Transformed(&'a String),
}
impl SourceText {
    pub fn source_arena_control_bytes()->std::io::Result<usize>{std::mem::size_of::<Backing>().checked_add(2*std::mem::size_of::<usize>()).ok_or_else(||std::io::ErrorKind::OutOfMemory.into())}
    /// Adopt the SAME transformed source allocation under the existing shared
    /// input/source family. Neither credit carries acquisition/model authority.
    /// String payload and last-weak control metadata have distinct lifetimes.
    pub fn from_source_arena(text:String,payload:crate::source_arena_credit::SourceArenaCredit,control:crate::source_arena_credit::SourceArenaControlCredit)->std::io::Result<Self>{
      // This guard fixes failure drop order too: physical String before either
      // credit even when capacity/metadata validation returns immediately.
      struct Pending{ text:Option<String>,payload:Option<crate::source_arena_credit::SourceArenaCredit>,control:Option<crate::source_arena_credit::SourceArenaControlCredit> }
      let mut pending=Pending{text:Some(text),payload:Some(payload),control:Some(control)};
      let metadata=Self::source_arena_control_bytes()?;
      if pending.payload.as_ref().unwrap().reserved_bytes()<pending.text.as_ref().unwrap().capacity()||pending.control.as_ref().unwrap().reserved_bytes()<metadata{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"transformed source adoption exceeds its actual input-family allocation credit"))}
      let length=pending.text.as_ref().unwrap().len();let backing=Backing{text:TextBacking::Transformed(pending.text.take().unwrap()),fingerprints:OnceLock::new(),_source_arena_payload:pending.payload.take()};
      Ok(Self{backing:Arc::new(backing),range:0..length,_source_arena_control:pending.control.take()})
    }
    pub fn source_arena_payload_credit(&self)->Option<&crate::source_arena_credit::SourceArenaCredit>{self.backing._source_arena_payload.as_ref()}
    pub fn source_arena_control_credit(&self)->Option<&crate::source_arena_credit::SourceArenaControlCredit>{self._source_arena_control.as_ref()}
    /// Real resource owner/control allocations only, never duplicate reserved
    /// bytes as a second copy of the source payload.
    pub fn visit_derived_resource_storage(&self,mut visit:impl FnMut(usize,usize)){
      if let Some(credit)=self.source_arena_payload_credit(){credit.visit_storage(&mut visit)}if let Some(credit)=self.source_arena_control_credit(){credit.visit_storage(&mut visit)}
    }
    /// SAME historical Analyze display-line projection of compiler-decoded
    /// original text. Bare CR adds display rows; CRLF adds only its LF row.
    pub fn analyze_display_line(&self,native_line:usize)->Option<usize>{
        let text=self.as_str().as_bytes();let mut line=1usize;let mut extra=0usize;for(offset,byte)in text.iter().enumerate(){if *byte==b'\n'{line+=1;}else if *byte==b'\r'&&text.get(offset+1)!=Some(&b'\n')&&line<native_line{extra+=1;}}
        if native_line==0||native_line>line{None}else{Some(native_line+extra)}
    }
    pub fn downgrade(&self) -> WeakSourceText {
        WeakSourceText {
            backing: Arc::downgrade(&self.backing),
            range: self.range.clone(),
            _source_arena_control:self._source_arena_control.clone(),
        }
    }
    pub fn as_str(&self) -> &str {
        &self.backing.text()[self.range.clone()]
    }
    pub fn visit_storage(&self, visitor: impl FnOnce(usize, usize, SourceTextStorage<'_>)) {
        let storage = match self.backing.as_ref() {
            Backing {
                text: TextBacking::Original(text),
                ..
            } => SourceTextStorage::Original(text),
            Backing {
                text: TextBacking::Transformed(text),
                ..
            } => SourceTextStorage::Transformed(text),
        };
        visitor(
            Arc::as_ptr(&self.backing) as usize,
            std::mem::size_of::<Backing>(),
            storage,
        );
    }
    /// Content fingerprint only: this issues no source/provenance authority.
    /// Ranges are relative to this view and must delimit valid UTF-8 text.
    pub fn span_fingerprint(&self, range: Range<usize>) -> Option<u128> {
        let text = self.as_str().get(range.clone())?;
        let absolute = (
            self.range.start.checked_add(range.start)?,
            self.range.start.checked_add(range.end)?,
        );
        let cache = self
            .backing
            .fingerprints
            .get_or_init(|| Mutex::new(Vec::new()));
        let mut entries = cache.lock().unwrap_or_else(|poison| poison.into_inner());
        match entries.binary_search_by_key(&absolute, |entry| entry.range) {
            Ok(index) => Some(entries[index].digest),
            Err(index) => {
                let digest = xxhash_rust::xxh3::xxh3_128(text.as_bytes());
                // Bound arbitrary span-history retention independently of input size.
                if entries.len() < 4096 {
                    entries.insert(
                        index,
                        SpanFingerprint {
                            range: absolute,
                            digest,
                        },
                    );
                }
                Some(digest)
            }
        }
    }
    /// Borrow memo storage for pointer-deduplicated retained-owner accounting.
    pub fn visit_fingerprint_storage(&self, visitor: impl FnOnce(usize, usize, usize)) {
        if let Some(cache) = self.backing.fingerprints.get() {
            let entries = cache.lock().unwrap_or_else(|poison| poison.into_inner());
            visitor(
                entries.as_ptr() as usize,
                entries.len() * std::mem::size_of::<SpanFingerprint>(),
                entries.capacity() * std::mem::size_of::<SpanFingerprint>(),
            );
        }
    }
    /// Exact immutable storage identity, including the selected byte range.
    /// This does not certify a compiler revision, source parse or occurrence.
    pub fn same_view(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.backing, &other.backing) && self.range == other.range
    }
    /// Resource-only equality for replacing a retained view with a smaller
    /// reference to its already authenticated owner. This grants no source role.
    #[cfg(test)]
    pub(crate) fn same_retained_view(&self, other: &Self) -> bool {
        self.same_view(other) && self.same_retained_control(other)
    }
    fn same_retained_control(&self, other: &Self) -> bool {
        match (&self._source_arena_control, &other._source_arena_control) {
            (None, None) => true,
            (Some(left), Some(right)) => std::ptr::addr_eq(left.owner(), right.owner()),
            _ => false,
        }
    }
    /// Compare the exact retained view a checked relative range would issue,
    /// without cloning its backing or control. This grants no source role.
    pub(crate) fn matches_retained_subview(&self, range: Range<usize>, other: &Self) -> bool {
        Arc::ptr_eq(&self.backing, &other.backing)
            && self.checked_absolute_range(range).is_some_and(|range| range == other.range)
            && self.same_retained_control(other)
    }

    fn checked_absolute_range(&self, range: Range<usize>) -> Option<Range<usize>> {
        self.as_str().get(range.clone())?;
        Some(self.range.start.checked_add(range.start)?..self.range.start.checked_add(range.end)?)
    }

    /// Share an exact byte view only when both endpoints are valid UTF-8 bounds.
    /// Content storage alone grants no parser, revision or occurrence authority.
    pub fn checked_view(&self, range: Range<usize>) -> Option<Self> {
        let range = self.checked_absolute_range(range)?;
        Some(Self {
            backing: Arc::clone(&self.backing),
            range,
            _source_arena_control:self._source_arena_control.clone(),
        })
    }
    /// Borrow an existing full string owner for compatibility consumers. A
    /// subrange or transformed buffer must retain its view or explicitly copy.
    pub fn full_original_owner(&self) -> Option<&Arc<str>> {
        match &self.backing.text {
            TextBacking::Original(text) if self.range == (0..text.len()) => Some(text),
            _ => None,
        }
    }
    #[cfg(test)]
    pub(crate) fn shares_backing(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.backing, &other.backing)
    }
    pub(crate) fn view(&self, range: Range<usize>) -> Self {
        // Views are issued only at validated UTF-8 boundaries by the planner.
        let _ = &self.as_str()[range.clone()];
        Self {
            backing: Arc::clone(&self.backing),
            range: (self.range.start + range.start)..(self.range.start + range.end),
            _source_arena_control:self._source_arena_control.clone(),
        }
    }
}
impl Default for SourceText {
    fn default() -> Self {
        String::new().into()
    }
}
impl From<Arc<str>> for SourceText {
    fn from(text: Arc<str>) -> Self {
        let length = text.len();
        Self {
            backing: Arc::new(Backing {
                text: TextBacking::Original(text),
                fingerprints: OnceLock::new(),
                _source_arena_payload: None,
            }),
            range: 0..length,
            _source_arena_control:None,
        }
    }
}
impl From<String> for SourceText {
    fn from(text: String) -> Self {
        let length = text.len();
        Self {
            backing: Arc::new(Backing {
                text: TextBacking::Transformed(text),
                fingerprints: OnceLock::new(),
                _source_arena_payload: None,
            }),
            range: 0..length,
            _source_arena_control:None,
        }
    }
}
impl From<&str> for SourceText {
    fn from(text: &str) -> Self {
        Arc::<str>::from(text).into()
    }
}
impl Deref for SourceText {
    type Target = str;
    fn deref(&self) -> &str {
        self.as_str()
    }
}
impl AsRef<str> for SourceText {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}
impl fmt::Debug for SourceText {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.as_str().fmt(formatter)
    }
}
impl PartialEq for SourceText {
    fn eq(&self, other: &Self) -> bool {
        self.as_str() == other.as_str()
    }
}
impl Eq for SourceText {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checked_source_views_share_bounds_and_full_owner_without_copying() {
        let bytes: Arc<str> = Arc::from("prefix\ncafé\nend\n");
        let source = SourceText::from(Arc::clone(&bytes));
        assert!(Arc::ptr_eq(source.full_original_owner().unwrap(), &bytes));
        let selected = source.checked_view(7..13).unwrap();
        assert_eq!(selected.as_ref(), "café\n");
        assert_eq!(selected.as_str().as_ptr(), source[7..].as_ptr());
        assert!(selected.same_view(&source.checked_view(7..13).unwrap()));
        assert!(selected.full_original_owner().is_none());
        assert!(source.checked_view(7..11).is_none(), "inside é");
        assert!(source.checked_view(13..7).is_none());
        assert!(source.checked_view(0..usize::MAX).is_none());
        assert!(SourceText::from(String::from("owned"))
            .full_original_owner()
            .is_none());
        let weak = Arc::downgrade(&bytes);
        drop(bytes);
        drop(source);
        assert!(weak.upgrade().is_some(), "view retains its immutable owner");
        drop(selected);
        assert!(weak.upgrade().is_none());
    }

    #[test]
    fn retained_subview_comparison_matches_checked_view_for_utf8_and_nested_ranges() {
        let source = SourceText::from(String::from("xééyz"));
        let nested = source.checked_view(1..6).unwrap();
        let first = source.checked_view(1..3).unwrap();
        let second = source.checked_view(3..5).unwrap();
        let empty = source.checked_view(3..3).unwrap();
        let foreign = SourceText::from("é");
        let backing_refs = Arc::strong_count(&source.backing);
        for start in 0..=source.len() + 1 {
            for end in (0..=source.len() + 1).chain(std::iter::once(usize::MAX)) {
                for candidate in [&first, &second, &empty, &nested, &foreign] {
                    let expected = nested.checked_view(start..end)
                        .is_some_and(|view| view.same_retained_view(candidate));
                    assert_eq!(nested.matches_retained_subview(start..end, candidate), expected);
                }
            }
        }
        assert!(nested.matches_retained_subview(0..2, &first));
        assert!(!nested.matches_retained_subview(0..2, &second));
        assert!(!nested.matches_retained_subview(0..2, &foreign));
        assert!(nested.matches_retained_subview(2..2, &empty));
        assert_eq!(Arc::strong_count(&source.backing), backing_refs);
    }

    #[test]
    fn exact_view_identity_and_weak_lifetime_preserve_backing_and_range() {
        let source = SourceText::from(String::from("café\nsecond\n"));
        let clone = source.clone();
        assert!(source.same_view(&clone));
        assert!(!source.same_view(&SourceText::from(source.as_str())));
        let first = source.view(0..6);
        let second = source.view(6..source.len());
        assert!(!first.same_view(&second));
        assert!(first.same_view(&source.view(0..6)));
        let weak = first.downgrade();
        assert!(weak.upgrade().unwrap().same_view(&first));
        drop(first);
        drop(second);
        drop(source);
        assert!(weak.upgrade().is_some());
        drop(clone);
        assert!(weak.upgrade().is_none());
    }

    #[test]
    fn span_fingerprints_share_absolute_ranges_and_reject_invalid_utf8_ranges() {
        let source = SourceText::from(String::from("one\ncafé\n"));
        let view = source.view(4..source.len());
        let expected = xxhash_rust::xxh3::xxh3_128("café\n".as_bytes());
        assert_eq!(source.span_fingerprint(4..source.len()), Some(expected));
        assert_eq!(view.span_fingerprint(0..view.len()), Some(expected));
        assert_eq!(view.span_fingerprint(0..4), None); // middle of é
        assert_eq!(view.span_fingerprint(6..7), None);
        assert_eq!(view.span_fingerprint(4..2), None);
        let mut first = None;
        source.visit_fingerprint_storage(|pointer, length, capacity| {
            assert_eq!(length, std::mem::size_of::<SpanFingerprint>());
            assert!(capacity >= length);
            first = Some(pointer);
        });
        view.visit_fingerprint_storage(|pointer, _, _| assert_eq!(Some(pointer), first));
        assert_eq!(source.as_str(), "one\ncafé\n");
    }

    #[test]
    fn arbitrary_span_history_is_bounded_and_poison_does_not_change_fingerprints() {
        let source = SourceText::from("x".repeat(4100));
        for end in 0..4100 {
            assert_eq!(
                source.span_fingerprint(0..end),
                Some(xxhash_rust::xxh3::xxh3_128(&source.as_bytes()[..end]))
            );
        }
        source.visit_fingerprint_storage(|_, length, _| {
            assert_eq!(length, 4096 * std::mem::size_of::<SpanFingerprint>());
        });
        let cache = source.backing.fingerprints.get().unwrap();
        let _ = std::panic::catch_unwind(|| {
            let _guard = cache.lock().unwrap();
            panic!("test poisoned optional memo");
        });
        assert_eq!(
            source.span_fingerprint(0..4100),
            Some(xxhash_rust::xxh3::xxh3_128(source.as_bytes()))
        );
    }

    #[test]
    fn string_backing_moves_allocation_and_views_preserve_utf8() {
        let mut text = String::with_capacity(128);
        text.push_str("one\ncafé\n");
        let pointer = text.as_ptr();
        let capacity = text.capacity();
        let source = SourceText::from(text);
        let first = source.view(0..4);
        let second = source.view(4..source.len());
        assert!(first.shares_backing(&second));
        assert_eq!(second.as_str(), "café\n");
        second.visit_storage(|_, _, storage| match storage {
            SourceTextStorage::Transformed(text) => {
                assert_eq!(text.as_ptr(), pointer);
                assert_eq!(text.capacity(), capacity);
            }
            SourceTextStorage::Original(_) => {
                panic!("owned string was copied into a different backing")
            }
        });
    }

    #[test]
    fn prepared_lines_share_original_and_continuation_arenas() {
        let original: Arc<str> =
            Arc::from("var/a = 1\nvar/b = 2\n#define X 1 \\\n + 2\n#define Y 3 \\\n + 4\n");
        let prepared = crate::regions::prepared_source::PreparedSource::new(Arc::clone(&original));
        let lines = prepared.lines();
        assert_eq!(lines.len(), 4);
        assert!(lines
            .get(0)
            .unwrap()
            .text
            .shares_backing(lines.get(1).unwrap().text));
        assert!(lines
            .get(2)
            .unwrap()
            .text
            .shares_backing(lines.get(3).unwrap().text));
        assert!(!lines
            .get(0)
            .unwrap()
            .text
            .shares_backing(lines.get(2).unwrap().text));
        lines
            .get(0)
            .unwrap()
            .text
            .visit_storage(|_, _, storage| match storage {
                SourceTextStorage::Original(text) => assert!(Arc::ptr_eq(text, &original)),
                SourceTextStorage::Transformed(_) => panic!("ordinary source line was copied"),
            });
        assert_eq!(lines.get(2).unwrap().text.as_str(), "#define X 1  + 2\n");
        assert_eq!(lines.get(3).unwrap().text.as_str(), "#define Y 3  + 4\n");
        assert_eq!(lines.get(2).unwrap().source_lines, 2);
        assert_eq!(lines.get(3).unwrap().source_line, 5);
    }

    #[test]
    fn comment_masking_preserves_source_spans_in_one_shared_arena() {
        let original: Arc<str> = Arc::from("var/a = 1 // café\nvar/b = 2 /* hidden */\n");
        let prepared = crate::regions::prepared_source::PreparedSource::new(Arc::clone(&original));
        let lines = prepared.lines();
        assert!(lines
            .get(0)
            .unwrap()
            .text
            .shares_backing(lines.get(1).unwrap().text));
        assert_eq!(lines.get(0).unwrap().text.as_str(), "var/a = 1         \n");
        assert_eq!(
            lines.get(1).unwrap().text.as_str(),
            "var/b = 2             \n"
        );
        assert_eq!(lines.get(0).unwrap().source_span.start, 0);
        assert_eq!(lines.get(1).unwrap().source_span.end, original.len());
        lines.get(0).unwrap().text.visit_storage(|_, _, storage| {
            assert!(matches!(storage, SourceTextStorage::Transformed(_)));
        });
    }
}

#[cfg(test)]mod actual_source_arena_credit_tests{
 use super::*;use crate::source_arena_credit::{SourceArenaCredit,SourceArenaCreditOwner};use std::sync::atomic::{AtomicUsize,Ordering};
 struct Credit{bytes:usize,used:Arc<AtomicUsize>}
 impl Drop for Credit{fn drop(&mut self){self.used.fetch_sub(self.bytes,Ordering::AcqRel);}}
 impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn std::any::Any{self}fn reserved_bytes(&self)->usize{self.bytes}fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize)){visit(self as*const Self as usize,std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>());}}
 fn credit(bytes:usize,used:&Arc<AtomicUsize>)->SourceArenaCredit{used.fetch_add(bytes,Ordering::AcqRel);SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes,used:Arc::clone(used)}))}
 #[test]fn actual_source_arena_moves_string_and_payload_refunds_at_last_strong_while_control_waits_for_last_weak(){
  let used=Arc::new(AtomicUsize::new(0));let text=String::from("α native source arena\n");let pointer=text.as_ptr();let capacity=text.capacity();let metadata=std::mem::size_of::<Backing>()+2*std::mem::size_of::<usize>();let source=SourceText::from_source_arena(text,credit(capacity,&used),credit(metadata,&used).into_control()).unwrap();assert_eq!(source.as_str().as_ptr(),pointer);let view=source.checked_view(3..source.len()).unwrap();let weak=source.downgrade();let last_weak=weak.clone();drop(source);assert_eq!(used.load(Ordering::Acquire),capacity+metadata);assert!(weak.upgrade().is_some());drop(view);assert!(weak.upgrade().is_none());assert_eq!(used.load(Ordering::Acquire),metadata,"String payload is actually gone; weak aliases retain only control credit");let mut observed=Vec::new();weak.visit_derived_resource_storage(|address,bytes|observed.push((address,bytes)));assert!(!observed.is_empty());assert!(observed.iter().all(|(_,bytes)|*bytes>0));assert!(weak.upgrade().is_none(),"resource census did not revive a dead source");drop(weak);assert_eq!(used.load(Ordering::Acquire),metadata);drop(last_weak);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]
 fn retained_subview_comparison_requires_same_source_arena_control() {
  let used=Arc::new(AtomicUsize::new(0));
  let text=String::from("α native");
  let capacity=text.capacity();
  let metadata=SourceText::source_arena_control_bytes().unwrap();
  let source=SourceText::from_source_arena(text,credit(capacity,&used),
      credit(metadata,&used).into_control()).unwrap();
  let exact=source.checked_view(0..2).unwrap();
  let mut foreign=exact.clone();
  foreign._source_arena_control=Some(credit(metadata,&used).into_control());
  let mut missing=exact.clone();
  missing._source_arena_control=None;
  assert!(source.matches_retained_subview(0..2,&exact));
  for candidate in [&foreign,&missing] {
   assert!(exact.same_view(candidate));
   assert!(!source.matches_retained_subview(0..2,candidate));
   assert!(!exact.same_retained_view(candidate));
  }
  drop((source,exact,foreign,missing));
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_source_arena_rejects_unfunded_payload_or_control_before_backing_adoption_and_keeps_ordinary_sources_unmarked(){
  let used=Arc::new(AtomicUsize::new(0));let text=String::from("actual allocation");let capacity=text.capacity();let metadata=std::mem::size_of::<Backing>()+2*std::mem::size_of::<usize>();assert_eq!(SourceText::from_source_arena(text,credit(capacity-1,&used),credit(metadata,&used).into_control()).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);let text=String::from("actual allocation");assert_eq!(SourceText::from_source_arena(text,credit(capacity,&used),credit(metadata-1,&used).into_control()).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);let ordinary:SourceText="same ordinary Native source".into();assert!(ordinary.source_arena_payload_credit().is_none());assert!(ordinary.source_arena_control_credit().is_none());
 }
}
