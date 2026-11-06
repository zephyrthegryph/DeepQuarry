use super::{
    EffectInput, OriginalDeclarationAndBody, OriginalThroughGraph, OriginalThroughKeywords,
    OriginalThroughReaderDeclarations, SourceSnapshot,
};
use crate::daemon::query::ORIGINAL_ORDERED_CHECKER_PHASES as PHASES;
use dm_analysis::{
    check_policy::DiagnosticSeverity,
    checker_effects::{OriginalDiagnosticLocation, OriginalDiagnosticPhase, ProducedPhase},
    checks::Diagnostic,
    checks_keyword_overrides::{PointProjection, REGISTRATION_TAG},
    checks_proc_visibility::BorrowedReportedPoint,
};
use std::{io, path::Path};

#[derive(serde::Serialize)]
struct Row<'a> {
    phase: &'static str,
    family: &'static str,
    registration_tag: Option<&'static str>,
    severity: &'static str,
    location_kind: &'static str,
    file: &'a Path,
    line: usize,
    column: usize,
    message: &'a str,
    notes: Vec<String>,
}

impl<'a> Row<'a> {
    fn diagnostic(
        phase: usize,
        diagnostic: &'a Diagnostic,
        tag: Option<&'static str>,
        severity: &'static str,
        kind: &'static str,
        (file, line, column): (&'a Path, usize, usize),
    ) -> Self {
        Self {
            phase: PHASES[phase],
            family: diagnostic.family,
            registration_tag: tag,
            severity,
            location_kind: kind,
            file,
            line,
            column,
            message: &diagnostic.message,
            notes: diagnostic.notes.iter().map(|note| note.legacy_text()).collect(),
        }
    }
}

fn write_row(
    output: &mut impl io::Write,
    input: &EffectInput,
    row: OriginalThroughReaderDeclarations<'_>,
    severity: DiagnosticSeverity,
) -> io::Result<()> {
    use OriginalDeclarationAndBody as Body;
    use OriginalThroughGraph as Graph;
    use OriginalThroughKeywords as Keyword;
    use OriginalThroughReaderDeclarations as Reader;

    let severity = super::super::named_policy::severity(severity);
    let emit = |output: &mut _, row: Row<'_>| serde_json::to_writer(output, &row).map_err(io::Error::from);
    match row {
        Reader::Declaration(finding) => {
            let point = finding.borrowed_reported_point().map_err(io::Error::other)?;
            let kind = match &point {
                BorrowedReportedPoint::Source(_) => "source",
                BorrowedReportedPoint::ParserSynthetic => "parser_synthetic",
                BorrowedReportedPoint::Builtin => "builtin",
            };
            emit(output, Row::diagnostic(
                0, finding.diagnostic(), finding.registration_tag(), severity, kind, point.coordinates(),
            ))
        }
        Reader::Semantic(Graph::Source(Keyword::Source(Body::Declaration(finding)))) => {
            let point = input.archive().borrowed_source_note_point(finding.diagnostic().span.start)
                .map_err(io::Error::other)?;
            emit(output, Row::diagnostic(
                1, finding.diagnostic(), finding.registration_tag(), severity, "source", point.reported_coordinates(),
            ))
        }
        Reader::Semantic(Graph::Source(Keyword::Source(Body::Body { row, .. }))) => {
            let phase = match row.phase() {
                OriginalDiagnosticPhase::Prelude => 2,
                OriginalDiagnosticPhase::Body => 3,
            };
            let archive = input.archive();
            let point = match row.location() {
                OriginalDiagnosticLocation::Expanded => Some(archive.borrowed_source_note_point(row.diagnostic().span.start).map_err(io::Error::other)?),
                OriginalDiagnosticLocation::Reader(point) => Some(archive.source_mapping().borrow_stored_original_reported_point(point).map_err(io::Error::other)?),
                OriginalDiagnosticLocation::ParserSynthetic => None,
            };
            let (kind, coordinates) = match &point {
                Some(point) => ("source", point.reported_coordinates()),
                None => ("parser_synthetic", (Path::new("(unknown)"), 0, 0)),
            };
            emit(output, Row::diagnostic(
                phase, row.diagnostic(), row.registration_tag(), severity, kind, coordinates,
            ))
        }
        Reader::Semantic(Graph::Source(Keyword::Keyword { findings, row })) => {
            let point = findings.point(row.point).map_err(io::Error::other)?;
            let kind = match &point {
                PointProjection::Source(_) => "source",
                PointProjection::Builtin => "builtin",
            };
            let (file, line, column) = point.coordinates();
            let notes = row.notes.iter()
                .map(|note| findings.legacy_note(row.point, note).map(|note| note.to_string()))
                .collect::<Result<_, _>>().map_err(io::Error::other)?;
            emit(output, Row {
                phase: PHASES[4], family: REGISTRATION_TAG,
                registration_tag: Some(REGISTRATION_TAG), severity, location_kind: kind, file, line, column,
                message: &row.message, notes,
            })
        }
        Reader::Semantic(Graph::Graph(finding)) => {
            let phase = match finding.phase() {
                ProducedPhase::SleepGraph => 5,
                ProducedPhase::PurityGraph => 6,
                ProducedPhase::BodyImmediate => return Err(io::Error::other("immediate effect is not a final graph diagnostic")),
            };
            let point = input.archive().borrowed_source_note_point(finding.diagnostic.span.start)
                .map_err(io::Error::other)?;
            emit(output, Row::diagnostic(
                phase, &finding.diagnostic, finding.registration_tag, severity, "source", point.reported_coordinates(),
            ))
        }
    }
}

impl SourceSnapshot {
    /// The IPC evaluator owns the bounded reply and publishes it only after
    /// all selected phases and the final revision/scope check succeed.
    pub(crate) fn write_original_ordered_checker(
        &self,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        let owner = self.original_checker_request_input(tree)?;
        let input = owner.input();
        self.with_effect_scope(input, environment, explicit, tree, |db, scope| {
            let loaded = scope.configuration();
            let policy_revision = self.policy_revision.ok_or_else(|| io::Error::other("Original checker policy revision unavailable"))?;
            let header = serde_json::to_vec(&serde_json::json!({
                "row": "source_native_original_ordered_checker",
                "schema": "dm-session-source-query-v1",
                "semantic_revision": format!("{:032x}", tree.identity()),
                "source_revision": format!("{:032x}", self.source_revision),
                "policy_revision": format!("{:032x}", policy_revision),
                "environment": environment,
                "configuration": loaded.selected.path,
                "configuration_explicit": loaded.selected.explicit,
                "configuration_present": loaded.present,
                "coverage": "selected_original_checker_phases",
                "phase_order": PHASES,
                "full_checker_parity": false,
            })).map_err(io::Error::from)?;
            output.write_all(header.strip_suffix(b"}").ok_or_else(|| io::Error::other("invalid ordered checker metadata object"))?)?;
            output.write_all(b",\"diagnostics\":[")?;
            let mut first = true;
            self.visit_original_cli_diagnostics_in_scope(input, tree, db, scope, |row, severity| {
                if !first {
                    output.write_all(b",")?;
                }
                first = false;
                write_row(output, input, row, severity)
            })?;
            output.write_all(b"]}\n")
        })
    }
}
