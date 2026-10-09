//! Borrow persistent macro payloads without inventing private im node capacity.
use super::*;

impl HeapCensus {
    pub(super) fn macro_environments(&mut self, frontend: &dm_tree::frontend::ColdFrontend) {
        let owner = "frontend.macro_environments";
        let mut previous = None;
        for region in &frontend.plan.regions {
            for segment in &region.segments {
                let environment = &segment.macros;
                if previous.is_some_and(|prior| environment.shares_storage_with(prior)) {
                    continue;
                }
                let visitor = |name: &Arc<str>, address, inline_bytes, definition: &Arc<dm_preprocess::Macro>, origin: Option<&dm_preprocess::regions::DefinitionOrigin>| {
                    self.arc_text(owner, name);
                    if !self.buffer(owner, address, inline_bytes, inline_bytes) {
                        return;
                    }
                    if self.arc_object(owner, definition) {
                        self.string(owner, &definition.replacement);
                        if let Some(parameters) = &definition.parameters {
                            self.strings(owner, parameters);
                        }
                    }
                    if let Some(origin) = origin {
                        self.arc_path(owner, &origin.path);
                    }
                };
                if let Some(prior) = previous {
                    environment.visit_storage_difference(prior, visitor);
                } else {
                    environment.visit_storage(visitor);
                }
                previous = Some(environment);
            }
            // Effects retain owned copies, independently of persistent bindings.
            for effect in &region.effects {
                use dm_preprocess::regions::MacroEffect;
                match effect {
                    MacroEffect::Define { name, definition } => {
                        self.string(owner, name);
                        self.macro_payload(owner, definition);
                    }
                    MacroEffect::Undef { name } => self.string(owner, name),
                    MacroEffect::PushFileDir { path, definition } => {
                        self.path(owner, path);
                        self.macro_payload(owner, definition);
                    }
                    MacroEffect::PopFileDir => (),
                }
            }
        }
        self.unknown(owner, "persistent im::OrdMap node allocations and Arc control blocks are opaque; changed snapshots use public structural diff to skip shared nodes, with payload-pointer deduplication");
    }
    fn macro_payload(&mut self, owner: &str, definition: &dm_preprocess::Macro) {
        self.string(owner, &definition.replacement);
        if let Some(parameters) = &definition.parameters {
            self.strings(owner, parameters);
        }
    }
}
