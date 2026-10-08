//! Deterministic DMB composition from pinned engine records, resolved native
//! declarations, initializers and linked procedure images. Current-image
//! certificates share linker validation with feature discovery; custom and
//! changed images retain the independent decoder path.
use crate::{lowering::Namespace, symbolic::FrozenBatch};
use byond_dmb::{
    dmb::{DmString, Dmb, Proc, Variable},
    ids::NONE,
};
use dm_codegen_byond::procedure_abi::{ArgumentSource, Category};
use dm_ir::{SymbolId, SymbolTable};
use dm_link::Key;
use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    io,
};

#[derive(Debug)]
pub enum CompositionError {
    Decode(io::Error),
    Unsupported(String),
    MissingSymbol(SymbolId),
    InvalidBinding(Key, u32),
    NonContiguous(String),
    Link(crate::symbolic::IntegrationError),
}
/// Captured non-text records join the same generation before final encoding.
/// Implementations verify source closure and return every exact linker key they
/// attached; the composer rejects dropped keys and unattached map initializers.
pub trait NonTextOutputStage {
    fn required_types(&self) -> Vec<SymbolId> {
        Vec::new()
    }
    fn validate_source(&self, frontend: &dm_tree::frontend::ColdFrontend) -> Result<(), String>;
    fn apply(&self, dmb: &mut Dmb, batch: &FrozenBatch) -> Result<BTreeSet<Key>, String>;
}
fn unsupported(message: impl Into<String>) -> CompositionError {
    CompositionError::Unsupported(message.into())
}
fn text(symbols: &SymbolTable, id: SymbolId) -> Result<&str, CompositionError> {
    symbols.text(id).ok_or(CompositionError::MissingSymbol(id))
}
fn proc_path(
    symbols: &SymbolTable,
    owner: SymbolId,
    name: SymbolId,
) -> Result<String, CompositionError> {
    let owner = text(symbols, owner)?;
    let name = text(symbols, name)?;
    Ok(if owner == "/" {
        format!("/proc/{name}")
    } else {
        format!("{owner}/proc/{name}")
    })
}
/// Every retained linker binding is checked against the pinned wire artifact.
/// VM Variable keys index the global footer, NOT `Dmb.variables`. This bounded
/// writer accepts global slots only; declaring-owner statics need a later proof.
fn validate_binding(
    dmb: &Dmb,
    key: Key,
    index: u32,
    symbols: &SymbolTable,
    content: Option<&[u8]>,
) -> Result<(), CompositionError> {
    let valid = match key {
        Key::BuiltinGlobalVars => dmb.variables.get(index as usize).is_some_and(|record| {
            record.kind == 82
                && record.value == 0
                && dmb.string(record.name) == Some(b"vars".as_slice())
        }),
        Key::String(_) => dmb.string(index) == content && content.is_some(),
        Key::Type(symbol) => {
            dmb.classes
                .get(index as usize)
                .and_then(|class| dmb.string(class.path_string_id()))
                == Some(text(symbols, symbol)?.as_bytes())
        }
        Key::Proc {
            owner,
            name,
            occurrence: 0,
        } => retained_named_procedure(dmb, symbols, owner, name, index, false)?,
        Key::Verb {
            owner,
            name,
            occurrence: 0,
        } => retained_named_procedure(dmb, symbols, owner, name, index, true)?,
        Key::Variable { owner, name } if text(symbols, owner)? == "/" => {
            dmb.lists
                .get(dmb.variable_footer as usize)
                .and_then(|footer| footer.get(index as usize * 2))
                .and_then(|id| dmb.variables.get(*id as usize))
                .and_then(|record| dmb.string(record.name))
                == Some(text(symbols, name)?.as_bytes())
        }
        _ => return Err(unsupported(format!("unproven retained binding {key:?}"))),
    };
    if valid {
        Ok(())
    } else {
        Err(CompositionError::InvalidBinding(key, index))
    }
}
/// Engine member names may be bare rather than qualified procedure paths. The
/// captured owner's procedure/verb list proves ownership independently of that
/// spelling; accepting only a matching bare name would conflate owners.
fn retained_named_procedure(
    dmb: &Dmb,
    symbols: &SymbolTable,
    owner: SymbolId,
    name: SymbolId,
    index: u32,
    verb: bool,
) -> Result<bool, CompositionError> {
    let owner_text = text(symbols, owner)?;
    let name_text = text(symbols, name)?;
    let list = if owner_text == "/" && !verb {
        Some(dmb.world.proc_list_id())
    } else {
        dmb.classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(owner_text.as_bytes()))
            .map(|class| {
                if verb {
                    class.verb_list_id()
                } else {
                    class.proc_list_id()
                }
            })
    };
    let owned = list
        .and_then(|list| dmb.lists.get(list as usize))
        .is_some_and(|list| list.contains(&index));
    let namespace = if verb { "verb" } else { "proc" };
    let qualified = format!(
        "{}/{namespace}/{name_text}",
        owner_text.trim_end_matches('/')
    );
    let implicit_path = format!("{}/{name_text}", owner_text.trim_end_matches('/'));
    let actual = dmb
        .procs
        .get(index as usize)
        .and_then(|proc| dmb.string(proc.strings[0]));
    Ok(owned
        && (actual == Some(name_text.as_bytes())
            || actual == Some(qualified.as_bytes())
            || actual == Some(implicit_path.as_bytes())))
}
pub(crate) fn append_list(dmb: &mut Dmb, words: Vec<u32>) -> Result<u32, CompositionError> {
    let next = u32::try_from(dmb.lists.len()).map_err(|_| unsupported("list count overflow"))?;
    if dm_link::is_reserved_table_index(dm_link::Table::List, next) {
        dmb.lists.push(Vec::new());
    }
    let id = u32::try_from(dmb.lists.len()).map_err(|_| unsupported("list count overflow"))?;
    dmb.lists.push(words);
    Ok(id)
}
pub(crate) struct StringIndex {
    buckets: HashMap<u128, Vec<u32>>,
}
impl StringIndex {
    pub(crate) fn build(dmb: &Dmb) -> Result<Self, CompositionError> {
        let mut result = Self {
            buckets: HashMap::new(),
        };
        for (index, string) in dmb.strings.iter().enumerate() {
            let id = u32::try_from(index).map_err(|_| unsupported("string count overflow"))?;
            if dm_link::is_reserved_string_index(id) {
                continue;
            }
            result
                .buckets
                .entry(xxhash_rust::xxh3::xxh3_128(&string.data))
                .or_default()
                .push(id);
        }
        Ok(result)
    }
    pub(crate) fn intern(&mut self, dmb: &mut Dmb, data: &[u8]) -> Result<u32, CompositionError> {
        let hash = xxhash_rust::xxh3::xxh3_128(data);
        if let Some(ids) = self.buckets.get(&hash) {
            for &id in ids {
                if dmb.string(id) == Some(data) {
                    return Ok(id);
                }
            }
        }
        while dm_link::is_reserved_string_index(
            u32::try_from(dmb.strings.len()).map_err(|_| unsupported("string count overflow"))?,
        ) {
            dmb.strings.push(DmString {
                data: Vec::new(),
                long_chunks: 0,
            });
        }
        let id =
            u32::try_from(dmb.strings.len()).map_err(|_| unsupported("string count overflow"))?;
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        dmb.strings.push(DmString {
            data: data.to_vec(),
            long_chunks: chunks,
        });
        self.buckets.entry(hash).or_default().push(id);
        Ok(id)
    }
}
/// Validate the complete source declaration admission before composing a program.
/// The artifact-only entry below does not claim it consumed a source program.
pub fn validate_global_program(
    frontend: &dm_tree::frontend::ColdFrontend,
) -> Result<(), CompositionError> {
    if frontend
        .plan
        .items
        .iter()
        .any(|item| matches!(item, dm_preprocess::regions::OrderedItem::NonText { .. }))
    {
        return Err(unsupported("source maps and skins are not admitted"));
    }
    fn admit(items: &[dm_syntax::Item]) -> Result<(), CompositionError> {
        for item in items {
            match item.kind {
                dm_syntax::ItemKind::Proc => {}
                dm_syntax::ItemKind::Type
                    if matches!(item.header.trim(), "/" | "proc" | "/proc") =>
                {
                    admit(&item.children)?
                }
                _ => {
                    return Err(unsupported(format!(
                        "source declaration not admitted: {}",
                        item.header
                    )))
                }
            }
        }
        Ok(())
    }
    admit(&frontend.syntax.items)?;
    let mut names = std::collections::BTreeSet::new();
    for body in frontend.bodies.iter() {
        let member = frontend
            .snapshot
            .tree
            .member(body.member)
            .ok_or_else(|| unsupported("missing source member"))?;
        let owner = frontend
            .snapshot
            .tree
            .type_node(member.owner)
            .ok_or_else(|| unsupported("missing source owner"))?
            .path;
        if owner != SymbolId::of("/")
            || member.kind != dm_tree::MemberKind::Proc
            || !names.insert(member.name)
        {
            return Err(unsupported(
                "only unique fresh global procedures are admitted",
            ));
        }
    }
    Ok(())
}

pub fn compose_global_program(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
) -> Result<Vec<u8>, CompositionError> {
    validate_global_program(frontend)?;
    let covered: HashSet<_> = batch
        .units
        .iter()
        .map(|unit| unit.lowered.origin.declaration)
        .collect();
    if covered.len() != batch.units.len()
        || frontend.bodies.len() != batch.units.len()
        || frontend
            .bodies
            .iter()
            .any(|body| !covered.contains(&body.declaration))
    {
        return Err(unsupported(
            "source procedure coverage does not match lowered artifacts",
        ));
    }
    compose_global_fixture(engine_bytes, batch, frontend.snapshot.tree.symbols())
}
/// Compose new global procedures into a pinned immutable engine image. Symbolic
/// table assignments are never silently rebased. Unsupported source table keys,
/// metadata, overrides and occupied indexes are explicit errors.
///
/// Returned bytes are a real validated DMB, not a complete production compiler.
/// Resources/maps/world configuration remain exactly the pinned engine artifact.
pub fn compose_global_fixture(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    symbols: &SymbolTable,
) -> Result<Vec<u8>, CompositionError> {
    compose_records(engine_bytes, batch, symbols, None, None)
}
/// Class emission uses the same procedure/argument/helper writer as the bounded
/// global entry, with mandatory immutable class/default/chain projection.
pub fn compose_projected_program(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &crate::class_projection::ClassProjection,
    values: &dyn crate::class_projection::TypeValuePolicy,
) -> Result<Vec<u8>, CompositionError> {
    compose_projected_with_stage(engine_bytes, batch, frontend, projection, values, None)
}
pub fn compose_projected_with_stage(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &crate::class_projection::ClassProjection,
    values: &dyn crate::class_projection::TypeValuePolicy,
    stage: Option<&dyn NonTextOutputStage>,
) -> Result<Vec<u8>, CompositionError> {
    compose_projected_with_symbols(
        engine_bytes,
        batch,
        frontend,
        projection,
        values,
        stage,
        frontend.snapshot.tree.symbols(),
    )
}
/// Body-local startup declarations use the collision-checked captured union dictionary.
pub fn compose_projected_with_symbols(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &crate::class_projection::ClassProjection,
    values: &dyn crate::class_projection::TypeValuePolicy,
    stage: Option<&dyn NonTextOutputStage>,
    symbols: &SymbolTable,
) -> Result<Vec<u8>, CompositionError> {
    if projection.tree_identity != frontend.snapshot.tree.identity()
        || projection.occurrence_count != frontend.snapshot.occurrences.source_order().len()
    {
        return Err(unsupported(
            "class projection does not cover this source model",
        ));
    }
    if frontend
        .plan
        .items
        .iter()
        .any(|item| matches!(item, dm_preprocess::regions::OrderedItem::NonText { .. }))
        && stage.is_none()
    {
        return Err(unsupported("map/skin materialization is not supplied"));
    }
    if let Some(stage) = stage {
        stage.validate_source(frontend).map_err(unsupported)?;
    }
    let covered: HashSet<_> = batch
        .units
        .iter()
        .map(|unit| unit.lowered.origin.declaration)
        .collect();
    if covered.len() != batch.units.len()
        || frontend.bodies.len() != batch.units.len()
        || frontend
            .bodies
            .iter()
            .any(|body| !covered.contains(&body.declaration))
    {
        return Err(unsupported("source procedure coverage mismatch"));
    }
    compose_records(
        engine_bytes,
        batch,
        symbols,
        Some((projection, values)),
        stage,
    )
}
fn compose_records(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    symbols: &SymbolTable,
    projection: Option<(
        &crate::class_projection::ClassProjection,
        &dyn crate::class_projection::TypeValuePolicy,
    )>,
    stage: Option<&dyn NonTextOutputStage>,
) -> Result<Vec<u8>, CompositionError> {
    let mut dmb = Dmb::from_bytes(engine_bytes).map_err(CompositionError::Decode)?;
    if let Some((plan, _)) = projection {
        let required: BTreeMap<_, _> = plan.runtime_writes.iter().copied().collect();
        let mut actual = BTreeMap::new();
        for unit in &batch.initializers {
            for &ordinal in unit.declaration_writes() {
                if actual.insert(ordinal, unit.identity).is_some() {
                    return Err(unsupported("duplicate executable initializer coverage"));
                }
            }
        }
        if required.len() != plan.runtime_writes.len() || actual != required {
            return Err(unsupported(
                "classified runtime defaults differ from executable initializer coverage",
            ));
        }
    } else if !batch.initializers.is_empty() {
        return Err(unsupported(
            "initializer artifacts require classified declaration projection",
        ));
    }
    dmb.validate_references()
        .map_err(CompositionError::Decode)?;
    let engine_strings = dmb.strings.len();
    let engine_procs = dmb.procs.len();
    let mut strings = BTreeMap::new();
    let mut procs = BTreeMap::new();
    let mut helpers = BTreeMap::new();
    let mut initializers = BTreeMap::new();
    let mut stage_keys = BTreeSet::new();
    let mut builtin_global_vars = None;
    for (&key, &index) in batch.tables.assignments() {
        match key {
            Key::String(_) if (index as usize) >= engine_strings => {
                let bytes = batch
                    .tables
                    .content(key)
                    .ok_or(CompositionError::InvalidBinding(key, index))?;
                strings.insert(index, bytes.to_vec());
            }
            Key::BuiltinGlobalVars if (index as usize) >= dmb.variables.len() => {
                builtin_global_vars = Some(index);
            }
            Key::Proc {
                owner,
                name,
                occurrence,
            }
            | Key::Verb {
                owner,
                name,
                occurrence,
            } if (index as usize) >= engine_procs => {
                let namespace = if matches!(key, Key::Verb { .. }) {
                    Namespace::Verb
                } else {
                    Namespace::Proc
                };
                if projection.is_none()
                    && (text(symbols, owner)? != "/"
                        || occurrence != 0
                        || namespace != Namespace::Proc)
                {
                    return Err(unsupported(
                        "only fresh global procedures are supported by the bounded entry",
                    ));
                }
                procs.insert(
                    index,
                    crate::lowering::UnitIdentity {
                        owner,
                        name,
                        namespace,
                        occurrence,
                    },
                );
            }
            Key::Type(_) if (index as usize) >= dmb.classes.len() && projection.is_some() => {}
            Key::Variable { .. } | Key::ProcedureStatic(_) if projection.is_some() => {}
            Key::ArgumentSource { .. } if (index as usize) >= engine_procs => {
                helpers.insert(index, key);
            }
            Key::Initializer(identity) if (index as usize) >= engine_procs => {
                if matches!(
                    identity,
                    dm_link::InitializerIdentity::Map { .. }
                        | dm_link::InitializerIdentity::Modified(_)
                ) {
                    if stage.is_none() {
                        return Err(unsupported("map initializer attachment stage absent"));
                    }
                    stage_keys.insert(key);
                }
                initializers.insert(index, identity);
            }
            Key::Instance(_) if stage.is_some() && (index as usize) >= dmb.instances.len() => {
                stage_keys.insert(key);
            }
            Key::MapInstance { .. } | Key::DefaultMapInstance { .. } | Key::Resource(_)
                if stage.is_some() =>
            {
                stage_keys.insert(key);
            }
            _ => validate_binding(&dmb, key, index, symbols, batch.tables.content(key))?,
        }
    }
    for (index, data) in strings {
        while dmb.strings.len() < index as usize
            && dm_link::is_reserved_string_index(dmb.strings.len() as u32)
        {
            dmb.strings.push(DmString {
                data: Vec::new(),
                long_chunks: 0,
            });
        }
        if index as usize != dmb.strings.len() {
            return Err(CompositionError::NonContiguous(
                "string table indexes".into(),
            ));
        }
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        dmb.strings.push(DmString {
            data,
            long_chunks: chunks,
        });
    }
    if let Some((plan, _)) = projection {
        crate::class_projection::materialize_types(&mut dmb, plan, &batch.tables, symbols)
            .map_err(|e| unsupported(format!("class skeleton {e:?}")))?;
    }
    let mut string_index = StringIndex::build(&dmb)?;
    if let Some(index) = builtin_global_vars {
        if index as usize != dmb.variables.len() {
            return Err(CompositionError::NonContiguous(
                "builtin variable record index".into(),
            ));
        }
        let name = string_index.intern(&mut dmb, b"vars")?;
        dmb.variables.push(Variable {
            kind: 82,
            value: 0,
            name,
        });
    }
    if helpers.len() != batch.helpers.len() {
        return Err(unsupported("helper inventory coverage mismatch"));
    }
    let helper_order = batch
        .helpers
        .iter()
        .map(|helper| crate::symbolic::helper_key(helper.owner, helper.argument))
        .collect::<Vec<_>>();
    let source_references = dm_link::ArgumentSourceReferences::assign(
        &batch.tables,
        dmb.proc_references.len(),
        &helper_order,
    )
    .map_err(|e| unsupported(format!("argument references {e:?}")))?;
    for key in &helper_order {
        dmb.proc_references.push(
            batch
                .tables
                .index(*key)
                .ok_or_else(|| unsupported("missing helper procedure index"))?,
        );
    }
    if procs.len() != batch.units.len() {
        return Err(unsupported("every unit must be one fresh global procedure"));
    }
    let mut units = BTreeMap::new();
    for (index, unit) in batch.units.iter().enumerate() {
        let identity = unit.lowered.identity;
        if units.insert(identity, (index, unit)).is_some() {
            return Err(unsupported("duplicate procedure artifact"));
        }
    }
    for (index, identity) in procs {
        let owner = identity.owner;
        let name = identity.name;
        reserve_procedure_sentinel(&mut dmb);
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "procedure table indexes".into(),
            ));
        }
        let &(unit_index, unit) = units
            .get(&identity)
            .ok_or_else(|| unsupported("missing global procedure artifact"))?;
        let abi = unit
            .lowered
            .abi
            .as_ref()
            .ok_or_else(|| unsupported("procedure ABI was not authoritative"))?;
        let proc = &unit.lowered.code.procedure;
        if proc.argument_names.len() != proc.argument_type_flags.len()
            || proc.argument_names.len() != abi.argument_sources.len()
        {
            return Err(unsupported("argument metadata count mismatch"));
        }
        if proc.local_count as usize != proc.local_names.len() {
            return Err(unsupported("local metadata count mismatch"));
        }
        let linked = batch
            .link_unit(unit_index, &Default::default())
            .map_err(CompositionError::Link)?;
        let code_id = append_list(&mut dmb, linked.words.to_vec())?;
        let mut locals = Vec::new();
        for name in &proc.local_names {
            let name_id = string_index.intern(&mut dmb, name.as_bytes())?;
            let variable_id = u32::try_from(dmb.variables.len())
                .map_err(|_| unsupported("variable record overflow"))?;
            dmb.variables.push(Variable {
                kind: 0,
                value: 0,
                name: name_id,
            });
            locals.push(variable_id);
        }
        let locals_id = append_list(&mut dmb, locals)?;
        let mut args = Vec::new();
        for (argument, name) in proc.argument_names.iter().enumerate() {
            let name_id = string_index.intern(&mut dmb, name.as_bytes())?;
            let variable_id = u32::try_from(dmb.variables.len())
                .map_err(|_| unsupported("argument record overflow"))?;
            dmb.variables.push(Variable {
                kind: 0,
                value: 0,
                name: name_id,
            });
            let value_source = match &abi.argument_sources[argument] {
                ArgumentSource::Builtin { kind, parameter } => {
                    u32::from(*kind) | (u32::from(*parameter) << 8)
                }
                ArgumentSource::Helper {
                    argument: helper_argument,
                } => {
                    let key = crate::symbolic::helper_key(
                        unit.lowered.identity,
                        u32::try_from(*helper_argument)
                            .map_err(|_| unsupported("helper argument overflow"))?,
                    );
                    let position = source_references
                        .index(key)
                        .ok_or_else(|| unsupported("missing argument source companion"))?;
                    0x40 | (u32::from(position) << 8)
                }
            };
            args.extend([
                proc.argument_type_flags[argument],
                value_source,
                variable_id,
                0,
            ]);
        }
        let args_id = append_list(&mut dmb, args)?;
        let mut path = proc_path(symbols, owner, name)?;
        if identity.namespace == Namespace::Verb {
            path = path.replacen("/proc/", "/verb/", 1);
        }
        let path_id = string_index.intern(&mut dmb, path.as_bytes())?;
        let default_display = text(symbols, name)?.replace('_', " ");
        let display = abi
            .layout
            .display_name
            .as_deref()
            .unwrap_or(default_display.as_bytes());
        let display_id = string_index.intern(&mut dmb, display)?;
        let description_id = match &abi.layout.description {
            Some(value) => string_index.intern(&mut dmb, value)?,
            None => NONE,
        };
        let category_id = match &abi.layout.category {
            Category::Text(value) => string_index.intern(&mut dmb, value)?,
            Category::Default | Category::Null => NONE,
        };
        let (flags, extended_flags) = abi.layout.encoded_flags();
        dmb.procs.push(Proc {
            strings: [path_id, display_id, description_id, category_id],
            source_parameter: abi.layout.source_parameter,
            source_kind: abi.layout.source_kind,
            flags,
            extended_flags,
            code_locals_args: [code_id, locals_id, args_id],
        });
    }
    let by_key: BTreeMap<_, _> = batch
        .helpers
        .iter()
        .map(|helper| {
            (
                crate::symbolic::helper_key(helper.owner, helper.argument),
                helper,
            )
        })
        .collect();
    if by_key.len() != batch.helpers.len() {
        return Err(unsupported("duplicate helper artifact"));
    }
    for (index, key) in helpers {
        reserve_procedure_sentinel(&mut dmb);
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "helper procedure indexes".into(),
            ));
        }
        let helper = by_key
            .get(&key)
            .ok_or_else(|| unsupported("missing helper artifact"))?;
        let image = batch.link_helper(helper).map_err(CompositionError::Link)?;
        emit_anonymous(
            &mut dmb,
            &mut string_index,
            &image.words,
            &helper.local_names,
        )?;
    }
    if initializers.len() != batch.initializers.len() {
        return Err(unsupported("initializer inventory coverage mismatch"));
    }
    let initialization: BTreeMap<_, _> = batch
        .initializers
        .iter()
        .map(|unit| (unit.identity, unit))
        .collect();
    if initialization.len() != batch.initializers.len() {
        return Err(unsupported("duplicate initializer artifact"));
    }
    for (index, identity) in initializers {
        reserve_procedure_sentinel(&mut dmb);
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "initializer indexes".into(),
            ));
        }
        let unit = initialization
            .get(&identity)
            .ok_or_else(|| unsupported("initializer artifact absent"))?;
        let image = batch
            .link_initializer(unit)
            .map_err(CompositionError::Link)?;
        emit_anonymous(&mut dmb, &mut string_index, &image.words, &unit.local_names)?;
        match identity {
            dm_link::InitializerIdentity::Global => {
                if dmb.world.ids[4] != NONE {
                    return Err(unsupported(
                        "retained global initializer requires explicit composition",
                    ));
                }
                dmb.world.ids[4] = index;
            }
            dm_link::InitializerIdentity::Class(owner) => {
                let class = batch
                    .tables
                    .index(Key::Type(owner))
                    .ok_or(CompositionError::MissingSymbol(owner))?;
                let record = dmb
                    .classes
                    .get_mut(class as usize)
                    .ok_or_else(|| unsupported("initializer class absent"))?;
                if record.lists_and_procs[2] != NONE {
                    return Err(unsupported(
                        "retained class initializer requires explicit composition",
                    ));
                }
                record.lists_and_procs[2] = index;
            }
            dm_link::InitializerIdentity::Map { .. }
            | dm_link::InitializerIdentity::Modified(_) => (),
        }
    }
    if let Some((plan, values)) = projection {
        crate::class_projection::materialize_members(
            &mut dmb,
            plan,
            &batch.tables,
            symbols,
            values,
        )
        .map_err(|e| unsupported(format!("class members {e:?}")))?;
    }
    if let Some(stage) = stage {
        let attached = stage.apply(&mut dmb, batch).map_err(unsupported)?;
        if attached != stage_keys {
            return Err(unsupported("non-text output stage linker coverage differs"));
        }
        let map_initializers: HashSet<u32> = dmb
            .instances
            .iter()
            .map(|instance| instance.initializer)
            .collect();
        for key in stage_keys {
            let index = batch
                .tables
                .index(key)
                .ok_or_else(|| unsupported("attached key has no linker index"))?;
            let present = attached_key_present(&dmb, key, index, &map_initializers);
            if !present {
                return Err(CompositionError::InvalidBinding(key, index));
            }
        }
    }
    let feature_images = batch.feature_images();
    let mut external = false;
    let mut debug = false;
    for index in 0..dmb.procs.len() {
        if dmb.is_reserved_proc_slot(index) {
            continue;
        }
        let words = dmb
            .proc_code_words(index)
            .ok_or_else(|| unsupported("missing procedure code"))?;
        if let Some(&(certified_words, features)) = feature_images.get(&(index as u32)) {
            if certified_words == words {
                external |= features.external;
                debug |= features.debug;
                continue;
            }
        }
        let instructions = byond_dmb::bytecode::decode(words)
            .map_err(|e| {
                let proc_record=&dmb.procs[index];
                let path=dmb.string(proc_record.strings[0]).map(String::from_utf8_lossy);
                let name=dmb.string(proc_record.strings[1]).map(String::from_utf8_lossy);
                let start=e.offset.saturating_sub(4).min(words.len());
                let end=e.offset.saturating_add(8).min(words.len());
                unsupported(format!("invalid composed bytecode: proc={index}, path={path:?}, name={name:?}, error={e:?}, words[{start}..{end}]={:?}",&words[start..end]))
            })?;
        for instruction in instructions {
            external |= matches!(instruction.name, "LoadExt" | "CallExt");
            debug |= matches!(instruction.name, "DbgFile" | "DbgLine");
        }
    }
    if external {
        dmb.header.flags |= 0x2000_0000;
    }
    if debug {
        dmb.header.flags |= 0x0002_0000;
    }
    // Choose the wide table ABI explicitly for the composed model. No instruction
    // operand is guessed/rebased; shared symbolic linking already fixed those.
    dmb.header.flags |= 0x4000_0000;
    dmb.validate_references()
        .map_err(CompositionError::Decode)?;
    let bytes = dmb.to_bytes().map_err(CompositionError::Decode)?;
    Dmb::from_bytes(&bytes)
        .and_then(|decoded| decoded.validate_references())
        .map_err(CompositionError::Decode)?;
    Ok(bytes)
}
fn attached_key_present(dmb: &Dmb, key: Key, index: u32, map_initializers: &HashSet<u32>) -> bool {
    match key {
        Key::Instance(_) | Key::MapInstance { .. } | Key::DefaultMapInstance { .. } => {
            dmb.instances.get(index as usize).is_some()
        }
        Key::Resource(_) => dmb.resources.get(index as usize).is_some(),
        Key::Initializer(dm_link::InitializerIdentity::Map { .. }) => {
            map_initializers.contains(&index)
        }
        Key::Initializer(dm_link::InitializerIdentity::Modified(_)) => {
            map_initializers.contains(&index)
        }
        _ => false,
    }
}

/// Native wide ProcIDs keep the nullable NONE slot as an exact blank record.
fn reserve_procedure_sentinel(dmb: &mut Dmb) {
    if dm_link::is_reserved_table_index(dm_link::Table::Procedure, dmb.procs.len() as u32) {
        dmb.procs.push(Proc {
            strings: [byond_dmb::ids::NONE; 4],
            source_parameter: 255,
            source_kind: 0,
            flags: 4,
            extended_flags: None,
            code_locals_args: [byond_dmb::ids::NONE; 3],
        });
    }
}
fn emit_anonymous(
    dmb: &mut Dmb,
    strings: &mut StringIndex,
    words: &[u32],
    names: &[String],
) -> Result<(), CompositionError> {
    let code = append_list(dmb, words.to_vec())?;
    let mut locals = Vec::with_capacity(names.len());
    for name in names {
        let name = strings.intern(dmb, name.as_bytes())?;
        let id = u32::try_from(dmb.variables.len())
            .map_err(|_| unsupported("anonymous local overflow"))?;
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name,
        });
        locals.push(id);
    }
    let locals = append_list(dmb, locals)?;
    let args = append_list(dmb, Vec::new())?;
    dmb.procs.push(Proc {
        strings: [NONE; 4],
        source_parameter: 255,
        source_kind: 0,
        flags: 4,
        extended_flags: None,
        code_locals_args: [code, locals, args],
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_reserved_list_padding_preserves_code_and_argument_links_roundtrip() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        dmb.lists.resize(byond_dmb::ids::NONE as usize, Vec::new());
        let code = append_list(&mut dmb, vec![0]).unwrap();
        let locals = append_list(&mut dmb, Vec::new()).unwrap();
        let args = append_list(&mut dmb, Vec::new()).unwrap();
        assert_eq!([code, locals, args], [0x10000, 0x10001, 0x10002]);
        assert!(dmb.lists[0xffff].is_empty());
        dmb.procs[0].code_locals_args = [code, locals, args];
        dmb.header.flags |= 0x4000_0000;
        dmb.validate_references().unwrap();
        let decoded = Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
        decoded.validate_references().unwrap();
        assert_eq!(decoded.procs[0].code_locals_args, [code, locals, args]);
        assert_eq!(decoded.proc_code_words(0), Some([0].as_slice()));
        assert!(decoded.lists[0xffff].is_empty());
    }
    #[test]
    fn native_reserved_procedure_padding_roundtrips_and_preserves_next_proc() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        let template = dmb.procs[0].clone();
        dmb.procs
            .resize(byond_dmb::ids::NONE as usize, template.clone());
        reserve_procedure_sentinel(&mut dmb);
        assert!(dmb.is_reserved_proc_slot(byond_dmb::ids::NONE as usize));
        let count = dmb.procs.len();
        reserve_procedure_sentinel(&mut dmb);
        assert_eq!(dmb.procs.len(), count);
        dmb.procs.push(template.clone());
        dmb.header.flags |= 0x4000_0000;
        dmb.validate_references().unwrap();
        let decoded = Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
        decoded.validate_references().unwrap();
        assert!(decoded.is_reserved_proc_slot(byond_dmb::ids::NONE as usize));
        assert_eq!(decoded.procs[0x10000], template);
    }
    #[test]
    fn writer_string_interning_preserves_reserved_holes_and_safe_field_decoding() {
        let mut image =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        image.strings.resize(
            0xffcd,
            DmString {
                data: Vec::new(),
                long_chunks: 0,
            },
        );
        let mut pool = StringIndex::build(&image).unwrap();
        let first = pool.intern(&mut image, b"field_after_modifiers").unwrap();
        assert_eq!(first, 0xfff2);
        assert!(image.strings[0xffcd..=0xfff1]
            .iter()
            .all(|row| row.data.is_empty()));
        assert_eq!(
            byond_dmb::operands::Variable::decode(&[first]).unwrap(),
            (byond_dmb::operands::Variable::Field(first), 1)
        );
        image.strings.resize(
            0xffff,
            DmString {
                data: Vec::new(),
                long_chunks: 0,
            },
        );
        let second = pool.intern(&mut image, b"field_after_absent").unwrap();
        assert_eq!(second, 0x10000);
        assert!(image.strings[0xffff].data.is_empty());
        assert_eq!(
            byond_dmb::operands::Variable::decode(&[second]).unwrap(),
            (byond_dmb::operands::Variable::Field(second), 1)
        );
        let rebuilt = StringIndex::build(&image).unwrap();
        assert!(!rebuilt
            .buckets
            .values()
            .flatten()
            .any(|id| dm_link::is_reserved_string_index(*id)));
    }
    #[test]
    fn map_initializer_attachment_coverage_uses_exact_index_and_domain() {
        let mut image =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        assert!(!image.instances.is_empty());
        image.instances[0].initializer = 17;
        let index: HashSet<u32> = image
            .instances
            .iter()
            .map(|instance| instance.initializer)
            .collect();
        let key = Key::Initializer(dm_link::InitializerIdentity::Map {
            source: 1,
            descriptor: 2,
        });
        assert!(attached_key_present(&image, key, 17, &index));
        assert!(!attached_key_present(&image, key, 999_999, &index));
        assert!(!attached_key_present(
            &image,
            Key::Initializer(dm_link::InitializerIdentity::Global),
            17,
            &index
        ));
        assert!(attached_key_present(
            &image,
            Key::MapInstance {
                source: 1,
                descriptor: 2
            },
            0,
            &index
        ));
        assert!(!attached_key_present(
            &image,
            Key::MapInstance {
                source: 1,
                descriptor: 2
            },
            image.instances.len() as u32,
            &index
        ));
    }
    #[test]
    fn every_captured_engine_named_procedure_binding_is_validated() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let dmb = Dmb::from_bytes(bytes).unwrap();
        let links = crate::engine_link::capture(bytes, &engine).unwrap();
        for (key, index) in links.inventory.fixed {
            if !matches!(key, Key::Proc { .. } | Key::Verb { .. }) {
                continue;
            }
            let result = validate_binding(&dmb, key, index, engine.symbols(), None);
            let record = &dmb.procs[index as usize];
            assert!(
                result.is_ok(),
                "{result:?}; index={index}; strings={:?}; key={key:?}; layouts={:?}",
                record.strings.map(|id| dmb.string(id)),
                engine
                    .procedure_layouts()
                    .iter()
                    .filter(|layout| layout.wire_proc == index)
                    .map(|layout| (
                        engine.symbols().text(layout.owner),
                        layout.name.and_then(|name| engine.symbols().text(name)),
                        layout.kind
                    ))
                    .collect::<Vec<_>>()
            );
        }
    }
    #[test]
    fn builtin_global_vars_uses_variable_record_domain_without_footer_allocation() {
        let bytes = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let pinned = Dmb::from_bytes(bytes).unwrap();
        let record = pinned.variables.len() as u32;
        let mut inventory = dm_link::LinkInventory::default();
        inventory
            .reserved_prefixes
            .insert(dm_link::Table::VariableRecord, record);
        inventory.entries.push(dm_link::Entry {
            key: Key::BuiltinGlobalVars,
            content: std::sync::Arc::from(b"builtin-vars-kind82".as_slice()),
        });
        let batch = FrozenBatch {
            units: vec![],
            helpers: vec![],
            initializers: vec![],
            tables: dm_link::LinkTables::build(inventory).unwrap(),
        };
        let result = compose_global_fixture(bytes, &batch, &SymbolTable::default()).unwrap();
        let decoded = Dmb::from_bytes(&result).unwrap();
        assert_eq!(decoded.variables[record as usize].kind, 82);
        assert_eq!(
            decoded.string(decoded.variables[record as usize].name),
            Some(b"vars".as_slice())
        );
        assert_eq!(
            decoded.lists.get(decoded.variable_footer as usize),
            pinned.lists.get(pinned.variable_footer as usize)
        );
    }
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    fn frontend(source: &'static str) -> dm_tree::frontend::ColdFrontend {
        dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap()
    }
    #[test]
    fn full_source_admission_rejects_globals_classes_and_missing_bodies() {
        assert!(validate_global_program(&frontend("/var/x = 1\n")).is_err());
        assert!(validate_global_program(&frontend("/datum/x\n")).is_err());
        assert!(
            validate_global_program(&frontend("/datum/x/proc/read()\n    return 1\n")).is_err()
        );
        let source = frontend("/proc/read()\n    return 1\n");
        assert!(validate_global_program(&source).is_ok());
        let batch = FrozenBatch {
            units: vec![],
            helpers: vec![],
            initializers: vec![],
            tables: dm_link::LinkTables::build(Default::default()).unwrap(),
        };
        assert!(
            matches!(compose_global_program(b"invalid",&batch,&source),Err(CompositionError::Unsupported(message)) if message.contains("coverage"))
        );
    }

    #[test]
    fn real_pinned_image_composes_and_retains_external_feature_bit() {
        let engine = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let batch = FrozenBatch {
            units: vec![],
            helpers: vec![],
            initializers: vec![],
            tables: dm_link::LinkTables::build(Default::default()).unwrap(),
        };
        let bytes = compose_global_fixture(engine, &batch, &SymbolTable::default()).unwrap();
        let decoded = Dmb::from_bytes(&bytes).unwrap();
        decoded.validate_references().unwrap();
        assert_ne!(decoded.header.flags & 0x2000_0000, 0);
        assert_eq!(
            decoded.procs.len(),
            Dmb::from_bytes(engine).unwrap().procs.len()
        );
    }
    #[test]
    fn canonical_indexes_cannot_overwrite_pinned_strings() {
        let engine = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let mut symbols = SymbolTable::default();
        let wrong = symbols.intern("not-the-engine-string").unwrap();
        let inventory = dm_link::LinkInventory {
            entries: vec![dm_link::Entry {
                key: Key::String(wrong),
                content: std::sync::Arc::from(b"not-the-engine-string".as_slice()),
            }],
            spellings: vec![(
                wrong,
                std::sync::Arc::from(b"not-the-engine-string".as_slice()),
            )],
            ..Default::default()
        };
        let batch = FrozenBatch {
            units: vec![],
            helpers: vec![],
            initializers: vec![],
            tables: dm_link::LinkTables::build(inventory).unwrap(),
        };
        assert!(matches!(
            compose_global_fixture(engine, &batch, &symbols),
            Err(CompositionError::InvalidBinding(Key::String(_), 0))
        ));
    }
}
