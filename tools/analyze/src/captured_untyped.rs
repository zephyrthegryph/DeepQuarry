//! Analyze's existing full untyped policy over same-archive value proofs.
//! Source encoding and captured configuration are host admission obligations.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
    tree::CODE_DM,
    value_schema_policy::ValueKind,
};
use dm_analysis::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::Unsupported,
    value_program::Values,
    value_query::{ArchiveValueInput, ArchiveValueProof, ValueQueryFailure},
    value_schemas::{Kind, Schemas},
};
use dm_ir::SymbolId;
use std::{path::Path, sync::Arc};
/// Trusted host capture boundary, analogous to Configuration. This enum does
/// not self-prove filesystem reads/absence. The host binds exact root manifest
/// original bytes or recorded negative facts to this SAME policy revision.
pub enum ManifestRead<'a> {
    Compiled,
    /// Host authenticates these exact original bytes with its private acquisition receipt.
    CompiledOriginalBytes(&'a [u8]),
    OriginalBytes(&'a [u8]),
    ProvenUnavailable,
}
pub struct CapturedUntyped<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedUntyped<'a> {
    pub fn capture(
        root: &Path,
        inputs: &'a PolicyInputs,
        config: Configuration<'_>,
    ) -> Result<Self, String> {
        Ok(Self {
            raw: CapturedRawPolicy::capture(root, inputs, config)?,
            inputs,
        })
    }
    /// Value input/proof is issued by the SAME compiler QueryDb in production.
    /// This backend never computes a second whole-program value graph.
    pub fn scan(
        &self,
        input: &Arc<ArchiveValueInput>,
        proof: Arc<ArchiveValueProof>,
        manifest: ManifestRead<'_>,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        BorrowedUntyped::capture(&self.raw, self.inputs)?.scan(input, proof, manifest, checkpoint)
    }
}
// Report-relative spelling is sufficient to REFUSE an ambiguous candidate,
// never to certify provider-key identity or select its bytes. Actual Windows
// alias admission requires the host's private acquisition-alias receipt.
fn reject_unproven_manifest_alias<'a>(
    root: &Path,
    paths: impl IntoIterator<Item = &'a Path>,
) -> Result<(), String> {
    let expected = dm_preprocess::regions::canonical_path(&root.join("deepquarry.dme"));
    for path in paths {
        if dm_preprocess::regions::relative_filesystem_path(path, root).as_deref()
            == Some(Path::new("deepquarry.dme"))
            && dm_preprocess::regions::canonical_path(path) != expected
        {
            return Err("manifest provider-key alias needs a private acquisition receipt".into());
        }
    }
    Ok(())
}
trait FindingsDemand {
    type Failure: From<String> + From<&'static str>;
    fn refusal(e: Unsupported) -> Self::Failure;
    fn resource(e: String) -> Self::Failure;
    fn findings<'a>(
        archive: &'a dm_tree::frontend::BodyArchive,
        values: &Values<'a>,
        schemas: &Schemas,
        root: &Path,
        exempt_types: &'a [String],
        exempt: impl Fn(&str) -> bool,
        project: impl Fn(
            dm_analysis::untyped_native::PolicyAnchor,
            dm_tree::frontend::SourceLocation,
        ) -> Result<dm_tree::frontend::SourceLocation, Unsupported>,
    ) -> Result<Vec<dm_analysis::untyped_native::Finding>, Self::Failure>;
}
struct CompatibilityFindings;
impl FindingsDemand for CompatibilityFindings {
    type Failure = String;
    fn refusal(e: Unsupported) -> String {
        e.0
    }
    fn resource(e: String) -> String {
        e
    }
    fn findings<'a>(
        archive: &'a dm_tree::frontend::BodyArchive,
        values: &Values<'a>,
        schemas: &Schemas,
        root: &Path,
        exempt_types: &'a [String],
        exempt: impl Fn(&str) -> bool,
        project: impl Fn(
            dm_analysis::untyped_native::PolicyAnchor,
            dm_tree::frontend::SourceLocation,
        ) -> Result<dm_tree::frontend::SourceLocation, Unsupported>,
    ) -> Result<Vec<dm_analysis::untyped_native::Finding>, String> {
        dm_analysis::untyped_native::archived_findings_projected(
            archive,
            values,
            schemas,
            root,
            exempt_types,
            exempt,
            project,
        )
        .map_err(|e| e.0)
    }
}
struct CheckedFindings;
impl FindingsDemand for CheckedFindings {
    type Failure = ValueQueryFailure;
    fn refusal(e: Unsupported) -> ValueQueryFailure {
        ValueQueryFailure::Unsupported(e)
    }
    fn resource(e: String) -> ValueQueryFailure {
        ValueQueryFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory, e))
    }
    fn findings<'a>(
        archive: &'a dm_tree::frontend::BodyArchive,
        values: &Values<'a>,
        schemas: &Schemas,
        root: &Path,
        exempt_types: &'a [String],
        exempt: impl Fn(&str) -> bool,
        project: impl Fn(
            dm_analysis::untyped_native::PolicyAnchor,
            dm_tree::frontend::SourceLocation,
        ) -> Result<dm_tree::frontend::SourceLocation, Unsupported>,
    ) -> Result<Vec<dm_analysis::untyped_native::Finding>, ValueQueryFailure> {
        dm_analysis::untyped_native::archived_findings_projected_checked(
            archive,
            values,
            schemas,
            root,
            exempt_types,
            exempt,
            project,
        )
    }
}
pub struct BorrowedUntyped<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedUntyped<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(
        &self,
        input: &Arc<ArchiveValueInput>,
        proof: Arc<ArchiveValueProof>,
        manifest: ManifestRead<'_>,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        self.scan_with::<CompatibilityFindings>(input, proof, manifest, checkpoint)
    }
    pub fn scan_checked(
        &self,
        input: &Arc<ArchiveValueInput>,
        proof: Arc<ArchiveValueProof>,
        manifest: ManifestRead<'_>,
        mut checkpoint: impl FnMut() -> std::io::Result<()>,
    ) -> Result<RawRun, ValueQueryFailure> {
        let result = self.scan_with::<CheckedFindings>(input, proof, manifest, || {
            checkpoint().map_err(ValueQueryFailure::Operational)
        });
        // Preserve an already issued actual IO error. Shared view denial is
        // still operational when the inner path only produced semantic data.
        if matches!(&result, Err(ValueQueryFailure::Operational(_))) {
            return result;
        }
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(CheckedFindings::resource(error));
        }
        result
    }
    fn scan_with<D: FindingsDemand>(
        &self,
        input: &Arc<ArchiveValueInput>,
        proof: Arc<ArchiveValueProof>,
        manifest: ManifestRead<'_>,
        mut checkpoint: impl FnMut() -> Result<(), D::Failure>,
    ) -> Result<RawRun, D::Failure> {
        checkpoint()?;
        if !Arc::ptr_eq(input.archive(), self.inputs.archive()) {
            return Err("untyped value proof belongs to another archive".into());
        }
        let scope = self.raw.scopes.for_lint("untyped", "");
        let mut expected = scope.list("exempt_types").to_vec();
        expected.sort();
        expected.dedup();
        if input.exempt_types() != expected.as_slice() {
            return Err("untyped value proof uses another exemption policy".into());
        }
        let tree = self.inputs.archive().tree();
        tree.checker_builtin_profile()
            .ok_or("untyped native schemas need certified fixed builtin ancestry")?;
        let values = Values::from_archive_input(input, proof).map_err(D::refusal)?;
        let schemas = self.schemas(manifest, &mut checkpoint)?;
        let rows = D::findings(
            self.inputs.archive(),
            &values,
            &schemas,
            &self.raw.tree.root,
            input.exempt_types(),
            |file| scope.exempt(file),
            |anchor, mut source| {
                let file = self
                    .inputs
                    .file(&source.path)
                    .ok_or_else(|| Unsupported("untyped origin absent from capture".into()))?;
                if !file.is_compiled() || file.role() != PolicyRole::DmSource {
                    return Err(Unsupported("untyped origin not compiled source".into()));
                }
                match anchor {
                    dm_analysis::untyped_native::PolicyAnchor::Assignment(at) => {
                        let exact = self
                            .inputs
                            .archive()
                            .original_policy_line(at.start)
                            .map_err(|error| {
                                Unsupported(format!(
                                    "untyped assignment {}:{} native@{}: {error}",
                                    source.path.display(),
                                    source.line,
                                    at.start
                                ))
                            })?;
                        if exact.path != source.path {
                            return Err(Unsupported(
                                "assignment policy point belongs to another file".into(),
                            ));
                        }
                        source.line = file
                            .analyze_display_line(exact.line)
                            .map_err(|e| Unsupported(e.to_string()))?;
                    }
                    dm_analysis::untyped_native::PolicyAnchor::Declaration(member) => {
                        let exact = self
                            .inputs
                            .archive()
                            .member_policy_compatibility_cursor(member)
                            .map_err(Unsupported)?;
                        // The original member's compiled raw capture was checked
                        // above. A planner-issued diagnostic boundary can belong
                        // to its parent manifest, which the original policy then
                        // naturally omits through its existing code/ selection.
                        source.path = exact.path;
                        source.line = if exact.logical_boundary {
                            exact.line
                        } else {
                            let target = self.inputs.file(&source.path).ok_or_else(|| {
                                Unsupported("declaration target source absent from capture".into())
                            })?;
                            target
                                .analyze_display_line(exact.line)
                                .map_err(|e| Unsupported(e.to_string()))?
                        };
                    }
                }
                // Legacy untyped applies engine_line both to declaration Sites
                // and to assignment locations embedded in their messages.
                Ok(source)
            },
        )?;
        checkpoint()?;
        if rows.len() > MAX_FIXTURE_SITES {
            return Err("untyped exceeds fixture finding admission".into());
        }
        let mut sink = Sink::new();
        // Original lint accepts no ALLOW annotations and has no per-site keeps.
        for row in rows {
            sink.site_decl(
                row.rule.name(),
                &row.file,
                row.line,
                row.message,
                row.identity,
            );
        }
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(D::resource(error));
        }
        Ok(RawRun {
            name: "untyped".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
    fn schemas<E: From<String> + From<&'static str>>(
        &self,
        manifest: ManifestRead<'_>,
        checkpoint: &mut impl FnMut() -> Result<(), E>,
    ) -> Result<Schemas, E> {
        // Decls orders markers by deepquarry.dme includes; schema kind precedence
        // is all SCHEMA markers, then all TRACKED_SCHEMA markers. Raw hint-only
        // presence sets cannot substitute for this ordered kind contract.
        let manifest_path = self.raw.tree.root.join("deepquarry.dme");
        reject_unproven_manifest_alias(
            &self.raw.tree.root,
            self.inputs
                .files()
                .map(|file| file.path().as_ref().as_path()),
        )?;
        reject_unproven_manifest_alias(
            &self.raw.tree.root,
            self.inputs
                .mapping()
                .source_acquisitions()
                .map(|(path, _)| path),
        )?;
        let positive_compiled_manifest =
            self.inputs
                .mapping()
                .source_acquisitions()
                .any(|(path, _)| {
                    dm_preprocess::regions::canonical_path(path)
                        == dm_preprocess::regions::canonical_path(&manifest_path)
                });
        let order = match manifest {
            ManifestRead::CompiledOriginalBytes(bytes) => {
                if !positive_compiled_manifest {
                    return Err("original compiled manifest receipt has no compiled member".into());
                }
                // Original UTF8/BOM is not reconstructed from stripped SourceText.
                // The private host receipt authenticates bytes; this cross-check
                // keeps a malformed facade caller from mixing another manifest.
                for (path, lease) in self.inputs.mapping().source_acquisitions() {
                    if dm_preprocess::regions::canonical_path(path)
                        != dm_preprocess::regions::canonical_path(&manifest_path)
                    {
                        continue;
                    }
                    let lease = lease.ok_or("manifest original acquisition unknown")?;
                    let expected = match lease.encoding() {
                        dm_preprocess::SourceEncoding::Utf8 => bytes,
                        dm_preprocess::SourceEncoding::Utf8Bom => bytes
                            .strip_prefix(b"\xef\xbb\xbf")
                            .ok_or("manifest BOM receipt contradicts original")?,
                        _ => return Err("manifest original is not certified UTF8".into()),
                    };
                    if expected != lease.source_text().as_bytes() {
                        return Err("manifest receipt contradicts source acquisition".into());
                    }
                }
                std::str::from_utf8(bytes)
                    .map(crate::raw_marker_policy::dme_include_order)
                    .unwrap_or_default()
            }
            ManifestRead::OriginalBytes(bytes) => {
                if positive_compiled_manifest
                    || self
                        .inputs
                        .file(&manifest_path)
                        .is_some_and(|file| file.is_compiled())
                {
                    return Err("compiled manifest must use its issued original acquisition".into());
                }
                // Exact old read_to_string behavior: invalid UTF8 was an IO
                // failure and supplied no include order, not lossy replacement.
                std::str::from_utf8(bytes)
                    .map(crate::raw_marker_policy::dme_include_order)
                    .unwrap_or_default()
            }
            ManifestRead::ProvenUnavailable => {
                if positive_compiled_manifest || self.inputs.file(&manifest_path).is_some() {
                    return Err("positive manifest capture contradicts unavailable proof".into());
                }
                std::collections::HashMap::new()
            }
            ManifestRead::Compiled => {
                let mut selected: Option<(&dm_preprocess::SourceText, bool)> = None;
                for (path, lease) in self.inputs.mapping().source_acquisitions() {
                    if dm_preprocess::regions::canonical_path(path)
                        != dm_preprocess::regions::canonical_path(&manifest_path)
                    {
                        continue;
                    }
                    let lease = lease.ok_or("manifest original acquisition is unknown")?;
                    let bom = match lease.encoding() {
                        dm_preprocess::SourceEncoding::Utf8 => false,
                        dm_preprocess::SourceEncoding::Utf8Bom => true,
                        _ => {
                            return Err("manifest original bytes are not proven strict UTF8".into())
                        }
                    };
                    if let Some((prior, prior_bom)) = selected {
                        if prior.as_bytes() != lease.source_text().as_bytes() || prior_bom != bom {
                            return Err("compiled manifest acquisitions contradict".into());
                        }
                    }
                    selected = Some((lease.source_text(), bom));
                }
                let (text,bom)=selected.ok_or("root/deepquarry.dme is not an acquired compiler input; explicit captured bytes/negative proof required")?;
                crate::raw_marker_policy::dme_include_order_view(text, bom)
            }
        };
        let mut files = self.raw.tree.select(&CODE_DM);
        files.sort_by(|a, b| {
            (
                order.get(&a.rel).copied().unwrap_or(usize::MAX),
                a.rel.as_str(),
            )
                .cmp(&(
                    order.get(&b.rel).copied().unwrap_or(usize::MAX),
                    b.rel.as_str(),
                ))
        });
        let mut schemas = Schemas::default();
        for name in ["SCHEMA", "TRACKED_SCHEMA"] {
            for file in &files {
                checkpoint()?;
                let text = file.marker().as_str();
                let mut offset = 0;
                for line in text.split('\n') {
                    if let Some(marker) =
                        crate::raw_marker_policy::statement_marker(text, offset, line, &[name])
                    {
                        let args = crate::raw_marker_policy::split_args(
                            &text[marker.open + 1..marker.close],
                        );
                        if let [owner, var, value, ..] = args.as_slice() {
                            if let Some(kind) = crate::value_schema_policy::kind_of(value) {
                                let kind = match kind {
                                    ValueKind::Path(path) => Kind::Path(path),
                                    ValueKind::Msg => Kind::Msg,
                                    ValueKind::Plain => Kind::Plain,
                                    ValueKind::Many => Kind::Many,
                                    ValueKind::Any => Kind::Any,
                                };
                                schemas.insert_policy_kind(
                                    SymbolId::of(owner.trim()),
                                    SymbolId::of(var.trim()),
                                    kind,
                                );
                            }
                        }
                    }
                    offset += line.len() + 1;
                }
            }
        }
        Ok(schemas)
    }
}

#[cfg(test)]
#[path = "captured_untyped_tests.rs"]
mod tests;
