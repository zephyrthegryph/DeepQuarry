//! Complete source-only SYSTEM_ACCESSOR policy over original captured views.
//! Explicit captured-file coverage; no workspace discovery or generated-file install.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration},
    system_accessors_policy::{Builder, Output},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct CapturedSystemAccessors<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
}
fn admit(total: &mut usize, bytes: usize) -> Result<(), String> {
    *total = total
        .checked_add(bytes)
        .ok_or("system accessor accounting overflow")?;
    if *total > 64 * 1024 * 1024 {
        return Err("system accessor result budget exceeded before retention".into());
    }
    Ok(())
}
impl<'a> CapturedSystemAccessors<'a> {
    pub fn capture(
        root: &Path,
        archive: &dm_tree::frontend::BodyArchive,
        inputs: &'a PolicyInputs,
    ) -> Result<Self, String> {
        let order =
            crate::captured_sparse_slots::CapturedSparseSlots::capture(root, archive, inputs)?
                .include_order()?;
        let raw = CapturedRawPolicy::capture(root, inputs, Configuration::ProvenMissing)?;
        Ok(Self { raw, inputs, order })
    }
    fn intact(&self) -> Result<(), String> {
        match self.raw.tree.captured_violation() {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }
    pub fn generate(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Output, String> {
        checkpoint()?;
        self.intact()?;
        self.raw.validate_current_raw_roster(self.inputs)?;
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
        let mut retained = 0usize;
        let mut defs = HashSet::new();
        let mut markers = Vec::new();
        let mut requested: BTreeMap<String, BTreeMap<String, bool>> = BTreeMap::new();
        for f in &files {
            checkpoint()?;
            self.intact()?;
            // Instances are intentionally selected from raw, not comment-stripped text.
            crate::system_accessors_policy::visit_system_defs(f.raw().text.as_str(), |def| {
                admit(
                    &mut retained,
                    def.len()
                        .checked_mul(4)
                        .and_then(|n| n.checked_add(128))
                        .ok_or("system name overflow")?,
                )?;
                defs.insert(def.to_owned());
                Ok(())
            })?;
            let stripped = f.marker();
            self.intact()?;
            let mut offset = 0usize;
            for (ln, line) in stripped.as_str().split('\n').enumerate() {
                checkpoint()?;
                if let Some(m) = crate::raw_marker_policy::statement_marker(
                    stripped.as_str(),
                    offset,
                    line,
                    &["SYSTEM_ACCESSOR"],
                ) {
                    if markers.len() >= crate::captured_raw_policy::MAX_FIXTURE_SITES {
                        return Err("system accessor marker budget exceeded".into());
                    }
                    let row = (m.close - m.open)
                        .checked_mul(32)
                        .and_then(|n| n.checked_add(f.rel.len().saturating_mul(8)))
                        .and_then(|n| n.checked_add(4096))
                        .ok_or("system accessor row overflow")?;
                    admit(&mut retained, row)?;
                    let args = crate::raw_marker_policy::split_args(
                        &stripped.as_str()[m.open + 1..m.close],
                    );
                    if let (Some(system), Some(key)) = (args.first(), args.get(2)) {
                        if let Some(var) = key
                            .trim()
                            .strip_prefix("nameof(")
                            .and_then(|s| s.strip_suffix(')'))
                        {
                            requested
                                .entry(system.clone())
                                .or_default()
                                .entry(var.trim().to_string())
                                .or_insert(false);
                        }
                    }
                    markers.push((
                        f.rel.clone(),
                        u32::try_from(ln + 1).map_err(|_| "system accessor line overflow")?,
                        args,
                    ));
                }
                offset = offset
                    .checked_add(line.len() + 1)
                    .ok_or("system accessor offset overflow")?;
            }
            self.intact()?;
        }
        // Only the requested own-field membership is retained. The existing raw
        // matcher remains the sole declaration policy; no semantic model is copied.
        let names: Vec<String> = requested.keys().cloned().collect();
        let mut candidates: HashMap<String, Vec<usize>> = HashMap::new();
        for (i, name) in names.iter().enumerate() {
            for ty in crate::system_accessors_policy::system_types(name) {
                candidates.entry(ty).or_default().push(i);
            }
        }
        for f in &files {
            checkpoint()?;
            self.intact()?;
            if names.is_empty() {
                continue;
            }
            let code = f.code();
            self.intact()?;
            let selected: Vec<bool> = names
                .iter()
                .map(|name| crate::system_accessors_policy::file_mentions_system(&code.text, name))
                .collect();
            if !selected.iter().any(|x| *x) {
                continue;
            }
            let clean = f.clean();
            self.intact()?;
            crate::raw_type_vars_policy::visit(&clean.text, |ty, var| {
                if let Some(indices) = candidates.get(ty) {
                    for &i in indices {
                        if selected[i] {
                            if let Some(found) = requested
                                .get_mut(&names[i])
                                .and_then(|vars| vars.get_mut(var))
                            {
                                *found = true
                            }
                        }
                    }
                }
            });
            self.intact()?;
        }
        let mut builder = Builder::new(defs);
        for (rel, line, args) in markers {
            checkpoint()?;
            builder.push(&rel, line, &args, |system, var| {
                requested
                    .get(system)
                    .and_then(|vars| vars.get(var))
                    .copied()
                    .unwrap_or(false)
            });
        }
        checkpoint()?;
        self.intact()?;
        Ok(builder.finish())
    }
}
#[cfg(test)]
#[path = "captured_system_accessors_tests.rs"]
mod tests;
