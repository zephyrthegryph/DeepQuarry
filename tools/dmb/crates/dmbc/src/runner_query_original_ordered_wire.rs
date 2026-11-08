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

pub(super) fn write_body_diagnostic_row(
    input: &EffectInput,
    row: &dm_analysis::checker_effects::OriginalBodyDiagnostic,
    level: DiagnosticSeverity,
    output: &mut dyn io::Write,
) -> io::Result<()> {
    let severity = super::super::named_policy::severity(level);
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
    serde_json::to_writer(output, &Row::diagnostic(
        phase, row.diagnostic(), row.registration_tag(), severity, kind, coordinates,
    )).map_err(io::Error::from)
}

fn write_row(
    output: &mut impl io::Write,
    input: &EffectInput,
    row: OriginalThroughReaderDeclarations<'_>,
    level: DiagnosticSeverity,
) -> io::Result<()> {
    use OriginalDeclarationAndBody as Body;
    use OriginalThroughGraph as Graph;
    use OriginalThroughKeywords as Keyword;
    use OriginalThroughReaderDeclarations as Reader;

    let severity = super::super::named_policy::severity(level);
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
            write_body_diagnostic_row(input, row, level, output)
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

struct OrderedArray {
    stage: crate::selected_report_spool::Stage,
    first: bool,
    clean: bool,
}
impl OrderedArray {
    fn new(cache:&Path)->io::Result<Self>{
        use std::io::Write as _;
        let mut stage=crate::selected_report_spool::Stage::new(cache)?;
        stage.write_all(b"[")?;
        Ok(Self{stage,first:true,clean:true})
    }
    fn push(&mut self,input:&EffectInput,row:OriginalThroughReaderDeclarations<'_>,severity:DiagnosticSeverity)->io::Result<()>{
        use std::io::Write as _;
        if !self.first {self.stage.write_all(b",")?;}
        write_row(&mut self.stage,input,row,severity)?;
        self.first=false;
        self.clean &= severity > DiagnosticSeverity::Info;
        Ok(())
    }
    fn seal(mut self)->io::Result<crate::selected_report_spool::Verified>{
        use std::io::Write as _;
        self.stage.write_all(b"]")?;
        let (verified,_)=self.stage.seal()?.validate(|source|io::copy(source,&mut io::sink()))?;
        Ok(verified)
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
    ) -> io::Result<bool> {
        let owner = self.original_checker_request_input(tree)?;
        self.write_original_ordered_checker_using(owner.input(),environment,explicit,tree,output)
    }

    pub(super) fn write_original_ordered_checker_using(
        &self,
        input:&std::sync::Arc<EffectInput>,
        environment:&Path,
        explicit:Option<&Path>,
        tree:&dm_tree::SemanticTree,
        output:&mut impl io::Write,
    )->io::Result<bool>{
        self.with_effect_scope(input, environment, explicit, tree, |db, scope| {
            let header = self.original_ordered_header(environment, tree, scope)?;
            output.write_all(header.strip_suffix(b"}").ok_or_else(|| io::Error::other("invalid ordered checker metadata object"))?)?;
            output.write_all(b",\"diagnostics\":[")?;
            let mut first = true;
            let mut clean = true;
            self.visit_original_cli_diagnostics_in_scope(input, tree, db, scope, |row, severity| {
                if !first {
                    output.write_all(b",")?;
                }
                first = false;
                write_row(output, input, row, severity)?;
                // Pinned DreamChecker CLI counts emitted Error, Warning and Info.
                clean &= severity > DiagnosticSeverity::Info;
                Ok(())
            })?;
            output.write_all(b"]}\n")?;
            Ok(clean)
        })
    }

    fn original_ordered_header(
        &self, environment:&Path, tree:&dm_tree::SemanticTree, scope:&super::PurityScope<'_>,
    )->io::Result<Vec<u8>>{
    let loaded = scope.configuration();
    let policy_revision = self.policy_revision.ok_or_else(|| io::Error::other("Original checker policy revision unavailable"))?;
    serde_json::to_vec(&serde_json::json!({
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
    })).map_err(io::Error::from)
    }

    /// Compound-only opt-in. The caller has already admitted the same shared
    /// Original capture, optional Checker configuration and external cache.
    pub(in crate::runner_host) fn write_compact_original_ordered_checker(
        &self, environment:&Path, tree:&dm_tree::SemanticTree, cache:&Path,
        output:&mut impl io::Write,
    )->io::Result<bool>{
        let absolute = self.original_checker_request_input(tree)?;
        let input = EffectInput::original_checker_source_with_current_bodies(
            std::sync::Arc::clone(absolute.input().archive()), absolute.input().profile(),
            self.diagnostic_declarations.as_ref().ok_or_else(||io::Error::other("compact Checker declaration receipt absent"))?,
            self.native_raw_queries.as_deref().ok_or_else(||io::Error::other("compact Checker query owner absent"))?,
        ).map_err(io::Error::other)?;
        self.write_compact_original_ordered_checker_using(
            &input,environment,None,tree,cache,dm_analysis::checker_order::ARCHIVED_CHUNK_WIDTH,output,
        )
    }

    pub(super) fn write_compact_original_ordered_checker_using(
        &self,
        input:&std::sync::Arc<EffectInput>,
        environment:&Path,
        explicit:Option<&Path>,
        tree:&dm_tree::SemanticTree,
        cache:&Path,
        width:usize,
        output:&mut impl io::Write,
    )->io::Result<bool>{
        use super::{OriginalDeclarationAndBody as Body, OriginalThroughGraph as Graph,
                    OriginalThroughKeywords as Keyword, OriginalThroughReaderDeclarations as Reader};
        use std::{cell::RefCell, io::Write as _};
        self.with_effect_scope(input, environment, explicit, tree, |db, scope| {
            let mut declarations = OrderedArray::new(cache)?;
            let validate = || scope.validate(db, input).map_err(io::Error::other);
            validate()?;
            let checkpoint = crate::daemon::control::checkpoint;
            db.visit_original_reader_declarations(input, &checkpoint, |finding| {
                let level = finding.original_fixed_level().ok_or_else(|| io::Error::other("original reader diagnostic lacks genuine default severity"))?;
                if let Some(severity) = scope.policy().register(finding.registration_tag(), level).filter(|level| *level <= DiagnosticSeverity::Info) {
                    declarations.push(input, Reader::Declaration(finding), severity)?;
                }
                Ok(())
            })?;
            validate()?;
            db.with_original_declarations(input, tree, &checkpoint, |findings| {
                for finding in findings.rows() {
                    crate::daemon::control::checkpoint()?;
                    if let Some(severity) = scope.policy().register(finding.registration_tag(), finding.default_severity()).filter(|level| *level <= DiagnosticSeverity::Info) {
                        declarations.push(input, Reader::Semantic(Graph::Source(Keyword::Source(Body::Declaration(finding)))), severity)?;
                    }
                }
                Ok(())
            })?;
            let tail = RefCell::new(OrderedArray::new(cache)?);
            let (prelude, body, body_clean) = db.with_archived_compact_report(
                input, scope, width, cache, write_body_diagnostic_row,
                |findings| {
                    use dm_analysis::checks_keyword_overrides::DEFAULT_SEVERITY;
                    if let Some(severity) = scope.policy().register(Some(REGISTRATION_TAG), DEFAULT_SEVERITY).filter(|level| *level <= DiagnosticSeverity::Info) {
                        for row in findings.rows() {
                            tail.borrow_mut().push(input, Reader::Semantic(Graph::Source(Keyword::Keyword{findings,row})),severity)?;
                        }
                    }
                    Ok(())
                },
                |row| {
                    if row.severity <= DiagnosticSeverity::Info {
                        tail.borrow_mut().push(input, Reader::Semantic(Graph::Graph(row)),row.severity)?;
                    }
                    Ok(())
                },
            )?;
            let tail = tail.into_inner();
            let clean = declarations.clean && body_clean && tail.clean;
            let phases = [declarations.seal()?, prelude, body, tail.seal()?];
            let header = self.original_ordered_header(environment, tree, scope)?;
            let prefix = header.strip_suffix(b"}").ok_or_else(|| io::Error::other("invalid ordered checker metadata object"))?;
            let head = b",\"diagnostics\":[";
            let mut length = (prefix.len()+head.len()+3) as u64;
            let mut groups = 0u64;
            for phase in &phases {
                let inner = phase.length().checked_sub(2).ok_or_else(|| io::Error::other("short verified checker phase"))?;
                if inner != 0 { groups += 1; }
                length = length.checked_add(inner).ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory,"ordered checker output overflow"))?;
            }
            if length.checked_add(groups.saturating_sub(1)).is_none_or(|bytes| bytes > dq_analyze::selected_exclusions_wire::MAX_STREAM) {
                return Err(io::Error::new(io::ErrorKind::OutOfMemory,"ordered checker output exceeds private report bound"));
            }
            validate()?;
            crate::daemon::control::checkpoint()?;
            output.write_all(prefix)?;
            output.write_all(head)?;
            let mut first = true;
            for phase in phases { phase.append_array_rows(output, &mut first)?; }
            output.write_all(b"]}\n")?;
            Ok(clean)
        })
    }

}
