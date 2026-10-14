//! Shared latest-image owner accounting; no linking or binding work is repeated.
use super::*;
impl HeapCensus {
    pub(crate) fn latest_image(&mut self, owner: &Arc<crate::symbolic::latest_image::LatestImage>) {
        if !self.arc_object("latest_images", owner) {
            return;
        }
        owner.visit_retained(|frozen,answers,image| {
            self.frozen_code(frozen);
            let (bindings,capacity)=answers.storage();
            if self.arc_object("latest_images.bindings",bindings) {
                self.collection_entries::<(dm_ir::SymRef,u32)>("latest_images.bindings",
                    Arc::as_ptr(bindings) as usize,bindings.len());
                if capacity!=0 {
                    self.unknown("latest_images.bindings","HashMap allocated bucket bytes/control bytes and Arc control blocks are unavailable; entries are logical payload lower bounds, not capacity estimates");
                }
            }
            if self.arc_object("latest_images.words",&image.words) {
                self.vec_payload("latest_images.words",&image.words);
            }
        });
        owner.visit_certificate(|bindings, origins| {
            let (address, inline, assignments, slots) = bindings.storage();
            if self.buffer("latest_images.table_certificate", address, inline, inline) {
                self.observe_items("latest_images.table_certificate", assignments.saturating_add(slots));
                self.unknown("latest_images.table_certificate", "private BTree index nodes and Arc control block bytes excluded; immutable owner descriptor size is exact");
            }
            origins.census(self, "latest_images.source_certificate");
        });
        owner.visit_retained_wire(|base, answers, image| {
            for words in [&base.words, &image.words] {
                if self.arc_object("latest_images.wire_words", words) {
                    self.vec_payload("latest_images.wire_words", words);
                }
            }
            let patches = answers.storage();
            if self.arc_object("latest_images.wire_answers", patches) {
                self.vec_payload("latest_images.wire_answers", patches);
            }
        });
    }
}
