use byond_dmb::compare::{compare_dmbs, CompareOptions};
use byond_dmb::dmb::Dmb;
use byond_dmb::od_emit::{
    emit_diagnostic_hashed_with_baseline_named, emit_diagnostic_with_baseline_named,
};
use byond_dmb::opendream::OpenDreamProgram;
use std::collections::HashMap;
use std::collections::HashSet;
use std::io::BufReader;
use std::path::Path;

type DefaultNames = (HashSet<Vec<u8>>, HashSet<Vec<u8>>);

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let program = OpenDreamProgram::from_path(&args[1]).unwrap();
    let baseline = OpenDreamProgram::from_path(&args[2]).unwrap();
    let template = Dmb::from_bytes(&std::fs::read(&args[3]).unwrap()).unwrap();
    let reference = Dmb::from_bytes(&std::fs::read(&args[4]).unwrap()).unwrap();
    let emitter = if std::env::var_os("DMB_AUDIT_HASH_RESOURCES").is_some() {
        emit_diagnostic_hashed_with_baseline_named
    } else {
        emit_diagnostic_with_baseline_named
    };
    let emission = emitter(
        &program,
        Some(&baseline),
        &template,
        Path::new(&args[5]),
        Some("deepquarry-static-ref"),
    )
    .unwrap();
    let emitted = emission.dmb;
    if std::env::var_os("DMB_AUDIT_HASH_RESOURCES").is_some() {
        let native_resources: HashSet<_> = reference
            .resources
            .iter()
            .map(|entry| (entry.kind, entry.id))
            .collect();
        let emitted_resources: HashSet<_> = emitted
            .resources
            .iter()
            .map(|entry| (entry.kind, entry.id))
            .collect();
        println!(
            "resource identity native={} emitted={} native-only={} emitted-only={}",
            native_resources.len(),
            emitted_resources.len(),
            native_resources.difference(&emitted_resources).count(),
            emitted_resources.difference(&native_resources).count()
        );
        let native_only: HashSet<_> = native_resources
            .difference(&emitted_resources)
            .copied()
            .collect();
        let emitted_only: HashSet<_> = emitted_resources
            .difference(&native_resources)
            .copied()
            .collect();
        let archive_path = Path::new(&args[4]).with_extension("rsc");
        let mut archive = BufReader::new(std::fs::File::open(archive_path).unwrap());
        while let Some(entry) = byond_dmb::rsc::read_entry(&mut archive).unwrap() {
            if let byond_dmb::rsc::Entry::Named(named) = entry {
                if native_only.contains(&(named.kind, named.id)) {
                    println!(
                        "native-only resource kind={} id={:08x} name={}",
                        named.kind,
                        named.id,
                        String::from_utf8_lossy(&named.name)
                    );
                }
            }
        }
        for (index, path) in program.resources.iter().enumerate() {
            let id = emission.ids.resources[index] as usize;
            let entry = &emitted.resources[id];
            if emitted_only.contains(&(entry.kind, entry.id)) {
                println!(
                    "emitted-only resource kind={} id={:08x} name={path}",
                    entry.kind, entry.id
                );
            }
        }
    }
    for (label, dmb) in [("native", &reference), ("emitted", &emitted)] {
        let var_markers: HashSet<u32> = dmb
            .variables
            .iter()
            .filter(|v| v.kind == 62)
            .map(|v| v.value)
            .collect();
        let class_markers: Vec<u32> = (0..dmb.classes.len())
            .flat_map(|id| dmb.class_initial_values(id).unwrap_or_default())
            .filter(|v| v.value.tag() == 62)
            .map(|v| v.value.id())
            .collect();
        let class_marker_set: HashSet<u32> = class_markers.iter().copied().collect();
        println!(
            "{label}: var62={} class62={} unique={} max={:?} overlap={}",
            var_markers.len(),
            class_markers.len(),
            class_marker_set.len(),
            class_marker_set.iter().max(),
            var_markers.intersection(&class_marker_set).count()
        );
        let declared: HashSet<u32> = (0..dmb.classes.len())
            .flat_map(|id| dmb.class_variable_declarations(id).unwrap_or_default())
            .map(|(id, _)| id)
            .collect();
        let global: HashSet<u32> = if dmb.variable_footer != 0xffff {
            dmb.lists[dmb.variable_footer as usize]
                .chunks_exact(2)
                .map(|pair| pair[0])
                .collect()
        } else {
            HashSet::new()
        };
        let marker_ids: HashSet<u32> = dmb
            .variables
            .iter()
            .enumerate()
            .filter(|(_, v)| v.kind == 62)
            .map(|(id, _)| id as u32)
            .collect();
        println!(
            "{label}: var62 declaration={} global={} neither={}",
            marker_ids.intersection(&declared).count(),
            marker_ids.intersection(&global).count(),
            marker_ids
                .iter()
                .filter(|id| !declared.contains(id) && !global.contains(id))
                .count()
        );
        println!("{label}: classes={} mobs={} procs={} vars={} instances={} resources={} lists={} strings={} map={:?} world name={:?}",
            dmb.classes.len(),dmb.mobs.len(),dmb.procs.len(),dmb.variables.len(),dmb.instances.len(),
            dmb.resources.len(),dmb.lists.len(),dmb.strings.len(),dmb.dimensions,
            dmb.string(dmb.world.ids[6]).map(String::from_utf8_lossy));
        let anonymous = dmb
            .procs
            .iter()
            .filter(|proc| proc.strings[0] == 0xffff)
            .count();
        let init = dmb
            .procs
            .iter()
            .filter(|proc| {
                proc.strings[0] != 0xffff
                    && dmb
                        .string(proc.strings[0])
                        .is_some_and(|s| s.ends_with(b"::<init>"))
            })
            .count();
        let world_global = dmb
            .procs
            .iter()
            .filter(|proc| {
                proc.strings[0] != 0xffff
                    && dmb
                        .string(proc.strings[0])
                        .is_some_and(|s| s.ends_with(b"::<global-init>"))
            })
            .count();
        println!(
            "{label}: anonymous procs={anonymous} class init={init} global init={world_global}"
        );
        let sent16 = dmb
            .procs
            .iter()
            .filter(|proc| proc.strings[0] == 0xffff)
            .count();
        let sent32 = dmb
            .procs
            .iter()
            .filter(|proc| proc.strings[0] == u32::MAX)
            .count();
        println!("{label}: proc path sentinel 16={sent16} 32={sent32}");
        let class_init: HashSet<_> = dmb
            .classes
            .iter()
            .map(|c| c.initializer_proc_id())
            .filter(|&id| id != 0xffff)
            .collect();
        let instance_init: HashSet<_> = dmb
            .instances
            .iter()
            .map(|i| i.initializer)
            .filter(|&id| id != 0xffff)
            .collect();
        let uncategorized = dmb
            .procs
            .iter()
            .enumerate()
            .filter(|(id, p)| {
                p.strings[0] == 0xffff
                    && !class_init.contains(&(*id as u32))
                    && !instance_init.contains(&(*id as u32))
            })
            .count();
        println!(
            "{label}: class init={} instance init={} uncategorized anonymous={}",
            class_init.len(),
            instance_init.len(),
            uncategorized
        );
        let mut init_uses = HashMap::<u32, HashSet<u32>>::new();
        for i in &dmb.instances {
            if i.initializer != 0xffff {
                init_uses.entry(i.initializer).or_default().insert(i.class);
            }
        }
        println!(
            "{label}: initializer procedures used by multiple classes={}",
            init_uses
                .values()
                .filter(|classes| classes.len() > 1)
                .count()
        );
    }
    let paths = |dmb: &Dmb| -> HashSet<Vec<u8>> {
        dmb.classes
            .iter()
            .filter_map(|class| dmb.string(class.path_string_id()).map(|p| p.to_vec()))
            .collect()
    };
    let n = paths(&reference);
    let e = paths(&emitted);
    let defaults_by_path = |dmb: &Dmb| -> HashMap<Vec<u8>, DefaultNames> {
        let mut result = HashMap::new();
        for (id, class) in dmb.classes.iter().enumerate() {
            if let Some(path) = dmb.string(class.path_string_id()) {
                let builtins = dmb
                    .class_builtin_overrides(id)
                    .unwrap_or_default()
                    .iter()
                    .filter_map(|v| dmb.string(v.name_string_id).map(|s| s.to_vec()))
                    .collect();
                let initial = dmb
                    .class_initial_values(id)
                    .unwrap_or_default()
                    .iter()
                    .filter_map(|v| dmb.variables.get(v.variable_id as usize))
                    .filter_map(|v| dmb.string(v.name).map(|s| s.to_vec()))
                    .collect();
                result.insert(path.to_vec(), (builtins, initial));
            }
        }
        result
    };
    let nd = defaults_by_path(&reference);
    let ed = defaults_by_path(&emitted);
    let emitted_classes: HashMap<Vec<u8>, usize> = emitted
        .classes
        .iter()
        .enumerate()
        .filter_map(|(id, class)| {
            emitted
                .string(class.path_string_id())
                .map(|path| (path.to_vec(), id))
        })
        .collect();
    let mut marker_values = HashMap::<Option<u8>, usize>::new();
    let od_types: HashMap<&str, usize> = program
        .types
        .iter()
        .enumerate()
        .map(|(id, typ)| (typ.path.as_str(), id))
        .collect();
    let mut marker_assignments = HashMap::<bool, usize>::new();
    let mut marker_explicit = HashMap::<bool, usize>::new();
    let mut marker_od_values = HashMap::<String, usize>::new();
    let mut native_marker_pairs = HashMap::<(Vec<u8>, Vec<u8>), usize>::new();
    for (native_id, class) in reference.classes.iter().enumerate() {
        let Some(path) = reference.string(class.path_string_id()) else {
            continue;
        };
        let Some(&emitted_id) = emitted_classes.get(path) else {
            continue;
        };
        let actual = emitted.class_initial_values(emitted_id).unwrap_or_default();
        for expected in reference
            .class_initial_values(native_id)
            .unwrap_or_default()
        {
            if expected.value.tag() != 62 {
                continue;
            }
            let Some(name) =
                reference.string(reference.variables[expected.variable_id as usize].name)
            else {
                continue;
            };
            *native_marker_pairs
                .entry((path.to_vec(), name.to_vec()))
                .or_default() += 1;
            let tag = actual
                .iter()
                .find(|entry| {
                    emitted.string(emitted.variables[entry.variable_id as usize].name) == Some(name)
                })
                .map(|entry| entry.value.tag());
            *marker_values.entry(tag).or_default() += 1;
            let assigned = std::str::from_utf8(path)
                .ok()
                .and_then(|p| od_types.get(p))
                .and_then(|id| program.types[*id].init_proc)
                .and_then(|id| program.procs.get(id))
                .and_then(|proc| proc.bytecode.as_deref())
                .is_some_and(|code| {
                    code.windows(6).any(|bytes| {
                        bytes[0..2] == [0x85, 0x0d]
                            && program
                                .strings
                                .get(u32::from_le_bytes(bytes[2..6].try_into().unwrap()) as usize)
                                .is_some_and(|s| s.as_bytes() == name)
                    })
                });
            *marker_assignments.entry(assigned).or_default() += 1;
            let explicit = std::str::from_utf8(path)
                .ok()
                .and_then(|p| od_types.get(p))
                .is_some_and(|id| {
                    program.types[*id]
                        .explicit_type_fields
                        .iter()
                        .any(|field| field.as_bytes() == name)
                });
            *marker_explicit.entry(explicit).or_default() += 1;
            if let Some(&od_id) = std::str::from_utf8(path).ok().and_then(|p| od_types.get(p)) {
                let category = std::str::from_utf8(name)
                    .ok()
                    .and_then(|n| program.types[od_id].variables.get(n))
                    .map(|v| {
                        if v.is_null() {
                            "null"
                        } else if v.is_object() {
                            "object"
                        } else if v.is_string() {
                            "string"
                        } else {
                            "number"
                        }
                    })
                    .unwrap_or("absent");
                *marker_od_values.entry(category.into()).or_default() += 1;
            }
        }
    }
    println!("native class tag62 emitted corresponding tags={marker_values:?}");
    println!("native class tag62 OD own initializer assignment={marker_assignments:?}");
    println!("native class tag62 OD explicit type field={marker_explicit:?}");
    println!("native class tag62 OD value categories={marker_od_values:?}");
    let mut emitted_marker_pairs = HashMap::<(Vec<u8>, Vec<u8>), usize>::new();
    for (class_id, class) in emitted.classes.iter().enumerate() {
        let Some(path) = emitted.string(class.path_string_id()) else {
            continue;
        };
        for entry in emitted.class_initial_values(class_id).unwrap_or_default() {
            if entry.value.tag() == 62 {
                if let Some(name) =
                    emitted.string(emitted.variables[entry.variable_id as usize].name)
                {
                    *emitted_marker_pairs
                        .entry((path.to_vec(), name.to_vec()))
                        .or_default() += 1;
                }
            }
        }
    }
    let marker_count_differences: Vec<_> = native_marker_pairs
        .iter()
        .filter_map(|((path, name), &count)| {
            let actual = emitted_marker_pairs
                .get(&(path.clone(), name.clone()))
                .copied()
                .unwrap_or(0);
            (count != actual).then(|| {
                (
                    String::from_utf8_lossy(path).into_owned(),
                    String::from_utf8_lossy(name).into_owned(),
                    count,
                    actual,
                )
            })
        })
        .collect();
    println!("class marker path/name count differences={marker_count_differences:?}");
    let declaration_markers = |dmb: &Dmb| {
        let mut markers = HashMap::<(Vec<u8>, Vec<u8>), usize>::new();
        for (class_id, class) in dmb.classes.iter().enumerate() {
            let Some(path) = dmb.string(class.path_string_id()) else {
                continue;
            };
            for (variable_id, _) in dmb
                .class_variable_declarations(class_id)
                .unwrap_or_default()
            {
                let variable = &dmb.variables[variable_id as usize];
                if variable.kind == 62 {
                    if let Some(name) = dmb.string(variable.name) {
                        *markers.entry((path.to_vec(), name.to_vec())).or_default() += 1;
                    }
                }
            }
        }
        markers
    };
    let native_declarations = declaration_markers(&reference);
    let emitted_declarations = declaration_markers(&emitted);
    let mut declaration_differences: Vec<_> = native_declarations
        .keys()
        .chain(emitted_declarations.keys())
        .collect::<HashSet<_>>()
        .into_iter()
        .filter_map(|key| {
            let expected = native_declarations.get(key).copied().unwrap_or(0);
            let actual = emitted_declarations.get(key).copied().unwrap_or(0);
            (expected != actual).then(|| {
                (
                    String::from_utf8_lossy(&key.0).into_owned(),
                    String::from_utf8_lossy(&key.1).into_owned(),
                    expected,
                    actual,
                )
            })
        })
        .collect();
    declaration_differences.sort();
    println!(
        "declaration marker path/name count differences={} all={declaration_differences:?}",
        declaration_differences.len()
    );
    let mut declaration_kind_differences = HashMap::<(String, usize, usize), usize>::new();
    for (path, name, expected, actual) in &declaration_differences {
        let kind = od_types
            .get(path.as_str())
            .and_then(|id| program.types[*id].initializer_value_kinds.get(name))
            .cloned()
            .unwrap_or_else(|| "missing".into());
        *declaration_kind_differences
            .entry((kind, *expected, *actual))
            .or_default() += 1;
    }
    println!("declaration marker mismatch expression kinds={declaration_kind_differences:?}");
    let global_markers = |dmb: &Dmb| {
        let mut names = HashMap::<Vec<u8>, usize>::new();
        if dmb.variable_footer != 0xffff {
            for pair in dmb.lists[dmb.variable_footer as usize].chunks_exact(2) {
                let variable = &dmb.variables[pair[0] as usize];
                if variable.kind == 62 {
                    if let Some(name) = dmb.string(variable.name) {
                        *names.entry(name.to_vec()).or_default() += 1;
                    }
                }
            }
        }
        names
    };
    let native_globals = global_markers(&reference);
    let emitted_globals = global_markers(&emitted);
    let mut global_marker_differences: Vec<_> = native_globals
        .keys()
        .chain(emitted_globals.keys())
        .collect::<HashSet<_>>()
        .into_iter()
        .filter_map(|key| {
            let expected = native_globals.get(key).copied().unwrap_or(0);
            let actual = emitted_globals.get(key).copied().unwrap_or(0);
            (expected != actual)
                .then(|| (String::from_utf8_lossy(key).into_owned(), expected, actual))
        })
        .collect();
    global_marker_differences.sort();
    println!(
        "global marker name count differences={} examples={:?}",
        global_marker_differences.len(),
        global_marker_differences
            .iter()
            .take(60)
            .collect::<Vec<_>>()
    );
    for (name, _, _) in &global_marker_differences {
        let variable_records = |dmb: &Dmb| {
            dmb.lists[dmb.variable_footer as usize]
                .chunks_exact(2)
                .filter_map(|pair| {
                    let id = pair[0] as usize;
                    let var = &dmb.variables[id];
                    (dmb.string(var.name) == Some(name.as_bytes()))
                        .then_some((id, var.kind, pair[1]))
                })
                .collect::<Vec<_>>()
        };
        println!(
            "global marker detail {name}: native={:?} emitted={:?}",
            variable_records(&reference),
            variable_records(&emitted)
        );
    }
    let duplicates: Vec<_> = native_marker_pairs
        .iter()
        .filter(|(_, count)| **count > 1)
        .take(15)
        .map(|((path, name), count)| {
            (
                String::from_utf8_lossy(path).into_owned(),
                String::from_utf8_lossy(name).into_owned(),
                *count,
            )
        })
        .collect();
    println!(
        "native class tag62 repeated path/name groups={} examples={duplicates:?}",
        native_marker_pairs
            .values()
            .filter(|&&count| count > 1)
            .count()
    );
    let native_classes: HashMap<Vec<u8>, usize> = reference
        .classes
        .iter()
        .enumerate()
        .filter_map(|(id, class)| {
            reference
                .string(class.path_string_id())
                .map(|path| (path.to_vec(), id))
        })
        .collect();
    let mut dynamic_candidates = HashMap::<(bool, bool), usize>::new();
    let mut false_dynamic_examples = Vec::new();
    let mut dynamic_prefixes = HashMap::<(bool, u8), usize>::new();
    let mut dynamic_last_null = HashMap::<(bool, bool), usize>::new();
    let mut false_nonnull_examples = Vec::new();
    let mut dynamic_last_opcode_hint = HashMap::<(bool, u8), usize>::new();
    let mut optimized_list_examples = Vec::new();
    for typ in &program.types {
        let Some(&class_id) = native_classes.get(typ.path.as_bytes()) else {
            continue;
        };
        let Some(code) = typ
            .init_proc
            .and_then(|id| program.procs.get(id))
            .and_then(|p| p.bytecode.as_deref())
        else {
            continue;
        };
        for name in &typ.explicit_type_fields {
            if typ.variables.get(name).is_none_or(|value| !value.is_null()) {
                continue;
            }
            if !code.windows(6).any(|bytes| {
                bytes[0..2] == [0x85, 0x0d]
                    && program
                        .strings
                        .get(u32::from_le_bytes(bytes[2..6].try_into().unwrap()) as usize)
                        == Some(name)
            }) {
                continue;
            }
            let matched = reference
                .class_initial_values(class_id)
                .unwrap_or_default()
                .iter()
                .any(|entry| {
                    entry.value.tag() == 62
                        && reference.string(reference.variables[entry.variable_id as usize].name)
                            == Some(name.as_bytes())
                });
            let existing = emitted_classes.get(typ.path.as_bytes()).is_some_and(|&id| {
                emitted
                    .class_initial_values(id)
                    .unwrap_or_default()
                    .iter()
                    .any(|entry| {
                        emitted.string(emitted.variables[entry.variable_id as usize].name)
                            == Some(name.as_bytes())
                    })
            });
            *dynamic_candidates.entry((matched, existing)).or_default() += 1;
            *dynamic_prefixes
                .entry((matched, *code.get(7).unwrap_or(&0)))
                .or_default() += 1;
            let final_push_null = code
                .windows(6)
                .enumerate()
                .rfind(|(_, bytes)| {
                    bytes[0..2] == [0x85, 0x0d]
                        && program
                            .strings
                            .get(u32::from_le_bytes(bytes[2..6].try_into().unwrap()) as usize)
                            == Some(name)
                })
                .is_some_and(|(at, _)| at > 0 && code[at - 1] == 0x11);
            if let Some((at, _)) = code.windows(6).enumerate().rfind(|(_, bytes)| {
                bytes[0..2] == [0x85, 0x0d]
                    && program
                        .strings
                        .get(u32::from_le_bytes(bytes[2..6].try_into().unwrap()) as usize)
                        == Some(name)
            }) {
                *dynamic_last_opcode_hint
                    .entry((matched, *code.get(at.saturating_sub(5)).unwrap_or(&0)))
                    .or_default() += 1;
                if matched
                    && code.get(at.saturating_sub(5)) == Some(&0)
                    && optimized_list_examples.len() < 12
                {
                    optimized_list_examples.push((
                        typ.path.clone(),
                        name.clone(),
                        code[at.saturating_sub(24)..at].to_vec(),
                    ));
                }
            }
            *dynamic_last_null
                .entry((matched, final_push_null))
                .or_default() += 1;
            if !matched && !final_push_null && false_nonnull_examples.len() < 30 {
                false_nonnull_examples.push((typ.path.clone(), name.clone(), code.len()));
            }
            if !matched && false_dynamic_examples.len() < 18 {
                false_dynamic_examples.push((typ.path.clone(), name.clone(), existing));
            }
        }
    }
    println!("OD dynamic explicit null assignment native tag62 match={dynamic_candidates:?}");
    println!("OD dynamic false examples={false_dynamic_examples:?}");
    let mut dynamic_prefixes: Vec<_> = dynamic_prefixes.into_iter().collect();
    dynamic_prefixes.sort_by_key(|(_, count)| std::cmp::Reverse(*count));
    println!(
        "OD dynamic prefixes top={:?}",
        dynamic_prefixes.iter().take(20).collect::<Vec<_>>()
    );
    println!("OD dynamic final PushNull={dynamic_last_null:?}");
    let mut dynamic_last_opcode_hint: Vec<_> = dynamic_last_opcode_hint.into_iter().collect();
    dynamic_last_opcode_hint.sort_by_key(|(_, count)| std::cmp::Reverse(*count));
    println!(
        "OD dynamic last at-5 hints={:?}",
        dynamic_last_opcode_hint.iter().take(25).collect::<Vec<_>>()
    );
    println!("OD optimized list examples={optimized_list_examples:?}");
    println!("OD dynamic false nonnull={false_nonnull_examples:?}");
    let mut builtin_mismatch = 0;
    let mut initial_mismatch = 0;
    for (path, (nb, ni)) in &nd {
        if let Some((eb, ei)) = ed.get(path) {
            builtin_mismatch += usize::from(nb != eb);
            initial_mismatch += usize::from(ni != ei);
        }
    }
    println!("common classes with builtin-name mismatch={builtin_mismatch}, initialized-variable-name mismatch={initial_mismatch}");
    let mut shown = 0;
    for (path, (nb, _)) in &nd {
        if let Some((eb, _)) = ed.get(path) {
            if nb != eb && shown < 12 {
                println!(
                    "builtin-name mismatch {} native-only={:?} emitted-only={:?}",
                    String::from_utf8_lossy(path),
                    nb.difference(eb)
                        .map(|s| String::from_utf8_lossy(s).into_owned())
                        .collect::<Vec<_>>(),
                    eb.difference(nb)
                        .map(|s| String::from_utf8_lossy(s).into_owned())
                        .collect::<Vec<_>>()
                );
                shown += 1;
            }
        }
    }
    let mut native_only = HashMap::<String, usize>::new();
    let mut emitted_only = HashMap::<String, usize>::new();
    for (path, (nb, _)) in &nd {
        if let Some((eb, _)) = ed.get(path) {
            for name in nb.difference(eb) {
                *native_only
                    .entry(String::from_utf8_lossy(name).into_owned())
                    .or_default() += 1;
            }
            for name in eb.difference(nb) {
                *emitted_only
                    .entry(String::from_utf8_lossy(name).into_owned())
                    .or_default() += 1;
            }
        }
    }
    let mut native_names: Vec<_> = native_only.into_iter().collect();
    native_names.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    let mut emitted_names: Vec<_> = emitted_only.into_iter().collect();
    emitted_names.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    println!(
        "builtin native-only top={:?}",
        native_names.iter().take(15).collect::<Vec<_>>()
    );
    println!(
        "builtin emitted-only top={:?}",
        emitted_names.iter().take(15).collect::<Vec<_>>()
    );
    for (path, (nb, ni)) in &nd {
        if let Some((eb, ei)) = ed.get(path) {
            if ni != ei {
                println!(
                    "initial-name mismatch {} native-only={:?} emitted-only={:?}",
                    String::from_utf8_lossy(path),
                    ni.difference(ei)
                        .map(|s| String::from_utf8_lossy(s).into_owned())
                        .collect::<Vec<_>>(),
                    ei.difference(ni)
                        .map(|s| String::from_utf8_lossy(s).into_owned())
                        .collect::<Vec<_>>()
                );
            }
            let _ = (nb, eb);
        }
    }
    println!(
        "extra classes={} missing={}",
        e.difference(&n).count(),
        n.difference(&e).count()
    );
    for p in e.difference(&n).take(12) {
        println!("extra {:?}", String::from_utf8_lossy(p));
    }
    for p in n.difference(&e).take(12) {
        println!("missing {:?}", String::from_utf8_lossy(p));
    }
    let proc_counts = |dmb: &Dmb| -> HashMap<Vec<u8>, usize> {
        let mut counts = HashMap::new();
        for proc in &dmb.procs {
            if proc.strings[0] != 0xffff {
                if let Some(path) = dmb.string(proc.strings[0]) {
                    *counts.entry(path.to_vec()).or_default() += 1;
                }
            }
        }
        counts
    };
    let np = proc_counts(&reference);
    let ep = proc_counts(&emitted);
    let mut differences: Vec<_> = ep
        .iter()
        .filter_map(|(path, &count)| {
            let native = np.get(path).copied().unwrap_or(0);
            (count != native).then_some((
                count as isize - native as isize,
                String::from_utf8_lossy(path).into_owned(),
            ))
        })
        .collect();
    differences.sort_by_key(|item| std::cmp::Reverse(item.0));
    println!(
        "proc differing paths={} top excess={:?}",
        differences.len(),
        differences.iter().take(20).collect::<Vec<_>>()
    );
    println!(
        "proc native-only paths={}",
        np.keys().filter(|p| !ep.contains_key(*p)).count()
    );
    let init_paths = |dmb: &Dmb| -> HashSet<Vec<u8>> {
        dmb.classes
            .iter()
            .filter(|c| c.initializer_proc_id() != 0xffff)
            .filter_map(|c| dmb.string(c.path_string_id()).map(|s| s.to_vec()))
            .collect()
    };
    let ni = init_paths(&reference);
    let ei = init_paths(&emitted);
    println!(
        "class init extra={} missing={}",
        ei.difference(&ni).count(),
        ni.difference(&ei).count()
    );
    for p in ei.difference(&ni).take(12) {
        println!("extra class init {:?}", String::from_utf8_lossy(p));
    }
    for p in ni.difference(&ei).take(12) {
        println!("missing class init {:?}", String::from_utf8_lossy(p));
    }
    let instance_counts = |dmb: &Dmb| -> HashMap<(u8, Vec<u8>, bool), usize> {
        let mut counts = HashMap::new();
        for i in &dmb.instances {
            let class = if i.kind == 8 {
                dmb.mobs.get(i.class as usize).map(|m| m.class)
            } else {
                Some(i.class)
            };
            let path = class
                .and_then(|id| dmb.classes.get(id as usize))
                .and_then(|c| dmb.string(c.path_string_id()))
                .unwrap_or(b"?")
                .to_vec();
            *counts
                .entry((i.kind, path, i.initializer != 0xffff))
                .or_default() += 1;
        }
        counts
    };
    let nin = instance_counts(&reference);
    let ein = instance_counts(&emitted);
    let mut ind: Vec<_> = ein
        .keys()
        .chain(nin.keys())
        .collect::<HashSet<_>>()
        .into_iter()
        .filter_map(|key| {
            let count = ein.get(key).copied().unwrap_or(0);
            let n = nin.get(key).copied().unwrap_or(0);
            (count != n).then_some((count as isize - n as isize, key.clone()))
        })
        .collect();
    ind.sort_by_key(|item| std::cmp::Reverse(item.0));
    println!("instance differing signatures={}", ind.len());
    let mut instance_groups = HashMap::<(u8, bool), (usize, usize)>::new();
    for (delta, (kind, _, init)) in &ind {
        let entry = instance_groups.entry((*kind, *init)).or_default();
        if *delta > 0 {
            entry.0 += *delta as usize;
        } else {
            entry.1 += (-*delta) as usize;
        }
    }
    println!("instance differing totals (extra,missing)={instance_groups:?}");
    let referenced_signature_counts = |dmb: &Dmb| {
        let mut result = HashMap::<(u8, Vec<u8>, bool), usize>::new();
        for object in &dmb.map_objects {
            let Some(instance) = dmb.instances.get(object.instance as usize) else {
                continue;
            };
            let class = if instance.kind == 8 {
                dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
            } else {
                Some(instance.class)
            };
            let Some(path) = class
                .and_then(|id| dmb.classes.get(id as usize))
                .and_then(|class| dmb.string(class.path_string_id()))
            else {
                continue;
            };
            *result
                .entry((instance.kind, path.to_vec(), instance.initializer != 0xffff))
                .or_default() += 1;
        }
        result
    };
    let native_ref = referenced_signature_counts(&reference);
    let emitted_ref = referenced_signature_counts(&emitted);
    let mut ref_gap = 0usize;
    for (_, key) in &ind {
        let n = native_ref.get(key).copied().unwrap_or(0);
        let e = emitted_ref.get(key).copied().unwrap_or(0);
        if n != e {
            ref_gap += 1;
        }
    }
    println!("instance differing signatures with map-object reference count mismatch={ref_gap}");
    let override_sequences = |dmb: &Dmb, path: &[u8]| {
        dmb.instances
            .iter()
            .filter_map(|instance| {
                let class = dmb.classes.get(instance.class as usize)?;
                if dmb.string(class.path_string_id()) == Some(path)
                    && instance.initializer != 0xffff
                {
                    Some({
                        dmb.lists
                            [dmb.procs[instance.initializer as usize].code_locals_args[0] as usize]
                            .windows(4)
                            .filter(|w| w[..3] == [0x34, 0xffdc, 0xffce])
                            .map(|w| {
                                String::from_utf8_lossy(dmb.string(w[3]).unwrap_or_default())
                                    .into_owned()
                            })
                            .collect::<Vec<_>>()
                    })
                } else {
                    None
                }
            })
            .take(3)
            .collect::<Vec<_>>()
    };
    println!(
        "map override sequences bluegrid native={:?} emitted={:?}",
        override_sequences(&reference, b"/turf/simulated/floor/bluegrid"),
        override_sequences(&emitted, b"/turf/simulated/floor/bluegrid")
    );
    for path in [
        b"/obj/machinery/door/airlock/external".as_slice(),
        b"/obj/machinery/access_button",
        b"/obj/machinery/status_display",
        b"/obj/structure/window/reinforced",
    ] {
        println!(
            "map override sequences {} native={:?} emitted={:?}",
            String::from_utf8_lossy(path),
            override_sequences(&reference, path),
            override_sequences(&emitted, path)
        );
    }
    let variable_id = |dmb: &Dmb, path: &[u8], name: &[u8]| {
        let mut class_id = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))?
            as u32;
        while class_id != 0xffff {
            let class = &dmb.classes[class_id as usize];
            let list = class.defining_variable_list_id();
            if list != 0xffff {
                for pair in dmb.lists[list as usize].chunks_exact(2) {
                    if dmb.string(dmb.variables[pair[0] as usize].name) == Some(name) {
                        return Some(pair[0]);
                    }
                }
            }
            class_id = class.parent_class_id();
        }
        None
    };
    for name in [b"frequency".as_slice(), b"req_access", b"locked", b"id_tag"] {
        let path = b"/obj/machinery/door/airlock/external";
        println!(
            "airlock field {} varID native={:?} emitted={:?}",
            String::from_utf8_lossy(name),
            variable_id(&reference, path, name),
            variable_id(&emitted, path, name)
        );
    }
    for (delta, (kind, path, init)) in ind.iter().take(12) {
        println!(
            "instance delta={delta} kind={kind} init={init} path={}",
            String::from_utf8_lossy(path)
        );
    }
    for (_, (_, path, _)) in ind.iter().take(3) {
        let code_records = |dmb: &Dmb| {
            dmb.instances
                .iter()
                .enumerate()
                .filter_map(|(id, instance)| {
                    let class = if instance.kind == 8 {
                        dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
                    } else {
                        Some(instance.class)
                    }?;
                    let class_path =
                        dmb.string(dmb.classes.get(class as usize)?.path_string_id())?;
                    (class_path == path.as_slice()).then(|| {
                        (
                            id,
                            instance.initializer,
                            dmb.map_objects
                                .iter()
                                .filter(|object| object.instance as usize == id)
                                .count(),
                            (instance.initializer != 0xffff).then(|| {
                                let proc = &dmb.procs[instance.initializer as usize];
                                dmb.lists[proc.code_locals_args[0] as usize].clone()
                            }),
                        )
                    })
                })
                .collect::<Vec<_>>()
        };
        println!(
            "instance code {} native={:?} emitted={:?}",
            String::from_utf8_lossy(path),
            code_records(&reference),
            code_records(&emitted)
        );
    }
    let var_counts = |dmb: &Dmb| -> HashMap<Vec<u8>, usize> {
        let mut counts = HashMap::new();
        for var in &dmb.variables {
            if let Some(name) = dmb.string(var.name) {
                *counts.entry(name.to_vec()).or_default() += 1;
            }
        }
        counts
    };
    let nv = var_counts(&reference);
    let ev = var_counts(&emitted);
    let mut vd: Vec<_> = ev
        .iter()
        .filter_map(|(name, &count)| {
            let native = nv.get(name).copied().unwrap_or(0);
            (count != native).then_some((
                count as isize - native as isize,
                String::from_utf8_lossy(name).into_owned(),
            ))
        })
        .collect();
    vd.sort_by_key(|item| std::cmp::Reverse(item.0));
    println!(
        "var differing names={} top excess={:?}",
        vd.len(),
        vd.iter().take(20).collect::<Vec<_>>()
    );
    for (label, dmb) in [("native", &reference), ("emitted", &emitted)] {
        let mut kinds = HashMap::new();
        let mut unique = HashSet::new();
        for var in &dmb.variables {
            *kinds.entry(var.kind).or_insert(0usize) += 1;
            unique.insert((var.kind, var.value, var.name));
        }
        println!(
            "{label}: variable kinds={kinds:?}, unique raw triples={}",
            unique.len()
        );
    }
    if args.len() <= 6 {
        return;
    }
    let mut reader = BufReader::new(std::fs::File::open(&args[6]).unwrap());
    let mut resources = HashMap::new();
    while let Some(entry) = byond_dmb::rsc::read_entry(&mut reader).unwrap() {
        if let byond_dmb::rsc::Entry::Named(named) = entry {
            resources.insert(
                String::from_utf8_lossy(&named.name).replace('\\', "/"),
                named.id,
            );
        }
    }
    let input_ids: HashSet<_> = program
        .resources
        .iter()
        .filter_map(|name| {
            let name = name.replace('\\', "/");
            resources
                .get(name.strip_prefix("icons/gen/").unwrap_or(&name))
                .copied()
        })
        .collect();
    let native_ids: HashSet<_> = reference.resources.iter().map(|r| r.id).collect();
    println!(
        "resource IDs OD={} native={} extra={} missing={}",
        input_ids.len(),
        native_ids.len(),
        input_ids.difference(&native_ids).count(),
        native_ids.difference(&input_ids).count()
    );
    for id in native_ids.difference(&input_ids).take(8) {
        println!(
            "native-only resource id={id} names={:?}",
            resources
                .iter()
                .filter(|(_, value)| *value == id)
                .map(|(name, _)| name)
                .collect::<Vec<_>>()
        );
    }
    let options = CompareOptions {
        authored_prefixes: vec![
            "/obj/item/clothing/gloves/gauntlets/rig/pathfinder".into(),
            "/obj/item/stack/cable_coil".into(),
        ],
        compare_bytecode: false,
        max_discrepancies: 30,
    };
    for difference in compare_dmbs(&reference, &emitted, &options) {
        println!("diff {} {}", difference.path, difference.field);
    }
    let pathfinder = b"/obj/item/clothing/gloves/gauntlets/rig/pathfinder";
    for (label, dmb) in [("native", &reference), ("emitted", &emitted)] {
        let class = dmb
            .classes
            .iter()
            .position(|c| dmb.string(c.path_string_id()) == Some(pathfinder))
            .unwrap();
        let mut names: Vec<_> = dmb
            .class_builtin_overrides(class)
            .unwrap_or_default()
            .iter()
            .map(|v| String::from_utf8_lossy(dmb.string(v.name_string_id).unwrap()).into_owned())
            .collect();
        names.sort();
        println!("{label}: pathfinder builtin override names={names:?}");
        let mut names: Vec<_> = dmb
            .class_initial_values(class)
            .unwrap_or_default()
            .iter()
            .map(|v| {
                String::from_utf8_lossy(
                    dmb.string(dmb.variables[v.variable_id as usize].name)
                        .unwrap(),
                )
                .into_owned()
            })
            .collect();
        names.sort();
        println!("{label}: pathfinder initial variable names={names:?}");
        let mut parent = dmb.classes[class].parent_class_id();
        for _ in 0..12 {
            if parent == 0xffff {
                break;
            }
            let p = &dmb.classes[parent as usize];
            let path = String::from_utf8_lossy(dmb.string(p.path_string_id()).unwrap_or_default())
                .into_owned();
            let mut names: Vec<_> = dmb
                .class_builtin_overrides(parent as usize)
                .unwrap_or_default()
                .iter()
                .map(|v| {
                    String::from_utf8_lossy(dmb.string(v.name_string_id).unwrap()).into_owned()
                })
                .collect();
            names.sort();
            println!("{label}: parent {path} builtin={names:?}");
            parent = p.parent_class_id();
        }
        for target in [
            b"/atom/movable".as_slice(),
            b"/obj".as_slice(),
            b"/obj/item".as_slice(),
        ] {
            let id = dmb
                .classes
                .iter()
                .position(|c| dmb.string(c.path_string_id()) == Some(target))
                .unwrap();
            let mut names: Vec<_> = dmb
                .class_variable_declarations(id)
                .unwrap_or_default()
                .iter()
                .map(|(var, _)| {
                    String::from_utf8_lossy(dmb.string(dmb.variables[*var as usize].name).unwrap())
                        .into_owned()
                })
                .collect();
            names.sort();
            println!(
                "{label}: declarations {} {names:?}",
                String::from_utf8_lossy(target)
            );
        }
    }
}
