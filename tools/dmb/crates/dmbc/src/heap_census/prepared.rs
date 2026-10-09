//! Borrowed accounting of compact completion payloads, never re-freezing code.
use super::*;

impl HeapCensus {
    pub fn prepared(&mut self, contributions: &Vec<crate::symbolic::PreparedContribution>) {
        if self.vec_payload("prepared_contributions", contributions) {
            for contribution in contributions {
                contribution.census(self);
            }
        }
    }
    pub(crate) fn prepared_unit(&mut self, unit: &crate::symbolic::FrozenUnit) {
        let owner = "prepared_contributions";
        self.frozen_code(&unit.frozen);
        self.debug(owner, &unit.lowered.debug_origins);
        self.source_location(owner, &unit.lowered.origin.source);
        self.slice(owner, &unit.lowered.origin.ast_path, true);
        self.slice(owner, &unit.lowered.origin.setting_context_origins, true);
        for origin in unit.lowered.origin.setting_context_origins.iter() {
            self.source_location(owner, origin);
        }
        self.strings(owner, &unit.lowered.frame.local_names);
        self.strings(owner, &unit.lowered.frame.argument_names);
        self.vec_payload(owner, &unit.lowered.frame.argument_type_flags);
        if let Some(abi) = &unit.lowered.abi {
            self.abi(abi);
        }
    }
    pub(crate) fn prepared_helper(&mut self, helper: &crate::symbolic::FrozenHelper) {
        self.frozen_code(&helper.frozen);
        self.debug("prepared_contributions", &helper.debug_origins);
        self.strings("prepared_contributions", &helper.local_names);
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
