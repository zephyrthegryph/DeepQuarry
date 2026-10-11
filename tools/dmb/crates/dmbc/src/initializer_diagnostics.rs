//! Error origins for the initializer compiler's local write coordinates.
//! These spans contain ordinals, never expanded-source byte offsets. Only the
//! producer's aligned captured source sidecar can turn them into diagnostics.
use crate::lowering::LoweringDiagnostic;
use dm_codegen_byond::{LowerError, LowerErrorKind};
use dm_tree::frontend::{DiagnosticKind, SourceLocation};
use dm_tree::{
    frontend::ColdFrontend,
    initializers::{InitializerOriginKind, InitializerPlan},
};
use std::{collections::HashMap, path::Path};

#[derive(Debug)]
pub enum InitializerLoweringError {
    Unsupported(String),
    Invariant(String),
    Diagnostics(Vec<LoweringDiagnostic>),
}
impl std::fmt::Display for InitializerLoweringError {
    fn fmt(&self, output: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unsupported(message) | Self::Invariant(message) => output.write_str(message),
            Self::Diagnostics(errors) => {
                write!(
                    output,
                    "{} initializer lowering diagnostics",
                    errors
                        .iter()
                        .map(|error| 1 + error.related.len())
                        .sum::<usize>()
                )
            }
        }
    }
}
impl std::error::Error for InitializerLoweringError {}
impl From<String> for InitializerLoweringError {
    fn from(message: String) -> Self {
        // Unclassified legacy strings must not be labelled invalid user code.
        Self::Unsupported(message)
    }
}
impl From<&str> for InitializerLoweringError {
    fn from(message: &str) -> Self {
        Self::Unsupported(message.into())
    }
}

/// Resolve only the failing assignments. Declaration provenance is projected
/// through the captured expansion records; local write ordinals never enter
/// `ColdFrontend::location` as source offsets.
pub fn map_captured_lower_errors(
    errors: Vec<LowerError>,
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    write_ordinals: &[usize],
) -> Result<Vec<LoweringDiagnostic>, InitializerLoweringError> {
    let mut origins = Vec::new();
    let mut counts = Vec::with_capacity(errors.len());
    for error in &errors {
        let primary = error.span.ok_or_else(|| {
            InitializerLoweringError::Unsupported(format!(
                "initializer lowering has no assignment coordinate: {}",
                error.reason
            ))
        })?;
        counts.push(1 + error.related.len());
        for span in std::iter::once(primary).chain(error.related.iter().map(|note| note.span)) {
            if span.start != span.end {
                return Err(InitializerLoweringError::Invariant(
                    "initializer diagnostic requires one issued assignment ordinal".into(),
                ));
            }
            let ordinal = *write_ordinals.get(span.start).ok_or_else(|| {
                InitializerLoweringError::Invariant(format!(
                    "initializer local write coordinate {} is outside its unit",
                    span.start
                ))
            })?;
            origins.push(plan.origins.get(ordinal).ok_or_else(|| {
                InitializerLoweringError::Invariant(format!(
                    "initializer source write coordinate {ordinal} is outside captured plan"
                ))
            })?);
        }
    }
    let locations = captured_locations(frontend, &origins)?;
    let mut cursor = 0usize;
    errors
        .into_iter()
        .zip(counts)
        .map(|(mut error, count)| {
            let end = cursor.checked_add(count).ok_or_else(|| {
                InitializerLoweringError::Invariant(
                    "initializer diagnostic coordinate overflow".into(),
                )
            })?;
            let sources = locations.get(cursor..end).ok_or_else(|| {
                InitializerLoweringError::Invariant(
                    "initializer diagnostic projection is incomplete".into(),
                )
            })?;
            cursor = end;
            error.span = Some(dm_codegen_byond::LowerSpan { start: 0, end: 0 });
            for (index, note) in error.related.iter_mut().enumerate() {
                note.span = dm_codegen_byond::LowerSpan {
                    start: index + 1,
                    end: index + 1,
                };
            }
            Ok(map_lower_errors(vec![error], sources)?.remove(0))
        })
        .collect()
}

/// Exact current provenance binding shared by initializer and field diagnostics.
pub(crate) fn captured_locations(
    frontend: &ColdFrontend,
    origins: &[&dm_tree::initializers::InitializerOrigin],
) -> Result<Vec<SourceLocation>, InitializerLoweringError> {
    // One borrowed reverse index per batch. Buckets retain expansion encounter
    // order, including multiple macro projections of the same physical span.
    type ProjectionKey<'a> = (&'a Path, usize, usize, usize);
    let requested = origins
        .iter()
        .filter_map(|origin| {
            if !matches!(origin.kind, InitializerOriginKind::Declaration(_)) {
                return None;
            }
            let source = frontend.source(origin.provenance.span.file)?;
            Some((
                source.path.as_path(),
                origin.provenance.include_occurrence as usize,
                origin.provenance.span.start as usize,
                origin.provenance.span.end as usize,
            ))
        })
        .collect::<std::collections::HashSet<ProjectionKey<'_>>>();
    let mut projections: HashMap<ProjectionKey<'_>, (_, Vec<_>)> = HashMap::new();
    let mut definition_files = HashMap::new();
    if !origins.is_empty() {
        for expanded in frontend.expanded.origins.iter() {
            let key = (
                expanded.origin.path.as_path(),
                frontend.plan.regions[expanded.region].occurrence,
                expanded.source_span.start,
                expanded.source_span.end,
            );
            if !requested.contains(&key) {
                continue;
            }
            match projections.entry(key) {
                std::collections::hash_map::Entry::Vacant(entry) => {
                    entry.insert((expanded, Vec::new()));
                }
                std::collections::hash_map::Entry::Occupied(mut entry) => {
                    entry.get_mut().1.push(expanded);
                }
            }
        }
        for file in frontend.files.iter() {
            // Match the former linear lookup's first-file behavior exactly.
            definition_files
                .entry(file.path.as_path())
                .or_insert(file.id);
        }
    }
    origins
        .iter()
        .map(|origin| {
            let location = match origin.kind {
                InitializerOriginKind::ProcedureStatic { expanded_span, .. } => {
                    frontend.location(expanded_span.start)
                }
                InitializerOriginKind::Declaration(_) => {
                    let source = frontend
                        .source(origin.provenance.span.file)
                        .ok_or_else(|| {
                            InitializerLoweringError::Invariant(
                                "initializer source file absent".into(),
                            )
                        })?;
                    projections
                        .get(&(
                            source.path.as_path(),
                            origin.provenance.include_occurrence as usize,
                            origin.provenance.span.start as usize,
                            origin.provenance.span.end as usize,
                        ))
                        .into_iter()
                        .flat_map(|(first, rest)| {
                            std::iter::once(*first).chain(rest.iter().copied())
                        })
                        .find_map(|expanded| {
                            let location = frontend.location(expanded.output_span.start)?;
                            let definitions = location
                                .macro_expansions
                                .iter()
                                .filter_map(|expansion| expansion.definition.as_ref())
                                .filter_map(|definition| {
                                    let file = *definition_files.get(definition.path.as_path())?;
                                    dm_ir::Span::new(
                                        file,
                                        u32::try_from(definition.source_span.start).ok()?,
                                        u32::try_from(definition.source_span.end).ok()?,
                                    )
                                    .ok()
                                })
                                .collect::<Vec<_>>();
                            (definitions.as_slice() == origin.provenance.expansion_stack.as_ref())
                                .then_some(location)
                        })
                }
            }
            .ok_or_else(|| {
                InitializerLoweringError::Invariant(
                    "initializer diagnostic has no matching captured source projection".into(),
                )
            })?;
            Ok(location)
        })
        .collect()
}

/// `sources[i]` is the exact captured location of assignment `i` in this one
/// grouped VM unit. No source sorting or filesystem lookup occurs here.
pub fn map_lower_errors(
    errors: Vec<LowerError>,
    sources: &[SourceLocation],
) -> Result<Vec<LoweringDiagnostic>, InitializerLoweringError> {
    errors.into_iter().map(|error| {
        let ordinal = error.span.ok_or_else(|| InitializerLoweringError::Unsupported(
            format!("initializer lowering has no assignment coordinate: {}", error.reason)
        ))?.start;
        let origin = sources.get(ordinal).ok_or_else(|| InitializerLoweringError::Invariant(
            format!("initializer assignment coordinate {ordinal} exceeds captured sidecar length {}", sources.len())
        ))?.clone();
        let related = error.related.into_iter().map(|note| {
            let origin = sources.get(note.span.start).ok_or_else(||
                InitializerLoweringError::Invariant("secondary initializer coordinate exceeds current source roster".into()))?.clone();
            if note.span.start > note.span.end || note.span.end > sources.len() {
                return Err(InitializerLoweringError::Invariant("invalid secondary initializer coordinate".into()));
            }
            Ok(crate::lowering::RelatedDiagnostic { origin, message: note.message })
        }).collect::<Result<Vec<_>, InitializerLoweringError>>()?;
        Ok(LoweringDiagnostic { related,
            kind: match error.kind {
                LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                LowerErrorKind::UnsupportedModel => DiagnosticKind::UnsupportedModel,
                LowerErrorKind::Internal => DiagnosticKind::Internal,
            },
            identity: None,
            origin,
            message: if error.kind == LowerErrorKind::SourceError || error.statement.is_empty() { error.reason }
                else { format!("{}: {}", error.statement, error.reason) },
        })
    }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_codegen_byond::LowerSpan;
    use std::{path::PathBuf, sync::Arc};
    fn source(path: &str, line: usize, occurrence: usize) -> SourceLocation {
        SourceLocation {
            span: dm_ir::Span::new(dm_ir::FileId(occurrence as u32), 100, 120).unwrap(),
            path: Arc::new(PathBuf::from(path)),
            semantic_path: path.into(),
            line,
            encounter_ordinal: occurrence,
            include_occurrence: occurrence,
            include_chain: [0, occurrence].into(),
            macro_expansions: Arc::new(Vec::new()),
        }
    }
    #[test]
    fn typed_source_error_keeps_authored_message_and_current_assignment_provenance() {
        let sources = [source("included.dm", 7, 4), source("included.dm", 31, 9)];
        for kind in [LowerErrorKind::SourceError, LowerErrorKind::UnsupportedModel, LowerErrorKind::Internal] {
            let error = LowerError { statement: "initializer assignment".into(),
                reason: "formerly_missing_initializer: undefined proc".into(), kind,
                span: Some(LowerSpan { start: 1, end: 1 }),
                related: vec![dm_codegen_byond::LowerRelated { span: LowerSpan { start: 0, end: 0 },
                    message: "current related occurrence".into() }], ..Default::default() };
            let diagnostics = map_lower_errors(vec![error], &sources).unwrap();
            assert_eq!(diagnostics[0].origin, sources[1]);
            assert_eq!(diagnostics[0].related[0].origin, sources[0]);
            assert_eq!(diagnostics[0].related[0].message, "current related occurrence");
            assert_eq!(diagnostics[0].message, if kind == LowerErrorKind::SourceError {
                "formerly_missing_initializer: undefined proc"
            } else { "initializer assignment: formerly_missing_initializer: undefined proc" });
            assert_eq!(diagnostics[0].kind, match kind {
                LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                LowerErrorKind::UnsupportedModel => DiagnosticKind::UnsupportedModel,
                LowerErrorKind::Internal => DiagnosticKind::Internal,
            });
        }
    }
    #[test]
    fn local_write_coordinates_select_exact_captured_sources() {
        let sources = [source("class.dm", 90, 4), source("static.dm", 12, 9)];
        let errors = vec![
            LowerError {
                primary_anchor: None,
                related: Vec::new(),
                reason: "unsupported meaning".into(),
                span: Some(LowerSpan { start: 1, end: 1 }),
                ..Default::default()
            },
            LowerError {
                primary_anchor: None,
                related: Vec::new(),
                reason: "bad label".into(),
                kind: LowerErrorKind::SourceError,
                span: Some(LowerSpan { start: 0, end: 0 }),
                ..Default::default()
            },
        ];
        let diagnostics = map_lower_errors(errors, &sources).unwrap();
        assert_eq!(diagnostics[0].origin.semantic_path.as_ref(), "static.dm");
        assert_eq!(diagnostics[0].origin.line, 12);
        assert_eq!(diagnostics[0].origin.include_occurrence, 9);
        assert_eq!(diagnostics[0].kind, DiagnosticKind::UnsupportedModel);
        assert_eq!(diagnostics[1].origin.line, 90);
        assert_eq!(diagnostics[1].kind, DiagnosticKind::SourceError);
    }
    #[test]
    fn captured_plan_maps_declaration_and_static_ordinals_to_included_lines() {
        struct Included;
        impl dm_preprocess::SourceProvider for Included {
            fn read(&self, path: &std::path::Path) -> Result<String, String> {
                match path.file_name().and_then(|name| name.to_str()) {
                    Some("project.dme") => Ok("#include \"body.dm\"\n".into()),
                    Some("body.dm") => Ok("var/one = 1\n/proc/p()\n    var/static/counter = 2\n    return counter\nvar/two = 3\n".into()),
                    _ => Err("unexpected file".into()),
                }
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Included,
            &Default::default(),
            1,
        )
        .unwrap();
        let startup = crate::startup::capture(&frontend).unwrap();
        assert_eq!(startup.plan().writes.len(), 3);
        let errors = [1, 0, 2]
            .into_iter()
            .map(|ordinal| LowerError {
                primary_anchor: None,
                related: Vec::new(),
                reason: "unsupported assignment".into(),
                span: Some(LowerSpan {
                    start: ordinal,
                    end: ordinal,
                }),
                ..Default::default()
            })
            .collect();
        let diagnostics =
            map_captured_lower_errors(errors, &frontend, startup.plan(), &[0, 1, 2]).unwrap();
        assert_eq!(
            diagnostics
                .iter()
                .map(|error| error.origin.line)
                .collect::<Vec<_>>(),
            [3, 1, 5]
        );
        assert!(diagnostics
            .iter()
            .all(|error| error.origin.semantic_path.ends_with("body.dm")));
        let related = dm_codegen_byond::LowerRelated {
            span: LowerSpan { start: 1, end: 1 },
            message: "previous definition".into(),
        };
        let error = LowerError {
            span: Some(LowerSpan { start: 0, end: 0 }),
            related: vec![related.clone()],
            kind: LowerErrorKind::SourceError,
            ..Default::default()
        };
        // Unit-local [0,1] refers to captured writes [2,0], not the dense
        // source roster. Both primary and related must use this SAME issuance.
        let bound =
            map_captured_lower_errors(vec![error.clone()], &frontend, startup.plan(), &[2, 0])
                .unwrap();
        assert_eq!(bound[0].origin.line, 5);
        assert_eq!(bound[0].related[0].origin.line, 1);
        assert!(bound[0].related[0]
            .origin
            .semantic_path
            .ends_with("body.dm"));
        assert!(map_captured_lower_errors(vec![error], &frontend, startup.plan(), &[2]).is_err());
    }
    #[test]
    fn missing_or_invalid_coordinates_never_fall_back_to_first_write() {
        assert!(matches!(
            map_lower_errors(vec![LowerError::default()], &[source("a.dm", 2, 1)]),
            Err(InitializerLoweringError::Unsupported(_))
        ));
        assert!(matches!(
            map_lower_errors(
                vec![LowerError {
                    primary_anchor: None,
                    related: Vec::new(),
                    span: Some(LowerSpan { start: 9, end: 9 }),
                    ..Default::default()
                }],
                &[source("a.dm", 2, 1)]
            ),
            Err(InitializerLoweringError::Invariant(_))
        ));
    }
    #[test]
    fn large_captured_error_batch_preserves_two_file_order_and_macro_frames() {
        struct Sources;
        impl dm_preprocess::SourceProvider for Sources {
            fn read(&self, path: &std::path::Path) -> Result<String, String> {
                match path.file_name().and_then(|name| name.to_str()) {
                    Some("project.dme") => {
                        Ok("#include \"first.dm\"\n#include \"second.dm\"\n".into())
                    }
                    Some(name @ ("first.dm" | "second.dm")) => {
                        let prefix = if name == "first.dm" {
                            "first"
                        } else {
                            "second"
                        };
                        let mut text = "#define VALUE 7\n".to_owned();
                        for index in 0..64 {
                            text.push_str(&format!("var/{prefix}_{index} = VALUE\n"));
                        }
                        Ok(text)
                    }
                    _ => Err("unexpected fixture source".into()),
                }
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Sources,
            &Default::default(),
            2,
        )
        .unwrap();
        let startup = crate::startup::capture(&frontend).unwrap();
        assert_eq!(startup.plan().writes.len(), 128);
        let ordinals = (0..128).collect::<Vec<_>>();
        let errors = (0..16384)
            .map(|index| LowerError {
                primary_anchor: None,
                related: Vec::new(),
                reason: format!("boundary {index}"),
                span: Some(LowerSpan {
                    start: 127 - index % 128,
                    end: 127 - index % 128,
                }),
                ..Default::default()
            })
            .collect();
        let diagnostics =
            map_captured_lower_errors(errors, &frontend, startup.plan(), &ordinals).unwrap();
        assert_eq!(diagnostics.len(), 16384);
        for (index, diagnostic) in diagnostics.iter().enumerate() {
            let ordinal = 127 - index % 128;
            assert!(diagnostic.origin.semantic_path.ends_with(if ordinal < 64 {
                "first.dm"
            } else {
                "second.dm"
            }));
            assert_eq!(diagnostic.origin.line, ordinal % 64 + 2);
            assert_eq!(diagnostic.message, format!("boundary {index}"));
            assert!(!diagnostic.origin.macro_expansions.is_empty());
        }
    }
}

/// Exact current-bound diagnostic comparison, including every secondary origin.
pub(crate) fn verification_diagnostics_equal(
    a: &[LoweringDiagnostic],
    b: &[LoweringDiagnostic],
) -> bool {
    a.len() == b.len()
        && a.iter().zip(b).all(|(a, b)| {
            a.kind == b.kind
                && a.identity == b.identity
                && a.origin == b.origin
                && a.message == b.message
                && a.related.len() == b.related.len()
                && a.related
                    .iter()
                    .zip(&b.related)
                    .all(|(a, b)| a.origin == b.origin && a.message == b.message)
        })
}
