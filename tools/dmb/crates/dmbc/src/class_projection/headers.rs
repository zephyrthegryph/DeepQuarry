//! Finalize effective native appearance defaults after source members are written.
//! Each known property uses its wire accessor; callback flags remain independent.
use super::*;
use byond_dmb::{
    dmb::{Class, Dmb},
    ids::NONE,
};
use std::collections::{BTreeSet, VecDeque};

pub(crate) fn finalize_headers(
    dmb: &mut Dmb,
    engine_bytes: &[u8],
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
) -> Result<(), ProjectionError> {
    let engine = Dmb::from_bytes(engine_bytes)
        .map_err(|error| ProjectionError::Unsupported(format!("header engine {error}")))?;
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
    let mut own: HashMap<u32, HashSet<&str>> = HashMap::new();
    let mut override_own: HashMap<u32, HashSet<&str>> = HashMap::new();
    for field in projection
        .fields
        .iter()
        .filter(|field| field.intrinsic && field.role == FieldRole::Assignment)
    {
        let id = tables
            .index(Key::Type(field.owner))
            .ok_or(ProjectionError::MissingMember)?;
        let name = symbols
            .text(field.name)
            .ok_or(ProjectionError::MissingMember)?;
        // Runtime override tokens are authored defaults too. Header slots use
        // scalar locks only, retaining the initial parent value until runtime.
        override_own.entry(id).or_default().insert(name);
        if matches!(
            field.value,
            crate::initializer_policy::DefaultValue::Scalar(_)
        ) {
            own.entry(id).or_default().insert(name);
        }
    }
    let ids = projection
        .types
        .iter()
        .map(|ty| {
            tables
                .index(Key::Type(ty.path))
                .ok_or(ProjectionError::MissingMember)
        })
        .collect::<Result<BTreeSet<_>, _>>()?;
    let order = parent_order(dmb, &ids)?;
    let mut authored_name = HashSet::new();
    let mut authored_text = HashSet::new();
    let mut pool = crate::composition::StringIndex::build(dmb)
        .map_err(|error| ProjectionError::Unsupported(format!("header strings {error:?}")))?;
    for id in order {
        let authored = own.get(&id).cloned().unwrap_or_default();
        let mut local = authored.clone();
        let path = dmb
            .string(dmb.classes[id as usize].path_string_id())
            .ok_or(ProjectionError::MissingMember)?;
        let engine_id = engine_classes.get(path).copied();
        let mut native_override_names = HashSet::new();
        if let Some(engine_id) = engine_id {
            let prototype = &engine.classes[engine_id];
            if let Some(parent) = engine.classes.get(prototype.parent_class_id() as usize) {
                native_header_differences(&engine, prototype, parent, &mut local);
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
        let parent_id = dmb.classes[id as usize].parent_class_id();
        let inherited_name = authored_name.contains(&parent_id);
        let inherited_text = authored_text.contains(&parent_id);
        if parent_id != NONE {
            let parent = dmb
                .classes
                .get(parent_id as usize)
                .ok_or(ProjectionError::MissingMember)?
                .clone();
            inherit_record(
                &parent,
                &mut dmb.classes[id as usize],
                &local,
                inherited_name,
                inherited_text,
            )?;
            inherit_overrides(
                dmb,
                id,
                parent_id,
                override_own.get(&id).unwrap_or(&HashSet::new()),
                &native_override_names,
            )?;
        }
        if authored.contains("name") && dmb.classes[id as usize].name_string_id() == NONE {
            // Native null-name reset restores the type leaf instead of leaving
            // a null display name. Keep this an authored effective name.
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
        if authored.contains("name") || inherited_name {
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
    for (name, slot) in [("desc", 3), ("icon", 4), ("icon_state", 5)] {
        if !own.contains(name) {
            child.initial_ids[slot] = parent.initial_ids[slot];
        }
    }
    if authored_name && !own.contains("name") {
        child.initial_ids[2] = parent.initial_ids[2];
    }
    if authored_text && !own.contains("text") {
        child.text = parent.text;
    }
    if !own.contains("layer") {
        child.layer_bits = parent.layer_bits;
    }
    if !own.contains("dir") {
        child.direction = parent.direction;
    }
    if !own.contains("maptext") {
        child.maptext = parent.maptext;
    }
    if !own.contains("suffix") {
        child.suffix = parent.suffix;
    }
    for (name, slot) in [
        ("maptext_width", 0),
        ("maptext_height", 1),
        ("maptext_x", 2),
        ("maptext_y", 3),
    ] {
        if !own.contains(name) {
            child.maptext_geometry[slot] = parent.maptext_geometry[slot];
        }
    }
    if !own.contains("density") {
        child.set_dense(parent.is_dense());
    }
    if !own.contains("opacity") {
        child.set_opaque(parent.is_opaque());
    }
    if !own.contains("appearance_flags") {
        child.set_appearance_flags(parent.appearance_flags());
    }
    if !own.contains("luminosity") {
        child
            .set_luminosity(parent.luminosity())
            .map_err(|e| ProjectionError::Unsupported(e.to_string()))?;
    }
    if !own.contains("mouse_opacity") {
        child
            .set_mouse_opacity(parent.mouse_opacity())
            .map_err(|e| ProjectionError::Unsupported(e.to_string()))?;
    }
    if !own.contains("animate_movement") {
        child
            .set_animate_movement(parent.animate_movement())
            .map_err(|e| ProjectionError::Unsupported(e.to_string()))?;
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
        ("layer", child.layer_bits != parent.layer_bits),
        ("dir", child.direction != parent.direction),
        ("maptext", child.maptext != parent.maptext),
        ("suffix", child.suffix != parent.suffix),
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

fn inherit_overrides(
    dmb: &mut Dmb,
    child: u32,
    parent: u32,
    authored: &HashSet<&str>,
    native_names: &HashSet<Vec<u8>>,
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
    dmb.classes[child as usize].overrides =
        crate::composition::append_list(dmb, words).map_err(|error| {
            ProjectionError::Unsupported(format!("inherited builtin defaults {error:?}"))
        })?;
    Ok(())
}

#[cfg(test)]
#[path = "headers_tests.rs"]
mod tests;
