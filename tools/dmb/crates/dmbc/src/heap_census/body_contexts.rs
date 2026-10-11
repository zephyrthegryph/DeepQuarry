//! Shared current source envelope census, counting immutable owners once.
use super::*;
impl HeapCensus {
    pub(crate) fn body_occurrences(
        &mut self,
        owner: &str,
        bodies: &Arc<[dm_tree::frontend::BodyOccurrence]>,
    ) {
        self.slice(owner, bodies, true);
        for body in bodies.iter() {
            self.slice(owner, &body.ast_path, true);
            self.slice(owner, &body.setting_context_origins, true);
            self.source_location(owner, &body.source);
            for location in body.setting_context_origins.iter() {
                self.source_location(owner, location);
            }
        }
    }
}
