//! Immutable source class/member projection for the cold writer. Wire allocation
//! remains separate: instance declarations are variable records, shared fields
//! additionally acquire VM footer slots, and field selectors remain strings.
use crate::initializer_policy::DefaultValue;
mod callbacks;
mod field_placements;
pub use field_placements::FieldPlacements;
mod class_roster;
pub(crate) mod header_recipes;
mod headers;
pub use header_recipes::HeaderRecipes;
pub(crate) mod member_contribution;
mod retained;
pub(crate) mod type_roster;
pub(crate) use class_roster::MaterializedClassRoster;
pub use retained::ClassProjections;
mod methods;
mod routing;
pub use callbacks::materialize_callback_flags;
use dm_ir::{SemanticValue, SymbolId, SymbolicExpression};
use dm_link::Key;
use dm_tree::{DefinitionMode, MemberKind, OccurrenceId, Target, TreeSnapshot};
pub(super) use headers::finalize_headers_retained;
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
    SourceError { field: usize, message: String },
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
    /// Current source binding is excluded from retained semantic field payloads.
    pub field_placements: FieldPlacements,
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
    pub fields: Arc<[Arc<FieldProjection>]>,
    pub chains: Arc<[ProcedureChain]>,
    /// Current authored method encounter order, normalized for BYOND membership.
    /// Independent of hashed linker table indexes and semantic super chains.
    pub procedure_membership: Arc<[Key]>,
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
    project_inner(source, order, evaluator, None, None)
}
pub fn project_classified(
    source: &TreeSnapshot,
    order: &[OccurrenceId],
    plan: &dm_tree::initializers::InitializerPlan,
    classified: &crate::initializer_policy::ClassifiedInitializers,
    units: &[crate::initializer_lowering::LoweredInitializerUnit],
) -> Result<ClassProjection, ProjectionError> {
    project_classified_with_artifacts(source, order, plan, classified, units, None)
}
pub fn project_classified_with_artifacts(
    source: &TreeSnapshot,
    order: &[OccurrenceId],
    plan: &dm_tree::initializers::InitializerPlan,
    classified: &crate::initializer_policy::ClassifiedInitializers,
    units: &[crate::initializer_lowering::LoweredInitializerUnit],
    artifacts: Option<&ClassProjections>,
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
    let ledger = crate::class_initialization::admit_lowered_borrowed(plan, classified, units)
        .map_err(ProjectionError::Unsupported)?;
    let mut projection = project_inner(
        source,
        order,
        &NoEvaluation,
        Some(ledger.as_slice()),
        artifacts,
    )?;
    let mut statics = Vec::new();
    for default in &ledger {
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
    for default in &ledger {
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
    defaults: Option<&[crate::class_initialization::BorrowedDefault<'_>]>,
    artifacts: Option<&ClassProjections>,
) -> Result<ClassProjection, ProjectionError> {
    if source.tree.identity() != source.occurrences.tree_identity() {
        return Err(ProjectionError::IdentityMismatch);
    }
    let occurrences = source.occurrences.source_order();
    if occurrences.len() != order.len() {
        return Err(ProjectionError::IncompleteOrder);
    }
    let tree = &source.tree;
    let types = match artifacts {
        Some(artifacts) => artifacts.types.obtain(tree),
        None => type_roster::produce(tree.types()),
    };
    let mut seen = HashSet::new();
    let mut fields = Vec::new();
    let mut field_placements = FieldPlacements::default();
    let default_index: HashMap<_, _> = defaults
        .into_iter()
        .flat_map(|ledger| ledger.iter())
        .filter(|value| {
            matches!(
                value.origin_kind,
                dm_tree::initializers::InitializerOriginKind::Declaration(_)
            )
        })
        .map(|value| (value.occurrence, value.value))
        .collect();
    let mut retention = artifacts
        .filter(|_| defaults.is_some())
        .and_then(|store| store.begin(source, order, &default_index));
    let mut procedure_declarations = BTreeMap::new();
    let mut procedure_encounters = Vec::new();
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
        let placement = member_contribution::CurrentPlacement { occurrence };
        let Target::Member(member_id) = placement.occurrence.target else {
            continue;
        };
        let contribution = match retention.as_mut() {
            Some(request) => {
                request.produce(tree, member_id, default_index.get(&id).copied(), evaluator)?
            }
            None => member_contribution::produce(
                tree,
                member_id,
                default_index.get(&id).copied(),
                defaults.is_some(),
                evaluator,
            )?,
        };
        match contribution {
            member_contribution::MemberContribution::Field(field) => {
                field_placements.push(fields.len(), id, &field);
                fields.push(field);
            }
            member_contribution::MemberContribution::Procedure {
                owner,
                name,
                verb,
                key,
                declared,
            } => {
                procedure_declarations.insert(key, declared);
                procedure_encounters.push((declared, key));
                if !procs.contains_key(&(owner, name, verb)) {
                    group_order.push((owner, name, verb));
                }
                procs
                    .entry((owner, name, verb))
                    .or_default()
                    .push((declared, key));
            }
        }
    }
    if let Some(request) = retention {
        request.finish();
    }
    // BYOND allocates formal methods before implicit overrides and prepends
    // each allocated member. Preserve the exact cross-name encounter roster;
    // reversing name groups would incorrectly make override chains contiguous.
    let procedure_membership = procedure_encounters
        .iter()
        .rev()
        .filter(|(declared, _)| !declared)
        .chain(
            procedure_encounters
                .iter()
                .rev()
                .filter(|(declared, _)| *declared),
        )
        .map(|(_, key)| *key)
        .collect::<Vec<_>>();
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
        field_placements,
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
            .flat_map(|ledger| ledger.iter())
            .filter(|value| value.runtime)
            .map(|value| (value.source_ordinal, value.initializer))
            .collect::<Vec<_>>()
            .into(),
        tree_identity: tree.identity(),
        occurrence_count: occurrences.len(),
        types,
        fields: fields.into(),
        chains: chains.into(),
        procedure_membership: procedure_membership.into(),
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
    let mut strings = crate::composition::StringIndex::build(dmb)
        .map_err(|e| ProjectionError::Unsupported(format!("type strings {e:?}")))?;
    materialize_types_with_strings(dmb, projection, tables, symbols, &mut strings)
}

pub(crate) fn materialize_types_with_strings(
    dmb: &mut byond_dmb::dmb::Dmb,
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
    strings: &mut crate::composition::StringIndex,
) -> Result<(), ProjectionError> {
    materialize_types_with_roster(dmb, projection, tables, symbols, strings).map(|_| ())
}
pub(crate) fn materialize_types_with_roster(
    dmb: &mut byond_dmb::dmb::Dmb,
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
    strings: &mut crate::composition::StringIndex,
) -> Result<MaterializedClassRoster, ProjectionError> {
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
        if routing::separate_type_record(ty.path) {
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

    let mut constructed: BTreeMap<u32, Class> = BTreeMap::new();
    let mut image_family = HashSet::new();
    if let Some(&image) = retained.get(&SymbolId::of("/image")) {
        image_family.insert(image);
        loop {
            let before = image_family.len();
            for (id, class) in dmb.classes.iter().enumerate() {
                if image_family.contains(&class.initial_ids[1]) {
                    image_family.insert(id as u32);
                }
            }
            if image_family.len() == before {
                break;
            }
        }
    }
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
            if image_family.contains(&parent) {
                // Native image roots may use the absent sentinel, but BYOND
                // materializes source image subclasses with explicit empty
                // strings. Authored assignments are applied by common writers.
                let empty = strings
                    .intern(dmb, b"")
                    .map_err(|e| ProjectionError::Unsupported(format!("image default {e:?}")))?;
                record.initial_ids[2] = empty;
                record.text = empty;
                image_family.insert(index);
            } else {
                record.initial_ids[2] = strings
                    .intern(dmb, display.as_bytes())
                    .map_err(|e| ProjectionError::Unsupported(format!("type display {e:?}")))?;
                record.text = strings
                    .intern(dmb, letter.as_bytes())
                    .map_err(|e| ProjectionError::Unsupported(format!("type letter {e:?}")))?;
            }
            record.lists_and_procs = [NONE; 6];
            record.overrides = NONE;
            constructed.insert(index, record);
        }
    }
    for (_, record) in constructed {
        dmb.classes.push(record);
    }
    Ok(MaterializedClassRoster::issued(type_ids))
}

#[path = "class_projection/members.rs"]
mod members;
pub use members::materialize_members;
pub(crate) use members::materialize_members_with_roster;

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
    fields: &[Arc<FieldProjection>],
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

#[cfg(test)]
#[path = "class_projection/image_header_tests.rs"]
mod image_header_tests;
#[cfg(test)]
#[path = "class_projection/shared_writer_tests.rs"]
mod shared_writer_tests;

#[cfg(test)]
#[path = "class_projection/shared_tmp_tests.rs"]
mod shared_tmp_tests;
