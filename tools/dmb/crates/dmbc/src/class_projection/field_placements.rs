//! Sparse current source positions beside source-neutral retained contributions.
use super::{ClassProjection, FieldProjection, ProjectionError};
use dm_tree::{
    frontend::{ColdFrontend, SourceLocation},
    OccurrenceId,
};
use std::{collections::BTreeMap, sync::Arc};
#[derive(Clone, Debug, Default)]
pub struct FieldPlacements {
    candidates: Vec<(usize, OccurrenceId)>,
    locations: BTreeMap<usize, SourceLocation>,
}
/// Only independently confirmed invalid intrinsic values are source errors.
/// This decision is shared by current binding and ordered wire materialization.
pub(super) fn source_error_message(field: &FieldProjection) -> Option<String> {
    use crate::initializer_policy::DefaultValue;
    use dm_ir::{SemanticValue, SymbolId};
    if !field.intrinsic || field.role != super::FieldRole::Assignment {
        return None;
    }
    if field.declaring_owner == SymbolId::of("/atom") && field.name == SymbolId::of("gender") {
        if let DefaultValue::Scalar(SemanticValue::Text(value)) = &field.value {
            if !matches!(value.as_ref(), b"neuter" | b"male" | b"female" | b"plural") {
                return Some("invalid gender".into());
            }
        }
    }
    if field.declaring_owner != SymbolId::of("/mob") {
        return None;
    }
    let DefaultValue::Scalar(SemanticValue::NumberBits(bits)) = field.value else {
        return None;
    };
    let number = f32::from_bits(bits);
    if !number.is_finite() {
        return None;
    }
    let reason = if field.name == SymbolId::of("sight") && number < 0.0 {
        "out of bounds"
    } else if field.name == SymbolId::of("see_in_dark") && number < 0.0 {
        "expected range is 0 and up"
    } else if field.name == SymbolId::of("see_invisible") && !(0.0..=101.0).contains(&number) {
        "expected range is 0 to 101"
    } else {
        return None;
    };
    Some(format!("{number}: {reason}"))
}
impl FieldPlacements {
    pub(super) fn push(
        &mut self,
        field_index: usize,
        occurrence: OccurrenceId,
        field: &FieldProjection,
    ) {
        if source_error_message(field).is_some() {
            self.candidates.push((field_index, occurrence));
        }
    }
    pub(super) fn error(&self, field: usize, message: String) -> ProjectionError {
        if self.locations.contains_key(&field) {
            ProjectionError::SourceError { field, message }
        } else {
            ProjectionError::Unsupported(format!("unbound source error: {message}"))
        }
    }
}
impl ClassProjection {
    pub(crate) fn bind_field_sources(
        &mut self,
        frontend: &ColdFrontend,
        plan: &dm_tree::initializers::InitializerPlan,
    ) -> Result<(), ProjectionError> {
        if !Arc::ptr_eq(&plan.source.occurrences, &frontend.snapshot.occurrences) {
            return Err(ProjectionError::IdentityMismatch);
        }
        // Ordinary valid builds do not create an origins index or traverse the
        // expanded source. Invalid candidates never emit an early diagnostic.
        if self.field_placements.candidates.is_empty() {
            return Ok(());
        }
        let wanted = self
            .field_placements
            .candidates
            .iter()
            .map(|(_, id)| id.0)
            .collect::<std::collections::BTreeSet<_>>();
        let origins = plan
            .origins
            .iter()
            .filter(|origin| wanted.contains(&origin.occurrence.0))
            .map(|origin| (origin.occurrence.0, origin))
            .collect::<BTreeMap<_, _>>();
        let mut selected = Vec::new();
        for &(index, id) in &self.field_placements.candidates {
            let field = self
                .fields
                .get(index)
                .ok_or(ProjectionError::InvalidOccurrence(id))?;
            if source_error_message(field).is_none() {
                return Err(ProjectionError::IdentityMismatch);
            }
            let occurrence = frontend
                .snapshot
                .occurrences
                .get(id)
                .ok_or(ProjectionError::InvalidOccurrence(id))?;
            let origin = origins
                .get(&id.0)
                .ok_or(ProjectionError::InvalidOccurrence(id))?;
            if origin.provenance != occurrence.provenance {
                return Err(ProjectionError::IdentityMismatch);
            }
            selected.push(*origin);
        }
        let locations = crate::initializer_diagnostics::captured_locations(frontend, &selected)
            .map_err(|error| {
                ProjectionError::Unsupported(format!("field source binding: {error}"))
            })?;
        for (&(index, _), location) in self.field_placements.candidates.iter().zip(locations) {
            self.field_placements.locations.insert(index, location);
        }
        Ok(())
    }
    pub(crate) fn source_diagnostic(
        &self,
        field: usize,
        message: String,
    ) -> Option<crate::lowering::LoweringDiagnostic> {
        Some(crate::lowering::LoweringDiagnostic {
            kind: dm_tree::frontend::DiagnosticKind::SourceError,
            identity: None,
            origin: self.field_placements.locations.get(&field)?.clone(),
            message,
        })
    }
}
#[cfg(test)]
#[path = "field_placements_tests.rs"]
mod tests;
