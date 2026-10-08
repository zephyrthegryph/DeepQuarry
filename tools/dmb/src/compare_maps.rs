use super::*;

pub(super) fn map_instance(dmb: &Dmb, id: u32) -> Option<(u8, Option<Vec<u8>>, bool)> {
    dmb.instances.get(id as usize).map(|instance| {
        let class = if instance.kind == 8 {
            dmb.mobs.get(instance.class as usize).map(|mob| mob.class)
        } else {
            Some(instance.class)
        };
        (
            instance.kind,
            class.and_then(|id| path(dmb, id)),
            instance.initializer != 0xffff,
        )
    })
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum MapConstant {
    Value(NormalValue),
    List(Vec<Self>),
    Assoc(Vec<(Self, Self)>),
}

/// Decode only straight-line constant map override assignments. A procedure
/// with branches, calls, reads, or other effects is left to strict bytecode
/// comparison, since reordering those operations may change behavior.
pub(super) fn constant_map_assignments(
    dmb: &Dmb,
    proc_id: u32,
) -> Option<BTreeMap<Vec<u8>, MapConstant>> {
    let code = dmb.proc_code_words(proc_id as usize)?;
    let instructions = bytecode::decode(code).ok()?;
    let mut stack = Vec::<MapConstant>::new();
    let mut assignments = BTreeMap::new();
    for instruction in instructions {
        match instruction.opcode {
            0x84 | 0x85 => {}
            0x50 => stack.push(MapConstant::Value(NormalValue::Number(
                (instruction.operands.first().copied()? as u16 as f32).to_bits(),
            ))),
            0x60 => {
                let Operand::Value(raw) = instruction.typed_operands().ok()?.into_iter().next()?
                else {
                    return None;
                };
                // Nested modified types and hidden runtime initializer values
                // need graph-aware comparison. Avoid recursive cycles and keep
                // their owning initializer opaque instead of dropping identity.
                if matches!(
                    raw.kind(),
                    ValueKind::InstanceTypePath | ValueKind::HiddenInitializer
                ) {
                    return None;
                }
                stack.push(MapConstant::Value(value(dmb, raw)));
            }
            0x19 => stack.push(MapConstant::List(Vec::new())),
            0x1a | 0xc8 | 0x17c => {
                let count = instruction.operands.first().copied()? as usize;
                let width = if instruction.opcode == 0x1a { 1 } else { 2 };
                let start = stack.len().checked_sub(count.checked_mul(width)?)?;
                let entries = stack.split_off(start);
                if width == 1 {
                    stack.push(MapConstant::List(entries));
                } else {
                    stack.push(MapConstant::Assoc(
                        entries
                            .chunks_exact(2)
                            .map(|pair| (pair[0].clone(), pair[1].clone()))
                            .collect(),
                    ));
                }
            }
            0x34 => {
                let Operand::Variable(target) =
                    instruction.typed_operands().ok()?.into_iter().next()?
                else {
                    return None;
                };
                let mut target = target;
                let name = loop {
                    let Variable::SetCache(owner, field) = target else {
                        return None;
                    };
                    if *owner != Variable::Src {
                        return None;
                    }
                    match *field {
                        Variable::Field(name) => break name,
                        nested @ Variable::SetCache(_, _) => target = nested,
                        _ => return None,
                    }
                };
                assignments.insert(bytes(dmb, name)?, stack.pop()?);
            }
            0 | 0x12 if stack.is_empty() => {}
            _ => return None,
        }
    }
    stack.is_empty().then_some(assignments)
}

/// Diagnostic identity for an instance with only independent constant overrides.
/// This excludes allocation IDs and assignment order, but retains its type,
/// field names, values, and ordered list contents. Effectful initializers return
/// None rather than being treated as equivalent.
pub fn constant_instance_signature(dmb: &Dmb, instance_id: u32) -> Option<String> {
    let instance = dmb.instances.get(instance_id as usize)?;
    let assignments = constant_map_assignments(dmb, instance.initializer)?;
    Some(format!(
        "{:?}:{assignments:?}",
        map_instance(dmb, instance_id)?
    ))
}

/// Read-only diagnostic for a procedure containing independent constant stores.
/// Effectful or unrecognized initializer bodies retain an unknown signature.
pub fn constant_initializer_signature(dmb: &Dmb, proc_id: u32) -> Option<String> {
    Some(format!("{:?}", constant_map_assignments(dmb, proc_id)?))
}

#[allow(clippy::too_many_arguments)]
pub(super) fn compare_map_instance(
    expected: &Dmb,
    left: u32,
    actual: &Dmb,
    right: u32,
    name: &str,
    independent_constants: bool,
    seen: &mut BTreeSet<(u32, u32)>,
    out: &mut Collector,
) {
    out.check(
        name,
        "instance",
        map_instance(expected, left),
        map_instance(actual, right),
    );
    let (Some(a), Some(b)) = (
        expected.instances.get(left as usize),
        actual.instances.get(right as usize),
    ) else {
        return;
    };
    if a.initializer != 0xffff
        && b.initializer != 0xffff
        && seen.insert((a.initializer, b.initializer))
    {
        match (
            independent_constants.then(|| constant_map_assignments(expected, a.initializer)),
            independent_constants.then(|| constant_map_assignments(actual, b.initializer)),
        ) {
            (Some(Some(left)), Some(Some(right))) => out.check(
                &format!("{name}::<instance init>"),
                "constant_assignments",
                left,
                right,
            ),
            _ => compare_initializer(
                expected,
                a.initializer,
                actual,
                b.initializer,
                &format!("{name}::<instance init>"),
                &CompareOptions::default(),
                out,
            ),
        }
    }
}

/// Compare decoded map cells and objects by linear coordinate, resolving
/// instance and class IDs. Anonymous map override initializers are paired by
/// their first shared cell or object and compared once per procedure pair.
pub(super) fn compare_maps_mode(
    expected: &Dmb,
    actual: &Dmb,
    max_discrepancies: usize,
    independent_constants: bool,
) -> Vec<Discrepancy> {
    let mut out = Collector {
        output: Vec::new(),
        limit: max_discrepancies,
        report: None,
    };
    out.check("/map", "dimensions", expected.dimensions, actual.dimensions);
    let expand = |dmb: &Dmb| {
        dmb.grid
            .iter()
            .flat_map(|run| {
                std::iter::repeat_n((run.turf, run.area, run.contents), run.copies as usize)
            })
            .collect::<Vec<_>>()
    };
    let left = expand(expected);
    let right = expand(actual);
    out.check("/map", "cell_count", left.len(), right.len());
    let mut seen = BTreeSet::new();
    let coordinate = |index: usize| format!("/map/flat#{index}");
    for (index, (&a, &b)) in left.iter().zip(&right).enumerate() {
        if out.full() {
            break;
        }
        let name = coordinate(index);
        compare_map_instance(
            expected,
            a.0,
            actual,
            b.0,
            &format!("{name}/turf"),
            independent_constants,
            &mut seen,
            &mut out,
        );
        compare_map_instance(
            expected,
            a.1,
            actual,
            b.1,
            &format!("{name}/area"),
            independent_constants,
            &mut seen,
            &mut out,
        );
        out.check(&name, "contents_presence", a.2 != 0xffff, b.2 != 0xffff);
        if a.2 != 0xffff && b.2 != 0xffff {
            out.add(
                &name,
                "contents",
                "unverified nonempty list",
                "unverified nonempty list",
            );
        }
    }
    let objects = |dmb: &Dmb| {
        let mut at = 0usize;
        dmb.map_objects
            .iter()
            .map(|object| {
                at += usize::from(object.offset);
                (at, object.instance)
            })
            .collect::<Vec<_>>()
    };
    let left = objects(expected);
    let right = objects(actual);
    out.check("/map", "object_count", left.len(), right.len());
    if independent_constants {
        let grouped = |objects: Vec<(usize, u32)>, dmb: &Dmb| {
            let mut cells = BTreeMap::<usize, Vec<u32>>::new();
            for (cell, instance) in objects {
                cells.entry(cell).or_default().push(instance);
            }
            for instances in cells.values_mut() {
                instances.sort_by_key(|&id| map_instance(dmb, id));
            }
            cells
        };
        let left = grouped(left, expected);
        let right = grouped(right, actual);
        for cell in left
            .keys()
            .chain(right.keys())
            .copied()
            .collect::<BTreeSet<_>>()
        {
            if out.full() {
                break;
            }
            let a = left.get(&cell).map(Vec::as_slice).unwrap_or_default();
            let b = right.get(&cell).map(Vec::as_slice).unwrap_or_default();
            out.check(&coordinate(cell), "object_count", a.len(), b.len());
            for (index, (&a, &b)) in a.iter().zip(b).enumerate() {
                compare_map_instance(
                    expected,
                    a,
                    actual,
                    b,
                    &format!("{}/object[{index}]", coordinate(cell)),
                    true,
                    &mut seen,
                    &mut out,
                );
            }
        }
    } else {
        for (index, (&a, &b)) in left.iter().zip(&right).enumerate() {
            if out.full() {
                break;
            }
            out.check("/map", &format!("object[{index}].cell"), a.0, b.0);
            compare_map_instance(
                expected,
                a.1,
                actual,
                b.1,
                &format!("/map/object[{index}]"),
                false,
                &mut seen,
                &mut out,
            );
        }
    }
    out.output
}

/// Strictly compare map instance initializer metadata and bytecode order.
pub fn compare_maps(expected: &Dmb, actual: &Dmb, max_discrepancies: usize) -> Vec<Discrepancy> {
    compare_maps_mode(expected, actual, max_discrepancies, false)
}

/// Treat independent constant writes to distinct map fields as equivalent
/// regardless of instruction order. Complex initializers still compare
/// strictly, so this never hides calls, reads, or branches.
pub fn compare_maps_semantic(
    expected: &Dmb,
    actual: &Dmb,
    max_discrepancies: usize,
) -> Vec<Discrepancy> {
    compare_maps_mode(expected, actual, max_discrepancies, true)
}
