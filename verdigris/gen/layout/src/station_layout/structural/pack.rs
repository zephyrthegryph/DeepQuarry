use super::*;

pub(super) fn pack_architectural_department(
    plan: &mut LogicalPlan,
    department: &DepartmentRequest,
    block: DepartmentBlock,
    next_room_id: &mut u16,
    seed: u64,
) -> Result<(), LayoutError> {
    let horizontal_hall = matches!(block.frontage, BlockFrontage::East | BlockFrontage::West);
    let axis_offset =
        (hash64(seed ^ u64::from(department.id) ^ 0x6861_6c6c_5f61_7869) % 3) as i16 - 1;
    let mut hall_axis = if horizontal_hall {
        let margin = ((block.max_y - block.min_y) / 2).min(2);
        u16::try_from(
            (i16::try_from(block.min_y + (block.max_y - block.min_y) / 2).unwrap_or(0)
                + axis_offset)
                .clamp(
                    i16::try_from(block.min_y + margin).unwrap_or(0),
                    i16::try_from(block.max_y - margin).unwrap_or(0),
                ),
        )
        .unwrap_or(block.min_y + (block.max_y - block.min_y) / 2)
    } else {
        let margin = ((block.max_x - block.min_x) / 2).min(2);
        u16::try_from(
            (i16::try_from(block.min_x + (block.max_x - block.min_x) / 2).unwrap_or(0)
                + axis_offset)
                .clamp(
                    i16::try_from(block.min_x + margin).unwrap_or(0),
                    i16::try_from(block.max_x - margin).unwrap_or(0),
                ),
        )
        .unwrap_or(block.min_x + (block.max_x - block.min_x) / 2)
    };
    // A centered spine in a shallow department consumes the only depth that
    // can satisfy real authored rooms (for example a 7x3 reception), leaving
    // two-tile strips which only compact closets can occupy. Put the spine on
    // one edge of shallow blocks. The room bay then retains the full remaining
    // depth and later portal construction connects it without inventing a
    // second cross-corridor through the department.
    let shallow_axis_hash = hash64(seed ^ u64::from(department.id) ^ 0x7368_616c_6c6f_775f);
    if horizontal_hall && block.max_y - block.min_y < 6 {
        hall_axis = if shallow_axis_hash & 1 == 0 {
            block.min_y
        } else {
            block.max_y
        };
    } else if !horizontal_hall && block.max_x - block.min_x < 6 {
        hall_axis = if shallow_axis_hash & 1 == 0 {
            block.min_x
        } else {
            block.max_x
        };
    }
    // End-cap rooms need enough depth for a real authored activity cluster;
    // two logical cells routinely rasterized into the suite's tiny-room tail.
    let terminal_depth = 2u16;
    // A full-width terminal room blocks the department spine. Splitting that
    // end cap then strands all but one child room behind another room. Keep
    // the compact spine continuous and partition rooms along its sides.
    let use_terminal_room = false;
    let mut hall_min_x = block.min_x;
    let mut hall_max_x = block.max_x;
    let mut hall_min_y = block.min_y;
    let mut hall_max_y = block.max_y;
    let terminal = if use_terminal_room {
        match block.frontage {
            BlockFrontage::East => {
                hall_min_x = block.min_x + terminal_depth;
                Some((
                    block.min_x,
                    block.min_x + terminal_depth - 1,
                    block.min_y,
                    block.max_y,
                ))
            }
            BlockFrontage::West => {
                hall_max_x = block.max_x - terminal_depth;
                Some((
                    block.max_x - terminal_depth + 1,
                    block.max_x,
                    block.min_y,
                    block.max_y,
                ))
            }
            BlockFrontage::North => {
                hall_min_y = block.min_y + terminal_depth;
                Some((
                    block.min_x,
                    block.max_x,
                    block.min_y,
                    block.min_y + terminal_depth - 1,
                ))
            }
            BlockFrontage::South => {
                hall_max_y = block.max_y - terminal_depth;
                Some((
                    block.min_x,
                    block.max_x,
                    block.max_y - terminal_depth + 1,
                    block.max_y,
                ))
            }
        }
    } else {
        None
    };
    let center = CellPoint {
        x: if horizontal_hall {
            block.min_x + (block.max_x - block.min_x) / 2
        } else {
            hall_axis
        },
        y: if horizontal_hall {
            hall_axis
        } else {
            block.min_y + (block.max_y - block.min_y) / 2
        },
    };
    plan.department_centers.insert(department.id, center);

    for y in block.min_y..=block.max_y {
        for x in block.min_x..=block.max_x {
            let point = CellPoint { x, y };
            if ((horizontal_hall && y == hall_axis) || (!horizontal_hall && x == hall_axis))
                && x >= hall_min_x
                && x <= hall_max_x
                && y >= hall_min_y
                && y <= hall_max_y
                && plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
        }
    }
    // Shallow blocks need a two-module circulation band. With one row, the
    // remaining five modules rasterize to fourteen floor tiles—deeper than
    // any authored room envelope—and the splitter is forced to cut across
    // frontage. Two rows leave an eleven-tile-deep bay that can be divided
    // only along the hall while every resulting room retains direct frontage.
    if horizontal_hall && block.max_y - block.min_y < 6 {
        let inner_y = if hall_axis == block.min_y {
            hall_axis + 1
        } else {
            hall_axis - 1
        };
        for x in block.min_x..=block.max_x {
            let point = CellPoint { x, y: inner_y };
            if plan.get(point) != Space::Public {
                plan.set(point, Space::Common(department.id));
            }
        }
    } else if !horizontal_hall && block.max_x - block.min_x < 6 {
        let inner_x = if hall_axis == block.min_x {
            hall_axis + 1
        } else {
            hall_axis - 1
        };
        for y in block.min_y..=block.max_y {
            let point = CellPoint { x: inner_x, y };
            if plan.get(point) != Space::Public {
                plan.set(point, Space::Common(department.id));
            }
        }
    } else if horizontal_hall {
        for y in block.min_y + 4..=block.max_y.saturating_sub(4) {
            for x in block.min_x..=block.max_x {
                let point = CellPoint { x, y };
                if plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
            }
        }
    } else {
        for x in block.min_x + 4..=block.max_x.saturating_sub(4) {
            for y in block.min_y..=block.max_y {
                let point = CellPoint { x, y };
                if plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
            }
        }
    }

    // Do not pre-carve a perpendicular cross through every department. Room
    // frontage branches are derived after packing, from actual door demand;
    // carving them up front fragments otherwise valid authored envelopes.

    let mut variants = department
        .room_types
        .iter()
        .filter(|room| room.max_count > 0)
        .collect::<Vec<_>>();
    variants.sort_by_key(|room| {
        (
            room.name.clone(),
            Reverse(room.ideal_area.max(room.content_area)),
            room.id,
        )
    });
    variants.dedup_by(|left, right| left.name == right.name);
    if variants.is_empty() {
        return Err(LayoutError(format!(
            "department {} has no authored room programs",
            department.id
        )));
    }

    let mut zones = Vec::new();
    if horizontal_hall {
        if block.min_y < hall_axis {
            let count = 2;
            for (min_x, max_x) in
                partition_axis_weighted(hall_min_x, hall_max_x, count, seed ^ 0x6c)
            {
                zones.push((min_x, max_x, block.min_y, hall_axis - 1));
            }
        }
        if hall_axis < block.max_y {
            let count = 2;
            for (min_x, max_x) in
                partition_axis_weighted(hall_min_x, hall_max_x, count, seed ^ 0x72)
            {
                zones.push((min_x, max_x, hall_axis + 1, block.max_y));
            }
        }
    } else {
        if block.min_x < hall_axis {
            let count = 2;
            for (min_y, max_y) in
                partition_axis_weighted(hall_min_y, hall_max_y, count, seed ^ 0x6d)
            {
                zones.push((block.min_x, hall_axis - 1, min_y, max_y));
            }
        }
        if hall_axis < block.max_x {
            let count = 2;
            for (min_y, max_y) in
                partition_axis_weighted(hall_min_y, hall_max_y, count, seed ^ 0x75)
            {
                zones.push((hall_axis + 1, block.max_x, min_y, max_y));
            }
        }
    }
    if let Some((min_x, max_x, min_y, max_y)) = terminal {
        let width = max_x - min_x + 1;
        let height = max_y - min_y + 1;
        if width >= 8 && width > height {
            for (part_min, part_max) in
                partition_axis_weighted(min_x, max_x, 2, seed ^ 0x0074_6572_6d78)
            {
                zones.push((part_min, part_max, min_y, max_y));
            }
        } else if height >= 8 && height > width {
            for (part_min, part_max) in
                partition_axis_weighted(min_y, max_y, 2, seed ^ 0x0074_6572_6d79)
            {
                zones.push((min_x, max_x, part_min, part_max));
            }
        } else {
            zones.push((min_x, max_x, min_y, max_y));
        }
    }
    zones.retain(|(min_x, max_x, min_y, max_y)| min_x <= max_x && min_y <= max_y);
    // Split every rectangular bay until it fits an authored content envelope.
    // The former area-only assignment could label a 100-tile bay as a
    // 30-tile reception and leave the decorator no principled way to fill it.
    let mut room_shapes = Vec::new();
    let mut provisional_types = Vec::new();
    for (min_x, max_x, min_y, max_y) in zones {
        let shape = (min_y..=max_y)
            .flat_map(|y| (min_x..=max_x).map(move |x| CellPoint { x, y }))
            .filter(|point| plan.get(*point) == Space::Exterior)
            .collect::<BTreeSet<_>>();
        for component in connected_components(&shape, plan.width, plan.height) {
            let partitions = split_shape_for_authored_rooms(
                &component,
                &department.room_types,
                plan.width,
                plan.height,
                8,
                Some(horizontal_hall),
            )
            .or_else(|| {
                // Unusual clipped bays may not divide along the preferred
                // frontage axis. Split them normally, then let the minimal
                // branch pass connect only the resulting back room(s).
                split_shape_for_authored_rooms(
                    &component,
                    &department.room_types,
                    plan.width,
                    plan.height,
                    8,
                    None,
                )
            });
            let Some(partitions) = partitions else {
                return Err(LayoutError(format!(
                    "department {} has a bay that cannot fit even a compact authored room",
                    department.id
                )));
            };
            for (partition, provisional) in partitions {
                room_shapes.push(partition);
                provisional_types.push(provisional);
            }
        }
    }
    let required_room_count = department
        .room_types
        .iter()
        .fold(BTreeMap::<&str, usize>::new(), |mut counts, room| {
            counts
                .entry(room.name.as_str())
                .and_modify(|count| *count = (*count).max(usize::from(room.min_count)))
                .or_insert(usize::from(room.min_count));
            counts
        })
        .values()
        .sum::<usize>();
    let available_semantics = department
        .room_types
        .iter()
        .map(|room| room.name.as_str())
        .collect::<BTreeSet<_>>()
        .len();
    let minimum_room_count = required_room_count.max(available_semantics.min(3));
    while room_shapes.len() < minimum_room_count {
        let candidate = (0..room_shapes.len())
            .filter_map(|index| {
                force_split_authored_shape(
                    &room_shapes[index],
                    &department.room_types,
                    plan.width,
                    plan.height,
                    Some(horizontal_hall),
                )
                .map(|replacement| (index, replacement))
            })
            .max_by_key(|(index, _)| projected_room_tile_area(&room_shapes[*index]));
        let Some((index, replacement)) = candidate else {
            break;
        };
        room_shapes.remove(index);
        provisional_types.remove(index);
        for (shape, provisional) in replacement {
            room_shapes.push(shape);
            provisional_types.push(provisional);
        }
    }
    // A collection of individually valid bays can still be impossible to
    // assign as a whole (for example, too many large bays that only the
    // department's anchor program can occupy). Keep partitioning the largest
    // splittable bay until the complete authored-program assignment succeeds.
    // This makes feasibility a construction invariant rather than a late
    // validation failure.
    let matched_types = loop {
        if let Some(matched) =
            match_room_variants_to_shapes(department, &provisional_types, &room_shapes)
        {
            break matched;
        }
        let candidate = (0..room_shapes.len())
            .filter_map(|index| {
                force_split_authored_shape(
                    &room_shapes[index],
                    &department.room_types,
                    plan.width,
                    plan.height,
                    Some(horizontal_hall),
                )
                .map(|replacement| (index, replacement))
            })
            .max_by_key(|(index, _)| projected_room_tile_area(&room_shapes[*index]));
        let Some((index, replacement)) = candidate else {
            let geometry = room_shapes
                .iter()
                .map(|shape| {
                    let (width, height) = projected_room_dimensions(shape);
                    format!("{}:{}x{}", projected_room_tile_area(shape), width, height)
                })
                .collect::<Vec<_>>()
                .join(",");
            let required = department
                .room_types
                .iter()
                .filter(|room| room.min_count > 0)
                .map(|room| format!("{}:{}@{}", room.name, room.min_count, room.id))
                .collect::<Vec<_>>()
                .join(",");
            return Err(LayoutError(format!(
                "department {} block {}x{} {:?} cannot assign required authored programs [{required}] to room geometry [{geometry}]",
                department.id,
                block.max_x - block.min_x + 1,
                block.max_y - block.min_y + 1,
                block.frontage,
            )));
        };
        room_shapes.remove(index);
        provisional_types.remove(index);
        for (shape, provisional) in replacement {
            room_shapes.push(shape);
            provisional_types.push(provisional);
        }
    };

    for (room_type, shape) in matched_types.into_iter().zip(room_shapes) {
        let room_id = *next_room_id;
        *next_room_id = next_room_id
            .checked_add(1)
            .ok_or_else(|| LayoutError("station contains too many rooms".into()))?;
        for point in shape {
            if plan.get(point) != Space::Public {
                plan.set(
                    point,
                    Space::Room {
                        department: department.id,
                        room: room_id,
                    },
                );
            }
        }
        plan.rooms.push(RoomPlan {
            id: room_id,
            department: department.id,
            room_type: room_type.clone(),
        });
    }
    Ok(())
}

pub(super) fn partition_axis_weighted(
    minimum: u16,
    maximum: u16,
    desired: usize,
    seed: u64,
) -> Vec<(u16, u16)> {
    let length = usize::from(maximum - minimum + 1);
    let count = desired.min((length / 2).max(1));
    let mut sizes = vec![2usize; count];
    let mut remaining = length.saturating_sub(count * 2);
    let mut cursor = hash64(seed) as usize;
    while remaining > 0 {
        let index = cursor % count;
        sizes[index] += 1;
        cursor = hash64(cursor as u64 ^ seed) as usize;
        remaining -= 1;
    }
    let mut result = Vec::with_capacity(count);
    let mut start = minimum;
    for size in sizes {
        let end = (start + size as u16 - 1).min(maximum);
        result.push((start, end));
        start = end.saturating_add(1);
    }
    result
}

pub(super) fn hash64(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

pub(super) fn minimum_spanning_tree(points: &[CellPoint], rng: &mut Rng) -> Vec<(usize, usize)> {
    let mut reached = BTreeSet::from([0usize]);
    let mut edges = Vec::new();
    while reached.len() < points.len() {
        let mut choices = Vec::new();
        for &left in &reached {
            for right in 0..points.len() {
                if !reached.contains(&right) {
                    choices.push((
                        cell_distance(points[left], points[right]),
                        rng.next(),
                        left,
                        right,
                    ));
                }
            }
        }
        choices.sort();
        let (_, _, left, right) = choices[0];
        reached.insert(right);
        edges.push((left, right));
    }
    edges
}

/// Turns surplus departmental concourse into the station's service network.
/// Growth is monotonic from existing maintenance, so it cannot create an
/// isolated maintenance pocket. A cell is surrendered only if local
/// circulation remains one connected component, still reaches the public hall,
/// and every room retains at least one local-hall frontage.
/// Replace broad anonymous department floor with the smallest connected local
/// circulation tree that reaches the public hall and every room. Any omitted
/// module is returned for assignment to a real authored micro room.
pub(super) fn match_room_variants_to_shapes<'a>(
    department: &'a super::super::model::DepartmentRequest,
    selected: &[&'a RoomType],
    shapes: &[BTreeSet<CellPoint>],
) -> Option<Vec<&'a RoomType>> {
    if selected.len() != shapes.len() {
        return None;
    }
    let mut candidates = shapes
        .iter()
        .enumerate()
        .map(|(shape_index, shape)| {
            let mut variants = department
                .room_types
                .iter()
                .filter(|variant| room_shape_fits(variant, shape))
                .collect::<Vec<_>>();
            variants.sort_by_key(|variant| {
                (
                    variant.name != selected[shape_index].name,
                    room_shape_score(variant, shape),
                    variant.id,
                )
            });
            (shape_index, variants)
        })
        .collect::<Vec<_>>();
    if candidates.iter().any(|(_, variants)| variants.is_empty()) {
        return None;
    }
    candidates.sort_by_key(|(shape_index, variants)| {
        (
            variants.len(),
            Reverse(projected_room_tile_area(&shapes[*shape_index])),
            *shape_index,
        )
    });

    // Minimum counts are a contract on an exact authored variant, not merely
    // on its semantic family. A compact "surgery" room must not satisfy the
    // catalog's required full surgery suite.
    let mut required_slots = department
        .room_types
        .iter()
        .flat_map(|room| {
            std::iter::repeat_n(
                (room.name.as_str(), Some(room.id)),
                usize::from(room.min_count),
            )
        })
        .collect::<Vec<_>>();
    let minimum_semantic_variety = department
        .room_types
        .iter()
        .map(|room| room.name.as_str())
        .collect::<BTreeSet<_>>()
        .len()
        .min(3)
        .min(shapes.len());
    for semantic in selected
        .iter()
        .map(|room| room.name.as_str())
        .chain(department.room_types.iter().map(|room| room.name.as_str()))
    {
        if required_slots
            .iter()
            .map(|(semantic, _)| *semantic)
            .collect::<BTreeSet<_>>()
            .len()
            >= minimum_semantic_variety
        {
            break;
        }
        if !required_slots
            .iter()
            .any(|(required_semantic, _)| *required_semantic == semantic)
            && candidates
                .iter()
                .any(|(_, variants)| variants.iter().any(|room| room.name == semantic))
        {
            required_slots.push((semantic, None));
        }
    }
    required_slots.sort_by_key(|(semantic, required_id)| {
        candidates
            .iter()
            .filter(|(_, variants)| {
                variants.iter().any(|room| {
                    room.name == *semantic
                        && required_id.is_none_or(|required_id| room.id == required_id)
                })
            })
            .count()
    });

    let mut result = vec![None; shapes.len()];
    let mut counts = BTreeMap::new();
    let slot_candidates = required_slots
        .iter()
        .map(|(semantic, required_id)| {
            let mut choices = candidates
                .iter()
                .flat_map(|(shape_index, variants)| {
                    variants
                        .iter()
                        .filter(|room| {
                            room.name == *semantic
                                && required_id.is_none_or(|required_id| room.id == required_id)
                        })
                        .map(move |room| (*shape_index, *room))
                })
                .collect::<Vec<_>>();
            choices.sort_by_key(|(shape_index, room)| {
                (
                    room_shape_score(room, &shapes[*shape_index]),
                    *shape_index,
                    room.id,
                )
            });
            choices
        })
        .collect::<Vec<_>>();
    if slot_candidates.iter().any(Vec::is_empty) {
        return None;
    }
    let mut slot_order = (0..required_slots.len()).collect::<Vec<_>>();
    slot_order.sort_by_key(|slot| slot_candidates[*slot].len());
    let mut shape_owner = vec![None; shapes.len()];
    let mut chosen_variant = vec![None; required_slots.len()];
    fn augment_required<'a>(
        slot: usize,
        slot_candidates: &[Vec<(usize, &'a RoomType)>],
        shape_owner: &mut [Option<usize>],
        chosen_variant: &mut [Option<&'a RoomType>],
        visited_shapes: &mut [bool],
    ) -> bool {
        for &(shape, variant) in &slot_candidates[slot] {
            if visited_shapes[shape] {
                continue;
            }
            visited_shapes[shape] = true;
            if shape_owner[shape].is_none()
                || augment_required(
                    shape_owner[shape]
                        .expect("invariant: `||` short-circuit means this arm only runs when the left `is_none()` was false"),
                    slot_candidates,
                    shape_owner,
                    chosen_variant,
                    visited_shapes,
                )
            {
                shape_owner[shape] = Some(slot);
                chosen_variant[slot] = Some(variant);
                return true;
            }
        }
        false
    }
    for slot in slot_order {
        if !augment_required(
            slot,
            &slot_candidates,
            &mut shape_owner,
            &mut chosen_variant,
            &mut vec![false; shapes.len()],
        ) {
            return None;
        }
    }
    for (shape, slot) in shape_owner.into_iter().enumerate() {
        if let Some(slot) = slot {
            let variant = chosen_variant[slot]?;
            result[shape] = Some(variant);
            *counts.entry(variant.id).or_default() += 1;
        }
    }
    let mut semantic_counts = BTreeMap::<&str, usize>::new();
    for room in result.iter().flatten() {
        *semantic_counts.entry(room.name.as_str()).or_default() += 1;
    }
    for (shape_index, variants) in &candidates {
        if result[*shape_index].is_some() {
            continue;
        }
        let variant = variants
            .iter()
            .copied()
            .filter(|variant| {
                let limit = if variant.min_short_side <= 1 {
                    candidates.len()
                } else {
                    usize::from(variant.max_count)
                };
                counts.get(&variant.id).copied().unwrap_or(0) < limit
            })
            .min_by_key(|variant| {
                (
                    semantic_counts
                        .get(variant.name.as_str())
                        .copied()
                        .unwrap_or(0),
                    room_shape_score(variant, &shapes[*shape_index]),
                    variant.id,
                )
            })?;
        result[*shape_index] = Some(variant);
        *counts.entry(variant.id).or_default() += 1;
        *semantic_counts.entry(variant.name.as_str()).or_default() += 1;
    }
    Some(result.into_iter().map(Option::unwrap).collect())
}
