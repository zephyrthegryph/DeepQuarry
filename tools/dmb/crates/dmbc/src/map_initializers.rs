//! Exact ordered per-instance map assignment units over immutable resolver facts.
//! A map assignment is not a source variable declaration: inherited default/
//! modifier metadata is deliberately neither guessed nor copied into this input.
use crate::map_projection::{AtomOrigin, Projection};
use dm_ir::{
    InitializerTarget, ResolveQuery, ResolvedMeaning, Resolver, SymbolId, SymbolicExpression,
};
use dm_tree::maps::{AssignmentOrigin, MapPlan};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Assignment {
    pub target: InitializerTarget,
    pub lexical_owner: SymbolId,
    pub expression: SymbolicExpression,
}
#[derive(Clone, Debug)]
pub struct SourceOrigin {
    pub atom: AtomOrigin,
    pub assignment: usize,
    pub span: AssignmentOrigin,
}
#[derive(Clone, Debug)]
pub struct Unit {
    pub owner: SymbolId,
    /// Exact authored order, including repeated writes to the same field.
    pub assignments: Arc<[Assignment]>,
    pub origins: Arc<[SourceOrigin]>,
}
#[derive(Clone, Debug)]
pub struct Plan {
    /// One entry per symbolic map instance. None means no authored block;
    /// Some(empty) preserves authored {} and needs a distinct initializer record.
    pub units: Arc<[Option<Unit>]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidOrigin,
    MissingField { instance: usize, name: SymbolId },
    UnsupportedStorage { instance: usize, name: SymbolId },
    SharedField { instance: usize, name: SymbolId },
    InconsistentStorage { instance: usize, name: SymbolId },
}
impl Unit {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = b"byond-map-assignment-unit-v1\0".to_vec();
        bytes.extend_from_slice(&self.owner.bits().to_le_bytes());
        bytes.extend_from_slice(&(self.assignments.len() as u64).to_le_bytes());
        for assignment in self.assignments.iter() {
            // Only validated instance targets can be admitted to map units.
            match assignment.target {
                InitializerTarget::Instance {
                    declaring_owner,
                    receiver_owner,
                    name,
                } => {
                    bytes.push(0);
                    for id in [declaring_owner, receiver_owner, name] {
                        bytes.extend_from_slice(&id.bits().to_le_bytes());
                    }
                }
                InitializerTarget::Shared { slot, owner, name } => {
                    bytes.push(1);
                    for id in [slot, owner, name] {
                        bytes.extend_from_slice(&id.bits().to_le_bytes());
                    }
                }
                InitializerTarget::ProcedureStatic(identity) => {
                    // Retain exact identity for forged inputs; lower_unit rejects
                    // this storage domain because map atoms cannot own proc locals.
                    bytes.push(2);
                    bytes.extend_from_slice(&identity.canonical_bytes());
                }
            }
            bytes.extend_from_slice(&assignment.lexical_owner.bits().to_le_bytes());
            let expression = assignment.expression.canonical_bytes();
            bytes.extend_from_slice(&(expression.len() as u64).to_le_bytes());
            bytes.extend_from_slice(&expression);
        }
        bytes
    }
}
/// No default-value or constant classification is done here. The target backend
/// selects modifier-table vs callable representation from a proven map ABI.
pub fn plan<R: Resolver>(
    projection: &Projection,
    maps: &[MapPlan],
    resolver: &R,
) -> Result<Plan, Error> {
    let mut units = Vec::with_capacity(projection.instances.len());
    for (instance_index, instance) in projection.instances.iter().enumerate() {
        if !instance.atom.initializer_present {
            units.push(None);
            continue;
        }
        let atom_origin = instance.origin.ok_or(Error::InvalidOrigin)?;
        let map = maps.get(atom_origin.map).ok_or(Error::InvalidOrigin)?;
        let template = map
            .model
            .templates
            .get(atom_origin.template)
            .ok_or(Error::InvalidOrigin)?;
        let authored = template
            .atoms
            .get(atom_origin.atom)
            .ok_or(Error::InvalidOrigin)?;
        if authored != &instance.atom {
            return Err(Error::InvalidOrigin);
        }
        let origin = map
            .template_origins
            .get(atom_origin.template)
            .and_then(|template| template.atoms.get(atom_origin.atom))
            .ok_or(Error::InvalidOrigin)?;
        if origin.assignments.len() != authored.assignments.len() {
            return Err(Error::InvalidOrigin);
        }
        let owner = authored.type_path;
        let mut assignments = Vec::with_capacity(authored.assignments.len());
        let mut origins = Vec::with_capacity(authored.assignments.len());
        for (ordinal, assignment) in authored.assignments.iter().enumerate() {
            let name = assignment.name;
            let target = match resolver.resolve(ResolveQuery::VarStorage { owner, name }) {
                ResolvedMeaning::InstanceField {
                    declaring_owner,
                    name: actual_name,
                } if actual_name == name => InitializerTarget::Instance {
                    declaring_owner,
                    receiver_owner: owner,
                    name,
                },
                ResolvedMeaning::Slot { .. } => {
                    return Err(Error::SharedField {
                        instance: instance_index,
                        name,
                    })
                }
                ResolvedMeaning::Missing => {
                    return Err(Error::MissingField {
                        instance: instance_index,
                        name,
                    })
                }
                ResolvedMeaning::Unsupported(_) => {
                    return Err(Error::UnsupportedStorage {
                        instance: instance_index,
                        name,
                    })
                }
                _ => {
                    return Err(Error::InconsistentStorage {
                        instance: instance_index,
                        name,
                    })
                }
            };
            assignments.push(Assignment {
                target,
                lexical_owner: owner,
                expression: assignment.value.clone(),
            });
            origins.push(SourceOrigin {
                atom: atom_origin,
                assignment: ordinal,
                span: origin.assignments[ordinal].clone(),
            });
        }
        units.push(Some(Unit {
            owner,
            assignments: assignments.into(),
            origins: origins.into(),
        }));
    }
    Ok(Plan {
        units: units.into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::map_projection::{project, InstanceClassifier, InstanceKind, WorldDefaults};
    struct Facts {
        shared: bool,
    }
    impl Resolver for Facts {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::VarStorage { owner, name } if self.shared => ResolvedMeaning::Slot {
                    symbol: SymbolId::of("slot"),
                    owner,
                    name,
                },
                ResolveQuery::VarStorage { name, .. } => ResolvedMeaning::InstanceField {
                    declaring_owner: SymbolId::of("/obj"),
                    name,
                },
                ResolveQuery::HasMemberVar { .. } => ResolvedMeaning::Presence(true),
                ResolveQuery::DeclaredVarType { .. } => ResolvedMeaning::DeclaredType(None),
                _ => ResolvedMeaning::Missing,
            }
        }
    }
    struct Kinds;
    impl InstanceClassifier for Kinds {
        fn classify(&self, path: SymbolId) -> Result<InstanceKind, String> {
            if path == SymbolId::of("/turf") {
                Ok(InstanceKind::Turf)
            } else if path == SymbolId::of("/area") {
                Ok(InstanceKind::Area)
            } else {
                Ok(InstanceKind::Object)
            }
        }
    }
    fn fixture() -> (Vec<MapPlan>, Projection) {
        let maps = vec![dm_tree::maps::plan(dm_tree::maps::CapturedMap {
            path: Arc::new(std::path::PathBuf::from("probe.dmm")),
            include_occurrence: 1,
            source: Arc::from("\"a\"=(/obj,/obj{},/obj{x=1;x=2})\n(1,1,1)={\"a\"}"),
        })
        .unwrap()];
        let projection = project(
            &maps,
            WorldDefaults {
                turf: SymbolId::of("/turf"),
                area: SymbolId::of("/area"),
                minimum_dimensions: [1, 1, 1],
            },
            &Kinds,
        )
        .unwrap();
        (maps, projection)
    }
    #[test]
    fn absent_empty_and_repeated_assignments_remain_distinct() {
        let (maps, projection) = fixture();
        let result = plan(&projection, &maps, &Facts { shared: false }).unwrap();
        assert!(result.units[2].is_none());
        assert!(result.units[3].as_ref().unwrap().assignments.is_empty());
        let writes = &result.units[4].as_ref().unwrap().assignments;
        assert_eq!(writes.len(), 2);
        assert_ne!(writes[0].expression, writes[1].expression);
        assert_eq!(writes[0].target, writes[1].target);
        assert!(
            matches!(writes[0].target,InitializerTarget::Instance {declaring_owner,..} if declaring_owner==SymbolId::of("/obj"))
        );
        let origins = &result.units[4].as_ref().unwrap().origins;
        assert_eq!(origins[0].assignment, 0);
        assert_eq!(origins[1].assignment, 1);
        assert_ne!(origins[0].span.value_span, origins[1].span.value_span);
    }
    #[test]
    fn ordered_unit_lowers_once_and_empty_block_has_end() {
        let (maps, projection) = fixture();
        let host = Facts { shared: false };
        let planned = plan(&projection, &maps, &host).unwrap();
        for index in [3, 4] {
            let output = lower_unit(
                planned.units[index].as_ref().unwrap(),
                &maps,
                dm_codegen_byond::initializer::InitializerContext {
                    symbols: &maps[0].symbols,
                    resource_search_context: None,
                    debug: None,
                },
                &host,
            )
            .unwrap();
            assert!(
                matches!(output.procedure.code.items.last(),Some(dm_codegen_byond::Item::Instruction(instruction)) if instruction.opcode==byond_dmb::bytecode::opcode::END)
            );
            let writes=output.procedure.code.items.iter().filter(|item|matches!(item,dm_codegen_byond::Item::Instruction(instruction) if instruction.opcode==byond_dmb::bytecode::opcode::SET_VAR)).count();
            assert_eq!(writes, if index == 3 { 0 } else { 2 });
        }
    }
    #[test]
    fn shared_override_policy_is_not_guessed() {
        let (maps, projection) = fixture();
        assert!(matches!(
            plan(&projection, &maps, &Facts { shared: true }),
            Err(Error::SharedField { .. })
        ));
    }
}

#[derive(Debug)]
pub enum LowerError {
    InvalidSource,
    Expression {
        assignment: usize,
        diagnostics: Vec<dm_syntax::Diagnostic>,
    },
    Backend(dm_codegen_byond::initializer::InitializerError),
}
/// Lower one complete ordered unit, with one END and one label/reference
/// namespace. AST spans refer to the captured map's exact source bytes, so a
/// supplied debug provider can use the authored map path/line directly.
pub fn lower_unit<R: Resolver>(
    unit: &Unit,
    maps: &[MapPlan],
    context: dm_codegen_byond::initializer::InitializerContext<'_>,
    host: &R,
) -> Result<dm_codegen_byond::lower_resolver::ResolverProc, LowerError> {
    let expressions = prepare_unit_expressions(unit, maps)?;
    dm_codegen_byond::initializer::lower_assignments(&expressions, unit.owner, context, host)
        .map_err(LowerError::Backend)
}
/// Current captured roots used by both ordinary lowering and retained sidecar
/// reissue. Neither a model expression nor a retained span authorizes this parse.
pub(crate) fn prepare_unit_expressions(
    unit: &Unit,
    maps: &[MapPlan],
) -> Result<Vec<(InitializerTarget, SymbolId, dm_syntax::Expr)>, LowerError> {
    if unit.assignments.len() != unit.origins.len() {
        return Err(LowerError::InvalidSource);
    }
    let mut expressions = Vec::with_capacity(unit.assignments.len());
    for (ordinal, (assignment, origin)) in
        unit.assignments.iter().zip(unit.origins.iter()).enumerate()
    {
        let map = maps.get(origin.atom.map).ok_or(LowerError::InvalidSource)?;
        let authored = map
            .model
            .templates
            .get(origin.atom.template)
            .and_then(|template| template.atoms.get(origin.atom.atom))
            .and_then(|atom| atom.assignments.get(origin.assignment))
            .ok_or(LowerError::InvalidSource)?;
        if authored.value != assignment.expression
            || authored.name
                != match assignment.target {
                    InitializerTarget::Instance { name, .. }
                    | InitializerTarget::Shared { name, .. } => name,
                    InitializerTarget::ProcedureStatic(_) => return Err(LowerError::InvalidSource),
                }
        {
            return Err(LowerError::InvalidSource);
        }
        let text = map
            .captured
            .source
            .get(origin.span.value_span.range())
            .ok_or(LowerError::InvalidSource)?;
        let mut parsed = dm_syntax::parse_expression(text);
        for diagnostic in &mut parsed.diagnostics {
            diagnostic.span.start += origin.span.value_span.start;
            diagnostic.span.end += origin.span.value_span.start;
        }
        if !parsed.diagnostics.is_empty() {
            return Err(LowerError::Expression {
                assignment: ordinal,
                diagnostics: parsed.diagnostics,
            });
        }
        let mut value = parsed.expr.ok_or(LowerError::InvalidSource)?;
        offset_expression(&mut value, origin.span.value_span.start);
        expressions.push((assignment.target.clone(), assignment.lexical_owner, value));
    }
    Ok(expressions)
}
fn offset_expression(expression: &mut dm_syntax::Expr, offset: usize) {
    use dm_syntax::ExprKind;
    expression.span.start += offset;
    expression.span.end += offset;
    match &mut expression.kind {
        ExprKind::Ident(_) | ExprKind::Literal(_) | ExprKind::TypePath(_) => {}
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => offset_expression(value, offset),
        ExprKind::Binary { lhs, rhs, .. } => {
            offset_expression(lhs, offset);
            offset_expression(rhs, offset);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            for value in [condition, then_value, else_value] {
                offset_expression(value, offset);
            }
        }
        ExprKind::Call { callee, args } => {
            offset_expression(callee, offset);
            for value in args {
                offset_expression(value, offset);
            }
        }
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => offset_expression(object, offset),
        ExprKind::ObjectInitializer { object, fields } => {
            offset_expression(object, offset);
            for (_, value) in fields {
                offset_expression(value, offset);
            }
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            offset_expression(object, offset);
            offset_expression(index, offset);
        }
    }
}
