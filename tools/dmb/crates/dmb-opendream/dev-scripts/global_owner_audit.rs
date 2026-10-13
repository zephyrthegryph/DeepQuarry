//! Read-only class-static binding audit. Unowned procedure statics stay unresolved.
use byond_dmb::{bytecode::Operand, dmb::Dmb, operands::Variable};
use std::{collections::BTreeMap, io::BufRead};

type Owners = BTreeMap<u32, Vec<Vec<u8>>>;
fn owners(dmb: &Dmb) -> Owners {
    let mut result = Owners::new();
    for (id, class) in dmb.classes.iter().enumerate() {
        for (variable, flags) in dmb.class_variable_declarations(id).unwrap_or_default() {
            if flags & 1 == 0 {
                continue;
            }
            if let Some(path) = dmb.string(class.path_string_id()) {
                result.entry(variable).or_default().push(path.to_vec());
            }
        }
    }
    for paths in result.values_mut() {
        paths.sort();
        paths.dedup();
    }
    result
}

fn globals(variable: &Variable, ids: &mut Vec<u32>) {
    match variable {
        Variable::Global(id) => ids.push(*id),
        Variable::SetCache(left, right) => {
            globals(left, ids);
            globals(right, ids);
        }
        Variable::Initial(value) | Variable::IsSaved(value) => globals(value, ids),
        _ => {}
    }
}

fn name(dmb: &Dmb, id: u32) -> Option<&[u8]> {
    dmb.string(dmb.variables.get(id as usize)?.name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_names_keep_distinct_static_owner_identities() {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        dmb.classes.clear();
        let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let mut ids = Vec::new();
        for path in [b"/datum/left".as_slice(), b"/datum/right"] {
            let mut text = dmb.strings[0].clone();
            text.data = path.to_vec();
            let path_id = dmb.strings.len() as u32;
            dmb.strings.push(text);
            let variable_id = dmb.variables.len() as u32;
            dmb.variables.push(template.variables[0].clone());
            let list_id = dmb.lists.len() as u32;
            dmb.lists.push(vec![variable_id, 1]);
            let mut class = template.classes[0].clone();
            class.initial_ids[0] = path_id;
            class.lists_and_procs[4] = list_id;
            dmb.classes.push(class);
            ids.push(variable_id);
        }
        assert_eq!(name(&dmb, ids[0]), name(&dmb, ids[1]));
        let map = owners(&dmb);
        assert_ne!(map.get(&ids[0]), map.get(&ids[1]));
        dmb.lists[dmb.classes[1].defining_variable_list_id() as usize][1] = 0;
        assert!(
            !owners(&dmb).contains_key(&ids[1]),
            "instance fields are not statics"
        );
    }

    #[test]
    fn nested_initial_saved_selectors_retain_global_binding() {
        let variable = Variable::Initial(Box::new(Variable::SetCache(
            Box::new(Variable::Global(7)),
            Box::new(Variable::IsSaved(Box::new(Variable::Global(9)))),
        )));
        let mut ids = Vec::new();
        globals(&variable, &mut ids);
        assert_eq!(ids, [7, 9]);
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 4 {
        return Err("usage: global_owner_audit NATIVE.dmb ACTUAL.dmb PARITY.ndjson".into());
    }
    let n = Dmb::from_bytes(&std::fs::read(&args[1])?)?;
    let a = Dmb::from_bytes(&std::fs::read(&args[2])?)?;
    let no = owners(&n);
    let ao = owners(&a);
    let mut checked = 0;
    let mut owner_mismatches = 0;
    let mut name_candidates = 0;
    let mut unresolved = 0;
    let mut skipped = 0;
    for line in std::io::BufReader::new(std::fs::File::open(&args[3])?).lines() {
        let row: serde_json::Value = serde_json::from_str(&line?)?;
        if row["section"] != "classification" {
            continue;
        }
        let code = |dmb: &Dmb, key: &str| -> Result<_, Box<dyn std::error::Error>> {
            Ok(byond_dmb::bytecode::decode(
                dmb.proc_code_words(row[key].as_u64().ok_or("missing procedure")? as usize)
                    .ok_or("missing code")?,
            )
            .map_err(|e| format!("{e:?}"))?
            .into_iter()
            .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
            .collect::<Vec<_>>())
        };
        let nc = code(&n, "native_proc")?;
        let ac = code(&a, "translated_proc")?;
        let numeric = |op| if op == 0x50 { 0x60 } else { op };
        if nc.len() != ac.len()
            || nc
                .iter()
                .zip(&ac)
                .any(|(x, y)| numeric(x.opcode) != numeric(y.opcode))
        {
            skipped += 1;
            continue;
        }
        for (index, (ni, ai)) in nc.iter().zip(&ac).enumerate() {
            let collect = |instruction: &byond_dmb::bytecode::Instruction| {
                let mut ids = Vec::new();
                for operand in instruction.typed_operands()? {
                    if let Operand::Variable(variable) = operand {
                        globals(&variable, &mut ids);
                    }
                }
                Ok::<_, byond_dmb::bytecode::DecodeError>(ids)
            };
            let ng = collect(ni).map_err(|e| format!("{e:?}"))?;
            let ag = collect(ai).map_err(|e| format!("{e:?}"))?;
            if ng.len() != ag.len() {
                unresolved += 1;
                continue;
            }
            for (nv, av) in ng.into_iter().zip(ag) {
                let (Some(np), Some(ap)) = (no.get(&nv), ao.get(&av)) else {
                    unresolved += 1;
                    continue;
                };
                checked += 1;
                let different_name = name(&n, nv) != name(&a, av);
                let different_owner = np != ap;
                owner_mismatches += usize::from(different_owner);
                name_candidates += usize::from(different_name);
                if different_name || different_owner {
                    println!(
                        "{}",
                        serde_json::json!({"path":row["path"],"instruction":index,
                        "native_name":name(&n,nv),"actual_name":name(&a,av),
                        "native_owners":np,"actual_owners":ap,
                        "different_name":different_name,"different_owner":different_owner})
                    );
                }
            }
        }
    }
    println!(
        "{}",
        serde_json::json!({"class_static_references_checked":checked,
        "owner_mismatches":owner_mismatches,"name_candidates":name_candidates,
        "unresolved_references":unresolved,"skipped_procedure_layouts":skipped})
    );
    Ok(())
}
