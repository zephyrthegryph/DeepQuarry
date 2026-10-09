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
}
/// Weak storage lifetime observation; it carries no compiler issuance authority.
#[derive(Clone)]
pub struct WeakSourceText {
    backing: Weak<Backing>,
    range: Range<usize>,
}
impl WeakSourceText {
    pub fn upgrade(&self) -> Option<SourceText> {
        Some(SourceText {
            backing: self.backing.upgrade()?,
            range: self.range.clone(),
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
    pub fn downgrade(&self) -> WeakSourceText {
        WeakSourceText {
            backing: Arc::downgrade(&self.backing),
            range: self.range.clone(),
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
            }),
            range: 0..length,
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
            }),
            range: 0..length,
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
