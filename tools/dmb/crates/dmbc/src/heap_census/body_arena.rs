//! Retained boxed parses and their issued immutable receipts.
use super::HeapCensus;
impl HeapCensus {
    pub fn body_arena(&mut self, arena: &dm_tree::frontend::BodyArena<'_>) {
        let owner = "body_arena";
        let storage = arena.visit_retained(|_, retained| match retained {
            Ok(parsed) => {
                let bytes = dm_tree::frontend::BodyArena::retained_result_bytes();
                self.buffer(owner, parsed as *const _ as usize, bytes, bytes);
                if let Some(receipt) = parsed.stored_declaration_receipt() {
                    if self.arc_object("startup.static_receipts", &receipt) {
                        self.static_plan(receipt.plan());
                    }
                }
                self.string(owner, &parsed.item().header);
                self.items(owner, &parsed.item().children);
                if let Some(body) = parsed.shared_statement_body() {
                    if self.arc_object(owner, &body) {
                        self.typed_body(owner, &body);
                    }
                }
            }
            Err(error) => {
                let bytes = dm_tree::frontend::BodyArena::retained_result_bytes();
                self.buffer(owner, error as *const _ as usize, bytes, bytes);
                self.string(owner, &error.message);
                if let Some(location) = &error.location {
                    self.source_location(owner, location);
                    if self.arc_object(owner, &location.macro_expansions)
                        && self.vec_payload(owner, &location.macro_expansions)
                    {
                        for expansion in location.macro_expansions.iter() {
                            self.macro_trace(owner, expansion);
                        }
                    }
                }
            }
        });
        self.owner(owner).observed_items += storage.len as u64;
        self.buffer(
            owner,
            storage.address,
            storage.len.saturating_mul(storage.slot_bytes),
            storage.capacity.saturating_mul(storage.slot_bytes),
        );
        self.unknown(
            owner,
            "taken ASTs are transient and absent at this quiescent boundary",
        );
    }
}
