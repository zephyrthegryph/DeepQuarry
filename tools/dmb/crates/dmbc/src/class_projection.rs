//! Immutable source class/member projection for the cold writer. Wire allocation
//! remains separate: instance declarations are variable records, shared fields
//! additionally acquire VM footer slots, and field selectors remain strings.
use crate::initializer_policy::DefaultValue;
use dm_ir::{SemanticValue, SymbolId, SymbolicExpression};
use dm_link::Key;
use dm_tree::{DefinitionMode, MemberKind, OccurrenceId, Target, TreeSnapshot};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    sync::Arc,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProjectionError {
    IdentityMismatch,
    InvalidOccurrence(OccurrenceId),
    IncompleteOrder,
    MissingMember,
    OpaqueField { owner: SymbolId, name: SymbolId },
    Unsupported(String),
    Evaluation(String),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TypeProjection {
    pub path: SymbolId,
    pub parent: Option<SymbolId>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FieldRole {
    Declaration,
    Assignment,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FieldProjection {
    pub owner: SymbolId,
    pub declaring_owner: SymbolId,
    pub name: SymbolId,
    pub role: FieldRole,
    /// Backend declaration flags, distinct from source modifier bits.
    pub wire_flags: Option<u32>,
    pub intrinsic: bool,
    pub shared: bool,
    pub value: DefaultValue,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProcedureChain {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub verb: bool,
    pub entries: Arc<[Key]>,
}
#[derive(Clone, Debug)]
pub struct ClassProjection {
    /// Exact source occurrence mode for physical proc/verb namespace paths.
    pub procedure_declarations: Arc<BTreeMap<Key, bool>>,
    pub shared_slot_order: Arc<[Key]>,
    pub procedure_statics: Arc<[ProcedureStaticProjection]>,
    pub runtime_writes: Arc<[(usize, dm_link::InitializerIdentity)]>,
    pub tree_identity: u128,
    pub occurrence_count: usize,
    pub types: Arc<[TypeProjection]>,
    /// Original occurrence order; writer emits formal declarations separately
    /// from assignment records, retaining each ordered assignment.
    pub fields: Arc<[FieldProjection]>,
    pub chains: Arc<[ProcedureChain]>,
}
#[derive(Clone, Debug)]
pub struct ProcedureStaticProjection {
    pub identity: dm_ir::ProcedureStaticIdentity,
    pub wire_flags: u32,
    pub value: DefaultValue,
    pub source_ordinal: usize,
}
/// Evaluator reads only a captured immutable resolver/configuration. Dynamic
/// initializers must use initializer artifacts; failures are not replaced by0.
pub trait CapturedFieldEvaluator {
    fn evaluate(
        &self,
        owner: SymbolId,
        value: &SymbolicExpression,
    ) -> Result<SemanticValue, String>;
}
fn wire_flags(flags: u32, owner: SymbolId) -> Result<(u32, bool), ProjectionError> {
    if flags & !15 != 0 {
        return Err(ProjectionError::Unsupported(
            "unknown source variable modifiers".into(),
        ));
    }
    let shared = owner == SymbolId::of("/") || flags & 11 != 0;
    let flags = (if flags & 2 != 0 {
        3
    } else if shared {
        1
    } else {
        0
    }) | (flags & 4);
    Ok((flags, shared))
}
pub fn project(
    source: &TreeSnapshot,
    order: &[OccurrenceId],
    evaluator: &dyn CapturedFieldEvaluator,
) -> Result<ClassProjection, ProjectionError> {
    project_inner(source, order, evaluator, None)
}
pub fn project_classified(
    source: &TreeSnapshot,
    order: &[OccurrenceId],
    plan: &dm_tree::initializers::InitializerPlan,
    classified: &crate::initializer_policy::ClassifiedInitializers,
    units: &[crate::initializer_lowering::LoweredInitializerUnit],
) -> Result<ClassProjection, ProjectionError> {
    struct NoEvaluation;
    impl CapturedFieldEvaluator for NoEvaluation {
        fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<SemanticValue, String> {
            Err("classified source default is absent".into())
        }
    }
    if plan.source.tree.identity() != source.tree.identity() {
        return Err(ProjectionError::IdentityMismatch);
    }
    let ledger = crate::class_initialization::admit_lowered(plan, classified, units)
        .map_err(ProjectionError::Unsupported)?;
    let mut projection = project_inner(source, order, &NoEvaluation, Some(&ledger))?;
    let mut statics = Vec::new();
    for default in &ledger.defaults {
        if let dm_tree::initializers::InitializerOriginKind::ProcedureStatic { identity, .. } =
            &default.origin_kind
        {
            let write = plan
                .writes
                .get(default.source_ordinal)
                .ok_or(ProjectionError::MissingMember)?;
            let flags = write.declaration_flags.ok_or_else(|| {
                ProjectionError::Unsupported("static modifier knowledge missing".into())
            })?;
            let (flags, shared) = wire_flags(flags, identity.procedure.owner)?;
            if !shared {
                return Err(ProjectionError::Unsupported(
                    "procedure static lacks shared storage modifiers".into(),
                ));
            }
            statics.push(ProcedureStaticProjection {
                identity: *identity,
                wire_flags: flags,
                value: default.value.clone(),
                source_ordinal: default.source_ordinal,
            });
        }
    }
    projection.procedure_statics = statics.into();
    let mut order = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for default in &ledger.defaults {
        let write = &plan.writes[default.source_ordinal];
        let key = match &default.origin_kind {
            dm_tree::initializers::InitializerOriginKind::ProcedureStatic { identity, .. } => {
                Some(Key::ProcedureStatic(*identity))
            }
            dm_tree::initializers::InitializerOriginKind::Declaration(member)
                if source
                    .tree
                    .member(*member)
                    .is_some_and(|member| member.definition == DefinitionMode::Declare) =>
            {
                match write.target {
                    dm_ir::InitializerTarget::Shared { owner, name, .. } => {
                        Some(Key::Variable { owner, name })
                    }
                    _ => None,
                }
            }
            _ => None,
        };
        if let Some(key) = key {
            if seen.insert(key) {
                order.push(key);
            }
        }
    }
    projection.shared_slot_order = order.into();
    Ok(projection)
}
fn project_inner(
    source: &TreeSnapshot,
    order: &[OccurrenceId],
    evaluator: &dyn CapturedFieldEvaluator,
    defaults: Option<&crate::class_initialization::DefaultLedger>,
) -> Result<ClassProjection, ProjectionError> {
    if source.tree.identity() != source.occurrences.tree_identity() {
        return Err(ProjectionError::IdentityMismatch);
    }
    let occurrences = source.occurrences.source_order();
    if occurrences.len() != order.len() {
        return Err(ProjectionError::IncompleteOrder);
    }
    let tree = &source.tree;
    let types = tree
        .types()
        .iter()
        .map(|node| TypeProjection {
            path: node.path,
            parent: node
                .parent
                .and_then(|id| tree.type_node(id))
                .map(|parent| parent.path),
        })
        .collect::<Vec<_>>();
    let mut seen = HashSet::new();
    let mut fields = Vec::new();
    let default_index: HashMap<_, _> = defaults
        .into_iter()
        .flat_map(|ledger| ledger.defaults.iter())
        .filter(|value| {
            matches!(
                value.origin_kind,
                dm_tree::initializers::InitializerOriginKind::Declaration(_)
            )
        })
        .map(|value| (value.occurrence, &value.value))
        .collect();
    let mut procedure_declarations = BTreeMap::new();
    let mut group_order = Vec::new();
    let mut procs: BTreeMap<(SymbolId, SymbolId, bool), Vec<(bool, Key)>> = BTreeMap::new();
    for &id in order {
        if !seen.insert(id) {
            return Err(ProjectionError::IncompleteOrder);
        }
        let occurrence = source
            .occurrences
            .get(id)
            .ok_or(ProjectionError::InvalidOccurrence(id))?;
        let Target::Member(member_id) = occurrence.target else {
            continue;
        };
        let member = tree
            .member(member_id)
            .ok_or(ProjectionError::MissingMember)?;
        let owner = tree
            .type_node(member.owner)
            .ok_or(ProjectionError::MissingMember)?
            .path;
        match member.kind {
            MemberKind::Var => {
                let metadata = &member.metadata;
                if metadata.array.is_some() && defaults.is_none() {
                    return Err(ProjectionError::Unsupported(
                        "array defaults need initializer materialization".into(),
                    ));
                }
                let role = if member.definition == DefinitionMode::Declare {
                    FieldRole::Declaration
                } else {
                    FieldRole::Assignment
                };
                let (flags, shared, declaring_owner, intrinsic) =
                    if let Some(base) = &metadata.inherited_opaque {
                        if role == FieldRole::Declaration {
                            return Err(ProjectionError::OpaqueField {
                                owner,
                                name: member.name,
                            });
                        }
                        match dm_ir::Resolver::resolve(
                            tree.as_ref(),
                            dm_ir::ResolveQuery::VarStorage {
                                owner,
                                name: member.name,
                            },
                        ) {
                            dm_ir::ResolvedMeaning::InstanceField {
                                declaring_owner,
                                name,
                            } if name == member.name => (None, false, declaring_owner, true),
                            dm_ir::ResolvedMeaning::Slot {
                                owner: slot_owner,
                                name,
                                ..
                            } if name == member.name => (None, true, slot_owner, true),
                            _ => {
                                return Err(ProjectionError::OpaqueField {
                                    owner: base.owner,
                                    name: member.name,
                                })
                            }
                        }
                    } else {
                        let (flags, shared) = wire_flags(metadata.flags, owner)?;
                        let mut declaration = member;
                        while declaration.definition != DefinitionMode::Declare {
                            declaration = tree
                                .member(declaration.previous.ok_or(ProjectionError::MissingMember)?)
                                .ok_or(ProjectionError::MissingMember)?;
                        }
                        let declaring_owner = tree
                            .type_node(declaration.owner)
                            .ok_or(ProjectionError::MissingMember)?
                            .path;
                        (Some(flags), shared, declaring_owner, false)
                    };
                let expression = if role == FieldRole::Declaration {
                    metadata.declared_initializer.as_ref()
                } else {
                    metadata.initializer.as_ref()
                };
                let value = if let Some(value) = default_index.get(&id) {
                    (*value).clone()
                } else {
                    if defaults.is_some() {
                        return Err(ProjectionError::Unsupported(
                            "classified source occurrence default is absent".into(),
                        ));
                    }
                    DefaultValue::Scalar(match expression {
                        Some(value) => evaluator
                            .evaluate(owner, value)
                            .map_err(ProjectionError::Evaluation)?,
                        None if role == FieldRole::Declaration => SemanticValue::Null,
                        None => {
                            return Err(ProjectionError::Unsupported(
                                "assignment has no authored value".into(),
                            ))
                        }
                    })
                };
                // Mutable lists have occurrence identity and cannot be merged as
                // scalar records; the initializer linker must materialize them.
                if matches!(value, DefaultValue::Scalar(SemanticValue::List(_))) {
                    return Err(ProjectionError::Unsupported(
                        "list defaults need occurrence-specific materialization".into(),
                    ));
                }
                fields.push(FieldProjection {
                    owner,
                    declaring_owner,
                    name: member.name,
                    role,
                    wire_flags: flags,
                    intrinsic,
                    shared,
                    value,
                });
            }
            MemberKind::Proc | MemberKind::Verb => {
                let verb = member.kind == MemberKind::Verb;
                let depth = tree
                    .override_chain(member_id)
                    .iter()
                    .filter(|id| {
                        tree.member(**id).is_some_and(|previous| {
                            previous.owner == member.owner
                                && previous.kind == member.kind
                                && previous.name == member.name
                        })
                    })
                    .count()
                    .checked_sub(1)
                    .ok_or(ProjectionError::MissingMember)?;
                let occurrence = u32::try_from(depth).map_err(|_| {
                    ProjectionError::Unsupported("procedure occurrence overflow".into())
                })?;
                let key = if verb {
                    Key::Verb {
                        owner,
                        name: member.name,
                        occurrence,
                    }
                } else {
                    Key::Proc {
                        owner,
                        name: member.name,
                        occurrence,
                    }
                };
                procedure_declarations.insert(key, member.definition == DefinitionMode::Declare);
                if !procs.contains_key(&(owner, member.name, verb)) {
                    group_order.push((owner, member.name, verb));
                }
                procs
                    .entry((owner, member.name, verb))
                    .or_default()
                    .push((member.definition == DefinitionMode::Declare, key));
            }
        }
    }
    let chains = group_order
        .into_iter()
        .map(|(owner, name, verb)| {
            let entries = procs
                .remove(&(owner, name, verb))
                .expect("encounter group recorded once");
            // BYOND evidence: formal base is below implicit overrides regardless of
            // its encounter position; implicit overrides retain encounter precedence.
            let mut formal = Vec::new();
            let mut implicit = Vec::new();
            for (declared, key) in entries {
                if declared {
                    formal.push(key)
                } else {
                    implicit.push(key)
                }
            }
            implicit.reverse();
            formal.reverse();
            implicit.extend(formal);
            ProcedureChain {
                owner,
                name,
                verb,
                entries: implicit.into(),
            }
        })
        .collect::<Vec<_>>();
    Ok(ClassProjection {
        procedure_declarations: Arc::new(procedure_declarations),
        shared_slot_order: fields
            .iter()
            .filter(|field| field.role == FieldRole::Declaration && field.shared)
            .map(|field| Key::Variable {
                owner: field.owner,
                name: field.name,
            })
            .collect::<Vec<_>>()
            .into(),
        procedure_statics: Arc::from([]),
        runtime_writes: defaults
            .into_iter()
            .flat_map(|ledger| ledger.defaults.iter())
            .filter(|value| value.runtime)
            .map(|value| (value.source_ordinal, value.initializer))
            .collect::<Vec<_>>()
            .into(),
        tree_identity: tree.identity(),
        occurrence_count: occurrences.len(),
        types: types.into(),
        fields: fields.into(),
        chains: chains.into(),
    })
}

/// Materialize source type records from their actual parent's pinned/native ABI.
/// This stage writes only type skeletons. Field defaults, proc chains and world
/// metadata are separate mandatory stages, never implicitly reported complete.
/// Canonical type IDs come from LinkTables and are checked against retained paths.
pub fn materialize_types(
    dmb: &mut byond_dmb::dmb::Dmb,
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
) -> Result<(), ProjectionError> {
    use byond_dmb::{dmb::Class, ids::NONE};
    let spelling = |symbol| {
        symbols.text(symbol).ok_or_else(|| {
            ProjectionError::Unsupported(format!("missing type spelling {symbol:?}"))
        })
    };
    let mut retained = HashMap::new();
    for (index, class) in dmb.classes.iter().enumerate() {
        let bytes = dmb
            .string(class.path_string_id())
            .ok_or_else(|| ProjectionError::Unsupported("retained class path missing".into()))?;
        let symbol = SymbolId::of_bytes(bytes);
        if spelling(symbol)?.as_bytes() != bytes || retained.insert(symbol, index as u32).is_some()
        {
            return Err(ProjectionError::Unsupported(
                "ambiguous retained class identity".into(),
            ));
        }
    }
    let mut planned = BTreeMap::new();
    let mut type_ids = retained.clone();
    for ty in projection.types.iter() {
        let path = spelling(ty.path)?;
        if path == "/" || path == "/world" {
            continue;
        }
        let index = tables
            .index(Key::Type(ty.path))
            .or_else(|| retained.get(&ty.path).copied())
            .ok_or_else(|| ProjectionError::Unsupported(format!("unbound type {path}")))?;
        if let Some(&retained_index) = retained.get(&ty.path) {
            if index != retained_index {
                return Err(ProjectionError::Unsupported(
                    "canonical engine type remap".into(),
                ));
            }
            let expected_parent = match ty.parent {
                None => NONE,
                Some(parent) if spelling(parent)? == "/" => NONE,
                Some(parent) => tables
                    .index(Key::Type(parent))
                    .or_else(|| retained.get(&parent).copied())
                    .ok_or_else(|| {
                        ProjectionError::Unsupported("unbound retained class parent".into())
                    })?,
            };
            // Authored parent_type changes the parent edge, not the retained
            // engine class identity or its opaque native header metadata.
            // Apply before cloning retained prototypes for fresh descendants.
            dmb.classes[retained_index as usize].initial_ids[1] = expected_parent;
            continue;
        }
        if (index as usize) < dmb.classes.len()
            || index == NONE
            || planned.insert(index, ty).is_some()
        {
            return Err(ProjectionError::Unsupported(
                "source class index collides with retained/sentinel record".into(),
            ));
        }
        type_ids.insert(ty.path, index);
    }
    for (ordinal, &index) in planned.keys().enumerate() {
        if index as usize != dmb.classes.len() + ordinal {
            return Err(ProjectionError::Unsupported(
                "noncontiguous canonical class indexes".into(),
            ));
        }
    }
    let mut strings = crate::composition::StringIndex::build(dmb)
        .map_err(|e| ProjectionError::Unsupported(format!("type strings {e:?}")))?;
    let mut constructed: BTreeMap<u32, Class> = BTreeMap::new();
    let parents = planned.iter().map(|(&index, ty)| {
        let parent = ty
                .parent
                .and_then(|symbol| type_ids.get(&symbol).copied())
                .ok_or_else(|| {
                    ProjectionError::Unsupported(format!("unproven source class parent ABI: class={}, index={index}, semantic_parent={:?}",
                        spelling(ty.path).unwrap_or("<unknown>"),
                        ty.parent.and_then(|parent| symbols.text(parent))))
                })?;
        Ok((index, parent))
    }).collect::<Result<BTreeMap<_, _>, ProjectionError>>()?;
    for wave in class_construction_waves(&parents, dmb.classes.len())? {
        for index in wave {
            let ty = planned[&index];
            let parent = parents[&index];
            let mut record = dmb
                .classes
                .get(parent as usize)
                .or_else(|| constructed.get(&parent))
                .ok_or_else(|| {
                    ProjectionError::Unsupported("unavailable parent class record".into())
                })?
                .clone();
            let path = spelling(ty.path)?;
            let display = path.rsplit('/').next().unwrap_or(path).replace('_', " ");
            let letter = display.chars().take(1).collect::<String>();
            record.initial_ids[0] = strings
                .intern(dmb, path.as_bytes())
                .map_err(|e| ProjectionError::Unsupported(format!("type path {e:?}")))?;
            record.initial_ids[1] = parent;
            record.initial_ids[2] = strings
                .intern(dmb, display.as_bytes())
                .map_err(|e| ProjectionError::Unsupported(format!("type display {e:?}")))?;
            record.text = strings
                .intern(dmb, letter.as_bytes())
                .map_err(|e| ProjectionError::Unsupported(format!("type letter {e:?}")))?;
            record.lists_and_procs = [NONE; 6];
            record.overrides = NONE;
            constructed.insert(index, record);
        }
    }
    for (_, record) in constructed {
        dmb.classes.push(record);
    }
    Ok(())
}

#[path = "class_projection/members.rs"]
mod members;
pub use members::materialize_members;

fn encoded_constant(kind: u8, value: u32) -> Result<Vec<u32>, ProjectionError> {
    if kind != 42 && value > 0x00ff_ffff {
        return Err(ProjectionError::Unsupported(
            "constant ID exceeds packed24".into(),
        ));
    }
    let operand = if kind == 42 {
        byond_dmb::operands::Value {
            tag_word: 42,
            data_word: value >> 16,
            extra_word: Some(value & 0xffff),
        }
    } else {
        byond_dmb::operands::Value {
            tag_word: u32::from(kind) | ((value >> 16) << 8),
            data_word: value & 0xffff,
            extra_word: None,
        }
    };
    Ok(operand.encode())
}
/// Runtime-family tags must be proved by the captured resolver/target schema;
/// modifiers/aliases cannot be inferred from the type path spelling alone.
pub trait TypeValuePolicy {
    /// Captured semantic content key; a dense resource ID is allocated later by
    /// the shared linker. Runtime CRC and class IDs are different namespaces.
    fn resource_key(&self, _path: SymbolId) -> Result<Key, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "resource content domain was not captured".into(),
        ))
    }
    /// Mob-table identity is a separate domain from class-table identity.
    fn mob_index(&self, _path: SymbolId) -> Result<u32, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "mob table inventory was not captured".into(),
        ))
    }
    fn resource_index(&self, _path: SymbolId) -> Result<u32, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "resource domain was not captured".into(),
        ))
    }
    fn tag(&self, path: SymbolId) -> Result<u8, ProjectionError>;
}

fn client_header_directives(
    fields: &[FieldProjection],
    owner_order: &[SymbolId],
    symbols: &dm_ir::SymbolTable,
) -> Result<Vec<crate::client_projection::Directive>, ProjectionError> {
    let mut by_owner: HashMap<SymbolId, Vec<&FieldProjection>> = HashMap::new();
    for field in fields.iter().filter(|field| field.intrinsic) {
        by_owner.entry(field.owner).or_default().push(field);
    }
    let mut directives = Vec::new();
    for owner in owner_order {
        for field in by_owner.get(owner).into_iter().flatten() {
            let name = symbols.text(field.name).ok_or_else(|| {
                ProjectionError::Unsupported("client field spelling missing".into())
            })?;
            if !crate::client_projection::is_header_field(name) {
                continue;
            }
            let DefaultValue::Scalar(value) = &field.value else {
                return Err(ProjectionError::Unsupported(
                    "client header requires scalar default".into(),
                ));
            };
            if let Some(directive) = crate::client_projection::project(name, value)
                .map_err(|error| ProjectionError::Unsupported(format!("client policy {error:?}")))?
            {
                directives.push(directive);
            }
        }
    }
    Ok(directives)
}

/// Preserve the old sorted readiness waves, including string-intern order,
/// without rescanning every pending class at each inheritance depth.
fn class_construction_waves(
    parents: &BTreeMap<u32, u32>,
    retained: usize,
) -> Result<Vec<Vec<u32>>, ProjectionError> {
    let mut children: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    let mut ready = Vec::new();
    for (&index, &parent) in parents {
        if (parent as usize) < retained {
            ready.push(index);
        } else if parents.contains_key(&parent) {
            children.entry(parent).or_default().push(index);
        } else {
            return Err(ProjectionError::Unsupported(
                "cyclic/unavailable parent class records".into(),
            ));
        }
    }
    let mut waves = Vec::new();
    let mut count = 0;
    while !ready.is_empty() {
        // Children of different parents interleave by assigned wire index.
        ready.sort_unstable();
        let mut next = Vec::new();
        for &index in &ready {
            if let Some(entries) = children.remove(&index) {
                next.extend(entries);
            }
        }
        count += ready.len();
        waves.push(ready);
        ready = next;
    }
    if count != parents.len() {
        return Err(ProjectionError::Unsupported(
            "cyclic/unavailable parent class records".into(),
        ));
    }
    Ok(waves)
}

#[cfg(test)]
mod construction_order_tests {
    use super::*;

    #[test]
    fn readiness_waves_preserve_forward_parent_and_branch_index_order() {
        // Allocation index order differs from dependency order; children of
        // separate parents interleave in the second wave.
        let parents = BTreeMap::from([(2, 6), (3, 5), (4, 6), (5, 0), (6, 1), (7, 2)]);
        assert_eq!(
            class_construction_waves(&parents, 2).unwrap(),
            vec![vec![5, 6], vec![2, 3, 4], vec![7]]
        );
    }

    #[test]
    fn deep_chains_construct_once_and_unavailable_or_cycles_fail() {
        let parents = (1..=4096).map(|index| (index, index - 1)).collect();
        let waves = class_construction_waves(&parents, 1).unwrap();
        assert_eq!(waves.len(), 4096);
        assert!(waves
            .iter()
            .enumerate()
            .all(|(i, wave)| wave == &vec![i as u32 + 1]));
        assert!(class_construction_waves(&BTreeMap::from([(1, 2), (2, 1)]), 1).is_err());
        assert!(class_construction_waves(&BTreeMap::from([(1, 8)]), 1).is_err());
    }
}

#[cfg(test)]
#[path = "class_projection_tests.rs"]
mod tests;
