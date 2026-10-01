use byond_dmb::{
    compare::{compare_dmbs, compare_maps_semantic, compare_proc_code, CompareOptions},
    dmb::Dmb,
};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::Write,
};

fn paths(dmb: &Dmb, classify: bool) -> BTreeMap<String, Vec<usize>> {
    let mut output = BTreeMap::<String, Vec<usize>>::new();
    for (id, proc) in dmb.procs.iter().enumerate() {
        if proc.strings[0] == 0xffff {
            continue;
        }
        if let Some(path) = dmb.string(proc.strings[0]) {
            if !path.is_empty() {
                output
                    .entry(
                        if classify && !path.starts_with(b"/proc/") && !path.starts_with(b"/verb/")
                        {
                            String::from_utf8_lossy(path)
                                .replace("/proc/", "/")
                                .replace("/verb/", "/")
                        } else {
                            String::from_utf8_lossy(path).into_owned()
                        },
                    )
                    .or_default()
                    .push(id);
            }
        }
    }
    for class in &dmb.classes {
        let id = class.initializer_proc_id();
        if id != 0xffff {
            let path =
                String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default());
            output.insert(format!("{path}::<class initializer>"), vec![id as usize]);
        }
    }
    let global = dmb.world.global_initializer_proc_id();
    if global != 0xffff {
        output.insert("/world::<global initializer>".into(), vec![global as usize]);
    }
    byond_dmb::compare::order_proc_groups_by_binding(dmb, output.values_mut());
    output
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args: Vec<_> = std::env::args().collect();
    let classify = args.iter().any(|arg| arg == "--classify");
    let corpus_path = args
        .iter()
        .find_map(|arg| arg.strip_prefix("--corpus=").map(str::to_owned));
    args.retain(|arg| arg != "--classify");
    args.retain(|arg| !arg.starts_with("--corpus="));
    let mut corpus_paths = BTreeSet::new();
    if let Some(path) = &corpus_path {
        let program =
            byond_dmb::opendream::OpenDreamProgram::from_path(std::path::Path::new(path))?;
        let authored = |proc: &byond_dmb::opendream::OpenDreamProc| {
            proc.source_info.iter().any(|info| {
                info.file
                    .and_then(|id| program.strings.get(id))
                    .is_some_and(|file| {
                        let file = file.replace('\\', "/");
                        file.contains("Content.Tests/DMProject/Tests/")
                            || file.ends_with("/corpus_source.dm")
                    })
            })
        };
        for typ in &program.types {
            for &id in typ.procs.iter().flatten() {
                if let Some(proc) = program.procs.get(id).filter(|proc| authored(proc)) {
                    let path = if typ.path == "/" && program.global_procs.contains(&id) {
                        format!(
                            "/{}/{}",
                            if proc.is_verb { "verb" } else { "proc" },
                            proc.name
                        )
                    } else {
                        format!("{}/{}", typ.path.trim_end_matches('/'), proc.name)
                    };
                    corpus_paths.insert(path);
                }
            }
            if let Some(id) = typ
                .init_proc
                .filter(|&id| program.procs.get(id).is_some_and(&authored))
            {
                let _ = id;
                corpus_paths.insert(format!("{}::<class initializer>", typ.path));
            }
        }
        for &id in &program.global_procs {
            if let Some(proc) = program.procs.get(id).filter(|proc| authored(proc)) {
                corpus_paths.insert(format!(
                    "/{}/{}",
                    if proc.is_verb { "verb" } else { "proc" },
                    proc.name
                ));
            }
        }
        if program.global_init_proc.as_ref().is_some_and(authored) {
            corpus_paths.insert("/world::<global initializer>".to_owned());
        }
    }
    let expected = Dmb::from_bytes(&std::fs::read(&args[1])?)?;
    let actual = Dmb::from_bytes(&std::fs::read(&args[2])?)?;
    let mut report = std::io::BufWriter::new(std::fs::File::create(&args[3])?);
    let metadata = compare_dmbs(
        &expected,
        &actual,
        &CompareOptions {
            compare_bytecode: false,
            max_discrepancies: usize::MAX,
            ..Default::default()
        },
    );
    let mut groups = BTreeMap::<String, usize>::new();
    for diff in &metadata {
        *groups.entry(diff.field.clone()).or_default() += 1;
        writeln!(
            report,
            "{}",
            serde_json::json!({"section":"metadata","path":diff.path,"field":diff.field,"native":diff.expected,"translated":diff.actual})
        )?;
    }
    println!("metadata differences={} groups={groups:?}", metadata.len());
    let left = paths(&expected, classify);
    let right = paths(&actual, classify);
    let mut classifications = BTreeMap::<String, usize>::new();
    let mut pairs = 0;
    let mut raw_matches = 0;
    let mut normalized_matches = 0;
    let mut only_native = 0;
    let mut only_translated = 0;
    let mut first_groups = BTreeMap::<String, usize>::new();
    for path in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        let a = left.get(path).map(Vec::as_slice).unwrap_or_default();
        let b = right.get(path).map(Vec::as_slice).unwrap_or_default();
        if corpus_path.is_some() && !corpus_paths.contains(path) {
            continue;
        }
        only_native += a.len().saturating_sub(b.len());
        only_translated += b.len().saturating_sub(a.len());
        if a.len() != b.len() {
            writeln!(
                report,
                "{}",
                serde_json::json!({"section":"procedure_presence","path":path,"native_ids":a,"translated_ids":b})
            )?;
        }
        for (&ai, &bi) in a.iter().zip(b) {
            pairs += 1;
            raw_matches += usize::from(expected.proc_code_words(ai) == actual.proc_code_words(bi));
            let differences = compare_proc_code(
                &expected,
                ai,
                &actual,
                bi,
                path,
                if classify { 512 } else { 3 },
                true,
            );
            if differences.is_empty() {
                normalized_matches += 1;
            } else {
                if classify {
                    let opcodes = |dmb: &Dmb, id| {
                        byond_dmb::bytecode::decode(dmb.proc_code_words(id).unwrap_or_default())
                            .unwrap()
                            .into_iter()
                            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .map(|item| item.opcode)
                            .collect::<Vec<_>>()
                    };
                    let native_ops = opcodes(&expected, ai);
                    let translated_ops = opcodes(&actual, bi);
                    let opcode_pairs = differences
                        .iter()
                        .filter(|diff| diff.field.ends_with(".opcode"))
                        .filter_map(|diff| {
                            Some((
                                diff.expected.parse::<u32>().ok()?,
                                diff.actual.parse::<u32>().ok()?,
                            ))
                        })
                        .collect::<Vec<_>>();
                    let operands = differences
                        .iter()
                        .filter(|diff| diff.field.ends_with(".operands"))
                        .collect::<Vec<_>>();
                    let category = if native_ops == translated_ops
                        && operands.iter().all(|diff| {
                            diff.expected.contains("Variable(")
                                && diff.actual.contains("Variable(")
                                && (diff.expected.contains("Nested(")
                                    || diff.actual.contains("Nested("))
                        }) {
                        "cache_or_reference_operands_only"
                    } else if native_ops == translated_ops
                        && operands.iter().all(|diff| {
                            diff.expected.contains("Branch(")
                                || diff.expected.contains("Switch")
                                || diff.expected.contains("Complex(")
                        })
                    {
                        "branch_or_switch_operands_only"
                    } else if native_ops == translated_ops {
                        "other_operands_only"
                    } else if native_ops.len() == translated_ops.len()
                        && !opcode_pairs.is_empty()
                        && opcode_pairs
                            .iter()
                            .all(|pair| matches!(pair, (0x2a, 0x29) | (0x29, 0x2a)))
                    {
                        "call_statement_opcode_encoding"
                    } else if native_ops.len() == translated_ops.len()
                        && !opcode_pairs.is_empty()
                        && opcode_pairs
                            .iter()
                            .all(|pair| matches!(pair, (0x34, 0x35) | (0x35, 0x34)))
                    {
                        "assignment_result_opcode_encoding"
                    } else if native_ops
                        .iter()
                        .filter(|&&op| matches!(op, 0x37 | 0x38))
                        .count()
                        != 0
                        && (translated_ops.contains(&0xb2) || translated_ops.contains(&0xb3))
                        && native_ops.iter().filter(|&&op| op == 0x36).count()
                            > translated_ops.iter().filter(|&&op| op == 0x36).count()
                    {
                        "equality_flag_with_short_circuit_candidate"
                    } else if native_ops.len() == translated_ops.len() {
                        "mixed_same_instruction_count"
                    } else {
                        "mixed_different_instruction_count"
                    };
                    *classifications.entry(category.to_owned()).or_default() += 1;
                    let histogram = |ops: Vec<u32>| {
                        let mut count = BTreeMap::<u32, i32>::new();
                        for op in ops {
                            *count.entry(op).or_default() += 1;
                        }
                        count
                    };
                    let a = histogram(native_ops);
                    let b = histogram(translated_ops);
                    let delta = a
                        .keys()
                        .chain(b.keys())
                        .collect::<BTreeSet<_>>()
                        .into_iter()
                        .filter_map(|&op| {
                            let value =
                                b.get(&op).copied().unwrap_or(0) - a.get(&op).copied().unwrap_or(0);
                            (value != 0).then_some((format!("{op:#x}"), value))
                        })
                        .collect::<BTreeMap<_, _>>();
                    writeln!(
                        report,
                        "{}",
                        serde_json::json!({"section":"classification","path":path,"native_proc":ai,"translated_proc":bi,"category":category,"reported_difference_count":differences.len(),"capped":differences.len()==512,"opcode_count_delta":delta})
                    )?;
                }
                let field = differences[0].field.split('[').next().unwrap().to_owned();
                *first_groups.entry(field).or_default() += 1;
                for diff in differences.into_iter().take(3) {
                    writeln!(
                        report,
                        "{}",
                        serde_json::json!({"section":"bytecode","path":path,"native_proc":ai,"translated_proc":bi,"field":diff.field,"native":diff.expected,"translated":diff.actual})
                    )?;
                }
            }
        }
    }
    println!("procedure pairs={pairs} raw_word_matches={raw_matches} normalized_matches={normalized_matches} differing={} native_only={only_native} translated_only={only_translated} first_difference_groups={first_groups:?}", pairs-normalized_matches);
    if classify {
        println!("classification candidates={classifications:?}");
        for (label, dmb) in [("native", &expected), ("translated", &actual)] {
            let mut equality_followers = BTreeMap::<String, usize>::new();
            let mut affected = BTreeMap::<String, BTreeSet<usize>>::new();
            let mut iter_masks = BTreeMap::<u32, usize>::new();
            let mut iterator_pushes = 0;
            let mut iterator_pops = 0;
            for id in 0..dmb.procs.len() {
                let items =
                    byond_dmb::bytecode::decode(dmb.proc_code_words(id).unwrap_or_default())
                        .unwrap()
                        .into_iter()
                        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .collect::<Vec<_>>();
                for pair in items.windows(2) {
                    if matches!(pair[0].opcode, 0x37 | 0x38) {
                        let key = format!("{:#x}", pair[1].opcode);
                        *equality_followers.entry(key.clone()).or_default() += 1;
                        affected.entry(key).or_default().insert(id);
                    }
                }
                for item in items {
                    if item.opcode == 0x52 && item.operands.first() == Some(&5) {
                        *iter_masks.entry(item.operands[1]).or_default() += 1;
                    }
                    iterator_pushes += usize::from(item.opcode == 0x54);
                    iterator_pops += usize::from(item.opcode == 0x55);
                }
            }
            let affected = affected
                .into_iter()
                .map(|(key, ids)| (key, ids.len()))
                .collect::<BTreeMap<_, _>>();
            println!("{label} equality immediate_followers={equality_followers:?} procedures_by_follower={affected:?}");
            println!("{label} IterLoad_mode5_masks={iter_masks:?} IterPush={iterator_pushes} IterPop={iterator_pops}");
        }
    }
    let maps = compare_maps_semantic(&expected, &actual, usize::MAX);
    println!("map semantic differences={}", maps.len());
    for diff in maps {
        writeln!(
            report,
            "{}",
            serde_json::json!({"section":"maps","path":diff.path,"field":diff.field,"native":diff.expected,"translated":diff.actual})
        )?;
    }
    let resources = |dmb: &Dmb| {
        dmb.resources
            .iter()
            .map(|entry| (entry.kind, entry.id))
            .collect::<BTreeSet<_>>()
    };
    let a = resources(&expected);
    let b = resources(&actual);
    println!(
        "resource identities native={} translated={} native_only={} translated_only={}",
        a.len(),
        b.len(),
        a.difference(&b).count(),
        b.difference(&a).count()
    );
    println!("tables native/translated: classes={}/{} procs={}/{} variables={}/{} strings={}/{} lists={}/{} instances={}/{}", expected.classes.len(), actual.classes.len(), expected.procs.len(), actual.procs.len(), expected.variables.len(), actual.variables.len(), expected.strings.len(), actual.strings.len(), expected.lists.len(), actual.lists.len(), expected.instances.len(), actual.instances.len());
    if args.len() == 6 {
        let read = |path: &str| -> Result<_, Box<dyn std::error::Error>> {
            let mut reader = std::io::BufReader::new(std::fs::File::open(path)?);
            let mut entries = BTreeMap::new();
            let mut order = Vec::new();
            while let Some(entry) = byond_dmb::rsc::read_entry(&mut reader)? {
                if let byond_dmb::rsc::Entry::Named(named) = entry {
                    order.push(named.name.clone());
                    entries.insert(named.name.clone(), named);
                }
            }
            Ok((entries, order))
        };
        let (a, ao) = read(&args[4])?;
        let (b, bo) = read(&args[5])?;
        let mut payload_differences = 0;
        let mut metadata_differences = 0;
        let mut metadata_fields = BTreeMap::<&str, usize>::new();
        let mut missing_names = 0;
        for name in a.keys().chain(b.keys()).collect::<BTreeSet<_>>() {
            match (a.get(name), b.get(name)) {
                (Some(a), Some(b)) => {
                    payload_differences += usize::from(a.asset_bytes()? != b.asset_bytes()?);
                    for (field, different) in [
                        ("kind", a.kind != b.kind),
                        ("id", a.id != b.id),
                        ("timestamp", a.timestamp != b.timestamp),
                        ("source_timestamp", a.source_timestamp != b.source_timestamp),
                        ("declared_size", a.declared_size != b.declared_size),
                    ] {
                        if different {
                            *metadata_fields.entry(field).or_default() += 1;
                        }
                    }
                    metadata_differences += usize::from(
                        (
                            a.kind,
                            a.id,
                            a.timestamp,
                            a.source_timestamp,
                            a.declared_size,
                        ) != (
                            b.kind,
                            b.id,
                            b.timestamp,
                            b.source_timestamp,
                            b.declared_size,
                        ),
                    );
                }
                _ => missing_names += 1,
            }
        }
        println!("RSC named entries native={} translated={} missing_names={missing_names} asset_payload_differences={payload_differences} metadata_differences={metadata_differences} same_entry_order={}", a.len(),b.len(),ao==bo);
        println!("RSC metadata differences by field={metadata_fields:?}");
    }
    Ok(())
}
