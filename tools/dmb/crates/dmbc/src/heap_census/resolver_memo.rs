//! Request-local answer memo accounting; it is dropped before retained pressure.
use super::*;
impl HeapCensus {
    pub fn resolver_memo<R: dm_ir::Resolver + ?Sized>(
        &mut self,
        memo: &dm_ir::MemoResolver<'_, R>,
    ) {
        memo.visit_storage(|view| match view {
            dm_ir::MemoStorageView::Buffer { pointer, bytes, capacity } => {
                self.buffer("request_resolver_memo.canonical", pointer, bytes, capacity);
            }
            dm_ir::MemoStorageView::Answer(answer) => resident_weight::answer(self, answer),
            dm_ir::MemoStorageView::PrivateIndex { entries, capacity: _ } => {
                self.observe_items("request_resolver_memo.index", entries);
                self.unknown("request_resolver_memo.index", "HashMap private buckets/control capacity is not exposed; request-local index payload and allocator layout remain unknown");
            }
        });
    }
}
