//! Anonymous procedures pair by rooted semantic use, never body similarity or IDs.
use super::*;
use std::collections::VecDeque;

pub(super) fn procedure_ownership(dmb: &memo::NormalizationContext<'_>) -> BTreeMap<String, u32> {
    let mut owned = BTreeMap::new();
    for (name, ids) in proc_index(dmb, &CompareOptions::default()) {
        for (rank, id) in ids.into_iter().enumerate() {
            owned.insert(format!("{}#{rank}", label(&name)), id as u32);
        }
    }
    for (name, ids) in class_index(dmb, &CompareOptions::default()) {
        for (rank, id) in ids.into_iter().enumerate() {
            let site = format!("{}#{rank}", label(&name));
            insert_proc(
                dmb,
                &mut owned,
                format!("{site}::<init>"),
                dmb.classes[id].initializer_proc_id(),
            );
            for field in dmb.class_initial_values(id).unwrap_or_default() {
                if let Some(variable) = dmb.variables.get(field.variable_id as usize) {
                    instance_value(
                        dmb,
                        &mut owned,
                        &format!(
                            "{site}::default:{}",
                            label(dmb.string(variable.name).unwrap_or_default())
                        ),
                        field.value,
                    );
                }
            }
            for field in dmb.class_builtin_overrides(id).unwrap_or_default() {
                instance_value(
                    dmb,
                    &mut owned,
                    &format!(
                        "{site}::builtin:{}",
                        label(dmb.string(field.name_string_id).unwrap_or_default())
                    ),
                    field.value,
                );
            }
        }
    }
    insert_proc(
        dmb,
        &mut owned,
        "/world::<global-init>".into(),
        dmb.world.global_initializer_proc_id(),
    );
    // Coordinate anchors survive grid run compression. Retain the first use of
    // each instance; subsequent shared uses don't supply a new procedure owner.
    let mut seen_instances = BTreeSet::new();
    let mut cell = 0usize;
    for run in &dmb.grid {
        for (kind, id) in [("turf", run.turf), ("area", run.area)] {
            if seen_instances.insert(id) {
                instance_initializer(dmb, &mut owned, &format!("/map/flat#{cell}/{kind}"), id);
            }
        }
        cell += usize::from(run.copies);
    }
    let mut cell = 0usize;
    let mut ordinal = 0usize;
    for object in &dmb.map_objects {
        if object.offset != 0 {
            ordinal = 0;
        }
        cell += usize::from(object.offset);
        if seen_instances.insert(object.instance) {
            instance_initializer(
                dmb,
                &mut owned,
                &format!("/map/flat#{cell}/object#{ordinal}"),
                object.instance,
            );
        }
        ordinal += 1;
    }
    let mut pending: VecDeque<_> = owned.iter().map(|(name, id)| (name.clone(), *id)).collect();
    let mut scanned = BTreeSet::new();
    while let Some((site, id)) = pending.pop_front() {
        if !scanned.insert(id) {
            continue;
        }
        let mut children = BTreeMap::new();
        for (index, argument) in dmb
            .proc_arguments(id as usize)
            .unwrap_or_default()
            .iter()
            .enumerate()
        {
            if let Some(child) = dmb.argument_source_proc_id(argument) {
                insert_proc(
                    dmb,
                    &mut children,
                    format!("{site}::<argument {index} source>"),
                    child,
                );
            }
        }
        if let Ok(code) = bytecode::decode(dmb.proc_code_words(id as usize).unwrap_or_default()) {
            let mut use_index = 0;
            for item in code {
                if let Ok(operands) = item.typed_operands() {
                    for operand in operands {
                        for value in operand_values(operand) {
                            if value.kind() == ValueKind::InstanceTypePath {
                                // Ordered modified-type use is a consumer role, not
                                // the raw instruction offset or a body match key.
                                instance_value(
                                    dmb,
                                    &mut children,
                                    &format!("{site}::<modified-type use {use_index}>"),
                                    value,
                                );
                                use_index += 1;
                            }
                        }
                    }
                }
            }
        }
        for (name, child) in children {
            if let std::collections::btree_map::Entry::Vacant(entry) = owned.entry(name) {
                pending.push_back((entry.key().clone(), child));
                entry.insert(child);
            }
        }
    }
    owned
}

fn insert_proc(
    dmb: &memo::NormalizationContext<'_>,
    owned: &mut BTreeMap<String, u32>,
    site: String,
    id: u32,
) {
    if id != 0xffff && dmb.procs.get(id as usize).is_some() {
        owned.insert(site, id);
    }
}

fn instance_value(
    dmb: &memo::NormalizationContext<'_>,
    owned: &mut BTreeMap<String, u32>,
    site: &str,
    value: Value,
) {
    if value.kind() == ValueKind::InstanceTypePath {
        instance_initializer(dmb, owned, site, value.id());
    }
}

fn instance_initializer(
    dmb: &memo::NormalizationContext<'_>,
    owned: &mut BTreeMap<String, u32>,
    site: &str,
    id: u32,
) {
    if let Some(instance) = dmb.instances.get(id as usize) {
        let class = if instance.kind == 8 {
            dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
        } else {
            Some(instance.class)
        };
        if let Some(name) = class.and_then(|class| path(dmb, class)) {
            insert_proc(
                dmb,
                owned,
                format!("{site}::<instance {} init>", label(&name)),
                instance.initializer,
            );
        }
    }
}

fn operand_values(operand: Operand) -> Vec<Value> {
    match operand {
        Operand::Value(value) => vec![value],
        Operand::Switch { cases, .. } => cases.into_iter().map(|(value, _)| value).collect(),
        Operand::RangeSwitch { ranges, exact, .. } => ranges
            .into_iter()
            .flat_map(|(a, b, _)| [a, b])
            .chain(exact.into_iter().map(|(value, _)| value))
            .collect(),
        _ => Vec::new(),
    }
}

pub(super) fn compare_anonymous(
    expected: &memo::NormalizationContext<'_>,
    actual: &memo::NormalizationContext<'_>,
    out: &mut Collector,
    left: &BTreeMap<String, u32>,
    right: &BTreeMap<String, u32>,
) {
    let options = CompareOptions::default();
    for site in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        let a = left.get(site).copied();
        let b = right.get(site).copied();
        if a.is_some_and(|id| proc_path(expected, id).is_none())
            || b.is_some_and(|id| proc_path(actual, id).is_none())
        {
            match (a, b) {
                (Some(a), Some(b)) => compare_proc(
                    expected,
                    actual,
                    (a as usize, b as usize),
                    site,
                    &options,
                    false,
                    out,
                ),
                _ => out.check(
                    site,
                    "proc.anonymous_owner_presence",
                    a.is_some(),
                    b.is_some(),
                ),
            }
        }
    }
}
