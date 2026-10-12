//! Current source registration events, before physical StringIDs are assigned.
//! These are request-local source facts, not executable artifact/cache identity.
use super::{Key, SymbolId};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StringRegistrationSource {
    pub encounter_order: usize,
    pub expanded_start: usize,
    pub expanded_end: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StringRegistrationEvent {
    FieldName {
        owner: SymbolId,
        name: SymbolId,
        source: StringRegistrationSource,
    },
    /// Only spellings also used by a current source field are retained here.
    /// The field name is registered before its own initializer expression.
    DeclarationStrings {
        owner: SymbolId,
        name: SymbolId,
        strings: Arc<[SymbolId]>,
        source: StringRegistrationSource,
    },
    /// Exact first root proc occurrence, even if a later override is effective.
    /// Captured literals survive folding/dead-code removal in its frozen code.
    FirstRootCallable {
        callable: Key,
        declaration: u32,
        strings: Arc<[SymbolId]>,
        source: StringRegistrationSource,
    },
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct StringRegistration {
    pub events: Vec<StringRegistrationEvent>,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn string_allocation_rejects_unexpanded_source_registration() {
        let inventory = crate::LinkInventory {
            string_registration: Some(StringRegistration::default()),
            ..Default::default()
        };
        assert!(matches!(
            crate::LinkTables::build(inventory),
            Err(crate::LinkError::IncompleteStringRegistration)
        ));
    }
}
