//! Current-snapshot lexical bindings; this is not a complete semantic type model.
use super::{LexicalBody, ReferenceBinding, ReferenceSite};
use crate::tree_export::ExportError;
use dm_syntax::{BindingValue, NodeStep};
use serde_json::{json, Value};
use std::io::Write;

pub const SCHEMA: &str = "dm-lexical-body-analysis-v1";
pub(crate) fn path(steps: &[NodeStep]) -> Vec<Value> {
    steps
        .iter()
        .map(|step| match step {
            NodeStep::Statement(i) => json!(["statement", i]),
            NodeStep::Branch(i) => json!(["branch", i]),
            NodeStep::Expression(i) => json!(["expression", i]),
            NodeStep::Child(i) => json!(["child", i]),
        })
        .collect()
}
fn emit(writer: &mut impl Write, row: Value) -> Result<(), ExportError> {
    serde_json::to_writer(&mut *writer, &row).map_err(ExportError::Json)?;
    writer.write_all(b"\n").map_err(ExportError::Io)
}
/// Numeric binding IDs and structural paths are local to this current body.
/// Nonlocal meanings and unsupported expression roles stay explicit in rows.
pub fn write_jsonl(model: &LexicalBody<'_>, writer: &mut impl Write) -> Result<usize, ExportError> {
    let member = model.occurrence.member.0;
    let declaration = model.occurrence.declaration.0;
    let mut count = 0;
    for (id, binding) in model.scopes.declarations().iter().enumerate() {
        let meaning = match &binding.value {
            BindingValue::Parameter { ordinal } => json!({"kind":"argument","ordinal":ordinal}),
            BindingValue::Local(local) => json!({"kind":"local","path":path(&local.path),
                "header_span":[local.header_span.start,local.header_span.end]}),
        };
        emit(
            writer,
            json!({"schema":SCHEMA,"row":"lexical_binding","member":member,
            "declaration":declaration,"id":id,"name":binding.name.as_ref(),"meaning":meaning}),
        )?;
        count += 1;
    }
    for reference in &model.references {
        let binding = match &reference.binding {
            ReferenceBinding::Lexical(id) => json!({"kind":"lexical","id":id.0}),
            ReferenceBinding::RequiresSemanticResolver => {
                json!({"kind":"requires_semantic_resolver"})
            }
        };
        emit(
            writer,
            json!({"schema":SCHEMA,"row":"identifier_reference","member":member,
            "declaration":declaration,"name":reference.name.as_ref(),"path":path(&reference.path),
            "span":[reference.span.start,reference.span.end],"binding":binding,
            "access":match reference.access {super::ReferenceAccess::Read=>"read",super::ReferenceAccess::Write=>"write",super::ReferenceAccess::ReadWrite=>"read_write"},
            "site":match reference.site { ReferenceSite::Expression=>"expression",ReferenceSite::IteratorHeader=>"iterator_header" }}),
        )?;
        count += 1;
    }
    for gap in &model.gaps {
        emit(
            writer,
            json!({"schema":SCHEMA,"row":"binding_gap","member":member,"declaration":declaration,
            "path":path(&gap.path),"span":[gap.span.start,gap.span.end],"reason":gap.reason}),
        )?;
        count += 1;
    }
    for reference in &model.selectors {
        emit(
            writer,
            json!({"schema":SCHEMA,"row":"selector_reference","member":member,"declaration":declaration,
            "selector":reference.selector.as_ref(),"path":path(&reference.path),
            "span":[reference.span.start,reference.span.end],
            "receiver_path":reference.receiver_path.as_ref().map(|steps|path(steps)),
            "kind":match reference.kind {
                super::SelectorKind::Field=>"field",super::SelectorKind::StaticField=>"static_field",
                super::SelectorKind::Procedure=>"procedure",super::SelectorKind::NamedProcedure=>"named_procedure",
                super::SelectorKind::GlobalField=>"global_field",super::SelectorKind::GlobalProcedure=>"global_procedure" },
            "binding":"requires_semantic_resolver"}),
        )?;
        count += 1;
    }
    emit(
        writer,
        json!({"schema":SCHEMA,"row":"binding_summary","member":member,"declaration":declaration,
        "lexical_bindings":model.scopes.declarations().len(),"references":model.references.len(),
        "selectors":model.selectors.len(),"gaps":model.gaps.len(),"diagnostic_count":model.diagnostics.len(),"semantic_resolution_complete":false}),
    )?;
    Ok(count + 1)
}
