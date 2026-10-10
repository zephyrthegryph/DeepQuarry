//! Borrowed header-recipe owners; no wire IDs or canonical materialization.
use super::*;
use crate::class_projection::header_recipes::HeaderRecipe;
fn recipe(census: &mut HeapCensus, value: &HeaderRecipe) {
    census.vec_payload("retained.headers.owner", &value.owner);
    census.strings("retained.headers.inherited_fields", &value.inherited_fields);
    for values in [
        &value.local,
        &value.effective_authored,
        &value.effective_overrides,
    ] {
        census.observe_items("retained.headers.sets", values.len());
        for name in values {
            census.string("retained.headers.names", name);
        }
    }
    census.observe_items("retained.headers.native", value.native_overrides.len());
    for name in &value.native_overrides {
        census.vec_payload("retained.headers.native", name);
    }
}
impl HeapCensus {
    pub(crate) fn header_recipes(&mut self, recipes: &crate::class_projection::HeaderRecipes) {
        use dm_session::ObservedArtifactStorageView as V;
        recipes.visit_storage(|view| match view {
            V::Store { entries, .. } => {
                self.observe_items("retained.headers.index", entries);
            }
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "retained.headers.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            V::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("retained.headers.keys", key, true);
                if self.slice("retained.headers.reads", reads, true) {
                    for read in reads.iter() {
                        if self.arc_object("retained.headers.parent", &read.answer) {
                            recipe(self, &read.answer);
                        }
                    }
                }
                self.slice("retained.headers.versions", versions, true);
                if self.arc_object("retained.headers.values", value) {
                    recipe(self, value);
                }
            }
        });
        recipes.visit_default_storage(|view| match view {
            V::Store { entries, .. } => {
                self.observe_items("retained.header_defaults.index", entries);
            }
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                self.buffer(
                    "retained.header_defaults.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            V::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                self.slice("retained.header_defaults.keys", key, true);
                self.slice("retained.header_defaults.reads", reads, true);
                self.slice("retained.header_defaults.versions", versions, true);
                if self.arc_object("retained.header_defaults.values", value)
                    && self.vec_payload("retained.header_defaults.rows", value)
                {
                    for selector in value.iter() {
                        self.vec_payload("retained.header_defaults.names", &selector.name);
                    }
                }
            }
        });
        self.unknown("retained.headers.index","private BTree nodes and allocator overhead excluded; exposed keys/observations/recipe buffers counted; current-roster retention has no byte admission budget");
    }
}
