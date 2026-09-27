use super::*;

pub fn validate_station_blueprint(
    blueprint: &StationBlueprint,
) -> Result<BTreeMap<String, u32>, LayoutError> {
    let mut ids = BTreeSet::new();
    let mut positions = BTreeMap::<Point, &str>::new();
    let mut wall_positions = BTreeSet::new();
    let mut semantic_fixture_total = 0usize;
    let mut clustered_fixture_total = 0usize;
    let mut rooms_with_cluster = 0usize;
    let mut rooms_matching_counterpart = 0usize;
    let mut rooms_below_counterpart_density = 0usize;
    let mut rooms_exceeding_counterpart_empty_region = 0usize;
    let mut empty_region_micros_total = 0u64;
    let doors: BTreeSet<Point> = blueprint.layout.doors.iter().map(|door| door.at).collect();
    for fixture in &blueprint.fixtures {
        if !ids.insert(fixture.id) {
            return Err(LayoutError(format!("duplicate fixture {}", fixture.id)));
        }
        if fixture.at.x >= blueprint.layout.width || fixture.at.y >= blueprint.layout.height {
            return Err(LayoutError(format!(
                "fixture {} lies outside station",
                fixture.id
            )));
        }
        if doors.contains(&fixture.at) {
            return Err(LayoutError(format!("fixture {} blocks a door", fixture.id)));
        }
        if fixture.layer != FixtureLayer::Wall {
            if let Some(existing) = positions.insert(fixture.at, &fixture.fixture_id) {
                let supported_charger = matches!(
                    (existing, fixture.fixture_id.as_str()),
                    ("charger_table", "equipment_recharger")
                        | ("equipment_recharger", "charger_table")
                );
                if !supported_charger {
                    return Err(LayoutError(format!(
                        "stacked floor fixtures at {},{}",
                        fixture.at.x, fixture.at.y
                    )));
                }
            }
        }
        if fixture.layer == FixtureLayer::Wall && !adjacent_to_wall(&blueprint.layout, fixture.at) {
            return Err(LayoutError(format!(
                "wall fixture {} lacks a wall",
                fixture.id
            )));
        }
        if fixture.layer == FixtureLayer::Wall && !wall_positions.insert(fixture.at) {
            return Err(LayoutError(format!(
                "stacked wall fixtures at {},{}",
                fixture.at.x, fixture.at.y
            )));
        }
        if fixture_is_wall_mounted(&fixture.fixture_id) && fixture.layer != FixtureLayer::Wall {
            return Err(LayoutError(format!(
                "wall-only fixture {} was placed on the floor",
                fixture.fixture_id
            )));
        }
        if fixture.fixture_id == "equipment_recharger"
            && !blueprint.fixtures.iter().any(|support| {
                support.fixture_id == "charger_table"
                    && support.room_id == fixture.room_id
                    && support.at == fixture.at
            })
        {
            return Err(LayoutError(format!(
                "equipment recharger {} lacks a table support",
                fixture.id
            )));
        }
    }
    for room in &blueprint.rooms {
        if room.semantic_role.is_empty()
            || room.selected_variant.is_empty()
            || room.fixture_ids.is_empty()
        {
            return Err(LayoutError(format!(
                "room {} lacks authoritative content",
                room.room_id
            )));
        }
        if room.accent_style.is_empty() || room.accent_style == "department" {
            return Err(LayoutError(format!(
                "room {} lacks a concrete department floor-paint style",
                room.room_id
            )));
        }
        if room.occupancy_micros > 650_000 {
            return Err(LayoutError(format!(
                "room {} has implausible occupancy {}",
                room.room_id, room.occupancy_micros
            )));
        }
        for required in ["apc", "air_alarm", "wall_light"] {
            if !room.fixture_ids.iter().any(|id| {
                blueprint
                    .fixtures
                    .iter()
                    .any(|f| f.id == *id && f.fixture_id == required)
            }) {
                return Err(LayoutError(format!(
                    "room {} lacks {required}",
                    room.room_id
                )));
            }
        }
        if !room.fixture_ids.iter().any(|id| {
            blueprint
                .fixtures
                .iter()
                .any(|f| f.id == *id && matches!(f.fixture_id.as_str(), "vent" | "scrubber"))
        }) {
            return Err(LayoutError(format!(
                "room {} lacks an atmosphere endpoint",
                room.room_id
            )));
        }
        let semantic_fixtures = room
            .fixture_ids
            .iter()
            .filter_map(|id| blueprint.fixtures.iter().find(|fixture| fixture.id == *id))
            .filter(|fixture| {
                fixture.layer != FixtureLayer::Wall
                    && fixture.layer != FixtureLayer::Ceiling
                    && !matches!(
                        fixture.fixture_id.as_str(),
                        "vent"
                            | "scrubber"
                            | "apc"
                            | "air_alarm"
                            | "fire_alarm"
                            | "wall_light"
                            | "charger_table"
                    )
            })
            .collect::<Vec<_>>();
        for chair in semantic_fixtures.iter().filter(|fixture| {
            fixture.fixture_id.contains("chair")
                || matches!(fixture.fixture_id.as_str(), "stool" | "executive_chair")
        }) {
            let related = semantic_fixtures.iter().any(|other| {
                chair.id != other.id
                    && distance(chair.at, other.at) == 1
                    && (other.fixture_id.contains("table")
                        || other.fixture_id.contains("desk")
                        || other.fixture_id.contains("bench")
                        || other.fixture_id.contains("console")
                        || other.fixture_id.contains("bed")
                        || matches!(
                            other.fixture_id.as_str(),
                            "visitor_bench" | "waiting_bench" | "side_table"
                        ))
            }) || room.fixture_ids.iter().any(|id| {
                blueprint.fixtures.iter().any(|other| {
                    other.id == *id
                        && distance(chair.at, other.at) == 1
                        && (other.fixture_id.contains("console")
                            || other.fixture_id.contains("monitor"))
                })
            });
            if !related {
                return Err(LayoutError(format!(
                    "room {} ({}) has an unpaired seat {} at {},{} among {:?}",
                    room.room_id,
                    room.semantic_role,
                    chair.fixture_id,
                    chair.at.x,
                    chair.at.y,
                    semantic_fixtures
                        .iter()
                        .map(|fixture| (&fixture.fixture_id, fixture.at))
                        .collect::<Vec<_>>(),
                )));
            }
        }
        let clustered = semantic_fixtures
            .iter()
            .filter(|fixture| {
                semantic_fixtures
                    .iter()
                    .any(|other| fixture.id != other.id && distance(fixture.at, other.at) == 1)
            })
            .count();
        semantic_fixture_total += semantic_fixtures.len();
        clustered_fixture_total += clustered;
        rooms_with_cluster += usize::from(clustered >= 2);
        let profile = counterpart_profile(&room.semantic_role);
        let unique_fixtures = semantic_fixtures
            .iter()
            .map(|fixture| fixture.fixture_id.as_str())
            .collect::<BTreeSet<_>>()
            .len();
        let cluster_micros =
            (clustered as u64 * 1_000_000 / semantic_fixtures.len().max(1) as u64) as u32;
        let structural_room = blueprint
            .layout
            .rooms
            .iter()
            .find(|candidate| candidate.id == room.room_id)
            .ok_or_else(|| {
                LayoutError(format!("room {} lacks structural geometry", room.room_id))
            })?;
        let room_tiles = structural_room
            .tiles
            .iter()
            .copied()
            .collect::<BTreeSet<_>>();
        if let Some(outside_fixture) = room.fixture_ids.iter().find_map(|id| {
            blueprint
                .fixtures
                .iter()
                .find(|fixture| fixture.id == *id && !room_tiles.contains(&fixture.at))
        }) {
            return Err(LayoutError(format!(
                "room {} fixture {} occupies a wall or another room at {},{}",
                room.room_id,
                outside_fixture.fixture_id,
                outside_fixture.at.x,
                outside_fixture.at.y
            )));
        }
        let semantic_positions = semantic_fixtures
            .iter()
            .map(|fixture| fixture.at)
            .collect::<BTreeSet<_>>();
        let empty_region_micros = (largest_region_size(
            &room_tiles,
            &semantic_positions,
            blueprint.layout.width,
            blueprint.layout.height,
        ) as u64
            * 1_000_000
            / room_tiles.len().max(1) as u64) as u32;
        empty_region_micros_total += u64::from(empty_region_micros);
        rooms_below_counterpart_density +=
            usize::from(room.occupancy_micros < profile.minimum_occupancy_micros);
        rooms_exceeding_counterpart_empty_region +=
            usize::from(empty_region_micros > profile.maximum_empty_region_micros);
        rooms_matching_counterpart += usize::from(
            cluster_micros >= profile.minimum_cluster_micros
                && unique_fixtures >= profile.minimum_unique_fixtures
                && semantic_fixtures.len() >= profile.minimum_fixture_count
                && room.occupancy_micros >= profile.minimum_occupancy_micros
                && empty_region_micros <= profile.maximum_empty_region_micros,
        );
        let mut repeat_counts = BTreeMap::new();
        for fixture in room
            .fixture_ids
            .iter()
            .filter_map(|id| blueprint.fixtures.iter().find(|fixture| fixture.id == *id))
            .filter(|fixture| {
                fixture.layer != FixtureLayer::Wall
                    && !matches!(fixture.fixture_id.as_str(), "vent" | "scrubber")
            })
        {
            *repeat_counts
                .entry(fixture.fixture_id.as_str())
                .or_insert(0usize) += 1;
        }
        for (fixture_id, count) in repeat_counts {
            let repeat_limit = fixture_repeat_limit_for_role(&room.semantic_role, fixture_id);
            if count > repeat_limit {
                return Err(LayoutError(format!(
                    "room {} repeats fixture {} {} times (limit {})",
                    room.room_id, fixture_id, count, repeat_limit
                )));
            }
        }
        if !room.fixture_ids.iter().any(|id| {
            blueprint.fixtures.iter().any(|f| {
                f.id == *id
                    && !matches!(
                        f.fixture_id.as_str(),
                        "vent" | "scrubber" | "apc" | "air_alarm" | "fire_alarm" | "wall_light"
                    )
            })
        }) {
            return Err(LayoutError(format!(
                "room {} lacks a role-defining fixture",
                room.room_id
            )));
        }
        let tiles: BTreeSet<Point> = structural_room.tiles.iter().copied().collect();
        let blocked: BTreeSet<Point> = room
            .fixture_ids
            .iter()
            .filter_map(|id| blueprint.fixtures.iter().find(|fixture| fixture.id == *id))
            .filter(|fixture| fixture.blocks_movement)
            .map(|fixture| fixture.at)
            .collect();
        let walkable: BTreeSet<Point> = tiles.difference(&blocked).copied().collect();
        let Some(start) = walkable.iter().next().copied() else {
            return Err(LayoutError(format!(
                "room {} has no walkable floor",
                room.room_id
            )));
        };
        let mut reached = BTreeSet::from([start]);
        let mut queue = VecDeque::from([start]);
        while let Some(point) = queue.pop_front() {
            for next in point_neighbors(point, blueprint.layout.width, blueprint.layout.height) {
                if walkable.contains(&next) && reached.insert(next) {
                    queue.push_back(next);
                }
            }
        }
        if reached.len() != walkable.len() {
            return Err(LayoutError(format!(
                "room {} furnishings isolate {} floor tiles",
                room.room_id,
                walkable.len() - reached.len()
            )));
        }
        let door_approaches = structural_room
            .door_ids
            .iter()
            .filter_map(|door_id| {
                blueprint
                    .layout
                    .doors
                    .iter()
                    .find(|door| door.id == *door_id)
            })
            .flat_map(|door| {
                point_neighbors(door.at, blueprint.layout.width, blueprint.layout.height)
            })
            .filter(|point| walkable.contains(point))
            .collect::<BTreeSet<_>>();
        let mut reached_from_doors = door_approaches.clone();
        let mut door_queue = VecDeque::from_iter(door_approaches);
        while let Some(point) = door_queue.pop_front() {
            for next in point_neighbors(point, blueprint.layout.width, blueprint.layout.height) {
                if walkable.contains(&next) && reached_from_doors.insert(next) {
                    door_queue.push_back(next);
                }
            }
        }
        let circulation: BTreeSet<Point> = room.circulation.iter().copied().collect();
        if !circulation.contains(&room.activity_center) || !circulation.is_subset(&walkable) {
            let outside = circulation
                .difference(&walkable)
                .copied()
                .collect::<Vec<_>>();
            return Err(LayoutError(format!(
                "room {} circulation is outside walkable floor or misses its activity center (center {:?}, contains {}, outside {:?})",
                room.room_id,
                room.activity_center,
                circulation.contains(&room.activity_center),
                outside
            )));
        }
        let mut circulation_reached = BTreeSet::from([room.activity_center]);
        let mut circulation_queue = VecDeque::from([room.activity_center]);
        while let Some(point) = circulation_queue.pop_front() {
            for next in point_neighbors(point, blueprint.layout.width, blueprint.layout.height) {
                if circulation.contains(&next) && circulation_reached.insert(next) {
                    circulation_queue.push_back(next);
                }
            }
        }
        if circulation_reached.len() != circulation.len() {
            return Err(LayoutError(format!(
                "room {} circulation has {} disconnected tiles",
                room.room_id,
                circulation.len() - circulation_reached.len()
            )));
        }
        for door_id in &structural_room.door_ids {
            let door = blueprint
                .layout
                .doors
                .iter()
                .find(|candidate| candidate.id == *door_id)
                .ok_or_else(|| {
                    LayoutError(format!(
                        "room {} references missing door {door_id}",
                        room.room_id
                    ))
                })?;
            if !neighbors(&blueprint.layout, door.at)
                .into_iter()
                .any(|point| tiles.contains(&point) && circulation.contains(&point))
            {
                return Err(LayoutError(format!(
                    "room {} door {} has no circulation approach",
                    room.room_id, door_id
                )));
            }
        }
        if let Some(uncovered) = walkable.iter().find(|point| {
            !circulation.contains(point)
                && !point_neighbors(**point, blueprint.layout.width, blueprint.layout.height)
                    .into_iter()
                    .any(|neighbor| circulation.contains(&neighbor))
        }) {
            return Err(LayoutError(format!(
                "room {} floor at {},{} is not served by circulation",
                room.room_id, uncovered.x, uncovered.y
            )));
        }
        for fixture in room
            .fixture_ids
            .iter()
            .filter_map(|id| blueprint.fixtures.iter().find(|fixture| fixture.id == *id))
        {
            if !fixture.blocks_movement
                && !circulation.contains(&fixture.at)
                && !point_neighbors(fixture.at, blueprint.layout.width, blueprint.layout.height)
                    .into_iter()
                    .any(|neighbor| circulation.contains(&neighbor))
            {
                return Err(LayoutError(format!(
                    "room {} fixture {} at {},{} is not served by circulation",
                    room.room_id, fixture.fixture_id, fixture.at.x, fixture.at.y
                )));
            }
            for access in &fixture.required_access {
                if !tiles.contains(access)
                    || blocked.contains(access)
                    || !reached.contains(access)
                    || !reached_from_doors.contains(access)
                    || !circulation.contains(access)
                {
                    return Err(LayoutError(format!(
                        "room {} fixture {} lacks clear reachable access at {},{}",
                        room.room_id, fixture.fixture_id, access.x, access.y
                    )));
                }
            }
        }
    }
    // Aggregate aesthetic scores rank and diagnose blueprints; they are not
    // correctness gates. A live seed with complete structure, access, and
    // fixtures must remain materializable even when its clustering score is
    // below the preferred Southern Cross envelope.
    let mut quality = BTreeMap::new();
    quality.insert("rooms".into(), blueprint.rooms.len() as u32);
    quality.insert("fixtures".into(), blueprint.fixtures.len() as u32);
    quality.insert("networks".into(), blueprint.networks.len() as u32);
    quality.insert(
        "unique_roles".into(),
        blueprint
            .rooms
            .iter()
            .map(|r| r.semantic_role.as_str())
            .collect::<BTreeSet<_>>()
            .len() as u32,
    );
    quality.insert(
        "average_occupancy_micros".into(),
        blueprint
            .rooms
            .iter()
            .map(|r| u64::from(r.occupancy_micros))
            .sum::<u64>()
            .div_ceil(blueprint.rooms.len().max(1) as u64) as u32,
    );
    quality.insert(
        "clustered_fixture_micros".into(),
        (clustered_fixture_total as u64 * 1_000_000 / semantic_fixture_total.max(1) as u64) as u32,
    );
    quality.insert("rooms_with_composition".into(), rooms_with_cluster as u32);
    quality.insert(
        "rooms_matching_counterpart".into(),
        rooms_matching_counterpart as u32,
    );
    quality.insert(
        "rooms_below_counterpart_density".into(),
        rooms_below_counterpart_density as u32,
    );
    quality.insert(
        "rooms_exceeding_counterpart_empty_region".into(),
        rooms_exceeding_counterpart_empty_region as u32,
    );
    quality.insert(
        "average_largest_empty_region_micros".into(),
        empty_region_micros_total.div_ceil(blueprint.rooms.len().max(1) as u64) as u32,
    );
    Ok(quality)
}
