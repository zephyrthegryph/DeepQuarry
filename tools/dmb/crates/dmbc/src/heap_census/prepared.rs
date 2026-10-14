//! Borrowed accounting of compact completion payloads, never re-freezing code.
use super::*;

impl HeapCensus {
    pub(crate) fn prepared_inventory_contribution(
        &mut self,
        owner: &Arc<dm_link::InventoryContribution>,
    ) {
        if self.arc_object("symbolic.inventory", owner) {
            self.vec_payload("symbolic.inventory.slots", owner.slots());
            self.prepared_strings(owner.strings());
            self.prepared_entry_bytes(&owner.entry().content);
        }
    }

    pub(crate) fn frozen_frame(
        &mut self,
        owner: &'static str,
        frame: &Arc<crate::symbolic::FrozenFrame>,
    ) {
        if self.arc_object(owner, frame) {
            self.strings(owner, &frame.local_names);
            self.strings(owner, &frame.argument_names);
            self.vec_payload(owner, &frame.argument_type_flags);
        }
    }
    pub fn prepared(&mut self, contributions: &Vec<crate::symbolic::PreparedContribution>) {
        if self.vec_payload("prepared_contributions", contributions) {
            for contribution in contributions {
                contribution.census(self);
            }
        }
    }
    pub(crate) fn prepared_procedure_parts(
        &mut self,
        frozen: &std::sync::Arc<dm_codegen_byond::FrozenProc>,
        frame: &Arc<crate::symbolic::FrozenFrame>,
        abi: &Option<std::sync::Arc<crate::procedure_policy::PreparedAbi>>,
        origin: &dm_tree::frontend::BodyOccurrence,
        debug: &crate::debug_sources::FrozenDebugOrigins,
    ) {
        let owner = "prepared_contributions";
        self.frozen_code(frozen);
        self.frozen_debug(owner, debug);
        self.source_location(owner, &origin.source);
        self.slice(owner, &origin.ast_path, true);
        self.slice(owner, &origin.setting_context_origins, true);
        for origin in origin.setting_context_origins.iter() {
            self.source_location(owner, origin);
        }
        self.frozen_frame(owner, frame);
        if let Some(abi) = abi {
            self.abi(abi);
        }
    }
    pub(crate) fn prepared_helper_parts(
        &mut self,
        frozen: &std::sync::Arc<dm_codegen_byond::FrozenProc>,
        names: &Arc<Vec<String>>,
        debug: &crate::debug_sources::FrozenDebugOrigins,
    ) {
        self.frozen_code(frozen);
        self.frozen_debug("prepared_contributions", debug);
        self.arc_object("helper.local_names", names);
        self.strings("prepared_contributions", names);
    }
    pub(crate) fn prepared_strings(&mut self, strings: &Vec<dm_ir::StringPayload>) {
        let owner = "prepared_strings";
        if self.vec_payload(owner, strings) {
            for payload in strings {
                self.slice(owner, &payload.bytes, true);
            }
        }
    }
    pub(crate) fn prepared_entry_bytes(&mut self, content: &dm_link::EntryContent) {
        self.entry_content("prepared_inventory.entry_bytes", content);
    }
    pub(crate) fn prepared_modified(
        &mut self,
        captured: &dm_codegen_byond::lower_resolver::CapturedModifiedInstance,
        origins: &crate::debug_sources::DebugOrigins,
    ) {
        let owner = "prepared_modified_seeds";
        self.vec_payload(owner, &captured.field_origins);
        self.slice(owner, captured.descriptor.canonical_bytes(), true);
        // ModifiedInstance owns these as Arc<[(String, Expr)]>, not a Vec.
        if self.slice(owner, captured.descriptor.fields(), true) {
            for (name, _) in captured.descriptor.fields() {
                self.string(owner, name);
            }
        }
        self.debug(owner, origins);
        self.unknown(owner, "modified descriptor expression boxes/strings and private resource indexes are not exposed");
    }
}
