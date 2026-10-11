//! Finalize effective native appearance defaults after source members are written.
//! Each known property uses its wire accessor; callback flags remain independent.
use super::*;
#[path = "header_fields.rs"]
pub(super) mod fields;
use byond_dmb::{
    dmb::{Class, Dmb},
    ids::NONE,
};
use dm_ir::SymbolTable;
use std::collections::{BTreeSet, VecDeque};

#[cfg(test)]
pub(crate) fn finalize_headers(
    dmb: &mut Dmb,
    engine_bytes: &[u8],
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
) -> Result<(), ProjectionError> {
    let mut pool = crate::composition::StringIndex::build(dmb)
        .map_err(|e| ProjectionError::Unsupported(format!("header strings {e:?}")))?;
    finalize_headers_with_strings(dmb, engine_bytes, projection, tables, symbols, &mut pool)
}

#[cfg(test)]
pub(crate) fn finalize_headers_with_strings(
    dmb: &mut Dmb,
    engine_bytes: &[u8],
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
    pool: &mut crate::composition::StringIndex,
) -> Result<(), ProjectionError> {
    finalize_headers_with_roster(dmb, engine_bytes, projection, tables, symbols, pool, None)
}
#[allow(clippy::too_many_arguments)]
#[cfg(test)]
pub(crate) fn finalize_headers_with_roster(
    dmb: &mut Dmb,
    engine_bytes: &[u8],
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
    pool: &mut crate::composition::StringIndex,
    roster: Option<&MaterializedClassRoster>,
) -> Result<(), ProjectionError> {
    finalize_headers_retained(
        dmb,
        engine_bytes,
        projection,
        tables,
        symbols,
        pool,
        roster,
        None,
    )
}
#[allow(clippy::too_many_arguments)]
pub(crate) fn finalize_headers_retained(
    dmb: &mut Dmb,
    engine_bytes: &[u8],
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &SymbolTable,
    pool: &mut crate::composition::StringIndex,
    roster: Option<&MaterializedClassRoster>,
    recipes: Option<&HeaderRecipes>,
) -> Result<(), ProjectionError> {
    let engine = Dmb::from_bytes(engine_bytes)
        .map_err(|error| ProjectionError::Unsupported(format!("header engine {error}")))?;
    finalize_headers_with_engine(
        dmb, &engine, projection, tables, symbols, pool, roster, recipes,
    )
}
/// The supplied model must be the authenticated pinned engine owner used by composition.
#[allow(clippy::too_many_arguments)]
pub(crate) fn finalize_headers_with_engine(
    dmb: &mut Dmb,
    engine: &Dmb,
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &SymbolTable,
    pool: &mut crate::composition::StringIndex,
    roster: Option<&MaterializedClassRoster>,
    recipes: Option<&HeaderRecipes>,
) -> Result<(), ProjectionError> {
    let engine_classes = engine
        .classes
        .iter()
        .enumerate()
        .filter_map(|(id, record)| {
            engine
                .string(record.path_string_id())
                .map(|path| (path, id))
        })
        .collect::<HashMap<_, _>>();
    let mut legacy_class_ids = HashMap::new();
    if roster.is_none() {
        for (id, record) in dmb.classes.iter().enumerate() {
            let bytes = dmb.string(record.path_string_id()).ok_or_else(|| {
                ProjectionError::Unsupported(format!(
                    "header class {id} missing path string {}",
                    record.path_string_id()
                ))
            })?;
            let path = std::str::from_utf8(bytes).map_err(|_| {
                ProjectionError::Unsupported(format!("header class {id} path is not UTF-8"))
            })?;
            let id = u32::try_from(id).map_err(|_| {
                ProjectionError::Unsupported("header class count exceeds u32".into())
            })?;
            if legacy_class_ids.insert(SymbolId::of(path), id).is_some() {
                return Err(ProjectionError::Unsupported(format!(
                    "header duplicate class path {path}"
                )));
            }
        }
    }
    let class_ids = roster
        .map(|roster| &roster.ids)
        .unwrap_or(&legacy_class_ids);
    let client_owners = routing::client_configuration_order(projection, tables)?
        .into_iter()
        .collect::<HashSet<_>>();
    let mut own: HashMap<u32, HashSet<&str>> = HashMap::new();
    let mut null_names = HashSet::new();
    let mut override_own: HashMap<u32, HashSet<&str>> = HashMap::new();
    for field in projection
        .fields
        .iter()
        .filter(|field| field.intrinsic && field.role == FieldRole::Assignment)
    {
        if routing::separate_type_record(field.owner)
            || routing::separate_intrinsic_field(field, &client_owners, symbols)?
        {
            continue;
        }
        let id = projected_class_index(field.owner, tables, class_ids, symbols)?;
        let name = symbols.text(field.name).ok_or_else(|| {
            ProjectionError::Unsupported(format!(
                "header assignment missing field spelling {:?} owner {:?}",
                field.name, field.owner
            ))
        })?;
        if name == "name" {
            if matches!(
                field.value,
                crate::initializer_policy::DefaultValue::Scalar(dm_ir::SemanticValue::Null)
            ) {
                null_names.insert(id);
            } else {
                null_names.remove(&id);
            }
        }
        // Runtime override tokens are authored defaults too. Header slots use
        // scalar locks only, retaining the initial parent value until runtime.
        override_own.entry(id).or_default().insert(name);
        if matches!(
            field.value,
            crate::initializer_policy::DefaultValue::Scalar(_)
                | crate::initializer_policy::DefaultValue::Transform(_)
        ) {
            own.entry(id).or_default().insert(name);
        }
    }
    let ids = projection
        .types
        .iter()
        .filter(|ty| !routing::separate_type_record(ty.path))
        .map(|ty| projected_class_index(ty.path, tables, class_ids, symbols))
        .collect::<Result<BTreeSet<_>, _>>()?;
    let order = parent_order(dmb, &ids)?;
    // Explicit source assignments outrank native subtype defaults, even when
    // the assigned value equals the ancestor's engine default. Share unchanged
    // provenance sets across descendants rather than copying per class.
    let mut effective_authored: HashMap<u32, Arc<HashSet<&str>>> = HashMap::new();
    let mut effective_overrides: HashMap<u32, Arc<HashSet<&str>>> = HashMap::new();
    let mut authored_name = HashSet::new();
    let mut authored_text = HashSet::new();
    let mut effective_recipes = HashMap::new();
    let mut retained_request = super::header_recipes::HeaderRequest {
        store: recipes,
        recipes: Vec::new(),
        defaults: Vec::new(),
    };

    for id in order {
        let authored = own.get(&id).cloned().unwrap_or_default();
        let mut local = authored.clone();
        let parent_id = dmb.classes[id as usize].parent_class_id();
        let inherited_authored = effective_authored
            .get(&parent_id)
            .cloned()
            .unwrap_or_default();
        let inherited_overrides = effective_overrides
            .get(&parent_id)
            .cloned()
            .unwrap_or_default();
        let path = dmb
            .string(dmb.classes[id as usize].path_string_id())
            .ok_or(ProjectionError::MissingMember)?;
        let engine_id = engine_classes.get(path).copied();
        let mut native_override_names = HashSet::new();
        if let Some(engine_id) = engine_id {
            let prototype = &engine.classes[engine_id];
            if let Some(parent) = engine.classes.get(prototype.parent_class_id() as usize) {
                native_header_differences(engine, prototype, parent, &mut local);
                let parent_defaults = engine
                    .class_builtin_overrides(prototype.parent_class_id() as usize)
                    .unwrap_or_default();
                for value in engine
                    .class_builtin_overrides(engine_id)
                    .unwrap_or_default()
                {
                    let name = engine
                        .string(value.name_string_id)
                        .ok_or(ProjectionError::MissingMember)?;
                    let same = parent_defaults.iter().any(|other| {
                        engine.string(other.name_string_id) == Some(name)
                            && other.value == value.value
                    });
                    if !same {
                        native_override_names.insert(name.to_vec());
                    }
                }
            }
        }
        let mut retained_recipe = None;
        let mut recipe_native_names = None;
        if let Some(store) = recipes {
            let parent_recipe = effective_recipes
                .get(&parent_id)
                .cloned()
                .unwrap_or_else(|| {
                    Arc::new(header_recipes::HeaderRecipe {
                        owner: dmb
                            .classes
                            .get(parent_id as usize)
                            .and_then(|record| dmb.string(record.path_string_id()))
                            .unwrap_or_default()
                            .to_vec(),
                        ..header_recipes::HeaderRecipe::default()
                    })
                });
            let authored_owned = authored.iter().map(|name| (*name).to_owned()).collect();
            let override_owned = override_own
                .get(&id)
                .into_iter()
                .flatten()
                .map(|name| (*name).to_owned())
                .collect();
            let local_owned = local.iter().map(|name| (*name).to_owned()).collect();
            let native_owned = native_override_names.iter().cloned().collect();
            let (key, recipe) = store.obtain_with_name_reset(
                path,
                &authored_owned,
                &override_owned,
                local_owned,
                native_owned,
                &parent_recipe,
                null_names.contains(&id),
            );
            retained_request.recipes.push(key);
            recipe_native_names = Some(recipe.native_overrides.iter().cloned().collect());
            retained_recipe = Some(recipe);
        } else {
            local.retain(|name| authored.contains(name) || !inherited_authored.contains(name));
            native_override_names.retain(|name| {
                !std::str::from_utf8(name).is_ok_and(|name| inherited_overrides.contains(name))
            });
        }
        if let Some(recipe) = &retained_recipe {
            local = recipe.local.iter().map(String::as_str).collect();
        }
        let native_override_names = recipe_native_names.unwrap_or(native_override_names);
        let inherited_name = authored_name.contains(&parent_id);
        let inherited_text = authored_text.contains(&parent_id);
        if parent_id != NONE {
            let parent = dmb
                .classes
                .get(parent_id as usize)
                .ok_or(ProjectionError::MissingMember)?
                .clone();
            if let Some(recipe) = &retained_recipe {
                inherit_record_selected(&parent, &mut dmb.classes[id as usize], |name| {
                    recipe.inherited_fields.iter().any(|field| field == name)
                })?;
            } else {
                inherit_record(
                    &parent,
                    &mut dmb.classes[id as usize],
                    &local,
                    inherited_name,
                    inherited_text,
                )?;
            }
            let owner_path = retained_recipe
                .as_ref()
                .map(|recipe| recipe.owner.as_slice())
                .unwrap_or_default();
            inherit_overrides_retained(
                dmb,
                id,
                parent_id,
                override_own.get(&id).unwrap_or(&HashSet::new()),
                &native_override_names,
                recipes.map(|store| (store, owner_path)),
                &mut retained_request.defaults,
            )?;
        }
        if let Some(recipe) = retained_recipe {
            effective_recipes.insert(id, recipe);
        }
        if recipes.is_none() {
            effective_authored.insert(id, extend_provenance(inherited_authored, &authored));
            effective_overrides.insert(
                id,
                extend_provenance(
                    inherited_overrides,
                    override_own.get(&id).unwrap_or(&HashSet::new()),
                ),
            );
        }
        if authored.contains("name") && dmb.classes[id as usize].name_string_id() == NONE {
            // Native null-name reset restores the type leaf instead of leaving
            // a null display name. Its generated name is not inherited.
            let path = dmb
                .string(dmb.classes[id as usize].path_string_id())
                .ok_or(ProjectionError::MissingMember)?;
            let leaf = path
                .rsplit(|&byte| byte == b'/')
                .next()
                .unwrap_or_default()
                .iter()
                .map(|&byte| if byte == b'_' { b' ' } else { byte })
                .collect::<Vec<_>>();
            let name = pool
                .intern(dmb, &leaf)
                .map_err(|error| ProjectionError::Unsupported(format!("header name {error:?}")))?;
            dmb.classes[id as usize].initial_ids[2] = name;
        }
        if !null_names.contains(&id) && (authored.contains("name") || inherited_name) {
            authored_name.insert(id);
        }
        if authored.contains("text") || inherited_text {
            authored_text.insert(id);
        }
        let interface = dmb.classes[id as usize].native_interface();
        if !authored_text.contains(&id)
            && !matches!(
                interface,
                byond_dmb::dmb::ClassInterface::Image
                    | byond_dmb::dmb::ClassInterface::MutableAppearance
            )
        {
            // Pinned native display derivation uses the first raw name byte,
            // after the special article-prefix bytes, not a Unicode character.
            let name_id = dmb.classes[id as usize].name_string_id();
            let bytes = dmb.string(name_id).map(|mut name| {
                while name.starts_with(&[0xff, 0x15]) || name.starts_with(&[0xff, 0x16]) {
                    name = &name[2..];
                }
                name.first().copied().into_iter().collect::<Vec<_>>()
            });
            dmb.classes[id as usize].text = match bytes {
                Some(bytes) => pool.intern(dmb, &bytes).map_err(|error| {
                    ProjectionError::Unsupported(format!("header text {error:?}"))
                })?,
                None => NONE,
            };
        }
    }
    Ok(())
}

fn extend_provenance<'a>(
    inherited: Arc<HashSet<&'a str>>,
    own: &HashSet<&'a str>,
) -> Arc<HashSet<&'a str>> {
    if own.is_empty() {
        return inherited;
    }
    let mut combined = inherited.as_ref().clone();
    combined.extend(own.iter().copied());
    Arc::new(combined)
}

fn projected_class_index(
    owner: SymbolId,
    tables: &dm_link::LinkTables,
    class_ids: &HashMap<SymbolId, u32>,
    symbols: &SymbolTable,
) -> Result<u32, ProjectionError> {
    let path = symbols.text(owner).ok_or_else(|| {
        ProjectionError::Unsupported(format!("header owner missing spelling {owner:?}"))
    })?;
    let actual = class_ids.get(&owner).copied().ok_or_else(|| {
        ProjectionError::Unsupported(format!("header owner {path} has no materialized class"))
    })?;
    if let Some(bound) = tables.index(Key::Type(owner)) {
        if bound != actual {
            return Err(ProjectionError::Unsupported(format!(
                "header owner {path} table class {bound} differs from materialized {actual}"
            )));
        }
    }
    Ok(actual)
}

fn parent_order(dmb: &Dmb, ids: &BTreeSet<u32>) -> Result<Vec<u32>, ProjectionError> {
    let mut children: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    let mut ready = VecDeque::new();
    for &id in ids {
        let parent = dmb
            .classes
            .get(id as usize)
            .ok_or(ProjectionError::MissingMember)?
            .parent_class_id();
        if parent == id {
            return Err(ProjectionError::Unsupported(
                "cyclic class header inheritance".into(),
            ));
        }
        if ids.contains(&parent) {
            children.entry(parent).or_default().push(id);
        } else {
            ready.push_back(id);
        }
    }
    let mut order = Vec::with_capacity(ids.len());
    while let Some(id) = ready.pop_front() {
        order.push(id);
        if let Some(children) = children.remove(&id) {
            ready.extend(children);
        }
    }
    if order.len() != ids.len() {
        return Err(ProjectionError::Unsupported(
            "cyclic class header inheritance".into(),
        ));
    }
    Ok(order)
}

fn inherit_record(
    parent: &Class,
    child: &mut Class,
    own: &HashSet<&str>,
    authored_name: bool,
    authored_text: bool,
) -> Result<(), ProjectionError> {
    inherit_record_selected(parent, child, |name| {
        !own.contains(name)
            && match name {
                "name" => authored_name,
                "text" => authored_text,
                _ => true,
            }
    })
}
fn inherit_record_selected(
    parent: &Class,
    child: &mut Class,
    inherit: impl Fn(&str) -> bool,
) -> Result<(), ProjectionError> {
    for field in fields::FIELDS {
        if inherit(field.name) {
            (field.copy)(parent, child)?;
        }
    }
    Ok(())
}

/// Preserve differences actually encoded by the supplied engine template.
/// A retained native subtype is not merely a clone of its parent.
fn native_header_differences(engine: &Dmb, child: &Class, parent: &Class, own: &mut HashSet<&str>) {
    for (name, slot) in [("desc", 3), ("icon", 4), ("icon_state", 5)] {
        let child_id = child.initial_ids[slot];
        let parent_id = parent.initial_ids[slot];
        let same = child_id == parent_id
            || (name != "icon"
                && child_id != NONE
                && parent_id != NONE
                && engine.string(child_id).is_some()
                && engine.string(child_id) == engine.string(parent_id));
        if !same {
            own.insert(name);
        }
    }
    for (name, different) in [
        (
            "transform",
            child.transform_flag != parent.transform_flag || child.transform != parent.transform,
        ),
        ("layer", child.layer_bits != parent.layer_bits),
        ("dir", child.direction != parent.direction),
        ("maptext", child.maptext != parent.maptext),
        ("suffix", child.suffix != parent.suffix),
        (
            "invisibility",
            child.is_normally_visible() != parent.is_normally_visible(),
        ),
        ("gender", child.gender_code() != parent.gender_code()),
        ("density", child.is_dense() != parent.is_dense()),
        ("opacity", child.is_opaque() != parent.is_opaque()),
        (
            "appearance_flags",
            child.appearance_flags() != parent.appearance_flags(),
        ),
        ("luminosity", child.luminosity() != parent.luminosity()),
        (
            "mouse_opacity",
            child.mouse_opacity() != parent.mouse_opacity(),
        ),
        (
            "animate_movement",
            child.animate_movement() != parent.animate_movement(),
        ),
    ] {
        if different {
            own.insert(name);
        }
    }
    for (name, slot) in [
        ("maptext_width", 0),
        ("maptext_height", 1),
        ("maptext_x", 2),
        ("maptext_y", 3),
    ] {
        if child.maptext_geometry[slot] != parent.maptext_geometry[slot] {
            own.insert(name);
        }
    }
}

#[cfg(test)]
fn inherit_overrides(
    dmb: &mut Dmb,
    child: u32,
    parent: u32,
    authored: &HashSet<&str>,
    native_names: &HashSet<Vec<u8>>,
) -> Result<(), ProjectionError> {
    inherit_overrides_retained(
        dmb,
        child,
        parent,
        authored,
        native_names,
        None,
        &mut Vec::new(),
    )
}
#[allow(clippy::too_many_arguments)]
fn inherit_overrides_retained(
    dmb: &mut Dmb,
    child: u32,
    parent: u32,
    authored: &HashSet<&str>,
    native_names: &HashSet<Vec<u8>>,
    retention: Option<(&HeaderRecipes, &[u8])>,
    current_keys: &mut Vec<Vec<u8>>,
) -> Result<(), ProjectionError> {
    let decode = |id: u32| {
        if dmb.classes[id as usize].overrides == NONE {
            Ok(Vec::new())
        } else {
            dmb.class_builtin_overrides(id as usize)
                .ok_or_else(|| ProjectionError::Unsupported("malformed builtin defaults".into()))
        }
    };
    let parent_values = decode(parent)?;
    if parent_values.is_empty() {
        return Ok(());
    }
    let own_values = decode(child)?
        .into_iter()
        .filter(|value| {
            dmb.string(value.name_string_id).is_some_and(|name| {
                native_names.contains(name)
                    || std::str::from_utf8(name).is_ok_and(|name| authored.contains(name))
            })
        })
        .collect::<Vec<_>>();
    let own_names = own_values
        .iter()
        .map(|value| {
            dmb.string(value.name_string_id)
                .map(<[u8]>::to_vec)
                .ok_or(ProjectionError::MissingMember)
        })
        .collect::<Result<HashSet<_>, _>>()?;
    let mut words = Vec::new();
    if let Some((store, owner)) = retention {
        let names = |rows: &[byond_dmb::dmb::ClassBuiltinOverride]| {
            rows.iter()
                .map(|row| {
                    dmb.string(row.name_string_id)
                        .map(<[u8]>::to_vec)
                        .ok_or(ProjectionError::MissingMember)
                })
                .collect::<Result<Vec<_>, _>>()
        };
        // Parent malformed names historically do not prevent emission. Preserve that
        // behavior by declining selectors and using the exact ordinary producer.
        let selectors = names(&parent_values).and_then(|parent_names| {
            names(&own_values).map(|own_names| store.defaults(owner, &parent_names, &own_names))
        });
        if let Ok((key, selectors)) = selectors {
            current_keys.push(key);
            for selector in selectors.iter() {
                let rows = if selector.from_parent {
                    &parent_values
                } else {
                    &own_values
                };
                let value = rows
                    .get(selector.ordinal)
                    .ok_or(ProjectionError::MissingMember)?;
                if dmb.string(value.name_string_id) != Some(selector.name.as_slice()) {
                    return Err(ProjectionError::MissingMember);
                }
                words.push(value.name_string_id);
                words.extend(value.value.encode());
            }
        } else {
            append_override_rows(dmb, &parent_values, &own_values, &own_names, &mut words);
        }
    } else {
        append_override_rows(dmb, &parent_values, &own_values, &own_names, &mut words);
    }
    dmb.classes[child as usize].overrides =
        crate::composition::append_list(dmb, words).map_err(|error| {
            ProjectionError::Unsupported(format!("inherited builtin defaults {error:?}"))
        })?;
    Ok(())
}

fn append_override_rows(
    dmb: &Dmb,
    parent_values: &[byond_dmb::dmb::ClassBuiltinOverride],
    own_values: &[byond_dmb::dmb::ClassBuiltinOverride],
    own_names: &HashSet<Vec<u8>>,
    words: &mut Vec<u32>,
) {
    for value in parent_values
        .iter()
        .filter(|value| {
            !dmb.string(value.name_string_id)
                .is_some_and(|name| own_names.contains(name))
        })
        .chain(own_values.iter())
    {
        words.push(value.name_string_id);
        words.extend(value.value.encode());
    }
}

#[cfg(test)]
#[path = "headers_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "headers_null_name_tests.rs"]
mod null_name_tests;

#[cfg(test)]
mod routing_tests {
    use super::*;

    #[test]
    fn world_and_root_projection_use_separate_records_while_retained_classes_finalize() {
        let bytes = include_bytes!("../../../../fixtures/native_template.bin");
        let mut dmb = Dmb::from_bytes(bytes).unwrap();
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let world = symbols.intern("/world").unwrap();
        let atom = symbols.intern("/atom").unwrap();
        let name = symbols.intern("name").unwrap();
        let savefile = symbols.intern("/savefile").unwrap();
        let version = symbols.intern("byond_version").unwrap();
        let projection = ClassProjection {
            type_construction: Default::default(),
            variable_records: Default::default(),
            field_placements: Default::default(),
            shared_slot_order: Arc::from([]),
            procedure_statics: Arc::from([]),
            runtime_writes: Arc::from([]),
            tree_identity: 0,
            occurrence_count: 0,
            types: vec![
                TypeProjection {
                    path: root,
                    parent: None,
                },
                TypeProjection {
                    path: world,
                    parent: None,
                },
                TypeProjection {
                    path: atom,
                    parent: None,
                },
            ]
            .into(),
            fields: vec![
                std::sync::Arc::new(FieldProjection {
                    owner: savefile,
                    declaring_owner: savefile,
                    name: version,
                    role: FieldRole::Assignment,
                    wire_flags: None,
                    intrinsic: true,
                    shared: false,
                    value: crate::initializer_policy::DefaultValue::Scalar(
                        dm_ir::SemanticValue::Null,
                    ),
                }),
                std::sync::Arc::new(FieldProjection {
                    owner: world,
                    declaring_owner: world,
                    name,
                    role: FieldRole::Assignment,
                    wire_flags: None,
                    intrinsic: true,
                    shared: false,
                    value: crate::initializer_policy::DefaultValue::Scalar(
                        dm_ir::SemanticValue::Null,
                    ),
                }),
            ]
            .into(),
            chains: Arc::from([]),
            procedure_membership: Arc::from([]),
            procedure_declarations: Arc::new(BTreeMap::new()),
        };
        let tables = dm_link::LinkTables::build(Default::default()).unwrap();
        finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
        let unknown = symbols.intern("/uncaptured").unwrap();
        assert!(projected_class_index(unknown, &tables, &HashMap::new(), &symbols).is_err());
    }
}
