//! Deterministic DMB composition from pinned engine records, resolved native
//! declarations, initializers and linked procedure images. Current-image
//! certificates share linker validation with feature discovery; custom and
//! changed images retain the independent decoder path.
use crate::{lowering::Namespace, symbolic::FrozenBatch};
use byond_dmb::{
    dmb::{DmString, Dmb, Proc, Variable},
    ids::NONE,
};
use dm_codegen_byond::procedure_abi::Category;
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
    namespace: Namespace,
    declared: bool,
) -> Result<String, CompositionError> {
    let owner = text(symbols, owner)?;
    let name = text(symbols, name)?;
    let namespace = match namespace {
        Namespace::Proc => "proc",
        Namespace::Verb => "verb",
    };
    Ok(if owner == "/" {
        format!("/{namespace}/{name}")
    } else if declared {
        format!("{owner}/{namespace}/{name}")
    } else {
        // Physical namespace membership records the source declaration form.
        // Implicit overrides are callable methods but are excluded by
        // typesof("/owner/proc"). Symbolic keys still retain their namespace.
        format!("{owner}/{name}")
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
pub(crate) fn append_list(
    dmb: &mut Dmb,
    words: impl Into<std::sync::Arc<Vec<u32>>>,
) -> Result<u32, CompositionError> {
    let next = u32::try_from(dmb.lists.len()).map_err(|_| unsupported("list count overflow"))?;
    if dm_link::is_reserved_table_index(dm_link::Table::List, next) {
        dmb.lists.push(Vec::new());
    }
    let id = u32::try_from(dmb.lists.len()).map_err(|_| unsupported("list count overflow"))?;
    dmb.lists.push_shared(words.into());
    Ok(id)
}
mod strings;
pub(crate) use strings::StringIndex;

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
    fn admit<'a>(
        items: impl IntoIterator<Item = dm_tree::frontend::ItemView<'a>>,
    ) -> Result<(), CompositionError> {
        for item in items {
            match item.kind() {
                dm_syntax::ItemKind::Proc => {}
                dm_syntax::ItemKind::Type
                    if matches!(item.header().trim(), "/" | "proc" | "/proc") =>
                {
                    admit(item.children())?
                }
                _ => {
                    return Err(unsupported(format!(
                        "source declaration not admitted: {}",
                        item.header()
                    )))
                }
            }
        }
        Ok(())
    }
    admit(frontend.syntax.items())?;
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
    compose_global_program_encoded(engine_bytes, batch, frontend)
        .map(byond_dmb::dmb::EncodedDmb::into_bytes)
}
pub fn compose_global_program_encoded(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
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
    compose_records_access(
        engine_bytes,
        owned::BatchAccess::Borrowed(batch),
        frontend.snapshot.tree.symbols(),
        None,
        None,
        None,
        None,
    )
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
    owned::validate_projected(batch, frontend, projection, stage)?;
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
    compose_records_access(
        engine_bytes,
        owned::BatchAccess::Borrowed(batch),
        symbols,
        projection,
        stage,
        None,
        None,
    )
    .map(byond_dmb::dmb::EncodedDmb::into_bytes)
}
fn compose_records_access(
    engine_bytes: &[u8],
    mut batch: owned::BatchAccess<'_>,
    symbols: &SymbolTable,
    projection: Option<(
        &crate::class_projection::ClassProjection,
        &dyn crate::class_projection::TypeValuePolicy,
    )>,
    stage: Option<&dyn NonTextOutputStage>,
    executor: Option<&dm_exec::BuildExecutor>,
    generation: Option<&RetainedGeneration>,
) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
    let mut dmb = {
        let _profile = dm_profile::stage("composition.decode_engine");
        Dmb::from_bytes(engine_bytes).map_err(CompositionError::Decode)?
    };
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
    let mut plan = procedure_plan::CompositionPlan::default();
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
                plan.procedures.push((
                    index,
                    crate::lowering::UnitIdentity {
                        owner,
                        name,
                        namespace,
                        occurrence,
                    },
                ));
            }
            Key::Type(_) if (index as usize) >= dmb.classes.len() && projection.is_some() => {}
            Key::Variable { .. } | Key::ProcedureStatic(_) if projection.is_some() => {}
            Key::ArgumentSource { .. } if (index as usize) >= engine_procs => {
                plan.helpers.push((index, key));
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
                plan.initializers.push((index, identity));
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
    let plan = match generation {
        Some(generation) => generation.bind_plan(plan, &batch),
        None => {
            plan.canonicalize();
            plan.bind(&batch)
        }
    };
    let [procedure_count, helper_count, initializer_count] = plan.counts;
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
    let mut string_index = {
        let _profile = dm_profile::stage("composition.string_index_build");
        StringIndex::build(&dmb)?
    };
    let class_roster = if let Some((plan, _)) = projection {
        let _profile = dm_profile::stage("composition.materialize_types");
        Some(
            crate::class_projection::materialize_types_with_roster(
                &mut dmb,
                plan,
                &batch.tables,
                symbols,
                &mut string_index,
            )
            .map_err(|e| unsupported(format!("class skeleton {e:?}")))?,
        )
    } else {
        None
    };
    // VM MobPath values use the mob table, not the class table. Allocate the
    // shared domain before admitting any compiler-owned procedure words.
    let mob_bindings = if let Some((plan, _)) = projection {
        crate::mob_writer::materialize_projection(&mut dmb, &batch.tables, plan)
            .map_err(unsupported)?
    } else {
        dm_link::MobBindings::new()
    };
    let linked_records_profile = dm_profile::stage("composition.linked_records");
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
    if helper_count != batch.helpers.len() {
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
    if procedure_count != batch.units.len() {
        return Err(unsupported("every unit must be one fresh global procedure"));
    }
    let procedures = plan.procedures?;
    let metadata = procedure_plan::prepare_metadata(
        &procedures,
        &batch,
        projection.map(|(plan, _)| plan),
        symbols,
        &source_references,
        executor,
        generation.is_some(),
    );
    for (slot, metadata) in procedures.iter().zip(metadata) {
        let index = slot.table_index;
        reserve_procedure_sentinel(&mut dmb);
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "procedure table indexes".into(),
            ));
        }
        let unit_index = slot
            .artifact
            .ok_or_else(|| unsupported("missing global procedure artifact"))?;
        let linked_words = batch
            .unit_words(unit_index, &mob_bindings)
            .map_err(CompositionError::Link)?;
        let metadata = metadata?;
        let unit = &batch.units[unit_index];
        frame_contribution::emit(
            &mut dmb,
            &mut string_index,
            unit,
            linked_words,
            metadata,
            generation.is_some(),
        )?;
    }
    for slot in plan.helpers?.iter() {
        let index = slot.table_index;
        reserve_procedure_sentinel(&mut dmb);
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "helper procedure indexes".into(),
            ));
        }
        let helper_index = slot
            .artifact
            .ok_or_else(|| unsupported("missing helper artifact"))?;
        let words = batch
            .helper_words(helper_index, &mob_bindings)
            .map_err(CompositionError::Link)?;
        emit_anonymous(
            &mut dmb,
            &mut string_index,
            words,
            &batch.helpers[helper_index].local_names,
        )?;
    }
    if initializer_count != batch.initializers.len() {
        return Err(unsupported("initializer inventory coverage mismatch"));
    }
    for slot in plan.initializers?.iter() {
        let index = slot.table_index;
        let identity = slot.identity;
        reserve_procedure_sentinel(&mut dmb);
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "initializer indexes".into(),
            ));
        }
        let unit_index = slot
            .artifact
            .ok_or_else(|| unsupported("initializer artifact absent"))?;
        let words = batch
            .initializer_words(unit_index, &mob_bindings)
            .map_err(CompositionError::Link)?;
        emit_anonymous(
            &mut dmb,
            &mut string_index,
            words,
            &batch.initializers[unit_index].local_names,
        )?;
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
    drop(linked_records_profile);
    if let Some((plan, values)) = projection {
        let members_profile = dm_profile::stage("composition.member_records");
        crate::class_projection::materialize_members_with_roster(
            &mut dmb,
            plan,
            (&batch.tables, mob_bindings),
            symbols,
            values,
            &mut string_index,
            class_roster.as_ref(),
        )
        .map_err(|e| unsupported(format!("class members {e:?}")))?;
        drop(members_profile);
        let headers_profile = dm_profile::stage("composition.authored_headers");
        crate::class_projection::finalize_headers_with_roster(
            &mut dmb,
            engine_bytes,
            plan,
            &batch.tables,
            symbols,
            &mut string_index,
            class_roster.as_ref(),
        )
        .map_err(|e| unsupported(format!("class headers {e:?}")))?;
        drop(headers_profile);
        let _profile = dm_profile::stage("composition.callback_flags");
        crate::class_projection::materialize_callback_flags(&mut dmb, plan, &batch.tables)
            .map_err(|e| unsupported(format!("class callbacks {e:?}")))?;
    }
    drop(class_roster);
    // The pool is valid only across writers that intern through this context.
    // Arbitrary non-text stages may mutate strings and must not reuse it.
    drop(string_index);
    if let Some(stage) = stage {
        let _profile = dm_profile::stage("composition.nontext_apply");
        let attached = stage.apply(&mut dmb, &batch).map_err(unsupported)?;
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
    let final_validation = dm_profile::stage("composition.final_instruction_validation");
    let feature_images = batch.certified_features();
    let (external, debug) = final_instructions::validate(&dmb, &feature_images, executor)?;
    drop(feature_images);
    drop(final_validation);
    // All output-stage and final instruction checks are complete. Consuming
    // requests release frozen IR/table inventories before encode/decode overlap.
    drop(batch);
    if external {
        dmb.header.flags |= 0x2000_0000;
    }
    if debug {
        dmb.header.flags |= 0x0002_0000;
    }
    // Choose the wide table ABI explicitly for the composed model. No instruction
    // operand is guessed/rebased; shared symbolic linking already fixed those.
    dmb.header.flags |= 0x4000_0000;
    let references_profile = dm_profile::stage("composition.reference_validation");
    dmb.validate_references()
        .map_err(CompositionError::Decode)?;
    drop(references_profile);
    crate::heap_census::emit_if_enabled("composition.model", |census| census.dmb(&dmb))
        .map_err(CompositionError::Decode)?;
    let bytes = match generation {
        Some(generation) => generation.encode(
            generation::CertifiedGenerationInputs::after_validation(dmb),
            executor,
        )?,
        None => {
            let encoded = generation::encode_model(&dmb, executor)?;
            drop(dmb);
            generation::validate_encoded(&encoded)?;
            encoded
        }
    };
    crate::heap_census::emit_if_enabled("composition.encoded", |census| {
        census.output_encoded("dmb.bytes", &bytes)
    })
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
    words: impl Into<std::sync::Arc<Vec<u32>>>,
    names: &[String],
) -> Result<(), CompositionError> {
    let code = append_list(dmb, words)?;
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
#[path = "composition/tests.rs"]
mod tests;

mod final_instructions;
mod lifecycle;
pub use lifecycle::{OwnedCompositionInputs, ValidatedComposition};
mod owned;
pub use owned::{
    compose_global_fixture_owned, compose_projected_owned_with_symbols,
    compose_projected_owned_with_symbols_on_executor,
};

mod frame_contribution;
mod procedure_plan;

mod generation;
pub use generation::RetainedGeneration;

mod procedure_metadata_recipe;
pub(crate) use procedure_metadata_recipe::ProcedureMetadataRecipe;
