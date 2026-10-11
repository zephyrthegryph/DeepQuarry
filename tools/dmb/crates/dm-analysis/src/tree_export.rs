//! Versioned JSON-lines projection, streamed directly from the immutable tree.
//! Semantic rows omit source paths and executable bodies. Occurrence/body rows
//! describe this build's current source, independently of semantic identity.
use dm_ir::{
    DeclaredTypeKnowledge, ProcedureSettingNode, SemanticValue, SymbolId, SymbolTable,
    SymbolicExpression, TypeId,
};
use dm_syntax::TokenKind;
use dm_tree::frontend::{ColdFrontend, SourceLocation};
use dm_tree::{DefinitionMode, MemberKind, SemanticTree, SettingOperation, Target};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fmt;
use std::io::Write;

pub const SCHEMA: &str = "dm-tree-analysis-v3";
#[path = "tree_export/member_row.rs"]
mod member_row;
#[path = "query_export.rs"]
mod query_export;
pub use query_export::{write_queries_jsonl, AnalysisQuery};

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
        SemanticValue::Procedure(identity) => json!({
            "kind":"procedure", "owner":spelling(symbols,identity.owner)?,
            "name":spelling(symbols,identity.name)?, "verb":identity.verb,
            "occurrence":identity.occurrence
        }),
        SemanticValue::ModifiedInstance(descriptor) => json!({
            "kind":"modified_instance", "identity":descriptor.alias(),
            "runtime_type":spelling(symbols,descriptor.runtime_type())?,
            "fields":descriptor.fields().iter().map(|(name,value)| json!({
                "name":name,"value":modified_expression(value)
            })).collect::<Vec<_>>()
        }),
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
/// Descriptor expressions are issued, normalized semantic values. Source spans
/// and lexical context belong to occurrence rows, never this structural value.
fn modified_expression(value: &dm_syntax::Expr) -> Value {
    use dm_syntax::ExprKind;
    match &value.kind {
        ExprKind::Ident(text) => json!({"kind":"identifier","text":text}),
        ExprKind::Literal(text) => json!({"kind":"literal","text":text}),
        ExprKind::TypePath(path) => json!({"kind":"type_path","path":path}),
        ExprKind::Unary { op, value } => {
            json!({"kind":"unary","operator":op,"value":modified_expression(value)})
        }
        ExprKind::Binary { op, lhs, rhs } => {
            json!({"kind":"binary","operator":op,"lhs":modified_expression(lhs),"rhs":modified_expression(rhs)})
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            json!({"kind":"conditional","condition":modified_expression(condition),"then_value":modified_expression(then_value),"else_value":modified_expression(else_value)})
        }
        ExprKind::Call { callee, args } => {
            json!({"kind":"call","callee":modified_expression(callee),"arguments":args.iter().map(modified_expression).collect::<Vec<_>>()})
        }
        ExprKind::Member {
            object,
            selector,
            via_colon,
        } => {
            json!({"kind":"member","object":modified_expression(object),"selector":selector,"via_colon":via_colon})
        }
        ExprKind::StaticMember { object, selector } => {
            json!({"kind":"static_member","object":modified_expression(object),"selector":selector})
        }
        ExprKind::SafeMember {
            object,
            selector,
            via_colon,
        } => {
            json!({"kind":"safe_member","object":modified_expression(object),"selector":selector,"via_colon":via_colon})
        }
        ExprKind::Index { object, index } => {
            json!({"kind":"index","object":modified_expression(object),"index":modified_expression(index)})
        }
        ExprKind::SafeIndex { object, index } => {
            json!({"kind":"safe_index","object":modified_expression(object),"index":modified_expression(index)})
        }
        ExprKind::Group(value) => json!({"kind":"group","value":modified_expression(value)}),
        ExprKind::TypeFilter { value, types } => {
            json!({"kind":"type_filter","value":modified_expression(value),"types":types})
        }
        ExprKind::ObjectInitializer { object, fields } => {
            json!({"kind":"object_initializer","object":modified_expression(object),"fields":fields.iter().map(|(name,value)|json!({"name":name,"value":modified_expression(value)})).collect::<Vec<_>>()})
        }
    }
}
fn setting_nodes(
    nodes: &[ProcedureSettingNode],
    symbols: &SymbolTable,
) -> Result<Vec<Value>, ExportError> {
    nodes.iter().map(|node| Ok(match node {
        ProcedureSettingNode::Setting(setting) => json!({
            "kind":"setting", "name":spelling(symbols,setting.name)?,
            "operation":operation(setting.operation), "value":expression(Some(&setting.value),symbols)?,
        }),
        ProcedureSettingNode::Conditional { condition, then_branch, else_branch } => json!({
            "kind":"conditional", "condition":expression(Some(condition),symbols)?,
            "then_branch":setting_nodes(then_branch,symbols)?, "else_branch":setting_nodes(else_branch,symbols)?,
        }),
        ProcedureSettingNode::UnsupportedContext { canonical_header, children } => json!({
            "kind":"unsupported_context", "header":expression(Some(canonical_header),symbols)?,
            "children":setting_nodes(children,symbols)?,
        }),
    })).collect()
}
fn source(location: &SourceLocation) -> Value {
    json!({
        "path":location.path.to_string_lossy(), "semantic_path":location.semantic_path.as_ref(),
        "start":location.span.start, "end":location.span.end, "line":location.line,
        "span_precision":"logical_line", "include_occurrence":location.include_occurrence,
        "include_chain":location.include_chain.as_ref(), "encounter_ordinal":location.encounter_ordinal,
        "macro_expansions":location.macro_expansions.iter().map(|expansion| json!({
            "name":expansion.name.as_ref(), "invocation_start":expansion.invocation_span.start,
            "invocation_end":expansion.invocation_span.end, "invocation_space":"expansion_input",
            "replacement_chain":expansion.replacement_chain.iter().map(|name| name.as_ref()).collect::<Vec<_>>(),
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
/// Identity of the exact current source/provenance projection, independent of tree identity.
/// This is a join token, never a filesystem freshness or artifact admission proof.
pub fn source_revision(frontend: &ColdFrontend) -> u128 {
    use xxhash_rust::xxh3::Xxh3;
    let mut hash = Xxh3::new();
    hash.update(b"dm-analysis-source-revision-v1\0");
    hash.update(&frontend.snapshot.tree.identity().to_le_bytes());
    for file in frontend.files.iter() {
        let path = file.path.to_string_lossy();
        hash.update(&(path.len() as u64).to_le_bytes());
        hash.update(path.as_bytes());
        hash.update(&[u8::from(file.captured)]);
        hash.update(
            &file
                .text
                .span_fingerprint(0..file.text.len())
                .expect("whole source range")
                .to_le_bytes(),
        );
    }
    hash.update(
        &frontend
            .expanded
            .text
            .span_fingerprint(0..frontend.expanded.text.len())
            .expect("whole expanded range")
            .to_le_bytes(),
    );
    for origin in frontend.expanded.origins.iter() {
        for value in [
            origin.output_span.start,
            origin.output_span.end,
            origin.source_span.start,
            origin.source_span.end,
            origin.region,
            origin.origin.source_line,
        ] {
            hash.update(&(value as u64).to_le_bytes());
        }
    }
    hash.digest128()
}

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
        json!({"row":"schema","schema":SCHEMA,"semantic_revision":format!("{:032x}",tree.identity()),
        "source_revision":format!("{:032x}",source_revision(frontend)),"snapshot_outcome":"frontend_analyzed",
        "source_span_precision":"logical_line",
        "model":if frontend.engine.is_some() { "engine_hierarchy_and_source_declarations" } else { "source_declarations" },
        "engine":engine,"engine_inventory":if frontend.engine.is_some() { "authoritative_hierarchy_partial_intrinsic_catalog" } else { "not_certified_by_export" },
        "unsupported_domains":["resource_resolution","executable_reference_resolution","opaque_intrinsic_metadata"],
        "query_schema":"dm-resolved-query-v1", "member_occurrence":"normalized_owner_local_override_depth"}),
    )?;
    let mut member_keys = Vec::with_capacity(tree.members().len());
    for (index, member) in tree.members().iter().enumerate() {
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
        let id = dm_tree::MemberId(
            u32::try_from(index)
                .map_err(|_| ExportError::InvalidModel("member index exceeds u32"))?,
        );
        let ordinal = tree
            .member_occurrence(id)
            .ok_or(ExportError::InvalidModel("member occurrence unavailable"))?;
        member_keys.push(format!("{base}:{ordinal}"));
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
        emit(
            writer,
            member_row::member_row(tree, dm_tree::MemberId(index as u32))?,
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
    for origin in frontend.expanded.origins.iter() {
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
            "source":source(&body.source),
            "setting_context_origins":body.setting_context_origins.iter().map(source).collect::<Vec<_>>()}),
        )?;
        counts.body_rows += 1;
    }
    counts.semantic_rows += query_export::write_member_queries(tree, &member_keys, writer)?;
    Ok(counts)
}

#[cfg(test)]
mod tests {
    #[test]
    fn typed_list_hints_export_as_structural_facts_separate_from_arrays() {
        let rows = source_rows("/datum/probe\n    var/list/datum/item/values\n    proc/read(list/datum/item/argument)\n        return 1\n");
        let field = rows
            .iter()
            .find(|row| row["row"] == "member" && row["name"] == "values")
            .unwrap();
        assert_eq!(field["declared_type"], "/list");
        assert_eq!(field["list_element_type"], "/datum/item");
        assert_eq!(field["list_element_type_status"], "known");
        assert!(field["array"].is_null());
        let procedure = rows.iter().find(|row| row["kind"] == "proc").unwrap();
        let argument = &procedure["procedure"]["parameters"][0];
        assert_eq!(argument["declared_type"], "/list");
        assert_eq!(argument["list_element_type"], "/datum/item");
        assert!(argument["array"].is_null());
    }
    #[test]
    fn modified_values_export_structural_identity_without_source_offsets() {
        use super::*;
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/obj/base").unwrap();
        let lexical = symbols.intern("/datum/holder").unwrap();
        let capture = |source: &str| {
            let parsed = dm_syntax::parse_expression(source).expr.unwrap();
            let dm_syntax::ExprKind::ObjectInitializer { fields, .. } = parsed.kind else {
                panic!("modified expression")
            };
            SemanticValue::ModifiedInstance(std::sync::Arc::new(dm_ir::ModifiedInstance::capture(
                owner, lexical, None, &fields,
            )))
        };
        let first = constant(
            &capture("/obj/base{amount=1;amount=2;other=list(3)}"),
            &symbols,
        )
        .unwrap();
        let shifted = constant(
            &capture("  /obj/base { amount = 1; amount = 2; other = list(3) }"),
            &symbols,
        )
        .unwrap();
        assert_eq!(first, shifted);
        assert_eq!(first["kind"], "modified_instance");
        assert_eq!(first["runtime_type"], "/obj/base");
        assert_eq!(first["fields"][0]["name"], "amount");
        assert_eq!(first["fields"][1]["name"], "amount");
        assert_eq!(first["fields"][1]["value"]["text"], "2");
        assert_eq!(first["fields"][2]["value"]["kind"], "call");
        assert_ne!(
            first,
            constant(
                &capture("/obj/base{amount=2;amount=1;other=list(3)}"),
                &symbols
            )
            .unwrap()
        );
        let encoded = first.to_string();
        assert!(!encoded.contains("span"));
        assert!(!encoded.contains("lexical_owner"));
        assert!(!encoded.contains("arena"));
    }
    #[test]
    fn procedure_constants_export_structural_identity_separately_from_types() {
        let mut symbols = dm_ir::SymbolTable::default();
        let owner = symbols.intern("/datum/base").unwrap();
        let name = symbols.intern("callback").unwrap();
        let value = SemanticValue::Procedure(dm_ir::ProcedureIdentity {
            owner,
            name,
            verb: true,
            occurrence: 3,
        });
        assert_eq!(
            super::constant(&value, &symbols).unwrap(),
            json!({
                "kind":"procedure", "owner":"/datum/base", "name":"callback",
                "verb":true, "occurrence":3
            })
        );
    }
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
    #[test]
    fn guarded_setting_rows_export_proc_wide_order_and_current_source_separately() {
        let rows = source_rows("/proc/p()\n    if (1)\n        set waitfor = 0\n    else\n        set waitfor = 1\n    while (runtime_value)\n        set background = 1\n    return 2\n");
        let procedure = rows.iter().find(|row| row["kind"] == "proc").unwrap();
        let settings = &procedure["procedure"]["settings"];
        // Runtime guards do not condition ABI metadata. Both branches and the
        // loop contribute settings in lexical encounter order (DESIGN §4.4).
        assert_eq!(settings.as_array().unwrap().len(), 3);
        for setting in settings.as_array().unwrap() {
            assert_eq!(setting["kind"], "setting");
        }
        assert_eq!(settings[0]["name"], "waitfor");
        assert_eq!(settings[1]["name"], "waitfor");
        assert_eq!(settings[2]["name"], "background");
        assert_ne!(settings[0]["value"], settings[1]["value"]);
        let body = rows.iter().find(|row| row["row"] == "body").unwrap();
        assert_eq!(body["setting_context_origins"].as_array().unwrap().len(), 6);
        assert_eq!(body["setting_context_origins"][1]["line"], 3);
        assert_eq!(rows[0]["schema"], SCHEMA);
    }
}
/// Export already captured/planned maps without performing source I/O. This
/// supplemental schema reports authored semantics, not resolved engine values.
pub fn write_maps_jsonl(
    maps: &[dm_tree::maps::MapPlan],
    writer: &mut impl Write,
) -> Result<(), ExportError> {
    emit(
        writer,
        json!({"row":"map_schema","schema":"dm-symbolic-map-analysis-v1","status":"authored_unresolved","initializer_presence":"explicit"}),
    )?;
    for (map_index, map) in maps.iter().enumerate() {
        let templates=map.model.templates.iter().map(|template| {
            let atoms=template.atoms.iter().map(|atom| {
                let assignments=atom.assignments.iter().map(|assignment| Ok::<_,ExportError>(json!({"name":spelling(&map.symbols,assignment.name)?,"value":expression(Some(&assignment.value),&map.symbols)?}))).collect::<Result<Vec<_>,_>>()?;
                Ok::<_,ExportError>(json!({"type":spelling(&map.symbols,atom.type_path)?,"initializer_present":atom.initializer_present,"assignments":assignments}))
            }).collect::<Result<Vec<_>,_>>()?;
            Ok::<_,ExportError>(json!({"key":template.key,"atoms":atoms}))
        }).collect::<Result<Vec<_>,_>>()?;
        let records = map
            .model
            .records
            .iter()
            .map(|record| match record {
                dm_ir::map::MapRecord::Template(index) => json!({"kind":"template","index":index}),
                dm_ir::map::MapRecord::Block(index) => json!({"kind":"block","index":index}),
            })
            .collect::<Vec<_>>();
        emit(
            writer,
            json!({"row":"map_semantics","map":map_index,"identity":format!("{:032x}",map.semantic_identity),"key_width":map.model.key_width,"templates":templates,"blocks":map.model.blocks.iter().map(|block|json!({"origin":block.origin,"cells":block.cells})).collect::<Vec<_>>(),"records":records}),
        )?;
        emit(
            writer,
            json!({"row":"map_occurrence","map":map_index,"source_identity":format!("{:032x}",map.source_identity),"path":map.captured.path.to_string_lossy(),"include_occurrence":map.captured.include_occurrence,
            "templates":map.template_origins.iter().map(|template|json!({"span":[template.span.start,template.span.end],"atoms":template.atoms.iter().map(|atom|json!({"span":[atom.span.start,atom.span.end],"assignments":atom.assignments.iter().map(|assignment|json!({"span":[assignment.span.start,assignment.span.end],"value_span":[assignment.value_span.start,assignment.value_span.end]})).collect::<Vec<_>>()})).collect::<Vec<_>>()})).collect::<Vec<_>>() }),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod map_export_tests {
    use super::*;
    #[test]
    fn map_rows_keep_empty_initializer_and_repeated_writes() {
        let map = dm_tree::maps::plan(dm_tree::maps::CapturedMap {
            path: std::sync::Arc::new(std::path::PathBuf::from("probe.dmm")),
            include_occurrence: 9,
            source: std::sync::Arc::from("\"a\"=(/obj{},/obj{x=1;x=2})\n(1,1,1)={\"a\"}"),
        })
        .unwrap();
        let mut bytes = Vec::new();
        write_maps_jsonl(&[map], &mut bytes).unwrap();
        let rows: Vec<Value> = String::from_utf8(bytes)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(
            rows[1]["templates"][0]["atoms"][0]["initializer_present"],
            true
        );
        assert_eq!(
            rows[1]["templates"][0]["atoms"][1]["assignments"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert_eq!(rows[2]["include_occurrence"], 9);
        assert!(rows[1]["identity"].as_str().unwrap().len() == 32);
    }
}

mod roster_pages;
pub use roster_pages::{write_roster_page, SemanticRoster};
