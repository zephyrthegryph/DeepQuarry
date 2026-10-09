//! Immutable relative declaration syntax and checked current offset bindings.
//! Exact source-key admission remains the responsibility of the owning store.
use dm_syntax::{Item, ItemKind, Span};
use std::sync::Arc;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindingError {
    InvalidRelativeSpan,
    OffsetOverflow,
    SourceLengthMismatch,
}
#[derive(Debug)]
pub struct RelativeSyntax {
    items: Arc<[Item]>,
    source_len: usize,
    max_end: usize,
    bodies: Vec<RelativeBody>,
}
#[derive(Debug)]
struct RelativeBody {
    path: Arc<[usize]>,
    span: Span,
    settings: Arc<[Span]>,
}
fn capture_bodies(items: &[Item], path: &mut Vec<usize>, output: &mut Vec<RelativeBody>) {
    for (index, item) in items.iter().enumerate() {
        path.push(index);
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            let mut settings = Vec::new();
            crate::settings::setting_spans(&item.children, &mut settings);
            output.push(RelativeBody {
                path: path.clone().into(),
                span: item.span,
                settings: settings.into(),
            });
        } else {
            capture_bodies(&item.children, path, output);
        }
        path.pop();
    }
}
pub(crate) struct CurrentBodyRecipe<'a> {
    relative: &'a RelativeBody,
    offset: usize,
    root_prefix: usize,
}
impl CurrentBodyRecipe<'_> {
    pub(crate) fn span(&self) -> Span {
        Span::new(
            self.relative.span.start + self.offset,
            self.relative.span.end + self.offset,
        )
    }
    pub(crate) fn path(&self) -> Arc<[usize]> {
        let mut path = self.relative.path.to_vec();
        path[0] += self.root_prefix;
        path.into()
    }
    pub(crate) fn settings(&self) -> impl Iterator<Item = Span> + '_ {
        self.relative
            .settings
            .iter()
            .map(|span| Span::new(span.start + self.offset, span.end + self.offset))
    }
}
impl RelativeSyntax {
    /// Mint once from root-relative parser output, validating every byte span.
    pub(crate) fn capture(items: Vec<Item>, source: &str) -> Result<Self, BindingError> {
        let mut max_end = 0;
        let mut pending: Vec<_> = items.iter().collect();
        while let Some(item) = pending.pop() {
            for span in [item.span, item.header_span] {
                if source.get(span.range()).is_none() {
                    return Err(BindingError::InvalidRelativeSpan);
                }
                max_end = max_end.max(span.end);
            }
            pending.extend(&item.children);
        }
        let mut bodies = Vec::new();
        capture_bodies(&items, &mut Vec::new(), &mut bodies);
        Ok(Self {
            items: items.into(),
            source_len: source.len(),
            max_end,
            bodies,
        })
    }
    pub fn relative_items(&self) -> &Arc<[Item]> {
        &self.items
    }
    pub fn visit_body_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(
            self.bodies.as_ptr() as usize,
            self.bodies.len() * std::mem::size_of::<RelativeBody>(),
            self.bodies.capacity() * std::mem::size_of::<RelativeBody>(),
        );
        for body in &self.bodies {
            visit(
                body.path.as_ptr() as usize,
                std::mem::size_of_val(body.path.as_ref()),
                std::mem::size_of_val(body.path.as_ref()),
            );
            visit(
                body.settings.as_ptr() as usize,
                std::mem::size_of_val(body.settings.as_ref()),
                std::mem::size_of_val(body.settings.as_ref()),
            );
        }
    }
    /// The caller has already checked the immutable exact source key. This is
    /// a coordinate certificate, not a replacement for source authentication.
    pub(crate) fn bind(
        self: &Arc<Self>,
        source_len: usize,
        offset: usize,
    ) -> Result<CurrentSyntaxChunk, BindingError> {
        if source_len != self.source_len {
            return Err(BindingError::SourceLengthMismatch);
        }
        let end = offset
            .checked_add(self.max_end)
            .ok_or(BindingError::OffsetOverflow)?;
        // Semantic declaration origins use u32 coordinates; preserve the existing
        // unsupported/overflow path rather than narrowing an unchecked offset.
        if u32::try_from(end).is_err() {
            return Err(BindingError::OffsetOverflow);
        }
        Ok(CurrentSyntaxChunk {
            relative: Arc::clone(self),
            offset,
        })
    }
}
#[derive(Clone, Debug)]
pub struct CurrentSyntaxChunk {
    relative: Arc<RelativeSyntax>,
    offset: usize,
}
impl CurrentSyntaxChunk {
    pub fn shared_relative(&self) -> &Arc<RelativeSyntax> {
        &self.relative
    }
    pub fn offset(&self) -> usize {
        self.offset
    }
    pub fn len(&self) -> usize {
        self.relative.items.len()
    }
    pub fn is_empty(&self) -> bool {
        self.relative.items.is_empty()
    }
    pub fn items(&self) -> impl ExactSizeIterator<Item = ItemView<'_>> + DoubleEndedIterator {
        self.relative.items.iter().map(|item| ItemView {
            item,
            offset: self.offset,
        })
    }
    fn item(&self, index: usize) -> Option<ItemView<'_>> {
        self.relative.items.get(index).map(|item| ItemView {
            item,
            offset: self.offset,
        })
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ItemView<'a> {
    item: &'a Item,
    offset: usize,
}
impl<'a> ItemView<'a> {
    pub fn relative_item(self) -> &'a Item {
        self.item
    }
    pub fn offset(self) -> usize {
        self.offset
    }
    pub fn same_node(self, other: ItemView<'_>) -> bool {
        std::ptr::eq(self.item, other.item) && self.offset == other.offset
    }

    pub fn kind(self) -> ItemKind {
        self.item.kind
    }
    pub fn header(self) -> &'a str {
        &self.item.header
    }
    pub fn span(self) -> Span {
        Span::new(
            self.item.span.start + self.offset,
            self.item.span.end + self.offset,
        )
    }
    pub fn header_span(self) -> Span {
        Span::new(
            self.item.header_span.start + self.offset,
            self.item.header_span.end + self.offset,
        )
    }
    pub fn children(self) -> impl ExactSizeIterator<Item = ItemView<'a>> + DoubleEndedIterator {
        self.item.children.iter().map(move |item| ItemView {
            item,
            offset: self.offset,
        })
    }
    pub fn child(self, index: usize) -> Option<Self> {
        self.item.children.get(index).map(|item| Self {
            item,
            offset: self.offset,
        })
    }
    /// Compatibility for a single requested body/custom policy, never whole-roster
    /// materialization. The same immutable nodes serve borrowed analysis.
    pub fn materialize(self) -> Item {
        let mut item = self.item.clone();
        fn shift(item: &mut Item, offset: usize) {
            item.span = Span::new(item.span.start + offset, item.span.end + offset);
            item.header_span = Span::new(
                item.header_span.start + offset,
                item.header_span.end + offset,
            );
            for child in &mut item.children {
                shift(child, offset);
            }
        }
        shift(&mut item, self.offset);
        item
    }
}
#[derive(Clone, Debug)]
pub struct DeclarationSyntax {
    chunks: Arc<[CurrentSyntaxChunk]>,
    prefix: Arc<[usize]>,
    len: usize,
}
impl DeclarationSyntax {
    pub(crate) fn body_recipes(&self) -> impl Iterator<Item = CurrentBodyRecipe<'_>> {
        self.chunks
            .iter()
            .zip(self.prefix.iter())
            .flat_map(|(chunk, &root_prefix)| {
                chunk
                    .relative
                    .bodies
                    .iter()
                    .map(move |relative| CurrentBodyRecipe {
                        relative,
                        offset: chunk.offset,
                        root_prefix,
                    })
            })
    }
    pub(crate) fn new(chunks: Vec<CurrentSyntaxChunk>) -> Result<Self, BindingError> {
        let mut prefix = Vec::with_capacity(chunks.len());
        let mut len = 0usize;
        for chunk in &chunks {
            prefix.push(len);
            len = len
                .checked_add(chunk.len())
                .ok_or(BindingError::OffsetOverflow)?;
        }
        Ok(Self {
            chunks: chunks.into(),
            prefix: prefix.into(),
            len,
        })
    }
    pub fn chunks(&self) -> &Arc<[CurrentSyntaxChunk]> {
        &self.chunks
    }
    pub fn root_prefix(&self) -> &Arc<[usize]> {
        &self.prefix
    }
    pub fn len(&self) -> usize {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    pub fn item(&self, index: usize) -> Option<ItemView<'_>> {
        if index >= self.len {
            return None;
        }
        let chunk = self
            .prefix
            .partition_point(|&begin| begin <= index)
            .checked_sub(1)?;
        self.chunks[chunk].item(index - self.prefix[chunk])
    }
    pub fn item_path(&self, path: &[usize]) -> Option<ItemView<'_>> {
        let (&root, children) = path.split_first()?;
        let mut item = self.item(root)?;
        for &child in children {
            item = item.child(child)?;
        }
        Some(item)
    }
    pub fn items(&self) -> DeclarationItems<'_> {
        DeclarationItems {
            syntax: self,
            front: 0,
            back: self.len,
            front_chunk: 0,
            back_chunk: self.chunks.len().saturating_sub(1),
        }
    }
}
pub struct DeclarationItems<'a> {
    syntax: &'a DeclarationSyntax,
    front: usize,
    back: usize,
    front_chunk: usize,
    back_chunk: usize,
}
impl<'a> Iterator for DeclarationItems<'a> {
    type Item = ItemView<'a>;
    fn next(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        let index = self.front;
        self.front += 1;
        while self.syntax.prefix[self.front_chunk] + self.syntax.chunks[self.front_chunk].len()
            <= index
        {
            self.front_chunk += 1;
        }
        self.syntax.chunks[self.front_chunk].item(index - self.syntax.prefix[self.front_chunk])
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let remaining = self.back - self.front;
        (remaining, Some(remaining))
    }
}
impl DoubleEndedIterator for DeclarationItems<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        self.back -= 1;
        while self.syntax.prefix[self.back_chunk] > self.back {
            self.back_chunk -= 1;
        }
        self.syntax.chunks[self.back_chunk].item(self.back - self.syntax.prefix[self.back_chunk])
    }
}
impl ExactSizeIterator for DeclarationItems<'_> {}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn borrowed_chunks_translate_nested_spans_and_keep_relative_nodes_shared() {
        let source = "/datum/example\n    var/value = 1\n    proc/read()\n        return value\n";
        let parsed = dm_syntax::parse(source);
        let original = parsed.items.clone();
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let first = relative.bind(source.len(), 0).unwrap();
        let shifted = relative.bind(source.len(), 107).unwrap();
        assert!(Arc::ptr_eq(
            first.shared_relative(),
            shifted.shared_relative()
        ));
        let syntax = DeclarationSyntax::new(vec![first, shifted]).unwrap();
        assert_eq!(syntax.len(), 2);
        assert_eq!(
            syntax.item_path(&[1, 1]).unwrap().header(),
            original[0].children[1].header
        );
        let child = syntax.item_path(&[1, 1]).unwrap();
        assert_eq!(child.span().start, original[0].children[1].span.start + 107);
        assert_eq!(
            child.materialize().children[0].span.start,
            original[0].children[1].children[0].span.start + 107
        );
        assert_eq!(relative.relative_items().as_ref(), original.as_slice());
        assert!(syntax.item(2).is_none());
        assert!(syntax.item_path(&[1, 100]).is_none());
        let mut items = syntax.items();
        assert_eq!(items.next().unwrap().span().start, 0);
        assert_eq!(items.next_back().unwrap().span().start, 107);
        assert_eq!(items.len(), 0);
    }
    #[test]
    fn body_recipes_share_syntax_and_rebind_paths_settings_and_coordinates() {
        let source = "/datum/example\n    proc/read()\n        set waitfor = 0\n        return 1\n/proc/other()\n    return 2\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let syntax = DeclarationSyntax::new(vec![
            relative.bind(source.len(), 0).unwrap(),
            relative.bind(source.len(), 200).unwrap(),
        ])
        .unwrap();
        let recipes = syntax.body_recipes().collect::<Vec<_>>();
        assert_eq!(recipes.len(), 4);
        for recipe in &recipes {
            let path = recipe.path();
            let item = syntax.item_path(&path).unwrap();
            assert!(matches!(item.kind(), ItemKind::Proc | ItemKind::Verb));
            assert_eq!(recipe.span(), item.span());
        }
        assert_eq!(recipes[0].path().as_ref(), &[0, 0]);
        assert_eq!(recipes[2].path().as_ref(), &[2, 0]);
        let first = recipes[0].settings().collect::<Vec<_>>();
        let shifted = recipes[2].settings().collect::<Vec<_>>();
        assert_eq!(first.len(), 1);
        assert_eq!(shifted[0].start, first[0].start + 200);
        assert_eq!(shifted[0].end, first[0].end + 200);
        assert!(source[first[0].range()].contains("waitfor"));
        assert!(Arc::ptr_eq(
            syntax.chunks()[0].shared_relative(),
            syntax.chunks()[1].shared_relative()
        ));
    }
    #[test]
    fn bindings_reject_overflow_foreign_lengths_and_non_utf8_span_boundaries() {
        let source = "/datum/é\n";
        let mut items = dm_syntax::parse_declaration_skeleton(source).items;
        let relative = Arc::new(RelativeSyntax::capture(items.clone(), source).unwrap());
        assert!(matches!(
            relative.bind(source.len(), usize::MAX),
            Err(BindingError::OffsetOverflow)
        ));
        assert!(matches!(
            relative.bind(source.len() + 1, 0),
            Err(BindingError::SourceLengthMismatch)
        ));
        items[0].header_span.end -= 1;
        assert!(matches!(
            RelativeSyntax::capture(items, source),
            Err(BindingError::InvalidRelativeSpan)
        ));
    }
    #[test]
    fn empty_chunks_do_not_change_global_root_ordinals() {
        let empty = Arc::new(RelativeSyntax::capture(vec![], "").unwrap());
        let source = "/datum/a\n";
        let nonempty = Arc::new(
            RelativeSyntax::capture(dm_syntax::parse_declaration_skeleton(source).items, source)
                .unwrap(),
        );
        let syntax = DeclarationSyntax::new(vec![
            empty.bind(0, 0).unwrap(),
            nonempty.bind(source.len(), 13).unwrap(),
            empty.bind(0, 20).unwrap(),
        ])
        .unwrap();
        assert_eq!(syntax.item(0).unwrap().span().start, 13);
        assert_eq!(syntax.items().count(), 1);
        let mut reversed = syntax.items();
        assert_eq!(reversed.next_back().unwrap().span().start, 13);
        assert!(reversed.next().is_none());
        let syntax = DeclarationSyntax::new(vec![
            empty.bind(0, 0).unwrap(),
            nonempty.bind(source.len(), 13).unwrap(),
            empty.bind(0, 20).unwrap(),
            nonempty.bind(source.len(), 27).unwrap(),
            empty.bind(0, 40).unwrap(),
            nonempty.bind(source.len(), 51).unwrap(),
            empty.bind(0, 80).unwrap(),
        ])
        .unwrap();
        let mut mixed = syntax.items();
        assert_eq!(mixed.next_back().unwrap().span().start, 51);
        assert_eq!(mixed.next().unwrap().span().start, 13);
        assert_eq!(mixed.next_back().unwrap().span().start, 27);
        assert!(mixed.next().is_none());
        assert!(mixed.next_back().is_none());
    }
}
