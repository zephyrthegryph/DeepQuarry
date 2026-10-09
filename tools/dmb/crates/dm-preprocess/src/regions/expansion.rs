use super::*;
use crate::{expand_traced, DiagnosticKind, ExpandLocation};
use dm_syntax::{lex_spans, SpanToken};
use std::borrow::Cow;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

#[derive(Clone, Debug, Default)]
pub struct ExpandedRegions {
    pub text: crate::SourceText,
    /// Lex the joined stream once: declarations and expressions may cross
    /// include boundaries and cannot be parsed as independent file programs.
    pub tokens: Vec<SpanToken>,
    pub origins: ExpandedOriginArena,
    /// Declaration ordering projection; grammar is always parsed in encounter order.
    pub emission_regions: Vec<usize>,
    pub diagnostics: Vec<Diagnostic>,
    pub receipts: Vec<region_memo::RegionReceipt>,
    pub lexical_diagnostics: Vec<dm_syntax::Diagnostic>,
}

pub(super) struct RegionOutput {
    pub(super) text: crate::SourceText,
    pub(super) receipt: Option<Arc<region_memo::ExpansionRecord>>,
    pub(super) lines: output_lines::OutputLines,
    pub(super) diagnostics: Vec<Diagnostic>,
}

/// Freeze directive state first, then expand independent regions in a bounded
/// scoped pool. Completion order never determines emission or diagnostics order.
pub fn expand_regions(plan: &DirectivePlan, workers: usize) -> ExpandedRegions {
    expand_regions_with_executor(
        plan,
        &dm_exec::BuildExecutor::new(workers).expect("expansion executor creation failed"),
    )
}

/// Large cold frontends lex bounded declaration chunks themselves. Retaining
/// millions of whole-project lexical spans would defeat the source arena model.
pub fn expand_regions_text(plan: &DirectivePlan, workers: usize) -> ExpandedRegions {
    expand_regions_text_with_executor(
        plan,
        &dm_exec::BuildExecutor::new(workers).expect("expansion executor creation failed"),
        None,
    )
}

pub fn expand_regions_text_with_memo(
    plan: &DirectivePlan,
    workers: usize,
    memo: &dyn region_memo::ExpansionMemo,
) -> ExpandedRegions {
    expand_regions_text_with_executor(
        plan,
        &dm_exec::BuildExecutor::new(workers).expect("expansion executor creation failed"),
        Some(memo),
    )
}
/// Expand on the build's shared workers without creating another pool.
pub fn expand_regions_with_executor(
    plan: &DirectivePlan,
    executor: &dm_exec::BuildExecutor,
) -> ExpandedRegions {
    expand_regions_inner(plan, executor, true, None)
}

/// Expand text with optional memo reuse on the explicitly supplied executor.
pub fn expand_regions_text_with_executor(
    plan: &DirectivePlan,
    executor: &dm_exec::BuildExecutor,
    memo: Option<&dyn region_memo::ExpansionMemo>,
) -> ExpandedRegions {
    expand_regions_inner(plan, executor, false, memo)
}

fn expand_regions_inner(
    plan: &DirectivePlan,
    executor: &dm_exec::BuildExecutor,
    retain_tokens: bool,
    memo: Option<&dyn region_memo::ExpansionMemo>,
) -> ExpandedRegions {
    if let Some(admissions) = memo.and_then(|memo| memo.input_admissions()) {
        admissions.retain_current(plan);
    }
    let count = plan.regions.len();
    let worker_count = executor.workers().min(count.max(1));
    let outputs = if worker_count == 1 {
        (0..count)
            .map(|index| match memo {
                Some(memo) => region_memo::expand(plan, index, memo),
                None => expand_region(plan, index, None),
            })
            .collect()
    } else {
        let next = AtomicUsize::new(0);
        let outputs = Mutex::new((0..count).map(|_| None).collect::<Vec<_>>());
        executor.scope(|scope| {
            for _ in 0..worker_count {
                let next = &next;
                let outputs = &outputs;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("frontend.expansion");
                    loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        if index >= count {
                            break;
                        }
                        let output = match memo {
                            Some(memo) => region_memo::expand(plan, index, memo),
                            None => expand_region(plan, index, None),
                        };
                        outputs.lock().expect("expansion output lock poisoned")[index] =
                            Some(output);
                    }
                });
            }
        });
        outputs
            .into_inner()
            .expect("expansion output lock poisoned")
            .into_iter()
            .map(|output| output.expect("every assigned region has one expansion result"))
            .collect::<Vec<_>>()
    };
    let mut diagnostics = plan
        .diagnostics
        .iter()
        .cloned()
        .zip(plan.diagnostic_ordinals.iter().copied())
        .map(|(diagnostic, ordinal)| (ordinal, diagnostic.line, diagnostic))
        .collect::<Vec<_>>();
    for (index, output) in outputs.iter().enumerate() {
        diagnostics.extend(output.diagnostics.iter().cloned().map(|diagnostic| {
            (
                plan.regions[index].encounter_ordinal,
                diagnostic.line,
                diagnostic,
            )
        }));
    }
    diagnostics.sort_by_key(|(ordinal, line, _)| (*ordinal, *line));
    let text_capacity = outputs.iter().map(|output| output.text.len()).sum();
    let origin_capacity = outputs.iter().map(|output| output.lines.len()).sum();
    let mut text = String::with_capacity(text_capacity);
    let mut result = ExpandedRegions {
        origins: ExpandedOriginArena::default(),
        diagnostics: diagnostics
            .into_iter()
            .map(|(_, _, diagnostic)| diagnostic)
            .collect(),
        emission_regions: plan.emission_regions().collect(),
        ..ExpandedRegions::default()
    };
    let mut origins = super::origin_arena::OriginArenaBuilder::with_capacity(origin_capacity);
    let mut outputs: Vec<_> = outputs.into_iter().map(Some).collect();
    // Grammar context crosses include boundaries, including DME type headers.
    // Deferred declaration ordering is a separate tree/link projection.
    for item in &plan.items {
        let OrderedItem::Text(index) = item else {
            continue;
        };
        let region = &plan.regions[*index];
        let output = outputs[*index]
            .take()
            .expect("a text region is emitted once");
        let path = plan.occurrences[region.occurrence].path.clone();
        let output_start = text.len();
        text.push_str(&output.text);
        if let Some(record) = output.receipt {
            result.receipts.push(region_memo::RegionReceipt {
                region: *index,
                output: Span::new(output_start, text.len()),
                record,
            });
        }
        for (relative_span, source_line, source_span, macro_expansions) in output.lines {
            origins.push(ExpandedOrigin {
                origin: Origin {
                    output_line: origins.len() + 1,
                    path: path.clone(),
                    source_line,
                },
                output_span: Span::new(
                    output_start + relative_span.start,
                    output_start + relative_span.end,
                ),
                source_span,
                region: *index,
                macro_expansions,
            });
        }
    }
    result.origins = origins.finish();
    result.text = text.into();
    if retain_tokens {
        let lexed = lex_spans(&result.text);
        result.tokens = lexed.tokens;
        result.lexical_diagnostics = lexed.diagnostics;
    }
    result
}

pub(super) fn expand_region(
    plan: &DirectivePlan,
    index: usize,
    recorder: Option<&region_memo::Recorder>,
) -> RegionOutput {
    let region = &plan.regions[index];
    let file_name = plan.semantic_path(region.occurrence);
    let mut text_buffer = String::new();
    let mut diagnostics = Vec::new();
    let mut lines = output_lines::OutputLineBuilder::default();
    let mut input = 0;
    let mut trace_arena = super::trace_arena::TraceArena::default();
    for (segment_index, segment) in region.segments.iter().enumerate() {
        for line in &segment.lines {
            let mut macro_expansions = Vec::new();
            let mut trace = |name: &str, invocation_span: Span, chain: &[&str]| {
                macro_expansions.push(MacroExpansion {
                    name: trace_arena.name(name),
                    invocation_span,
                    replacement_chain: trace_arena.chain(chain),
                    definition: segment.macros.definition_origin(name).cloned(),
                });
            };
            let recording = recorder.map(|recorder| region_memo::RecordingLookup {
                env: &segment.macros,
                recorder,
                segment: segment_index,
                input,
            });
            input += 1;
            let lookup: &dyn crate::MacroLookup = recording
                .as_ref()
                .map_or(&segment.macros as &dyn crate::MacroLookup, |lookup| lookup);
            let source = line.text.trim_end_matches(['\r', '\n']);
            // Empty indentation cannot contain a macro, interpolation, lexical
            // error or traced invocation. Keep the original source slice instead
            // of lexing and copying it; recorder input ordinals still advance.
            let text = if source.bytes().all(|byte| matches!(byte, b' ' | b'\t')) {
                Cow::Borrowed(source)
            } else {
                match expand_traced(
                    source,
                    lookup,
                    ExpandLocation {
                        file_name: &file_name,
                        line: line.source_line,
                    },
                    &mut trace,
                ) {
                    Ok(text) => Cow::Owned(text),
                    Err(message) => {
                        diagnostics.push(Diagnostic {
                            path: plan.occurrences[region.occurrence].path.as_ref().clone(),
                            line: line.source_line,
                            kind: DiagnosticKind::Macro,
                            message,
                        });
                        Cow::Borrowed(source)
                    }
                }
            };
            // Traces survive through analysis and lowering. Release growth
            // slack before publishing immutable backing shared by emitted lines.
            let macro_expansions = trace_arena.freeze_expansions(macro_expansions);
            // The terminal separator is not another emitted line. Interior
            // empty lines are source content, including inside block strings.
            for part in text.strip_suffix('\n').unwrap_or(&text).split('\n') {
                let start = text_buffer.len();
                text_buffer.push_str(part);
                text_buffer.push('\n');
                lines.push((
                    Span::new(start, text_buffer.len()),
                    line.source_line,
                    line.source_span,
                    macro_expansions.clone(),
                ));
            }
        }
    }
    RegionOutput {
        text: text_buffer.into(),
        receipt: None,
        lines: lines.finish(),
        diagnostics,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Memory(BTreeMap<PathBuf, String>);
    impl SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.0.get(path).cloned().ok_or_else(|| "missing".into())
        }
    }
    #[test]
    fn indentation_only_lines_match_full_expansion_and_preserve_origins() {
        let provider = Memory(
            [(
                PathBuf::from("project.dme"),
                "#define VALUE 9\n\n \t\nvar/value = VALUE\n\t\n".into(),
            )]
            .into_iter()
            .collect(),
        );
        let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
        let mut blank_count = 0;
        for (index, region) in plan.regions.iter().enumerate() {
            let output = expand_region(&plan, index, None);
            let mut expected = String::new();
            let mut origins = Vec::new();
            let mut traces = Vec::new();
            for segment in &region.segments {
                for line in &segment.lines {
                    let source = line.text.trim_end_matches(['\r', '\n']);
                    if source.bytes().all(|byte| matches!(byte, b' ' | b'\t')) {
                        blank_count += 1;
                    }
                    let mut trace = Vec::new();
                    let text = expand_traced(
                        source,
                        &segment.macros,
                        ExpandLocation {
                            file_name: &plan.semantic_path(region.occurrence),
                            line: line.source_line,
                        },
                        &mut |name, invocation_span, chain| {
                            trace.push(MacroExpansion {
                                name: Arc::from(name),
                                invocation_span,
                                replacement_chain: chain
                                    .iter()
                                    .map(|name| Arc::from(*name))
                                    .collect(),
                                definition: segment.macros.definition_origin(name).cloned(),
                            });
                        },
                    )
                    .unwrap();
                    for part in text.strip_suffix('\n').unwrap_or(&text).split('\n') {
                        let start = expected.len();
                        expected.push_str(part);
                        expected.push('\n');
                        origins.push((
                            Span::new(start, expected.len()),
                            line.source_line,
                            line.source_span,
                        ));
                        traces.push(format!("{trace:?}"));
                    }
                }
            }
            assert_eq!(output.text.as_str(), expected);
            assert!(output.diagnostics.is_empty());
            assert_eq!(
                output
                    .lines
                    .iter()
                    .map(|(_, _, _, trace)| format!("{trace:?}"))
                    .collect::<Vec<_>>(),
                traces,
            );
            assert_eq!(
                output
                    .lines
                    .iter()
                    .map(|(span, line, source, _)| (span, line, source))
                    .collect::<Vec<_>>(),
                origins
            );
        }
        assert!(blank_count > 0);
    }
    #[test]
    fn contiguous_regions_preserve_line_origins_and_macro_chains() {
        let provider = Memory(
            [
                (
                    PathBuf::from("project.dme"),
                    "#define VALUE 1\nvar/root = VALUE\n#include \"child.dm\"\nvar/tail = VALUE\n"
                        .into(),
                ),
                (
                    PathBuf::from("child.dm"),
                    "#define VALUE 7\nvar/text = {\"alpha\nomega\"}\nvar/child = VALUE\n".into(),
                ),
            ]
            .into_iter()
            .collect(),
        );
        let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
        let serial = expand_regions_text(&plan, 1);
        assert!(serial.diagnostics.is_empty());
        assert_eq!(
            serial.text.as_ref(),
            "var/root = 1\nvar/text = {\"alpha\nomega\"}\nvar/child = 7\nvar/tail = 7\n"
        );
        assert_eq!(
            serial
                .origins
                .iter()
                .map(|origin| origin.origin.source_line)
                .collect::<Vec<_>>(),
            vec![2, 2, 2, 4, 4]
        );
        let mut offset = 0;
        for origin in &serial.origins {
            assert_eq!(origin.output_span.start, offset);
            let emitted = &serial.text[origin.output_span.range()];
            assert!(emitted.ends_with('\n'));
            assert_eq!(emitted.bytes().filter(|byte| *byte == b'\n').count(), 1);
            offset = origin.output_span.end;
        }
        assert_eq!(offset, serial.text.len());
        assert_eq!(
            serial.origins.get(0).unwrap().macro_expansions[0]
                .name
                .as_ref(),
            "VALUE"
        );
        assert!(Arc::ptr_eq(
            serial.origins.get(1).unwrap().macro_expansions,
            serial.origins.get(2).unwrap().macro_expansions,
        ));
        assert_eq!(
            serial.origins.get(4).unwrap().macro_expansions[0]
                .definition
                .as_ref()
                .unwrap()
                .path
                .as_path(),
            Path::new("child.dm")
        );
        let parallel = expand_regions_text(&plan, 4);
        assert_eq!(serial.text.as_ref(), parallel.text.as_ref());
        assert_eq!(
            serial
                .origins
                .iter()
                .map(|origin| (
                    origin.origin,
                    origin.output_span,
                    origin.source_span,
                    origin.region
                ))
                .collect::<Vec<_>>(),
            parallel
                .origins
                .iter()
                .map(|origin| (
                    origin.origin,
                    origin.output_span,
                    origin.source_span,
                    origin.region
                ))
                .collect::<Vec<_>>()
        );
    }
    #[test]
    fn internal_empty_block_string_line_keeps_following_source() {
        let provider = Memory(
            [(
                PathBuf::from("project.dme"),
                "var/text = {\"first\n\nlast\"}\nvar/after = 7\n/world/New()\n\t..()\n".into(),
            )]
            .into_iter()
            .collect(),
        );
        let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
        for workers in [1, 4] {
            let expanded = expand_regions_text(&plan, workers);
            assert!(expanded.diagnostics.is_empty());
            assert_eq!(
                expanded.text.as_ref(),
                provider.0[Path::new("project.dme")].as_str()
            );
            assert_eq!(expanded.origins.len(), 6);
            assert_eq!(
                &expanded.text[expanded.origins.get(1).unwrap().output_span.range()],
                "\n"
            );
            assert_eq!(
                expanded.origins.get(0).unwrap().source_span,
                expanded.origins.get(2).unwrap().source_span
            );
            assert_eq!(expanded.origins.get(3).unwrap().origin.source_line, 4);
            assert_eq!(expanded.origins.get(5).unwrap().origin.source_line, 6);
        }
    }
}

#[path = "output_lines.rs"]
pub(super) mod output_lines;
