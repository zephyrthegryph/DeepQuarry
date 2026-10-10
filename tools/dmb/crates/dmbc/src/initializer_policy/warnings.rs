//! Successful initializer warnings, bound only to the current source plan.
//! These never enter failure diagnostics or retained classification payloads.
use super::{ClassifiedInitializers, RuntimeValue};
use crate::initializer_diagnostics::{InitializerLoweringError, captured_locations};
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WarningCode {
    ListDoubleInit,
}
impl WarningCode {
    pub fn name(self) -> &'static str {
        match self {
            Self::ListDoubleInit => "list_double_init",
        }
    }
}
#[derive(Clone, Debug)]
pub struct InitializerWarning {
    pub source_ordinal: usize,
    pub code: WarningCode,
    pub name: String,
    pub location: SourceLocation,
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
            name,
            location,
        })
        .collect())
}

/// A warning has no failure status; callers keep their successful outcome.
pub fn write_warnings(output: &mut impl Write, warnings: &[InitializerWarning]) -> io::Result<()> {
    for warning in warnings {
        writeln!(
            output,
            "{}:{}:warning ({}): {}: list doubly initialized",
            warning.location.semantic_path,
            warning.location.line,
            warning.code.name(),
            warning.name
        )?;
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
            name: "value".into(),
            location: SourceLocation {
                span: dm_ir::Span { file: dm_ir::FileId(0), start: 12, end: 19 },
                path: Arc::new(PathBuf::from("current.dm")),
                semantic_path: Arc::from("current.dm"),
                line: 2,
                encounter_ordinal: 7,
                include_occurrence: 0,
                include_chain: Arc::from([]),
                macro_expansions: Arc::new(Vec::new()),
            },
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
