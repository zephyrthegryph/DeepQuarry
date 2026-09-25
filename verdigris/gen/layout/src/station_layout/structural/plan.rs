use super::*;

pub(super) fn build_logical_plan(request: &LayoutRequest) -> Result<LogicalPlan, LayoutError> {
    build_architectural_plan(request)
}

pub(super) fn build_architectural_plan(request: &LayoutRequest) -> Result<LogicalPlan, LayoutError> {
    let canvas_width = (request.settings.width - 3) / PITCH;
    let canvas_height = (request.settings.height - 3) / PITCH;
    let available_side = canvas_width.min(canvas_height);
    if available_side < 25 {
        return Err(LayoutError(format!(
            "architectural station canvas requires at least {} physical tiles per side",
            25 * PITCH + 3
        )));
    }
    let side = available_side.min(29);
    let span = side * PITCH + 1;
    let origin = Point {
        x: (request.settings.width - span) / 2,
        y: (request.settings.height - span) / 2,
    };
    let mut plan = LogicalPlan {
        width: side,
        height: side,
        origin,
        cells: vec![Space::Exterior; usize::from(side).pow(2)],
        rooms: Vec::new(),
        portals: Vec::new(),
        maintenance_barriers: BTreeSet::new(),
        department_centers: BTreeMap::new(),
        department_edges: Vec::new(),
    };
    let center_x = side / 2;
    let center_y = side / 2;
    // Keep a recognizable station grammar without making every seed the same
    // four-wing cross.  The two offset-spine orientations are deliberately more
    // common than the cross, matching the asymmetric circulation of authored maps.
    let circulation_grammar = 1 + (hash64(request.settings.seed ^ 0x6d61_6372_6f5f_6772) % 2) as u8;
    let bent_spine = true;
    let transpose_bent_spine = circulation_grammar == 2;
    let upper_spine_x = center_x.saturating_sub(3);
    let lower_spine_x = center_x + 3;
    let jog_start = 3;
    let jog_end = upper_spine_x.saturating_sub(2).max(jog_start + 2);
    let jog_axis = if hash64(request.settings.seed ^ 0x636f_7272_6964_6f72) & 1 == 1 {
        center_y + 1
    } else {
        center_y - 1
    };
    for point in plan.points().collect::<Vec<_>>() {
        if point.x == 0 || point.y == 0 || point.x + 1 == side || point.y + 1 == side {
            plan.set(point, Space::Exterior);
        } else if (if bent_spine {
            if transpose_bent_spine {
                ((point.x == center_x
                    && point.y >= 2
                    && point.y + 2 < side
                    && !(point.y > jog_start && point.y < jog_end))
                    || (point.x == jog_axis && point.y >= jog_start && point.y <= jog_end)
                    || ((point.y == jog_start || point.y == jog_end)
                        && point.x >= center_x.min(jog_axis)
                        && point.x <= center_x.max(jog_axis)))
                    || (point.y == upper_spine_x && point.x >= 2 && point.x <= center_x)
                    || (point.y == lower_spine_x && point.x >= center_x && point.x + 2 < side)
            } else {
                ((point.y == center_y
                    && point.x >= 2
                    && point.x + 2 < side
                    && !(point.x > jog_start && point.x < jog_end))
                    || (point.y == jog_axis && point.x >= jog_start && point.x <= jog_end)
                    || ((point.x == jog_start || point.x == jog_end)
                        && point.y >= center_y.min(jog_axis)
                        && point.y <= center_y.max(jog_axis)))
                    || (point.x == upper_spine_x && point.y >= 2 && point.y <= center_y)
                    || (point.x == lower_spine_x && point.y >= center_y && point.y + 2 < side)
            }
        } else {
            point.x == center_x || point.y == center_y
        }) && point.x >= 2
            && point.y >= 2
            && point.x + 2 < side
            && point.y + 2 < side
        {
            plan.set(point, Space::Public);
        }
    }

    let low_min = 2;
    let low_max_x = center_x - 1;
    let high_min_x = center_x + 1;
    let low_max_y = center_y - 1;
    let high_min_y = center_y + 1;
    let high_max = side - 3;
    let mut quadrant_specs = vec![
        (
            low_min,
            low_max_x,
            high_min_y,
            high_max,
            BlockFrontage::South,
        ),
        (
            high_min_x,
            high_max,
            high_min_y,
            high_max,
            BlockFrontage::South,
        ),
        (low_min, low_max_x, low_min, low_max_y, BlockFrontage::North),
        (
            high_min_x,
            high_max,
            low_min,
            low_max_y,
            BlockFrontage::North,
        ),
    ];
    let mut rng = Rng::new(request.settings.seed);
    for index in (1..quadrant_specs.len()).rev() {
        let other = rng.choose(index + 1);
        quadrant_specs.swap(index, other);
    }
    let mut counts = [2usize, 2, 2, 1];
    if rng.choose(2) == 1 {
        counts.rotate_left(1);
    }
    let mut blocks = Vec::new();
    for ((min_x, max_x, min_y, max_y, horizontal_frontage), count) in
        quadrant_specs.into_iter().zip(counts)
    {
        let use_horizontal = rng.choose(2) == 0;
        if count == 1 {
            blocks.push(DepartmentBlock {
                min_x,
                max_x,
                min_y,
                max_y,
                frontage: if use_horizontal {
                    horizontal_frontage
                } else if max_x < center_x {
                    BlockFrontage::East
                } else {
                    BlockFrontage::West
                },
            });
            continue;
        }
        if use_horizontal {
            let midpoint = i16::try_from(min_x + (max_x - min_x) / 2).unwrap_or(0);
            let margin = ((max_x - min_x).saturating_sub(2) / 2).min(5);
            // Coordinates are station-grid sized (far below i16::MAX), but
            // fall back to the unclamped midpoint rather than panic if a
            // future caller ever passes near-u16::MAX bounds.
            let lo = i16::try_from(min_x + margin).unwrap_or(midpoint);
            let hi = i16::try_from(max_x - margin).unwrap_or(midpoint);
            let separator = u16::try_from((midpoint + rng.signed(1)).clamp(lo.min(hi), lo.max(hi)))
                .unwrap_or(min_x + (max_x - min_x) / 2);
            blocks.push(DepartmentBlock {
                min_x,
                max_x: separator - 1,
                min_y,
                max_y,
                frontage: horizontal_frontage,
            });
            blocks.push(DepartmentBlock {
                min_x: separator + 1,
                max_x,
                min_y,
                max_y,
                frontage: horizontal_frontage,
            });
        } else {
            let midpoint = i16::try_from(min_y + (max_y - min_y) / 2).unwrap_or(0);
            let margin = ((max_y - min_y).saturating_sub(2) / 2).min(5);
            // See the horizontal branch above: fall back rather than panic.
            let lo = i16::try_from(min_y + margin).unwrap_or(midpoint);
            let hi = i16::try_from(max_y - margin).unwrap_or(midpoint);
            let separator = u16::try_from((midpoint + rng.signed(1)).clamp(lo.min(hi), lo.max(hi)))
                .unwrap_or(min_y + (max_y - min_y) / 2);
            let vertical_frontage = if max_x < center_x {
                BlockFrontage::East
            } else {
                BlockFrontage::West
            };
            blocks.push(DepartmentBlock {
                min_x,
                max_x,
                min_y,
                max_y: separator - 1,
                frontage: vertical_frontage,
            });
            blocks.push(DepartmentBlock {
                min_x,
                max_x,
                min_y: separator + 1,
                max_y,
                frontage: vertical_frontage,
            });
        }
    }
    if bent_spine {
        blocks =
            bent_spine_department_blocks(side, center_y, upper_spine_x, lower_spine_x, &mut rng);
        if transpose_bent_spine {
            blocks = blocks.into_iter().map(transpose_department_block).collect();
        }
    }
    blocks.truncate(request.departments.len());
    if blocks.len() != request.departments.len() {
        return Err(LayoutError(
            "architectural grammar could not allocate every department".into(),
        ));
    }
    let mut next_room_id = 1u16;
    // Match program demand to usable territory. Randomly shuffling departments
    // into rectangles made tiny programs inherit huge wings and forced the
    // room allocator to repeat roles merely to consume the excess.
    blocks.sort_by_key(|block| {
        (
            Reverse(
                u32::from(block.max_x - block.min_x + 1) * u32::from(block.max_y - block.min_y + 1),
            ),
            hash64(
                request.settings.seed
                    ^ u64::from(block.min_x).rotate_left(13)
                    ^ u64::from(block.min_y).rotate_left(29),
            ),
        )
    });
    let mut departments = request.departments.iter().collect::<Vec<_>>();
    // Preserve capacity matching while varying equally sized wings. Stable
    // sorting alone assigned the same six major departments to the same six
    // blocks for every seed, making the adjacency graph canonical despite
    // visibly different outlines.
    departments.sort_by_key(|department| {
        (
            Reverse(department.desired_area),
            hash64(request.settings.seed ^ u64::from(department.id)),
        )
    });
    for (department, block) in departments.into_iter().zip(blocks) {
        let block = shape_department_block(block, request.settings.seed, department.id);
        pack_architectural_department(
            &mut plan,
            department,
            block,
            &mut next_room_id,
            request.settings.seed,
        )?;
    }
    consolidate_optional_tiny_rooms(&mut plan, request);
    validate_room_envelopes(&plan, "department packing")?;
    add_secondary_public_crosslinks(&mut plan, request.settings.seed);
    validate_room_envelopes(&plan, "public crosslinks")?;
    articulate_department_suites(&mut plan, request.settings.seed);
    validate_room_envelopes(&plan, "suite articulation")?;
    trim_public_dead_ends(&mut plan);
    validate_room_envelopes(&plan, "public trimming")?;
    derive_maintenance_service_space(&mut plan);
    validate_room_envelopes(&plan, "maintenance derivation")?;
    connect_service_pockets(&mut plan)?;
    validate_room_envelopes(&plan, "service connection")?;
    repair_disconnected_room_ownership(&mut plan)?;
    validate_room_envelopes(&plan, "disconnected-room repair")?;
    extend_common_halls_to_every_room(&mut plan)?;
    validate_room_envelopes(&plan, "minimal hall branches")?;
    assign_portals(&mut plan, request)?;
    ensure_maintenance_component_portals(&mut plan)?;
    derive_department_transit_graph(&mut plan, request.settings.seed);
    validate_logical_plan(&plan, request)?;
    Ok(plan)
}

/// Describe the physical department arrangement, rather than emitting an
/// empty/canonical dependency graph. The graph is a minimum spanning tree over
/// actual suite centers; seed ordering only resolves equally good links.
pub(super) fn derive_department_transit_graph(plan: &mut LogicalPlan, seed: u64) {
    let centers = plan
        .department_centers
        .iter()
        .map(|(id, center)| (*id, *center))
        .collect::<Vec<_>>();
    if centers.len() < 2 {
        plan.department_edges.clear();
        return;
    }
    let points = centers
        .iter()
        .map(|(_, center)| *center)
        .collect::<Vec<_>>();
    let mut rng = Rng::new(seed ^ 0x7472_616e_7369_745f);
    plan.department_edges = minimum_spanning_tree(&points, &mut rng)
        .into_iter()
        .map(|(left, right)| (centers[left].0, centers[right].0))
        .collect();
}

/// Compact catalog variants are useful for genuine closets, but recursive bay
/// splitting must not turn them into the dominant station grammar.  Fold an
/// optional tiny partition into an adjacent authored room whenever their union
/// has a valid envelope. Required semantic rooms are never removed.
pub(super) fn consolidate_optional_tiny_rooms(plan: &mut LogicalPlan, request: &LayoutRequest) {
    loop {
        let mut changed = false;
        let room_ids = plan.rooms.iter().map(|room| room.id).collect::<Vec<_>>();
        for room_id in room_ids {
            let Some(room_index) = plan.rooms.iter().position(|room| room.id == room_id) else {
                continue;
            };
            let room = plan.rooms[room_index].clone();
            let cells = plan
                .points()
                .filter(|point| plan.get(*point).room() == Some(room_id))
                .collect::<BTreeSet<_>>();
            if projected_room_tile_area(&cells) > 16 {
                continue;
            }
            let Some(department) = request
                .departments
                .iter()
                .find(|department| department.id == room.department)
            else {
                continue;
            };
            let semantic_count = plan
                .rooms
                .iter()
                .filter(|candidate| {
                    candidate.department == room.department
                        && candidate.room_type.name == room.room_type.name
                })
                .count();
            let exact_count = plan
                .rooms
                .iter()
                .filter(|candidate| {
                    candidate.department == room.department
                        && candidate.room_type.id == room.room_type.id
                })
                .count();
            if exact_count <= usize::from(room.room_type.min_count) {
                continue;
            }
            let required_count = department
                .room_types
                .iter()
                .filter(|variant| variant.name == room.room_type.name)
                .map(|variant| usize::from(variant.min_count))
                .max()
                .unwrap_or(0);
            if semantic_count <= required_count {
                continue;
            }
            let adjacent_ids = cells
                .iter()
                .flat_map(|point| plan.neighbors(*point))
                .filter_map(|point| plan.get(point).room())
                .filter(|other_id| *other_id != room_id)
                .collect::<BTreeSet<_>>();
            let replacement = adjacent_ids
                .into_iter()
                .filter_map(|other_id| {
                    let other_index = plan.rooms.iter().position(|other| {
                        other.id == other_id && other.department == room.department
                    })?;
                    let mut combined = cells.clone();
                    combined.extend(
                        plan.points()
                            .filter(|point| plan.get(*point).room() == Some(other_id)),
                    );
                    department
                        .room_types
                        .iter()
                        .filter(|variant| variant.name == plan.rooms[other_index].room_type.name)
                        .filter(|variant| room_shape_fits(variant, &combined))
                        .min_by_key(|variant| room_shape_score(variant, &combined))
                        .map(|variant| (other_id, other_index, combined, variant.clone()))
                })
                .min_by_key(|(_, _, combined, variant)| room_shape_score(variant, combined));
            let Some((other_id, other_index, combined, variant)) = replacement else {
                // The partition has real hallway frontage but cannot combine
                // with a neighbor without violating that neighbor's authored
                // envelope. It is circulation alcove, not a pretend 2x2 room.
                for point in cells {
                    plan.set(point, Space::Common(room.department));
                }
                plan.rooms.remove(room_index);
                changed = true;
                break;
            };
            for point in combined {
                plan.set(
                    point,
                    Space::Room {
                        department: room.department,
                        room: other_id,
                    },
                );
            }
            plan.rooms[other_index].room_type = variant;
            plan.rooms.remove(room_index);
            changed = true;
            break;
        }
        if !changed {
            break;
        }
    }
}

pub(super) fn validate_room_envelopes(plan: &LogicalPlan, stage: &str) -> Result<(), LayoutError> {
    for planned_room in &plan.rooms {
        let cells = plan
            .points()
            .filter(|point| {
                plan.get(*point)
                    == (Space::Room {
                        department: planned_room.department,
                        room: planned_room.id,
                    })
            })
            .collect::<BTreeSet<_>>();
        if !room_shape_within_maximum(&planned_room.room_type, &cells) {
            return Err(LayoutError(format!(
                "{stage}: room {} violates its selected authored envelope (area {}, minimum {}, ideal {}, variant {})",
                planned_room.id,
                projected_room_tile_area(&cells),
                room_minimum_area(&planned_room.room_type),
                planned_room.room_type.ideal_area,
                planned_room.room_type.id,
            )));
        }
    }
    Ok(())
}

pub(super) fn add_secondary_public_crosslinks(plan: &mut LogicalPlan, seed: u64) {
    const REACH: u16 = 3;
    let common_in_direction =
        |plan: &LogicalPlan, point: CellPoint, dx: i16, dy: i16| -> Option<u16> {
            for distance in 1..=REACH {
                let x = i32::from(point.x) + i32::from(dx) * i32::from(distance);
                let y = i32::from(point.y) + i32::from(dy) * i32::from(distance);
                if x < 0 || y < 0 || x >= i32::from(plan.width) || y >= i32::from(plan.height) {
                    break;
                }
                match plan.get(CellPoint {
                    x: u16::try_from(x).ok()?,
                    y: u16::try_from(y).ok()?,
                }) {
                    Space::Common(department) => return Some(department),
                    Space::Exterior => {}
                    _ => break,
                }
            }
            None
        };
    let candidates = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Exterior)
        .filter(|point| {
            common_in_direction(plan, *point, -1, 0)
                .zip(common_in_direction(plan, *point, 1, 0))
                .is_some_and(|(left, right)| left != right)
                || common_in_direction(plan, *point, 0, -1)
                    .zip(common_in_direction(plan, *point, 0, 1))
                    .is_some_and(|(bottom, top)| bottom != top)
        })
        .collect::<BTreeSet<_>>();
    let mut links = connected_components(&candidates, plan.width, plan.height)
        .into_iter()
        .filter(|component| component.len() <= usize::from(REACH))
        .collect::<Vec<_>>();
    links.sort_by_key(|component| {
        component
            .iter()
            .map(|point| hash_cell(seed ^ 0x6372_6f73_736c_696e, *point))
            .min()
            .unwrap_or(u64::MAX)
    });
    let target = 2 + usize::try_from(seed & 1).unwrap_or(0);
    for link in links.into_iter().take(target) {
        for point in link {
            plan.set(point, Space::Public);
        }
    }
}

pub(super) fn articulate_department_suites(plan: &mut LogicalPlan, seed: u64) {
    let departments = plan
        .rooms
        .iter()
        .map(|room| room.department)
        .collect::<BTreeSet<_>>();
    for department in departments {
        let room_ids = plan
            .rooms
            .iter()
            .filter(|room| room.department == department)
            .map(|room| room.id)
            .collect::<BTreeSet<_>>();
        let vestibule_target = (room_ids.len() / 4).max(1);
        let mut articulated = BTreeSet::new();
        let mut vestibules = plan
            .points()
            .filter_map(|point| {
                let Space::Room {
                    department: owner,
                    room,
                } = plan.get(point)
                else {
                    return None;
                };
                if owner != department {
                    return None;
                }
                plan.neighbors(point)
                    .any(|neighbor| plan.get(neighbor) == Space::Common(department))
                    .then_some((point, room))
            })
            .collect::<Vec<_>>();
        vestibules.sort_by_key(|(point, room)| {
            hash_cell(seed ^ 0x7665_7374_6962_756c ^ u64::from(*room), *point)
        });
        for (point, room) in vestibules {
            if articulated.contains(&room) {
                continue;
            }
            let remaining = plan
                .points()
                .filter(|candidate| {
                    *candidate != point
                        && matches!(
                            plan.get(*candidate),
                            Space::Room {
                                department: owner,
                                room: candidate_room,
                            } if owner == department && candidate_room == room
                        )
                })
                .collect::<BTreeSet<_>>();
            if remaining.len() < 4 || !cells_connected(&remaining, plan.width, plan.height) {
                continue;
            }
            let Some(contract) = plan
                .rooms
                .iter()
                .find(|planned| planned.id == room)
                .map(|planned| &planned.room_type)
            else {
                continue;
            };
            if !room_shape_fits(contract, &remaining) {
                continue;
            }
            plan.set(point, Space::Common(department));
            articulated.insert(room);
            if articulated.len() >= vestibule_target {
                break;
            }
        }
    }
}

pub(super) fn transpose_department_block(block: DepartmentBlock) -> DepartmentBlock {
    DepartmentBlock {
        min_x: block.min_y,
        max_x: block.max_y,
        min_y: block.min_x,
        max_y: block.max_x,
        frontage: match block.frontage {
            BlockFrontage::East => BlockFrontage::North,
            BlockFrontage::West => BlockFrontage::South,
            BlockFrontage::North => BlockFrontage::East,
            BlockFrontage::South => BlockFrontage::West,
        },
    }
}

pub(super) fn bent_spine_department_blocks(
    side: u16,
    center_y: u16,
    upper_spine_x: u16,
    lower_spine_x: u16,
    rng: &mut Rng,
) -> Vec<DepartmentBlock> {
    let min = 2;
    let max = side - 3;
    let upper_min_y = min;
    let upper_max_y = center_y - 1;
    let upper_separator = upper_min_y + (upper_max_y - upper_min_y) / 2;
    let mut blocks = vec![
        DepartmentBlock {
            min_x: min,
            max_x: upper_spine_x - 1,
            min_y: upper_min_y,
            max_y: upper_separator - 1,
            frontage: BlockFrontage::East,
        },
        DepartmentBlock {
            min_x: min,
            max_x: upper_spine_x - 1,
            min_y: upper_separator + 1,
            max_y: upper_max_y,
            frontage: BlockFrontage::East,
        },
        DepartmentBlock {
            min_x: upper_spine_x + 1,
            max_x: max,
            min_y: upper_min_y,
            max_y: upper_separator - 1,
            frontage: BlockFrontage::West,
        },
        DepartmentBlock {
            min_x: upper_spine_x + 1,
            max_x: max,
            min_y: upper_separator + 1,
            max_y: upper_max_y,
            frontage: BlockFrontage::West,
        },
    ];
    let lower_min_y = center_y + 1;
    let lower_max_y = max;
    let lower_separator = lower_min_y + (lower_max_y - lower_min_y) / 2;
    let split_left = rng.choose(2) == 0;
    let (split_min_x, split_max_x, split_frontage, single_min_x, single_max_x, single_frontage) =
        if split_left {
            (
                min,
                lower_spine_x - 1,
                BlockFrontage::East,
                lower_spine_x + 1,
                max,
                BlockFrontage::West,
            )
        } else {
            (
                lower_spine_x + 1,
                max,
                BlockFrontage::West,
                min,
                lower_spine_x - 1,
                BlockFrontage::East,
            )
        };
    blocks.push(DepartmentBlock {
        min_x: split_min_x,
        max_x: split_max_x,
        min_y: lower_min_y,
        max_y: lower_separator - 1,
        frontage: split_frontage,
    });
    blocks.push(DepartmentBlock {
        min_x: split_min_x,
        max_x: split_max_x,
        min_y: lower_separator + 1,
        max_y: lower_max_y,
        frontage: split_frontage,
    });
    blocks.push(DepartmentBlock {
        min_x: single_min_x,
        max_x: single_max_x,
        min_y: lower_min_y,
        max_y: lower_max_y,
        frontage: single_frontage,
    });
    blocks
}

pub(super) fn trim_public_dead_ends(plan: &mut LogicalPlan) {
    loop {
        let removable = plan.points().find(|point| {
            if plan.get(*point) != Space::Public {
                return false;
            }
            let neighbors = plan.neighbors(*point).collect::<Vec<_>>();
            let public_neighbors = neighbors
                .iter()
                .filter(|neighbor| plan.get(**neighbor) == Space::Public)
                .count();
            let serves_department = neighbors.iter().any(|neighbor| {
                matches!(plan.get(*neighbor), Space::Common(_) | Space::Room { .. })
            });
            public_neighbors <= 1 && !serves_department
        });
        let Some(point) = removable else {
            break;
        };
        plan.set(point, Space::Exterior);
    }
}

pub(super) fn connect_service_pockets(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
    loop {
        let maintenance = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Maintenance)
            .collect::<BTreeSet<_>>();
        let components = connected_components(&maintenance, plan.width, plan.height);
        if components.len() <= 1 {
            return (!maintenance.is_empty()).then_some(()).ok_or_else(|| {
                LayoutError("architectural plan produced no maintenance network".into())
            });
        }
        let network = components
            .iter()
            .max_by_key(|component| component.len())
            .cloned()
            .ok_or_else(|| {
                LayoutError("architectural plan produced no maintenance network".into())
            })?;
        let pocket = components
            .iter()
            .filter(|component| **component != network)
            .min_by_key(|component| {
                component
                    .iter()
                    .flat_map(|point| {
                        network
                            .iter()
                            .map(move |other| cell_distance(*point, *other))
                    })
                    .min()
                    .unwrap_or(u16::MAX)
            })
            .cloned()
            .ok_or_else(|| LayoutError("maintenance pocket selection failed".into()))?;
        let allowed = plan
            .points()
            .filter(|point| matches!(plan.get(*point), Space::Exterior | Space::Maintenance))
            .collect::<BTreeSet<_>>();
        let path = shortest_path_between_sets(&network, &pocket, &allowed, plan.width, plan.height)
            .or_else(|| {
                // A service bay can be enclosed by a department suite after
                // room packing. Route its choke point through local/common
                // circulation, never through an authored room or the public
                // spine. This models the short maintenance cross-passages used
                // on hand-authored stations and keeps the service graph whole.
                let service_or_local = plan
                    .points()
                    .filter(|point| {
                        matches!(
                            plan.get(*point),
                            Space::Exterior | Space::Maintenance | Space::Common(_) | Space::Public
                        )
                    })
                    .collect::<BTreeSet<_>>();
                shortest_path_between_sets(
                    &network,
                    &pocket,
                    &service_or_local,
                    plan.width,
                    plan.height,
                )
            })
            .ok_or_else(|| {
                LayoutError(
                    "maintenance pockets cannot connect without crossing an authored room".into(),
                )
            })?;
        for point in path {
            plan.set(point, Space::Maintenance);
        }
    }
}

pub(super) fn ensure_maintenance_component_portals(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
    let maintenance = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Maintenance)
        .collect::<BTreeSet<_>>();
    for component in connected_components(&maintenance, plan.width, plan.height) {
        if plan
            .portals
            .iter()
            .any(|portal| component.contains(&portal.left) || component.contains(&portal.right))
        {
            continue;
        }
        let mut candidate = None;
        for maintenance_cell in &component {
            for neighbor in plan.neighbors(*maintenance_cell) {
                let (department, room, kind) = match plan.get(neighbor) {
                    Space::Public => (0, None, PortalKind::PublicMaintenance),
                    Space::Common(department) => (department, None, PortalKind::Maintenance),
                    Space::Room { department, room } => {
                        (department, Some(room), PortalKind::RoomMaintenance)
                    }
                    _ => continue,
                };
                candidate = Some(Portal {
                    left: neighbor,
                    right: *maintenance_cell,
                    department,
                    room,
                    kind,
                });
                break;
            }
            if candidate.is_some() {
                break;
            }
        }
        let portal = candidate.ok_or_else(|| {
            LayoutError("isolated maintenance service space has no accessible boundary".into())
        })?;
        plan.portals.push(portal);
    }
    Ok(())
}

pub(super) fn shape_department_block(
    mut block: DepartmentBlock,
    seed: u64,
    department: u16,
) -> DepartmentBlock {
    let hash = hash64(seed ^ u64::from(department) ^ 0x626c_6f63_6b5f_7368);
    let depth_trim = 1 + (hash % 3) as u16;
    match block.frontage {
        BlockFrontage::East => {
            block.min_x = (block.min_x + depth_trim).min(block.max_x.saturating_sub(6));
        }
        BlockFrontage::West => {
            block.max_x = block.max_x.saturating_sub(depth_trim).max(block.min_x + 6);
        }
        BlockFrontage::North => {
            block.min_y = (block.min_y + depth_trim).min(block.max_y.saturating_sub(6));
        }
        BlockFrontage::South => {
            block.max_y = block.max_y.saturating_sub(depth_trim).max(block.min_y + 6);
        }
    }
    let cross_span = if matches!(block.frontage, BlockFrontage::North | BlockFrontage::South) {
        block.max_x - block.min_x + 1
    } else {
        block.max_y - block.min_y + 1
    };
    if cross_span >= 9 {
        let trim_low = ((hash >> 8) & 1) as u16;
        let trim_high = ((hash >> 9) & 1) as u16;
        if matches!(block.frontage, BlockFrontage::North | BlockFrontage::South) {
            block.min_x += trim_low;
            block.max_x -= trim_high;
        } else {
            block.min_y += trim_low;
            block.max_y -= trim_high;
        }
    }
    block
}

pub(super) fn derive_maintenance_service_space(plan: &mut LogicalPlan) {
    let active = plan
        .points()
        .filter(|point| plan.get(*point) != Space::Exterior)
        .collect::<BTreeSet<_>>();
    let service = active
        .iter()
        .flat_map(|point| cardinal_cells(*point, plan.width, plan.height))
        .filter(|point| !active.contains(point))
        .collect::<BTreeSet<_>>();
    for point in service {
        plan.set(point, Space::Maintenance);
    }
    bridge_interdepartment_service_gaps(plan);
}

pub(super) fn bridge_interdepartment_service_gaps(plan: &mut LogicalPlan) {
    const SEARCH: u16 = 6;
    let exterior = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Exterior)
        .collect::<Vec<_>>();
    let department_in_direction = |plan: &LogicalPlan, point: CellPoint, dx: i16, dy: i16| {
        (1..=SEARCH).find_map(|distance| {
            let x = i32::from(point.x) + i32::from(dx) * i32::from(distance);
            let y = i32::from(point.y) + i32::from(dy) * i32::from(distance);
            if x < 0 || y < 0 || x >= i32::from(plan.width) || y >= i32::from(plan.height) {
                return None;
            }
            match plan.get(CellPoint {
                x: u16::try_from(x).ok()?,
                y: u16::try_from(y).ok()?,
            }) {
                Space::Room { department, .. } | Space::Common(department) => Some(department),
                Space::Public | Space::Maintenance | Space::Exterior => None,
            }
        })
    };
    for point in exterior {
        let west = department_in_direction(plan, point, -1, 0);
        let east = department_in_direction(plan, point, 1, 0);
        let south = department_in_direction(plan, point, 0, -1);
        let north = department_in_direction(plan, point, 0, 1);
        let separates_departments = west.zip(east).is_some_and(|(left, right)| left != right)
            || south.zip(north).is_some_and(|(bottom, top)| bottom != top);
        if separates_departments {
            plan.set(point, Space::Maintenance);
        }
    }
}
