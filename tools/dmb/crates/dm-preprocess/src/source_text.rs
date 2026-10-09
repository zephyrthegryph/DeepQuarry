//! Immutable lexical text views; clones share a file arena instead of line buffers.
use std::{
    fmt,
    ops::{Deref, Range},
    sync::Arc,
};

#[derive(Clone)]
enum Backing {
    Original(Arc<str>),
    Transformed(String),
}
impl Backing {
    fn text(&self) -> &str {
        match self {
            Self::Original(text) => text,
            Self::Transformed(text) => text,
        }
    }
}
#[derive(Clone)]
pub struct SourceText {
    backing: Arc<Backing>,
    range: Range<usize>,
}
/// Borrow actual backing allocations for a deduplicated retained-owner census.
/// Transformed storage exposes its String capacity without copying its payload.
pub enum SourceTextStorage<'a> {
    Original(&'a Arc<str>),
    Transformed(&'a String),
}
impl SourceText {
    pub fn as_str(&self) -> &str {
        &self.backing.text()[self.range.clone()]
    }
    pub fn visit_storage(&self, visitor: impl FnOnce(usize, usize, SourceTextStorage<'_>)) {
        let storage = match self.backing.as_ref() {
            Backing::Original(text) => SourceTextStorage::Original(text),
            Backing::Transformed(text) => SourceTextStorage::Transformed(text),
        };
        visitor(
            Arc::as_ptr(&self.backing) as usize,
            std::mem::size_of::<Backing>(),
            storage,
        );
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
impl From<Arc<str>> for SourceText {
    fn from(text: Arc<str>) -> Self {
        let length = text.len();
        Self {
            backing: Arc::new(Backing::Original(text)),
            range: 0..length,
        }
    }
}
impl From<String> for SourceText {
    fn from(text: String) -> Self {
        let length = text.len();
        Self {
            backing: Arc::new(Backing::Transformed(text)),
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
