use byond_dmb::{dmb::Dmb, opendream::OpenDreamProgram};
use std::collections::{HashMap, HashSet};

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let od = OpenDreamProgram::from_path(&args[1]).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(&args[2]).unwrap()).unwrap();
    let known: HashSet<_> = od
        .types
        .iter()
        .flat_map(|t| {
            t.dynamic_initializer_assignments
                .iter()
                .map(|f| (t.path.clone(), f.clone()))
        })
        .collect();
    let kinds: HashMap<_, _> = od
        .types
        .iter()
        .map(|t| (t.path.as_str(), &t.initializer_value_kinds))
        .collect();
    let mut missing = HashSet::new();
    for (id, class) in native.classes.iter().enumerate() {
        let path =
            String::from_utf8_lossy(native.string(class.path_string_id()).unwrap_or_default());
        for entry in native.class_initial_values(id).unwrap_or_default() {
            if entry.value.tag() != 62 {
                continue;
            }
            let name = String::from_utf8_lossy(
                native
                    .string(native.variables[entry.variable_id as usize].name)
                    .unwrap_or_default(),
            );
            if !known.contains(&(path.to_string(), name.to_string())) {
                let kind = kinds.get(path.as_ref()).and_then(|m| m.get(name.as_ref()));
                missing.insert((path.to_string(), name.to_string(), kind.cloned()));
            }
        }
    }
    let mut missing: Vec<_> = missing.into_iter().collect();
    missing.sort();
    println!("missing {}", missing.len());
    for (path, name, kind) in missing {
        println!("{path}.{name}: {kind:?}");
    }
}
