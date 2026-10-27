use super::plan_trace::{trace_key, PassState, PlanTrace, SubtreeRecord, TraceEntry, VisitEntry};
use super::*;
use crate::{
    directive_identifier, eval_condition, macro_defined, parse_include, Conditional, DiagnosticKind,
};
use std::collections::HashMap;

pub(super) fn plan<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
) -> DirectivePlan {
    plan_with_memo(project, provider, defines, None).0
}
pub(super) fn plan_with_memo<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    memo: Option<&dyn ExpansionMemo>,
) -> (DirectivePlan, PlanReuse) {
    plan_incremental(project, provider, defines, memo, None)
}
pub(super) fn plan_incremental<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    memo: Option<&dyn ExpansionMemo>,
    previous: Option<&DirectivePlan>,
) -> (DirectivePlan, PlanReuse) {
    let previous = previous.filter(|previous| previous.trace.is_some());
    // Only the include subtrees whose files changed run again, when the provider can say which (same defines only).
    if let Some(previous) = previous.filter(|previous| &previous.defines == defines) {
        if let Some(patched) = patch::patch(provider, memo, previous) {
            return patched;
        }
    }
    let mut pass = DirectivePass::new(
        provider,
        memo,
        previous,
        canonical_path(project.parent().unwrap_or(Path::new(""))),
    );
    pass.plan.defines = defines.clone();
    for (name, replacement) in [
        ("EXCEPTION", "new /exception(message, __FILE__, __LINE__)"),
        ("REGEX_QUOTE", "regex(message, 1)"),
        ("REGEX_QUOTE_REPLACEMENT", "regex(message, 2)"),
    ] {
        pass.plan.final_macros.insert(
            name.into(),
            Macro {
                parameters: Some(vec!["message".into()]),
                variadic: false,
                replacement: replacement.into(),
            },
        );
    }
    // Pinned native spellings are initial object macros. Undef removes only
    // substitution; any remaining runtime/global meaning belongs to the resolver.
    // Install them before caller definitions; source define/undef effects then
    // apply through the same ordered environment as every other macro.
    for (name, replacement) in [
        // Exact native516.1687 #ifdef and root/datum values: native_sdk_macros/receipt.json.
        ("ANIMATION_CONTINUE", "512"),
        ("ANIMATION_END_LOOP", "16"),
        ("ANIMATION_END_NOW", "1"),
        ("ANIMATION_LINEAR_TRANSFORM", "2"),
        ("ANIMATION_PARALLEL", "4"),
        ("ANIMATION_RELATIVE", "256"),
        ("ANIMATION_SLICE", "8"),
        ("AREA_LAYER", "1"),
        ("BACKGROUND_LAYER", "20000"),
        ("BACK_EASING", "6"),
        ("BLEND_ADD", "2"),
        ("BLEND_DEFAULT", "0"),
        ("BLEND_INSET_OVERLAY", "5"),
        ("BLEND_MULTIPLY", "4"),
        ("BLEND_OVERLAY", "1"),
        ("BLEND_SUBTRACT", "3"),
        ("BOUNCE_EASING", "4"),
        ("CIRCULAR_EASING", "2"),
        ("COLORSPACE_HCY", "3"),
        ("COLORSPACE_HSL", "2"),
        ("COLORSPACE_HSV", "1"),
        ("COLORSPACE_RGB", "0"),
        ("CONTROL_FREAK_ALL", "1"),
        ("CONTROL_FREAK_MACROS", "4"),
        ("CONTROL_FREAK_SKIN", "2"),
        ("CUBIC_EASING", "3"),
        ("DM_BUILD", "1687"),
        ("DOWN", "32"),
        ("EASE_IN", "64"),
        ("EASE_OUT", "128"),
        ("EAST", "4"),
        ("EDGE_PERSPECTIVE", "2"),
        ("EFFECTS_LAYER", "5000"),
        ("ELASTIC_EASING", "5"),
        ("EYE_PERSPECTIVE", "1"),
        ("FALSE", "0"),
        ("FEMALE", "\"female\""),
        ("FILTER_COLOR_HCY", "3"),
        ("FILTER_COLOR_HSL", "2"),
        ("FILTER_COLOR_HSV", "1"),
        ("FILTER_COLOR_RGB", "0"),
        ("FILTER_OVERLAY", "1"),
        ("FILTER_UNDERLAY", "2"),
        ("FLOAT_LAYER", "(-1)"),
        ("FLOAT_PLANE", "(-32767)"),
        ("FLY_LAYER", "5"),
        ("FORWARD_STEPS", "1"),
        ("ICON_ADD", "0"),
        ("ICON_AND", "4"),
        ("ICON_MULTIPLY", "2"),
        ("ICON_OR", "5"),
        ("ICON_OVERLAY", "3"),
        ("ICON_SUBTRACT", "1"),
        ("ICON_UNDERLAY", "6"),
        ("ISOMETRIC_MAP", "1"),
        ("JSON_ALLOW_COMMENTS", "2"),
        ("JSON_PRETTY_PRINT", "1"),
        ("JSON_STRICT", "1"),
        ("JUMP_EASING", "8"),
        ("KEEP_APART", "64"),
        ("KEEP_TOGETHER", "32"),
        ("LEGACY_MOVEMENT_MODE", "0"),
        ("LINEAR_EASING", "0"),
        ("LINEAR_RAND", "2"),
        ("LONG_GLIDE", "1"),
        ("MALE", "\"male\""),
        ("MASK_INVERSE", "1"),
        ("MASK_SWAP", "2"),
        ("MATRIX_ROTATE", "5"),
        ("MATRIX_SCALE", "6"),
        ("MATRIX_TRANSLATE", "7"),
        ("MOB_LAYER", "4"),
        ("MOB_PERSPECTIVE", "0"),
        ("MOUSE_ACTIVE_POINTER", "1"),
        ("MOUSE_ARROW_POINTER", "5"),
        ("MOUSE_CROSSHAIRS_POINTER", "6"),
        ("MOUSE_DRAG_POINTER", "3"),
        ("MOUSE_DROP_POINTER", "4"),
        ("MOUSE_HAND_POINTER", "7"),
        ("MOUSE_INACTIVE_POINTER", "0"),
        ("MS_WINDOWS", "\"MS Windows\""),
        ("NEUTER", "\"neuter\""),
        ("NORMAL_RAND", "1"),
        ("NORTH", "1"),
        ("NORTHEAST", "5"),
        ("NORTHWEST", "9"),
        ("NO_CLIENT_COLOR", "16"),
        ("NO_STEPS", "0"),
        ("OBJ_LAYER", "3"),
        ("OUTLINE_SHARP", "1"),
        ("OUTLINE_SQUARE", "2"),
        ("PASS_MOUSE", "1024"),
        ("PIXEL_MOVEMENT_MODE", "2"),
        ("PIXEL_SCALE", "512"),
        ("PLANE_MASTER", "128"),
        ("PLURAL", "\"plural\""),
        ("PROFILE_AVERAGE", "4"),
        ("PROFILE_CLEAR", "2"),
        ("PROFILE_REFRESH", "0"),
        ("PROFILE_RESTART", "2"),
        ("PROFILE_START", "0"),
        ("PROFILE_STOP", "1"),
        ("QUAD_EASING", "7"),
        ("RESET_ALPHA", "4"),
        ("RESET_COLOR", "2"),
        ("RESET_TRANSFORM", "8"),
        ("SEE_BLACKNESS", "1024"),
        ("SEE_INFRA", "64"),
        ("SEE_MOBS", "4"),
        ("SEE_OBJS", "8"),
        ("SEE_PIXELS", "256"),
        ("SEE_SELF", "32"),
        ("SEE_THRU", "512"),
        ("SEE_TURFS", "16"),
        ("SIDE_MAP", "2"),
        ("SINE_EASING", "1"),
        ("SLIDE_STEPS", "2"),
        ("SOUND_MUTE", "1"),
        ("SOUND_PAUSED", "2"),
        ("SOUND_STREAM", "4"),
        ("SOUND_UPDATE", "16"),
        ("SOUTH", "2"),
        ("SOUTHEAST", "6"),
        ("SOUTHWEST", "10"),
        ("SQUARE_RAND", "3"),
        ("SYNC_STEPS", "3"),
        ("TILED_ICON_MAP", "32768"),
        ("TILE_BOUND", "256"),
        ("TILE_MOVEMENT_MODE", "1"),
        ("TILE_MOVER", "2048"),
        ("TOPDOWN_LAYER", "10000"),
        ("TOPDOWN_MAP", "0"),
        ("TRUE", "1"),
        ("TURF_LAYER", "2"),
        ("UNIFORM_RAND", "0"),
        ("UNIX", "\"UNIX\""),
        ("UP", "16"),
        ("VIS_HIDE", "128"),
        ("VIS_INHERIT_DIR", "4"),
        ("VIS_INHERIT_ICON", "1"),
        ("VIS_INHERIT_ICON_STATE", "2"),
        ("VIS_INHERIT_ID", "32"),
        ("VIS_INHERIT_LAYER", "8"),
        ("VIS_INHERIT_PLANE", "16"),
        ("VIS_UNDERLAY", "64"),
        ("WAVE_BOUNDED", "2"),
        ("WAVE_SIDEWAYS", "1"),
        ("WEST", "8"),
    ] {
        pass.plan.final_macros.insert(
            name.into(),
            Macro {
                parameters: None,
                variadic: false,
                replacement: replacement.into(),
            },
        );
    }
    for (name, replacement) in defines {
        let definition = Macro {
            parameters: None,
            variadic: false,
            replacement: replacement.clone(),
        };
        if name == "FILE_DIR" {
            pass.push_file_dir(&definition);
            pass.file_dir_origins.push(None);
        }
        pass.plan.final_macros.insert(name.clone(), definition);
    }
    for (name, definition) in &pass.plan.final_macros {
        pass.environment.insert(name, definition.clone(), None);
    }
    let occurrence = pass.occurrence(project, None, None, Span::default(), 1);
    let started = std::time::Instant::now();
    pass.visit(occurrence);
    if let Some(previous) = pass.previous {
        let started = std::time::Instant::now();
        pass.match_fresh_regions(previous);
        pass.reuse.timings.matching = started.elapsed();
    }
    // A reused subtree skipped its macro mutations; the final macros are what the environment
    // holds (the pass keeps the two in step, and the unit tests pin that).
    if pass.reuse.subtrees > 0 {
        let mut finals = BTreeMap::new();
        pass.environment
            .visit_storage(|name, _, _, definition, _| {
                finals.insert(name.to_string(), (**definition).clone());
            });
        pass.plan.final_macros = finals;
    }
    #[cfg(test)]
    {
        let mut finals = BTreeMap::new();
        pass.environment
            .visit_storage(|name, _, _, definition, _| {
                finals.insert(name.to_string(), (**definition).clone());
            });
        assert_eq!(finals, pass.plan.final_macros, "the environment and the terminal macros differ");
    }
    if std::env::var_os("DMB_TIMINGS_DETAIL").is_some_and(|value| value == "1") {
        let d = &pass.detail;
        eprintln!(
            "detail directives: total={:.3}s source={:.3}s (provider={:.3}s) context={:.3}s match={:.3}s replay={:.3}s intervals={} hits={}",
            started.elapsed().as_secs_f64(),
            d.source.as_secs_f64(),
            d.provider.as_secs_f64(),
            d.context.as_secs_f64(),
            d.matching.as_secs_f64(),
            d.replay.as_secs_f64(),
            d.intervals,
            d.hits,
        );
    }
    pass.reuse.regions = std::mem::take(&mut pass.region_map);
    pass.plan.trace = Some(Arc::new(PlanTrace::new(std::mem::take(&mut pass.trace))));
    pass.plan.input_revision = provider.revision();
    (pass.plan, pass.reuse)
}

/// Whether two regions hold the same span, effects, lines and macro environments: what an
/// expansion reads, apart from the file's identity.
fn same_region(a: &IncludeRegion, b: &IncludeRegion) -> bool {
    if a.source_span != b.source_span
        || a.manifest_source != b.manifest_source
        || a.segments.len() != b.segments.len()
        || a.effects.len() != b.effects.len()
        || (!a.effects.is_empty() && format!("{:?}", a.effects) != format!("{:?}", b.effects))
    {
        return false;
    }
    a.segments.iter().zip(b.segments.iter()).all(|(x, y)| {
        x.macros.same_bindings(&y.macros)
            && x.lines.len() == y.lines.len()
            && x.lines.iter().zip(y.lines.iter()).all(|(l, m)| {
                l.source_span == m.source_span
                    && l.source_line == m.source_line
                    && l.source_lines == m.source_lines
                    && (l.text.same_view(&m.text) || l.text.as_str() == m.text.as_str())
            })
    })
}

/// Diagnostic wall-time split of the ordered pass (DMB_TIMINGS_DETAIL=1).
#[derive(Default)]
struct PassDetail {
    source: std::time::Duration,
    provider: std::time::Duration,
    context: std::time::Duration,
    matching: std::time::Duration,
    replay: std::time::Duration,
    intervals: usize,
    hits: usize,
}

#[path = "plan_patch.rs"]
mod patch;

struct DirectivePass<'a, P> {
    provider: &'a P,
    memo: Option<&'a dyn ExpansionMemo>,
    /// The plan this pass may adopt subtrees from (it carries a trace).
    previous: Option<&'a DirectivePlan>,
    /// Per occurrence: how many occurrences of its file the pass had created before it.
    nth: Vec<u32>,
    occurrence_counts: HashMap<PathBuf, u32>,
    journal: Vec<VisitEntry>,
    dependency_log: Vec<PathBuf>,
    /// Macro names the directives read or wrote, in order (subtree records take their slice).
    tested_log: std::cell::RefCell<Vec<Arc<str>>>,
    /// How the current macro environment differs from the previous pass's at the same point: the bindings a subtree
    /// adopted from that pass must take on (`adopt_previous_inner`). Empty while the two agree.
    delta: super::environment::EnvDelta,
    /// Environments rebased under the current delta, by the environment they were made from: consecutive segments
    /// share one environment, and so do their rebased copies (a persistent map per segment would cost a path copy each).
    rebased: Vec<(MacroEnvironment, MacroEnvironment)>,
    trace: Vec<TraceEntry>,
    /// For every region created so far: the previous plan's region it copies, if any.
    region_map: Vec<Option<usize>>,
    reuse: PlanReuse,
    recording: Option<directive_memo::Recording>,
    plan: DirectivePlan,
    visited: BTreeSet<PathBuf>,
    repeatable: BTreeSet<PathBuf>,
    file_dir_definitions: Vec<Macro>,
    environment: MacroEnvironment,
    file_dir_origins: Vec<Option<DefinitionOrigin>>,
    /// Definition-site path of each file by its occurrence path's allocation: relative to the project directory, so
    /// macro traces (and the region rows that hold them) are equal in every worktree of one project.
    definition_paths: HashMap<usize, (Arc<PathBuf>, Arc<PathBuf>)>,
    // Includes splice their directives into the same encounter stream.
    conditionals: Vec<Conditional>,
    detail: PassDetail,
}

impl<'a, P: SourceProvider> DirectivePass<'a, P> {
    fn new(
        provider: &'a P,
        memo: Option<&'a dyn ExpansionMemo>,
        previous: Option<&'a DirectivePlan>,
        project_dir: PathBuf,
    ) -> Self {
        DirectivePass {
            provider,
            memo,
            previous,
            nth: Vec::new(),
            occurrence_counts: HashMap::new(),
            journal: Vec::new(),
            dependency_log: Vec::new(),
            tested_log: std::cell::RefCell::new(Vec::new()),
            delta: Default::default(),
            rebased: Vec::new(),
            trace: Vec::new(),
            region_map: Vec::new(),
            reuse: PlanReuse::default(),
            recording: None,
            plan: DirectivePlan {
                project_dir,
                ..DirectivePlan::default()
            },
            visited: BTreeSet::new(),
            repeatable: BTreeSet::new(),
            file_dir_definitions: Vec::new(),
            environment: MacroEnvironment::default(),
            file_dir_origins: Vec::new(),
            conditionals: Vec::new(),
            detail: PassDetail::default(),
            definition_paths: HashMap::new(),
        }
    }
}
impl<P: SourceProvider> DirectivePass<'_, P> {
    fn evaluate(&self, word: &str, rest: &str) -> Result<bool, String> {
        if let Some(recording) = self.recording.as_ref() {
            evaluate(
                word,
                rest,
                &Tested {
                    inner: &directive_memo::Lookup {
                        environment: &self.environment,
                        recording,
                    },
                    log: &self.tested_log,
                },
            )
        } else {
            evaluate(
                word,
                rest,
                &Tested {
                    inner: &self.environment,
                    log: &self.tested_log,
                },
            )
        }
    }
    fn tested(&self, name: &str) {
        self.tested_log.borrow_mut().push(Arc::from(name));
    }
    fn finish_recording(&mut self, region: usize, pending: &mut super::segment_lines::PendingLines) {
        self.freeze_lines(region, pending);
        if let Some(recording) = self.recording.take() {
            if let Some(memo) = self.memo {
                memo.insert_directive(Arc::new(recording.finish(&self.conditionals)));
            }
        }
    }
    fn replay_directives(
        &mut self,
        occurrence: usize,
        region: usize,
        lines: prepared_source::PreparedLines<'_>,
        record: &DirectiveRecord,
        pending: &mut super::segment_lines::PendingLines,
        recoveries: &mut BTreeSet<usize>,
    ) {
        for action in record.actions() {
            match action {
                directive_memo::Action::RecoveryDirective { input } => {
                    let line = lines.get(*input).expect("checked recovery directive index");
                    recoveries.insert(line.source_span.start);
                }
                directive_memo::Action::Text(input) => {
                    let line = lines
                        .get(*input)
                        .expect("recorded directive input outside range");
                    let _ = line;
                    pending.push(lines.offset() + *input);
                }
                directive_memo::Action::Freeze => self.freeze_lines(region, pending),
                directive_memo::Action::Multiple => {
                    self.repeatable
                        .insert(self.plan.occurrences[occurrence].path.as_ref().clone());
                }
                directive_memo::Action::Define {
                    input,
                    name,
                    definition,
                } => {
                    let line = lines
                        .get(*input)
                        .expect("recorded directive input outside range");
                    self.apply_define(
                        occurrence,
                        region,
                        line.source_span,
                        line.source_line,
                        name.clone(),
                        definition.clone(),
                    );
                }
                directive_memo::Action::Undef { name, .. } => self.apply_undef(region, name),
                directive_memo::Action::Error {
                    input,
                    kind,
                    message,
                } => self.error(
                    occurrence,
                    lines
                        .get(*input)
                        .expect("recorded directive input outside range")
                        .source_line,
                    *kind,
                    message.clone(),
                ),
                directive_memo::Action::Warning { input, message } => self.warn(
                    occurrence,
                    lines
                        .get(*input)
                        .expect("recorded directive input outside range")
                        .source_line,
                    message.clone(),
                ),
            }
        }
        self.conditionals = record.outgoing().to_vec();
    }
    fn apply_define(
        &mut self,
        occurrence: usize,
        region: usize,
        span: Span,
        source_line: usize,
        name: String,
        definition: Macro,
    ) {
        let path = self.definition_path(occurrence);
        if let Some(recording) = self.recording.as_mut() {
            recording.actions.push(directive_memo::Action::Define {
                input: recording.current,
                name: name.clone(),
                definition: definition.clone(),
            });
            recording.local.insert(name.clone());
        }
        let origin = DefinitionOrigin {
            path: path.clone(),
            source_span: span,
            source_line,
        };
        if name == "FILE_DIR"
            && definition.parameters.is_none()
            && !definition.replacement.trim().is_empty()
        {
            let path = self.push_file_dir(&definition);
            self.file_dir_origins.push(Some(origin.clone()));
            Arc::make_mut(&mut self.plan.regions[region].effects).push(
                MacroEffect::PushFileDir {
                    path,
                    definition: definition.clone(),
                },
            );
        }
        self.tested(&name);
        Arc::make_mut(&mut self.plan.regions[region].effects).push(MacroEffect::Define {
            name: name.clone(),
            definition: definition.clone(),
        });
        self.environment
            .insert(&name, definition.clone(), Some(origin));
        self.plan.final_macros.insert(name, definition);
    }
    /// Where a definition in `occurrence`'s file is reported: the file's path relative to the project directory (the
    /// absolute path when the file lies outside it). Consumers resolve it against `DirectivePlan::project_dir`.
    fn definition_path(&mut self, occurrence: usize) -> Arc<PathBuf> {
        let path = &self.plan.occurrences[occurrence].path;
        let key = Arc::as_ptr(path) as usize;
        if let Some((_, relative)) = self.definition_paths.get(&key) {
            return Arc::clone(relative);
        }
        let relative = match path.strip_prefix(&self.plan.project_dir) {
            Ok(relative) if !relative.as_os_str().is_empty() => Arc::new(relative.to_path_buf()),
            _ => Arc::clone(path),
        };
        // The occurrence path is held with its entry, so its address names it for as long as the entry lives.
        self.definition_paths.insert(key, (Arc::clone(path), Arc::clone(&relative)));
        relative
    }
    fn apply_undef(&mut self, region: usize, name: &str) {
        if let Some(recording) = self.recording.as_mut() {
            recording.actions.push(directive_memo::Action::Undef {
                input: recording.current,
                name: name.to_owned(),
            });
            recording.local.insert(name.to_owned());
            if name == "FILE_DIR" {
                recording.directory_read();
            }
        }
        self.tested(name);
        Arc::make_mut(&mut self.plan.regions[region].effects).push(MacroEffect::Undef {
            name: name.to_owned(),
        });
        self.plan.final_macros.remove(name);
        self.environment.remove(name);
        if name == "FILE_DIR" {
            self.plan.file_dirs.pop();
            self.file_dir_definitions.pop();
            self.file_dir_origins.pop();
            Arc::make_mut(&mut self.plan.regions[region].effects).push(MacroEffect::PopFileDir);
            if let Some(restored) = self.file_dir_definitions.last() {
                self.plan
                    .final_macros
                    .insert(name.to_owned(), restored.clone());
            }
            if let Some(restored) = self.file_dir_definitions.last() {
                let origin = self.file_dir_origins.last().cloned().flatten();
                self.environment.insert(name, restored.clone(), origin);
            }
        }
    }
    fn occurrence(
        &mut self,
        path: &Path,
        parent: Option<usize>,
        include_spelling: Option<&Path>,
        directive_span: Span,
        directive_line: usize,
    ) -> usize {
        let index = self.plan.occurrences.len();
        let counted = self.occurrence_counts.entry(canonical_path(path)).or_insert(0);
        self.nth.push(*counted);
        *counted += 1;
        let semantic_path = if let Some(parent) = parent {
            let parent_occurrence = &self.plan.occurrences[parent];
            // Preserve the authored include operand. Recovering it from an
            // access path can leak drive/UNC roots after host normalization.
            let relative = include_spelling.expect("child occurrence has include spelling");
            Path::new(parent_occurrence.semantic_path.as_ref())
                .parent()
                .unwrap_or(Path::new(""))
                .join(relative)
        } else {
            PathBuf::from(path.file_name().unwrap_or(path.as_os_str()))
        };
        self.plan.occurrences.push(IncludeOccurrence {
            path: Arc::new(canonical_path(path)),
            semantic_path: Arc::from(semantic_path.to_string_lossy().replace('\\', "/")),
            parent,
            directive_span,
            directive_line,
            suppressed: false,
            eof_cursor_line: None,
            eof_cursor_encounter: None,
            return_cursor: parent.and_then(|parent_occurrence| {
                let parent = &self.plan.occurrences[parent_occurrence];
                let text = self.plan.source_texts.get(parent.path.as_ref())?;
                (directive_span.start <= directive_span.end
                    && directive_span.end <= text.len()
                    && text.is_char_boundary(directive_span.start)
                    && text.is_char_boundary(directive_span.end))
                .then_some(IncludeReturnCursor {
                    parent_occurrence,
                    decoded_offset: directive_span.end,
                    directive_anchor_line: None,
                    encounter_ordinal: None,
                })
            }),
        });
        index
    }

    fn error(&mut self, occurrence: usize, line: usize, kind: DiagnosticKind, message: String) {
        let ordinal = self
            .plan
            .regions
            .iter()
            .rev()
            .find(|region| region.occurrence == occurrence)
            .map_or(self.plan.items.len(), |region| region.encounter_ordinal);
        if let Some(recording) = self.recording.as_mut() {
            recording.actions.push(directive_memo::Action::Error {
                input: recording.current,
                kind,
                message: message.clone(),
            });
        }
        self.plan.diagnostic_ordinals.push(ordinal);
        self.plan.diagnostics.push(Diagnostic {
            path: self.plan.occurrences[occurrence].path.as_ref().clone(),
            line,
            kind,
            message,
        });
    }

    /// DreamMaker prints `#warn` text as a warning and keeps compiling.
    fn warn(&mut self, occurrence: usize, line: usize, message: String) {
        if let Some(recording) = self.recording.as_mut() {
            recording.actions.push(directive_memo::Action::Warning {
                input: recording.current,
                message: message.clone(),
            });
        }
        self.plan.warnings.push(Diagnostic {
            path: self.plan.occurrences[occurrence].path.as_ref().clone(),
            line,
            kind: DiagnosticKind::UserError,
            message,
        });
    }

    fn begin_region(&mut self, occurrence: usize, start: usize) -> usize {
        let index = self.plan.regions.len();
        self.plan.regions.push(IncludeRegion {
            occurrence,
            source_span: Span::new(start, start),
            encounter_ordinal: self.plan.items.len(),
            manifest_source: self.plan.occurrences[occurrence]
                .path
                .extension()
                .is_some_and(|extension| extension.eq_ignore_ascii_case("dme")),
            segments: Arc::new(Vec::new()),
            effects: Arc::new(Vec::new()),
        });
        self.region_map.push(None);
        self.plan.items.push(OrderedItem::Text(index));
        index
    }

    fn freeze_lines(&mut self, region: usize, pending: &mut super::segment_lines::PendingLines) {
        if pending.is_empty() {
            return;
        }
        if let Some(recording) = self.recording.as_mut() {
            recording.actions.push(directive_memo::Action::Freeze);
        }
        // Every segment sees its exact full incoming environment. Persistent
        // roots and Arc bindings share unchanged entries across define epochs;
        // token-pasted names require no pruning guess and no full-table clone.
        Arc::make_mut(&mut self.plan.regions[region].segments).push(ExpansionSegment {
            lines: pending.take(),
            macros: self.environment.clone(),
        });
    }

    fn push_file_dir(&mut self, definition: &Macro) -> PathBuf {
        let path = PathBuf::from(
            definition
                .replacement
                .trim()
                .trim_matches(['"', '\''])
                .replace('\\', "/"),
        );
        self.plan.file_dirs.push(path.clone());
        self.file_dir_definitions.push(definition.clone());
        path
    }

    /// A region the pass built again (the manifest's own, between its includes) can still be a
    /// verbatim copy of the previous plan's region at the same place: the same file occurrence,
    /// the same ordinal inside it, the same span, lines and macro environments. Its expansion is
    /// then the previous one too.
    fn match_fresh_regions(&mut self, previous: &DirectivePlan) {
        let mut counts: HashMap<&Path, u32> = HashMap::new();
        let mut previous_occurrence: HashMap<u128, usize> =
            HashMap::with_capacity(previous.occurrences.len());
        for (index, occurrence) in previous.occurrences.iter().enumerate() {
            let nth = counts.entry(occurrence.path.as_path()).or_insert(0);
            previous_occurrence.insert(trace_key(occurrence.path.as_path(), *nth), index);
            *nth += 1;
        }
        let mut previous_regions: Vec<Vec<usize>> = vec![Vec::new(); previous.occurrences.len()];
        for (index, region) in previous.regions.iter().enumerate() {
            previous_regions[region.occurrence].push(index);
        }
        let mut ordinals = vec![0usize; self.plan.occurrences.len()];
        for index in 0..self.plan.regions.len() {
            let occurrence = self.plan.regions[index].occurrence;
            let ordinal = ordinals[occurrence];
            ordinals[occurrence] += 1;
            if self.region_map[index].is_some() {
                continue;
            }
            let key = trace_key(self.plan.occurrences[occurrence].path.as_path(), self.nth[occurrence]);
            let Some(&before) = previous_occurrence.get(&key) else {
                continue;
            };
            let Some(&candidate) = previous_regions[before].get(ordinal) else {
                continue;
            };
            if previous.occurrences[before].semantic_path
                == self.plan.occurrences[occurrence].semantic_path
                && same_region(&self.plan.regions[index], &previous.regions[candidate])
            {
                self.region_map[index] = Some(candidate);
                self.reuse.matched_regions += 1;
            }
        }
    }

    fn depend(&mut self, path: &Path) {
        self.plan.dependencies.insert(path.to_path_buf());
        self.dependency_log.push(path.to_path_buf());
    }
    fn snapshot(&self) -> PassState {
        PassState {
            environment: self.environment.clone(),
            conditionals: self.conditionals.clone(),
            file_dirs: self.plan.file_dirs.clone(),
            file_dir_definitions: self.file_dir_definitions.clone(),
            file_dir_origins: self.file_dir_origins.clone(),
            repeatable: self.repeatable.clone(),
        }
    }
    fn restore(&mut self, state: &PassState) {
        self.environment = state.environment.clone();
        self.conditionals = state.conditionals.clone();
        self.plan.file_dirs = state.file_dirs.clone();
        self.file_dir_definitions = state.file_dir_definitions.clone();
        self.file_dir_origins = state.file_dir_origins.clone();
        self.repeatable = state.repeatable.clone();
    }

    /// Visit an include subtree and leave a record of it, unless it reported anything.
    fn visit_recording(&mut self, occurrence: usize) {
        let region = self.plan.regions.len();
        let item = self.plan.items.len();
        let journal = self.journal.len();
        let dependencies = self.dependency_log.len();
        let tested = self.tested_log.borrow().len();
        let diagnostics = self.plan.diagnostics.len();
        let warnings = self.plan.warnings.len();
        let state_in = self.snapshot();
        self.visit(occurrence);
        let entry = &self.plan.occurrences[occurrence];
        if entry.suppressed
            || self.plan.diagnostics.len() != diagnostics
            || self.plan.warnings.len() != warnings
            || entry.eof_cursor_line.is_none()
        {
            return;
        }
        let visits = self.journal[journal..].to_vec();
        let reads = visits
            .iter()
            .filter(|visit| visit.proceeded)
            .map(|visit| Arc::clone(&visit.path))
            .collect();
        let record = SubtreeRecord {
            occurrences: self.plan.occurrences.len() - occurrence,
            regions: self.plan.regions.len() - region,
            items: self.plan.items.len() - item,
            state_in,
            state_out: self.snapshot(),
            root_semantic_path: Arc::clone(&entry.semantic_path),
            visits,
            reads,
            dependencies: self.dependency_log[dependencies..].to_vec(),
            tested: {
                let mut names = self.tested_log.borrow()[tested..].to_vec();
                names.sort();
                names.dedup();
                names.into()
            },
        };
        self.trace.push(TraceEntry {
            key: trace_key(entry.path.as_ref(), self.nth[occurrence]),
            occurrence,
            region,
            item,
            record: Arc::new(record),
        });
    }

    /// Whether the current environment is the previous pass's `before` plus the carried delta, updating the delta when
    /// it is not (a subtree that ran again changed what differs). At most a few dozen bindings may differ.
    /// `environment` with the current delta applied, shared with every earlier rebase of the same environment.
    fn rebase(&mut self, environment: &MacroEnvironment) -> MacroEnvironment {
        if let Some((_, rebased)) = self.rebased.iter().find(|(from, _)| from.shares_storage_with(environment)) {
            return rebased.clone();
        }
        let rebased = environment.apply(&self.delta);
        if self.rebased.len() >= 16 {
            self.rebased.remove(0);
        }
        self.rebased.push((environment.clone(), rebased.clone()));
        rebased
    }
    fn carried_delta(&mut self, current: &MacroEnvironment, before: &MacroEnvironment) -> bool {
        const LIMIT: usize = 64;
        if self.delta.is_empty() && current.same_bindings(before) {
            return true;
        }
        if !self.delta.is_empty() && before.apply(&self.delta).same_bindings(current) {
            return true;
        }
        match current.delta_from(before, LIMIT) {
            Some(delta) => {
                self.delta = delta;
                self.rebased.clear();
                true
            }
            None => false,
        }
    }
    /// Adopt the previous plan's subtree for this include when everything it depends on is
    /// unchanged: the same files with the same text, the same incoming state, the same include
    /// context and the same include-once decisions. Returns whether it did.
    fn adopt_previous(&mut self, occurrence: usize) -> bool {
        let started = std::time::Instant::now();
        let adopted = self.adopt_previous_inner(occurrence);
        self.reuse.timings.adopt += started.elapsed();
        adopted
    }
    fn adopt_previous_inner(&mut self, occurrence: usize) -> bool {
        let Some(previous) = self.previous else {
            return false;
        };
        let Some(trace) = previous.trace.as_ref() else {
            return false;
        };
        let path = self.plan.occurrences[occurrence].path.clone();
        let key = trace_key(path.as_ref(), self.nth[occurrence]);
        let Some(entry) = trace.get(key).cloned() else {
            return false;
        };
        let record = Arc::clone(&entry.record);
        let context_matches = previous.occurrences.get(entry.occurrence).is_some_and(|before| {
            before.path == path
                && before.semantic_path == self.plan.occurrences[occurrence].semantic_path
                && before.semantic_path == record.root_semantic_path
        });
        if !context_matches {
            self.reuse.declined.context += 1;
            return false;
        }
        // The include-once set decides whether this visit proceeds at all.
        if self.visited.contains(path.as_ref()) && !self.repeatable.contains(path.as_ref()) {
            return false;
        }
        // A repeated ancestor means the bounded-recursion check may trip: interpret it.
        let mut ancestor = self.plan.occurrences[occurrence].parent;
        while let Some(parent) = ancestor {
            if self.plan.occurrences[parent].path == path {
                self.reuse.declined.context += 1;
                return false;
            }
            ancestor = self.plan.occurrences[parent].parent;
        }
        let state_started = std::time::Instant::now();
        let current = self.snapshot();
        let state_same = current.same_apart_from_macros(&record.state_in)
            && self.carried_delta(&current.environment, &record.state_in.environment)
            && !record.tested.iter().any(|name| self.delta.contains(name));
        self.reuse.timings.state += state_started.elapsed();
        if !state_same {
            self.reuse.declined.state += 1;
            return false;
        }
        let rebase = !self.delta.is_empty();
        let delta_names = rebase.then(|| self.delta.names());
        let mut seen = BTreeSet::new();
        for visit in &record.visits {
            if seen.insert(visit.path.as_ref())
                && self.visited.contains(visit.path.as_ref()) != visit.was_visited
            {
                self.reuse.declined.visits += 1;
                return false;
            }
        }
        // Same text for every file the subtree read; each is requested from the provider so the
        // caller's input capture sees the same reads a full pass makes.
        let touch_started = std::time::Instant::now();
        let mut touched = Vec::with_capacity(record.reads.len());
        for read in &record.reads {
            let Some(prepared) = self.provider.prepared_source(read) else {
                self.reuse.declined.files += 1;
                return false;
            };
            let unchanged = previous.source_texts.get(read.as_ref()).is_some_and(|old| {
                prepared.original().same_view(old) || prepared.original().as_str() == old.as_str()
            });
            if !unchanged {
                self.reuse.declined.files += 1;
                return false;
            }
            touched.push((read, prepared));
        }
        self.reuse.timings.touch += touch_started.elapsed();
        let copy_started = std::time::Instant::now();
        let occ_delta = occurrence as isize - entry.occurrence as isize;
        let region_base = self.plan.regions.len();
        let item_base = self.plan.items.len();
        let region_delta = region_base as isize - entry.region as isize;
        let item_delta = item_base as isize - entry.item as isize;
        let shift = |value: usize, delta: isize| (value as isize + delta) as usize;
        for (read, prepared) in touched {
            self.plan
                .source_line_starts
                .insert(read.as_ref().clone(), prepared.line_starts().clone());
            self.plan
                .source_texts
                .insert(read.as_ref().clone(), prepared.original().clone());
        }
        // The root was created by the include directive just handled; it takes the recorded
        // end-of-file cursor and every descendant follows it, renumbered.
        let old_root = &previous.occurrences[entry.occurrence];
        {
            let root = &mut self.plan.occurrences[occurrence];
            root.eof_cursor_line = old_root.eof_cursor_line;
            root.eof_cursor_encounter = old_root
                .eof_cursor_encounter
                .map(|encounter| shift(encounter, item_delta));
        }
        let descendants = entry.occurrence + 1..entry.occurrence + record.occurrences;
        for old in &previous.occurrences[descendants] {
            let mut copy = old.clone();
            copy.parent = copy.parent.map(|parent| shift(parent, occ_delta));
            if let Some(cursor) = &mut copy.return_cursor {
                cursor.parent_occurrence = shift(cursor.parent_occurrence, occ_delta);
                cursor.encounter_ordinal = cursor
                    .encounter_ordinal
                    .map(|ordinal| shift(ordinal, item_delta));
            }
            copy.eof_cursor_encounter = copy
                .eof_cursor_encounter
                .map(|encounter| shift(encounter, item_delta));
            // Each descendant counts as an occurrence of its file created by this pass.
            let counted = self
                .occurrence_counts
                .entry(copy.path.as_ref().clone())
                .or_insert(0);
            self.nth.push(*counted);
            *counted += 1;
            self.plan.occurrences.push(copy);
        }
        for (offset, old) in previous.regions[entry.region..entry.region + record.regions]
            .iter()
            .enumerate()
        {
            let mut copy = old.clone();
            copy.occurrence = shift(copy.occurrence, occ_delta);
            copy.encounter_ordinal = shift(copy.encounter_ordinal, item_delta);
            if rebase {
                // The subtree never read the bindings that differ: its segments see the current ones. Its expansion
                // is then proven again by the macros it reads (the expansion memo), not copied.
                copy.segments = Arc::new(
                    copy.segments
                        .iter()
                        .map(|segment| ExpansionSegment {
                            lines: segment.lines.clone(),
                            macros: self.rebase(&segment.macros),
                        })
                        .collect(),
                );
                self.reuse.rebased_regions.insert(
                    self.region_map.len(),
                    (entry.region + offset, Arc::clone(delta_names.as_ref().expect("rebased"))),
                );
                self.region_map.push(None);
            } else {
                self.region_map.push(Some(entry.region + offset));
            }
            self.plan.regions.push(copy);
        }
        for old in &previous.items[entry.item..entry.item + record.items] {
            self.plan.items.push(match old {
                OrderedItem::Text(region) => OrderedItem::Text(shift(*region, region_delta)),
                OrderedItem::NonText { occurrence, kind } => OrderedItem::NonText {
                    occurrence: shift(*occurrence, occ_delta),
                    kind: *kind,
                },
            });
        }
        for dependency in &record.dependencies {
            self.depend(dependency);
        }
        for visit in &record.visits {
            self.visited.insert(visit.path.as_ref().clone());
            self.journal.push(visit.clone());
        }
        self.restore(&record.state_out);
        if rebase {
            self.environment = self.rebase(&self.environment.clone());
            self.reuse.rebased_subtrees += 1;
        }
        self.tested_log.borrow_mut().extend(record.tested.iter().cloned());
        // Carry the subtree's records forward, renumbered, for the next pass.
        for carried in trace.within(entry.occurrence, record.occurrences) {
            // A rebased subtree's records describe its regions as copied: the carried bindings are theirs too.
            let carried_record = if rebase {
                let mut rebased = (*carried.record).clone();
                rebased.state_in.environment = self.rebase(&rebased.state_in.environment);
                rebased.state_out.environment = self.rebase(&rebased.state_out.environment);
                Arc::new(rebased)
            } else {
                Arc::clone(&carried.record)
            };
            self.trace.push(TraceEntry {
                key: carried.key,
                occurrence: shift(carried.occurrence, occ_delta),
                region: shift(carried.region, region_delta),
                item: shift(carried.item, item_delta),
                record: carried_record,
            });
        }
        self.reuse.subtrees += 1;
        self.reuse.occurrences += record.occurrences;
        self.reuse.copied_regions += record.regions;
        self.reuse.timings.copy += copy_started.elapsed();
        true
    }


    fn visit(&mut self, occurrence: usize) {
        let path = self.plan.occurrences[occurrence].path.clone();
        // Ordinary files are included once; an active #pragma multiple opts
        // this exact file path into subsequent inclusion under current macros.
        let inserted = self.visited.insert(path.as_ref().clone());
        let proceeded = inserted || self.repeatable.contains(path.as_ref());
        self.journal.push(VisitEntry {
            path: Arc::clone(&path),
            was_visited: !inserted,
            proceeded,
        });
        if !proceeded {
            self.plan.occurrences[occurrence].suppressed = true;
            return;
        }
        // Repeatable includes can recurse under macro guards. Bound only the
        // active chain, allowing finite same-file recursion without risking a
        // process stack overflow for an unguarded repeated include.
        let mut ancestor = self.plan.occurrences[occurrence].parent;
        let mut repeated_ancestors = 0;
        while let Some(parent) = ancestor {
            if self.plan.occurrences[parent].path == path {
                repeated_ancestors += 1;
            }
            if repeated_ancestors >= 64 {
                self.error(
                    occurrence,
                    1,
                    DiagnosticKind::Unsupported,
                    "repeatable include recursion exceeds 64 occurrences".into(),
                );
                return;
            }
            ancestor = self.plan.occurrences[parent].parent;
        }
        self.depend(path.as_ref());
        let source_started = std::time::Instant::now();
        let prepared = match self.provider.prepared_source(&path) {
            Some(prepared) => prepared,
            None => match self.provider.read(&path) {
                Ok(source) => prepared_source::shared_prepared(source.into()),
                Err(error) => {
                    // DreamMaker reports an unreadable include at its #include
                    // directive, naming the authored operand.
                    let current = &self.plan.occurrences[occurrence];
                    match current.parent {
                        Some(parent) => {
                            let line = current.directive_line;
                            let parent_dir =
                                Path::new(self.plan.occurrences[parent].semantic_path.as_ref())
                                    .parent()
                                    .map(Path::to_path_buf)
                                    .unwrap_or_default();
                            let semantic = PathBuf::from(current.semantic_path.as_ref());
                            let spelling = semantic
                                .strip_prefix(&parent_dir)
                                .unwrap_or(&semantic)
                                .to_string_lossy()
                                .into_owned();
                            // DreamMaker prints the operand with the host separator.
                            let spelling = if cfg!(windows) {
                                spelling.replace('/', "\\")
                            } else {
                                spelling
                            };
                            self.error(
                                parent,
                                line,
                                DiagnosticKind::Io,
                                format!("unable to open \"{spelling}\"."),
                            );
                        }
                        None => self.error(occurrence, 1, DiagnosticKind::Io, error),
                    }
                    return;
                }
            },
        };
        self.detail.provider += source_started.elapsed();
        self.plan
            .source_line_starts
            .insert(path.as_ref().clone(), prepared.line_starts().clone());
        self.plan
            .source_texts
            .insert(path.as_ref().clone(), prepared.original().clone());
        self.detail.source += source_started.elapsed();
        let mut line_number = 0;
        let mut returns = Vec::new();
        let mut recoveries = BTreeSet::new();
        let diagnostic_start = self.plan.diagnostics.len();
        let mut region = self.begin_region(occurrence, 0);
        let mut pending = super::segment_lines::PendingLines::new(Arc::clone(&prepared));
        let lines = prepared.lines();
        let mut cursor = 0;
        while cursor < lines.len() {
            if self
                .recording
                .as_ref()
                .is_some_and(|recording| recording.end == cursor)
            {
                self.finish_recording(region, &mut pending);
            }
            if self.recording.is_none() && !prepared.is_include(cursor) {
                if let Some(memo) = self.memo {
                    let end = (cursor..lines.len())
                        .find(|&index| prepared.is_include(index))
                        .unwrap_or(lines.len());
                    let context_started = std::time::Instant::now();
                    let context =
                        directive_memo::context(prepared.original(), lines.slice(cursor..end));
                    self.detail.context += context_started.elapsed();
                    self.detail.intervals += 1;
                    if let Some(context) = context {
                        let matching_started = std::time::Instant::now();
                        let mut hit = None;
                        memo.visit_directive_candidates(context.2, &mut |record| {
                            let accepted = record.matches(
                                context.0,
                                context.1,
                                end - cursor,
                                &self.environment,
                                &self.conditionals,
                                (&self.plan.file_dirs, &self.file_dir_definitions),
                            );
                            if accepted {
                                hit = Some(std::sync::Arc::clone(record));
                            }
                            accepted
                        });
                        self.detail.matching += matching_started.elapsed();
                        if let Some(record) = hit {
                            self.detail.hits += 1;
                            for name in record.read_names() {
                                self.tested_log.borrow_mut().push(Arc::clone(name));
                            }
                            let replay_started = std::time::Instant::now();
                            self.replay_directives(
                                occurrence,
                                region,
                                lines.slice(cursor..end),
                                &record,
                                &mut pending,
                                &mut recoveries,
                            );
                            self.detail.replay += replay_started.elapsed();
                            line_number += lines
                                .slice(cursor..end)
                                .iter()
                                .map(|line| line.source_lines)
                                .sum::<usize>();
                            cursor = end;
                            continue;
                        }
                        self.recording = Some(directive_memo::Recording::new(
                            cursor,
                            end,
                            context,
                            &self.conditionals,
                            &self.plan.file_dirs,
                            &self.file_dir_definitions,
                        ));
                    }
                }
            }
            if let Some(recording) = self.recording.as_mut() {
                recording.current = cursor - recording.start;
            }
            let logical = lines.get(cursor).expect("directive cursor outside source");
            cursor += 1;
            let source_line = logical.source_line;
            line_number += logical.source_lines;
            let span = logical.source_span;
            let start = span.start;
            let end = span.end;
            let active = self.conditionals.last().is_none_or(|frame| frame.active);
            let Some(syntax) = prepared.directive(cursor - 1) else {
                if active {
                    if let Some(recording) = self.recording.as_mut() {
                        recording
                            .actions
                            .push(directive_memo::Action::Text(recording.current));
                    }
                    pending.push(cursor - 1);
                }
                continue;
            };
            let (word, rest) = syntax.parts(logical.text);
            // Record only executed directive decisions in the ordinary pass;
            // retained directive replay carries the same checked line event.
            if matches!(word, "if" | "ifdef" | "ifndef" | "elif" | "else" | "endif")
                || active && matches!(word, "define" | "include")
            {
                recoveries.insert(span.start);
                if let Some(recording) = self.recording.as_mut() {
                    recording
                        .actions
                        .push(directive_memo::Action::RecoveryDirective {
                            input: recording.current,
                        });
                }
            }

            if matches!(word, "if" | "ifdef" | "ifndef" | "elif" | "else" | "endif") {
                self.conditional(occurrence, source_line, word, rest);
                continue;
            }
            if word == "include" {
                self.freeze_lines(region, &mut pending);
                self.plan.regions[region].source_span.end = start;
                if active {
                    let child = self.plan.occurrences.len();
                    self.include(occurrence, span, source_line, rest);
                    if self
                        .plan
                        .occurrences
                        .get(child)
                        .is_some_and(|entry| entry.parent == Some(occurrence))
                    {
                        // The child visit has completed. Issue the CURRENT
                        // ordered stream boundary, including suppressed includes.
                        if let Some(returned) = &mut self.plan.occurrences[child].return_cursor {
                            returned.encounter_ordinal = Some(self.plan.items.len());
                        }
                        returns.push((child, cursor));
                    }
                }
                region = self.begin_region(occurrence, end);
                continue;
            }
            if !active {
                continue;
            }
            match word {
                "define" => {
                    self.freeze_lines(region, &mut pending);
                    match syntax
                        .definition
                        .as_ref()
                        .expect("define syntax captured")
                        .clone()
                    {
                        Ok((name, definition)) => {
                            self.apply_define(
                                occurrence,
                                region,
                                span,
                                source_line,
                                name,
                                definition,
                            );
                        }
                        Err(error) => {
                            self.error(occurrence, source_line, DiagnosticKind::Macro, error)
                        }
                    }
                }
                "undef" => {
                    self.freeze_lines(region, &mut pending);
                    match syntax
                        .identifier
                        .as_ref()
                        .expect("undef syntax captured")
                        .clone()
                    {
                        Ok(name) => {
                            self.apply_undef(region, &name);
                        }
                        Err(error) => {
                            self.error(occurrence, source_line, DiagnosticKind::Macro, error)
                        }
                    }
                }
                "error" => self.error(
                    occurrence,
                    source_line,
                    DiagnosticKind::UserError,
                    rest.trim_end_matches(['\r', '\n']).into(),
                ),
                "pragma" => {
                    if rest.trim() == "multiple" {
                        self.repeatable.insert(path.as_ref().clone());
                        if let Some(recording) = self.recording.as_mut() {
                            recording.actions.push(directive_memo::Action::Multiple);
                        }
                    }
                }
                "warning" | "warn" => {
                    self.warn(occurrence, source_line, format!("#{word} {}", rest.trim()))
                }
                "" => {}
                // DreamMaker rejects a directive it does not know; one it knows
                // but the native planner does not implement stays unsupported.
                other
                    if !matches!(
                        other,
                        "define"
                            | "undef"
                            | "include"
                            | "if"
                            | "ifdef"
                            | "ifndef"
                            | "elif"
                            | "else"
                            | "endif"
                            | "error"
                            | "warn"
                            | "warning"
                            | "pragma"
                    ) =>
                {
                    self.error(
                        occurrence,
                        source_line,
                        DiagnosticKind::Directive,
                        format!("unknown directive {other}"),
                    )
                }
                other => self.error(
                    occurrence,
                    source_line,
                    DiagnosticKind::Unsupported,
                    format!("unsupported preprocessor directive #{other}"),
                ),
            }
        }
        self.freeze_lines(region, &mut pending);
        self.finish_recording(region, &mut pending);
        self.plan.regions[region].source_span.end = prepared.original().len();
        // Native accepts an active unfinished conditional at root EOF, but an
        // inactive root EOF is an error. A child EOF never closes the stack.
        if self.plan.occurrences[occurrence].parent.is_none()
            && self.conditionals.last().is_some_and(|frame| !frame.active)
        {
            self.error(
                occurrence,
                line_number + 1,
                DiagnosticKind::Conditional,
                "still skipping code at end of file (possibly an unclosed #if/#ifdef/#ifndef)"
                    .into(),
            );
        }
        // Issue recovery boundaries from the SAME completed logical-line plan.
        // An intervening omitted directive leaves BYOND's recovery cursor on
        // the originating include site (pinned include_return_diagnostics).
        // Unexpanded ordinary text cannot certify this progression.
        for (child, after) in returns {
            let anchor = (after..lines.len())
                .find_map(|index| {
                    let line = lines.get(index)?;
                    (!line.text.trim().is_empty()).then_some(index)
                })
                .and_then(|index| {
                    let line = lines.get(index)?;
                    (self.plan.diagnostics.len() == diagnostic_start
                        && recoveries.contains(&line.source_span.start))
                    .then_some(self.plan.occurrences[child].directive_line)
                });
            if let Some(cursor) = &mut self.plan.occurrences[child].return_cursor {
                cursor.directive_anchor_line = anchor;
            }
        }
        if self.plan.diagnostics.len() == diagnostic_start {
            self.plan.occurrences[occurrence].eof_cursor_line = line_number.checked_add(1);
            self.plan.occurrences[occurrence].eof_cursor_encounter = Some(self.plan.items.len());
        }
    }

    fn include(&mut self, parent: usize, span: Span, line: usize, rest: &str) {
        let Some(relative) = parse_include(rest) else {
            self.error(
                parent,
                line,
                DiagnosticKind::Include,
                "expected quoted #include path".into(),
            );
            return;
        };
        let child = self.plan.occurrences[parent]
            .path
            .parent()
            .unwrap_or(Path::new(""))
            .join(&relative);
        let created = std::time::Instant::now();
        let occurrence = self.occurrence(&child, Some(parent), Some(&relative), span, line);
        self.reuse.timings.occurrences += created.elapsed();
        let kind = match child.extension().and_then(|extension| extension.to_str()) {
            Some(extension) if extension.eq_ignore_ascii_case("dmm") => Some(NonTextKind::Map),
            Some(extension) if extension.eq_ignore_ascii_case("dmf") => Some(NonTextKind::Skin),
            Some(extension)
                if extension.eq_ignore_ascii_case("dm")
                    || extension.eq_ignore_ascii_case("dme") =>
            {
                None
            }
            _ => {
                self.error(
                    parent,
                    line,
                    DiagnosticKind::Unsupported,
                    "unverified include extension".into(),
                );
                return;
            }
        };
        if let Some(kind) = kind {
            let path = self.plan.occurrences[occurrence].path.as_ref().clone();
            self.depend(&path);
            self.plan
                .items
                .push(OrderedItem::NonText { occurrence, kind });
        } else if !self.adopt_previous(occurrence) {
            let started = std::time::Instant::now();
            self.visit_recording(occurrence);
            self.reuse.timings.visit += started.elapsed();
        }
    }

    fn conditional(&mut self, occurrence: usize, line: usize, word: &str, rest: &str) {
        let active = self.conditionals.last().is_none_or(|frame| frame.active);
        match word {
            "if" | "ifdef" | "ifndef" => {
                let result = if active {
                    self.evaluate(word, rest)
                } else {
                    Ok(false)
                };
                let yes = result.unwrap_or_else(|error| {
                    self.error(occurrence, line, DiagnosticKind::Conditional, error);
                    false
                });
                self.conditionals.push(Conditional {
                    parent_active: active,
                    branch_taken: yes,
                    active: active && yes,
                    else_seen: false,
                });
            }
            "elif" | "else" => {
                let Some(mut frame) = self.conditionals.pop() else {
                    self.error(
                        occurrence,
                        line,
                        DiagnosticKind::Conditional,
                        format!("unexpected #{word}"),
                    );
                    return;
                };
                if frame.else_seen {
                    self.error(
                        occurrence,
                        line,
                        DiagnosticKind::Conditional,
                        format!("#{word} after #else"),
                    );
                }
                let result = if !frame.parent_active || frame.branch_taken {
                    Ok(false)
                } else if word == "else" {
                    Ok(true)
                } else {
                    self.evaluate("if", rest)
                };
                let yes = result.unwrap_or_else(|error| {
                    self.error(occurrence, line, DiagnosticKind::Conditional, error);
                    false
                });
                frame.active = frame.parent_active && yes;
                frame.branch_taken |= yes;
                frame.else_seen |= word == "else";
                self.conditionals.push(frame);
            }
            "endif" => {
                if self.conditionals.pop().is_none() {
                    self.error(
                        occurrence,
                        line,
                        DiagnosticKind::Conditional,
                        "unexpected #endif".into(),
                    );
                }
            }
            _ => unreachable!(),
        }
    }
}

/// A macro lookup that logs every name it is asked for (the directives' reads of the environment).
struct Tested<'a> {
    inner: &'a dyn crate::MacroLookup,
    log: &'a std::cell::RefCell<Vec<Arc<str>>>,
}
impl crate::MacroLookup for Tested<'_> {
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)> {
        self.log.borrow_mut().push(Arc::from(name));
        self.inner.get_key_value(name)
    }
    fn location_read(&self, file: bool) {
        self.inner.location_read(file);
    }
    fn contains_key(&self, name: &str) -> bool {
        self.log.borrow_mut().push(Arc::from(name));
        self.inner.contains_key(name)
    }
}

fn evaluate(word: &str, expression: &str, macros: &dyn crate::MacroLookup) -> Result<bool, String> {
    match word {
        "ifdef" | "ifndef" => directive_identifier(expression)
            .map(|name| macro_defined(name, macros) == (word == "ifdef")),
        _ => eval_condition(expression, macros),
    }
}
