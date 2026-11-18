//! Bounded syntax inventory for large preprocessed worlds. The caller keeps
//! the source text; this module never builds a whole-project token or AST Vec.

use crate::{
    parse, parse_proc_body, AstFile, Diagnostic, DiagnosticKind, Item, ItemKind, Span, Statement,
    StatementKind,
};
use std::collections::BTreeMap;

const MAX_DIAGNOSTIC_GROUPS: usize = 256;

#[cfg(test)]
mod stable_group_tests {
    use super::*;
    #[test]
    fn body_length_edits_preserve_following_grammar_groups() {
        let original = (0..180)
            .map(|n| format!("/proc/p{n}()\n    return {n}\n"))
            .collect::<String>();
        let changed = original.replace(
            "    return 2\n",
            "    return list(1, 2, 3, 4, 5, 6, 7, 8)\n",
        );
        let groups = |source: &str| {
            let mut groups = Vec::new();
            let report = for_each_stable_source_chunk(source, source.len(), 32, |text, _| {
                groups.push(text.to_string())
            });
            assert_eq!(report.skipped_declarations, 0);
            assert_eq!(groups.concat(), source);
            groups
        };
        let first = groups(&original);
        let second = groups(&changed);
        assert_eq!(first.len(), second.len());
        assert_eq!(first.iter().zip(&second).filter(|(a, b)| a != b).count(), 1);
        for group in second {
            assert!(parse(&group).diagnostics.is_empty());
        }
    }
}

#[derive(Debug, Default)]
pub struct ChunkReport {
    pub parsed_chunks: usize,
    pub parsed_bytes: usize,
    pub skipped_declarations: usize,
    pub skipped_bytes: usize,
    pub first_skipped_span: Option<Span>,
}

/// Invoke `visit` with each bounded AST, then drop it before parsing the next
/// chunk. The callback may retain declarations, but the parser never retains
/// the complete source's tokens or procedure bodies by itself.
pub fn for_each_parsed_chunk(
    source: &str,
    max_chunk_bytes: usize,
    mut visit: impl FnMut(&AstFile, usize),
) -> ChunkReport {
    for_each_source_chunk(source, max_chunk_bytes, |text, offset| {
        let ast = parse(text);
        visit(&ast, offset);
    })
}

/// Visit independent structural chunks without allocating tokens or parsing.
/// Boundaries are identical to `for_each_parsed_chunk` and preserve declaration
/// nesting, multiline literals, and include footprint declarations.
pub fn for_each_source_chunk(
    source: &str,
    max_chunk_bytes: usize,
    visit: impl FnMut(&str, usize),
) -> ChunkReport {
    for_each_source_chunk_with_limits(source, max_chunk_bytes, max_chunk_bytes, visit)
}

/// Separate cache granularity from the maximum supported declaration size.
/// A single declaration can exceed `target_chunk_bytes` while remaining bounded
/// by `max_declaration_bytes`.
pub fn for_each_source_chunk_with_limits(
    source: &str,
    target_chunk_bytes: usize,
    max_declaration_bytes: usize,
    mut visit: impl FnMut(&str, usize),
) -> ChunkReport {
    let limit = max_declaration_bytes.max(1);
    let target = target_chunk_bytes.max(1).min(limit);
    let mut report = ChunkReport::default();
    let mut chunk_start = 0usize;
    let mut chunk_end = 0usize;
    let mut declaration_start = 0usize;
    let mut parse_chunk = |start: usize, end: usize, report: &mut ChunkReport| {
        if source[start..end].trim().is_empty() {
            return;
        }
        report.parsed_chunks += 1;
        report.parsed_bytes += end - start;
        visit(&source[start..end], start);
    };
    let mut on_boundary = |boundary: usize| {
        if boundary <= declaration_start {
            return;
        }
        let segment_len = boundary - declaration_start;
        if segment_len > limit {
            if chunk_end > chunk_start {
                parse_chunk(chunk_start, chunk_end, &mut report);
            }
            report.skipped_declarations += 1;
            report.skipped_bytes += segment_len;
            report
                .first_skipped_span
                .get_or_insert(Span::new(declaration_start, boundary));
            chunk_start = boundary;
            chunk_end = boundary;
        } else {
            if chunk_end > chunk_start && boundary - chunk_start > target {
                parse_chunk(chunk_start, chunk_end, &mut report);
                chunk_start = declaration_start;
            }
            chunk_end = boundary;
        }
        declaration_start = boundary;
    };
    for_each_top_level_boundary(source, &mut on_boundary);
    on_boundary(source.len());
    if chunk_end > chunk_start {
        parse_chunk(chunk_start, chunk_end, &mut report);
    }
    report
}

/// Group complete root declarations by header anchors, rather than body byte
/// counts. Body edits preserve following groups; an insertion resynchronizes at
/// the next anchor. Large type blocks remain indivisible grammar units.
pub fn for_each_stable_source_chunk(
    source: &str,
    max_declaration_bytes: usize,
    max_declarations: usize,
    mut visit: impl FnMut(&str, usize),
) -> ChunkReport {
    crate::stable_chunks::scan_stable_source_chunks_from::<()>(
        source,
        crate::BoundaryCheckpoint::default(),
        max_declaration_bytes,
        max_declarations,
        |text, offset, _| {
            visit(text, offset);
            std::ops::ControlFlow::Continue(())
        },
    )
    .expect("initial joined-stream stable checkpoint is valid")
    .0
}

/// Primary-issued envelope and scalar lexical cursor, from the SAME AstFile.
pub struct ProcedureWithOrigins {
    pub item: Item,
    pub opening_parenthesis: Option<Span>,
    pub parameters: crate::ProcedureParameters,
}
/// Compatibility wrapper retains the existing parser/runtime interface.
pub fn parse_proc_at_span(source: &str, span: Span) -> Result<Item, Diagnostic> {
    parse_proc_with_origins_at_span(source, span).map(|issued| issued.item)
}
pub fn parse_proc_with_origins_at_span(
    source: &str,
    span: Span,
) -> Result<ProcedureWithOrigins, Diagnostic> {
    let Some(slice) = source.get(span.range()) else {
        return Err(Diagnostic {
            span,
            kind: DiagnosticKind::Unsupported,
            message: "procedure span is outside source".into(),
        });
    };
    let mut ast = parse(slice);
    if let Some(mut diagnostic) = ast.diagnostics.into_iter().next() {
        diagnostic.span.start += span.start;
        diagnostic.span.end += span.start;
        return Err(diagnostic);
    }
    if ast.items.len() != 1 || !matches!(ast.items[0].kind, ItemKind::Proc | ItemKind::Verb) {
        return Err(Diagnostic {
            span,
            kind: DiagnosticKind::Unsupported,
            message: "span does not contain one procedure".into(),
        });
    }
    let mut item = ast.items.remove(0);
    // Token kinds exclude parentheses inside strings/comments. Selection runs
    // before tokens are dropped, never a second lex/parse in a policy pass.
    let opening_parenthesis = ast
        .tokens
        .iter()
        .find(|token| {
            token.span.start >= item.header_span.start
                && token.span.end <= item.header_span.end
                && token.kind == crate::TokenKind::Punctuation
                && token.text == "("
        })
        .map(|token| Span::new(token.span.start + span.start, token.span.end + span.start));
    let parameters =
        crate::parameter_syntax::issue(slice, &ast.tokens, item.header_span, span.start);
    rebase_item(&mut item, span.start);
    Ok(ProcedureWithOrigins {
        item,
        opening_parenthesis,
        parameters: crate::ProcedureParameters::Owned(parameters),
    })
}

/// Grammar adapter over a captured declaration owner's ORIGINAL span tokens.
/// This lower-level syntax API is not source/current-frame authority. Native
/// callers must first authenticate their exact original chunk/body recipe.
pub fn parse_proc_with_origins_from_spans(
    source: &str,
    span: Span,
    tokens: &[crate::SpanToken],
    base: usize,
) -> Result<ProcedureWithOrigins, Diagnostic> {parse_proc_with_origins_and_default_roots_from_spans(source,span,tokens,base,None)}
/// SAME actual procedure/token grammar. A supplied default owner is consumed
/// before optional expression issuance; absent/mismatched data never reparses.
pub fn parse_proc_with_origins_and_default_roots_from_spans(source:&str,span:Span,tokens:&[crate::SpanToken],base:usize,defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>)->Result<ProcedureWithOrigins,Diagnostic>{parse_proc_with_parameter_profile(source,span,crate::TokenWindow::from_slice(tokens),base,defaults,false,None,None)}
/// Original formal interpretation DATA. This API confers no current source or
/// semantic profile grant; the authenticated existing Header owner selects it.
pub fn parse_original_proc_with_origins_and_default_roots_from_spans(source:&str,span:Span,tokens:&[crate::SpanToken],base:usize,defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>)->Result<ProcedureWithOrigins,Diagnostic>{parse_proc_with_parameter_profile(source,span,crate::TokenWindow::from_slice(tokens),base,defaults,true,None,None)}
/// BODY grammar adopts this SAME preissued header allocation; no parameter
/// grammar/default producer runs again. Caller authenticates its source owner.
pub fn parse_original_proc_with_shared_parameters_from_spans(source:&str,span:Span,tokens:&[crate::SpanToken],base:usize,parameters:crate::SharedParameterSignature)->Result<ProcedureWithOrigins,Diagnostic>{parse_original_proc_with_shared_parameters_from_window(source,span,crate::TokenWindow::from_slice(tokens),base,parameters,None)}
/// Actual primary token DATA with its preissued parameter cohort. Structural
/// BODY grammar reads the exact window directly and allocates no dense token tape.
pub fn parse_original_proc_with_shared_parameters_from_window(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,parameters:crate::SharedParameterSignature,facts:Option<crate::OriginalLiteralFactsView<'_>>)->Result<ProcedureWithOrigins,Diagnostic>{
    parse_proc_with_parameter_profile(source,span,tokens,base,None,true,Some(parameters),facts)
}
/// Source-neutral consumption DATA from the SAME actual native production.
/// Current authority requires the private recipe/factory; exported Items cannot
/// reacquire that owner merely by carrying equal bytes or this scalar.
pub fn parse_proc_with_native_consumption_from_window(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,original:bool,preissued:Option<crate::SharedParameterSignature>,facts:Option<crate::OriginalLiteralFactsView<'_>>)->(Result<ProcedureWithOrigins,Diagnostic>,bool){
 let mut complete=false;
 let result=parse_proc_with_parameter_profile_and_native_consumption(source,span,tokens,base,defaults,original,preissued,facts,Some(&mut complete),false,None);
 (result,complete)
}
/// Same canonical parser with transient typed collection completion. DATA only;
/// the private commit factory must supply its pre-funded cleanup and actual loan.
pub fn parse_proc_with_committed_native_consumption_from_window(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,preissued:crate::SharedParameterSignature,facts:crate::OriginalLiteralFactsView<'_>)->(Result<ProcedureWithOrigins,Diagnostic>,bool){let mut complete=false;let result=parse_proc_with_parameter_profile_and_native_consumption(source,span,tokens,base,None,true,Some(preissued),Some(facts),Some(&mut complete),true,None);(result,complete)}

/// Actual result DATA precedes the SAME Storage credit. On any ordinary drop,
/// the Item/diagnostic payload dies before its physical allocation is released.
/// No Current/source/Original grammar authority is issued by this wrapper.
pub struct AdmittedProcedureWithOrigins{result:Option<Result<ProcedureWithOrigins,Diagnostic>>,complete:bool,credit:Option<crate::SettingRootLease>}
impl AdmittedProcedureWithOrigins{
 pub fn complete(&self)->bool{self.complete}
 pub fn take_result(&mut self)->Result<ProcedureWithOrigins,Diagnostic>{self.result.take().expect("actual canonical result taken once")}
 pub fn into_credit(mut self)->crate::SettingRootLease{assert!(self.result.is_none(),"take actual result before transferring its storage credit");self.credit.take().expect("actual canonical credit taken once")}
}
fn parse_admitted_procedure(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,original:bool,preissued:Option<crate::SharedParameterSignature>,facts:Option<crate::OriginalLiteralFactsView<'_>>,typed:bool,a:&crate::SettingAdmission<'_>)->std::io::Result<AdmittedProcedureWithOrigins>{
 if !preissued.as_ref().is_some_and(|parameters|parameters.is_admitted_by(a)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"canonical allocation-only parser requires its admitted shared parameter owner"))}
 let storage=crate::declaration_parser::CanonicalPrimaryStorage::new(a)?;
 let mut complete=false;
 // Storage is declared BEFORE result, so all failure paths destroy actual
 // Item/header/diagnostic backing before the grant, including failed finish.
 let result=parse_proc_with_parameter_profile_and_native_consumption(source,span,tokens,base,defaults,original,preissued,facts,Some(&mut complete),typed,Some(&storage));
 if let Some(actual)=storage.take_failure().or_else(||a.take_operational_error()){return Err(actual)}
 let credit=storage.finish(&result)?;
 Ok(AdmittedProcedureWithOrigins{result:Some(result),complete,credit:Some(credit)})
}
pub fn parse_proc_with_native_consumption_from_window_admitted(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,original:bool,preissued:Option<crate::SharedParameterSignature>,facts:Option<crate::OriginalLiteralFactsView<'_>>,a:&crate::SettingAdmission<'_>)->std::io::Result<AdmittedProcedureWithOrigins>{parse_admitted_procedure(source,span,tokens,base,defaults,original,preissued,facts,false,a)}
pub fn parse_proc_with_committed_native_consumption_from_window_admitted(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,preissued:crate::SharedParameterSignature,facts:crate::OriginalLiteralFactsView<'_>,a:&crate::SettingAdmission<'_>)->std::io::Result<AdmittedProcedureWithOrigins>{parse_admitted_procedure(source,span,tokens,base,None,true,Some(preissued),Some(facts),true,a)}
fn parse_proc_with_parameter_profile(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,mut defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,original:bool,preissued:Option<crate::SharedParameterSignature>,facts:Option<crate::OriginalLiteralFactsView<'_>>)->Result<ProcedureWithOrigins,Diagnostic>{
    parse_proc_with_parameter_profile_and_native_consumption(source,span,tokens,base,defaults,original,preissued,facts,None,false,None)
}
fn parse_proc_with_parameter_profile_and_native_consumption(source:&str,span:Span,tokens:crate::TokenWindow<'_>,base:usize,mut defaults:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,original:bool,preissued:Option<crate::SharedParameterSignature>,facts:Option<crate::OriginalLiteralFactsView<'_>>,native_consumption:Option<&mut bool>,typed:bool,allocation:Option<&crate::declaration_parser::CanonicalPrimaryStorage<'_,'_>>)->Result<ProcedureWithOrigins,Diagnostic>{
    let failure = |message: &str| match allocation {
        Some(storage)=>storage.diagnostic(span,DiagnosticKind::Unsupported,message),
        None=>Diagnostic {span,kind:DiagnosticKind::Unsupported,message:message.into()},
    };
    if source.get(span.range()).is_none() || span.end.checked_add(base).is_none() {
        return Err(failure("original procedure token range is outside source"));
    }
    let first = tokens.partition_point(|t| t.span.end <= span.start);
    let end = tokens.partition_point(|t| t.span.start < span.end);
    let tokens = tokens
        .range(first,end)
        .ok_or_else(|| failure("original procedure token range differs"))?;
    if tokens.iter().any(|t| {
        t.span.start < span.start || t.span.end > span.end || source.get(t.span.range()).is_none()
    }) || tokens.iter().zip(tokens.iter().skip(1)).any(|(left,right)|left.span.end>right.span.start)
    {
        return Err(failure("original procedure token boundaries differ"));
    }
    let mut consumed=false;
    let (mut items, diagnostics) =
        if let Some(storage)=allocation{storage.parse(source,span,tokens,facts,&mut consumed,typed)}else{if typed{crate::declaration_parser::parse_original_body_span_range_with_typed_native_consumption(source,span,tokens,facts,&mut consumed)}else{crate::declaration_parser::parse_original_body_span_range_with_native_consumption(source,span,tokens,facts,&mut consumed)}};
    let observe_native_parameters=native_consumption.is_some()&&!original;
    if let Some(complete)=native_consumption{*complete=consumed;}
    if let Some(mut diagnostic) = diagnostics.into_iter().next() {
        diagnostic.span.start += base;
        diagnostic.span.end += base;
        return Err(diagnostic);
    }
    if items.len() != 1 || !matches!(items[0].kind, ItemKind::Proc | ItemKind::Verb) {
        return Err(failure(
            "original token span does not contain one procedure",
        ));
    }
    let mut item = items.remove(0);
    let opening_parenthesis = tokens
        .iter()
        .find(|t| {
            t.span.start >= item.header_span.start
                && t.span.end <= item.header_span.end
                && t.kind == crate::TokenKind::Punctuation
                && t.text(source) == "("
        })
        .map(|t| Span::new(t.span.start + base, t.span.end + base));
    let parameters = match preissued{Some(parameters)=>{let header=Span::new(item.header_span.start.checked_add(base).ok_or_else(||failure("parameter header offset overflow"))?,item.header_span.end.checked_add(base).ok_or_else(||failure("parameter header offset overflow"))?);if parameters.header()!=header{return Err(failure("preissued parameter metadata belongs to another actual header"))}crate::ProcedureParameters::Shared(parameters)},None=>{
        let dense=tokens.as_dense_slice().ok_or_else(||failure("actual original parameter metadata is unissued"))?;
        crate::ProcedureParameters::Owned(if original{crate::parameter_syntax::parameter_signature_original_with_default_roots(source,dense,item.header_span,base,&mut defaults)}else if observe_native_parameters{crate::parameter_syntax::parameter_signature_native_observed(source,dense,item.header_span,base,&mut defaults)}else{match defaults{Some(provider)=>crate::parameter_syntax::parameter_signature_with_default_roots(source,dense,item.header_span,base,provider),None=>crate::parameter_syntax::issue_spans(source,dense,item.header_span,base)}})
    }};
    rebase_item(&mut item, base);
    Ok(ProcedureWithOrigins {
        item,
        opening_parenthesis,
        parameters,
    })
}

fn rebase_item(item: &mut Item, offset: usize) {
    item.span.start += offset;
    item.span.end += offset;
    item.header_span.start += offset;
    item.header_span.end += offset;
    for child in &mut item.children {
        rebase_item(child, offset);
    }
}

#[derive(Debug, Default)]
pub struct StreamingAudit {
    pub parsed_chunks: usize,
    pub parsed_bytes: usize,
    pub skipped_declarations: usize,
    pub skipped_bytes: usize,
    pub items: usize,
    pub procedures: usize,
    pub statements: usize,
    pub unsupported_statements: usize,
    pub diagnostic_count: usize,
    pub diagnostic_groups: BTreeMap<String, usize>,
    /// First representative of each diagnostic group, with absolute source span.
    pub diagnostic_examples: BTreeMap<String, Diagnostic>,
    /// The first diagnostics only, with spans relative to the complete source.
    pub diagnostics: Vec<Diagnostic>,
}

impl StreamingAudit {
    fn diagnostic(&mut self, mut diagnostic: Diagnostic, offset: usize, sample_limit: usize) {
        self.diagnostic_count += 1;
        let mut group = diagnostic_group(&diagnostic.message);
        if !self.diagnostic_groups.contains_key(&group)
            && self.diagnostic_groups.len() >= MAX_DIAGNOSTIC_GROUPS
        {
            group = "<other>".into();
        }
        *self.diagnostic_groups.entry(group.clone()).or_default() += 1;
        self.diagnostic_examples.entry(group).or_insert_with(|| {
            let mut example = diagnostic.clone();
            example.span.start += offset;
            example.span.end += offset;
            if example.message.len() > 512 {
                example.message.truncate(512);
            }
            example
        });
        if self.diagnostics.len() < sample_limit {
            diagnostic.span.start += offset;
            diagnostic.span.end += offset;
            if diagnostic.message.len() > 512 {
                diagnostic.message.truncate(512);
            }
            self.diagnostics.push(diagnostic);
        }
    }

    fn parse_chunk(&mut self, source: &str, offset: usize, sample_limit: usize) {
        if source.trim().is_empty() {
            return;
        }
        let ast = parse(source);
        self.parsed_chunks += 1;
        self.parsed_bytes += source.len();
        for diagnostic in ast.diagnostics {
            self.diagnostic(diagnostic, offset, sample_limit);
        }
        for item in &ast.items {
            self.visit_item(item, offset, sample_limit);
        }
    }

    fn visit_item(&mut self, item: &Item, offset: usize, sample_limit: usize) {
        self.items += 1;
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            self.procedures += 1;
            let body = parse_proc_body(item);
            for diagnostic in body.diagnostics {
                self.diagnostic(diagnostic, offset, sample_limit);
            }
            for statement in &body.statements {
                self.visit_statement(statement);
            }
        } else {
            for child in &item.children {
                self.visit_item(child, offset, sample_limit);
            }
        }
    }

    fn visit_statement(&mut self, statement: &Statement) {
        self.statements += 1;
        match &statement.kind {
            StatementKind::Unsupported => self.unsupported_statements += 1,
            StatementKind::If {
                then_branch,
                else_branch,
                ..
            } => {
                for child in then_branch.iter().chain(else_branch) {
                    self.visit_statement(child);
                }
            }
            StatementKind::While { body, .. }
            | StatementKind::DoWhile { body, .. }
            | StatementKind::Spawn { body, .. }
            | StatementKind::For { body, .. } => {
                for child in body {
                    self.visit_statement(child);
                }
            }
            StatementKind::Switch {
                cases, else_branch, ..
            } => {
                for case in cases {
                    for child in &case.body {
                        self.visit_statement(child);
                    }
                }
                for child in else_branch {
                    self.visit_statement(child);
                }
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                for child in body.iter().chain(catch_body) {
                    self.visit_statement(child);
                }
            }
            _ => {}
        }
    }

    fn skip_oversized(&mut self, start: usize, end: usize, sample_limit: usize) {
        self.skipped_declarations += 1;
        self.skipped_bytes += end - start;
        self.diagnostic(
            Diagnostic {
                span: Span::new(start, end),
                kind: DiagnosticKind::Unsupported,
                message: "top-level declaration exceeds syntax audit chunk limit".into(),
            },
            0,
            sample_limit,
        );
    }
}

fn diagnostic_group(message: &str) -> String {
    for prefix in [
        "unexpected token in expression:",
        "unexpected expression token:",
        "unsupported expression token:",
    ] {
        if message.starts_with(prefix) {
            return prefix.into();
        }
    }
    message.chars().take(160).collect()
}

/// Parse top-level declarations in bounded chunks. A declaration larger than
/// `max_chunk_bytes` is counted and skipped instead of allowing an unbounded
/// parse. `max_diagnostics` caps retained samples, not the diagnostic count.
/// 256 KiB chunks are suitable for repository-wide audits.
pub fn audit_source_streaming(
    source: &str,
    max_chunk_bytes: usize,
    max_diagnostics: usize,
) -> StreamingAudit {
    let limit = max_chunk_bytes.max(1);
    let mut result = StreamingAudit::default();
    let mut chunk_start = 0usize;
    let mut chunk_end = 0usize;
    let mut declaration_start = 0usize;
    let mut on_boundary = |boundary: usize| {
        if boundary <= declaration_start {
            return;
        }
        let segment_len = boundary - declaration_start;
        if segment_len > limit {
            if chunk_end > chunk_start {
                result.parse_chunk(
                    &source[chunk_start..chunk_end],
                    chunk_start,
                    max_diagnostics,
                );
            }
            result.skip_oversized(declaration_start, boundary, max_diagnostics);
            chunk_start = boundary;
            chunk_end = boundary;
        } else {
            if chunk_end > chunk_start && boundary - chunk_start > limit {
                result.parse_chunk(
                    &source[chunk_start..chunk_end],
                    chunk_start,
                    max_diagnostics,
                );
                chunk_start = declaration_start;
            }
            chunk_end = boundary;
        }
        declaration_start = boundary;
    };
    for_each_top_level_boundary(source, &mut on_boundary);
    on_boundary(source.len());
    if chunk_end > chunk_start {
        result.parse_chunk(
            &source[chunk_start..chunk_end],
            chunk_start,
            max_diagnostics,
        );
    }
    result
}

fn for_each_top_level_boundary(source: &str, mut visit: impl FnMut(usize)) {
    let _ = crate::boundary_scan::scan_top_level_boundaries::<()>(
        source,
        crate::boundary_scan::BoundaryCheckpoint::default(),
        |checkpoint| {
            visit(checkpoint.offset());
            std::ops::ControlFlow::Continue(())
        },
    )
    .expect("initial joined-stream boundary checkpoint is valid");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_procs_without_retaining_project_ast() {
        let source = "/proc/a()\n    return 1\n/proc/b()\n    return 2\n/proc/c()\n    return 3\n";
        let audit = audit_source_streaming(source, 25, 5);
        assert_eq!(audit.procedures, 3);
        assert_eq!(audit.statements, 3);
        assert_eq!(audit.parsed_chunks, 3);
        assert_eq!(audit.parsed_bytes, source.len());
        assert_eq!(audit.skipped_declarations, 0);
    }

    #[test]
    fn oversized_declaration_is_skipped_and_diagnostics_capped() {
        let source = format!(
            "/proc/big()\n    return \"{}\"\n/proc/small()\n    return 2\n",
            "x".repeat(200)
        );
        let audit = audit_source_streaming(&source, 80, 1);
        assert_eq!(audit.skipped_declarations, 1);
        assert_eq!(audit.procedures, 1);
        assert_eq!(audit.diagnostic_count, 1, "{audit:?}");
        assert_eq!(audit.diagnostics.len(), 1);
    }

    #[test]
    fn block_string_and_nested_comment_do_not_split_chunks() {
        let source = "/proc/a()\n    var/text = {\"line\n/proc/not_real()\nend\"}\n/* outer /* inner */ still comment\n/proc/not_real_either()\n*/\n/proc/b()\n    return 2\n";
        let audit = audit_source_streaming(source, 256, 5);
        assert_eq!(audit.procedures, 2);
        assert_eq!(audit.skipped_declarations, 0);
    }

    #[test]
    fn callback_chunks_and_reparses_proc_at_absolute_span() {
        let source = "/proc/a()\n    return 1\n/proc/b()\n    return 2\n";
        let mut spans = Vec::new();
        let report = for_each_parsed_chunk(source, 25, |ast, offset| {
            for item in &ast.items {
                spans.push(Span::new(item.span.start + offset, item.span.end + offset));
            }
        });
        assert_eq!(report.parsed_chunks, 2);
        assert_eq!(report.skipped_declarations, 0);
        let proc_b = parse_proc_at_span(source, spans[1]).unwrap();
        assert_eq!(proc_b.header, "/proc/b()");
        assert_eq!(proc_b.span, spans[1]);
        assert_eq!(proc_b.children[0].header, "return 2");
        assert!(proc_b.children[0].span.start > spans[1].start);
    }

    #[test]
    fn reparses_implicit_override_from_nested_type() {
        let source = "/datum/example\n    run()\n        return 7\n";
        let ast = parse(source);
        let original = &ast.items[0].children[0];
        assert_eq!(original.kind, ItemKind::Proc);
        let reparsed = parse_proc_at_span(source, original.span).unwrap();
        assert_eq!(reparsed.span, original.span);
        assert_eq!(reparsed.header, "run()");
        assert_eq!(reparsed.children[0].header, "return 7");
    }

    #[test]
    fn raw_block_string_does_not_create_declaration_boundary() {
        let source = "/proc/a()\n    var/text = @{\"line\n/proc/not_real()\nend\"}\n/proc/b()\n    return 2\n";
        let audit = audit_source_streaming(source, 256, 5);
        assert_eq!(audit.procedures, 2);
        assert_eq!(audit.skipped_declarations, 0);
    }

    #[test]
    fn raw_inline_regex_preserves_following_chunk_boundaries() {
        let source = r#"/proc/om_is_handle(h)
    var/static/regex/shape = regex(@"^(\d+:\d+|\[0x[0-9a-fA-F]+\](#\d+)?|@\w+)$")
    return shape
/mob/dview
    anchored = 1
/atom/movable
    var/anchored = 0
"#;
        let mut headers = Vec::new();
        let report = for_each_source_chunk_with_limits(source, 64, source.len(), |chunk, _| {
            let ast = parse(chunk);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            headers.extend(ast.items.into_iter().map(|item| item.header));
        });
        assert_eq!(report.skipped_declarations, 0);
        assert_eq!(
            headers,
            ["/proc/om_is_handle(h)", "/mob/dview", "/atom/movable"]
        );
    }

    #[test]
    fn column_zero_lines_inside_macro_proc_and_call_do_not_split_chunks() {
        let source = "/datum/globals/var/list/x; /datum/globals/proc/InitX(){x =list(\nNORTHEAST,\nNORTHWEST\n); order += \"x\";}\n/proc/next()\n    return 2\n";
        let mut starts = Vec::new();
        let report = for_each_parsed_chunk(source, 105, |ast, offset| {
            starts.push(offset);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        });
        assert_eq!(report.skipped_declarations, 0, "{report:?}");
        assert_eq!(starts.len(), 2, "{starts:?}");
        assert_eq!(starts[1], source.find("/proc/next()").unwrap());
    }

    #[test]
    fn include_footprint_absolute_declaration_is_chunk_boundary() {
        let source = "/proc/a()\n    return 1\n                                        /var/from_include\n/proc/b()\n    return 2\n";
        let mut boundaries = Vec::new();
        for_each_top_level_boundary(source, |offset| boundaries.push(offset));
        assert!(boundaries.contains(&source.find("/var/from_include").unwrap()));
        let report = for_each_parsed_chunk(source, 100, |_, _| {});
        assert_eq!(report.skipped_declarations, 0);
        assert_eq!(report.parsed_chunks, 2);
    }

    #[test]
    fn dynamic_diagnostics_share_a_bounded_group() {
        let mut audit = StreamingAudit::default();
        for index in 0..300 {
            audit.diagnostic(
                Diagnostic {
                    span: Span::new(0, 1),
                    kind: DiagnosticKind::Expression,
                    message: format!("unexpected token in expression: {index}"),
                },
                0,
                2,
            );
        }
        assert_eq!(audit.diagnostic_count, 300);
        assert_eq!(audit.diagnostics.len(), 2);
        assert_eq!(
            audit.diagnostic_groups["unexpected token in expression:"],
            300
        );
        assert_eq!(audit.diagnostic_examples.len(), 1);
        assert_eq!(
            audit.diagnostic_examples["unexpected token in expression:"]
                .span
                .start,
            0
        );
    }
}

#[cfg(test)]
mod ascii_scan_tests {
    use super::*;
    use crate::{boundary_scan::after_token_line_start, quoted_end};
    fn reference_boundaries(source: &str, mut visit: impl FnMut(usize)) {
        let mut at_line_start = true;
        let mut indented = false;
        let mut delimiter_depth = 0usize;
        let mut pos = 0usize;
        while pos < source.len() {
            let rest = &source[pos..];
            if rest.starts_with("//") {
                pos += rest.find('\n').unwrap_or(rest.len());
                continue;
            }
            if rest.starts_with("/*") {
                let mut depth = 1usize;
                let mut cursor = 2usize;
                while depth > 0 && cursor + 1 < rest.len() {
                    if rest[cursor..].starts_with("/*") {
                        depth += 1;
                        cursor += 2;
                    } else if rest[cursor..].starts_with("*/") {
                        depth -= 1;
                        cursor += 2;
                    } else {
                        cursor += rest[cursor..].chars().next().unwrap().len_utf8();
                    }
                }
                let end = if depth == 0 { cursor } else { rest.len() };
                (at_line_start, indented) =
                    after_token_line_start(&rest[..end], at_line_start, indented, true);
                pos += end;
                continue;
            }
            let string = if rest.starts_with("@{\"") {
                quoted_end(&rest[1..], true, true).map(|end| end + 1)
            } else if rest.starts_with("{\"") {
                quoted_end(rest, true, false)
            } else if rest.starts_with("@\"") {
                quoted_end(&rest[1..], false, true).map(|end| end + 1)
            } else if rest.starts_with('"') {
                quoted_end(rest, false, false)
            } else {
                None
            };
            if let Some(end) = string {
                (at_line_start, indented) =
                    after_token_line_start(&rest[..end], at_line_start, indented, false);
                pos += end;
                continue;
            }
            if rest.starts_with('\'') {
                let mut escaped = false;
                let mut end = rest.len();
                for (at, ch) in rest.char_indices().skip(1) {
                    if escaped {
                        escaped = false;
                    } else if ch == '\\' {
                        escaped = true;
                    } else if ch == '\'' {
                        end = at + 1;
                        break;
                    }
                }
                (at_line_start, indented) =
                    after_token_line_start(&rest[..end], at_line_start, indented, false);
                pos += end;
                continue;
            }
            let ch = rest.chars().next().unwrap();
            if ch == '\n' {
                at_line_start = true;
                indented = false;
            } else if matches!(ch, ' ' | '\t') && at_line_start {
                indented = true;
            } else if !matches!(ch, ' ' | '\t' | '\r') {
                // Expanded #include directives can leave spaces before the first
                // absolute declaration path of an included file.
                if at_line_start && delimiter_depth == 0 && (!indented || ch == '/')
                    && !(indented&&ch=='/'&&crate::boundary_scan::indented_prefab_initializer(source,pos)) {
                    visit(pos);
                }
                at_line_start = false;
            }
            match ch {
                '(' | '[' | '{' => delimiter_depth += 1,
                ')' | ']' | '}' => delimiter_depth = delimiter_depth.saturating_sub(1),
                _ => {}
            }
            pos += ch.len_utf8();
        }
    }

    #[test]
    fn ascii_boundary_scan_matches_character_reference() {
        for source in [
        "/datum/a\n    proc/f()\n        return call(\n/datum/not_boundary,\n        1)\n/datum/b\n",
        "/datum/日本\n    var/text = {\"line\n/obj/not_boundary\n\"}\n /obj/next\n",
        "/* outer\n/* inner */\n*/ /obj/a\n// /obj/comment\n/obj/b\n",
        "/datum/a\n    var/x = \"outer [call(\"nested [1]\")]\"\n/obj/b\n",
        "/datum/a\n    var/x = 'icons/日本.dmi'\n/obj/b\n",
        "/datum/a\n    var/x = @{\"raw \\text\n/obj/inside\"}\n/obj/b\n",
    ] {
        for end in (0..=source.len()).filter(|end| source.is_char_boundary(*end)) {
            let prefix = &source[..end];
            let mut expected = Vec::new();
            reference_boundaries(prefix, |offset| expected.push(offset));
            let mut actual = Vec::new();
            for_each_top_level_boundary(prefix, |offset| actual.push(offset));
            assert_eq!(actual, expected, "{prefix:?}");
        }
    }
    }
}

#[cfg(test)]
mod native_structural_consumption_controls{
 use super::*;
 #[test]fn native_consumption_comes_from_actual_mask_layout_and_level_exhaustion(){
  for(source,expected)in[
   ("/proc/p()\n    return 1\n",true),
   ("/proc/p() { return 1; }\n",true),
   ("/proc/p() { return 1;\n",false),
   ("/proc/p()\n    return 1\n}\n",false),
  ]{
   let tokens=crate::lex_spans(source);
   assert!(tokens.diagnostics.is_empty());
   let(parsed,complete)=parse_proc_with_native_consumption_from_window(source,Span::new(0,source.len()),crate::TokenWindow::from_slice(&tokens.tokens),0,None,false,None,None);
   assert_eq!(complete&&parsed.is_ok(),expected,"{source}: native successful consumption, not a span-length EOF");
  }
 }
}

#[cfg(test)]
#[path="canonical_primary_allocation_controls.rs"]mod canonical_primary_allocation_controls;
