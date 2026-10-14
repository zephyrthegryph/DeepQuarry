//! Immutable relative declaration syntax and checked current offset bindings.
//! Exact source-key admission remains the responsibility of the owning store.
use dm_syntax::{Item, ItemKind, Span};
use std::sync::Arc;
#[path = "frontend_relative_arena.rs"]
mod arena;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindingError {
    InvalidRelativeSpan,
    OffsetOverflow,
    SourceLengthMismatch,
}
#[derive(Debug)]
pub struct RelativeSyntax {
    items: arena::Arena,
    source_len: usize,
    max_end: usize,
    bodies: Vec<RelativeBody>,
}
/// Exact source-capture capability. Only this parser-owned producer can mint it.
#[derive(Debug)]
pub struct BodyCodeIdentity {
    _private: u8,
}
#[derive(Debug)]
struct RelativeBody {
    code: Arc<BodyCodeIdentity>,
    path: Arc<[usize]>,
    span: Span,
    settings: Arc<[Span]>,
    stored_candidates: bool,
    settings_owner: Option<Arc<dm_ir::ProcedureMetadata>>,
}
fn capture_bodies(
    items: &[Item],
    source: &str,
    path: &mut Vec<usize>,
    output: &mut Vec<RelativeBody>,
    owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
) {
    for (index, item) in items.iter().enumerate() {
        path.push(index);
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            let mut settings = Vec::new();
            crate::settings::setting_spans(&item.children, &mut settings);
            output.push(RelativeBody {
                code: Arc::new(BodyCodeIdentity { _private: 0 }),
                path: path.clone().into(),
                span: item.span,
                settings: settings.into(),
                settings_owner: owners.get(&item.span.start).and_then(|owner| {
                    let mut symbols = dm_ir::SymbolTable::default();
                    crate::settings::extract_settings(&item.children, &mut symbols)
                        .ok()
                        .filter(|nodes| nodes.as_ref() == owner.settings.as_ref())
                        .map(|_| Arc::clone(owner))
                }),
                stored_candidates: crate::procedure_statics::may_contain_stored_declarations(
                    &source[item.span.range()],
                ),
            });
        } else {
            capture_bodies(&item.children, source, path, output, owners);
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
    pub(crate) fn code_identity(&self) -> Arc<BodyCodeIdentity> {
        Arc::clone(&self.relative.code)
    }
    pub(crate) fn settings_owner(&self) -> Option<Arc<dm_ir::ProcedureMetadata>> {
        self.relative.settings_owner.clone()
    }
    pub(crate) fn stored_candidates(&self) -> bool {
        self.relative.stored_candidates
    }
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
    #[cfg(test)]
    pub(crate) fn capture(items: Vec<Item>, source: &str) -> Result<Self, BindingError> {
        Self::capture_shared(items, Arc::from(source))
    }
    #[cfg(test)]
    pub(crate) fn capture_shared(items: Vec<Item>, source: Arc<str>) -> Result<Self, BindingError> {
        Self::capture_with_settings(items, source.into(), &Default::default())
    }
    pub(crate) fn capture_with_settings(
        items: Vec<Item>,
        source: dm_preprocess::SourceText,
        owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
    ) -> Result<Self, BindingError> {
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
        capture_bodies(&items, &source, &mut Vec::new(), &mut bodies, owners);
        let source_len = source.len();
        Ok(Self {
            items: arena::Arena::capture(items, source),
            source_len,
            max_end,
            bodies,
        })
    }
    /// Compatibility materialization for a demanded standalone consumer.
    pub fn materialize_relative_items(&self) -> Vec<Item> {
        self.items
            .roots()
            .map(|item| ItemView { item, offset: 0 }.materialize())
            .collect()
    }
    /// Overflow fallback backing, exposed only for borrowed storage accounting.
    pub fn wide_relative_items(&self) -> Option<&Arc<[Item]>> {
        self.items.wide_items()
    }
    pub fn shared_source(&self) -> Option<&dm_preprocess::SourceText> {
        self.items.source()
    }
    pub fn visit_settings_owners(&self, mut visit: impl FnMut(&Arc<dm_ir::ProcedureMetadata>)) {
        for body in &self.bodies {
            if let Some(owner) = &body.settings_owner {
                visit(owner);
            }
        }
    }
    pub fn visit_item_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        self.items.visit_storage(visit);
    }
    pub fn visit_body_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(
            self.bodies.as_ptr() as usize,
            self.bodies.len() * std::mem::size_of::<RelativeBody>(),
            self.bodies.capacity() * std::mem::size_of::<RelativeBody>(),
        );
        for body in &self.bodies {
            visit(
                Arc::as_ptr(&body.code) as usize,
                std::mem::size_of::<BodyCodeIdentity>(),
                std::mem::size_of::<BodyCodeIdentity>(),
            );

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
        self.relative.items.roots().len()
    }
    pub fn is_empty(&self) -> bool {
        self.relative.items.roots().len() == 0
    }
    pub fn items(&self) -> impl ExactSizeIterator<Item = ItemView<'_>> + DoubleEndedIterator {
        self.relative.items.roots().map(|item| ItemView {
            item,
            offset: self.offset,
        })
    }
    fn item(&self, index: usize) -> Option<ItemView<'_>> {
        self.relative.items.roots().nth(index).map(|item| ItemView {
            item,
            offset: self.offset,
        })
    }
}
#[derive(Clone, Copy, Debug)]
pub struct ItemView<'a> {
    item: arena::Ref<'a>,
    offset: usize,
}
impl PartialEq for ItemView<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.kind() == other.kind()
            && self.header() == other.header()
            && self.span() == other.span()
            && self.header_span() == other.header_span()
            && self.item.indent() == other.item.indent()
            && self.children().eq(other.children())
    }
}
impl Eq for ItemView<'_> {}
impl<'a> ItemView<'a> {
    pub fn offset(self) -> usize {
        self.offset
    }
    pub fn same_node(self, other: ItemView<'_>) -> bool {
        self.item.same(other.item) && self.offset == other.offset
    }
    pub fn same_relative_node(self, other: ItemView<'_>) -> bool {
        self.item.same(other.item)
    }
    pub fn kind(self) -> ItemKind {
        self.item.kind()
    }
    pub fn header(self) -> &'a str {
        self.item.header()
    }
    pub fn relative_span(self) -> Span {
        self.item.span()
    }
    pub fn span(self) -> Span {
        let span = self.item.span();
        Span::new(span.start + self.offset, span.end + self.offset)
    }
    pub fn header_span(self) -> Span {
        let span = self.item.header_span();
        Span::new(span.start + self.offset, span.end + self.offset)
    }
    pub fn children(self) -> impl ExactSizeIterator<Item = ItemView<'a>> + DoubleEndedIterator {
        self.item.children().map(move |item| ItemView {
            item,
            offset: self.offset,
        })
    }
    pub fn child(self, index: usize) -> Option<Self> {
        self.item.children().nth(index).map(|item| Self {
            item,
            offset: self.offset,
        })
    }
    /// Materialize only this requested subtree; ordinary traversal stays borrowed.
    pub fn materialize(self) -> Item {
        Item {
            kind: self.kind(),
            header: self.header().to_owned(),
            span: self.span(),
            header_span: self.header_span(),
            indent: self.item.indent(),
            children: self.children().map(Self::materialize).collect(),
        }
    }
    /// Standalone ABI adapters historically receive root-relative coordinates.
    pub fn materialize_relative(self) -> Item {
        Self { offset: 0, ..self }.materialize()
    }
}
#[derive(Clone, Debug)]
pub struct DeclarationSyntax {
    chunks: Arc<[CurrentSyntaxChunk]>,
    prefix: Arc<[usize]>,
    len: usize,
    ordered_chunks: bool,
}
impl DeclarationSyntax {
    /// Exact current parser header context. Procedure executable children are
    /// deliberately excluded from declaration authority.
    pub fn declaration_header_at(&self, offset: usize) -> Option<ItemKind> {
        fn search<'a>(
            len: usize,
            item: &dyn Fn(usize) -> Option<ItemView<'a>>,
            offset: usize,
        ) -> Option<ItemKind> {
            let (mut low, mut high) = (0, len);
            while low < high {
                let mid = low + (high - low) / 2;
                if item(mid)?.header_span().start <= offset {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
            let node = item(low.checked_sub(1)?)?;
            if node.header_span().start == offset {
                return matches!(
                    node.kind(),
                    ItemKind::Type | ItemKind::Var | ItemKind::Proc | ItemKind::Verb
                )
                .then_some(node.kind());
            }
            if offset >= node.span().end || !matches!(node.kind(), ItemKind::Type | ItemKind::Var) {
                return None;
            }
            search(node.children().len(), &|index| node.child(index), offset)
        }
        if !self.ordered_chunks {
            return None;
        }
        let index = self
            .chunks
            .partition_point(|chunk| chunk.offset <= offset)
            .checked_sub(1)?;
        let chunk = &self.chunks[index];
        if offset.checked_sub(chunk.offset)? >= chunk.relative.source_len {
            return None;
        }
        search(chunk.len(), &|index| chunk.item(index), offset)
    }
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
        // Public compatibility binding may supply unsorted/overlapping chunks.
        // Preserve iteration but decline coordinate authority for that topology.
        let ordered_chunks = chunks.windows(2).all(|pair| {
            pair[0]
                .offset
                .checked_add(pair[0].relative.source_len)
                .is_some_and(|end| end <= pair[1].offset)
        });
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
            ordered_chunks,
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
    fn compact_views_preserve_setting_values_errors_and_current_coordinates() {
        for source in [
            "/proc/run()\n    if(1)\n        set waitfor = 0\n    else\n        set name = \"alternate\"\n",
            "/proc/run()\n    set waitfor = 0\n        return 1\n",
        ] {
            let parsed=dm_syntax::parse(source);
            let old=parsed.items.clone();
            let relative=Arc::new(RelativeSyntax::capture(parsed.items,source).unwrap());
            let current=relative.bind(source.len(),37).unwrap();
            let body=current.items().next().unwrap();
            let mut before=dm_ir::SymbolTable::default();
            let mut after=dm_ir::SymbolTable::default();
            assert_eq!(crate::settings::extract_settings(&old[0].children,&mut before),crate::settings::extract_settings_view(body,&mut after));
            assert_eq!(before.ordered(),after.ordered());
            assert_eq!(body.materialize_relative(),old[0]);
            assert_eq!(body.span().start,old[0].span.start+37);
            assert_eq!(body.header_span().start,old[0].header_span.start+37);
        }
    }
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
        assert_eq!(relative.materialize_relative_items(), original);
        assert!(syntax.item(2).is_none());
        assert!(syntax.item_path(&[1, 100]).is_none());
        let mut items = syntax.items();
        assert_eq!(items.next().unwrap().span().start, 0);
        assert_eq!(items.next_back().unwrap().span().start, 107);
        assert_eq!(items.len(), 0);
    }
    #[test]
    fn body_candidate_facts_rebind_without_rescanning_current_source() {
        let source = "/proc/plain()\n    return \"static\"\n/proc/stored()\n    var/static/value = 1\n    return value\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let syntax = DeclarationSyntax::new(vec![
            relative.bind(source.len(), 0).unwrap(),
            relative.bind(source.len(), 200).unwrap(),
        ])
        .unwrap();
        let candidates = syntax
            .body_recipes()
            .map(|recipe| recipe.stored_candidates())
            .collect::<Vec<_>>();
        assert_eq!(candidates, [false, true, false, true]);
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
        let source = "/datum/ÃƒÆ’Ã‚Â©\n";
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

#[cfg(test)]
mod header_lookup_tests {
    use super::*;
    #[test]
    fn issued_declaration_headers_exclude_executable_calls_and_rebind_chunks() {
        let source = "/datum/a\n    proc/run()\n        for(var/i=0; i<1; i++)\n            foo()\n        foo()\n    verb/act()\n        foo()\n/proc/top()\n    foo()\n/var/value=1\n";
        let parsed = dm_syntax::parse(source);
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let shift = source.len() + 30;
        let syntax = DeclarationSyntax::new(vec![
            relative.bind(source.len(), 0).unwrap(),
            relative.bind(source.len(), shift).unwrap(),
        ])
        .unwrap();
        for base in [0, shift] {
            for (text, kind) in [
                ("/datum/a", ItemKind::Type),
                ("proc/run()", ItemKind::Proc),
                ("verb/act()", ItemKind::Verb),
                ("/proc/top()", ItemKind::Proc),
                ("/var/value", ItemKind::Var),
            ] {
                let offset = base + source.find(text).unwrap();
                assert_eq!(syntax.declaration_header_at(offset), Some(kind));
                assert_eq!(syntax.declaration_header_at(offset + 1), None);
            }
            for (offset, _) in source.match_indices("foo()") {
                assert_eq!(syntax.declaration_header_at(base + offset), None);
            }
            assert_eq!(
                syntax.declaration_header_at(base + source.find("for(").unwrap()),
                None
            );
        }
        assert_eq!(syntax.declaration_header_at(source.len() + 2), None);
        assert_eq!(syntax.declaration_header_at(usize::MAX), None);
    }
    #[test]
    fn foreign_chunk_topology_cannot_issue_header_context() {
        let source = "/proc/top()\n    return 1\n";
        let relative =
            Arc::new(RelativeSyntax::capture(dm_syntax::parse(source).items, source).unwrap());
        for offsets in [[40, 0], [0, 1]] {
            let syntax = DeclarationSyntax::new(
                offsets
                    .into_iter()
                    .map(|offset| relative.bind(source.len(), offset).unwrap())
                    .collect(),
            )
            .unwrap();
            for offset in offsets {
                assert_eq!(syntax.declaration_header_at(offset), None);
            }
        }
    }
}
