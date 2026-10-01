use crate::load_dmb;
use byond_dmb::dmb::Dmb;
use std::io;

pub(crate) fn execute(name: &str, args: &[String]) -> io::Result<()> {
    match name {
        "dmb-compare" => dmb_compare(args),
        "dmb-map-compare" => dmb_map_compare(args),
        "dmb-info" => dmb_info(args),
        "reference-audit" => reference_audit(args),
        "dmb-detail" => dmb_detail(args),
        "instance" => instance(args),
        "proc-args-audit" => proc_args_audit(args),
        "argument-source-audit" => argument_source_audit(args),
        "table-audit" => table_audit(args),
        "class-vars-audit" => class_vars_audit(args),
        "class-initials-audit" => class_initials_audit(args),
        "class-overrides-audit" => class_overrides_audit(args),
        "class-initial-tag" => class_initial_tag(args),
        "class-initials" => class_initials(args),
        "dmb-copy" => dmb_copy(args),
        "opcode-audit" => opcode_audit(args),
        "value-tags" => value_tags(args),
        "value-tag-context" => value_tag_context(args),
        "proc-code" => proc_code(args),
        "list-code" => list_code(args),
        "opcode-context" => opcode_context(args),
        "string" => string(args),
        "list" => list(args),
        "variable" => variable(args),
        "proc" => proc(args),
        "mob-type" => mob_type(args),
        "class" => class(args),
        "class-path" => class_path(args),
        "class-low-flags" => class_low_flags(args),
        "class-interface-audit" => class_interface_audit(args),
        "record-kinds-audit" => record_kinds_audit(args),
        "record-kind-context" => record_kind_context(args),
        "proc-flags-audit" => proc_flags_audit(args),
        "proc-source-audit" => proc_source_audit(args),
        "proc-flag-context" => proc_flag_context(args),
        "proc-flags-context" => proc_flags_context(args),
        "mob-sight-audit" => mob_sight_audit(args),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("unknown command: {name}"),
        )),
    }
}

fn dmb_compare(args: &[String]) -> io::Result<()> {
    let expected = load_dmb(&args[2])?;
    let actual = load_dmb(&args[3])?;
    let options = byond_dmb::compare::CompareOptions {
        authored_prefixes: args[4..].to_vec(),
        ..Default::default()
    };
    for prefix in &options.authored_prefixes {
        let one = byond_dmb::compare::CompareOptions {
            authored_prefixes: vec![prefix.clone()],
            ..Default::default()
        };
        if byond_dmb::compare::selected_path_count(&expected, &one) == 0
            && byond_dmb::compare::selected_path_count(&actual, &one) == 0
        {
            return Err(io::Error::other(format!(
                "path filter {prefix:?} matched no class or procedure"
            )));
        }
    }
    let differences = byond_dmb::compare::compare_dmbs(&expected, &actual, &options);
    if differences.is_empty() {
        println!("no decoded semantic discrepancies in selected records");
    } else {
        for difference in &differences {
            println!(
                "{} {}: expected {}, actual {}",
                difference.path, difference.field, difference.expected, difference.actual
            );
        }
        return Err(io::Error::other(format!(
            "{} semantic discrepancies (showing at most {})",
            differences.len(),
            options.max_discrepancies
        )));
    }
    Ok(())
}

fn dmb_map_compare(args: &[String]) -> io::Result<()> {
    let expected = load_dmb(&args[2])?;
    let actual = load_dmb(&args[3])?;
    let differences = if args.len() == 5 {
        byond_dmb::compare::compare_maps_semantic(&expected, &actual, 100)
    } else {
        byond_dmb::compare::compare_maps(&expected, &actual, 100)
    };
    if differences.is_empty() {
        println!("no decoded map discrepancies");
    } else {
        for difference in &differences {
            println!(
                "{} {}: expected {}, actual {}",
                difference.path, difference.field, difference.expected, difference.actual
            );
        }
        return Err(io::Error::other(format!(
            "{} map discrepancies (showing at most 100)",
            differences.len()
        )));
    }
    Ok(())
}

fn dmb_info(args: &[String]) -> io::Result<()> {
    let bytes = std::fs::read(&args[2])?;
    let dmb = Dmb::from_bytes(&bytes)?;
    println!(
                "map={:?} grid_runs={} classes={} mobs={} strings={} lists={} procs={} variables={} instances={} map_objects={} resources={}",
                dmb.dimensions,
                dmb.grid.len(),
                dmb.classes.len(),
                dmb.mobs.len(),
                dmb.strings.len(),
                dmb.lists.len(),
                dmb.procs.len(),
                dmb.variables.len(),
                dmb.instances.len(),
                dmb.map_objects.len(),
                dmb.resources.len()
            );
    let code_lists = (0..dmb.procs.len())
        .filter(|&index| dmb.proc_code_words(index).is_some())
        .count();
    println!("procedure_code_lists={code_lists}");
    Ok(())
}

fn reference_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    dmb.validate_references()?;
    println!("all typed cross-table references resolve");
    Ok(())
}

fn dmb_detail(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    println!(
        "header={:?} world={:?} variable_footer={:#x}",
        dmb.header, dmb.world, dmb.variable_footer
    );
    let mut flags = std::collections::BTreeMap::new();
    for class in &dmb.classes {
        *flags.entry(class.flags).or_insert(0usize) += 1;
    }
    println!("class_flags={flags:?}");
    Ok(())
}

fn instance(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid instance ID"))?;
    let instance = dmb
        .instances
        .get(id)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "instance ID out of range"))?;
    println!("instance#{id} {instance:?}");
    Ok(())
}

fn proc_args_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut lengths = std::collections::BTreeMap::<usize, usize>::new();
    let mut malformed = Vec::new();
    let mut fourth = std::collections::BTreeMap::<u32, usize>::new();
    let mut source_kinds = std::collections::BTreeMap::<u8, usize>::new();
    let mut type_bits = 0u32;
    let mut invalid_variables = 0usize;
    let mut source_examples = std::collections::BTreeMap::<u8, (usize, [u32; 4], String)>::new();
    for (index, proc) in dmb.procs.iter().enumerate() {
        if dmb.is_reserved_proc_slot(index) {
            continue;
        }
        let id = proc.code_locals_args[2];
        if id == 0xffff {
            continue;
        }
        match dmb.lists.get(id as usize) {
            Some(words) => {
                *lengths.entry(words.len() % 4).or_default() += 1;
                for arg in words.chunks_exact(4) {
                    *fourth.entry(arg[3]).or_default() += 1;
                    *source_kinds.entry(arg[1] as u8).or_default() += 1;
                    type_bits |= arg[0];
                    source_examples.entry(arg[1] as u8).or_insert_with(|| {
                        (
                            index,
                            [arg[0], arg[1], arg[2], arg[3]],
                            dmb.variables
                                .get(arg[2] as usize)
                                .and_then(|v| dmb.string(v.name))
                                .map(String::from_utf8_lossy)
                                .unwrap_or_default()
                                .to_string(),
                        )
                    });
                    if dmb.variables.get(arg[2] as usize).is_none() {
                        invalid_variables += 1;
                    }
                }
                if words.len() % 4 != 0 && malformed.len() < 8 {
                    malformed.push((
                        index,
                        id,
                        words.len(),
                        words.iter().take(12).copied().collect::<Vec<_>>(),
                    ));
                }
            }
            None => malformed.push((index, id, 0, Vec::new())),
        }
    }
    println!("argument_list_length_remainders={lengths:?} fourth_word={fourth:?} type_bits={type_bits:#x} source_kinds={source_kinds:?} source_examples={source_examples:?} invalid_variables={invalid_variables} examples={malformed:?}");
    Ok(())
}

fn argument_source_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut groups = std::collections::BTreeMap::<u32, (usize, String)>::new();
    for (proc_id, proc) in dmb.procs.iter().enumerate() {
        if let Some(arguments) = dmb.proc_arguments(proc_id) {
            for arg in arguments {
                groups
                    .entry(arg.value_source)
                    .and_modify(|entry| entry.0 += 1)
                    .or_insert_with(|| {
                        (
                            1,
                            String::from_utf8_lossy(
                                dmb.string(proc.strings[0]).unwrap_or_default(),
                            )
                            .into_owned(),
                        )
                    });
            }
        }
    }
    for (code, (count, path)) in groups {
        println!("source={code:#x} count={count} example={path}");
    }
    println!("proc_references={}", dmb.proc_references.len());
    for (i, id) in dmb.proc_references.iter().take(8).enumerate() {
        println!(
            "reference[{i}]={id} path={}",
            dmb.procs
                .get(*id as usize)
                .and_then(|proc| dmb.string(proc.strings[0]))
                .map(String::from_utf8_lossy)
                .unwrap_or_default()
        );
    }
    Ok(())
}

fn table_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    for slot in 0..6 {
        let ids: Vec<_> = dmb
            .classes
            .iter()
            .enumerate()
            .filter_map(|(i, c)| {
                (c.lists_and_procs[slot] != 0xffff).then_some((i, c.lists_and_procs[slot]))
            })
            .collect();
        println!(
            "class_slot_{slot} present={} examples={:?}",
            ids.len(),
            ids.iter().take(6).collect::<Vec<_>>()
        );
    }
    let flags = dmb.lists.get(dmb.variable_footer as usize).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidData, "variable footer list missing")
    })?;
    println!(
        "variable_footer_words={} first={:?}",
        flags.len(),
        &flags[..flags.len().min(40)]
    );
    let entries = dmb.global_variable_flags().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "malformed global variable flags",
        )
    })?;
    let mut kinds = std::collections::BTreeMap::new();
    for (id, kind) in entries {
        if id as usize >= dmb.variables.len() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "global variable ID out of range",
            ));
        }
        *kinds.entry(kind).or_insert(0usize) += 1;
    }
    println!("global_variable_declarations={kinds:?}");
    Ok(())
}

fn class_vars_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    for slot in [4usize] {
        let mut remainders = std::collections::BTreeMap::<usize, usize>::new();
        let mut second = std::collections::BTreeMap::<u32, usize>::new();
        let mut invalid = 0usize;
        for class in &dmb.classes {
            let id = class.lists_and_procs[slot];
            if id == 0xffff {
                continue;
            }
            if let Some(words) = dmb.lists.get(id as usize) {
                *remainders.entry(words.len() % 2).or_default() += 1;
                for pair in words.chunks_exact(2) {
                    *second.entry(pair[1]).or_default() += 1;
                    if pair[0] as usize >= dmb.variables.len() {
                        invalid += 1;
                    }
                }
            } else {
                invalid += 1;
            }
        }
        println!("slot={slot} remainders={remainders:?} second={second:?} invalid_variable_ids={invalid}");
    }
    Ok(())
}

fn class_initials_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut total = 0usize;
    let mut bad = Vec::new();
    let mut tags = std::collections::BTreeMap::<u8, usize>::new();
    for (index, class) in dmb.classes.iter().enumerate() {
        if class.initialized_variable_list_id() == 0xffff {
            continue;
        }
        match dmb.class_initial_values(index) {
            Some(values) => {
                total += values.len();
                for value in values {
                    *tags.entry(value.value.tag()).or_default() += 1;
                    if value.variable_id as usize >= dmb.variables.len() && bad.len() < 8 {
                        bad.push((index, value.variable_id));
                    }
                }
            }
            None if bad.len() < 8 => bad.push((index, class.initialized_variable_list_id())),
            _ => {}
        }
    }
    println!("class_initial_values={total} tags={tags:?} bad_examples={bad:?}");
    Ok(())
}

fn class_overrides_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut total = 0usize;
    let mut bad = Vec::new();
    let mut tags = std::collections::BTreeMap::<u8, usize>::new();
    for (index, class) in dmb.classes.iter().enumerate() {
        if class.overriding_variable_list_id() == 0xffff {
            continue;
        }
        match dmb.class_builtin_overrides(index) {
            Some(values) => {
                for item in values {
                    total += 1;
                    *tags.entry(item.value.tag()).or_default() += 1;
                    if dmb.string(item.name_string_id).is_none() && bad.len() < 8 {
                        bad.push((index, item.name_string_id));
                    }
                }
            }
            None if bad.len() < 8 => bad.push((index, class.overriding_variable_list_id())),
            _ => {}
        }
    }
    println!("builtin_overrides={total} tags={tags:?} bad_examples={bad:?}");
    Ok(())
}

fn class_initial_tag(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let tag: u8 = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid tag"))?;
    let mut shown = 0;
    for (index, class) in dmb.classes.iter().enumerate() {
        if let Some(values) = dmb.class_initial_values(index) {
            for item in values {
                if item.value.tag() != tag {
                    continue;
                }
                let path =
                    String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default());
                let name = dmb
                    .variables
                    .get(item.variable_id as usize)
                    .and_then(|v| dmb.string(v.name))
                    .map(String::from_utf8_lossy)
                    .unwrap_or_default();
                let list = dmb
                    .lists
                    .get(item.value.id() as usize)
                    .map(|v| v.iter().take(12).copied().collect::<Vec<_>>());
                println!(
                    "class={index} {path} variable#{}={name} value={:?} list={list:?}",
                    item.variable_id, item.value
                );
                shown += 1;
                if shown >= 10 {
                    return Ok(());
                }
            }
        }
    }
    Ok(())
}

fn class_initials(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid class ID"))?;
    for item in dmb.class_initial_values(id).unwrap_or_default() {
        let name = dmb
            .variables
            .get(item.variable_id as usize)
            .and_then(|v| dmb.string(v.name))
            .map(String::from_utf8_lossy)
            .unwrap_or_default();
        println!("variable#{} {name} {:?}", item.variable_id, item.value);
    }
    Ok(())
}

fn dmb_copy(args: &[String]) -> io::Result<()> {
    let bytes = std::fs::read(&args[2])?;
    let dmb = Dmb::from_bytes(&bytes)?;
    std::fs::write(&args[3], dmb.to_bytes()?)?;
    Ok(())
}

fn opcode_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut decoded = 0usize;
    let mut reserved = 0usize;
    let mut failures = std::collections::BTreeMap::<String, usize>::new();
    let mut examples = Vec::new();
    let mut newer = std::collections::BTreeMap::<u32, (usize, String)>::new();
    for index in 0..dmb.procs.len() {
        if dmb.is_reserved_proc_slot(index) {
            reserved += 1;
            continue;
        }
        let words = dmb.proc_code_words(index).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("procedure {index} has no code"),
            )
        })?;
        match byond_dmb::bytecode::decode(words) {
            Ok(instructions) => {
                if byond_dmb::bytecode::encode(&instructions) != words {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "bytecode round trip changed words",
                    ));
                }
                let boundaries: std::collections::BTreeSet<_> =
                    instructions.iter().map(|item| item.offset).collect();
                for instruction in &instructions {
                    instruction.typed_operands().map_err(|error| {
                        io::Error::new(io::ErrorKind::InvalidData, error.reason)
                    })?;
                    for target in instruction
                        .branch_targets()
                        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.reason))?
                    {
                        if !boundaries.contains(&(target as usize)) {
                            return Err(io::Error::new(
                                        io::ErrorKind::InvalidData,
                                        format!("procedure {index} instruction {} branches to non-instruction word {target}", instruction.offset),
                                    ));
                        }
                    }
                    if instruction.name.starts_with("Unknown516_") {
                        let path_id = dmb.procs[index].strings[0];
                        let path = dmb
                            .string(path_id)
                            .map(|bytes| String::from_utf8_lossy(bytes).to_string())
                            .unwrap_or_else(|| format!("proc#{index}"));
                        newer
                            .entry(instruction.opcode)
                            .and_modify(|entry| entry.0 += 1)
                            .or_insert((1, path));
                    }
                }
                decoded += 1;
            }
            Err(error) => {
                if examples.len() < 8 {
                    let start = error.offset.saturating_sub(6);
                    let end = (error.offset + 4).min(words.len());
                    examples.push((index, error.offset, words[start..end].to_vec()));
                }
                *failures.entry(error.reason).or_default() += 1;
            }
        }
    }
    println!(
                "decoded={decoded} reserved={reserved} total={} failures={failures:?} examples={examples:?} newer={newer:?}",
                dmb.procs.len()
            );
    if !failures.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "one or more procedures could not be decoded",
        ));
    }
    Ok(())
}

fn value_tags(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut tags = std::collections::BTreeMap::<u32, usize>::new();
    for index in 0..dmb.procs.len() {
        if dmb.is_reserved_proc_slot(index) {
            continue;
        }
        for instruction in
            byond_dmb::bytecode::decode(dmb.proc_code_words(index).ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "procedure has no code")
            })?)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.reason))?
        {
            if instruction.opcode == 0x60 {
                *tags.entry(instruction.operands[0] & 0xff).or_default() += 1;
            }
        }
    }
    println!("{tags:?}");
    Ok(())
}

fn value_tag_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let target: u32 = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid tag"))?;
    let mut shown = 0;
    for (index, proc) in dmb.procs.iter().enumerate() {
        if dmb.is_reserved_proc_slot(index) {
            continue;
        }
        let instructions =
            byond_dmb::bytecode::decode(dmb.proc_code_words(index).ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "procedure has no code")
            })?)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.reason))?;
        for (position, instruction) in instructions.iter().enumerate() {
            if instruction.opcode != 0x60 || instruction.operands[0] & 0xff != target {
                continue;
            }
            println!(
                "proc#{index} {}",
                String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
            );
            for neighbor in
                &instructions[position.saturating_sub(3)..(position + 4).min(instructions.len())]
            {
                println!(
                    "  {:04x} {:04x} {} {:?}",
                    neighbor.offset, neighbor.opcode, neighbor.name, neighbor.operands
                );
            }
            shown += 1;
            if shown >= 5 {
                return Ok(());
            }
        }
    }
    Ok(())
}

fn proc_code(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let index: usize = if let Ok(index) = args[3].parse() {
        index
    } else {
        dmb.procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(args[3].as_bytes()))
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "proc path not found"))?
    };
    let proc = dmb
        .procs
        .get(index)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "proc index out of range"))?;
    let path = dmb.string(proc.strings[0]).unwrap_or_default();
    println!("proc#{index} {}", String::from_utf8_lossy(path));
    for instruction in byond_dmb::bytecode::decode(
        dmb.proc_code_words(index)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "procedure has no code"))?,
    )
    .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.reason))?
    {
        println!(
            "{:04x} {:04x} {} {:?}",
            instruction.offset, instruction.opcode, instruction.name, instruction.operands
        );
    }
    Ok(())
}

fn list_code(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let index: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid list ID"))?;
    let words = dmb
        .lists
        .get(index)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "list ID out of range"))?;
    println!("list#{index} words={}", words.len());
    for instruction in byond_dmb::bytecode::decode(words)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.reason))?
    {
        println!(
            "{:04x} {:04x} {} {:?}",
            instruction.offset, instruction.opcode, instruction.name, instruction.operands
        );
    }
    Ok(())
}

fn opcode_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let target = u32::from_str_radix(args[3].trim_start_matches("0x"), 16)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid opcode hex"))?;
    let mut shown = 0;
    for (index, proc) in dmb.procs.iter().enumerate() {
        if dmb.is_reserved_proc_slot(index) {
            continue;
        }
        let instructions =
            byond_dmb::bytecode::decode(dmb.proc_code_words(index).ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "procedure has no code")
            })?)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.reason))?;
        for (position, instruction) in instructions.iter().enumerate() {
            if instruction.opcode != target {
                continue;
            }
            println!(
                "proc#{index} {}",
                String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
            );
            for neighbor in
                &instructions[position.saturating_sub(4)..(position + 5).min(instructions.len())]
            {
                println!(
                    "  {:04x} {:04x} {} {:?}",
                    neighbor.offset, neighbor.opcode, neighbor.name, neighbor.operands
                );
            }
            shown += 1;
            if shown >= 5 {
                return Ok(());
            }
        }
    }
    Ok(())
}

fn string(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: u32 = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid string ID"))?;
    println!(
        "{}",
        String::from_utf8_lossy(dmb.string(id).ok_or_else(|| io::Error::new(
            io::ErrorKind::InvalidInput,
            "string ID out of range"
        ))?)
    );
    Ok(())
}

fn list(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid list ID"))?;
    println!(
        "{:?}",
        dmb.lists
            .get(id)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "list ID out of range"))?
    );
    Ok(())
}

fn variable(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid variable ID"))?;
    let variable = dmb
        .variables
        .get(id)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "variable ID out of range"))?;
    println!(
        "{variable:?} name={}",
        String::from_utf8_lossy(dmb.string(variable.name).unwrap_or_default())
    );
    Ok(())
}

fn proc(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid proc ID"))?;
    let proc = dmb
        .procs
        .get(id)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "proc ID out of range"))?;
    println!(
        "{proc:?} path={}",
        String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
    );
    Ok(())
}

fn mob_type(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid mob ID"))?;
    let mob = dmb
        .mobs
        .get(id)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "mob ID out of range"))?;
    println!(
        "{mob:?} path={}",
        String::from_utf8_lossy(
            dmb.string(dmb.classes[mob.class as usize].path_string_id())
                .unwrap_or_default()
        )
    );
    Ok(())
}

fn class(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let id: usize = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid class ID"))?;
    let class = dmb
        .classes
        .get(id)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "class ID out of range"))?;
    println!(
        "{class:?} path={}",
        String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default())
    );
    Ok(())
}

fn class_path(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    for (id, class) in dmb.classes.iter().enumerate() {
        if dmb.string(class.path_string_id()) == Some(args[3].as_bytes()) {
            println!("class#{id} {class:?}");
        }
    }
    Ok(())
}

fn class_low_flags(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut groups = std::collections::BTreeMap::<u64, (usize, String)>::new();
    for class in &dmb.classes {
        let low = class.flags & ((1 << 21) - 1);
        groups
            .entry(low)
            .and_modify(|entry| entry.0 += 1)
            .or_insert_with(|| {
                (
                    1,
                    String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default())
                        .to_string(),
                )
            });
    }
    for (flags, (count, path)) in groups {
        println!("{flags:#08x} count={count} example={path}");
    }
    Ok(())
}

fn class_interface_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut groups = std::collections::BTreeMap::<(u8, Option<u32>), (usize, String)>::new();
    for class in &dmb.classes {
        groups
            .entry((class.interface, class.extended_interface))
            .and_modify(|v| v.0 += 1)
            .or_insert_with(|| {
                (
                    1,
                    String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default())
                        .to_string(),
                )
            });
    }
    for (kind, (count, path)) in groups {
        println!("{kind:?} count={count} example={path}");
    }
    Ok(())
}

fn record_kinds_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut vars = std::collections::BTreeMap::<u8, usize>::new();
    let mut instances = std::collections::BTreeMap::<u8, usize>::new();
    for variable in &dmb.variables {
        *vars.entry(variable.kind).or_default() += 1;
    }
    for instance in &dmb.instances {
        *instances.entry(instance.kind).or_default() += 1;
    }
    println!("variable_kinds={vars:?} instance_kinds={instances:?}");
    let slots: Vec<u32> = dmb
        .variables
        .iter()
        .filter(|v| v.kind == 62)
        .map(|v| v.value)
        .collect();
    let unique: std::collections::BTreeSet<_> = slots.iter().copied().collect();
    println!(
        "hidden_initializer_slots={} unique={} min={:?} max={:?}",
        slots.len(),
        unique.len(),
        unique.first(),
        unique.last()
    );
    Ok(())
}

fn record_kind_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let kind: u8 = args[3]
        .parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid kind"))?;
    for (id, variable) in dmb
        .variables
        .iter()
        .enumerate()
        .filter(|(_, v)| v.kind == kind)
        .take(20)
    {
        println!(
            "variable#{id} {:?} name={}",
            variable,
            String::from_utf8_lossy(dmb.string(variable.name).unwrap_or_default())
        );
    }
    Ok(())
}

fn proc_flags_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut flags = std::collections::BTreeMap::<u8, usize>::new();
    let mut extended = std::collections::BTreeMap::<(u32, u8), usize>::new();
    for proc in &dmb.procs {
        *flags.entry(proc.flags).or_default() += 1;
        if let Some(extra) = proc.extended_flags {
            *extended.entry(extra).or_default() += 1;
        }
    }
    println!("flags={flags:?} extended={extended:?}");
    Ok(())
}

fn proc_source_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut groups = std::collections::BTreeMap::<(u8, u8), (usize, String)>::new();
    for proc in &dmb.procs {
        groups
            .entry((proc.source_kind, proc.source_parameter))
            .and_modify(|entry| entry.0 += 1)
            .or_insert_with(|| {
                (
                    1,
                    String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
                        .into_owned(),
                )
            });
    }
    for (code, (count, path)) in groups {
        println!("source={code:?} count={count} example={path}");
    }
    Ok(())
}

fn proc_flag_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let target = u32::from_str_radix(args[3].trim_start_matches("0x"), 16)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "invalid flag hex"))?;
    for (id, proc) in dmb
        .procs
        .iter()
        .enumerate()
        .filter(|(_, proc)| proc.effective_flags() & target == target)
        .take(30)
    {
        println!(
            "proc#{id} flags={:#x} path={}",
            proc.effective_flags(),
            String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
        );
    }
    Ok(())
}

fn proc_flags_context(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    for (id, proc) in dmb
        .procs
        .iter()
        .enumerate()
        .filter(|(_, p)| p.extended_flags.is_some())
    {
        println!(
            "proc#{id} flags={:#x} extended={:?} path={}",
            proc.flags,
            proc.extended_flags,
            String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default())
        );
    }
    Ok(())
}

fn mob_sight_audit(args: &[String]) -> io::Result<()> {
    let dmb = load_dmb(&args[2])?;
    let mut compact = std::collections::BTreeMap::<u8, usize>::new();
    let mut extended = std::collections::BTreeMap::<(u32, u8, u8), usize>::new();
    for mob in &dmb.mobs {
        if let Some(ext) = mob.extended_sight {
            *extended.entry(ext).or_default() += 1;
        } else {
            *compact.entry(mob.sight).or_default() += 1;
        }
    }
    println!("compact={compact:?} extended={extended:?}");
    Ok(())
}
