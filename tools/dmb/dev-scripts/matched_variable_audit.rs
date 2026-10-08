use super::*;

pub(super) fn report(reference: &Dmb, emitted: &Dmb, args: &[String], program: &OpenDreamProgram) {
    let var_counts = |dmb: &Dmb| -> HashMap<Vec<u8>, usize> {
        let mut counts = HashMap::new();
        for var in &dmb.variables {
            if let Some(name) = dmb.string(var.name) {
                *counts.entry(name.to_vec()).or_default() += 1;
            }
        }
        counts
    };
    let nv = var_counts(reference);
    let ev = var_counts(emitted);
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
    for (label, dmb) in [("native", reference), ("emitted", emitted)] {
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
    for difference in compare_dmbs(reference, emitted, &options) {
        println!("diff {} {}", difference.path, difference.field);
    }
    let pathfinder = b"/obj/item/clothing/gloves/gauntlets/rig/pathfinder";
    for (label, dmb) in [("native", reference), ("emitted", emitted)] {
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
