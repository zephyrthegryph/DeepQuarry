use super::*;

/// Preprocess a DME root. Each include occurrence is expanded in source order, even when a
/// file was included previously, because macros and declaration overrides are order-sensitive.
pub fn preprocess_project<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
) -> PreprocessedProject {
    preprocess_project_inner(project, provider, defines, None)
}

pub fn preprocess_project_cached<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
) -> PreprocessedProject {
    preprocess_project_inner(project, provider, defines, Some(cache))
}

fn preprocess_project_inner<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    cache: Option<&mut PreprocessCache>,
) -> PreprocessedProject {
    let mut ctx = Context {
        provider,
        cache,
        output: PreprocessedProject::default(),
        stack: Vec::new(),
        output_line: 1,
        macro_digest: [0; 32],
        macro_hashes: BTreeMap::new(),
        file_dir_changes: Vec::new(),
        file_dir_definitions: Vec::new(),
        project_dir: normalize(project.parent().unwrap_or(Path::new("")).to_path_buf()),
        manifest_lines: Vec::new(),
        reads: Vec::new(),
        macro_changes: Vec::new(),
    };
    for (name, replacement) in [
        ("EXCEPTION", "new /exception(message, __FILE__, __LINE__)"),
        ("REGEX_QUOTE", "regex(message, 1)"),
        ("REGEX_QUOTE_REPLACEMENT", "regex(message, 2)"),
    ] {
        ctx.set_macro(
            name.into(),
            Some(Macro {
                parameters: Some(vec!["message".into()]),
                variadic: false,
                replacement: replacement.into(),
            }),
        );
    }
    for (name, replacement) in defines {
        if name == "FILE_DIR" {
            ctx.change_file_dir(FileDirChange::Push(
                PathBuf::from(
                    replacement
                        .trim()
                        .trim_matches(['"', '\''])
                        .replace('\\', "/"),
                ),
                Macro {
                    parameters: None,
                    variadic: false,
                    replacement: replacement.clone(),
                },
            ));
        }
        ctx.set_macro(
            name.clone(),
            Some(Macro {
                parameters: None,
                variadic: false,
                replacement: replacement.clone(),
            }),
        );
    }
    ctx.visit(project.to_path_buf());
    for (text, path, source_line) in std::mem::take(&mut ctx.manifest_lines) {
        ctx.output.text.push_str(&text);
        ctx.output.text.push('\n');
        ctx.output.origins.push(Origin {
            output_line: ctx.output_line,
            path,
            source_line,
        });
        ctx.output_line += 1;
    }
    ctx.output
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(super) struct Conditional {
    pub(super) parent_active: bool,
    pub(super) branch_taken: bool,
    pub(super) active: bool,
    pub(super) else_seen: bool,
}

pub(super) fn macro_defined(name: &str, macros: &dyn MacroLookup) -> bool {
    matches!(name, "__FILE__" | "__LINE__") || macros.contains_key(name)
}

pub(super) fn directive_identifier(rest: &str) -> Result<&str, String> {
    let lexed = lex_spans(rest);
    if let Some(diagnostic) = lexed.diagnostics.first() {
        return Err(diagnostic.message.clone());
    }
    let mut identifiers = lexed.tokens.iter().filter(|token| {
        !matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        )
    });
    let Some(token) = identifiers.next() else {
        return Err("missing conditional macro name".into());
    };
    if token.kind != TokenKind::Ident || identifiers.next().is_some() {
        return Err("expected one conditional macro name".into());
    }
    Ok(token.text(rest))
}

#[derive(Clone, Copy)]
pub(super) struct ExpandLocation<'a> {
    pub(super) file_name: &'a str,
    pub(super) line: usize,
}

struct Context<'a, P: SourceProvider> {
    provider: &'a P,
    cache: Option<&'a mut PreprocessCache>,
    output: PreprocessedProject,
    stack: Vec<PathBuf>,
    output_line: usize,
    macro_digest: [u8; 32],
    macro_hashes: BTreeMap<String, [u8; 32]>,
    file_dir_changes: Vec<FileDirChange>,
    file_dir_definitions: Vec<Macro>,
    project_dir: PathBuf,
    manifest_lines: Vec<(String, std::sync::Arc<PathBuf>, usize)>,
    reads: Vec<(PathBuf, [u8; 32])>,
    macro_changes: Vec<(String, Option<Macro>)>,
}

impl<P: SourceProvider> Context<'_, P> {
    fn change_file_dir(&mut self, change: FileDirChange) {
        match &change {
            FileDirChange::Push(path, definition) => {
                self.output.file_dirs.push(path.clone());
                self.file_dir_definitions.push(definition.clone());
            }
            FileDirChange::Pop => {
                self.output.file_dirs.pop();
                self.file_dir_definitions.pop();
            }
        }
        self.file_dir_changes.push(change);
    }

    fn set_macro(&mut self, name: String, definition: Option<Macro>) {
        self.macro_changes.push((name.clone(), definition.clone()));
        self.output.final_macros.remove(&name);
        if let Some(previous) = self.macro_hashes.remove(&name) {
            xor_digest(&mut self.macro_digest, previous);
        }
        if let Some(definition) = definition {
            let hash = macro_hash(&name, &definition);
            xor_digest(&mut self.macro_digest, hash);
            self.macro_hashes.insert(name.clone(), hash);
            self.output.final_macros.insert(name, definition);
        }
    }

    fn error_as(
        &mut self,
        path: &Path,
        line: usize,
        kind: DiagnosticKind,
        message: impl Into<String>,
    ) {
        self.output.diagnostics.push(Diagnostic {
            path: path.to_owned(),
            line,
            kind,
            message: message.into(),
        });
    }

    /// Emits already expanded active text (one or more lines) with origins.
    fn emit_active_text(
        &mut self,
        path: &Path,
        origin_path: &Arc<PathBuf>,
        expanded: &str,
        source_line: usize,
    ) {
        for (offset, segment) in expanded.split('\n').enumerate() {
            if offset > 0 && segment.is_empty() && expanded.ends_with('\n') {
                break;
            }
            // DreamMaker parses manifest DM after all ordinary includes,
            // in manifest encounter order. Directives still act here.
            if path
                .extension()
                .is_some_and(|extension| extension.eq_ignore_ascii_case("dme"))
            {
                self.manifest_lines.push((
                    segment.to_owned(),
                    origin_path.clone(),
                    source_line + offset,
                ));
                continue;
            }
            self.output.text.push_str(segment);
            self.output.text.push('\n');
            self.output.origins.push(Origin {
                output_line: self.output_line,
                path: origin_path.clone(),
                source_line: source_line + offset,
            });
            self.output_line += 1;
        }
    }

    /// Lines held for a macro call that nothing closed: expanded one by one, each
    /// with its own diagnostic, as before calls could span directives.
    fn flush_open_calls(
        &mut self,
        held: &mut Vec<(String, usize)>,
        path: &Path,
        file_name: &str,
        origin_path: &Arc<PathBuf>,
    ) {
        for (text, line) in std::mem::take(held) {
            let expanded = match expand(
                &text,
                &self.output.final_macros,
                0,
                ExpandLocation { file_name, line },
            ) {
                Ok(s) => s,
                Err(e) => {
                    self.error_as(path, line, DiagnosticKind::Macro, e);
                    text.clone()
                }
            };
            self.emit_active_text(path, origin_path, &expanded, line);
        }
    }

    // Preserve original UTF-8 boundary checks before hashing frozen source slices.
    #[allow(clippy::sliced_string_as_bytes)]
    pub(super) fn visit(&mut self, path: PathBuf) {
        let path = normalize(path);
        if self.stack.contains(&path) {
            let chain = self
                .stack
                .iter()
                .chain(std::iter::once(&path))
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join(" -> ");
            self.error_as(
                &path,
                1,
                DiagnosticKind::Include,
                format!("include cycle: {chain}"),
            );
            return;
        }
        self.output.dependencies.insert(path.clone());
        let source = match self.provider.read(&path) {
            Ok(s) => s,
            Err(e) => {
                self.error_as(
                    &path,
                    1,
                    DiagnosticKind::Io,
                    format!("cannot read source: {e}"),
                );
                return;
            }
        };
        let exact_source_digest = self.provider.fingerprint_read(&path, &source);
        self.reads.push((path.clone(), exact_source_digest));
        let cache_key = path
            .strip_prefix(&self.project_dir)
            .unwrap_or(&path)
            .to_path_buf();
        if let Some(cache) = self.cache.as_deref_mut() {
            cache.load_unit(&cache_key);
        }
        let nested = has_include_directive(&source);
        // Nested units carry exact transitive source fingerprints and all side effects.
        let cacheable = source.len() <= MAX_CACHED_LEAF_BYTES
            && !path
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("dme"))
            && self.cache.as_ref().is_some_and(|cache| {
                cache.entries.contains_key(&cache_key) || cache.entries.len() < MAX_CACHED_PATHS
            });
        // FILE_DIR affects resource resolution and remains an ordered checkpoint.
        let mut directory_hasher = Sha256::new();
        for (directory, definition) in self.output.file_dirs.iter().zip(&self.file_dir_definitions)
        {
            let name = directory.to_string_lossy();
            directory_hasher.update((name.len() as u64).to_le_bytes());
            directory_hasher.update(name.as_bytes());
            directory_hasher.update(macro_hash("FILE_DIR", definition));
        }
        let directory_digest: [u8; 32] = directory_hasher.finalize().into();
        let source_digest: [u8; 32] = if cacheable {
            exact_source_digest
        } else {
            [0; 32]
        };
        if cacheable {
            if let Some(cache) = self.cache.as_deref_mut() {
                if let Some(entry) = cache.entries.get(&cache_key).and_then(|entries| {
                    entries.iter().find(|entry| {
                        entry.source_len == source.len()
                            && entry.source_digest == source_digest
                            && entry.dependencies.iter().all(|(relative, digest)| {
                                let dependency = normalize(self.project_dir.join(relative));
                                !self.stack.contains(&dependency)
                                    && self
                                        .provider
                                        .fingerprint(&dependency)
                                        .is_ok_and(|current| current == *digest)
                            })
                            && entry.input_digest
                                == dependency_digest(
                                    entry.macro_dependencies.as_deref(),
                                    &self.macro_hashes,
                                    self.macro_digest,
                                    directory_digest,
                                )
                    })
                }) {
                    let macro_changes = entry.macro_changes.clone();
                    let file_dir_changes = entry.file_dir_changes.clone();
                    let byte_start = self.output.text.len();
                    let line_start = self.output_line;
                    let origin_path = Arc::new(path.clone());
                    for (relative, digest) in &entry.dependencies {
                        let dependency = normalize(self.project_dir.join(relative));
                        self.output.dependencies.insert(dependency.clone());
                        self.reads.push((dependency, *digest));
                    }
                    self.output.map_includes.extend(
                        entry
                            .map_includes
                            .iter()
                            .map(|path| self.project_dir.join(path)),
                    );
                    self.output.skin_includes.extend(
                        entry
                            .skin_includes
                            .iter()
                            .map(|path| self.project_dir.join(path)),
                    );
                    self.manifest_lines.extend(entry.manifest_lines.iter().map(
                        |(text, relative, line)| {
                            (
                                text.clone(),
                                Arc::new(self.project_dir.join(relative)),
                                *line,
                            )
                        },
                    ));
                    self.output.text.push_str(&entry.output_text);
                    self.output
                        .origins
                        .extend(entry.origins.iter().map(|origin| Origin {
                            output_line: origin.0 + line_start - 1,
                            path: origin.2.as_ref().map_or_else(
                                || origin_path.clone(),
                                |relative| Arc::new(self.project_dir.join(relative)),
                            ),
                            source_line: origin.1,
                        }));
                    self.output
                        .units
                        .extend(entry.units.iter().cloned().map(|mut unit| {
                            unit.output_span.start += byte_start;
                            unit.output_span.end += byte_start;
                            unit.path = self.project_dir.join(&unit.path);
                            unit
                        }));
                    self.output
                        .unit_digests
                        .extend_from_slice(&entry.unit_digests);
                    self.output
                        .diagnostics
                        .extend(entry.diagnostics.iter().cloned().map(|mut diagnostic| {
                            diagnostic.path = self.project_dir.join(&diagnostic.path);
                            diagnostic
                        }));
                    self.output_line += entry.origins.len();
                    cache.hits += 1;
                    for change in file_dir_changes {
                        self.change_file_dir(change);
                    }
                    for (name, definition) in macro_changes {
                        self.set_macro(name, definition);
                    }
                    return;
                }
                cache.misses += 1;
            }
        }
        let macro_dependencies = (cacheable && !nested)
            .then(|| macro_dependencies(&source, &self.output.final_macros))
            .flatten();
        let input_digest = dependency_digest(
            macro_dependencies.as_deref(),
            &self.macro_hashes,
            self.macro_digest,
            directory_digest,
        );
        let macro_change_start = self.macro_changes.len();
        let read_start = self.reads.len();
        let map_start = self.output.map_includes.len();
        let skin_start = self.output.skin_includes.len();
        let manifest_start = self.manifest_lines.len();
        let origin_start = self.output.origins.len();
        let unit_start_index = self.output.units.len();
        let diagnostic_start = self.output.diagnostics.len();
        let file_dir_change_start = self.file_dir_changes.len();
        let line_start = self.output_line;
        self.stack.push(path.clone());
        let unit_start = self.output.text.len();
        let origin_path = Arc::new(path.clone());
        let file_name = path
            .strip_prefix(&self.project_dir)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");
        let mut conditionals: Vec<Conditional> = Vec::new();
        let mut line_number = 0;
        let mut held: Vec<(String, usize)> = Vec::new();
        let uncommented = strip_source_comments(&source);
        for logical in logical_lines(&uncommented) {
            let source_line = line_number + 1;
            line_number += logical.source_lines;
            let raw = logical.text;
            let trimmed = raw.trim_start();
            let directive = trimmed.strip_prefix('#').map(str::trim_start);
            let active = conditionals.last().is_none_or(|c| c.active);
            if let Some(d) = directive {
                let (word, rest) = split_word(d);
                if active && matches!(word, "define" | "undef" | "include") {
                    self.flush_open_calls(&mut held, &path, &file_name, &origin_path);
                }
                match word {
                    "ifdef" | "ifndef" | "if" => {
                        let yes = if !active {
                            false
                        } else if word == "ifdef" {
                            match directive_identifier(rest) {
                                Ok(name) => macro_defined(name, &self.output.final_macros),
                                Err(error) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        error,
                                    );
                                    false
                                }
                            }
                        } else if word == "ifndef" {
                            match directive_identifier(rest) {
                                Ok(name) => !macro_defined(name, &self.output.final_macros),
                                Err(error) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        error,
                                    );
                                    false
                                }
                            }
                        } else {
                            match eval_condition(rest, &self.output.final_macros) {
                                Ok(v) => v,
                                Err(e) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        e,
                                    );
                                    false
                                }
                            }
                        };
                        conditionals.push(Conditional {
                            parent_active: active,
                            branch_taken: yes,
                            active: active && yes,
                            else_seen: false,
                        });
                    }
                    "elif" => {
                        let Some(mut c) = conditionals.pop() else {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "unexpected #elif",
                            );
                            continue;
                        };
                        if c.else_seen {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "#elif after #else",
                            );
                        }
                        let yes = if !c.parent_active || c.branch_taken {
                            false
                        } else {
                            match eval_condition(rest, &self.output.final_macros) {
                                Ok(v) => v,
                                Err(e) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        e,
                                    );
                                    false
                                }
                            }
                        };
                        c.active = c.parent_active && yes;
                        c.branch_taken |= yes;
                        conditionals.push(c);
                    }
                    "else" => {
                        let Some(mut c) = conditionals.pop() else {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "unexpected #else",
                            );
                            continue;
                        };
                        if c.else_seen {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "duplicate #else",
                            );
                        }
                        c.active = c.parent_active && !c.branch_taken;
                        c.branch_taken = true;
                        c.else_seen = true;
                        conditionals.push(c);
                    }
                    "endif" => {
                        if conditionals.pop().is_none() {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "unexpected #endif",
                            );
                        }
                    }
                    _ if !active => {}
                    "include" => match parse_include(rest) {
                        Some(rel) => {
                            if rel
                                .extension()
                                .is_some_and(|extension| extension.eq_ignore_ascii_case("dmm"))
                            {
                                self.output
                                    .map_includes
                                    .push(path.parent().unwrap_or(Path::new("")).join(rel));
                                continue;
                            }
                            let child = path.parent().unwrap_or(Path::new("")).join(rel);
                            if child
                                .extension()
                                .is_some_and(|ext| ext.eq_ignore_ascii_case("dmf"))
                            {
                                self.output.dependencies.insert(child.clone());
                                match self.provider.read(&child) {
                                    Ok(text) => {
                                        self.reads.push((
                                            child.clone(),
                                            self.provider.fingerprint_read(&child, &text),
                                        ));
                                        self.output.skin_includes.push(child);
                                    }
                                    Err(error) => {
                                        self.error_as(&child, 1, DiagnosticKind::Io, error)
                                    }
                                }
                                continue;
                            }
                            self.visit(child);
                        }
                        None => self.error_as(
                            &path,
                            source_line,
                            DiagnosticKind::Include,
                            "expected quoted #include path",
                        ),
                    },
                    "define" => match parse_define(rest) {
                        Ok((name, def)) => {
                            if name == "FILE_DIR" && def.parameters.is_none() {
                                let value = def.replacement.trim().trim_matches(['"', '\'']);
                                if !value.is_empty() {
                                    self.change_file_dir(FileDirChange::Push(
                                        PathBuf::from(value.replace('\\', "/")),
                                        def.clone(),
                                    ));
                                }
                            }
                            self.set_macro(name, Some(def));
                        }
                        Err(e) => self.error_as(&path, source_line, DiagnosticKind::Macro, e),
                    },
                    "undef" => {
                        let name = rest.trim().to_owned();
                        if name == "FILE_DIR" && !self.output.file_dirs.is_empty() {
                            self.change_file_dir(FileDirChange::Pop);
                        }
                        let restored = if name == "FILE_DIR" {
                            self.file_dir_definitions.last().cloned()
                        } else {
                            None
                        };
                        self.set_macro(name, restored);
                    }
                    "error" => self.error_as(&path, source_line, DiagnosticKind::UserError, rest),
                    "warning" | "warn" | "pragma" => {}
                    "" => {}
                    other => self.error_as(
                        &path,
                        source_line,
                        DiagnosticKind::Unsupported,
                        format!("unsupported preprocessor directive #{other}"),
                    ),
                }
            } else if active {
                // Manifests can contain ordinary DM, including startup procedures.
                // Their extension does not change the language of active lines.
                // A macro call still open at the end of the line may be closed by a
                // later active line, with preprocessor directives in between.
                let single = raw.trim_end_matches(['\r', '\n']);
                let joined;
                let (text, first_line) = if held.is_empty() {
                    (single, source_line)
                } else {
                    let mut text = String::new();
                    for (earlier, _) in &held {
                        text.push_str(earlier);
                        text.push('\n');
                    }
                    text.push_str(single);
                    joined = text;
                    (joined.as_str(), held[0].1)
                };
                match expand(
                    text,
                    &self.output.final_macros,
                    0,
                    ExpandLocation {
                        file_name: &file_name,
                        line: first_line,
                    },
                ) {
                    Ok(expanded) => {
                        held.clear();
                        self.emit_active_text(&path, &origin_path, &expanded, first_line);
                    }
                    Err(e) if e == MISSING_CALL_CLOSE && held.len() < MAX_OPEN_CALL_LINES => {
                        held.push((single.to_owned(), source_line));
                    }
                    Err(_) if !held.is_empty() => {
                        held.push((single.to_owned(), source_line));
                        self.flush_open_calls(&mut held, &path, &file_name, &origin_path);
                    }
                    Err(e) => {
                        self.error_as(&path, source_line, DiagnosticKind::Macro, e);
                        self.emit_active_text(&path, &origin_path, single, source_line);
                    }
                }
            }
        }
        self.flush_open_calls(&mut held, &path, &file_name, &origin_path);
        if !conditionals.is_empty() {
            self.error_as(
                &path,
                line_number,
                DiagnosticKind::Conditional,
                "unterminated #if block",
            );
        }
        let unit_end = self.output.text.len();
        self.output
            .unit_digests
            .push(Sha256::digest(self.output.text[unit_start..unit_end].as_bytes()).into());
        self.output.units.push(Unit {
            path: path.clone(),
            output_span: Span::new(unit_start, unit_end),
            source_lines: line_number,
        });
        self.stack.pop();
        if let Some(cache) = self.cache.as_deref_mut().filter(|_| cacheable) {
            if (nested && self.output.diagnostics.len() != diagnostic_start)
                || unit_end - unit_start > MAX_CACHED_LEAF_BYTES
                || self.output.origins.len() - origin_start > MAX_CACHED_ORIGINS
                || self.output.units.len() - unit_start_index > MAX_CACHED_ORIGINS
                || self.reads.len() - read_start > MAX_CACHED_PATHS
            {
                return;
            }
            let entry = CachedUnit {
                source_digest,
                source_len: source.len(),
                input_digest,
                macro_dependencies,
                dependencies: self.reads[read_start..]
                    .iter()
                    .map(|(path, digest)| {
                        (
                            path.strip_prefix(&self.project_dir)
                                .unwrap_or(path)
                                .to_path_buf(),
                            *digest,
                        )
                    })
                    .collect(),
                map_includes: self.output.map_includes[map_start..]
                    .iter()
                    .map(|path| {
                        path.strip_prefix(&self.project_dir)
                            .unwrap_or(path)
                            .to_path_buf()
                    })
                    .collect(),
                skin_includes: self.output.skin_includes[skin_start..]
                    .iter()
                    .map(|path| {
                        path.strip_prefix(&self.project_dir)
                            .unwrap_or(path)
                            .to_path_buf()
                    })
                    .collect(),
                manifest_lines: self.manifest_lines[manifest_start..]
                    .iter()
                    .map(|(text, path, line)| {
                        (
                            text.clone(),
                            path.strip_prefix(&self.project_dir)
                                .unwrap_or(path.as_ref())
                                .to_path_buf(),
                            *line,
                        )
                    })
                    .collect(),
                output_text: self.output.text[unit_start..unit_end].to_owned(),
                unit_digests: self.output.unit_digests[unit_start_index..].to_vec(),
                origins: self.output.origins[origin_start..]
                    .iter()
                    .map(|origin| {
                        DiskOrigin(
                            origin.output_line - line_start + 1,
                            origin.source_line,
                            (origin.path.as_ref() != &path).then(|| {
                                origin
                                    .path
                                    .strip_prefix(&self.project_dir)
                                    .unwrap_or(origin.path.as_ref())
                                    .to_path_buf()
                            }),
                        )
                    })
                    .collect(),
                units: self.output.units[unit_start_index..]
                    .iter()
                    .cloned()
                    .map(|mut unit| {
                        unit.output_span.start -= unit_start;
                        unit.output_span.end -= unit_start;
                        unit.path = unit
                            .path
                            .strip_prefix(&self.project_dir)
                            .unwrap_or(&unit.path)
                            .to_path_buf();
                        unit
                    })
                    .collect(),
                diagnostics: self.output.diagnostics[diagnostic_start..]
                    .iter()
                    .cloned()
                    .map(|mut diagnostic| {
                        diagnostic.path = diagnostic
                            .path
                            .strip_prefix(&self.project_dir)
                            .unwrap_or(&diagnostic.path)
                            .to_path_buf();
                        diagnostic
                    })
                    .collect(),
                macro_changes: self.macro_changes[macro_change_start..]
                    .iter()
                    .cloned()
                    .collect(),
                file_dir_changes: self.file_dir_changes[file_dir_change_start..].to_vec(),
            };
            let key_bytes = cache_key.as_os_str().len();
            let is_new_key = !cache.entries.contains_key(&cache_key);
            cache.dirty.insert(cache_key.clone());
            let entries = cache.entries.entry(cache_key).or_default();
            if is_new_key {
                cache.resident_bytes += key_bytes;
            }
            cache.resident_bytes += entry.resident_bytes();
            entries.push(entry);
            if entries.len() > 2 {
                cache.resident_bytes -= entries.remove(0).resident_bytes();
            }
            cache.enforce_budget(MAX_CACHE_RESIDENT_BYTES);
        }
    }
}
