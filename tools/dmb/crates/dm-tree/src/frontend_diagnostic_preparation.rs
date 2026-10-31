//! Diagnostic-only preparation over ONE original native frontend pass.
//! No alternate parser, model, normalized member table or runtime ABI receipt.
use super::*;
use crate::diagnostic_declarations::DiagnosticDeclarationReceipt;
use crate::SemanticTree;
pub struct DiagnosticFrontend {
    inner: ColdFrontend,
    receipt: Arc<DiagnosticDeclarationReceipt>,
    archive: Arc<BodyArchive>,
    retained_records: Option<super::DiagnosticRetainedRecords>,
}
/// Sealed borrowed projection of existing handles, never an alternate Sem model.
/// Only the original diagnostic preparation can issue this view.
pub struct DiagnosticSourceView<'a> {
    owner: &'a DiagnosticFrontend,
}
impl DiagnosticFrontend {
    pub(super) fn bind(
        inner: ColdFrontend,
        mut receipt: DiagnosticDeclarationReceipt,
    ) -> Result<Self, Vec<Diagnostic>> {
        if !receipt.authenticates(&inner.snapshot.tree) {
            return Err(vec![internal(
                "diagnostic declaration receipt belongs to another native graph",
            )]);
        }
        let archive = inner
            .body_archive()
            .ok_or_else(|| vec![internal("diagnostic original archive unavailable")])?;
        receipt.settings_compilable=inner.issued_settings.iter().flatten().all(|owner|crate::procedure::settings_compilable(&owner.settings,inner.snapshot.tree.symbols()));
        if !receipt.settings_compilable{receipt.retained_records=None;}
        let retained_records = receipt.retained_records.take();
        Ok(Self {
            retained_records,
            inner,
            receipt: Arc::new(receipt),
            archive,
        })
    }
    pub fn with_body_queries(self, host: Arc<dyn BodySyntaxQueries>) -> Result<Self, String> {
        let Self {
            inner,
            receipt,
            retained_records,
            ..
        } = self;
        let inner = inner.with_body_queries(host);
        let archive = inner
            .body_archive()
            .ok_or("diagnostic current body-query archive unavailable")?;
        Ok(Self {
            inner,
            receipt,
            archive,
            retained_records,
        })
    }
    pub fn source_view(&self) -> Result<DiagnosticSourceView<'_>, String> {
        if !self.receipt.authenticates(&self.inner.snapshot.tree)
            || !self.archive.matches_tree(&self.inner.snapshot.tree)
            || !self
                .inner
                .source_export_mapping()
                .is_some_and(|mapping| Arc::ptr_eq(mapping, self.archive.source_mapping()))
        {
            return Err("diagnostic original source handles no longer agree".into());
        }
        Ok(DiagnosticSourceView { owner: self })
    }
    /// The ordinary compiler can consume this exact original frontend only when
    /// its declaration builder recorded NO compile errors. No second parse/build.
    pub fn try_into_compilable_retained(
        mut self,
        state: &mut RetainedSemanticTree,
    ) -> Result<ColdFrontend, Self> {
        if self.receipt.settings_compilable() && self.receipt.errors().is_empty()
            && state
                .snapshot_tree()
                .is_some_and(|tree| Arc::ptr_eq(tree, &self.inner.snapshot.tree))
        {
            // Existing complete native entry already owns this exact graph.
            return Ok(self.inner);
        }
        if !self.receipt.settings_compilable() || !self.receipt.errors().is_empty() || self.retained_records.is_none() {
            return Err(self);
        }
        let records = self
            .retained_records
            .take()
            .expect("complete original records checked");
        state
            .adopt_valid_diagnostic_records(records, &self.inner.snapshot)
            .expect("private original diagnostic record owner cannot change");
        Ok(self.inner)
    }
    pub fn try_into_compilable(self) -> Result<ColdFrontend, Self> {
        if self.receipt.settings_compilable() && self.receipt.errors().is_empty() {
            Ok(self.inner)
        } else {
            Err(self)
        }
    }
}
impl DiagnosticSourceView<'_> {
    pub fn tree(&self) -> &Arc<SemanticTree> {
        &self.owner.inner.snapshot.tree
    }
    pub fn occurrences(&self) -> &Arc<crate::OccurrenceTable> {
        &self.owner.inner.snapshot.occurrences
    }
    pub fn archive(&self) -> &Arc<BodyArchive> {
        &self.owner.archive
    }
    pub fn mapping(&self) -> &Arc<SourceExportMapping> {
        self.owner.archive.source_mapping()
    }
    pub fn files(&self) -> &Arc<[SourceFile]> {
        &self.owner.inner.files
    }
    pub fn bodies(&self) -> &Arc<[BodyOccurrence]> {
        &self.owner.inner.bodies
    }
    pub fn source_revision(&self) -> u128 {
        self.owner.inner.source_export_revision()
    }
    pub fn receipt(&self) -> &Arc<DiagnosticDeclarationReceipt> {
        &self.owner.receipt
    }
    pub fn includes(&self) -> impl Iterator<Item = (usize, &Arc<PathBuf>)> {
        self.owner
            .inner
            .plan
            .occurrences
            .iter()
            .enumerate()
            .map(|(index, row)| (index, &row.path))
    }
}

#[cfg(test)]
#[path = "frontend_diagnostic_preparation_tests.rs"]
mod tests;
