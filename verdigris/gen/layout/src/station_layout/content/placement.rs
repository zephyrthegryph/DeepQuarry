use super::*;

/// The part of a room's placement context that stays the same across every
/// `place_room_program` attempt for that room (primary program, fragment
/// retry, compact fallback), grouped so the function stays under clippy's
/// argument limit instead of taking each of these separately.
#[derive(Clone, Copy)]
pub(super) struct RoomPlacementContext<'a> {
    pub(super) layout: &'a StationLayout,
    pub(super) tiles: &'a BTreeSet<Point>,
    pub(super) reserved: &'a BTreeSet<Point>,
    pub(super) doors: &'a BTreeSet<Point>,
    pub(super) center: Point,
    pub(super) protected_approaches: &'a BTreeSet<Point>,
}

pub(super) fn place_room_program(
    ctx: &RoomPlacementContext<'_>,
    program: &RoomProgram,
    initial_blocking: &BTreeSet<Point>,
    initial_required_access: &BTreeSet<Point>,
    initial_occupied: &BTreeSet<Point>,
) -> Result<Vec<AuthoredCompositionPlacement>, LayoutError> {
    let RoomPlacementContext {
        layout,
        tiles,
        reserved,
        doors,
        center,
        protected_approaches,
    } = *ctx;
    let entrance = doors
        .iter()
        .copied()
        .min_by_key(|point| (distance(*point, center), point.y, point.x))
        .unwrap_or(center);
    let mut occupied = initial_occupied.clone();
    occupied.insert(center);
    occupied.extend(protected_approaches.iter().copied());
    let mut blocking = initial_blocking.clone();
    let mut required_access = initial_required_access.clone();
    let mut result = Vec::new();

    // A program is a workflow, not a density quota. Repeating an arbitrary
    // zone until a percentage was reached produced the visible rows of the
    // same cabinet/chair/console. Large-purpose spaces must receive explicitly
    // authored secondary zones; they must never be padded by cloning furniture.
    let mut scheduled = program
        .zones
        .iter()
        .map(|zone| (zone, true))
        .collect::<Vec<_>>();
    if tiles.len() as u32 >= program.ideal_area
        && let Some(zone) = program.zones.iter().find(|zone| zone.repeatable)
    {
        // A room at or above its authored capacity receives one explicit
        // second work bay: another ward bay, locker bank, archive bank, and so
        // on. More than one clone is forbidden; further capacity needs a
        // different authored activity zone.
        scheduled.push((zone, false));
    }

    for (schedule_index, (zone, primary)) in scheduled.into_iter().enumerate() {
        let mut anchors = tiles.iter().copied().collect::<Vec<_>>();
        anchors.sort_by_key(|point| {
            let spread = result
                .iter()
                .map(|placed: &AuthoredCompositionPlacement| distance(*point, placed.at))
                .min()
                .unwrap_or(0);
            let seeded_order = stable_text_hash(zone.id)
                ^ layout.seed
                ^ u64::from(point.x).rotate_left(11)
                ^ u64::from(point.y).rotate_left(23)
                ^ (schedule_index as u64).rotate_left(37);
            match zone.anchor {
                ProgramAnchor::Center => (
                    0,
                    distance(*point, center),
                    std::cmp::Reverse(spread),
                    seeded_order,
                ),
                ProgramAnchor::Entrance => (
                    0,
                    distance(*point, entrance),
                    std::cmp::Reverse(spread),
                    seeded_order,
                ),
                ProgramAnchor::Perimeter => (
                    u16::from(!adjacent_to_wall(layout, *point)),
                    0,
                    std::cmp::Reverse(spread),
                    seeded_order,
                ),
            }
        });
        let rotation_offset =
            usize::try_from(layout.seed ^ stable_text_hash(zone.id)).unwrap_or_default() % 4;
        let env = ZonePlacementEnv {
            layout,
            tiles,
            doors,
            center,
        };
        let mut selected = None;
        'candidate: for anchor in anchors {
            // Try all 4 quarter-turns for this anchor (starting from
            // `rotation_offset`'s own rotation) before giving up on it: a
            // rotation that doesn't fit at this anchor may still fit once
            // turned. See `try_place_zone_at`.
            for turn_offset in 0..4 {
                let turns = (rotation_offset + turn_offset) % 4;
                if let Some(placed) = try_place_zone_at(
                    &env,
                    &occupied,
                    &required_access,
                    &blocking,
                    zone,
                    anchor,
                    turns,
                ) {
                    selected = Some(placed);
                    break 'candidate;
                }
            }
        }
        if let Some((placements, trial_blocking, trial_access)) = selected {
            for placement in &placements {
                occupied.insert(placement.at);
            }
            blocking = trial_blocking;
            required_access = trial_access;
            result.extend(placements);
        } else {
            let adaptive = place_adaptive_activity_zone(
                layout,
                zone,
                tiles,
                center,
                entrance,
                &occupied,
                &blocking,
                &required_access,
            );
            let Some((placements, trial_blocking, trial_access)) = adaptive else {
                if !primary || !zone.required {
                    continue;
                }
                return Err(LayoutError(format!(
                    "room program {} cannot place required activity zone {} ({} tiles, {} circulation tiles)",
                    program.id,
                    zone.id,
                    tiles.len(),
                    reserved.len(),
                )));
            };
            for placement in &placements {
                occupied.insert(placement.at);
            }
            blocking = trial_blocking;
            required_access = trial_access;
            result.extend(placements);
        }
    }
    Ok(result)
}

/// The parts of a zone-placement attempt that don't change across anchors or
/// rotations, grouped so `try_place_zone_at` stays under clippy's argument
/// limit instead of taking each of these separately.
pub(super) struct ZonePlacementEnv<'a> {
    pub(super) layout: &'a StationLayout,
    pub(super) tiles: &'a BTreeSet<Point>,
    pub(super) doors: &'a BTreeSet<Point>,
    pub(super) center: Point,
}

/// Tries to place every fixture of `zone`, anchored at `anchor` and rotated
/// `turns` quarter-turns (see `program_rotate_offset`), without colliding
/// with `occupied`/`env.doors`/`blocking`/`required_access` and without
/// leaving the room's walkable area disconnected. Returns the placements
/// plus the blocking/access point sets they would add, or `None` if this
/// anchor/rotation doesn't fit -- the caller then retries with the next
/// rotation, and failing all 4, the next anchor.
pub(super) fn try_place_zone_at(
    env: &ZonePlacementEnv<'_>,
    occupied: &BTreeSet<Point>,
    required_access: &BTreeSet<Point>,
    blocking: &BTreeSet<Point>,
    zone: &ActivityZone,
    anchor: Point,
    turns: usize,
) -> Option<(Vec<AuthoredCompositionPlacement>, BTreeSet<Point>, BTreeSet<Point>)> {
    let mut placements = Vec::with_capacity(zone.fixtures.len());
    let mut local = BTreeSet::new();
    let mut trial_blocking = blocking.clone();
    let mut trial_access = required_access.clone();
    for fixture in &zone.fixtures {
        let (dx, dy) = program_rotate_offset(fixture.dx, fixture.dy, turns);
        let x = i32::from(anchor.x) + i32::from(dx);
        let y = i32::from(anchor.y) + i32::from(dy);
        if x < 0 || y < 0 {
            return None;
        }
        let at = Point {
            x: u16::try_from(x).unwrap_or(u16::MAX),
            y: u16::try_from(y).unwrap_or(u16::MAX),
        };
        if !env.tiles.contains(&at)
            || env.doors.contains(&at)
            || occupied.contains(&at)
            || required_access.contains(&at)
            || !local.insert(at)
        {
            return None;
        }
        let wall_mounted = fixture_is_wall_mounted(fixture.id);
        let layer = if wall_mounted {
            FixtureLayer::Wall
        } else {
            match fixture.layer {
                ProgramLayer::Furniture => FixtureLayer::Furniture,
                ProgramLayer::Machine => FixtureLayer::Machine,
                ProgramLayer::Wall => FixtureLayer::Wall,
            }
        };
        let facing = if wall_mounted || fixture.layer == ProgramLayer::Wall {
            wall_fixture_facing(env.layout, at)?
        } else if zone.anchor == ProgramAnchor::Perimeter {
            wall_fixture_facing(env.layout, anchor)
                .map(opposite_facing)
                .unwrap_or_else(|| face_toward(at, env.center))
        } else {
            face_toward(at, anchor)
        };
        if !wall_mounted && fixture_blocks(fixture.id) {
            trial_blocking.insert(at);
        }
        placements.push(AuthoredCompositionPlacement {
            at,
            facing,
            fixture_id: fixture.id.into(),
            layer,
        });
    }
    for placement in &mut placements {
        if !fixture_blocks_on_layer(&placement.fixture_id, placement.layer) {
            continue;
        }
        let preferred = placement.facing;
        let candidate_facings = if fixture_requires_fixed_facing(&placement.fixture_id) {
            vec![preferred]
        } else {
            vec![
                preferred,
                Facing::North,
                Facing::East,
                Facing::South,
                Facing::West,
            ]
        };
        let (access, facing) = candidate_facings
            .into_iter()
            .map(|facing| (step_facing(placement.at, facing), facing))
            .find(|(access, _)| env.tiles.contains(access) && !trial_blocking.contains(access))?;
        placement.facing = facing;
        trial_access.insert(access);
    }
    if !room_walkable_connected(env.tiles, &trial_blocking, env.layout.width, env.layout.height) {
        return None;
    }
    Some((placements, trial_blocking, trial_access))
}

// Thin dispatcher: forwards straight into
// place_adaptive_fixture_sequence's recursion below, so its argument list
// exists only because that one does. Not bundled for the same reason.
#[allow(clippy::too_many_arguments)]
pub(super) fn place_adaptive_activity_zone(
    layout: &StationLayout,
    zone: &ActivityZone,
    tiles: &BTreeSet<Point>,
    center: Point,
    entrance: Point,
    initial_occupied: &BTreeSet<Point>,
    initial_blocking: &BTreeSet<Point>,
    initial_access: &BTreeSet<Point>,
) -> Option<(
    Vec<AuthoredCompositionPlacement>,
    BTreeSet<Point>,
    BTreeSet<Point>,
)> {
    let target = match zone.anchor {
        ProgramAnchor::Entrance => entrance,
        _ => center,
    };
    place_adaptive_fixture_sequence(
        layout,
        zone,
        tiles,
        target,
        0,
        target,
        initial_occupied.clone(),
        initial_blocking.clone(),
        initial_access.clone(),
        Vec::new(),
    )
}

// Recursive backtracking search: most of these args are per-call-frame
// accumulators (occupied/blocking/access/placements) or loop state
// (fixture_index/cluster_target) that change on every recursive step, not
// a fixed context a struct would factor out cleanly. Not bundled.
#[allow(clippy::too_many_arguments)]
pub(super) fn place_adaptive_fixture_sequence(
    layout: &StationLayout,
    zone: &ActivityZone,
    tiles: &BTreeSet<Point>,
    target: Point,
    fixture_index: usize,
    cluster_target: Point,
    occupied: BTreeSet<Point>,
    blocking: BTreeSet<Point>,
    access: BTreeSet<Point>,
    placements: Vec<AuthoredCompositionPlacement>,
) -> Option<(
    Vec<AuthoredCompositionPlacement>,
    BTreeSet<Point>,
    BTreeSet<Point>,
)> {
    let Some(fixture) = zone.fixtures.get(fixture_index) else {
        return Some((placements, blocking, access));
    };
    let is_seat = fixture.id.contains("chair")
        || matches!(
            fixture.id,
            "stool" | "visitor_bench" | "waiting_bench" | "executive_chair"
        );
    let relationship_target = is_seat
        .then(|| {
            placements.iter().rev().find(|placement| {
                placement.fixture_id.contains("table")
                    || placement.fixture_id.contains("desk")
                    || placement.fixture_id.contains("bench")
                    || placement.fixture_id.contains("console")
                    || placement.fixture_id.contains("bed")
            })
        })
        .flatten()
        .map(|placement| placement.at);
    let placement_target = relationship_target.unwrap_or(cluster_target);
    let mut candidates = tiles
        .iter()
        .copied()
        .filter(|point| {
            !occupied.contains(point)
                && !access.contains(point)
                && relationship_target
                    .map(|target| distance(*point, target) == 1)
                    .unwrap_or(true)
        })
        .collect::<Vec<_>>();
    candidates.sort_by_key(|point| {
        (
            match zone.anchor {
                ProgramAnchor::Perimeter => u16::from(!adjacent_to_wall(layout, *point)),
                _ => 0,
            },
            distance(*point, placement_target),
            distance(*point, target),
            point.y,
            point.x,
        )
    });
    // This is a small constraint problem (normally 3-7 fixtures), not a
    // greedy decoration pass. Trying only the nearest candidate made a
    // perfectly furnishable room fail when the first machine consumed the
    // sole operating aisle needed by a later fixture.
    for at in candidates {
        let wall_mounted = fixture_is_wall_mounted(fixture.id);
        if wall_mounted && !adjacent_to_wall(layout, at) {
            continue;
        }
        let mut trial_blocking = blocking.clone();
        let mut facing = if wall_mounted {
            wall_fixture_facing(layout, at)?
        } else {
            face_toward(at, target)
        };
        let mut fixture_access = None;
        if !wall_mounted && fixture_blocks(fixture.id) {
            trial_blocking.insert(at);
            if !room_walkable_connected(tiles, &trial_blocking, layout.width, layout.height) {
                continue;
            }
            let candidate_facings = if fixture_requires_fixed_facing(fixture.id) {
                vec![facing]
            } else {
                vec![
                    facing,
                    Facing::North,
                    Facing::East,
                    Facing::South,
                    Facing::West,
                ]
            };
            let Some((point, direction)) = candidate_facings
                .into_iter()
                .map(|direction| (step_facing(at, direction), direction))
                .find(|(point, _)| tiles.contains(point) && !trial_blocking.contains(point))
            else {
                continue;
            };
            facing = direction;
            fixture_access = Some(point);
        }
        let mut trial_occupied = occupied.clone();
        trial_occupied.insert(at);
        let mut trial_access = access.clone();
        if let Some(point) = fixture_access {
            trial_access.insert(point);
        }
        let mut trial_placements = placements.clone();
        trial_placements.push(AuthoredCompositionPlacement {
            at,
            facing,
            fixture_id: fixture.id.into(),
            layer: if wall_mounted {
                FixtureLayer::Wall
            } else {
                match fixture.layer {
                    ProgramLayer::Furniture => FixtureLayer::Furniture,
                    ProgramLayer::Machine => FixtureLayer::Machine,
                    ProgramLayer::Wall => FixtureLayer::Wall,
                }
            },
        });
        if let Some(result) = place_adaptive_fixture_sequence(
            layout,
            zone,
            tiles,
            target,
            fixture_index + 1,
            at,
            trial_occupied,
            trial_blocking,
            trial_access,
            trial_placements,
        ) {
            return Some(result);
        }
    }
    None
}

pub(super) fn program_rotate_offset(dx: i16, dy: i16, turns: usize) -> (i16, i16) {
    match turns % 4 {
        0 => (dx, dy),
        1 => (-dy, dx),
        2 => (-dx, -dy),
        _ => (dy, -dx),
    }
}

pub(super) fn wall_fixture_facing(layout: &StationLayout, at: Point) -> Option<Facing> {
    [
        (Facing::North, 0i16, 1i16),
        (Facing::East, 1, 0),
        (Facing::South, 0, -1),
        (Facing::West, -1, 0),
    ]
    .into_iter()
    .find_map(|(facing, dx, dy)| {
        let x = i32::from(at.x) + i32::from(dx);
        let y = i32::from(at.y) + i32::from(dy);
        if x < 0 || y < 0 {
            return None;
        }
        let point = Point {
            x: u16::try_from(x).ok()?,
            y: u16::try_from(y).ok()?,
        };
        layout
            .tiles
            .get(usize::from(point.y) * usize::from(layout.width) + usize::from(point.x))
            .filter(|tile| {
                matches!(
                    tile.class,
                    TileClass::Hull | TileClass::Structure | TileClass::Partition
                )
            })
            .map(|_| facing)
    })
}

pub(super) fn opposite_facing(facing: Facing) -> Facing {
    match facing {
        Facing::North => Facing::South,
        Facing::East => Facing::West,
        Facing::South => Facing::North,
        Facing::West => Facing::East,
    }
}

pub(super) fn stable_text_hash(value: &str) -> u64 {
    value.bytes().fold(0xcbf29ce484222325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3)
    })
}

pub(super) fn room_walkable_connected(
    tiles: &BTreeSet<Point>,
    blocking: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> bool {
    let walkable = tiles.difference(blocking).copied().collect::<BTreeSet<_>>();
    let Some(start) = walkable.iter().next().copied() else {
        return false;
    };
    let mut reached = BTreeSet::from([start]);
    let mut queue = VecDeque::from([start]);
    while let Some(point) = queue.pop_front() {
        for neighbor in point_neighbors(point, width, height) {
            if walkable.contains(&neighbor) && reached.insert(neighbor) {
                queue.push_back(neighbor);
            }
        }
    }
    reached.len() == walkable.len()
}

pub(super) fn largest_region_size(
    tiles: &BTreeSet<Point>,
    occupied: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> usize {
    let mut remaining = tiles.difference(occupied).copied().collect::<BTreeSet<_>>();
    let mut largest = 0usize;
    while let Some(start) = remaining.pop_first() {
        let mut size = 1usize;
        let mut queue = VecDeque::from([start]);
        while let Some(point) = queue.pop_front() {
            for neighbor in point_neighbors(point, width, height) {
                if remaining.remove(&neighbor) {
                    size += 1;
                    queue.push_back(neighbor);
                }
            }
        }
        largest = largest.max(size);
    }
    largest
}
