//! Exact retained canonical generation owners; no model or byte clones.
use super::*;
impl HeapCensus {
    pub fn composition_generation(&mut self, generation: &crate::composition::RetainedGeneration) {
        generation.census_plan(self);
        generation.visit_retained(|model, encoded| {
            self.dmb_image(model);
            self.output_encoded("retained.generation.encoded", encoded);
        });
        self.unknown("retained.generation", "Mutex/owner inline layout and allocator metadata are unavailable; list and encoded Arc control blocks are reported as unknown structural overhead");
    }
}
