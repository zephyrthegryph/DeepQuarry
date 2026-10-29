//! Complete base_vars/hot_home rule, not the complete base_vars lint.
//! Borrows issued declaration/source owners. No fallback model, raw declaration
//! parser, filesystem discovery, semantic clone, or mutable source read runs.
use crate::{
    base_var_hot_policy::{homes_in, hot_problems, BASE_TYPES, HOT_TABLE, SCOPES_FILE},
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
    tree::Select,
};
use dm_analysis::{
    base_var_declarations::{base_var_declarations, BaseVarDeclaration},
    policy_inputs::{PolicyInputs, PolicyRole, TextView},
};
use std::{borrow::Cow, collections::HashSet, path::Path};

/// A view of one issued variable; declaration metadata and initializer tokens
/// stay borrowed from their compiler owner. Only report coordinates are added.
pub struct NativeBaseVar<'a> {
    pub native: BaseVarDeclaration<'a>,
    pub relative: Cow<'a, str>,
    pub owner: &'a str,
    pub name: &'a str,
    pub line: u32,
}
pub struct NativeBaseVarFacts<'a> {
    policy: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> NativeBaseVarFacts<'a> {
    pub fn capture(
        policy: &'a CapturedRawPolicy,
        inputs: &'a PolicyInputs,
    ) -> Result<Self, String> {
        let mut files = 0;
        for captured in inputs
            .files()
            .filter(|file| file.role() == PolicyRole::DmSource)
        {
            let rel = dm_preprocess::regions::relative_filesystem_path(
                captured.path().as_ref(),
                &policy.tree.root,
            )
            .ok_or("base-var capture lies outside raw policy root")?
            .to_string_lossy()
            .replace('\\', "/");
            let source = policy
                .tree
                .get(&rel)
                .ok_or("base-var capture roster differs from raw policy")?;
            if !source.raw().text.same_view(
                captured
                    .view(TextView::AnalyzeRaw)
                    .map_err(|e| e.to_string())?,
            ) {
                return Err("base-var facts belong to another raw policy capture".into());
            }
            files += 1;
        }
        if files != policy.tree.files.len() {
            return Err("base-var raw policy has foreign source members".into());
        }
        Ok(Self { policy, inputs })
    }
    pub fn declarations(&self, base_types: &[&str]) -> Result<Vec<NativeBaseVar<'a>>, String> {
        let policy: &'a CapturedRawPolicy = self.policy;
        let inputs: &'a PolicyInputs = self.inputs;
        let archive = inputs.archive();
        let tree = archive.tree();
        let mut result = Vec::new();
        for native in
            base_var_declarations(archive, base_types, &policy.tree.root).map_err(|e| e.0)?
        {
            // Preserve original source authority and provenance. A diagnostic
            // include-return cursor is an independent projection, not another
            // compiled source or a replacement of native.source.
            let original = inputs
                .file(native.source.path.as_path())
                .ok_or("base-var declaration origin has no captured policy source")?;
            if !original.is_compiled() {
                return Err("base-var declaration is not an issued compiled source".into());
            }
            let original_rel = dm_preprocess::regions::relative_filesystem_path(
                native.source.path.as_path(),
                &policy.tree.root,
            )
            .ok_or("base-var declaration lies outside policy root")?
            .to_string_lossy()
            .replace('\\', "/");
            let original_raw = policy
                .tree
                .get(&original_rel)
                .ok_or("base-var declaration lacks captured raw source")?;
            if !original_raw.raw().text.same_view(
                original
                    .view(TextView::AnalyzeRaw)
                    .map_err(|e| e.to_string())?,
            ) {
                return Err("base-var raw source owner belongs to another policy capture".into());
            }
            let cursor = archive
                .member_policy_compatibility_cursor(native.declaration)
                .map_err(|error| {
                    format!(
                        "base-var cursor {}::{} original {}:{}: {error}",
                        tree.symbols().text(native.owner).unwrap_or("<unknown>"),
                        tree.symbols().text(native.name).unwrap_or("<unknown>"),
                        native.source.path.display(),
                        native.source.line
                    )
                })?;
            let relative = dm_preprocess::regions::relative_filesystem_path(
                cursor.path.as_path(),
                &policy.tree.root,
            )
            .ok_or("base-var policy cursor lies outside root")?
            .to_string_lossy()
            .replace('\\', "/");
            let (relative, line) = if relative.starts_with("code/") {
                let captured = inputs
                    .file(cursor.path.as_path())
                    .ok_or("base-var code cursor lacks captured policy source")?;
                if !captured.is_compiled() {
                    return Err("base-var code cursor is not compiled source".into());
                }
                let source = policy
                    .tree
                    .get(&relative)
                    .ok_or("base-var code cursor lacks captured raw source")?;
                if !source.raw().text.same_view(
                    captured
                        .view(TextView::AnalyzeRaw)
                        .map_err(|e| e.to_string())?,
                ) {
                    return Err("base-var code cursor has a foreign raw source".into());
                }
                // engine_line is applied even to a certified logical EOF. It
                // accepts an actual trailing-LF line head beyond raw.num_lines.
                let line = captured
                    .analyze_display_line(cursor.line)
                    .map_err(|e| e.to_string())?;
                if line == 0 || (!cursor.logical_boundary && line > source.raw().num_lines()) {
                    return Err("base-var code cursor line cannot be projected".into());
                }
                (Cow::Borrowed(source.rel.as_str()), line)
            } else {
                // The old typed_vars keeps this row for hot_home's declared
                // set, then the original by_rel code-file selector omits it.
                // The current mapping issued this target and EOF progression;
                // no raw DME payload/read or fabricated HostCapture is needed.
                (Cow::Owned(relative), cursor.line)
            };
            let owner = tree
                .symbols()
                .text(native.owner)
                .ok_or("base-var owner spelling is unavailable")?;
            let name = tree
                .symbols()
                .text(native.name)
                .ok_or("base-var member spelling is unavailable")?;
            result.push(NativeBaseVar {
                native,
                relative,
                owner,
                name,
                line: u32::try_from(line).map_err(|_| "base-var line overflow")?,
            });
        }
        result.sort_by(|a, b| {
            (a.relative.as_ref(), a.line, a.owner).cmp(&(b.relative.as_ref(), b.line, b.owner))
        });
        Ok(result)
    }
}
pub struct CapturedBaseVarHotPolicy<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedBaseVarHotPolicy<'a> {
    pub fn capture(
        root: &Path,
        inputs: &'a PolicyInputs,
        configuration: Configuration<'_>,
    ) -> Result<Self, String> {
        Ok(Self {
            raw: CapturedRawPolicy::capture(root, inputs, configuration)?,
            inputs,
        })
    }
    pub fn scan(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        checkpoint()?;
        let scope = self.raw.scopes.for_lint("base_vars", "");
        let hot = scope.table(HOT_TABLE).cloned().unwrap_or_default();
        let mut sink = Sink::new();
        sink.note(format!(
            "base_vars: {} hot base vars homed by base_var_home_hot",
            hot.len()
        ));
        let mut homes = HashSet::new();
        // Exactly cx.all_files: hidden-inclusive code/*.dm, no path exemption.
        let select = Select {
            roots: &[("code", "dm")],
            hidden: true,
        };
        for file in self.raw.tree.select(&select) {
            checkpoint()?;
            homes.extend(homes_in(
                file.code().text.as_str(),
                scope.list("base_var_home_macros"),
                scope.list("base_var_home_relations"),
            ));
        }
        let facts = NativeBaseVarFacts::capture(&self.raw, self.inputs)?;
        let declarations = facts.declarations(BASE_TYPES)?;
        // This is the compact policy set the original classifier consumes, not
        // another type tree or variable model. Hidden authored declarations
        // remain here, just as legacy typed_sites builds declared before filter.
        let declared = declarations
            .iter()
            .filter(|row| row.native.base)
            .map(|row| (row.owner.to_string(), row.name.to_string()))
            .collect::<HashSet<_>>();
        let ceiling = scope
            .list("hot_ceiling")
            .first()
            .and_then(|value| value.trim().parse().ok());
        for (key, msg) in hot_problems(&hot, Some(&declared), &homes, ceiling) {
            sink.site_decl("hot_home", SCOPES_FILE, 1, msg, format!("hot::{key}"));
        }
        checkpoint()?;
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(error);
        }
        if sink.sites.len() > MAX_FIXTURE_SITES {
            return Err("base-var hot fixture exceeds finding admission".into());
        }
        // hot_home owns no ALLOW suppression. Other base_vars rule ALLOW uses
        // are outside this named-rule cohort and are not claimed as aggregated.
        Ok(RawRun {
            name: "base_vars".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
#[cfg(test)]
#[path = "captured_base_var_hot_policy_tests.rs"]
mod tests;
