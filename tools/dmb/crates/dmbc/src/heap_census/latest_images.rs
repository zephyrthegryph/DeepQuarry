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
    }
}
