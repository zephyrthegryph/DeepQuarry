//! Small, strict DMM reader. Map files are separate compilation inputs, not DM source.
#[cfg(test)]
use byond_dmb::bytecode::opcode;
use byond_dmb::dmb::{DmString, Dmb, GridRun, Instance, MapObject, Proc};
use dm_codegen_byond::{
    compile_simple_proc_with_bindings, link_proc, Ledger, LowerBindings, Symbol, Table,
};
use dm_resources::ResourceSet;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
#[cfg(test)]
use std::fs;
use std::path::{Path, PathBuf};

pub struct MapSet {
    pub files: Vec<(PathBuf, String)>,
    pub fingerprint: [u8; 32],
}

pub fn load_map_set(dme_path: &Path) -> Result<MapSet, String> {
    fn visit(
        path: &Path,
        seen: &mut HashSet<PathBuf>,
        maps: &mut Vec<PathBuf>,
    ) -> Result<(), String> {
        let path = path
            .canonicalize()
            .map_err(|error| format!("{}: {error}", path.display()))?;
        if !seen.insert(path.clone()) {
            return Ok(());
        }
        if path
            .extension()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("dmm"))
        {
            maps.push(path);
            return Ok(());
        }
        let source = dm_preprocess::read_source_file(&path)
            .map_err(|error| format!("{}: {error}", path.display()))?;
        for line in source.lines() {
            let Some(include) = line.trim().strip_prefix("#include") else {
                continue;
            };
            let Some(name) = include
                .trim()
                .strip_prefix('"')
                .and_then(|text| text.split_once('"').map(|(name, _)| name))
            else {
                continue;
            };
            let included = path.parent().unwrap().join(name.replace('\\', "/"));
            if included.extension().is_some_and(|ext| {
                ext.eq_ignore_ascii_case("dm")
                    || ext.eq_ignore_ascii_case("dme")
                    || ext.eq_ignore_ascii_case("dmm")
            }) {
                visit(&included, seen, maps)?;
            }
        }
        Ok(())
    }
    let mut paths = Vec::new();
    visit(dme_path, &mut HashSet::new(), &mut paths)?;
    load_map_set_from_paths(dme_path, &paths)
}

pub fn load_map_set_from_paths(dme_path: &Path, paths: &[PathBuf]) -> Result<MapSet, String> {
    let raw_root = dme_path
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let root = raw_root.canonicalize().map_err(|error| error.to_string())?;
    let mut files = Vec::new();
    let mut seen = HashSet::new();
    let mut hash = Sha256::new();
    let mut ordered_paths = Vec::new();
    for path in paths {
        let disk = if path.is_absolute() || path.starts_with(raw_root) {
            path.clone()
        } else {
            raw_root.join(path)
        };
        let disk = disk
            .canonicalize()
            .map_err(|error| format!("{}: {error}", disk.display()))?;
        if !seen.insert(disk.clone()) {
            continue;
        }
        let relative = disk
            .strip_prefix(&root)
            .map_err(|_| format!("map lies outside project: {}", disk.display()))?;
        ordered_paths.push((disk.clone(), relative.to_path_buf()));
    }
    // Keep reads bounded and commit in manifest order: map order determines z
    // offsets and must remain independent of worker scheduling.
    let workers = std::env::var("DM_COMPILER_WORKERS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(2);
    for batch in ordered_paths.chunks(workers.clamp(1, 2)) {
        let loaded = std::thread::scope(|scope| {
            let pending: Vec<_> = batch
                .iter()
                .map(|(disk, _)| {
                    scope.spawn(move || {
                        dm_preprocess::read_source_file(disk)
                            .map_err(|error| format!("{}: {error}", disk.display()))
                    })
                })
                .collect();
            pending
                .into_iter()
                .map(|worker| {
                    worker
                        .join()
                        .map_err(|_| "map reader worker panicked".to_owned())?
                })
                .collect::<Result<Vec<_>, String>>()
        })?;
        for ((disk, relative), source) in batch.iter().zip(loaded) {
            hash.update(relative.to_string_lossy().replace('\\', "/").as_bytes());
            hash.update([0]);
            hash.update(source.as_bytes());
            hash.update([0]);
            files.push((disk.clone(), source));
        }
    }
    Ok(MapSet {
        files,
        fingerprint: hash.finalize().into(),
    })
}

pub fn emit_maps(dmb: &mut Dmb, maps: &MapSet) -> Result<(), String> {
    emit_maps_inner(dmb, maps, None)
}

pub fn emit_maps_with_resources(
    dmb: &mut Dmb,
    maps: &MapSet,
    resources: &ResourceSet,
) -> Result<(), String> {
    emit_maps_inner(dmb, maps, Some(resources.inputs.iter()
        .map(|input| (input.archive_name.as_str(), input.named.id, input.named.kind)).collect()))
}

pub fn emit_maps_with_catalog(dmb: &mut Dmb, maps: &MapSet, resources: &dm_resources::ResourceCatalog) -> Result<(), String> {
    emit_maps_inner(dmb, maps, Some(resources.entries.iter()
        .map(|input| (input.archive_name.as_str(), input.id, input.kind)).collect()))
}

fn emit_maps_inner(
    dmb: &mut Dmb,
    maps: &MapSet,
    resources: Option<Vec<(&str, u32, u8)>>,
) -> Result<(), String> {
    if maps.files.is_empty() {
        return Ok(());
    }
    let class_ids: HashMap<String, u32> = dmb
        .classes
        .iter()
        .enumerate()
        .filter_map(|(id, class)| {
            dmb.string(class.path_string_id())
                .map(|path| (String::from_utf8_lossy(path).into_owned(), id as u32))
        })
        .collect();
    let mut resource_ids = HashMap::new();
    if let Some(resources) = resources {
        for (name, resource_id, kind) in resources {
            let id = dmb
                .resources
                .iter()
                .position(|entry| entry.id == resource_id && entry.kind == kind)
                .ok_or_else(|| format!("unattached map resource: {name}"))?;
            resource_ids.insert(name, id as u32);
        }
    }
    let mut instance_ids = HashMap::<(u8, u32, Option<String>), u32>::new();
    for (id, instance) in dmb.instances.iter().enumerate() {
        if instance.initializer == 0xffff {
            instance_ids
                .entry((instance.kind, instance.class, None))
                .or_insert(id as u32);
        }
    }
    let mut cells = HashMap::<(usize, usize, usize), (u32, u32, Vec<u32>)>::new();
    for (path, source) in &maps.files {
        let z_offset = cells.keys().map(|cell| cell.2).max().unwrap_or(0);
        let mut keys = HashMap::<String, (u32, u32, Vec<u32>)>::new();
        for (key, payload) in
            map_templates(source).map_err(|error| format!("{}: {error}", path.display()))?
        {
            let mut turf = None;
            let mut area = None;
            let mut objects = Vec::new();
            for atom in split_top_level(payload, ',').into_iter().map(str::trim) {
                let (atom, assignments) =
                    atom.split_once('{').map_or((atom, None), |(name, tail)| {
                        (
                            name.trim(),
                            Some(tail.strip_suffix('}').ok_or_else(|| {
                                format!("{}: unclosed map initializer", path.display())
                            })),
                        )
                    });
                let assignments = assignments.transpose()?;
                let class = *class_ids
                    .get(atom)
                    .ok_or_else(|| format!("{}: unresolved map type {atom}", path.display()))?;
                let kind = map_instance_kind(dmb, class)
                    .ok_or_else(|| format!("{}: unsupported map type: {atom}", path.display()))?;
                let instance_class = if kind == 8 {
                    dmb.mobs
                        .iter()
                        .position(|mob| mob.class == class)
                        .ok_or_else(|| {
                            format!("{}: map mob has no mob descriptor: {atom}", path.display())
                        })? as u32
                } else {
                    class
                };
                let descriptor = (kind, instance_class, assignments.map(str::to_owned));
                let id = if let Some(id) = instance_ids.get(&descriptor) {
                    *id
                } else {
                    let id = checked_map_instance_id(dmb.instances.len())?;
                    let initializer = if let Some(assignments) = assignments {
                        let code = lower_complex_map_initializer(
                            dmb,
                            assignments,
                            &class_ids,
                            &resource_ids,
                        )?;
                        if dmb.lists.len() == 0xffff {
                            dmb.lists.push(Vec::new());
                        }
                        let code_id = dmb.lists.len() as u32;
                        dmb.lists.push(code);
                        if dmb.lists.len() == 0xffff {
                            dmb.lists.push(Vec::new());
                        }
                        let empty_id = dmb.lists.len() as u32;
                        dmb.lists.push(Vec::new());
                        crate::reserve_proc_sentinel(dmb);
                        let proc_id = dmb.procs.len() as u32;
                        dmb.procs.push(Proc {
                            strings: [0xffff; 4],
                            source_parameter: 255,
                            source_kind: 0,
                            flags: 0,
                            extended_flags: None,
                            code_locals_args: [code_id, empty_id, empty_id],
                        });
                        proc_id
                    } else {
                        0xffff
                    };
                    dmb.instances.push(Instance {
                        kind,
                        class: instance_class,
                        initializer,
                    });
                    instance_ids.insert(descriptor, id);
                    id
                };
                if kind == 10 {
                    turf = Some(id);
                } else if kind == 11 {
                    area = Some(id);
                } else {
                    objects.push(id);
                }
            }
            keys.insert(
                key.into(),
                (
                    turf.map(Ok)
                        .unwrap_or_else(|| default_map_instance(dmb, 10))?,
                    area.map(Ok)
                        .unwrap_or_else(|| default_map_instance(dmb, 11))?,
                    objects,
                ),
            );
        }
        for (axes, text) in
            map_blocks(source).map_err(|error| format!("{}: {error}", path.display()))?
        {
            let rows: Vec<&str> = text.trim().lines().map(str::trim).collect();
            for (row, line) in rows.iter().enumerate() {
                let mut x = axes[0];
                let mut at = 0;
                while at < line.len() {
                    let key = keys
                        .keys()
                        .find(|key| line[at..].starts_with(key.as_str()))
                        .ok_or_else(|| format!("{}: unknown map key", path.display()))?;
                    let cell = keys[key].clone();
                    if cells
                        .insert(
                            (
                                x,
                                axes[1] + rows.len() - 1 - row,
                                axes[2]
                                    .checked_add(z_offset)
                                    .ok_or("map z coordinate overflow")?,
                            ),
                            cell,
                        )
                        .is_some()
                    {
                        return Err(format!("{}: overlapping map cells", path.display()));
                    }
                    x += 1;
                    at += key.len();
                }
            }
        }
    }
    if cells.is_empty() {
        return Err("map files contain no cells".into());
    }
    let maxx = cells
        .keys()
        .map(|cell| cell.0)
        .max()
        .unwrap()
        .max(usize::from(dmb.dimensions[0]));
    let maxy = cells
        .keys()
        .map(|cell| cell.1)
        .max()
        .unwrap()
        .max(usize::from(dmb.dimensions[1]));
    let maxz = cells
        .keys()
        .map(|cell| cell.2)
        .max()
        .unwrap()
        .max(usize::from(dmb.dimensions[2]));
    dmb.dimensions = [maxx, maxy, maxz]
        .map(|value| u16::try_from(value).map_err(|_| "map dimension exceeds 16 bits".to_owned()))
        .into_iter()
        .collect::<Result<Vec<_>, _>>()?
        .try_into()
        .unwrap();
    dmb.grid.clear();
    dmb.map_objects.clear();
    let mut offset = 0usize;
    let mut last_object_position = 0usize;
    let empty_cell = (
        default_map_instance(dmb, 10)?,
        default_map_instance(dmb, 11)?,
        Vec::new(),
    );
    for z in 1..=maxz {
        for y in 1..=maxy {
            for x in 1..=maxx {
                let (turf, area, objects) = cells.get(&(x, y, z)).unwrap_or(&empty_cell);
                if !objects.is_empty() {
                    for (index, instance) in objects.iter().enumerate() {
                        let delta = if index == 0 {
                            offset - last_object_position
                        } else {
                            0
                        };
                        let object_offset =
                            u16::try_from(delta).map_err(|_| "map object gap exceeds 16 bits")?;
                        dmb.map_objects.push(MapObject {
                            offset: object_offset,
                            instance: *instance,
                        });
                    }
                    last_object_position = offset;
                }
                if let Some(last) = dmb.grid.last_mut() {
                    if last.turf == *turf
                        && last.area == *area
                        && last.contents == 0xffff
                        && last.copies < u8::MAX
                    {
                        last.copies += 1;
                        offset += 1;
                        continue;
                    }
                }
                dmb.grid.push(GridRun {
                    turf: *turf,
                    area: *area,
                    contents: 0xffff,
                    copies: 1,
                });
                offset += 1;
            }
        }
    }
    crate::promote_object_ids(dmb);
    dmb.validate_references().map_err(|error| error.to_string())
}

fn map_blocks(source: &str) -> Result<Vec<([usize; 3], &str)>, String> {
    let lexed = dm_syntax::lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err("invalid map tokens".into());
    }
    let tokens = lexed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        })
        .collect::<Vec<_>>();
    let mut blocks = Vec::new();
    for window in tokens.windows(9) {
        if [0, 2, 4, 6, 7]
            .into_iter()
            .zip(["(", ",", ",", ")", "="])
            .any(|(index, text)| window[index].text(source) != text)
        {
            continue;
        }
        if window[8].kind != dm_syntax::TokenKind::String {
            continue;
        }
        let raw = window[8].text(source);
        let Some(text) = raw
            .strip_prefix("{\"")
            .and_then(|text| text.strip_suffix("\"}"))
        else {
            continue;
        };
        let mut axes = [0; 3];
        for (axis, index) in [1, 3, 5].into_iter().enumerate() {
            axes[axis] = window[index]
                .text(source)
                .parse()
                .map_err(|_| "invalid map coordinates")?;
        }
        if axes.contains(&0) {
            return Err("invalid map coordinates".into());
        }
        blocks.push((axes, text));
    }
    Ok(blocks)
}

fn map_templates(source: &str) -> Result<Vec<(&str, &str)>, String> {
    let lexed = dm_syntax::lex_spans(source);
    if let Some(error) = lexed.diagnostics.first() {
        return Err(error.message.clone());
    }
    let tokens: Vec<_> = lexed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        })
        .collect();
    let mut result = Vec::new();
    let mut at = 0;
    while at + 2 < tokens.len() {
        let key = &tokens[at];
        if key.kind != dm_syntax::TokenKind::String
            || tokens[at + 1].text(source) != "="
            || tokens[at + 2].text(source) != "("
        {
            at += 1;
            continue;
        }
        let start = tokens[at + 2].span.end;
        let mut end = at + 3;
        let mut depth = 1usize;
        while end < tokens.len() {
            match tokens[end].text(source) {
                "(" => depth += 1,
                ")" => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                _ => {}
            }
            end += 1;
        }
        if depth != 0 {
            return Err("unclosed map template".into());
        }
        let key_text = key
            .text(source)
            .strip_prefix('"')
            .and_then(|value| value.strip_suffix('"'))
            .ok_or("invalid map template key")?;
        if key_text.is_empty() {
            return Err("empty map template key".into());
        }
        result.push((key_text, &source[start..tokens[end].span.start]));
        at = end + 1;
    }
    Ok(result)
}

fn split_top_level(source: &str, separator: char) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0usize;
    let mut quote = None;
    let mut start = 0;
    let mut escape = false;
    for (at, ch) in source.char_indices() {
        if escape {
            escape = false;
            continue;
        }
        if ch == '\\' && quote.is_some() {
            escape = true;
            continue;
        }
        if let Some(ending) = quote {
            if ch == ending {
                quote = None;
            }
            continue;
        }
        match ch {
            '\'' | '"' => quote = Some(ch),
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => depth = depth.saturating_sub(1),
            _ if ch == separator && depth == 0 => {
                parts.push(&source[start..at]);
                start = at + ch.len_utf8();
            }
            _ => {}
        }
    }
    parts.push(&source[start..]);
    parts
}

fn lower_complex_map_initializer(
    dmb: &mut Dmb,
    assignments: &str,
    class_ids: &HashMap<String, u32>,
    resource_ids: &HashMap<&str, u32>,
) -> Result<Vec<u32>, String> {
    let mut source = String::from("/proc/__map_initializer()\n");
    let mut bindings = LowerBindings::default();
    for part in split_top_level(assignments, ';')
        .into_iter()
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        let (name, _) = part
            .split_once('=')
            .ok_or_else(|| format!("invalid map assignment: {part}"))?;
        bindings.fields.insert(name.trim().into());
        source.push_str("    ");
        source.push_str(part);
        source.push('\n');
    }
    let ast = dm_syntax::parse(&source);
    if !ast.diagnostics.is_empty() {
        return Err(format!("invalid map initializer: {:?}", ast.diagnostics));
    }
    let compiled = compile_simple_proc_with_bindings(&ast.items[0].children, &bindings)
        .map_err(|errors| format!("unsupported map initializer: {errors:?}"))?;
    let mut ledger = Ledger::default();
    for key in &compiled.strings {
        let id = intern_bytes(dmb, compiled.string_bytes(key));
        ledger
            .bind(Symbol::new(Table::String, key), id)
            .map_err(|error| error.to_string())?;
    }
    for path in &compiled.class_paths {
        let builtin = ["/list", "/savefile", "/file", "/client"]
            .iter()
            .any(|base| path == *base || path.starts_with(&format!("{base}/")));
        let id = if builtin {
            0
        } else {
            let class = *class_ids
                .get(path)
                .ok_or_else(|| format!("unresolved map initializer type: {path}"))?;
            if map_instance_kind(dmb, class) == Some(8) {
                dmb.mobs
                    .iter()
                    .position(|mob| mob.class == class)
                    .ok_or_else(|| format!("missing map mob descriptor: {path}"))?
                    as u32
            } else {
                class
            }
        };
        // Type tags give these payloads independent namespaces; aliases may share IDs.
        ledger
            .bind_alias(Symbol::new(Table::Class, path), id)
            .map_err(|error| error.to_string())?;
    }
    for path in &compiled.resources {
        let id = *resource_ids
            .get(path.as_str())
            .ok_or_else(|| format!("unloaded map initializer resource: {path}"))?;
        ledger
            .bind_alias(Symbol::new(Table::Resource, path), id)
            .map_err(|error| error.to_string())?;
    }
    Ok(link_proc(&compiled.code, &ledger)
        .map_err(|error| error.to_string())?
        .words)
}

fn intern_bytes(dmb: &mut Dmb, value: &[u8]) -> u32 {
    if let Some(id) = dmb.strings.iter().enumerate().find_map(|(id, entry)| {
        (!crate::native_reserved_string_id(id as u32) && entry.data == value).then_some(id)
    }) {
        return id as u32;
    }
    while crate::native_reserved_string_id(dmb.strings.len() as u32) {
        dmb.strings.push(DmString {
            data: Vec::new(),
            long_chunks: 0,
        });
    }
    let id = dmb.strings.len() as u32;
    dmb.strings.push(DmString {
        data: value.to_vec(),
        long_chunks: u16::try_from(value.len() / u16::MAX as usize).unwrap_or(u16::MAX),
    });
    id
}

fn checked_map_instance_id(count: usize) -> Result<u32, String> {
    if count >= 0xffff {
        return Err("instance table reaches native unsupported ID 65535".into());
    }
    Ok(count as u32)
}

pub(crate) fn default_map_instance(dmb: &mut Dmb, kind: u8) -> Result<u32, String> {
    let class = if kind == 10 {
        dmb.world.turf_class_id()
    } else {
        dmb.world.area_class_id()
    };
    if let Some(id) = dmb.instances.iter().position(|instance| {
        instance.kind == kind && instance.class == class && instance.initializer == 0xffff
    }) {
        return Ok(id as u32);
    }
    let id = checked_map_instance_id(dmb.instances.len())?;
    dmb.instances.push(Instance {
        kind,
        class,
        initializer: 0xffff,
    });
    Ok(id)
}

fn map_instance_kind(dmb: &Dmb, mut class: u32) -> Option<u8> {
    loop {
        let record = dmb.classes.get(class as usize)?;
        match dmb.string(record.path_string_id())? {
            b"/turf" => return Some(10),
            b"/area" => return Some(11),
            b"/obj" => return Some(9),
            b"/mob" => return Some(8),
            _ => {}
        }
        class = record.parent_class_id();
        if class == 0xffff {
            return None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repeated_map_atoms_share_descriptors_and_initializer_programs() {
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            "/obj/test\n    var/value = 0\n",
            include_bytes!("../../../fixtures/native_template.bin"),
            "intern-map",
        )
        .unwrap();
        let maps=MapSet{files:vec![(PathBuf::from("first.dmm"),"\"a\" = (/obj/test{value=3},/turf,/area)\n\"b\" = (/obj/test{value=3},/turf,/area)\n(1,1,1) = {\"\nab\n\"}".into())],fingerprint:[0;32]};
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(dmb.map_objects.len(), 2);
        assert_eq!(dmb.map_objects[0].instance, dmb.map_objects[1].instance);
        assert_eq!(
            dmb.instances
                .iter()
                .filter(|instance| instance.kind == 11
                    && instance.class == dmb.world.area_class_id()
                    && instance.initializer == 0xffff)
                .count(),
            1,
            "identical area templates must represent a single runtime area"
        );
        dmb.validate_references().unwrap();
    }
    #[test]
    fn map_type_constants_use_tagged_namespaces() {
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            "/mob/map_mob\n    var/value = 7\n",
            include_bytes!("../../../fixtures/native_template.bin"),
            "map_types",
        )
        .unwrap();
        let classes = dmb
            .classes
            .iter()
            .enumerate()
            .map(|(id, class)| {
                (
                    String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap())
                        .into_owned(),
                    id as u32,
                )
            })
            .collect::<HashMap<_, _>>();
        let mob = dmb
            .mobs
            .iter()
            .position(|mob| mob.class == classes["/mob/map_mob"])
            .unwrap() as u32;
        let words = lower_complex_map_initializer(
            &mut dmb,
            "value = list(/mob/map_mob, /datum, /list, /savefile)",
            &classes,
            &HashMap::new(),
        )
        .unwrap();
        let instructions = byond_dmb::bytecode::decode(&words).unwrap();
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == opcode::PUSH_VAL
                && instruction.operands == [8, mob]));
        for tag in [40, 36] {
            assert!(instructions
                .iter()
                .any(|instruction| instruction.opcode == opcode::PUSH_VAL
                    && instruction.operands == [tag, 0]));
        }
    }

    #[test]
    fn multiline_map_float_null_and_escaped_string_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/map_multiline.native.bin"
        ))
        .unwrap();
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            include_str!("../../../fixtures/native_compiler/map_multiline.dm")
                .split("/obj/map_props")
                .nth(1)
                .map(|tail| format!("/obj/map_props{tail}"))
                .unwrap()
                .as_str(),
            include_bytes!("../../../fixtures/native_template.bin"),
            "map_multiline",
        )
        .unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("map_multiline.dmm"),
                include_str!("../../../fixtures/native_compiler/map_multiline.dmm").into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        let code = |world: &Dmb| {
            let instance = &world.instances[world.map_objects[0].instance as usize];
            byond_dmb::bytecode::decode(
                world
                    .proc_code_words(instance.initializer as usize)
                    .unwrap(),
            )
            .unwrap()
        };
        let normalize = |world: &Dmb| {
            code(world)
                .into_iter()
                .map(|instruction| {
                    let mut operands = instruction.operands;
                    let mut string = None;
                    if instruction.opcode == opcode::PUSH_VAL && operands.first() == Some(&6) {
                        string = Some(world.string(operands[1]).unwrap().to_vec());
                        operands[1] = 0;
                    } else if instruction.opcode == opcode::SET_VAR {
                        let last = operands.last_mut().unwrap();
                        string = Some(world.string(*last).unwrap().to_vec());
                        *last = 0;
                    }
                    (instruction.opcode, operands, string)
                })
                .collect::<Vec<_>>()
        };
        let assignments = |world: &Dmb| {
            let instructions = normalize(world);
            let mut pairs = instructions[..instructions.len() - 1]
                .chunks(2)
                .map(|pair| pair.to_vec())
                .collect::<Vec<_>>();
            pairs.sort_by(|a, b| a[1].2.cmp(&b[1].2));
            pairs
        };
        assert_eq!(assignments(&dmb), assignments(&native));
        Dmb::from_bytes(&dmb.to_bytes().unwrap())
            .unwrap()
            .validate_references()
            .unwrap();
    }

    #[test]
    fn active_test_maps_have_valid_multiline_templates_and_assignments() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(4)
            .unwrap();
        let mut checked = 0;
        for entry in fs::read_dir(root.join("maps/virgo_minitest")).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().is_none_or(|ext| ext != "dmm") {
                continue;
            }
            let source = dm_preprocess::read_source_file(&path).unwrap();
            let templates = map_templates(&source).unwrap();
            let blocks = map_blocks(&source).unwrap();
            assert!(!blocks.is_empty(), "{}", path.display());
            let width = templates[0].0.len();
            for (_, text) in blocks {
                for row in text.trim().lines() {
                    assert_eq!(row.trim().len() % width, 0);
                    for key in row.trim().as_bytes().chunks(width) {
                        assert!(templates.iter().any(|(name, _)| name.as_bytes() == key));
                    }
                }
            }
            assert!(!templates.is_empty(), "{}", path.display());
            for (_, payload) in templates {
                for atom in split_top_level(payload, ',') {
                    let Some((_, fields)) = atom.split_once('{') else {
                        continue;
                    };
                    let fields = fields.trim().strip_suffix('}').unwrap();
                    let mut proc = String::from("/proc/map_init()\n");
                    let mut bindings = LowerBindings::default();
                    for part in split_top_level(fields, ';')
                        .into_iter()
                        .map(str::trim)
                        .filter(|part| !part.is_empty())
                    {
                        let (name, _) = part.split_once('=').unwrap();
                        bindings.fields.insert(name.trim().to_owned());
                        proc.push_str("    ");
                        proc.push_str(part);
                        proc.push('\n');
                    }
                    let ast = dm_syntax::parse(&proc);
                    assert!(
                        ast.diagnostics.is_empty(),
                        "{}: {fields}: {:?}",
                        path.display(),
                        ast.diagnostics
                    );
                    let result =
                        compile_simple_proc_with_bindings(&ast.items[0].children, &bindings);
                    assert!(result.is_ok(), "{}: {fields}: {result:?}", path.display());
                    checked += 1;
                }
            }
        }
        assert!(checked > 100);
    }

    #[test]
    fn map_mobs_use_native_mob_descriptors_instead_of_class_ids() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/mob_map.native.bin"
        ))
        .unwrap();
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            include_str!("../../../fixtures/native_compiler/mob_map.dm"),
            include_bytes!("../../../fixtures/native_template.bin"),
            "mob-map",
        )
        .unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("mob_map.dmm"),
                include_str!("../../../fixtures/native_compiler/mob_map.dmm").into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        let actual = &dmb.instances[dmb.map_objects[0].instance as usize];
        let expected = &native.instances[native.map_objects[0].instance as usize];
        assert_eq!(expected.kind, 8);
        assert_eq!(actual.kind, expected.kind);
        let actual_class = &dmb.classes[dmb.mobs[actual.class as usize].class as usize];
        let expected_class = &native.classes[native.mobs[expected.class as usize].class as usize];
        assert_eq!(
            dmb.string(actual_class.path_string_id()),
            native.string(expected_class.path_string_id())
        );
        let actual_code =
            byond_dmb::bytecode::decode(dmb.proc_code_words(actual.initializer as usize).unwrap())
                .unwrap();
        let expected_code = byond_dmb::bytecode::decode(
            native
                .proc_code_words(expected.initializer as usize)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            actual_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>(),
            expected_code
                .iter()
                .map(|ins| ins.opcode)
                .collect::<Vec<_>>()
        );
        let bytes = dmb.to_bytes().unwrap();
        Dmb::from_bytes(&bytes)
            .unwrap()
            .validate_references()
            .unwrap();
    }

    #[test]
    fn map_instances_reject_native_null_id_without_allocating() {
        assert_eq!(checked_map_instance_id(0xfffe).unwrap(), 0xfffe);
        assert!(checked_map_instance_id(0xffff).is_err());
        assert!(checked_map_instance_id(0x10000).is_err());
    }

    #[test]
    fn codegen_accepts_mixed_map_list_initializer() {
        let ast = dm_syntax::parse("/proc/mapinit()\n    values = list(9, \"x\" = 1)\n");
        let mut bindings = dm_codegen_byond::LowerBindings::default();
        bindings.fields.insert("values".into());
        let result =
            dm_codegen_byond::compile_simple_proc_with_bindings(&ast.items[0].children, &bindings);
        assert!(result.is_ok(), "{result:?}");
    }

    #[test]
    fn dmm_mixed_and_assoc_lists_lower() {
        for (name, contents, expected_opcode) in [
            (
                "map_mixed",
                include_str!("../../../fixtures/translation/map_mixed.dmm"),
                0xc8,
            ),
            (
                "map_assoc",
                include_str!("../../../fixtures/translation/map_assoc.dmm"),
                0xc8,
            ),
            (
                "map_list",
                include_str!("../../../fixtures/translation/map_list.dmm"),
                opcode::NEW_LIST,
            ),
        ] {
            let source = format!("/obj/{name}\n    var/values\n");
            let (mut dmb, _) = crate::bootstrap::emit_global_procs(
                &source,
                include_bytes!("../../../fixtures/native_template.bin"),
                name,
            )
            .unwrap();
            let maps = MapSet {
                files: vec![(PathBuf::from(format!("{name}.dmm")), contents.into())],
                fingerprint: [0; 32],
            };
            emit_maps(&mut dmb, &maps).unwrap();
            let instance = &dmb.instances[dmb.map_objects[0].instance as usize];
            let code = byond_dmb::bytecode::decode(
                dmb.proc_code_words(instance.initializer as usize).unwrap(),
            )
            .unwrap();
            assert!(
                code.iter().any(|ins| ins.opcode == expected_opcode),
                "{name}"
            );
        }
    }

    #[test]
    fn one_cell_map_emits_grid_and_instances() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("test.dmm"),
                "\"a\" = (/turf,/area)\n(1,1,1) = {\"a\"}\n".into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(dmb.dimensions, [1, 1, 1]);
        assert_eq!(dmb.grid.len(), 1);
        assert_eq!(dmb.instances[dmb.grid[0].turf as usize].kind, 10);
        assert_eq!(dmb.instances[dmb.grid[0].area as usize].kind, 11);
    }

    #[test]
    fn map_contents_emit_object_offsets() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("test.dmm"),
                "\"a\" = (/obj,/turf,/area)\n(1,1,1) = {\"a\"}\n".into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(dmb.map_objects.len(), 1);
        assert_eq!(dmb.map_objects[0].offset, 0);
        assert_eq!(dmb.instances[dmb.map_objects[0].instance as usize].kind, 9);
    }

    #[test]
    fn object_offsets_are_relative_deltas() {
        let mut dmb =
            Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("test.dmm"),
                "\"a\" = (/obj,/turf,/area)\n(1,1,1) = {\"aaa\"}\n".into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(
            dmb.map_objects
                .iter()
                .map(|object| object.offset)
                .collect::<Vec<_>>(),
            [0, 1, 1]
        );
    }

    #[test]
    fn map_numeric_initializer_matches_native_shape() {
        let source = include_str!("../../../fixtures/translation/map_order.dm");
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/map_order.native.bin"
        ))
        .unwrap();
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            source,
            include_bytes!("../../../fixtures/native_template.bin"),
            "map_order",
        )
        .unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("map_order.dmm"),
                include_str!("../../../fixtures/translation/map_order.dmm").into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(dmb.map_objects.len(), 1);
        let ours = &dmb.instances[dmb.map_objects[0].instance as usize];
        let theirs = &native.instances[native.map_objects[0].instance as usize];
        let our_code =
            byond_dmb::bytecode::decode(dmb.proc_code_words(ours.initializer as usize).unwrap())
                .unwrap();
        let native_code = byond_dmb::bytecode::decode(
            native.proc_code_words(theirs.initializer as usize).unwrap(),
        )
        .unwrap();
        assert_eq!(
            our_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>(),
            native_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>()
        );
        assert_eq!(our_code[0].operands, native_code[0].operands);
        assert_eq!(our_code[2].operands, native_code[2].operands);
    }

    #[test]
    fn map_string_initializer_matches_native_shape() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/cable_numeric_parse/probe.native.bin"
        ))
        .unwrap();
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            "/obj/cable\n/obj/cable/green\n",
            include_bytes!("../../../fixtures/native_template.bin"),
            "cable",
        )
        .unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("probe.dmm"),
                include_str!("../../../fixtures/translation/cable_numeric_parse/probe.dmm").into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        let ours = dmb
            .map_objects
            .iter()
            .map(|object| &dmb.instances[object.instance as usize])
            .find(|instance| instance.initializer != 0xffff)
            .unwrap();
        let theirs = native
            .map_objects
            .iter()
            .map(|object| &native.instances[object.instance as usize])
            .find(|instance| instance.initializer != 0xffff)
            .unwrap();
        let our_code =
            byond_dmb::bytecode::decode(dmb.proc_code_words(ours.initializer as usize).unwrap())
                .unwrap();
        let native_code = byond_dmb::bytecode::decode(
            native.proc_code_words(theirs.initializer as usize).unwrap(),
        )
        .unwrap();
        assert_eq!(
            our_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>(),
            native_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>()
        );
        assert_eq!(
            dmb.string(our_code[0].operands[1]),
            native.string(native_code[0].operands[1])
        );
    }

    #[test]
    fn separate_map_files_stack_local_z_levels() {
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            "",
            include_bytes!("../../../fixtures/native_template.bin"),
            "stacked_maps",
        )
        .unwrap();
        let maps = MapSet {
            files: vec![
                (
                    PathBuf::from("first.dmm"),
                    "\"a\"=(/turf,/area)\n(1,1,1)={\"a\"}".into(),
                ),
                (
                    PathBuf::from("second.dmm"),
                    "\"a\"=(/turf,/area)\n(1,1,1)={\"a\"}".into(),
                ),
            ],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/map_stack.native.bin"
        ))
        .unwrap();
        assert_eq!(dmb.dimensions, native.dimensions);
        assert_eq!(dmb.dimensions, [1, 1, 2]);
        assert_eq!(
            dmb.grid
                .iter()
                .map(|run| usize::from(run.copies))
                .sum::<usize>(),
            2
        );
        dmb.validate_references().unwrap();
        dmb.dimensions = [1, 1, 3];
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(dmb.dimensions, [1, 1, 3]);
        assert_eq!(
            dmb.grid
                .iter()
                .map(|run| usize::from(run.copies))
                .sum::<usize>(),
            3
        );
    }

    #[test]
    fn grid_blocks_ignore_coordinate_text_inside_strings() {
        let source = r#""a"=(/obj{name="(bad) = {\"fake\"}"},/turf,/area)
(2,3,1)={"
a
"}"#;
        let blocks = map_blocks(source).unwrap();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].0, [2, 3, 1]);
        assert_eq!(blocks[0].1.trim(), "a");
    }

    #[test]
    fn map_resource_spellings_may_share_a_table_entry() {
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            "/obj/map_props\n    var/payload\n",
            include_bytes!("../../../fixtures/native_template.bin"),
            "map_resource_alias",
        )
        .unwrap();
        let words = lower_complex_map_initializer(
            &mut dmb,
            "payload = list('tiny.png', 'icons/tiny.png')",
            &HashMap::new(),
            &HashMap::from([("tiny.png", 2323), ("icons/tiny.png", 2323)]),
        )
        .unwrap();
        let instructions = byond_dmb::bytecode::decode(&words).unwrap();
        assert_eq!(
            instructions
                .iter()
                .filter(|instruction| instruction.opcode == opcode::PUSH_VAL
                    && instruction.operands == [12, 2323])
                .count(),
            2
        );
    }

    #[test]
    fn map_resource_initializer_matches_native_shape() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/translation/resource_archive_order");
        let resources = ResourceSet::load(["A.txt", "tiny.png"].into_iter().map(|name| {
            dm_resources::ResourceRequest {
                archive_name: name.into(),
                disk_path: root.join(name),
            }
        }))
        .unwrap();
        let (mut dmb, _, _) = crate::bootstrap::emit_global_procs_with_resources(
            "/turf/test\n    var/asset = null\n",
            include_bytes!("../../../fixtures/native_template.bin"),
            "map",
            &resources,
        )
        .unwrap();
        let maps = MapSet {
            files: vec![(
                root.join("map.dmm"),
                include_str!("../../../fixtures/translation/resource_archive_order/map.dmm").into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps_with_resources(&mut dmb, &maps, &resources).unwrap();
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/resource_archive_order/dms_map.native.bin"
        ))
        .unwrap();
        let ours = dmb
            .instances
            .iter()
            .find(|instance| instance.initializer != 0xffff)
            .unwrap();
        let theirs = native
            .instances
            .iter()
            .find(|instance| instance.initializer != 0xffff)
            .unwrap();
        let our_code =
            byond_dmb::bytecode::decode(dmb.proc_code_words(ours.initializer as usize).unwrap())
                .unwrap();
        let native_code = byond_dmb::bytecode::decode(
            native.proc_code_words(theirs.initializer as usize).unwrap(),
        )
        .unwrap();
        assert_eq!(
            our_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>(),
            native_code.iter().map(|ins| ins.opcode).collect::<Vec<_>>()
        );
        let mut actual: Vec<_> = our_code
            .iter()
            .filter(|ins| ins.opcode == opcode::PUSH_VAL)
            .map(|ins| {
                assert_eq!(ins.operands[0], 12);
                let reference = &dmb.resources[ins.operands[1] as usize];
                (reference.id, reference.kind)
            })
            .collect();
        let mut expected: Vec<_> = native_code
            .iter()
            .filter(|ins| ins.opcode == opcode::PUSH_VAL)
            .map(|ins| {
                let reference = &native.resources[ins.operands[1] as usize];
                (reference.id, reference.kind)
            })
            .collect();
        actual.sort();
        expected.sort();
        assert_eq!(actual, expected);
    }

    #[test]
    fn modified_alias_paths_use_actual_type_ancestry() {
        let source = "/datum/obj_alias\n    parent_type = /obj\n/datum/turf_alias\n    parent_type = /turf\n/datum/area_alias\n    parent_type = /area\n";
        let (mut dmb, _) = crate::bootstrap::emit_global_procs(
            source,
            include_bytes!("../../../fixtures/native_template.bin"),
            "aliases",
        )
        .unwrap();
        let maps = MapSet {
            files: vec![(
                PathBuf::from("alias.dmm"),
                include_str!("../../../fixtures/translation/type_category_alias.dmm").into(),
            )],
            fingerprint: [0; 32],
        };
        emit_maps(&mut dmb, &maps).unwrap();
        assert_eq!(dmb.map_objects.len(), 1);
        assert_eq!(dmb.instances[dmb.grid[0].turf as usize].kind, 10);
        assert_eq!(dmb.instances[dmb.grid[0].area as usize].kind, 11);
        assert_ne!(
            dmb.instances[dmb.map_objects[0].instance as usize].initializer,
            0xffff
        );
    }

    #[test]
    fn bounded_map_reads_keep_manifest_order_and_remove_duplicates() {
        let base = std::env::temp_dir().join(format!("dm-map-order-{}", std::process::id()));
        fs::create_dir_all(&base).unwrap();
        let manifest = base.join("test.dme");
        fs::write(&manifest, "").unwrap();
        for (name, source) in [
            ("first.dmm", "first"),
            ("second.dmm", "second"),
            ("third.dmm", "third"),
        ] {
            fs::write(base.join(name), source).unwrap();
        }
        let paths: Vec<_> = ["second.dmm", "first.dmm", "second.dmm", "third.dmm"]
            .into_iter()
            .map(PathBuf::from)
            .collect();
        let maps = load_map_set_from_paths(&manifest, &paths).unwrap();
        assert_eq!(
            maps.files
                .iter()
                .map(|(_, text)| text.as_str())
                .collect::<Vec<_>>(),
            ["second", "first", "third"]
        );
        let missing = load_map_set_from_paths(&manifest, &[PathBuf::from("missing.dmm")]);
        assert!(matches!(missing, Err(error) if error.contains("missing.dmm")));
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn map_fingerprint_is_content_based_across_roots() {
        let base = std::env::temp_dir().join(format!("dm-map-fingerprint-{}", std::process::id()));
        let first = base.join("first");
        let second = base.join("second");
        for root in [&first, &second] {
            fs::create_dir_all(root).unwrap();
            fs::write(root.join("test.dme"), "#include \"map.dmm\"\n").unwrap();
            fs::write(
                root.join("map.dmm"),
                "\"a\" = (/turf,/area)\n(1,1,1) = {\"a\"}\n",
            )
            .unwrap();
        }
        let a = load_map_set(&first.join("test.dme")).unwrap().fingerprint;
        let b = load_map_set(&second.join("test.dme")).unwrap().fingerprint;
        assert_eq!(a, b);
        fs::write(second.join("map.dmm"), "changed").unwrap();
        assert_ne!(
            a,
            load_map_set(&second.join("test.dme")).unwrap().fingerprint
        );
        fs::remove_dir_all(base).unwrap();
    }
}
