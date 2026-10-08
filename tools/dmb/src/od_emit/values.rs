//! Native value metadata and reference conversion.
use super::*;

pub(super) fn native_world_view(view: &JsonValue) -> Result<u16, EmitError> {
    if let Some(radius) = view.as_f64() {
        if !radius.is_finite() || !(-1.0..=35.0).contains(&radius) {
            return Err(EmitError::Invalid(
                "world.view radius must be between -1 and 35".into(),
            ));
        }
        let side = (radius as i32 * 2 + 1) as u16;
        return Ok((side << 8) | side);
    }
    let text = view.as_str().ok_or_else(|| {
        EmitError::Unsupported("world.view must be numeric or WIDTHxHEIGHT".into())
    })?;
    fn decimal(bytes: &[u8]) -> Option<(i32, usize)> {
        let mut at = 0;
        while bytes.get(at).is_some_and(u8::is_ascii_whitespace) {
            at += 1;
        }
        let negative = bytes.get(at) == Some(&b'-');
        if matches!(bytes.get(at), Some(b'+' | b'-')) {
            at += 1;
        }
        let digits = at;
        let mut value = 0i64;
        while let Some(byte @ b'0'..=b'9') = bytes.get(at) {
            value = (value * 10 + i64::from(*byte - b'0')).min(i64::from(i32::MAX) + 1);
            at += 1;
        }
        if at == digits {
            return None;
        }
        let value = if negative { -value } else { value };
        Some((
            value.clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32,
            at,
        ))
    }
    let bytes = text.as_bytes();
    let (width, at) = decimal(bytes)
        .filter(|(_, at)| bytes.get(*at) == Some(&b'x'))
        .ok_or_else(|| EmitError::Invalid("world.view requires decimal WIDTHxHEIGHT".into()))?;
    let (height, _) = decimal(&bytes[at + 1..])
        .ok_or_else(|| EmitError::Invalid("world.view requires a decimal height".into()))?;
    let (width, height) = (width.max(0) as u32, height.max(0) as u32);
    if width > 255 || height > 255 || width * height > 5041 {
        return Err(EmitError::Invalid(
            "world.view dimensions exceed native limits".into(),
        ));
    }
    Ok(if width == 0 {
        (height / 2) as u16
    } else {
        ((width << 8) | height) as u16
    })
}
/// Native client setup visits descendants before their parents, preserving
/// sibling creation order. Only authored settings participate in this fold.
pub(super) fn native_client_configuration(
    program: &OpenDreamProgram,
) -> Option<(HashMap<String, JsonValue>, HashSet<String>)> {
    let root = program.types.iter().position(|typ| typ.path == "/client")?;
    let mut values = program.types[root].variables.clone();
    let mut authored = HashSet::new();
    fn visit(
        program: &OpenDreamProgram,
        id: usize,
        values: &mut HashMap<String, JsonValue>,
        authored: &mut HashSet<String>,
        seen: &mut HashSet<usize>,
    ) {
        if !seen.insert(id) {
            return;
        }
        for (child, typ) in program.types.iter().enumerate() {
            if typ.parent == Some(id) {
                visit(program, child, values, authored, seen);
            }
        }
        let typ = &program.types[id];
        for name in [
            "control_freak",
            "preload_rsc",
            "script",
            "show_verb_panel",
            "lazy_eye",
            "authenticate",
            "show_popup_menus",
            "show_map",
            "macro_mode",
            "perspective",
        ] {
            let setting = typ
                .native_client_settings
                .get(name)
                .cloned()
                .or_else(|| {
                    typ.explicit_type_fields
                        .contains(name)
                        .then(|| typ.variables.get(name).cloned())
                        .flatten()
                })
                .or_else(|| {
                    (typ.path == "/client")
                        .then(|| {
                            program
                                .native_client_settings
                                .get(name)
                                .map(|&value| JsonValue::from(value))
                        })
                        .flatten()
                });
            if let Some(value) = setting {
                values.insert(name.into(), value);
                authored.insert(name.into());
            }
        }
    }
    visit(
        program,
        root,
        &mut values,
        &mut authored,
        &mut HashSet::new(),
    );
    Some((values, authored))
}
pub(super) fn native_blank_class() -> crate::dmb::Class {
    crate::dmb::Class {
        initial_ids: [NONE; 6],
        direction: 2,
        interface: 1,
        extended_interface: None,
        text: NONE,
        maptext: NONE,
        maptext_geometry: [0; 4],
        suffix: NONE,
        flags: 0,
        lists_and_procs: [NONE; 6],
        layer_bits: (-1.0f32).to_bits(),
        transform_flag: 0,
        transform: None,
        color_matrix_flag: 0,
        color_matrix: None,
        overrides: NONE,
    }
}
pub(super) fn native_blank_proc() -> Proc {
    Proc {
        strings: [NONE; 4],
        source_parameter: 255,
        source_kind: 0,
        flags: 4,
        extended_flags: None,
        code_locals_args: [NONE; 3],
    }
}
pub(super) struct ModifiedTypeParts {
    pub(super) path: String,
    pub(super) overrides: HashMap<String, JsonValue>,
    pub(super) order: Vec<String>,
}

#[derive(Clone)]
pub(super) struct ResolvedVerbMetadata {
    pub(super) attributes: u32,
    pub(super) name: Option<String>,
    pub(super) category: Option<String>,
    pub(super) desc: Option<String>,
    pub(super) source: Option<i32>,
    pub(super) range: Option<i32>,
    pub(super) invisibility: i8,
    pub(super) explicit_invisibility: bool,
}

pub(super) fn argument_type_flags(
    argument: &OpenDreamArgument,
    program: &OpenDreamProgram,
) -> Result<u32, EmitError> {
    const VERIFIED_OD_TYPES: u32 = 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 512 | 2048 | 4096;
    if argument.r#type & !VERIFIED_OD_TYPES != 0 {
        return Err(EmitError::Unsupported(format!(
            "argument {} has unpaired OpenDream type flags {:#x}",
            argument.name, argument.r#type
        )));
    }
    let mut flags = if argument.explicit_anything {
        crate::dmb::argument_type::ANYTHING
    } else {
        0
    };
    for (od, dmb) in [
        (1, 0x80),
        (2, 4),
        (4, 2),
        (8, 1),
        (16, 0x20),
        (32, 8),
        (64, 0x800),
        (128, 0x100),
        (512, 0x10),
        (2048, 0x400),
        (4096, 0x200),
    ] {
        if argument.r#type & od != 0 {
            flags |= dmb;
        }
    }
    if flags == 0 {
        if let Some(id) = argument
            .type_path
            .as_deref()
            .and_then(|path| program.types.iter().position(|typ| typ.path == path))
        {
            flags = match program.native_type_tag(id) {
                Some(8) => 1,
                Some(9) => {
                    if program.type_inherits_path(id, "/obj") {
                        2
                    } else {
                        3
                    }
                }
                Some(10) => {
                    if program.type_inherits_path(id, "/turf") {
                        0x20
                    } else {
                        0x123
                    }
                }
                Some(11) => 0x100,
                _ => 0,
            };
        }
    }
    if flags == 0 && argument.type_path.as_deref() == Some("/list") {
        if let Some(declared) = argument.declared_path.as_deref() {
            let declared = declared
                .trim_start_matches('/')
                .strip_prefix("var/")
                .unwrap_or(declared.trim_start_matches('/'));
            let mut parts = declared.split('/');
            if parts.next() == Some("list") {
                flags = match parts.next() {
                    Some("mob") => crate::dmb::argument_type::MOB,
                    Some("obj") => crate::dmb::argument_type::OBJ,
                    Some("turf") => crate::dmb::argument_type::TURF,
                    Some("area") => crate::dmb::argument_type::AREA,
                    Some("atom") => match parts.next() {
                        Some("movable") => 3,
                        _ => 0x123,
                    },
                    _ => 0,
                };
            }
        }
    }
    Ok(flags)
}

pub(super) fn modified_type_json(
    value: &JsonValue,
) -> Result<Option<ModifiedTypeParts>, EmitError> {
    if value.get("type").and_then(JsonValue::as_u64) != Some(7) {
        return Ok(None);
    }
    let path = value
        .get("TypePath")
        .and_then(JsonValue::as_str)
        .ok_or_else(|| EmitError::Invalid("modified type constant lacks TypePath".into()))?;
    let overrides = value
        .get("Overrides")
        .and_then(JsonValue::as_object)
        .ok_or_else(|| EmitError::Invalid("modified type constant lacks Overrides".into()))?
        .iter()
        .map(|(name, value)| (name.clone(), value.clone()))
        .collect();
    let order = value
        .get("OverrideOrder")
        .and_then(JsonValue::as_array)
        .map(|names| {
            names
                .iter()
                .map(|name| {
                    name.as_str().map(str::to_owned).ok_or_else(|| {
                        EmitError::Invalid("modified type OverrideOrder contains non-string".into())
                    })
                })
                .collect::<Result<Vec<_>, _>>()
        })
        .transpose()?
        .unwrap_or_default();
    Ok(Some(ModifiedTypeParts {
        path: path.to_owned(),
        overrides,
        order,
    }))
}

pub(super) fn requires_wide_object_ids(dmb: &Dmb) -> bool {
    [
        dmb.classes.len(),
        dmb.mobs.len(),
        dmb.strings.len(),
        dmb.lists.len(),
        dmb.procs.len(),
        dmb.variables.len(),
        dmb.proc_references.len(),
        dmb.instances.len(),
        dmb.map_objects.len(),
        dmb.resources.len(),
    ]
    .into_iter()
    .any(|count| count > u16::MAX as usize)
}

pub(super) fn is_class_value_tag(tag: u8) -> bool {
    matches!(tag, 9 | 10 | 11 | 32 | 36 | 39 | 40 | 63 | 89)
}
pub(super) fn remap_class_value(value: &mut Value, remap: &[u32]) -> Result<(), EmitError> {
    if !is_class_value_tag(value.tag()) || (value.id() == 0 && matches!(value.tag(), 36 | 39 | 40))
    {
        return Ok(());
    }
    let id = *remap
        .get(value.id() as usize)
        .ok_or_else(|| EmitError::Invalid("type value has invalid ClassID".into()))?;
    value.tag_word = (value.tag_word & !0xff00) | ((id >> 16) << 8);
    value.data_word = (value.data_word & !0xffff) | (id & 0xffff);
    Ok(())
}
pub(super) fn remap_proc_variable(
    variable: &mut crate::operands::Variable,
    remap: &[u32],
) -> Result<(), EmitError> {
    use crate::operands::Variable;
    match variable {
        Variable::StaticProc(id) | Variable::StaticVerb(id) => {
            *id = *remap
                .get(*id as usize)
                .ok_or_else(|| EmitError::Invalid("static selector has invalid ProcID".into()))?;
        }
        Variable::SetCache(left, right) => {
            remap_proc_variable(left, remap)?;
            remap_proc_variable(right, remap)?;
        }
        Variable::Initial(inner) | Variable::IsSaved(inner) => remap_proc_variable(inner, remap)?,
        _ => {}
    }
    Ok(())
}
pub(super) fn remap_proc_value(value: &mut Value, remap: &[u32]) -> Result<(), EmitError> {
    if value.tag() != 38 {
        return Ok(());
    }
    let id = *remap
        .get(value.id() as usize)
        .ok_or_else(|| EmitError::Invalid("proc value has invalid ProcID".into()))?;
    value.tag_word = (value.tag_word & !0xff00) | ((id >> 16) << 8);
    value.data_word = (value.data_word & !0xffff) | (id & 0xffff);
    Ok(())
}
pub(super) fn same_od_constant(
    a: &JsonValue,
    b: &JsonValue,
    input: &OpenDreamProgram,
    baseline: &OpenDreamProgram,
) -> bool {
    if a == b {
        return true;
    }
    if a.get("type").and_then(JsonValue::as_u64) == Some(1)
        && b.get("type").and_then(JsonValue::as_u64) == Some(1)
    {
        let a = a
            .get("value")
            .and_then(JsonValue::as_u64)
            .and_then(|id| input.types.get(id as usize));
        let b = b
            .get("value")
            .and_then(JsonValue::as_u64)
            .and_then(|id| baseline.types.get(id as usize));
        return a.zip(b).is_some_and(|(a, b)| a.path == b.path);
    }
    false
}
