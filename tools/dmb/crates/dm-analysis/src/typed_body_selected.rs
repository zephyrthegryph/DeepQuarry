//! Bind admitted compiler-selection payloads to the current authenticated source.
//! Dependency freshness belongs to the artifact admission path, not this exporter.
use dm_ir::{SelectedMeaning, SelectedReferences, SymbolId};
use dm_syntax::{Expr, ExprKind, NodeStep, TypedVisitor, VisitDecision};
use dm_tree::frontend::{ColdFrontend, ParsedBody};
use std::collections::{HashMap, HashSet};
use std::io::Write;

pub const SCHEMA: &str = "dm-selected-reference-analysis-v1";
#[path = "typed_body_selected_bound.rs"]
mod bound;
pub use bound::{write_bound_jsonl, BoundReference, SelectionCoverage};
#[cfg(test)]
#[path = "typed_body_selected_tests.rs"]
mod tests;

/// No rows are written until every retained coordinate/name matches this issued body.
pub fn write_jsonl(
    frontend: &ColdFrontend,
    body: &ParsedBody,
    selections: &SelectedReferences,
    writer: &mut impl Write,
) -> Result<usize, String> {
    frontend
        .validate_parsed_body(body, body.occurrence())
        .map_err(|error| format!("{error:?}"))?;
    let statements = body
        .statement_body()
        .ok_or("body has no typed statement model")?;
    let mut index = NodeIndex {
        wanted: selections
            .references
            .iter()
            .map(|reference| reference.path.as_slice())
            .collect(),
        nodes: HashMap::new(),
    };
    dm_syntax::visit_statements(&statements.parsed().statements, &mut index);
    for reference in &selections.references {
        let node = index
            .nodes
            .get(&reference.path)
            .ok_or("selected reference path is absent from current body")?;
        if SymbolId::of(&node.name) != reference.name {
            return Err("selected reference name does not match current body node".into());
        }
        if !reference.meaning.structurally_valid() || !node.supports(&reference.meaning) {
            return Err("selected reference meaning does not match current typed node role".into());
        }
    }
    let mut count = 0;
    let occurrence = body.occurrence();
    for reference in &selections.references {
        let node = &index.nodes[&reference.path];
        let row = reference_json(
            occurrence,
            reference.name,
            Some(&node.name),
            &reference.meaning,
            &reference.path,
            node.span.start,
            node.span.end,
        );
        serde_json::to_writer(&mut *writer, &row).map_err(|error| error.to_string())?;
        writer.write_all(b"\n").map_err(|error| error.to_string())?;
        count += 1;
    }
    serde_json::to_writer(
        &mut *writer,
        &serde_json::json!({"schema":SCHEMA,
        "row":"selected_reference_summary","member":occurrence.member.0,
        "declaration":occurrence.declaration.0,"references":count,
        "semantic_resolution_complete":selections.complete,
        "coverage_policy":std::str::from_utf8(dm_ir::SELECTED_REFERENCES_POLICY).expect("ASCII policy"),
        "unbound_selections":selections.unbound_selections}),
    )
    .map_err(|error| error.to_string())?;
    writer.write_all(b"\n").map_err(|error| error.to_string())?;
    Ok(count)
}
fn reference_json(
    occurrence: &dm_tree::frontend::BodyOccurrence,
    name: SymbolId,
    spelling: Option<&str>,
    meaning: &SelectedMeaning,
    path: &[NodeStep],
    start: usize,
    end: usize,
) -> serde_json::Value {
    serde_json::json!({"schema":SCHEMA,"row":"selected_reference",
        "member":occurrence.member.0,"declaration":occurrence.declaration.0,
        "path":super::lexical::jsonl::path(path),"name":spelling,"name_symbol":name,
        "start":start,"end":end,"meaning":meaning_json(meaning)})
}
struct NodeLocation {
    name: String,
    span: dm_syntax::Span,
    role: NodeRole,
}
#[derive(Clone, Copy)]
enum NodeRole {
    Identifier,
    Property {
        safe: bool,
        static_property: bool,
    },
    Dynamic {
        dispatcher: SymbolId,
        target_count: usize,
    },
}
impl NodeLocation {
    fn supports(&self, meaning: &SelectedMeaning) -> bool {
        use SelectedMeaning as M;
        match meaning {
            M::RuntimeProperty {
                safe,
                static_property,
                ..
            } => {
                matches!(self.role,NodeRole::Property{safe:current_safe,static_property:current_static} if current_safe==*safe && current_static==*static_property)
            }
            M::ProcedureCall { safe, .. } | M::DynamicProcedure { safe, .. } => match self.role {
                NodeRole::Identifier => !*safe,
                NodeRole::Property {
                    safe: current_safe,
                    static_property: false,
                } => current_safe == *safe,
                _ => false,
            },
            M::DynamicCall {
                dispatcher,
                target_count,
            } => {
                matches!(self.role,NodeRole::Dynamic{dispatcher:current,target_count:count} if current==*dispatcher && count==usize::from(*target_count))
            }
            M::SharedStorage(_) => !matches!(self.role, NodeRole::Dynamic { .. }),
            M::Literal => {
                matches!(self.role, NodeRole::Identifier)
                    && dm_syntax::is_literal_identifier(&self.name)
            }
            _ => matches!(self.role, NodeRole::Identifier),
        }
    }
}
struct NodeIndex<'a> {
    wanted: HashSet<&'a [NodeStep]>,
    nodes: HashMap<Vec<NodeStep>, NodeLocation>,
}
impl TypedVisitor for NodeIndex<'_> {
    fn expression(&mut self, node: &Expr, path: &[NodeStep]) -> VisitDecision {
        if self.wanted.contains(path) {
            if let Some(name) = dm_syntax::reference_node_name(node) {
                let role = match &node.kind {
                    ExprKind::Ident(_) => NodeRole::Identifier,
                    ExprKind::Member { .. } => NodeRole::Property {
                        safe: false,
                        static_property: false,
                    },
                    ExprKind::SafeMember { .. } => NodeRole::Property {
                        safe: true,
                        static_property: false,
                    },
                    ExprKind::StaticMember { .. } => NodeRole::Property {
                        safe: false,
                        static_property: true,
                    },
                    _ => match dm_syntax::call_target(node) {
                        dm_syntax::CallTarget::Dynamic {
                            dispatcher,
                            targets,
                        } => NodeRole::Dynamic {
                            dispatcher: SymbolId::of(dispatcher),
                            target_count: targets.len(),
                        },
                        _ => return VisitDecision::Descend,
                    },
                };
                self.nodes.insert(
                    path.to_vec(),
                    NodeLocation {
                        name: name.to_owned(),
                        span: node.span,
                        role,
                    },
                );
            }
        }
        VisitDecision::Descend
    }
}
fn meaning_json(meaning: &SelectedMeaning) -> serde_json::Value {
    use SelectedMeaning as M;
    match meaning {
        M::Local(ordinal) => serde_json::json!({"kind":"local","ordinal":ordinal}),
        M::Argument(ordinal) => serde_json::json!({"kind":"argument","ordinal":ordinal}),
        M::SharedStorage(reference) => {
            serde_json::json!({"kind":"shared_storage","reference":reference})
        }
        M::InstanceField { owner, name } => {
            serde_json::json!({"kind":"instance_field","owner":owner,"name":name})
        }
        M::Builtin(builtin) => {
            serde_json::json!({"kind":"builtin","builtin":format!("{builtin:?}")})
        }
        M::Literal => serde_json::json!({"kind":"literal"}),
        M::NumericConstant(bits) => serde_json::json!({"kind":"numeric_constant","bits":bits}),
        M::StringConstant(id) => serde_json::json!({"kind":"string_constant","symbol":id}),
        M::ProcedureValue(reference) => {
            serde_json::json!({"kind":"procedure_value","reference":reference})
        }
        M::TypeValue(id) => serde_json::json!({"kind":"type_value","symbol":id}),
        M::RuntimeProperty {
            name,
            static_property,
            safe,
        } => {
            serde_json::json!({"kind":"runtime_property","name":name,"static":static_property,"safe":safe})
        }
        M::ProcedureCall { reference, safe } => {
            serde_json::json!({"kind":"procedure_call","reference":reference,"safe":safe})
        }
        M::DynamicProcedure { selector, safe } => {
            serde_json::json!({"kind":"dynamic_procedure","selector":selector,"safe":safe})
        }
        M::DynamicCall {
            dispatcher,
            target_count,
        } => {
            serde_json::json!({"kind":"dynamic_call","dispatcher":dispatcher,"target_count":target_count})
        }
        M::IntrinsicCall(name) => serde_json::json!({"kind":"intrinsic_call","name":name}),
    }
}
