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
                .ok_or_else(|| ProjectionError::Unsupported("unavailable parent class record".into()))?
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

/// Append scalar variable records/default assignments and procedure chains to a
/// staged output. Shared slot IDs are checked against footer positions; instance
/// field declaration IDs remain a separate exact(owner,name) record domain.
/// The caller discards this staged image on error and must emit any runtime
/// initializer units before publication.
pub fn materialize_members(
    dmb: &mut byond_dmb::dmb::Dmb,
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
    value_types: &dyn TypeValuePolicy,
) -> Result<(), ProjectionError> {
    use byond_dmb::{dmb::Variable, ids::NONE};
    let mut mob_order = Vec::new();
    for ty in projection.types.iter() {
        let Some(mut class) = tables.index(Key::Type(ty.path)) else {
            continue;
        };
        let mut visited = HashSet::new();
        while visited.insert(class) {
            let Some(record) = dmb.classes.get(class as usize) else {
                break;
            };
            if dmb.string(record.path_string_id()) == Some(b"/mob".as_slice()) {
                mob_order.push(ty.path);
                break;
            }
            class = record.parent_class_id();
            if class == NONE {
                break;
            }
        }
    }
    mob_order.sort_by_key(|path| tables.index(Key::Type(*path)));
    let mobs = crate::mob_writer::materialize(dmb, tables, &mob_order)
        .map_err(ProjectionError::Unsupported)?;
    struct Values<'a> {
        underlying: &'a dyn TypeValuePolicy,
        mobs: HashMap<SymbolId, u32>,
        tables: &'a dm_link::LinkTables,
    }
    impl TypeValuePolicy for Values<'_> {
        fn tag(&self, path: SymbolId) -> Result<u8, ProjectionError> {
            self.underlying.tag(path)
        }
        fn resource_index(&self, path: SymbolId) -> Result<u32, ProjectionError> {
            let key = self.underlying.resource_key(path)?;
            if !matches!(key, Key::Resource(_)) {
                return Err(ProjectionError::Unsupported("resource policy returned a non-resource key".into()));
            }
            self.tables.index(key).ok_or_else(|| ProjectionError::Unsupported(
                "resource content absent from frozen link inventory".into(),
            ))
        }
        fn mob_index(&self, path: SymbolId) -> Result<u32, ProjectionError> {
            self.mobs.get(&path).copied().ok_or_else(|| {
                ProjectionError::Unsupported(
                    "mob default absent from explicit type inventory".into(),
                )
            })
        }
    }
    let values = Values {
        underlying: value_types,
        mobs,
        tables,
    };
    let value_types: &dyn TypeValuePolicy = &values;
    let text = |symbol| {
        symbols.text(symbol).ok_or_else(|| {
            ProjectionError::Unsupported(format!("missing field spelling {symbol:?}"))
        })
    };
    let world = SymbolId::of("/world");
    let savefile = SymbolId::of("/savefile");
    let savefile_values = projection.fields.iter()
        .filter(|field| field.owner == savefile && field.intrinsic
            && field.name == SymbolId::of("byond_version"))
        .map(|field| match &field.value {
            DefaultValue::Scalar(value) => crate::savefile_projection::project(value)
                .map_err(ProjectionError::Unsupported),
            _ => Err(ProjectionError::Unsupported("savefile header requires scalar default".into())),
        }).collect::<Result<Vec<_>, _>>()?;
    crate::savefile_projection::apply(dmb, &savefile_values)
        .map_err(ProjectionError::Unsupported)?;
    let world_values = projection
        .fields
        .iter()
        .filter(|field| field.owner == world && field.intrinsic)
        .map(|field| match &field.value {
            DefaultValue::Scalar(value) => Ok((text(field.name)?, value)),
            _ => Err(ProjectionError::Unsupported(
                "world intrinsic constructor default unsupported".into(),
            )),
        })
        .collect::<Result<Vec<_>, ProjectionError>>()?;
    let directives = crate::world_projection::project(world_values)
        .map_err(|error| ProjectionError::Unsupported(format!("world policy {error:?}")))?;
    let client = SymbolId::of("/client");
    let client_types = projection.types.iter().filter_map(|typ| {
        tables.index(Key::Type(typ.path)).map(|ordinal| (typ.path, typ.parent, ordinal))
    }).collect::<Vec<_>>();
    let client_order = crate::client_projection::configuration_order(client, &client_types)
        .map_err(|error| ProjectionError::Unsupported(format!("client order {error:?}")))?;
    let client_owners: HashSet<_> = client_order.iter().copied().collect();
    let client_directives = client_header_directives(&projection.fields, &client_order, symbols)?;
    crate::client_projection::apply(dmb, &client_directives);
    struct Defaults<'a> {
        tables: &'a dm_link::LinkTables,
        values: &'a dyn TypeValuePolicy,
    }
    impl crate::world_writer::DefaultBindings for Defaults<'_> {
        fn index(
            &self,
            kind: crate::world_projection::DefaultKind,
            path: SymbolId,
        ) -> Result<u32, String> {
            match kind {
                crate::world_projection::DefaultKind::Mob => {
                    self.values.mob_index(path).map_err(|e| format!("{e:?}"))
                }
                _ => self
                    .tables
                    .index(Key::Type(path))
                    .ok_or_else(|| "world default class missing".into()),
            }
        }
    }
    let mut world_strings = crate::composition::StringIndex::build(dmb)
        .map_err(|e| ProjectionError::Unsupported(format!("world strings {e:?}")))?;
    crate::world_writer::apply(
        dmb,
        &directives,
        &mut world_strings,
        &Defaults {
            tables,
            values: value_types,
        },
    )
    .map_err(ProjectionError::Unsupported)?;
    if let Some(script) = client_directives.iter().rev().find_map(|directive| {
        match directive {
            crate::client_projection::Directive::Script(script) => Some(script),
            _ => None,
        }
    }) {
        struct ScriptBindings<'a> {
            strings: &'a mut crate::composition::StringIndex,
            resources: &'a dyn TypeValuePolicy,
        }
        impl crate::client_script::Bindings for ScriptBindings<'_> {
            fn string(&mut self, dmb: &mut byond_dmb::dmb::Dmb, bytes: &[u8]) -> Result<u32, String> {
                self.strings.intern(dmb, bytes).map_err(|error| format!("{error:?}"))
            }
            fn resource(&self, symbol: SymbolId) -> Result<u32, String> {
                self.resources.resource_index(symbol).map_err(|error| format!("{error:?}"))
            }
        }
        crate::client_script::apply(dmb, script, &mut ScriptBindings {
            strings: &mut world_strings,
            resources: value_types,
        }).map_err(ProjectionError::Unsupported)?;
    }
    let mut classes = HashMap::new();
    let mut declarations = HashMap::new();
    for (index, class) in dmb.classes.iter().enumerate() {
        let path = dmb
            .string(class.path_string_id())
            .ok_or(ProjectionError::MissingMember)?;
        let owner = SymbolId::of_bytes(path);
        if text(owner)?.as_bytes() != path || classes.insert(owner, index as u32).is_some() {
            return Err(ProjectionError::Unsupported(
                "ambiguous retained class paths".into(),
            ));
        }
        for (variable, _) in dmb.class_variable_declarations(index).unwrap_or_default() {
            let record = dmb
                .variables
                .get(variable as usize)
                .ok_or(ProjectionError::MissingMember)?;
            let name = dmb
                .string(record.name)
                .ok_or(ProjectionError::MissingMember)?;
            let symbol = SymbolId::of_bytes(name);
            // Unknown engine fields remain indexed by exact bytes, not claimed
            // typed. Only source fields with checked symbol spellings use them.
            if declarations.insert((owner, symbol), variable).is_some() {
                return Err(ProjectionError::Unsupported(
                    "ambiguous declaring field records".into(),
                ));
            }
        }
    }
    let mut pool = crate::composition::StringIndex::build(dmb)
        .map_err(|e| ProjectionError::Unsupported(format!("string writer {e:?}")))?;
    fn list(dmb: &mut byond_dmb::dmb::Dmb, words: Vec<u32>) -> Result<u32, ProjectionError> {
        crate::composition::append_list(dmb, words)
            .map_err(|error| ProjectionError::Unsupported(format!("list writer {error:?}")))
    }
    fn extend(
        dmb: &mut byond_dmb::dmb::Dmb,
        id: u32,
        words: Vec<u32>,
    ) -> Result<u32, ProjectionError> {
        if id == NONE {
            list(dmb, words)
        } else {
            dmb.lists
                .get_mut(id as usize)
                .ok_or(ProjectionError::MissingMember)?
                .extend(words);
            Ok(id)
        }
    }
    fn scalar(
        dmb: &mut byond_dmb::dmb::Dmb,
        pool: &mut crate::composition::StringIndex,
        default: &DefaultValue,
        tables: &dm_link::LinkTables,
        types: &dyn TypeValuePolicy,
    ) -> Result<(u8, u32), ProjectionError> {
        let value = match default {
            DefaultValue::Scalar(value) => value,
            DefaultValue::InitializerExpression { token, .. } => return Ok((62, *token)),
        };
        match value {
            SemanticValue::Null => Ok((0, 0)),
            SemanticValue::NumberBits(bits) => Ok((42, *bits)),
            SemanticValue::Text(bytes) => Ok((
                6,
                pool.intern(dmb, bytes)
                    .map_err(|e| ProjectionError::Unsupported(format!("string literal {e:?}")))?,
            )),
            SemanticValue::Type(path) => {
                let tag = types.tag(*path)?;
                if let Some(primitive) = dm_codegen_byond::NativePrimitiveType::from_symbol(*path) {
                    if tag != primitive.tag() {
                        return Err(ProjectionError::Unsupported("primitive family policy disagrees with captured native tag".into()));
                    }
                    return Ok((tag, 0));
                }
                let index = if tag == 8 {
                    types.mob_index(*path)?
                } else {
                    tables.index(Key::Type(*path)).ok_or_else(|| {
                        ProjectionError::Unsupported("missing type literal binding".into())
                    })?
                };
                Ok((tag, index))
            }
            SemanticValue::Resource(path) => Ok((12, types.resource_index(*path)?)),
            SemanticValue::Procedure(identity) => {
                let key = if identity.verb {
                    Key::Verb { owner: identity.owner, name: identity.name, occurrence: identity.occurrence }
                } else {
                    Key::Proc { owner: identity.owner, name: identity.name, occurrence: identity.occurrence }
                };
                let index = tables.index(key).ok_or_else(|| ProjectionError::Unsupported(
                    "procedure literal absent from frozen link inventory".into()))?;
                Ok((38, index))
            }
            SemanticValue::ModifiedInstance(instance) => {
                let key = Key::Instance(SymbolId::of(&instance.alias()));
                let index = tables.index(key).ok_or_else(|| ProjectionError::Unsupported("modified default descriptor absent from frozen inventory".into()))?;
                if tables.content(key) != Some(instance.canonical_bytes()) {
                    return Err(ProjectionError::Unsupported("modified default descriptor content differs from frozen inventory".into()));
                }
                Ok((41, index))
            }
            SemanticValue::List(_) => Err(ProjectionError::Unsupported(
                "list literal requires initializer materialization".into(),
            )),
        }
    }
    let mut shared_records = BTreeMap::new();
    for field in projection
        .fields
        .iter()
        .filter(|field| field.role == FieldRole::Declaration)
    {
        let flags = field.wire_flags.ok_or_else(|| {
            ProjectionError::Unsupported("formal declaration wire flags unavailable".into())
        })?;
        if declarations.contains_key(&(field.owner, field.name)) {
            return Err(ProjectionError::Unsupported(
                "source field redeclares retained record".into(),
            ));
        }
        let name = pool
            .intern(dmb, text(field.name)?.as_bytes())
            .map_err(|e| ProjectionError::Unsupported(format!("field name {e:?}")))?;
        let (kind, value) = scalar(dmb, &mut pool, &field.value, tables, value_types)?;
        let variable = u32::try_from(dmb.variables.len())
            .map_err(|_| ProjectionError::Unsupported("variable record overflow".into()))?;
        dmb.variables.push(Variable { kind, value, name });
        declarations.insert((field.owner, field.name), variable);
        if field.shared {
            let key = Key::Variable {
                owner: field.owner,
                name: field.name,
            };
            let index = tables.index(key).ok_or_else(|| {
                ProjectionError::Unsupported("shared slot binding missing".into())
            })?;
            if shared_records.insert(index, (variable, flags)).is_some() {
                return Err(ProjectionError::Unsupported(
                    "duplicate shared slot record".into(),
                ));
            }
        }
        if field.owner != SymbolId::of("/") {
            let class = *classes
                .get(&field.owner)
                .ok_or(ProjectionError::MissingMember)?;
            let old = dmb.classes[class as usize].lists_and_procs[4];
            let id = extend(dmb, old, vec![variable, flags])?;
            dmb.classes[class as usize].lists_and_procs[4] = id;
        }
    }
    for local in projection.procedure_statics.iter() {
        let index = tables
            .index(Key::ProcedureStatic(local.identity))
            .ok_or_else(|| {
                ProjectionError::Unsupported("procedure static slot binding missing".into())
            })?;
        let name = pool
            .intern(dmb, text(local.identity.name)?.as_bytes())
            .map_err(|error| {
                ProjectionError::Unsupported(format!("procedure static name {error:?}"))
            })?;
        let (kind, value) = scalar(dmb, &mut pool, &local.value, tables, value_types)?;
        let variable = u32::try_from(dmb.variables.len())
            .map_err(|_| ProjectionError::Unsupported("procedure static record overflow".into()))?;
        dmb.variables.push(Variable { kind, value, name });
        if shared_records
            .insert(index, (variable, local.wire_flags))
            .is_some()
        {
            return Err(ProjectionError::Unsupported(
                "duplicate procedure static shared slot".into(),
            ));
        }
    }
    if !shared_records.is_empty() {
        let mut footer = if dmb.variable_footer == NONE {
            Vec::new()
        } else {
            dmb.lists
                .get(dmb.variable_footer as usize)
                .ok_or(ProjectionError::MissingMember)?
                .clone()
        };
        if footer.len() % 2 != 0 {
            return Err(ProjectionError::Unsupported(
                "invalid variable footer".into(),
            ));
        }
        for (index, (record, flags)) in shared_records {
            if usize::try_from(index).ok() != Some(footer.len() / 2) {
                return Err(ProjectionError::Unsupported(
                    "shared slot order disagrees with footer allocation".into(),
                ));
            }
            footer.extend([record, flags]);
        }
        dmb.variable_footer = list(dmb, footer)?;
    }
    for field in projection
        .fields
        .iter()
        .filter(|field| field.role == FieldRole::Assignment)
    {
        if field.owner == world && field.intrinsic {
            continue;
        }
        if field.owner == savefile && field.intrinsic
            && field.name == SymbolId::of("byond_version")
        {
            continue;
        }
        if client_owners.contains(&field.owner) && field.intrinsic
            && crate::client_projection::is_header_field(text(field.name)?)
            && !(text(field.name)? == "preload_rsc"
                && matches!(&field.value, DefaultValue::Scalar(SemanticValue::Text(_))))
        {
            continue;
        }
        if field.shared {
            return Err(ProjectionError::Unsupported(
                "shared variable reinitialization requires explicit compile-error policy".into(),
            ));
        }
        let class = *classes
            .get(&field.owner)
            .ok_or(ProjectionError::MissingMember)?;
        if field.intrinsic && !declarations.contains_key(&(field.declaring_owner, field.name)) {
            let name = text(field.name)?;
            let (kind, value) = scalar(dmb, &mut pool, &field.value, tables, value_types)?;
            let numeric = match &field.value {
                DefaultValue::Scalar(SemanticValue::NumberBits(bits)) => {
                    Some(f32::from_bits(*bits))
                }
                _ => None,
            };
            let integer = |low: f32, high: f32| -> Result<f32, ProjectionError> {
                let number = numeric
                    .filter(|number| {
                        number.is_finite()
                            && number.fract() == 0.0
                            && *number >= low
                            && *number <= high
                    })
                    .ok_or_else(|| {
                        ProjectionError::Unsupported(format!(
                            "invalid intrinsic {name} numeric value"
                        ))
                    })?;
                Ok(number)
            };
            match name {
                "name" | "desc" | "icon_state" | "text" | "maptext" | "suffix" => {
                    if kind != 0 && kind != 6 {
                        return Err(ProjectionError::Unsupported(
                            "intrinsic text default has wrong value kind".into(),
                        ));
                    }
                    let id = if kind == 0 { NONE } else { value };
                    let record = &mut dmb.classes[class as usize];
                    match name {
                        "name" => record.initial_ids[2] = id,
                        "desc" => record.initial_ids[3] = id,
                        "icon_state" => record.initial_ids[5] = id,
                        "text" => record.text = id,
                        "maptext" => record.maptext = id,
                        _ => record.suffix = id,
                    }
                }
                "icon" => {
                    if kind != 0 && kind != 12 {
                        return Err(ProjectionError::Unsupported(
                            "icon default is not a resource".into(),
                        ));
                    }
                    dmb.classes[class as usize].initial_ids[4] =
                        if kind == 0 { NONE } else { value };
                }
                "density" => dmb.classes[class as usize].set_dense(integer(0.0, 1.0)? != 0.0),
                "opacity" => dmb.classes[class as usize].set_opaque(integer(0.0, 1.0)? != 0.0),
                "layer" => {
                    dmb.classes[class as usize].layer_bits = match field.value {
                        DefaultValue::Scalar(SemanticValue::NumberBits(bits)) => bits,
                        _ => {
                            return Err(ProjectionError::Unsupported("layer is not numeric".into()))
                        }
                    }
                }
                "dir" => dmb.classes[class as usize].direction = integer(0.0, 255.0)? as u8,
                "maptext_width" | "maptext_height" | "maptext_x" | "maptext_y" => {
                    let slot = match name {
                        "maptext_width" => 0,
                        "maptext_height" => 1,
                        "maptext_x" => 2,
                        _ => 3,
                    };
                    dmb.classes[class as usize].maptext_geometry[slot] = if slot < 2 {
                        integer(0.0, 65535.0)? as u16
                    } else {
                        integer(-32768.0, 32767.0)? as i16 as u16
                    };
                }
                "mouse_opacity" => dmb.classes[class as usize]
                    .set_mouse_opacity(integer(0.0, 255.0)? as u8)
                    .map_err(|e| ProjectionError::Unsupported(e.to_string()))?,
                "animate_movement" => dmb.classes[class as usize]
                    .set_animate_movement(integer(0.0, 255.0)? as u8)
                    .map_err(|e| ProjectionError::Unsupported(e.to_string()))?,
                "luminosity" => dmb.classes[class as usize]
                    .set_luminosity(integer(0.0, 7.0)? as u8)
                    .map_err(|e| ProjectionError::Unsupported(e.to_string()))?,
                "appearance_flags" => {
                    dmb.classes[class as usize]
                        .set_appearance_flags(integer(0.0, u32::MAX as f32)? as u32)
                }
                _ => {
                    let selector = pool.intern(dmb, name.as_bytes()).map_err(|e| {
                        ProjectionError::Unsupported(format!("native selector {e:?}"))
                    })?;
                    let mut words = vec![selector];
                    words.extend(encoded_constant(kind, value)?);
                    let old = dmb.classes[class as usize].overrides;
                    let id = extend(dmb, old, words)?;
                    dmb.classes[class as usize].overrides = id;
                }
            }
            continue;
        }
        let variable = *declarations
            .get(&(field.declaring_owner, field.name))
            .ok_or(ProjectionError::MissingMember)?;
        let (kind, value) = scalar(dmb, &mut pool, &field.value, tables, value_types)?;
        let mut words = vec![variable];
        words.extend(encoded_constant(kind, value)?);
        let old = dmb.classes[class as usize].lists_and_procs[3];
        let id = extend(dmb, old, words)?;
        dmb.classes[class as usize].lists_and_procs[3] = id;
    }
    // Group order is the explicit first-encounter projection, not hash order.
    let mut proc_lists: BTreeMap<(SymbolId, bool), Vec<u32>> = BTreeMap::new();
    for chain in projection.chains.iter() {
        let ids = chain
            .entries
            .iter()
            .map(|key| {
                tables.index(*key).ok_or_else(|| {
                    ProjectionError::Unsupported("missing procedure chain binding".into())
                })
            })
            .collect::<Result<Vec<_>, _>>()?;
        if chain.owner == SymbolId::of("/") {
            continue;
        }
        proc_lists
            .entry((chain.owner, chain.verb))
            .or_default()
            .extend(ids);
    }
    for ((owner, verb), mut entries) in proc_lists {
        if owner == SymbolId::of("/world") {
            if verb {
                return Err(ProjectionError::Unsupported(
                    "world verb ABI not supported".into(),
                ));
            }
            let old = dmb.world.ids[3];
            if old != NONE {
                entries.extend(
                    dmb.lists
                        .get(old as usize)
                        .ok_or(ProjectionError::MissingMember)?
                        .iter()
                        .copied(),
                );
            }
            dmb.world.ids[3] = list(dmb, entries)?;
        } else {
            let class = *classes.get(&owner).ok_or(ProjectionError::MissingMember)?;
            let slot = usize::from(!verb);
            let old = dmb.classes[class as usize].lists_and_procs[slot];
            if old != NONE {
                entries.extend(
                    dmb.lists
                        .get(old as usize)
                        .ok_or(ProjectionError::MissingMember)?
                        .iter()
                        .copied(),
                );
            }
            dmb.classes[class as usize].lists_and_procs[slot] = list(dmb, entries)?;
        }
    }
    Ok(())
}
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
        Err(ProjectionError::Unsupported("resource content domain was not captured".into()))
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
            let name = symbols.text(field.name).ok_or_else(||
                ProjectionError::Unsupported("client field spelling missing".into()))?;
            if !crate::client_projection::is_header_field(name) { continue; }
            let DefaultValue::Scalar(value) = &field.value else {
                return Err(ProjectionError::Unsupported("client header requires scalar default".into()));
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
fn class_construction_waves(parents: &BTreeMap<u32, u32>, retained: usize)
    -> Result<Vec<Vec<u32>>, ProjectionError>
{
    let mut children: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    let mut ready = Vec::new();
    for (&index, &parent) in parents {
        if (parent as usize) < retained {
            ready.push(index);
        } else if parents.contains_key(&parent) {
            children.entry(parent).or_default().push(index);
        } else {
            return Err(ProjectionError::Unsupported("cyclic/unavailable parent class records".into()));
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
        return Err(ProjectionError::Unsupported("cyclic/unavailable parent class records".into()));
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
        assert_eq!(class_construction_waves(&parents, 2).unwrap(),
            vec![vec![5, 6], vec![2, 3, 4], vec![7]]);
    }

    #[test]
    fn deep_chains_construct_once_and_unavailable_or_cycles_fail() {
        let parents = (1..=4096).map(|index| (index, index - 1)).collect();
        let waves = class_construction_waves(&parents, 1).unwrap();
        assert_eq!(waves.len(), 4096);
        assert!(waves.iter().enumerate().all(|(i, wave)| wave == &vec![i as u32 + 1]));
        assert!(class_construction_waves(&BTreeMap::from([(1, 2), (2, 1)]), 1).is_err());
        assert!(class_construction_waves(&BTreeMap::from([(1, 8)]), 1).is_err());
    }
}

#[cfg(test)]
#[path = "class_projection_tests.rs"]
mod tests;
