//! Exact retained canonical generation owners; no model or byte clones.
#[path = "header_recipes.rs"]
mod header_recipes;
use super::*;
impl HeapCensus {
    pub fn composition_generation(&mut self, generation: &crate::composition::RetainedGeneration) {
        self.observe_items(
            "retained.generation.wire_memo_evictions",
            generation.wire_memo_evictions() as usize,
        );
        generation.census_plan(self);
        generation.census_string_index(self);
        generation.census_headers(self);
        generation.visit_retained(|model, encoded| {
            self.dmb_image(model);
            self.output_encoded("retained.generation.encoded", encoded);
        });
        self.unknown("retained.generation", "publication/attempt controls, Mutex/owner inline layout and allocator metadata are unavailable; list and encoded Arc control blocks are reported as unknown structural overhead");
    }
}
