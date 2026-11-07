//! Legacy semantic-policy admission is separate from compiler source identity.
//! Native compile/equation caches stay valid when decoding yields equal text.
use super::*;
use dm_preprocess::{SourceAcquisitionLease, SourceEncoding};
use dm_tree::frontend::{ColdFrontend, SourceExportMapping};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Weak,
};
struct Entry {
    occurrence: usize,
    path: Arc<PathBuf>,
    acquisition: Option<SourceAcquisitionLease>,
}
pub(crate) struct SemanticSourceEvidence {
    key: u64,
    mapping: Weak<SourceExportMapping>,
    entries: Box<[Entry]>,
    // This result is issued once from authenticated immutable mapping/receipts.
    // A later request must still prove the exact mapping Arc before reusing it.
    compatibility: Result<(), String>,
}
impl SemanticSourceEvidence {
    pub(crate) fn key(&self) -> u64 {
        self.key
    }
    pub(crate) fn budget_charge(&self) -> usize {
        use dm_preprocess::source_acquisition::AcquisitionStorage as V;
        let mut seen = std::collections::BTreeSet::new();
        let mut charge = std::mem::size_of_val(self)
            .saturating_add(2 * std::mem::size_of::<usize>())
            .saturating_add(std::mem::size_of_val(self.entries.as_ref()));
        if let Err(error) = &self.compatibility {
            charge = charge.saturating_add(error.capacity());
        }
        for entry in &self.entries {
            if seen.insert((3, Arc::as_ptr(&entry.path) as usize)) {
                charge = charge
                    .saturating_add(std::mem::size_of_val(entry.path.as_ref()))
                    .saturating_add(2 * std::mem::size_of::<usize>())
                    .saturating_add(entry.path.capacity());
            }
            if let Some(acquired) = &entry.acquisition {
                acquired.visit_storage(|value| match value {
                    V::Object { address, bytes } => {
                        if seen.insert((0, address)) {
                            charge = charge
                                .saturating_add(bytes)
                                .saturating_add(2 * std::mem::size_of::<usize>());
                        }
                    }
                    V::Receipt {
                        address,
                        bytes,
                        value,
                    } => {
                        if seen.insert((1, address)) {
                            if let Some(original) = super::recorded_source_receipt_original(value) {
                                let owner = original.shared_owner();
                                if seen.insert((5, owner as *const dm_resources::SharedBytesOwner as usize)) {
                                    charge = charge
                                        .saturating_add(std::mem::size_of_val(owner))
                                        .saturating_add(2 * std::mem::size_of::<usize>())
                                        .saturating_add(owner.bytes().capacity());
                                }
                            }
                            charge = charge
                                .saturating_add(bytes)
                                .saturating_add(2 * std::mem::size_of::<usize>());
                            if let Some((path, fact_path, issuer)) =
                                super::recorded_source_receipt_storage(value)
                            {
                                if seen.insert((4, Arc::as_ptr(issuer) as usize)) {
                                    charge = charge
                                        .saturating_add(std::mem::size_of_val(issuer.as_ref()))
                                        .saturating_add(2 * std::mem::size_of::<usize>());
                                }
                                for path in [path, fact_path] {
                                    if seen.insert((
                                        2,
                                        path.as_os_str().as_encoded_bytes().as_ptr() as usize,
                                    )) {
                                        charge = charge.saturating_add(path.capacity());
                                    }
                                }
                            } else {
                                charge = usize::MAX;
                            }
                        }
                    }
                    // Prepared lexical payloads have their existing native
                    // retention budget; this charges new admission metadata.
                    V::Source(_) => {}
                });
            }
        }
        charge
    }

    pub(crate) fn require_mapping(&self, mapping: &Arc<SourceExportMapping>) -> io::Result<()> {
        if !Weak::ptr_eq(&self.mapping, &Arc::downgrade(mapping)) {
            return Err(invalid(
                "semantic source admission belongs to another issued source mapping",
            ));
        }
        Ok(())
    }
    pub(crate) fn check(&self, mapping: &Arc<SourceExportMapping>) -> io::Result<()> {
        self.require_mapping(mapping)?;
        self.compatibility
            .as_ref()
            .map(|_| ())
            .map_err(|error| invalid(error))
    }
    fn evaluate_compatibility(
        mapping: &Arc<SourceExportMapping>,
        entries: &[Entry],
    ) -> io::Result<()> {
        for entry in entries {
            let acquired = entry.acquisition.as_ref().ok_or_else(|| {
                invalid(&format!(
                    "semantic source original encoding unproven: {}",
                    entry.path.display()
                ))
            })?;
            if mapping
                .source_acquisition(entry.occurrence)
                .is_none_or(|current| !current.same_binding(acquired))
            {
                return Err(invalid(
                    "semantic source admission acquisition binding is foreign",
                ));
            }
            match acquired.encoding() {
                SourceEncoding::Utf8 | SourceEncoding::Utf8Bom | SourceEncoding::SyntheticUtf8 => {}
                SourceEncoding::IncompatibleOriginal => {
                    return Err(invalid(&format!(
                        "original source encoding lacks legacy semantic parity: {}",
                        entry.path.display()
                    )))
                }
            }
        }
        Ok(())
    }
    pub(crate) fn visit_storage(
        &self,
        mut buffer: impl FnMut(usize, usize),
        mut entry: impl FnMut(&Arc<PathBuf>, Option<&SourceAcquisitionLease>),
    ) {
        buffer(
            self.entries.as_ptr() as usize,
            std::mem::size_of_val(self.entries.as_ref()),
        );
        if let Err(error) = &self.compatibility {
            if error.capacity() > 0 {
                buffer(error.as_ptr() as usize, error.capacity());
            }
        }
        for value in &self.entries {
            entry(&value.path, value.acquisition.as_ref());
        }
    }
}
impl<P: SnapshotProvider> RecordingInputs<P> {
    pub(crate) fn semantic_source_evidence(
        &self,
        frontend: &ColdFrontend,
    ) -> io::Result<Arc<SemanticSourceEvidence>> {
        self.semantic_source_evidence_for_roster(frontend, &frontend.files)
    }
    #[cfg(test)]
    pub(crate) fn semantic_source_evidence_without_captured_roster(
        &self,
        frontend: &ColdFrontend,
    ) -> io::Result<Arc<SemanticSourceEvidence>> {
        self.semantic_source_evidence_for_roster(frontend, &[])
    }
    fn semantic_source_evidence_for_roster(
        &self,
        frontend: &ColdFrontend,
        files: &[dm_tree::frontend::SourceFile],
    ) -> io::Result<Arc<SemanticSourceEvidence>> {
        let mapping = frontend
            .source_export_mapping()
            .ok_or_else(|| invalid("semantic source mapping is not current compiler issuance"))?;
        self.semantic_source_evidence_parts(
            mapping,
            files,
            frontend
                .plan
                .occurrences()
                .iter()
                .enumerate()
                // Actual typed resources have no text/encoding lease. Keep
                // original occurrence indices for every real source binding.
                .filter(|(_,row)|row.non_text_kind().is_none())
                .map(|(index, row)| (index, &row.path)),
        )
    }
    pub(crate) fn diagnostic_source_evidence(
        &self,
        frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
    ) -> io::Result<Arc<SemanticSourceEvidence>> {
        if !frontend.receipt().authenticates(frontend.tree())
            || !frontend.archive().matches_tree(frontend.tree())
        {
            return Err(invalid("diagnostic evidence original graph differs"));
        }
        self.semantic_source_evidence_parts(
            frontend.mapping(),
            frontend.files(),
            frontend.semantic_includes(),
        )
    }
    fn semantic_source_evidence_parts<'a>(
        &self,
        mapping: &Arc<SourceExportMapping>,
        files: &[dm_tree::frontend::SourceFile],
        includes: impl Iterator<Item = (usize, &'a Arc<PathBuf>)>,
    ) -> io::Result<Arc<SemanticSourceEvidence>> {
        // Lookup only: this is the compiler's existing source roster, not a model.
        let sources: BTreeMap<_, _> = files
            .iter()
            .filter(|file| file.captured)
            .map(|file| (file.path.as_path(), &file.text))
            .collect();
        let mut entries = Vec::new();
        for (occurrence, path) in includes {
            let source = sources.get(path.as_path());
            let acquisition = mapping
                .source_acquisition(occurrence)
                .filter(|value| {
                    (self.mapped_recorded_source_fact(mapping,occurrence,path.as_ref()).is_ok()||self.validate_analysis_subject_lease(path.as_ref(),value))
                        && source.is_some_and(|source| value.source_text().same_view(source))
                })
                .cloned();
            entries.push(Entry {
                occurrence,
                path: Arc::clone(path),
                acquisition,
            });
        }
        let compatibility = SemanticSourceEvidence::evaluate_compatibility(mapping, &entries)
            .map_err(|error| error.to_string());
        static NEXT: AtomicU64 = AtomicU64::new(1);
        Ok(Arc::new(SemanticSourceEvidence {
            key: NEXT
                .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                    value.checked_add(1)
                })
                .map_err(|_| invalid("semantic source admission issuance exhausted"))?,
            mapping: Arc::downgrade(mapping),
            entries: entries.into_boxed_slice(),
            compatibility,
        }))
    }
}
