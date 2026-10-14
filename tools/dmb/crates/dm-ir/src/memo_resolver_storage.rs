//! Optional borrowed census of the same request memo; no retained owner facade.
use super::*;
pub enum MemoStorageView<'a> {
    Buffer {
        pointer: usize,
        bytes: usize,
        capacity: usize,
    },
    Answer(&'a ResolvedMeaning),
    PrivateIndex {
        entries: usize,
        capacity: usize,
    },
}
impl<R: Resolver + ?Sized> MemoResolver<'_, R> {
    /// Callbacks run outside the memo lock. Arc descriptors remain alive during
    /// the visit; control-block allowances belong to the caller's census policy.
    pub fn visit_storage(&self, mut visit: impl FnMut(MemoStorageView<'_>)) {
        let Ok(entries) = self.entries.read() else {
            return;
        };
        let capacity = entries.capacity();
        let values: Vec<_> = entries
            .values()
            .map(|entry| (entry.answer.clone(), entry.canonical.clone()))
            .collect();
        drop(entries);
        visit(MemoStorageView::PrivateIndex {
            entries: values.len(),
            capacity,
        });
        for (answer, cell) in &values {
            visit(MemoStorageView::Answer(answer));
            if let Some(cell) = cell {
                let size = std::mem::size_of::<OnceLock<Option<Arc<[u8]>>>>();
                visit(MemoStorageView::Buffer {
                    pointer: Arc::as_ptr(cell) as usize,
                    bytes: size,
                    capacity: size,
                });
                if let Some(Some(bytes)) = cell.get() {
                    visit(MemoStorageView::Buffer {
                        pointer: bytes.as_ptr() as usize,
                        bytes: bytes.len(),
                        capacity: bytes.len(),
                    });
                }
            }
        }
    }
    /// Live request-only canonical payload, excludes Arc controls/private table.
    /// Never present this as retained-session bytes or total private memory.
    pub fn canonical_payload_bytes(&self) -> usize {
        self.entries
            .read()
            .map(|entries| {
                entries
                    .values()
                    .filter_map(|entry| {
                        entry
                            .canonical
                            .as_ref()?
                            .get()?
                            .as_ref()
                            .map(|bytes| bytes.len())
                    })
                    .sum()
            })
            .unwrap_or(0)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Missing
        }
    }
    #[test]
    fn canonical_memo_storage_exposes_lazy_cells_and_payload_without_claiming_private_index() {
        let memo = MemoResolver::new(&Host, 4);
        let query = ResolveQuery::GlobalProc(crate::SymbolId::of("missing"));
        memo.resolve(query);
        assert_eq!(memo.canonical_payload_bytes(), 0);
        let mut buffers = Vec::new();
        memo.visit_storage(|view| {
            if let MemoStorageView::Buffer {
                pointer,
                bytes,
                capacity,
            } = view
            {
                buffers.push((pointer, bytes, capacity));
            }
        });
        assert!(buffers.is_empty());
        let answer = memo.resolve_with_canonical(query);
        memo.visit_storage(|view| {
            if let MemoStorageView::Buffer {
                pointer,
                bytes,
                capacity,
            } = view
            {
                buffers.push((pointer, bytes, capacity));
            }
        });
        assert_eq!(buffers.len(), 2);
        assert!(buffers.iter().any(|(pointer, bytes, capacity)| *pointer
            == answer.canonical().as_ptr() as usize
            && *bytes == answer.canonical().len()
            && *capacity == *bytes));
        assert_eq!(memo.canonical_payload_bytes(), answer.canonical().len());
    }
}
