//! One exact physical record producer shared by binding and emission.
use super::{ClassProjection, FieldProjection, FieldRole, ProcedureStaticProjection};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum VariableRecord {
    Field(usize),
    ProcedureStatic(usize),
}
#[derive(Debug)]
pub(crate) struct VariableRecordRoster {
    fields: Arc<[Arc<FieldProjection>]>,
    statics: Arc<[ProcedureStaticProjection]>,
    entries: Vec<VariableRecord>,
}
impl VariableRecordRoster {
    fn issue(projection: &ClassProjection) -> Self {
        let entries = projection
            .fields
            .iter()
            .enumerate()
            .filter(|(_, field)| field.role == FieldRole::Declaration)
            .map(|(index, _)| VariableRecord::Field(index))
            .chain((0..projection.procedure_statics.len()).map(VariableRecord::ProcedureStatic))
            .collect();
        Self {
            fields: projection.fields.clone(),
            statics: projection.procedure_statics.clone(),
            entries,
        }
    }
    fn admits(&self, projection: &ClassProjection) -> bool {
        (Arc::ptr_eq(&self.fields, &projection.fields) || self.fields == projection.fields)
            && (Arc::ptr_eq(&self.statics, &projection.procedure_statics)
                || self.statics == projection.procedure_statics)
    }
    pub(crate) fn iter(&self) -> impl Iterator<Item = VariableRecord> + '_ {
        self.entries.iter().copied()
    }
    pub(crate) fn storage(
        &self,
    ) -> (
        &Arc<[Arc<FieldProjection>]>,
        &Arc<[ProcedureStaticProjection]>,
        &Vec<VariableRecord>,
    ) {
        (&self.fields, &self.statics, &self.entries)
    }
}
impl ClassProjection {
    pub(crate) fn variable_record_roster(&self) -> Arc<VariableRecordRoster> {
        let roster = self
            .variable_records
            .get_or_init(|| Arc::new(VariableRecordRoster::issue(self)));
        if roster.admits(self) {
            roster.clone()
        } else {
            Arc::new(VariableRecordRoster::issue(self))
        }
    }
    pub(crate) fn retained_variable_record_roster(&self) -> Option<&Arc<VariableRecordRoster>> {
        self.variable_records.get()
    }
}
