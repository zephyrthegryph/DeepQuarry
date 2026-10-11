//! Native observed resource-demand coverage through the existing capture producer.
//! This is not BYOND access completeness, implicit-profile admission, physical
//! path containment, or a complete map/skin container-source receipt.
use crate::frozen_inputs::{JournalAccessView, JournalFileAccess};
use dm_resources::capture::{CaptureConfig, CaptureProvider, CapturedResources, ResourceDemand};
use dm_resources::SharedBytes;
use dm_preprocess::regions::{canonical_path, relative_filesystem_path};
use std::{cell::Cell, collections::{BTreeMap, BTreeSet}, io, path::Path};

#[derive(Clone, Copy)]
pub struct CoverageLimits {
    pub candidate_reads: usize,
    pub source_payload_bytes: usize,
}
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ObservedResourceCoverage {
    pub candidate_reads: usize,
    pub source_payload_bytes: usize,
    pub resource_aliases: usize,
}
fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}
struct JournalProvider<'a, 'journal> {
    root: &'a Path,
    files: BTreeMap<&'a Path, JournalFileAccess<'a>>,
    folders: BTreeMap<&'a Path, &'a crate::input_snapshot::FolderListing>,
    negative: BTreeSet<&'a Path>,
    reads: Cell<usize>,
    bytes: Cell<usize>,
    limits: CoverageLimits,
    physical: Option<&'a JournalAccessView<'journal>>,
    root_identity: Cell<Option<u128>>,
}
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ResourceJournalAdmission {
    pub schema_version: u32,
    pub physical_observed_demand_admitted: bool,
    pub shared_input_closure_complete: bool,
    pub coverage: Option<ObservedResourceCoverage>,
    pub decline_reason: Option<String>,
}
/// Called with the production capture's exact current demand/encoding receipts.
/// Missing/unsupported physical evidence declines this optional admission only;
/// ordinary fresh compilation and observed-only analysis remain available.
pub fn admit_recorded_demand(
    inputs: &crate::frozen_inputs::Inputs, demand: &ResourceDemand,
    captured: &CapturedResources, config: CaptureConfig<'_>, limits: CoverageLimits,
) -> ResourceJournalAdmission {
    let result = inputs.with_access_view(|journal|
        validate_physically_contained_demand(demand.clone(), captured, config, &journal, limits));
    let (coverage, decline_reason) = match result {
        Ok(Some(coverage)) => (Some(coverage), None),
        Ok(None) => (None, Some("provider has no recorded journal authority".into())),
        Err(error) => (None, Some(error.to_string())),
    };
    ResourceJournalAdmission { schema_version: 1,
        physical_observed_demand_admitted: coverage.is_some(),
        shared_input_closure_complete: false, coverage, decline_reason }
}
impl CaptureProvider for JournalProvider<'_, '_> {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<SharedBytes>> {
        if relative_filesystem_path(path, self.root).is_none() {
            return Err(io::Error::new(io::ErrorKind::Unsupported, "resource candidate escapes supported project root"));
        }
        let reads = self.reads.get().checked_add(1).ok_or_else(|| invalid("resource coverage read overflow"))?;
        if reads > self.limits.candidate_reads { return Err(invalid("resource coverage read budget exceeded")); }
        self.reads.set(reads);
        let path = canonical_path(path);
        let parent = path.parent().ok_or_else(|| invalid("resource candidate has no parent"))?;
        if let Some(journal) = self.physical {
            for observed in [path.as_path(), parent] {
                let identity = journal.physical_root_identity(observed, self.root)?;
                if self.root_identity.get().is_some_and(|previous| previous != identity) {
                    return Err(invalid("resource journal root identity changed during capture"));
                }
                self.root_identity.set(Some(identity));
            }
        }
        let listing = self.folders.get(parent)
            .ok_or_else(|| invalid("resource candidate search-folder roster is not observed"))?;
        if let crate::input_snapshot::FolderListing::Present(names) = listing {
            if names.windows(2).any(|pair| pair[0] >= pair[1]) {
                return Err(invalid("resource search folder roster is not canonical"));
            }
        }
        if let Some(file) = self.files.get(path.as_path()) {
            if matches!(listing, crate::input_snapshot::FolderListing::Missing) {
                return Err(invalid("resource file contradicts missing search folder"));
            }
            let name = path.file_name().and_then(|name| name.to_str())
                .ok_or_else(|| invalid("resource candidate name is not Unicode"))?;
            if let crate::input_snapshot::FolderListing::Present(names) = listing {
                if !names.iter().any(|entry| {
                    if cfg!(windows) { entry.eq_ignore_ascii_case(name) } else { entry == name }
                }) {
                    return Err(invalid("resource file contradicts search folder membership"));
                }
            }
            let size = usize::try_from(file.stamp.size).map_err(|_| invalid("resource payload exceeds address space"))?;
            let bytes = self.bytes.get().checked_add(size).ok_or_else(|| invalid("resource coverage byte overflow"))?;
            if bytes > self.limits.source_payload_bytes { return Err(invalid("resource coverage payload budget exceeded")); }
            self.bytes.set(bytes);
            let (_, payload, _) = file.read_verified()?.into_parts();
            return Ok(Some(SharedBytes::from(payload)));
        }
        if self.negative.contains(path.as_path()) { return Ok(None); }
        Err(invalid(format!("resource candidate is not observed in journal: {}", path.display())))
    }
}
/// Reproduce only the current finite resource demand against recorded bytes and
/// negative probes using the SAME ordered capture/encoding admission producer.
/// No live filesystem or second search scanner is consulted. Payload allocation
/// is bounded by caller limits and released when validation returns.
/// CaptureConfig must be the current real encoding receipts/policy; this method
/// does not upgrade an arbitrary raw policy into BYOND profile authority.
pub fn validate_observed_demand(
    demand: ResourceDemand,
    captured: &CapturedResources,
    config: CaptureConfig<'_>,
    journal: &JournalAccessView<'_>,
    limits: CoverageLimits,
) -> io::Result<ObservedResourceCoverage> {
    validate_demand(demand, captured, config, journal, limits, false)
}
/// Strict capture-time physical containment, in addition to observed demand.
/// Requires held no-reparse ancestor evidence for every consumed candidate and
/// folder. Old journals and unsupported platform issuers explicitly decline.
/// This still does not certify BYOND's complete input/configuration closure.
pub fn validate_physically_contained_demand(
    demand: ResourceDemand, captured: &CapturedResources, config: CaptureConfig<'_>,
    journal: &JournalAccessView<'_>, limits: CoverageLimits,
) -> io::Result<ObservedResourceCoverage> {
    validate_demand(demand, captured, config, journal, limits, true)
}
fn validate_demand(
    demand: ResourceDemand, captured: &CapturedResources, config: CaptureConfig<'_>,
    journal: &JournalAccessView<'_>, limits: CoverageLimits, physical: bool,
) -> io::Result<ObservedResourceCoverage> {
    captured.require_complete()?;
    if demand.search_roots().any(|path| relative_filesystem_path(path, demand.project_root()).is_none()) {
        return Err(io::Error::new(io::ErrorKind::Unsupported, "resource search root escapes supported project root"));
    }
    let root = demand.project_root().to_owned();
    let root_identity = if physical { Some(journal.physical_root_identity(&root, &root)?) } else { None };
    let provider = JournalProvider {
        root: &root,
        files: journal.files().map(|file| (file.path, file)).collect(),
        negative: journal.negative_paths().collect(),
        folders: journal.folders().collect(),
        reads: Cell::new(0), bytes: Cell::new(0), limits,
        physical: physical.then_some(journal), root_identity: Cell::new(root_identity),
    };
    let current = dm_resources::capture::capture_discovered(demand, config, &provider)
        .map_err(|error| invalid(format!("resource journal coverage declined: {error:?}")))?;
    current.require_complete()?;
    if current.context.bytes() != captured.context.bytes()
        || current.literals != captured.literals
        || current.source_literal_count != captured.source_literal_count
        || current.lookups != captured.lookups
        || current.observations != captured.observations
        || current.resources.inputs != captured.resources.inputs
        || current.resources.fingerprint != captured.resources.fingerprint
    { return Err(invalid("current journal resource capture differs from issued captured resources")); }
    Ok(ObservedResourceCoverage { candidate_reads: provider.reads.get(),
        source_payload_bytes: provider.bytes.get(), resource_aliases: current.resources.inputs.len() })
}
#[cfg(test)]
#[path = "resource_journal_coverage/tests.rs"]
mod tests;
