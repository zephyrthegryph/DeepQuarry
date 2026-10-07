use super::*;
use crate::{expand_traced, DiagnosticKind, ExpandLocation};
use dm_syntax::{lex_spans, SpanToken};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

#[derive(Clone, Debug, Default)]
pub struct ExpandedRegions {
    pub text: String,
    /// Lex the joined stream once: declarations and expressions may cross
    /// include boundaries and cannot be parsed as independent file programs.
    pub tokens: Vec<SpanToken>,
    pub origins: Vec<ExpandedOrigin>,
    /// Declaration ordering projection; grammar is always parsed in encounter order.
    pub emission_regions: Vec<usize>,
    pub diagnostics: Vec<Diagnostic>,
    pub lexical_diagnostics: Vec<dm_syntax::Diagnostic>,
}

#[derive(Default)]
struct RegionOutput {
    text: String,
    lines: Vec<(Span, usize, Span, Arc<Vec<MacroExpansion>>)>,
    diagnostics: Vec<Diagnostic>,
}

/// Freeze directive state first, then expand independent regions in a bounded
/// scoped pool. Completion order never determines emission or diagnostics order.
pub fn expand_regions(plan: &DirectivePlan, workers: usize) -> ExpandedRegions {
    expand_regions_inner(plan, workers, true)
}

/// Large cold frontends lex bounded declaration chunks themselves. Retaining
/// millions of whole-project lexical spans would defeat the source arena model.
pub fn expand_regions_text(plan: &DirectivePlan, workers: usize) -> ExpandedRegions {
    expand_regions_inner(plan, workers, false)
}

fn expand_regions_inner(
    plan: &DirectivePlan,
    workers: usize,
    retain_tokens: bool,
) -> ExpandedRegions {
    let count = plan.regions.len();
    let hardware_workers = std::thread::available_parallelism().map_or(1, usize::from);
    let worker_count = workers.max(1).min(hardware_workers).min(count.max(1));
    let outputs = if worker_count == 1 {
        (0..count).map(|index| expand_region(plan, index)).collect()
    } else {
        let next = AtomicUsize::new(0);
        let outputs = Mutex::new((0..count).map(|_| None).collect::<Vec<_>>());
        std::thread::scope(|scope| {
            for _ in 0..worker_count {
                let next = &next;
                let outputs = &outputs;
                scope.spawn(move || loop {
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    if index >= count {
                        break;
                    }
                    let output = expand_region(plan, index);
                    outputs.lock().expect("expansion output lock poisoned")[index] = Some(output);
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
    let mut result = ExpandedRegions {
        text: String::with_capacity(text_capacity),
        origins: Vec::with_capacity(origin_capacity),
        diagnostics: diagnostics
            .into_iter()
            .map(|(_, _, diagnostic)| diagnostic)
            .collect(),
        emission_regions: plan.emission_regions().collect(),
        ..ExpandedRegions::default()
    };
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
        let output_start = result.text.len();
        result.text.push_str(&output.text);
        for (relative_span, source_line, source_span, macro_expansions) in output.lines {
            result.origins.push(ExpandedOrigin {
                origin: Origin {
                    output_line: result.origins.len() + 1,
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
    if retain_tokens {
        let lexed = lex_spans(&result.text);
        result.tokens = lexed.tokens;
        result.lexical_diagnostics = lexed.diagnostics;
    }
    result
}

fn expand_region(plan: &DirectivePlan, index: usize) -> RegionOutput {
    let region = &plan.regions[index];
    let file_name = plan.semantic_path(region.occurrence);
    let mut output = RegionOutput::default();
    for segment in &region.segments {
        for line in &segment.lines {
            let mut macro_expansions = Vec::new();
            let mut trace = |name: &str, invocation_span: Span, chain: &[&str]| {
                macro_expansions.push(MacroExpansion {
                    name: name.to_owned(),
                    invocation_span,
                    replacement_chain: chain.iter().map(|name| (*name).to_owned()).collect(),
                    definition: segment.macros.definition_origin(name).cloned(),
                });
            };
            let text = match expand_traced(
                line.text.trim_end_matches(['\r', '\n']),
                &segment.macros,
                ExpandLocation {
                    file_name: &file_name,
                    line: line.source_line,
                },
                &mut trace,
            ) {
                Ok(text) => text,
                Err(message) => {
                    output.diagnostics.push(Diagnostic {
                        path: plan.occurrences[region.occurrence].path.as_ref().clone(),
                        line: line.source_line,
                        kind: DiagnosticKind::Macro,
                        message,
                    });
                    line.text.trim_end_matches(['\r', '\n']).to_owned()
                }
            };
            let macro_expansions = Arc::new(macro_expansions);
            // The terminal separator is not another emitted line. Interior
            // empty lines are source content, including inside block strings.
            for part in text.strip_suffix('\n').unwrap_or(&text).split('\n') {
                let start = output.text.len();
                output.text.push_str(part);
                output.text.push('\n');
                output.lines.push((
                    Span::new(start, output.text.len()),
                    line.source_line,
                    line.source_span,
                    macro_expansions.clone(),
                ));
            }
        }
    }
    output
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
            serial.text,
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
        assert_eq!(serial.origins[0].macro_expansions[0].name, "VALUE");
        assert_eq!(
            serial.origins[4].macro_expansions[0]
                .definition
                .as_ref()
                .unwrap()
                .path
                .as_path(),
            Path::new("child.dm")
        );
        let parallel = expand_regions_text(&plan, 4);
        assert_eq!(serial.text, parallel.text);
        assert_eq!(
            serial
                .origins
                .iter()
                .map(|origin| (
                    &origin.origin,
                    origin.output_span,
                    origin.source_span,
                    origin.region
                ))
                .collect::<Vec<_>>(),
            parallel
                .origins
                .iter()
                .map(|origin| (
                    &origin.origin,
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
            assert_eq!(expanded.text, provider.0[Path::new("project.dme")]);
            assert_eq!(expanded.origins.len(), 6);
            assert_eq!(
                &expanded.text[expanded.origins[1].output_span.range()],
                "\n"
            );
            assert_eq!(
                expanded.origins[0].source_span,
                expanded.origins[2].source_span
            );
            assert_eq!(expanded.origins[3].origin.source_line, 4);
            assert_eq!(expanded.origins[5].origin.source_line, 6);
        }
    }
}
