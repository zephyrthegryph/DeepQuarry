use super::*;
use crate::{
    directive_identifier, eval_condition, macro_defined, parse_define, parse_include, split_word,
    Conditional, DiagnosticKind,
};

pub(super) fn plan<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
) -> DirectivePlan {
    let mut pass = DirectivePass {
        provider,
        plan: DirectivePlan {
            project_dir: canonical_path(project.parent().unwrap_or(Path::new(""))),
            ..DirectivePlan::default()
        },
        visited: BTreeSet::new(),
        file_dir_definitions: Vec::new(),
        environment: MacroEnvironment::default(),
        file_dir_origins: Vec::new(),
        conditionals: Vec::new(),
    };
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
    let occurrence = pass.occurrence(project, None, Span::default(), 1);
    pass.visit(occurrence);
    pass.plan
}

struct DirectivePass<'a, P> {
    provider: &'a P,
    plan: DirectivePlan,
    visited: BTreeSet<PathBuf>,
    file_dir_definitions: Vec<Macro>,
    environment: MacroEnvironment,
    file_dir_origins: Vec<Option<DefinitionOrigin>>,
    // Includes splice their directives into the same encounter stream.
    conditionals: Vec<Conditional>,
}

impl<P: SourceProvider> DirectivePass<'_, P> {
    fn occurrence(
        &mut self,
        path: &Path,
        parent: Option<usize>,
        directive_span: Span,
        directive_line: usize,
    ) -> usize {
        let index = self.plan.occurrences.len();
        let semantic_path = if let Some(parent) = parent {
            let parent_occurrence = &self.plan.occurrences[parent];
            let relative = path
                .strip_prefix(parent_occurrence.path.parent().unwrap_or(Path::new("")))
                .unwrap_or(path);
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
        self.plan.diagnostic_ordinals.push(ordinal);
        self.plan.diagnostics.push(Diagnostic {
            path: self.plan.occurrences[occurrence].path.as_ref().clone(),
            line,
            kind,
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
            segments: Vec::new(),
            effects: Vec::new(),
        });
        self.plan.items.push(OrderedItem::Text(index));
        index
    }

    fn freeze_lines(&mut self, region: usize, pending: &mut Vec<RegionLine>) {
        if pending.is_empty() {
            return;
        }
        // Every segment sees its exact full incoming environment. Persistent
        // roots and Arc bindings share unchanged entries across define epochs;
        // token-pasted names require no pruning guess and no full-table clone.
        self.plan.regions[region].segments.push(ExpansionSegment {
            lines: std::mem::take(pending),
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

    fn visit(&mut self, occurrence: usize) {
        let path = self.plan.occurrences[occurrence].path.clone();
        // Paired same-file/distinct-file fixtures establish first-visit
        // suppression. Alias/case policies remain explicitly unproven.
        if !self.visited.insert(path.as_ref().clone()) {
            self.plan.occurrences[occurrence].suppressed = true;
            return;
        }
        self.plan.dependencies.insert(path.as_ref().clone());
        let prepared = match self.provider.prepared_source(&path) {
            Some(prepared) => prepared,
            None => match self.provider.read(&path) {
                Ok(source) => Arc::new(prepared_source::PreparedSource::new(Arc::from(source))),
                Err(error) => {
                    self.error(occurrence, 1, DiagnosticKind::Io, error);
                    return;
                }
            },
        };
        self.plan
            .source_line_starts
            .insert(path.as_ref().clone(), prepared.line_starts().clone());
        let mut line_number = 0;
        let mut region = self.begin_region(occurrence, 0);
        let mut pending = Vec::new();
        for logical in prepared.lines() {
            let source_line = logical.source_line;
            line_number += logical.source_lines;
            let span = logical.source_span;
            let start = span.start;
            let end = span.end;
            let active = self.conditionals.last().is_none_or(|frame| frame.active);
            let Some(directive) = logical.text.trim_start().strip_prefix('#') else {
                if active {
                    pending.push(RegionLine {
                        source_span: span,
                        source_line,
                        text: logical.text.clone(),
                    });
                }
                continue;
            };
            let (word, rest) = split_word(directive.trim_start());
            if matches!(word, "if" | "ifdef" | "ifndef" | "elif" | "else" | "endif") {
                self.conditional(occurrence, source_line, word, rest);
                continue;
            }
            if word == "include" {
                self.freeze_lines(region, &mut pending);
                self.plan.regions[region].source_span.end = start;
                if active {
                    self.include(occurrence, span, source_line, rest);
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
                    match parse_define(rest) {
                        Ok((name, definition)) => {
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
                                self.plan.regions[region]
                                    .effects
                                    .push(MacroEffect::PushFileDir {
                                        path,
                                        definition: definition.clone(),
                                    });
                            }
                            self.plan.regions[region].effects.push(MacroEffect::Define {
                                name: name.clone(),
                                definition: definition.clone(),
                            });
                            self.environment
                                .insert(&name, definition.clone(), Some(origin));
                            self.plan.final_macros.insert(name, definition);
                        }
                        Err(error) => {
                            self.error(occurrence, source_line, DiagnosticKind::Macro, error)
                        }
                    }
                }
                "undef" => {
                    self.freeze_lines(region, &mut pending);
                    match directive_identifier(rest) {
                        Ok(name) => {
                            self.plan.regions[region].effects.push(MacroEffect::Undef {
                                name: name.to_owned(),
                            });
                            self.plan.final_macros.remove(name);
                            self.environment.remove(name);
                            if name == "FILE_DIR" {
                                self.plan.file_dirs.pop();
                                self.file_dir_definitions.pop();
                                self.file_dir_origins.pop();
                                self.plan.regions[region]
                                    .effects
                                    .push(MacroEffect::PopFileDir);
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
                "warning" | "warn" | "pragma" | "" => {}
                other => self.error(
                    occurrence,
                    source_line,
                    DiagnosticKind::Directive,
                    format!("unsupported preprocessor directive #{other}"),
                ),
            }
        }
        self.freeze_lines(region, &mut pending);
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
                "unterminated #if block".into(),
            );
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
            .join(relative);
        let occurrence = self.occurrence(&child, Some(parent), span, line);
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
                    DiagnosticKind::Include,
                    "unverified include extension".into(),
                );
                return;
            }
        };
        if let Some(kind) = kind {
            let path = self.plan.occurrences[occurrence].path.as_ref().clone();
            self.plan.dependencies.insert(path);
            self.plan
                .items
                .push(OrderedItem::NonText { occurrence, kind });
        } else {
            self.visit(occurrence);
        }
    }

    fn conditional(&mut self, occurrence: usize, line: usize, word: &str, rest: &str) {
        let active = self.conditionals.last().is_none_or(|frame| frame.active);
        match word {
            "if" | "ifdef" | "ifndef" => {
                let result = if active {
                    evaluate(word, rest, &self.plan.final_macros)
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
                        format!("#{word} without #if"),
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
                    evaluate("if", rest, &self.plan.final_macros)
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
                        "#endif without #if".into(),
                    );
                }
            }
            _ => unreachable!(),
        }
    }
}

fn evaluate(
    word: &str,
    expression: &str,
    macros: &BTreeMap<String, Macro>,
) -> Result<bool, String> {
    match word {
        "ifdef" | "ifndef" => directive_identifier(expression)
            .map(|name| macro_defined(name, macros) == (word == "ifdef")),
        _ => eval_condition(expression, macros),
    }
}
