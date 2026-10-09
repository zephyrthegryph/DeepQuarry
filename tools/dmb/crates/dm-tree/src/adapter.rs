//! Structural AST adapter. Unsupported declaration forms are explicit errors;
//! executable bodies stay in the syntax layer and never enter tree identity.
use crate::{DefinitionMode, MemberKind, MemberMetadata, Provenance, Skeleton};
use dm_ir::{FileId, Span, SymbolId, SymbolTable, TypePath};
use dm_syntax::{AstFile, Item, ItemKind, TokenKind};
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct AdapterError {
    pub span: Span,
    pub message: String,
}
#[derive(Clone, Debug)]
pub struct AdaptedDeclarations {
    pub symbols: SymbolTable,
    pub skeletons: Vec<Skeleton>,
    pub origins: Vec<Provenance>,
}
/// Adapt one expanded region's AST, preserving declaration order. The caller
/// replaces the expansion stack and region identity with preprocessor records.
pub fn from_ast(
    ast: &AstFile,
    symbols: SymbolTable,
    file: FileId,
    include_occurrence: u32,
    region: u128,
) -> Result<AdaptedDeclarations, Vec<AdapterError>> {
    from_ast_in_scope(ast, symbols, file, include_occurrence, region, "/")
}

/// Parse fragments only when the caller retains their containing declaration
/// scope. Includes cutting through a declaration need the combined encounter AST
/// or a parser continuation; a root reset would change their meaning.
pub fn from_ast_in_scope(
    ast: &AstFile,
    mut symbols: SymbolTable,
    file: FileId,
    include_occurrence: u32,
    region: u128,
    owner: &str,
) -> Result<AdaptedDeclarations, Vec<AdapterError>> {
    let mut result = AdaptedDeclarations {
        symbols: SymbolTable::default(),
        skeletons: Vec::new(),
        origins: Vec::new(),
    };
    let mut errors = Vec::new();
    for diagnostic in &ast.diagnostics {
        errors.push(AdapterError {
            span: Span {
                file,
                start: diagnostic.span.start as u32,
                end: diagnostic.span.end as u32,
            },
            message: diagnostic.message.clone(),
        });
    }
    let normalized = crate::normalize::declarations_in_scope(&ast.items, owner);
    let mut context = AdapterContext {
        file,
        include_occurrence,
        region,
        symbols: &mut symbols,
        result: &mut result,
        errors: &mut errors,
    };
    walk(&normalized, owner, &mut context);
    result.symbols = symbols;
    if errors.is_empty() {
        Ok(result)
    } else {
        Err(errors)
    }
}
fn symbol(table: &mut SymbolTable, text: &str) -> Result<SymbolId, String> {
    table.intern(text).map_err(|error| error.to_string())
}
fn absolute(owner: &str, path: &str) -> Result<String, String> {
    let path = path.trim_end_matches('/');
    let full = if path.is_empty() {
        owner.into()
    } else if path.starts_with('/') {
        path.into()
    } else if owner == "/" {
        format!("/{path}")
    } else {
        format!("{owner}/{path}")
    };
    TypePath::parse(&full).map_err(str::to_owned)?;
    Ok(full)
}
/// Lossless token spellings with explicit kind/length framing. Whitespace and
/// comments are omitted; string contents and source settings are not rewritten.
fn canonical(text: &str) -> Result<Arc<[u8]>, String> {
    let tokens = dm_syntax::lex(text);
    if !tokens.diagnostics.is_empty() {
        return Err("invalid tokens in declaration metadata".into());
    }
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"dm-declaration-tokens-v1\0");
    let mut previous = None;
    for token in tokens.tokens {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            continue;
        }
        let sensitive = previous
            .is_some_and(|(kind, _)| matches!(kind, TokenKind::Operator | TokenKind::Punctuation))
            && matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation);
        bytes.push(if sensitive {
            if previous.is_some_and(|(_, end)| end == token.span.start) {
                1
            } else {
                2
            }
        } else {
            0
        });
        previous = Some((token.kind, token.span.end));
        bytes.push(token.kind as u8);
        bytes.extend_from_slice(&(token.text.len() as u64).to_le_bytes());
        bytes.extend_from_slice(token.text.as_bytes());
    }
    Ok(bytes.into())
}
struct AdapterContext<'a> {
    file: FileId,
    include_occurrence: u32,
    region: u128,
    symbols: &'a mut SymbolTable,
    result: &'a mut AdaptedDeclarations,
    errors: &'a mut Vec<AdapterError>,
}
fn walk(items: &[Item], owner: &str, context: &mut AdapterContext<'_>) {
    let file = context.file;
    let include_occurrence = context.include_occurrence;
    let region = context.region;
    let mut containing_owner = owner.to_owned();
    for item in items {
        let owner = containing_owner.as_str();
        let span = Span {
            file,
            start: item.span.start as u32,
            end: item.span.end as u32,
        };
        let header = item.header.trim();
        let adapted = (|| -> Result<Option<Skeleton>, String> {
            match item.kind {
                ItemKind::Type => {
                    let path = absolute(owner, header)?;
                    // Namespace blocks are traversed as source structure, not
                    // invented semantic types named proc, verb or var.
                    if path.ends_with("/proc") || path.ends_with("/verb") || path.ends_with("/var")
                    {
                        return Err(
                            "namespace blocks require frontend normalization before dm-tree".into(),
                        );
                    }
                    let mut parent = None;
                    for child in &item.children {
                        if let Some((name, value)) = child.header.split_once('=') {
                            if name.trim() == "parent_type" {
                                let value = absolute("/", value.trim())?;
                                parent = Some(symbol(context.symbols, &value)?)
                            }
                        }
                    }
                    Ok(Some(Skeleton::Type {
                        path: symbol(context.symbols, &path)?,
                        explicit_parent: parent,
                    }))
                }
                ItemKind::Var => {
                    let (declaration, initializer) = dm_syntax::top_level_assignment_index(header)
                        .map_or((header, None), |index| {
                            (header[..index].trim(), Some(header[index + 1..].trim()))
                        });
                    let separator = declaration
                        .match_indices("var/")
                        .find(|(index, _)| *index == 0 || declaration.as_bytes()[index - 1] == b'/')
                        .map(|(index, _)| index)
                        .ok_or("var namespace block requires normalization")?;
                    let (prefix, tail) = (&declaration[..separator], &declaration[separator + 4..]);
                    let owner = if prefix == "/" || (prefix.is_empty() && header.starts_with('/')) {
                        "/".into()
                    } else if prefix.is_empty() {
                        owner.into()
                    } else {
                        absolute(owner, prefix.trim_end_matches('/'))?
                    };
                    let tail = dm_syntax::normalize_declaration_type(tail)
                        .split_once(" as ")
                        .map_or(tail, |(declaration, _)| declaration)
                        .trim();
                    let parts: Vec<_> = tail.split('/').collect();
                    let raw_name = parts
                        .last()
                        .ok_or("missing var name")?
                        .split(" as ")
                        .next()
                        .unwrap()
                        .trim();
                    let raw_name = raw_name.split('[').next().unwrap().trim();
                    if raw_name.is_empty() {
                        return Err("missing var name".into());
                    }
                    let flags = parts[..parts.len() - 1]
                        .iter()
                        .filter_map(|part| match *part {
                            "static" => Some(1),
                            "const" => Some(2),
                            "tmp" => Some(4),
                            "global" => Some(8),
                            _ => None,
                        })
                        .fold(0, |flags, flag| flags | flag);
                    let type_parts: Vec<_> = parts[..parts.len() - 1]
                        .iter()
                        .copied()
                        .filter(|part| !matches!(*part, "static" | "const" | "tmp" | "global"))
                        .collect();
                    let authored_type = format!("/{}", type_parts.join("/"));
                    let projection = dm_syntax::project_declaration_type(&authored_type);
                    let list_element_type = projection
                        .list_element_path
                        .map(|path| symbol(context.symbols, &format!("/{path}")))
                        .transpose()?;
                    let declared_type = if declaration.contains('[') {
                        Some(symbol(context.symbols, "/list")?)
                    } else if type_parts.is_empty() {
                        None
                    } else {
                        Some(symbol(
                            context.symbols,
                            dm_syntax::project_declaration_type(&format!(
                                "/{}",
                                type_parts.join("/")
                            ))
                            .runtime_path,
                        )?)
                    };
                    let symbolic_initializer = initializer
                        .map(|text| crate::procedure::expression(text, context.symbols))
                        .transpose()?;
                    let resolved_constant = if flags & 2 != 0 {
                        initializer
                            .and_then(|text| {
                                crate::constants::evaluate_with(text, |_| None, |_| None, |_| None)
                            })
                            .map(|value| value.to_semantic(context.symbols))
                            .transpose()
                            .map_err(|error| error.to_string())?
                    } else {
                        None
                    };
                    let element_type = if type_parts.is_empty() {
                        None
                    } else {
                        Some(symbol(
                            context.symbols,
                            &format!("/{}", type_parts.join("/")),
                        )?)
                    };
                    let array =
                        crate::procedure::parse_array(declaration, element_type, context.symbols)?;
                    let metadata = MemberMetadata {
                        inherited_opaque: None,
                        declared_type,
                        list_element_type,
                        display_name: None,
                        flags,
                        procedure: None,
                        array,
                        declared_initializer: symbolic_initializer.clone(),
                        initializer: symbolic_initializer,
                        resolved_constant,
                        canonical: canonical(header)?,
                    };
                    let content = xxhash_rust::xxh3::xxh3_128(&metadata.canonical);
                    Ok(Some(Skeleton::Member {
                        owner: symbol(context.symbols, &owner)?,
                        name: symbol(context.symbols, raw_name)?,
                        kind: MemberKind::Var,
                        mode: DefinitionMode::Declare,
                        metadata: Arc::new(metadata),
                        content,
                    }))
                }
                ItemKind::Proc | ItemKind::Verb => {
                    let (raw, arguments, trailing) = signature_parts(header)?;
                    // DM accepts an optional path separator before the formal
                    // argument list: receive_signal/(datum/signal/signal).
                    let raw = raw.trim().trim_end_matches('/');
                    let marker = if item.kind == ItemKind::Verb {
                        "verb/"
                    } else {
                        "proc/"
                    };
                    let explicit = raw.starts_with(marker) || raw.contains(&format!("/{marker}"));
                    let (prefix, name) = raw
                        .strip_prefix(marker)
                        .map(|name| ("", name))
                        .or_else(|| raw.rsplit_once(&format!("/{marker}")))
                        .or_else(|| raw.rsplit_once('/'))
                        .unwrap_or(("", raw));
                    let owner = if prefix == "/" || (prefix.is_empty() && raw.starts_with('/')) {
                        "/".into()
                    } else if prefix.is_empty() {
                        owner.into()
                    } else {
                        absolute(owner, prefix)?
                    };
                    if name.is_empty() || name.contains('/') {
                        return Err("invalid procedure name".into());
                    }
                    let typed_settings =
                        crate::settings::extract_settings(&item.children, context.symbols)?;
                    let mut display_name = None;
                    for child in &item.children {
                        let setting = child.header.trim();
                        if setting.starts_with("set ") {
                            if let Some(value) = setting.strip_prefix("set name = ") {
                                if let Some(value) = value
                                    .trim()
                                    .strip_prefix('"')
                                    .and_then(|v| v.strip_suffix('"'))
                                {
                                    display_name = Some(symbol(context.symbols, value)?)
                                }
                            }
                        }
                    }
                    let typed_signature =
                        crate::procedure::parse_signature(arguments, trailing, context.symbols)?;
                    let procedure = Some(Arc::new(crate::ProcedureMetadata {
                        signature: typed_signature,
                        settings: typed_settings,
                    }));
                    let mut semantic_header = canonical(header)?.to_vec();
                    semantic_header
                        .extend_from_slice(&procedure.as_ref().unwrap().canonical_bytes());
                    let metadata = MemberMetadata {
                        inherited_opaque: None,
                        declared_type: None,
                        list_element_type: None,
                        display_name,
                        flags: 0,
                        procedure,
                        array: None,
                        initializer: None,
                        declared_initializer: None,
                        resolved_constant: None,
                        canonical: semantic_header.into(),
                    };
                    let kind = if item.kind == ItemKind::Verb {
                        MemberKind::Verb
                    } else {
                        MemberKind::Proc
                    };
                    let path = format!("{}/{}{name}", owner.trim_end_matches('/'), marker);
                    symbol(context.symbols, &path)?;
                    let content = xxhash_rust::xxh3::xxh3_128(&metadata.canonical);
                    Ok(Some(Skeleton::Member {
                        owner: symbol(context.symbols, &owner)?,
                        name: symbol(context.symbols, name)?,
                        kind,
                        mode: if explicit {
                            DefinitionMode::Declare
                        } else {
                            DefinitionMode::Implicit
                        },
                        metadata: Arc::new(metadata),
                        content,
                    }))
                }
                ItemKind::Unknown | ItemKind::Statement
                    if header
                        .split_once('=')
                        .is_some_and(|(key, _)| key.trim() == "parent_type") =>
                {
                    Ok(None)
                }
                ItemKind::Unknown | ItemKind::Statement => {
                    let index = dm_syntax::top_level_assignment_index(header)
                        .ok_or_else(|| format!("unsupported declaration: {header}"))?;
                    let target = header[..index].trim();
                    let (assignment_owner, name) = match target.rsplit_once('/') {
                        Some(("", name)) => ("/".to_owned(), name),
                        Some((prefix, name)) => (absolute(owner, prefix)?, name),
                        None => (owner.to_owned(), target),
                    };
                    if name.is_empty() || name.contains('[') {
                        return Err(format!("unsupported field assignment: {header}"));
                    }
                    let metadata = MemberMetadata {
                        inherited_opaque: None,
                        initializer: Some(crate::procedure::expression(
                            header[index + 1..].trim(),
                            context.symbols,
                        )?),
                        canonical: canonical(&header[index + 1..])?,
                        ..MemberMetadata::default()
                    };
                    let content = xxhash_rust::xxh3::xxh3_128(&metadata.canonical);
                    Ok(Some(Skeleton::Member {
                        owner: symbol(context.symbols, &assignment_owner)?,
                        name: symbol(context.symbols, name)?,
                        kind: MemberKind::Var,
                        mode: DefinitionMode::Override,
                        metadata: Arc::new(metadata),
                        content,
                    }))
                }
            }
        })();
        match adapted {
            Ok(Some(skeleton)) => {
                context.result.skeletons.push(skeleton);
                context.result.origins.push(Provenance {
                    span,
                    include_occurrence,
                    region,
                    expansion_stack: Arc::from([]),
                });
                if item.kind == ItemKind::Type {
                    if let Ok(path) = absolute(owner, header) {
                        containing_owner = path.clone();
                        walk(&item.children, &path, context)
                    }
                }
            }
            Ok(None) => {}
            Err(message) => context.errors.push(AdapterError { span, message }),
        }
    }
}

#[cfg(test)]
#[path = "adapter_tests.rs"]
mod tests;

fn signature_parts(header: &str) -> Result<(&str, &str, &str), String> {
    let tokens = dm_syntax::lex(header);
    let mut open = None;
    let mut depth = 0;
    for token in &tokens.tokens {
        match token.text.as_str() {
            "(" => {
                if depth == 0 {
                    open = Some(token.span.start)
                }
                depth += 1
            }
            ")" => {
                if depth == 0 {
                    return Err("unmatched procedure signature parenthesis".into());
                }
                depth -= 1;
                if depth == 0 {
                    let start = open.unwrap();
                    return Ok((
                        &header[..start],
                        &header[start + 1..token.span.start],
                        &header[token.span.end..],
                    ));
                }
            }
            _ => {}
        }
    }
    Err("unterminated procedure signature".into())
}

/// A resolved frontend result ready for lowering and analysis. Semantic nodes
/// share independently from the current build's occurrence/provenance table.
#[derive(Clone, Debug)]
pub struct TreeSnapshot {
    pub tree: Arc<crate::SemanticTree>,
    pub occurrences: Arc<crate::OccurrenceTable>,
}
#[derive(Clone, Debug)]
pub enum SnapshotError {
    Tree(crate::TreeError),
    Origins(crate::OccurrenceCountMismatch),
    Inventory(crate::InventoryError),
}
impl AdaptedDeclarations {
    /// Append expansion fragments in semantic emission order. Symbol collisions
    /// are checked even when independently parsed fragments share numeric IDs.
    pub fn append(&mut self, other: AdaptedDeclarations) -> Result<(), dm_ir::SymbolCollision> {
        for (_, text) in other.symbols.ordered() {
            self.symbols.intern(text)?;
        }
        self.skeletons.extend(other.skeletons);
        self.origins.extend(other.origins);
        Ok(())
    }
    pub fn finish(self) -> Result<TreeSnapshot, SnapshotError> {
        self.finish_with_engine(None)
    }

    /// Engine types contribute hierarchy and semantic identity, never authored
    /// source occurrences. Intrinsic members remain opaque presence records.
    pub fn finish_with_engine(
        self,
        seed: Option<&crate::frontend::EngineSeed>,
    ) -> Result<TreeSnapshot, SnapshotError> {
        self.finish_with_engine_observed(seed, |_, _, _| {})
    }

    /// Report failures while their original source ledger is still borrowed.
    /// Successful resolution does not clone the source ledger for diagnostics.
    pub fn finish_with_engine_observed(
        self,
        seed: Option<&crate::frontend::EngineSeed>,
        on_error: impl FnMut(&SnapshotError, &[Skeleton], &[Provenance]),
    ) -> Result<TreeSnapshot, SnapshotError> {
        self.finish_with_engine_observed_execution(seed, on_error, None, None)
    }
    pub fn finish_with_engine_observed_on_executor(
        self,
        seed: Option<&crate::frontend::EngineSeed>,
        on_error: impl FnMut(&SnapshotError, &[Skeleton], &[Provenance]),
        executor: &dm_exec::BuildExecutor,
    ) -> Result<TreeSnapshot, SnapshotError> {
        self.finish_with_engine_observed_execution(seed, on_error, Some(executor), None)
    }
    pub(crate) fn finish_with_engine_normalization(
        self,
        seed: Option<&crate::frontend::EngineSeed>,
        on_error: impl FnMut(&SnapshotError, &[Skeleton], &[Provenance]),
        executor: &dm_exec::BuildExecutor,
        normalization: Option<(
            &crate::declaration_contributions::KeyedDeclarations,
            &crate::owner_normalization::RetainedNormalization,
        )>,
    ) -> Result<TreeSnapshot, SnapshotError> {
        self.finish_with_engine_observed_execution(seed, on_error, Some(executor), normalization)
    }
    fn finish_with_engine_observed_execution(
        self,
        seed: Option<&crate::frontend::EngineSeed>,
        mut on_error: impl FnMut(&SnapshotError, &[Skeleton], &[Provenance]),
        executor: Option<&dm_exec::BuildExecutor>,
        normalization: Option<(
            &crate::declaration_contributions::KeyedDeclarations,
            &crate::owner_normalization::RetainedNormalization,
        )>,
    ) -> Result<TreeSnapshot, SnapshotError> {
        let mut skeletons = Vec::new();
        let hierarchy = seed_hierarchy(&self.skeletons, seed).map_err(|error| {
            let error = SnapshotError::Tree(error);
            on_error(&error, &self.skeletons, &self.origins);
            error
        })?;
        if let Some(hierarchy) = &hierarchy {
            skeletons.extend(
                hierarchy
                    .parents
                    .iter()
                    .map(|&(path, parent)| Skeleton::Type {
                        path,
                        explicit_parent: parent,
                    }),
            );
        }
        let engine_count = skeletons.len();
        skeletons.extend(self.skeletons);
        let fields = seed.map_or(&[][..], |seed| seed.fields.as_ref());
        let intrinsics = seed.map_or(&[][..], |seed| seed.intrinsics.as_ref());
        let mut tree = crate::build_with_intrinsic_members_indexed(
            self.symbols,
            &skeletons,
            fields,
            intrinsics,
            seed.is_none(),
            normalization,
        )
        .map_err(|error| {
            let error = SnapshotError::Tree(error);
            on_error(&error, &skeletons[engine_count..], &self.origins);
            error
        })?;
        // The source ledger is a projection, not a made-up origin for seeds.
        tree.declaration_targets = tree.declaration_targets[engine_count..].into();
        if let Some(seed) = seed {
            let hierarchy = hierarchy.unwrap();
            tree = match executor {
                Some(executor) => tree.with_engine_intrinsics_on_executor(
                    hierarchy,
                    seed.intrinsics.to_vec(),
                    executor,
                ),
                None => tree.with_engine_intrinsics(hierarchy, seed.intrinsics.to_vec()),
            }
            .map_err(|error| {
                let error = SnapshotError::Inventory(error);
                on_error(&error, &skeletons[engine_count..], &self.origins);
                error
            })?;
        }
        let tree = Arc::new(tree);
        let occurrences = Arc::new(crate::OccurrenceTable::build(&tree, self.origins).map_err(
            |error| {
                let error = SnapshotError::Origins(error);
                // Origin validation errors carry their own exact error value;
                // resolution_error never selects a declaration for this domain.
                on_error(&error, &skeletons[engine_count..], &[]);
                error
            },
        )?);
        Ok(TreeSnapshot { tree, occurrences })
    }
}

/// One authored-parent precedence producer, shared by full and retained builds.
pub(crate) fn seed_hierarchy(
    skeletons: &[Skeleton],
    seed: Option<&crate::frontend::EngineSeed>,
) -> Result<Option<crate::EngineHierarchy>, crate::TreeError> {
    let mut authored_parents = std::collections::HashMap::new();
    for row in skeletons {
        if let Skeleton::Type {
            path,
            explicit_parent: Some(parent),
        } = row
        {
            if let Some(previous) = authored_parents.insert(*path, *parent) {
                if previous != *parent {
                    return Err(crate::TreeError::ConflictingParent(*path));
                }
            }
        }
    }
    Ok(seed.map(|seed| {
        let mut hierarchy = seed.hierarchy.clone();
        for (path, parent) in &mut hierarchy.parents {
            if let Some(authored) = authored_parents.get(path) {
                *parent = Some(*authored);
            }
        }
        hierarchy
    }))
}
pub(crate) fn projected_identity(
    skeletons: &[Skeleton],
    seed: Option<&crate::frontend::EngineSeed>,
) -> Result<(u128, Option<crate::EngineHierarchy>), crate::TreeError> {
    let hierarchy = seed_hierarchy(skeletons, seed)?;
    let mut combined = Vec::new();
    if let Some(hierarchy) = &hierarchy {
        combined.extend(
            hierarchy
                .parents
                .iter()
                .map(|&(path, parent)| Skeleton::Type {
                    path,
                    explicit_parent: parent,
                }),
        );
    }
    combined.extend_from_slice(skeletons);
    Ok((
        crate::declaration_identity(&combined, seed.map_or(&[][..], |seed| seed.fields.as_ref())),
        hierarchy,
    ))
}
