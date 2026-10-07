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
                    let (prefix, tail) = declaration
                        .rsplit_once("var/")
                        .ok_or("var namespace block requires normalization")?;
                    let owner = if prefix.is_empty() || prefix == "/" {
                        owner.into()
                    } else {
                        absolute(owner, prefix.trim_end_matches('/'))?
                    };
                    let tail = tail
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
                    let declared_type = if declaration.contains('[') {
                        Some(symbol(context.symbols, "/list")?)
                    } else if type_parts.is_empty() {
                        None
                    } else {
                        Some(symbol(
                            context.symbols,
                            &format!("/{}", type_parts.join("/")),
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
                        declared_type,
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
                        metadata,
                        content,
                    }))
                }
                ItemKind::Proc | ItemKind::Verb => {
                    let (raw, arguments, trailing) = signature_parts(header)?;
                    let raw = raw.trim();
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
                    let owner = if prefix.is_empty() || prefix == "/" {
                        owner.into()
                    } else {
                        absolute(owner, prefix)?
                    };
                    if name.is_empty() || name.contains('/') {
                        return Err("invalid procedure name".into());
                    }
                    let mut settings = String::new();
                    let mut typed_settings = Vec::new();
                    let mut display_name = None;
                    for child in &item.children {
                        let setting = child.header.trim();
                        if setting.starts_with("set ") {
                            typed_settings
                                .push(crate::procedure::parse_setting(setting, context.symbols)?);
                            settings.push_str(setting);
                            settings.push('\n');
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
                        settings: typed_settings.into(),
                    }));
                    let metadata = MemberMetadata {
                        declared_type: None,
                        display_name,
                        flags: 0,
                        procedure,
                        array: None,
                        initializer: None,
                        declared_initializer: None,
                        resolved_constant: None,
                        canonical: canonical(&format!("{header}\n{settings}"))?,
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
                        metadata,
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
                    let name = header[..index].trim();
                    if name.is_empty() || name.contains('/') || name.contains('[') {
                        return Err(format!("unsupported field assignment: {header}"));
                    }
                    let metadata = MemberMetadata {
                        initializer: Some(crate::procedure::expression(
                            header[index + 1..].trim(),
                            context.symbols,
                        )?),
                        canonical: canonical(&header[index + 1..])?,
                        ..MemberMetadata::default()
                    };
                    let content = xxhash_rust::xxh3::xxh3_128(&metadata.canonical);
                    Ok(Some(Skeleton::Member {
                        owner: symbol(context.symbols, owner)?,
                        name: symbol(context.symbols, name)?,
                        kind: MemberKind::Var,
                        mode: DefinitionMode::Override,
                        metadata,
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
mod tests {
    use super::*;
    use crate::{build, MemberKind, OccurrenceTable};
    fn adapt(source: &str) -> AdaptedDeclarations {
        from_ast(
            &dm_syntax::parse(source),
            SymbolTable::default(),
            FileId(3),
            7,
            11,
        )
        .unwrap()
    }
    #[test]
    fn namespaces_arrays_defaults_and_settings_bridge_to_tree() {
        let result=adapt("/datum/base\n    var\n        static/list\n            values[2][3]\n    proc\n        read(value = 3 as num)\n            set name = \"Reader\"\n            set waitfor = 0\n            return value\n");
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let owner = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
        let array = tree
            .member(
                tree.resolve(owner, SymbolId::of("values"), MemberKind::Var)
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(array.metadata.declared_type, Some(SymbolId::of("/list")));
        assert_eq!(array.metadata.flags & 1, 1);
        let proc = tree
            .member(
                tree.resolve(owner, SymbolId::of("read"), MemberKind::Proc)
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(proc.metadata.display_name, Some(SymbolId::of("Reader")));
        assert!(proc.metadata.procedure.is_some());
        assert_eq!(
            OccurrenceTable::build(&tree, result.origins)
                .unwrap()
                .source_order()
                .len(),
            3
        );
    }
    #[test]
    fn inherited_field_assignment_preserves_type_and_flags() {
        let result=adapt("/datum/base\n    var/tmp/list/values = null\n/datum/child\n    parent_type = /datum/base\n    values = list(1, 2)\n");
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let owner = tree.lookup_type(SymbolId::of("/datum/child")).unwrap();
        let field = tree
            .member(
                tree.resolve(owner, SymbolId::of("values"), MemberKind::Var)
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(field.metadata.declared_type, Some(SymbolId::of("/list")));
        assert_eq!(field.metadata.flags & 4, 4);
        assert!(field.previous.is_some());
    }
    #[test]
    fn forward_multilevel_field_inheritance_resolves_in_dependency_order() {
        let result=adapt("/datum/child\n    parent_type = /datum/parent\n    value = 3\n/datum/parent\n    parent_type = /datum/grand\n    value = 2\n/datum/grand\n    var/tmp/list/value = null\n");
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let child = tree.lookup_type(SymbolId::of("/datum/child")).unwrap();
        let id = tree
            .resolve(child, SymbolId::of("value"), MemberKind::Var)
            .unwrap();
        assert_eq!(
            tree.member(id).unwrap().metadata.declared_type,
            Some(SymbolId::of("/list"))
        );
        assert_eq!(tree.member(id).unwrap().metadata.flags & 4, 4);
        assert_eq!(tree.override_chain(id).len(), 3);
    }

    #[test]
    fn observed_formal_base_and_encounter_override_chain_are_distinct() {
        let project = include_str!(
            "../../../fixtures/phase0/preprocess/manifest-order/proc-two-overrides/project.dme"
        );
        let child = include_str!(
            "../../../fixtures/phase0/preprocess/manifest-order/proc-two-overrides/child.dm"
        );
        let source = project.replace("#include \"child.dm\"", child);
        let result = adapt(&source);
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let effective = tree
            .resolve(owner, SymbolId::of("read"), MemberKind::Proc)
            .unwrap();
        let chain = tree.override_chain(effective);
        assert_eq!(chain.len(), 3);
        assert_eq!(
            tree.member(chain[0]).unwrap().definition,
            DefinitionMode::Implicit
        );
        assert_eq!(
            tree.member(chain[2]).unwrap().definition,
            DefinitionMode::Declare
        );
        let origins = OccurrenceTable::build(&tree, result.origins).unwrap();
        let texts: Vec<_> = chain
            .iter()
            .map(|id| {
                let origin = origins
                    .get(origins.for_target(crate::Target::Member(*id))[0])
                    .unwrap();
                &source[origin.provenance.span.start as usize..origin.provenance.span.end as usize]
            })
            .collect();
        assert!(texts[0].contains("return 2"));
        assert!(texts[1].contains("return 1"));
        assert!(texts[2].contains("return 0"));
    }
    #[test]
    fn implicit_before_formal_still_resolves_to_override() {
        let source = "/datum/probe/read()\n    return 2\n/datum/probe/proc/read()\n    return 1\n";
        let result = adapt(source);
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let id = tree
            .resolve(owner, SymbolId::of("read"), MemberKind::Proc)
            .unwrap();
        let chain = tree.override_chain(id);
        assert_eq!(chain, vec![crate::MemberId(0), crate::MemberId(1)]);
        assert_eq!(
            tree.member(id).unwrap().definition,
            DefinitionMode::Implicit
        );
    }
    #[test]
    fn observed_field_default_is_retained_beside_effective_class_assignment() {
        let project = include_str!(
            "../../../fixtures/phase0/preprocess/manifest-order/field-before/project.dme"
        );
        let child = include_str!(
            "../../../fixtures/phase0/preprocess/manifest-order/field-before/child.dm"
        );
        let result = adapt(&project.replace("#include \"child.dm\"", child));
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let id = tree
            .resolve(owner, SymbolId::of("value"), MemberKind::Var)
            .unwrap();
        let metadata = &tree.member(id).unwrap().metadata;
        assert_eq!(
            metadata
                .declared_initializer
                .as_ref()
                .unwrap()
                .source_text(tree.symbols())
                .as_deref(),
            Some("1")
        );
        assert_eq!(
            metadata
                .initializer
                .as_ref()
                .unwrap()
                .source_text(tree.symbols())
                .as_deref(),
            Some("2")
        );
    }

    #[test]
    fn body_changes_reuse_tree_but_setting_changes_do_not() {
        let identity = |source| {
            let result = adapt(source);
            build(result.symbols, &result.skeletons).unwrap().identity()
        };
        let first = "/datum/base/proc/read(value = 3 as num)\n    set waitfor = 0\n    return 1\n";
        let second = first.replace("return 1", "return 222");
        assert_eq!(identity(first), identity(&second));
        assert_ne!(
            identity(first),
            identity(&first.replace("waitfor = 0", "waitfor = 1"))
        );
    }
    #[test]
    fn unresolved_constant_is_explicitly_unsupported() {
        use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
        let result = adapt("var/const/first = 1\nvar/const/second = first + 1\n");
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let query = ResolveQuery::Constant {
            owner: SymbolId::of("/"),
            name: SymbolId::of("second"),
        };
        assert_eq!(
            Resolver::resolve(&tree, query),
            ResolvedMeaning::Unsupported(query)
        );
        assert!(matches!(
            Resolver::resolve(
                &tree,
                ResolveQuery::Constant {
                    owner: SymbolId::of("/"),
                    name: SymbolId::of("first")
                }
            ),
            ResolvedMeaning::Member { .. }
        ));
    }
    #[test]
    fn absolute_field_assignment_is_owned_by_its_target() {
        let result = adapt("/datum/base\n    var/value = 1\n/datum/base/value = 2\n");
        let tree = build(result.symbols, &result.skeletons).unwrap();
        let owner = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
        let field = tree
            .resolve(owner, SymbolId::of("value"), MemberKind::Var)
            .unwrap();
        assert_eq!(tree.override_chain(field).len(), 2);
    }
}

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
        let tree =
            Arc::new(crate::build(self.symbols, &self.skeletons).map_err(SnapshotError::Tree)?);
        let occurrences = Arc::new(
            crate::OccurrenceTable::build(&tree, self.origins).map_err(SnapshotError::Origins)?,
        );
        Ok(TreeSnapshot { tree, occurrences })
    }
}
