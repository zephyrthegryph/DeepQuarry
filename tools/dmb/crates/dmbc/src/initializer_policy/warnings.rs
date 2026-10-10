//! Successful initializer warnings, bound only to the current source plan.
//! These never enter failure diagnostics or retained classification payloads.
use super::{ClassifiedInitializers, RuntimeValue};
use crate::initializer_diagnostics::{captured_locations, InitializerLoweringError};
use dm_ir::{InitializerSite, InitializerTarget};
use dm_tree::{
    frontend::{ColdFrontend, SourceLocation},
    initializers::{InitializerOrigin, InitializerPlan},
};
use std::io::{self, Write};

// Effective receiver expansion may repeat a declaration's authored occurrence.
// Emission ordinal is intentionally excluded; include/macro provenance is not.
fn unique_authored<'a>(
    seen: &mut std::collections::HashMap<dm_tree::OccurrenceId, Vec<&'a InitializerOrigin>>,
    origin: &'a InitializerOrigin,
) -> bool {
    let entries = seen.entry(origin.occurrence).or_default();
    if entries
        .iter()
        .any(|previous| previous.kind == origin.kind && previous.provenance == origin.provenance)
    {
        return false;
    }
    entries.push(origin);
    true
}

pub use dm_ir::WarningCode;
/// Presentation coordinates only; occurrence provenance is used during capture,
/// never inferred from a different enclosing procedure or retained here.
#[derive(Clone, Debug)]
pub struct WarningLocation {
    pub semantic_path: std::sync::Arc<str>,
    pub line: usize,
}
impl From<SourceLocation> for WarningLocation {
    fn from(location: SourceLocation) -> Self {
        Self {
            semantic_path: location.semantic_path,
            line: location.line,
        }
    }
}

#[derive(Clone, Debug)]
pub struct InitializerWarning {
    pub source_ordinal: usize,
    pub code: WarningCode,
    pub name: Option<String>,
    pub location: WarningLocation,
}

/// Call after successful classification/lowering. The classifier's typed
/// combined value proves a sized allocation plus an authored expression;
/// implicit allocations and inherited assignments therefore remain silent.
pub fn capture(
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    classified: &ClassifiedInitializers,
) -> Result<Vec<InitializerWarning>, InitializerLoweringError> {
    if frontend.snapshot.tree.identity() != plan.source.tree.identity()
        || frontend.snapshot.occurrences.tree_identity() != plan.source.occurrences.tree_identity()
        || plan.writes.len() != plan.origins.len()
    {
        return Err(InitializerLoweringError::Invariant(
            "warning plan differs from current frontend".into(),
        ));
    }
    let mut selected = Vec::new();
    for value in &classified.writes {
        let ordinal = value.source_ordinal;
        if plan.writes.get(ordinal) != Some(&value.write) {
            return Err(InitializerLoweringError::Invariant(
                "warning classification differs from current write".into(),
            ));
        }
        if value.write.source_site != InitializerSite::Declaration
            || !matches!(
                value.runtime_value.as_ref(),
                Some(RuntimeValue::SizedArrayExplicit { .. })
            )
        {
            continue;
        }
        let symbol = match value.write.target {
            InitializerTarget::ProcedureStatic(identity) => identity.name,
            InitializerTarget::Shared { name, .. } | InitializerTarget::Instance { name, .. } => {
                name
            }
        };
        let name = plan.symbols.text(symbol).ok_or_else(|| {
            InitializerLoweringError::Invariant("warning variable spelling is unavailable".into())
        })?;
        selected.push((ordinal, name.to_owned()));
    }
    // Classification phases may reorder writes; warnings follow source order.
    selected.sort_by_key(|(ordinal, _)| *ordinal);
    let mut seen = std::collections::HashMap::new();
    selected.retain(|(ordinal, _)| unique_authored(&mut seen, &plan.origins[*ordinal]));
    let origins = selected
        .iter()
        .map(|(ordinal, _)| &plan.origins[*ordinal])
        .collect::<Vec<_>>();
    let locations = captured_locations(frontend, &origins)?;
    Ok(selected
        .into_iter()
        .zip(locations)
        .map(|((source_ordinal, name), location)| InitializerWarning {
            source_ordinal,
            code: WarningCode::ListDoubleInit,
            name: Some(name),
            location: location.into(),
        })
        .collect())
}

/// A warning has no failure status; callers keep their successful outcome.
pub fn write_warnings(output: &mut impl Write, warnings: &[InitializerWarning]) -> io::Result<()> {
    for warning in warnings {
        if warning.code.requires_name() != warning.name.is_some() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid warning subject",
            ));
        }
        write!(
            output,
            "{}:{}:warning ({}): ",
            warning.location.semantic_path,
            warning.location.line,
            warning.code.name()
        )?;
        if let Some(name) = &warning.name {
            write!(output, "{name}: ")?;
        }
        writeln!(output, "{}", warning.code.message())?;
    }
    Ok(())
}

/// Store only the presentation issued for this validated source snapshot.
pub fn render(warnings: &[InitializerWarning]) -> io::Result<Vec<String>> {
    warnings
        .iter()
        .map(|warning| {
            let mut bytes = Vec::new();
            write_warnings(&mut bytes, std::slice::from_ref(warning))?;
            String::from_utf8(bytes)
                .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{path::PathBuf, sync::Arc};

    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }

    #[test]
    fn pinned_frontend_startup_classification_binds_current_warning_lines() {
        let mut retained = crate::runner_host::BuildHost::one_shot();
        let engine = retained
            .engine(
                "warnings.dme".into(),
                Default::default(),
                true,
                include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        for (source, shift) in [
            (
                "/var/list/global_value[2] = null\n/datum/probe\n    var/list/value[2] = list(1,2)\n    var/list/implicit[2]\n/datum/probe/child\n    value = null\n/proc/probe()\n    var/static/list/cache[2] = null\n    return cache\n",
                0,
            ),
            (
                "// shifted current source\n\n/var/list/global_value[2] = null\n/datum/probe\n    var/list/value[2] = list(1,2)\n    var/list/implicit[2]\n/datum/probe/child\n    value = null\n/proc/probe()\n    var/static/list/cache[2] = null\n    return cache\n",
                2,
            ),
        ] {
            let frontend = dm_tree::frontend::FrontendRevision::new(
                dm_tree::frontend::build_with_config(
                    std::path::Path::new("warnings.dme"),
                    &Source(source),
                    &Default::default(),
                    dm_tree::frontend::FrontendConfig {
                        workers: 1,
                        engine: Some(engine.frontend_seed()),
                        observer: None,
                    },
                )
                .unwrap(),
            );
            let (host, _) =
                crate::request_runner::runner_facts::prepare(&frontend, &engine.snapshot).unwrap();
            let bodies = dm_tree::frontend::BodyArena::new(&frontend);
            let startup = crate::startup::capture_revision_facts_with_executor_and_bodies(
                &frontend,
                &[],
                &executor,
                &bodies,
            )
            .unwrap();
            let current = startup.view_revision(&frontend).unwrap();
            let plan = current.plan();
            let evaluator = crate::driver_facts::DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: &host,
                symbols: &plan.symbols,
            };
            let classified =
                super::super::classify(&plan.writes, &plan.symbols, &evaluator).unwrap();
            let warnings = capture(&frontend, plan, &classified).unwrap();
            let rows = warnings
                .iter()
                .map(|warning| (warning.name.as_deref().unwrap(), warning.location.line))
                .collect::<Vec<_>>();
            assert_eq!(
                rows,
                [
                    ("global_value", 1 + shift),
                    ("value", 3 + shift),
                    ("cache", 8 + shift)
                ]
            );
            assert_eq!(render(&warnings).unwrap().len(), 3);
        }
    }

    #[test]
    fn inherited_receivers_warn_once_but_distinct_includes_remain_distinct() {
        let origin = InitializerOrigin {
            occurrence: dm_tree::OccurrenceId(3),
            kind: dm_tree::initializers::InitializerOriginKind::Declaration(dm_tree::MemberId(2)),
            encounter_ordinal: 3,
            emission_ordinal: 0,
            provenance: dm_tree::Provenance {
                span: dm_ir::Span {
                    file: dm_ir::FileId(0),
                    start: 1,
                    end: 9,
                },
                include_occurrence: 0,
                region: 17,
                expansion_stack: Arc::from([]),
            },
        };
        let mut inherited = origin.clone();
        inherited.emission_ordinal = 9;
        let mut included = origin.clone();
        included.occurrence = dm_tree::OccurrenceId(4);
        included.provenance.include_occurrence = 1;
        let mut seen = std::collections::HashMap::new();
        assert!(unique_authored(&mut seen, &origin));
        assert!(!unique_authored(&mut seen, &inherited));
        assert!(unique_authored(&mut seen, &included));
    }

    #[test]
    fn warning_uses_current_location_and_exact_dreammaker_shape() {
        let warning = InitializerWarning {
            source_ordinal: 7,
            code: WarningCode::ListDoubleInit,
            name: Some("value".into()),
            location: SourceLocation {
                span: dm_ir::Span {
                    file: dm_ir::FileId(0),
                    start: 12,
                    end: 19,
                },
                path: Arc::new(PathBuf::from("current.dm")),
                semantic_path: Arc::from("current.dm"),
                line: 2,
                encounter_ordinal: 7,
                include_occurrence: 0,
                include_chain: Arc::from([]),
                macro_expansions: Arc::new(Vec::new()),
            }
            .into(),
        };
        let mut output = Vec::new();
        write_warnings(&mut output, &[warning]).unwrap();
        assert_eq!(
            String::from_utf8(output).unwrap(),
            "current.dm:2:warning (list_double_init): value: list doubly initialized\n"
        );
        let mut silent = Vec::new();
        write_warnings(&mut silent, &[]).unwrap();
        assert!(silent.is_empty());
    }
}
