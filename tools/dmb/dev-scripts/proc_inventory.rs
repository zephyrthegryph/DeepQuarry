//! Read-only inventory of generated procedures and their structural referents.
use byond_dmb::{bytecode, dmb::Dmb};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::{BufWriter, Write},
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if !(3..=4).contains(&args.len()) {
        return Err(
            "usage: proc_inventory NATIVE.dmb TRANSLATED.dmb OUTPUT.ndjson [NATIVE_INSTANCE_ID]"
                .into(),
        );
    }
    let mut output = BufWriter::new(fs::File::create(&args[2])?);
    for (side, filename) in [("native", &args[0]), ("translated", &args[1])] {
        let dmb = Dmb::from_bytes(&fs::read(filename)?)?;
        let proc_name = |id: usize| {
            dmb.procs
                .get(id)
                .and_then(|p| {
                    (p.strings[0] != 0xffff)
                        .then(|| dmb.string(p.strings[0]))
                        .flatten()
                })
                .map(|s| String::from_utf8_lossy(s).into_owned())
        };
        if side == "native" {
            if let Some(target) = args.get(3) {
                let target = target.parse::<u32>()?;
                for id in 0..dmb.procs.len() {
                    for instruction in bytecode::decode(dmb.proc_code_words(id).unwrap_or_default())
                        .map_err(|e| format!("{e:?}"))?
                    {
                        for operand in instruction.typed_operands().map_err(|e| format!("{e:?}"))? {
                            let values = match operand {
                                bytecode::Operand::Value(value) => vec![value],
                                bytecode::Operand::Switch { cases, .. } => {
                                    cases.into_iter().map(|(value, _)| value).collect()
                                }
                                bytecode::Operand::RangeSwitch { ranges, exact, .. } => ranges
                                    .into_iter()
                                    .flat_map(|(a, b, _)| [a, b])
                                    .chain(exact.into_iter().map(|(value, _)| value))
                                    .collect(),
                                _ => vec![],
                            };
                            if values
                                .iter()
                                .any(|value| value.tag() == 41 && value.id() == target)
                            {
                                println!(
                                    "instance#{target} code ref proc#{id} {:?} word#{}",
                                    proc_name(id),
                                    instruction.offset
                                );
                            }
                        }
                    }
                }
                for (id, variable) in dmb.variables.iter().enumerate() {
                    if variable.kind == 41 && variable.value == target {
                        println!(
                            "instance#{target} variable ref var#{id} {:?}",
                            dmb.string(variable.name).map(String::from_utf8_lossy)
                        );
                    }
                }
                for id in 0..dmb.classes.len() {
                    for initial in dmb.class_initial_values(id).unwrap_or_default() {
                        if initial.value.tag() == 41 && initial.value.id() == target {
                            println!(
                                "instance#{target} class ref class#{id} var#{}",
                                initial.variable_id
                            );
                        }
                    }
                }
                let grid_refs = dmb
                    .grid
                    .iter()
                    .filter(|run| run.turf == target || run.area == target)
                    .count();
                let object_refs = dmb
                    .map_objects
                    .iter()
                    .filter(|object| object.instance == target)
                    .count();
                println!("instance#{target} map grid_refs={grid_refs} object_refs={object_refs}");
            }
        }
        let mut roles = BTreeMap::<usize, BTreeSet<String>>::new();
        for (instance_id, instance) in dmb.instances.iter().enumerate() {
            if instance.initializer != 0xffff {
                continue;
            }
            let class = if instance.kind == 8 {
                dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
            } else {
                Some(instance.class)
            };
            let path = class
                .and_then(|id| dmb.classes.get(id as usize))
                .and_then(|class| dmb.string(class.path_string_id()))
                .map(String::from_utf8_lossy);
            writeln!(
                output,
                "{}",
                serde_json::json!({"side":side,"category":"plain_instance","instance_id":instance_id,"kind":instance.kind,"path":path})
            )?;
        }
        for (index, class) in dmb.classes.iter().enumerate() {
            let id = class.initializer_proc_id() as usize;
            if id != 0xffff {
                let path = dmb
                    .string(class.path_string_id())
                    .map(String::from_utf8_lossy)
                    .unwrap_or_default();
                roles
                    .entry(id)
                    .or_default()
                    .insert(format!("class:{path}#{index}"));
            }
        }
        for (index, instance) in dmb.instances.iter().enumerate() {
            if instance.initializer != 0xffff {
                roles
                    .entry(instance.initializer as usize)
                    .or_default()
                    .insert(format!("instance:{index}"));
            }
        }
        roles
            .entry(dmb.world.global_initializer_proc_id() as usize)
            .or_default()
            .insert("global initializer".into());
        for id in 0..dmb.procs.len() {
            for (index, argument) in dmb
                .proc_arguments(id)
                .unwrap_or_default()
                .iter()
                .enumerate()
            {
                if let Some(source) = dmb.argument_source_proc_id(argument) {
                    roles.entry(source as usize).or_default().insert(format!(
                        "argument:{}:{index}",
                        proc_name(id).unwrap_or_else(|| format!("#{id}"))
                    ));
                }
            }
        }
        let mut counts = BTreeMap::<String, usize>::new();
        for id in 0..dmb.procs.len() {
            if proc_name(id).is_some() {
                continue;
            }
            let referents = roles.get(&id).cloned().unwrap_or_default();
            let category = if referents.is_empty() {
                "unreferenced"
            } else if referents.iter().any(|r| r.starts_with("argument:")) {
                "argument"
            } else if referents.iter().any(|r| r.starts_with("class:")) {
                "class"
            } else if referents.iter().any(|r| r.starts_with("instance:")) {
                "instance"
            } else {
                "other"
            };
            *counts.entry(category.into()).or_default() += 1;
            let words = dmb.proc_code_words(id).unwrap_or_default();
            let instructions =
                bytecode::decode(words).map_err(|error| format!("proc#{id}: {error:?}"))?;
            let instance_signatures = referents
                .iter()
                .filter_map(|referent| {
                    let index = referent.strip_prefix("instance:")?.parse::<u32>().ok()?;
                    Some((
                        index,
                        byond_dmb::compare::constant_instance_signature(&dmb, index),
                    ))
                })
                .collect::<Vec<_>>();
            writeln!(
                output,
                "{}",
                serde_json::json!({"side":side,"id":id,"category":category,"referents":referents,"words":words,"instance_signatures":instance_signatures,"opcodes":instructions.iter().filter(|i| !matches!(i.opcode,0x84|0x85)).map(|i|i.opcode).collect::<Vec<_>>()})
            )?;
        }
        println!("{side} total={} anonymous={counts:?}", dmb.procs.len());
    }
    Ok(())
}
