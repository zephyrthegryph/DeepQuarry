//! Wire materialization of scalar members and procedure chains.
use super::*;

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
    let mut pool = crate::composition::StringIndex::build(dmb)
        .map_err(|e| ProjectionError::Unsupported(format!("world strings {e:?}")))?;
    materialize_members_with_strings(dmb, projection, tables, symbols, value_types, &mut pool)
}

pub(crate) fn materialize_members_with_strings(
    dmb: &mut byond_dmb::dmb::Dmb,
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
    symbols: &dm_ir::SymbolTable,
    value_types: &dyn TypeValuePolicy,
    pool: &mut crate::composition::StringIndex,
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
                return Err(ProjectionError::Unsupported(
                    "resource policy returned a non-resource key".into(),
                ));
            }
            self.tables.index(key).ok_or_else(|| {
                ProjectionError::Unsupported(
                    "resource content absent from frozen link inventory".into(),
                )
            })
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
    let savefile_values = projection
        .fields
        .iter()
        .filter(|field| {
            field.owner == savefile
                && field.intrinsic
                && field.name == SymbolId::of("byond_version")
        })
        .map(|field| match &field.value {
            DefaultValue::Scalar(value) => {
                crate::savefile_projection::project(value).map_err(ProjectionError::Unsupported)
            }
            _ => Err(ProjectionError::Unsupported(
                "savefile header requires scalar default".into(),
            )),
        })
        .collect::<Result<Vec<_>, _>>()?;
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
    let client_order = routing::client_configuration_order(projection, tables)?;
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

    crate::world_writer::apply(
        dmb,
        &directives,
        pool,
        &Defaults {
            tables,
            values: value_types,
        },
    )
    .map_err(ProjectionError::Unsupported)?;
    if let Some(script) = client_directives
        .iter()
        .rev()
        .find_map(|directive| match directive {
            crate::client_projection::Directive::Script(script) => Some(script),
            _ => None,
        })
    {
        struct ScriptBindings<'a> {
            strings: &'a mut crate::composition::StringIndex,
            resources: &'a dyn TypeValuePolicy,
        }
        impl crate::client_script::Bindings for ScriptBindings<'_> {
            fn string(
                &mut self,
                dmb: &mut byond_dmb::dmb::Dmb,
                bytes: &[u8],
            ) -> Result<u32, String> {
                self.strings
                    .intern(dmb, bytes)
                    .map_err(|error| format!("{error:?}"))
            }
            fn resource(&self, symbol: SymbolId) -> Result<u32, String> {
                self.resources
                    .resource_index(symbol)
                    .map_err(|error| format!("{error:?}"))
            }
        }
        crate::client_script::apply(
            dmb,
            script,
            &mut ScriptBindings {
                strings: pool,
                resources: value_types,
            },
        )
        .map_err(ProjectionError::Unsupported)?;
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
                        return Err(ProjectionError::Unsupported(
                            "primitive family policy disagrees with captured native tag".into(),
                        ));
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
                    Key::Verb {
                        owner: identity.owner,
                        name: identity.name,
                        occurrence: identity.occurrence,
                    }
                } else {
                    Key::Proc {
                        owner: identity.owner,
                        name: identity.name,
                        occurrence: identity.occurrence,
                    }
                };
                let index = tables.index(key).ok_or_else(|| {
                    ProjectionError::Unsupported(
                        "procedure literal absent from frozen link inventory".into(),
                    )
                })?;
                Ok((38, index))
            }
            SemanticValue::ModifiedInstance(instance) => {
                let key = Key::Instance(SymbolId::of(&instance.alias()));
                let index = tables.index(key).ok_or_else(|| {
                    ProjectionError::Unsupported(
                        "modified default descriptor absent from frozen inventory".into(),
                    )
                })?;
                if tables.content(key) != Some(instance.canonical_bytes()) {
                    return Err(ProjectionError::Unsupported(
                        "modified default descriptor content differs from frozen inventory".into(),
                    ));
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
        let (kind, value) = scalar(dmb, pool, &field.value, tables, value_types)?;
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
        let (kind, value) = scalar(dmb, pool, &local.value, tables, value_types)?;
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
        if routing::separate_intrinsic_field(field, &client_owners, symbols)? {
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
            let (kind, value) = scalar(dmb, pool, &field.value, tables, value_types)?;
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
                "luminosity" => {
                    dmb.classes[class as usize]
                        .set_luminosity(integer(0.0, 7.0)? as u8)
                        .map_err(|e| ProjectionError::Unsupported(e.to_string()))?;
                    // Pinned BYOND stores authored luminosity both in the
                    // appearance header and as a builtin selector default,
                    // including assignments equal to the engine baseline.
                    let selector = pool.intern(dmb, name.as_bytes()).map_err(|e| {
                        ProjectionError::Unsupported(format!("luminosity selector {e:?}"))
                    })?;
                    let mut words = vec![selector];
                    words.extend(encoded_constant(kind, value)?);
                    let old = dmb.classes[class as usize].overrides;
                    dmb.classes[class as usize].overrides = extend(dmb, old, words)?;
                }
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
        let (kind, value) = scalar(dmb, pool, &field.value, tables, value_types)?;
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

#[cfg(test)]
#[path = "members_luminosity_tests.rs"]
mod luminosity_tests;
