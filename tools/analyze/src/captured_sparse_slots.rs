//! Whole sparse_slots policy over borrowed original-owner captured raw sources.
//! This does not certify workspace discovery or install generated files.
use crate::sparse_slots_policy::{Builder, Output};
use dm_analysis::policy_inputs::{PolicyInputs, PolicyRole, TextView};
use std::{collections::HashMap, path::Path};
pub const GENERATOR: &str = "sparse_slots";
pub const OUTPUT: &str = "code/engine/_generated/sparse_slots.dm";
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct CapturedSparseSlots<'a> {
    root: &'a Path,
    inputs: &'a PolicyInputs,
    _archive: &'a dm_tree::frontend::BodyArchive,
}
impl<'a> CapturedSparseSlots<'a> {
    pub fn capture(
        root: &'a Path,
        archive: &'a dm_tree::frontend::BodyArchive,
        inputs: &'a PolicyInputs,
    ) -> Result<Self, String> {
        if !root.is_absolute() {
            return Err("generator root must be absolute".into());
        }
        if !inputs.matches_archive(archive) {
            return Err("generator policy capture belongs to another original archive".into());
        }
        Ok(Self {
            root,
            inputs,
            _archive: archive,
        })
    }
    pub(crate) fn include_order(&self) -> Result<HashMap<String, usize>, String> {
        let path = self.root.join("deepquarry.dme");
        let mut chosen = None;
        for (actual, lease) in self.inputs.mapping().source_acquisitions() {
            if dm_preprocess::regions::canonical_path(actual)
                != dm_preprocess::regions::canonical_path(&path)
            {
                continue;
            }
            let lease = lease.ok_or("generator manifest original acquisition unproven")?;
            let bom = match lease.encoding() {
                dm_preprocess::SourceEncoding::Utf8 => false,
                dm_preprocess::SourceEncoding::Utf8Bom => true,
                _ => return Err("generator manifest needs issued original strict UTF8".into()),
            };
            if let Some((previous, old_bom)) = chosen {
                if previous != lease.source_text().as_str() || old_bom != bom {
                    return Err("generator manifest acquisitions contradict".into());
                }
            }
            chosen = Some((lease.source_text().as_str(), bom));
        }
        let (text, bom) =
            chosen.ok_or("generator root manifest is not an acquired compiler input")?;
        Ok(crate::raw_marker_policy::dme_include_order_view(text, bom))
    }
    pub fn generate(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Output, String> {
        checkpoint()?;
        let order = self.include_order()?;
        let mut files: Vec<(String, &dm_preprocess::SourceText)> = Vec::new();
        let mut total = 0usize;
        let mut retained_admission = 0usize;
        for file in self
            .inputs
            .files()
            .filter(|f| f.role() == PolicyRole::DmSource)
        {
            checkpoint()?;
            let rel = dm_preprocess::regions::relative_filesystem_path(file.path(), self.root)
                .ok_or("generator source outside root")?
                .to_string_lossy()
                .replace('\\', "/");
            if !rel.starts_with("code/")
                || !rel.ends_with(".dm")
                || rel.split('/').any(|p| p.starts_with('.'))
            {
                continue;
            }
            let text = file
                .view(TextView::AnalyzeRaw)
                .map_err(|_| "generator needs original captured AnalyzeRaw view")?;
            if text.len() > crate::captured_raw_policy::MAX_FIXTURE_FILE_BYTES {
                return Err("generator per-file captured scope budget exceeded".into());
            }
            total = total
                .checked_add(text.len())
                .ok_or("generator source size overflow")?;
            if total > crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES {
                return Err("generator explicit captured scope budget exceeded".into());
            }
            if files.iter().any(|(name, _)| name == &rel) {
                return Err("generator provider keys collide in report path".into());
            }
            if files.len() >= crate::captured_raw_policy::MAX_FIXTURE_SITES {
                return Err("generator file count exceeds explicit captured scope budget".into());
            }
            retained_admission = retained_admission
                .checked_add(
                    rel.len()
                        .checked_mul(4)
                        .and_then(|n| n.checked_add(256))
                        .ok_or("generator path accounting overflow")?,
                )
                .ok_or("generator metadata accounting overflow")?;
            if retained_admission > 64 * 1024 * 1024 {
                return Err("generator metadata budget exceeded before allocation".into());
            }
            files.push((rel, text));
        }
        files.sort_by(|a, b| {
            (order.get(&a.0).copied().unwrap_or(usize::MAX), &a.0)
                .cmp(&(order.get(&b.0).copied().unwrap_or(usize::MAX), &b.0))
        });
        let mut builder = Builder::default();
        let mut count = 0usize;
        for (rel, text) in files {
            checkpoint()?;
            // Same source-view + statement-marker policy as Decls::scan_file. No AST,
            // semantic table or SourceFile facade is reconstructed here.
            let stripped = crate::raw_marker_policy::strip_comments_keep_strings(text.as_str());
            let mut offset = 0;
            for (ln, line) in stripped.split('\n').enumerate() {
                checkpoint()?;
                if let Some(marker) =
                    crate::raw_marker_policy::statement_marker(&stripped, offset, line, &["sparse"])
                {
                    count += 1;
                    if count > crate::captured_raw_policy::MAX_FIXTURE_SITES {
                        return Err("generator marker count exceeds captured scope budget".into());
                    }
                    // Pre-admit the row/argument/diagnostic + final output worst-case before
                    // retaining them. Deeply nested multiline markers can otherwise repeat
                    // most of a file at every line, despite a bounded input-file length.
                    let bytes = marker.close - marker.open;
                    retained_admission = retained_admission
                        .checked_add(
                            bytes
                                .checked_mul(16)
                                .and_then(|n| n.checked_add(rel.len().saturating_mul(8)))
                                .and_then(|n| n.checked_add(2048))
                                .ok_or("generator row accounting overflow")?,
                        )
                        .ok_or("generator result accounting overflow")?;
                    if retained_admission > 64 * 1024 * 1024 {
                        return Err("generator result budget exceeded before row retention".into());
                    }
                    let args = crate::raw_marker_policy::split_args(
                        &stripped[marker.open + 1..marker.close],
                    );
                    builder.push(
                        &rel,
                        u32::try_from(ln + 1).map_err(|_| "generator line overflow")?,
                        &args,
                    );
                }
                offset = offset
                    .checked_add(line.len() + 1)
                    .ok_or("generator offset overflow")?;
            }
        }
        checkpoint()?;
        Ok(builder.finish())
    }
}
#[cfg(test)]
#[path = "captured_sparse_slots_tests.rs"]
mod tests;

/// Existing RAW_FILE lazies, borrowed under the caller's current family gate.
/// No generated file installation or implicit source capture occurs here.
pub struct BorrowedSparseSlots<'a> {
    raw: &'a crate::captured_raw_policy::CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
    budget: std::sync::Arc<crate::captured_generator_budget::Budget>,
}
fn current_violation(raw: &crate::captured_raw_policy::CapturedRawPolicy) -> Result<(), String> {
    match raw.tree.captured_violation() {
        Some(e) => Err(e),
        None => Ok(()),
    }
}
pub(crate) fn captured_order(
    raw: &crate::captured_raw_policy::CapturedRawPolicy,
    inputs: &PolicyInputs,
    budget: &crate::captured_generator_budget::Budget,
) -> Result<HashMap<String, usize>, String> {
    raw.validate_current_raw_roster(inputs)?;
    current_violation(raw)?;
    original_order(&raw.tree.root,inputs,budget)
}
/// Same original manifest/include policy, independent of bounded raw roster.
pub(crate) fn original_order(root:&std::path::Path,inputs:&PolicyInputs,budget:&crate::captured_generator_budget::Budget)->Result<HashMap<String,usize>,String>{
    let metadata = inputs
        .mapping()
        .source_acquisitions()
        .try_fold(
            root
                .as_os_str()
                .as_encoded_bytes()
                .len()
                .saturating_mul(16)
                .saturating_add(4096),
            |sum, (path, _)| {
                sum.checked_add(
                    path.as_os_str()
                        .as_encoded_bytes()
                        .len()
                        .saturating_mul(16)
                        .saturating_add(256),
                )
            },
        )
        .ok_or("generator manifest metadata overflow")?;
    budget.charge(metadata)?;
    let original = CapturedSparseSlots::capture(root, inputs.archive(), inputs)?;
    let mut width = 0usize;
    for (path, lease) in inputs.mapping().source_acquisitions() {
        if dm_preprocess::regions::canonical_path(path)
            == dm_preprocess::regions::canonical_path(&root.join("deepquarry.dme"))
        {
            width = width.max(
                lease
                    .ok_or("generator manifest original unissued")?
                    .source_text()
                    .len(),
            )
        }
    }
    budget.charge(
        width
            .checked_mul(64)
            .and_then(|n| n.checked_add(4096))
            .ok_or("generator manifest admission overflow")?,
    )?;
    original.include_order()
}
impl<'a> BorrowedSparseSlots<'a> {
    pub fn capture(
        raw: &'a crate::captured_raw_policy::CapturedRawPolicy,
        inputs: &'a PolicyInputs,
        budget: std::sync::Arc<crate::captured_generator_budget::Budget>,
    ) -> Result<Self, String> {
        let order = captured_order(raw, inputs, &budget)?;
        Ok(Self {
            raw,
            inputs,
            order,
            budget,
        })
    }
    pub fn generate(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Output, String> {
        checkpoint()?;
        self.budget.require()?;
        self.raw.validate_current_raw_roster(self.inputs)?;
        self.budget.charge(
            self.raw
                .tree
                .files
                .len()
                .saturating_mul(256)
                .saturating_add(4096),
        )?;
        let mut files = self.raw.tree.select(&crate::tree::CODE_DM);
        files.sort_by(|a, b| {
            (
                self.order.get(&a.rel).copied().unwrap_or(usize::MAX),
                &a.rel,
            )
                .cmp(&(
                    self.order.get(&b.rel).copied().unwrap_or(usize::MAX),
                    &b.rel,
                ))
        });
        let mut builder = Builder::captured(self.budget.clone());
        let mut count = 0;
        for file in files {
            checkpoint()?;
            current_violation(self.raw)?;
            self.budget.require()?;
            let marker = file.marker();
            current_violation(self.raw)?;
            let mut offset = 0usize;
            for (ln, line) in marker.as_str().split('\n').enumerate() {
                checkpoint()?;
                self.budget.require()?;
                if let Some(row) = crate::raw_marker_policy::statement_marker(
                    marker.as_str(),
                    offset,
                    line,
                    &["sparse"],
                ) {
                    count += 1;
                    if count > crate::captured_raw_policy::MAX_FIXTURE_SITES {
                        return Err("generator marker count exceeds captured scope budget".into());
                    }
                    self.budget.charge(
                        (row.close - row.open)
                            .checked_mul(16)
                            .and_then(|n| n.checked_add(file.rel.len().saturating_mul(8)))
                            .and_then(|n| n.checked_add(2048))
                            .ok_or("generator row admission overflow")?,
                    )?;
                    self.budget.split_args(row.close - row.open)?;
                    let args = crate::raw_marker_policy::split_args(
                        &marker.as_str()[row.open + 1..row.close],
                    );
                    builder.push(
                        &file.rel,
                        u32::try_from(ln + 1).map_err(|_| "generator line overflow")?,
                        &args,
                    );
                    self.budget.require()?;
                }
                offset = offset
                    .checked_add(line.len() + 1)
                    .ok_or("generator offset overflow")?;
            }
            current_violation(self.raw)?;
        }
        checkpoint()?;
        self.budget.require()?;
        let out = builder.finish();
        self.budget.require()?;
        current_violation(self.raw)?;
        checkpoint()?;
        Ok(out)
    }
}
