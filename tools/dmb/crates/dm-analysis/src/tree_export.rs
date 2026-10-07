//! Versioned JSON-lines projection, streamed directly from the immutable tree.
//! Semantic rows omit source paths and executable bodies. Occurrence/body rows
//! describe this build's current source, independently of semantic identity.
use dm_ir::{
    DeclaredTypeKnowledge, SemanticValue, SymbolId, SymbolTable, SymbolicExpression, TypeId,
};
use dm_syntax::TokenKind;
use dm_tree::frontend::{ColdFrontend, SourceLocation};
use dm_tree::{DefinitionMode, MemberKind, SemanticTree, SettingOperation, Target};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fmt;
use std::io::Write;

pub const SCHEMA: &str = "dm-tree-analysis-v1";

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ExportCounts {
    pub semantic_rows: usize,
    pub occurrence_rows: usize,
    pub body_rows: usize,
}

#[derive(Debug)]
pub enum ExportError {
    Json(serde_json::Error),
    Io(std::io::Error),
    InvalidModel(&'static str),
}
impl fmt::Display for ExportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => error.fmt(formatter),
            Self::Io(error) => error.fmt(formatter),
            Self::InvalidModel(message) => formatter.write_str(message),
        }
    }
}
impl std::error::Error for ExportError {}

fn emit(writer: &mut impl Write, row: Value) -> Result<(), ExportError> {
    serde_json::to_writer(&mut *writer, &row).map_err(ExportError::Json)?;
    writer.write_all(b"\n").map_err(ExportError::Io)
}
fn spelling(symbols: &SymbolTable, id: SymbolId) -> Result<&str, ExportError> {
    symbols
        .text(id)
        .ok_or(ExportError::InvalidModel("unknown exported symbol"))
}
fn type_key(tree: &SemanticTree, id: TypeId) -> Result<String, ExportError> {
    let node = tree
        .type_node(id)
        .ok_or(ExportError::InvalidModel("unknown exported type"))?;
    Ok(format!("type:{:016x}", node.path.bits()))
}
fn kind(kind: MemberKind) -> &'static str {
    match kind {
        MemberKind::Var => "var",
        MemberKind::Proc => "proc",
        MemberKind::Verb => "verb",
    }
}
fn token_kind(kind: TokenKind) -> &'static str {
    match kind {
        TokenKind::Ident => "identifier",
        TokenKind::Number => "number",
        TokenKind::String => "string",
        TokenKind::Resource => "resource",
        TokenKind::Interpolation => "interpolation",
        TokenKind::Operator => "operator",
        TokenKind::Punctuation => "punctuation",
        TokenKind::Whitespace => "whitespace",
        TokenKind::Newline => "newline",
        TokenKind::Comment => "comment",
        TokenKind::Unknown => "unknown",
    }
}
fn definition(mode: DefinitionMode) -> &'static str {
    match mode {
        DefinitionMode::Declare => "declare",
        DefinitionMode::Override => "override",
        DefinitionMode::Reopen => "reopen",
        DefinitionMode::Implicit => "implicit",
    }
}
fn operation(operation: SettingOperation) -> &'static str {
    match operation {
        SettingOperation::Assign => "assign",
        SettingOperation::In => "in",
    }
}
fn expression(
    value: Option<&SymbolicExpression>,
    symbols: &SymbolTable,
) -> Result<Value, ExportError> {
    let Some(value) = value else {
        return Ok(Value::Null);
    };
    let mut previous = None;
    let tokens = value.tokens.iter().map(|token| {
        let sensitive = previous.is_some_and(|(kind, _)| matches!(kind, TokenKind::Operator | TokenKind::Punctuation))
            && matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation);
        let adjacency = if sensitive { Some(previous.is_some_and(|(_, end)| end == token.relative_span.start)) } else { None };
        previous = Some((token.kind, token.relative_span.end));
        Ok(json!({"kind":token_kind(token.kind), "text":spelling(symbols,token.text)?, "operator_adjacent":adjacency}))
    }).collect::<Result<Vec<_>,ExportError>>()?;
    Ok(json!({"tokens": tokens}))
}
fn constant(value: &SemanticValue, symbols: &SymbolTable) -> Result<Value, ExportError> {
    Ok(match value {
        SemanticValue::Null => json!({"kind":"null"}),
        SemanticValue::NumberBits(bits) => json!({"kind":"number", "f32_bits":bits}),
        SemanticValue::Text(bytes) => json!({"kind":"text", "bytes":bytes.as_ref()}),
        SemanticValue::Type(path) => json!({"kind":"type", "path":spelling(symbols,*path)?}),
        SemanticValue::Resource(path) => {
            json!({"kind":"resource", "path":spelling(symbols,*path)?})
        }
        SemanticValue::List(entries) => {
            json!({"kind":"list", "entries":entries.iter().map(|(key,value)| {
            Ok(json!({"key":key.as_ref().map(|key| constant(key,symbols)).transpose()?, "value":constant(value,symbols)?}))
        }).collect::<Result<Vec<_>, ExportError>>()?})
        }
    })
}
fn source(location: &SourceLocation) -> Value {
    json!({
        "path":location.path.to_string_lossy(), "semantic_path":location.semantic_path.as_ref(),
        "start":location.span.start, "end":location.span.end, "line":location.line,
        "span_precision":"logical_line", "include_occurrence":location.include_occurrence,
        "include_chain":location.include_chain.as_ref(), "encounter_ordinal":location.encounter_ordinal,
        "macro_expansions":location.macro_expansions.iter().map(|expansion| json!({
            "name":expansion.name, "invocation_start":expansion.invocation_span.start,
            "invocation_end":expansion.invocation_span.end, "invocation_space":"expansion_input",
            "replacement_chain":expansion.replacement_chain,
            "definition":expansion.definition.as_ref().map(|definition| json!({
                "path":definition.path.to_string_lossy(), "start":definition.source_span.start,
                "end":definition.source_span.end, "line":definition.source_line,
            })),
        })).collect::<Vec<_>>(),
    })
}

/// Export does not resolve through a compiler/session or reconstruct declarations.
/// IDs name owner/name/kind and a deterministic same-name declaration-chain
/// ordinal. Meaning fingerprints are separate, so changing a default preserves
/// its declaration ID. Source offsets
/// and executable body text never participate in those IDs.
pub fn write_jsonl(
    frontend: &ColdFrontend,
    writer: &mut impl Write,
) -> Result<ExportCounts, ExportError> {
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let mut counts = ExportCounts::default();
    let engine = frontend.engine.as_ref().map(|engine| json!({
        "identity":format!("{:032x}",engine.identity), "schema":format!("{:032x}",engine.schema),
        "type_count":engine.type_count,"known_intrinsic_members":engine.known_intrinsic_members,
        "member_catalog_complete":engine.member_catalog_complete,
        "typed_member_metadata_decoded":engine.typed_member_metadata_decoded,
    }));
    emit(
        writer,
        json!({"row":"schema","schema":SCHEMA,"source_span_precision":"logical_line",
        "model":if frontend.engine.is_some() { "engine_hierarchy_and_source_declarations" } else { "source_declarations" },
        "engine":engine,"engine_inventory":if frontend.engine.is_some() { "authoritative_hierarchy_partial_intrinsic_catalog" } else { "not_certified_by_export" },
        "unsupported_domains":["resource_resolution","executable_lowering","opaque_intrinsic_metadata"]}),
    )?;
    let mut identical = HashMap::new();
    let mut member_keys = Vec::with_capacity(tree.members().len());
    for member in tree.members() {
        let owner = tree
            .type_node(member.owner)
            .ok_or(ExportError::InvalidModel("unknown member owner"))?
            .path;
        let base = format!(
            "member:{:016x}:{}:{:016x}",
            owner.bits(),
            kind(member.kind),
            member.name.bits()
        );
        let ordinal = identical.entry(base.clone()).or_insert(0usize);
        member_keys.push(format!("{base}:{ordinal}"));
        *ordinal += 1;
    }
    for id in tree.lexical_types() {
        let node = tree
            .type_node(id)
            .ok_or(ExportError::InvalidModel("unknown lexical type"))?;
        emit(
            writer,
            json!({"row":"type", "id":type_key(tree,id)?, "path":spelling(symbols,node.path)?,
            "parent":node.parent.map(|parent| type_key(tree,parent)).transpose()?,
            "explicit_parent":node.explicit_parent, "synthetic":node.synthetic}),
        )?;
        counts.semantic_rows += 1;
    }
    let mut members: Vec<_> = (0..tree.members().len()).collect();
    members.sort_by_key(|index| &member_keys[*index]);
    for index in members {
        let member = &tree.members()[index];
        let metadata = &member.metadata;
        let effective = tree
            .resolve(member.owner, member.name, member.kind)
            .and_then(|id| tree.member(id))
            .ok_or(ExportError::InvalidModel(
                "member has no effective declaration",
            ))?;
        let procedure = metadata.procedure.as_ref().map(|procedure| {
            let parameters = procedure.signature.parameters.iter().map(|parameter| Ok(json!({
                "name":spelling(symbols,parameter.name)?,
                "declared_type":parameter.declared_type.map(|id| spelling(symbols,id)).transpose()?,
                "default":expression(parameter.default.as_ref(),symbols)?,
                "input_annotation":expression(parameter.input_annotation.as_ref(),symbols)?,
                "source_expression":expression(parameter.source_expression.as_ref(),symbols)?,
            }))).collect::<Result<Vec<_>, ExportError>>()?;
            let settings = procedure.settings.iter().map(|setting| Ok(json!({
                "name":spelling(symbols,setting.name)?, "operation":operation(setting.operation),
                "value":expression(Some(&setting.value),symbols)?,
            }))).collect::<Result<Vec<_>, ExportError>>()?;
            Ok::<_,ExportError>(json!({"parameters":parameters,"variadic":procedure.signature.variadic,
                "return_annotation":expression(procedure.signature.return_annotation.as_ref(),symbols)?,"settings":settings}))
        }).transpose()?;
        let array = metadata.array.as_ref().map(|array| Ok::<_,ExportError>(json!({
            "element_type":array.element_type.map(|id| spelling(symbols,id)).transpose()?,
            "dimensions":array.dimensions.iter().map(|dimension| expression(dimension.as_ref(),symbols)).collect::<Result<Vec<_>,_>>()?,
        }))).transpose()?;
        let opaque = metadata.inherited_opaque.as_ref().map(|base| Ok::<_,ExportError>(json!({
            "owner":spelling(symbols,base.owner)?,"name":spelling(symbols,base.name)?,
            "declared_type":match base.declared_type { DeclaredTypeKnowledge::Known(path)=>Some(spelling(symbols,path)?),DeclaredTypeKnowledge::Unsupported=>None },
            "declared_type_status":match base.declared_type { DeclaredTypeKnowledge::Known(_)=>"known",DeclaredTypeKnowledge::Unsupported=>"unsupported" },
            "flags_status":"unknown", "formal_default_status":"unknown", "array_shape_status":"unknown",
        }))).transpose()?;
        emit(
            writer,
            json!({"row":"member", "id":member_keys[index], "owner":type_key(tree,member.owner)?,
            "meaning":format!("{:032x}",member.content), "name":spelling(symbols,member.name)?, "kind":kind(member.kind),"definition":definition(member.definition),
            "previous":member.previous.map(|previous| &member_keys[previous.index()]),
            "declared_type":metadata.declared_type.map(|id| spelling(symbols,id)).transpose()?,
            "display_name":metadata.display_name.map(|id| spelling(symbols,id)).transpose()?,
            "inherited_opaque":opaque,
            "flags":metadata.inherited_opaque.is_none().then_some(metadata.flags),
            "flags_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" },
            "effective_flags":effective.metadata.inherited_opaque.is_none().then_some(effective.metadata.flags),
            "effective_flags_status":if effective.metadata.inherited_opaque.is_some() { "unknown" } else { "known" }, "initializer":expression(metadata.initializer.as_ref(),symbols)?,
            "declared_default":expression(metadata.declared_initializer.as_ref(),symbols)?,
            "declared_default_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" },
            "effective_default":expression(effective.metadata.initializer.as_ref(),symbols)?,
            "resolved_constant":metadata.resolved_constant.as_ref().map(|value| constant(value,symbols)).transpose()?,
            "procedure":procedure,"array":array,
            "array_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" }}),
        )?;
        counts.semantic_rows += 1;
    }
    let target_key = |target| match target {
        Target::Type(id) => type_key(tree, id),
        Target::Member(id) => member_keys
            .get(id.index())
            .cloned()
            .ok_or(ExportError::InvalidModel("unknown occurrence member")),
    };
    let mut expanded_locations = HashMap::new();
    for origin in &frontend.expanded.origins {
        let include = frontend.plan.regions[origin.region].occurrence;
        expanded_locations
            .entry((include, origin.source_span.start))
            .or_insert(origin.output_span.start);
    }
    for (index, occurrence) in frontend
        .snapshot
        .occurrences
        .source_order()
        .iter()
        .enumerate()
    {
        let provenance = &occurrence.provenance;
        let file = frontend
            .source(provenance.span.file)
            .ok_or(ExportError::InvalidModel("unknown occurrence source"))?;
        emit(
            writer,
            json!({"row":"occurrence","occurrence":index,"target":target_key(occurrence.target)?,
            "path":file.path.to_string_lossy(),"start":provenance.span.start,"end":provenance.span.end,
            "include_occurrence":provenance.include_occurrence,"region":format!("{:032x}",provenance.region),
            "source":expanded_locations.get(&(provenance.include_occurrence as usize,provenance.span.start as usize))
                .and_then(|offset| frontend.location(*offset)).as_ref().map(source),
            "definition_origins":provenance.expansion_stack.iter().map(|span| {
                let file=frontend.source(span.file).ok_or(ExportError::InvalidModel("unknown macro definition source"))?;
                Ok(json!({"path":file.path.to_string_lossy(),"start":span.start,"end":span.end}))
            }).collect::<Result<Vec<_>,ExportError>>()?}),
        )?;
        counts.occurrence_rows += 1;
    }
    for body in frontend.bodies.iter() {
        emit(
            writer,
            json!({"row":"body","declaration":body.declaration.0,
            "member":target_key(Target::Member(body.member))?,
            "expanded_start":body.expanded_span.start,"expanded_end":body.expanded_span.end,
            "source":source(&body.source)}),
        )?;
        counts.body_rows += 1;
    }
    Ok(counts)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::path::{Path, PathBuf};
    struct Input(String);
    impl dm_preprocess::SourceProvider for Input {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    fn rows(body: &str) -> Vec<Value> {
        source_rows(&format!("/datum/probe\n    var/value = 7\n    proc/read(argument = 3)\n        set waitfor = 0\n        return {body}\n"))
    }
    fn source_rows(source: &str) -> Vec<Value> {
        let input = Input(source.into());
        let frontend =
            dm_tree::frontend::build(&PathBuf::from("project.dme"), &input, &BTreeMap::new(), 1)
                .unwrap();
        let mut bytes = Vec::new();
        let counts = write_jsonl(&frontend, &mut bytes).unwrap();
        assert_eq!(counts.body_rows, 1);
        String::from_utf8(bytes)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect()
    }
    #[test]
    fn whitespace_equivalent_metadata_exports_identical_semantics() {
        let first = source_rows("/datum/probe\n    var/value = 7 + 3\n    proc/read(argument = 3)\n        set waitfor = 0\n        return 1\n");
        let second = source_rows("/datum/probe\n    var/value=7+3\n    proc/read(argument=3)\n        set waitfor=0\n        return 1\n");
        let semantics = |rows: Vec<Value>| {
            rows.into_iter()
                .filter(|row| matches!(row["row"].as_str(), Some("type" | "member")))
                .collect::<Vec<_>>()
        };
        assert_eq!(semantics(first), semantics(second));
    }
    #[test]
    fn executable_edits_leave_semantic_rows_stable_and_update_occurrences() {
        let first = rows("1");
        let second = rows("222");
        let semantics = |rows: &[Value]| {
            rows.iter()
                .filter(|row| matches!(row["row"].as_str(), Some("type" | "member")))
                .cloned()
                .collect::<Vec<_>>()
        };
        assert_eq!(semantics(&first), semantics(&second));
        let origins = |rows: &[Value]| {
            rows.iter()
                .filter(|row| matches!(row["row"].as_str(), Some("occurrence" | "body")))
                .cloned()
                .collect::<Vec<_>>()
        };
        assert_ne!(origins(&first), origins(&second));
        let proc = first.iter().find(|row| row["kind"] == "proc").unwrap();
        assert_eq!(proc["procedure"]["parameters"][0]["name"], "argument");
        assert_eq!(proc["procedure"]["settings"][0]["name"], "waitfor");
    }
}
