use super::contract::CatalogMapping;
use super::error::LayoutError;
use super::model::*;
use super::program::{
    ActivityZone, ProgramAnchor, ProgramLayer, RoomProgram, compact_room_program, room_program,
};
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::OnceLock;

// Generate above the acceptance floor so final semantic pruning (for example,
// removing chairs whose support moved to a wall) cannot leave the live room
// below 30% visible occupancy.
const MIN_OCCUPANCY_MICROS: u32 = 360_000;
const MAX_OCCUPANCY_MICROS: u32 = 520_000;

#[derive(Clone, Copy)]
struct FixtureSpec {
    id: &'static str,
    layer: FixtureLayer,
}

#[derive(Clone, Copy)]
struct CompositionCell {
    dx: i16,
    dy: i16,
    spec: FixtureSpec,
}

#[derive(Clone, Copy)]
struct CompositionPlacement {
    at: Point,
    facing: Facing,
    spec: FixtureSpec,
}

#[derive(Clone)]
struct AuthoredCompositionPlacement {
    at: Point,
    facing: Facing,
    fixture_id: String,
    layer: FixtureLayer,
}

#[derive(Clone, Copy)]
enum CompositionAnchor {
    Center,
    Perimeter,
    Entrance,
}

#[derive(Clone, Copy)]
struct CounterpartProfile {
    anchor: CompositionAnchor,
    minimum_cluster_micros: u32,
    minimum_unique_fixtures: usize,
    minimum_occupancy_micros: u32,
    target_occupancy_micros: u32,
    maximum_empty_region_micros: u32,
    minimum_fixture_count: usize,
}

#[derive(Deserialize)]
struct SouthernCrossReference {
    profiles: BTreeMap<String, SouthernCrossRoleProfile>,
}

#[derive(Clone, Copy, Deserialize)]
struct SouthernCrossRoleProfile {
    occupancy_p25_micros: u32,
    occupancy_median_micros: u32,
    largest_empty_region_p75_micros: u32,
    unique_fixture_types_p25: usize,
    fixture_count_p25: usize,
}

fn southern_cross_reference() -> &'static SouthernCrossReference {
    static REFERENCE: OnceLock<SouthernCrossReference> = OnceLock::new();
    REFERENCE.get_or_init(|| {
        serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../tools/generated_station/southern_cross_reference.json"
        )))
        .expect("measured Southern Cross room reference must remain valid JSON")
    })
}

pub fn generate_station_blueprint(
    layout: StationLayout,
    mapping: &CatalogMapping,
) -> Result<StationBlueprint, LayoutError> {
    let mut fixtures = Vec::new();
    let mut rooms = Vec::new();
    let door_tiles: BTreeSet<Point> = layout.doors.iter().map(|door| door.at).collect();
    let mut occupied = BTreeSet::new();
    let mut next_fixture_id = 1u32;

    for room in &layout.rooms {
        let assigned_type = mapping.rooms.get(&room.room_type_id).ok_or_else(|| {
            LayoutError(format!(
                "room {} references missing catalog variant",
                room.id
            ))
        })?;
        let room_type = select_richest_variant(mapping, room, &assigned_type.role);
        if room_type.department_id != assigned_type.department_id {
            return Err(LayoutError(format!(
                "room {} crossed department ownership while selecting content ({} -> {})",
                room.id, assigned_type.department_id, room_type.department_id
            )));
        }
        let tiles: BTreeSet<Point> = room.tiles.iter().copied().collect();
        let center = room_center(room, &tiles);
        let mut circulation = vec![center];
        connect_to_circulation(
            &mut circulation,
            room_door_approaches(&layout, room, &tiles, center),
            &tiles,
            layout.width,
            layout.height,
        )?;
        // Reserve only the door-to-activity spine while furnishing. The old
        // pre-decoration coverage expansion marked most of a room as an aisle,
        // which made otherwise valid authored fragments impossible to place.
        // Full every-tile access coverage is derived after all fixtures have
        // been accepted.
        let reserved: BTreeSet<Point> = circulation.iter().copied().collect();
        let wall_candidates = wall_fixture_candidates(&layout, &tiles, &door_tiles);
        let mut floor_candidates: Vec<Point> = tiles
            .iter()
            .copied()
            .filter(|point| !reserved.contains(point) && !door_tiles.contains(point))
            .collect();
        floor_candidates.sort_by_key(|point| (distance(*point, center), point.y, point.x));
        let mut atmosphere_candidates: Vec<Point> = tiles
            .iter()
            .copied()
            .filter(|point| !door_tiles.contains(point))
            .collect();
        atmosphere_candidates.sort_by_key(|point| (distance(*point, center), point.y, point.x));
        let mut room_fixture_ids = Vec::new();
        let mut blocking = BTreeSet::new();
        let mut required_access = BTreeSet::new();

        let wall_specs = [
            FixtureSpec {
                id: "wall_light",
                layer: FixtureLayer::Wall,
            },
            FixtureSpec {
                id: "air_alarm",
                layer: FixtureLayer::Wall,
            },
            FixtureSpec {
                id: "fire_alarm",
                layer: FixtureLayer::Wall,
            },
            FixtureSpec {
                id: "apc",
                layer: FixtureLayer::Wall,
            },
        ];
        let mut used_wall_points = BTreeSet::new();
        for (index, spec) in wall_specs.iter().enumerate() {
            let candidate_index = if wall_candidates.len() <= 1 {
                0
            } else {
                index * (wall_candidates.len() - 1) / (wall_specs.len() - 1)
            };
            if let Some((at, facing)) = wall_candidates.get(candidate_index).copied() {
                used_wall_points.insert(at);
                push_fixture(
                    &mut fixtures,
                    &mut room_fixture_ids,
                    &mut next_fixture_id,
                    *spec,
                    at,
                    facing,
                    room,
                    None,
                    index as u16,
                );
            }
        }
        // Larger rooms receive enough lights to eliminate dark corners.
        let extra_light_candidates = wall_candidates
            .iter()
            .step_by(6)
            .filter(|(at, _)| !used_wall_points.contains(at))
            .copied()
            .collect::<Vec<_>>();
        for (index, (at, facing)) in extra_light_candidates.into_iter().enumerate() {
            used_wall_points.insert(at);
            push_fixture(
                &mut fixtures,
                &mut room_fixture_ids,
                &mut next_fixture_id,
                FixtureSpec {
                    id: "wall_light",
                    layer: FixtureLayer::Wall,
                },
                at,
                facing,
                room,
                None,
                index as u16 + 1,
            );
        }

        // Reserve life-support endpoints before decorative density consumes
        // the usable floor. In very small rooms these are the authoritative
        // contents rather than an optional afterthought.
        let atmosphere_fixture_ids: &[&str] = if floor_candidates.len() >= 4 {
            &["vent", "scrubber"]
        } else if room.id % 2 == 0 {
            &["vent"]
        } else {
            &["scrubber"]
        };
        for (offset, fixture_id) in atmosphere_fixture_ids.iter().copied().enumerate() {
            if let Some(index) = atmosphere_candidates
                .iter()
                .enumerate()
                .filter(|(_, point)| !occupied.contains(*point))
                .min_by_key(|(_, point)| {
                    (
                        !reserved.contains(*point),
                        distance(**point, center),
                        point.y,
                        point.x,
                    )
                })
                .map(|(index, _)| index)
            {
                let at = atmosphere_candidates.remove(index);
                if let Some(index) = floor_candidates.iter().position(|point| *point == at) {
                    floor_candidates.remove(index);
                }
                occupied.insert(at);
                let network = Some(
                    if fixture_id == "vent" {
                        "atmos-supply"
                    } else {
                        "atmos-return"
                    }
                    .into(),
                );
                push_fixture(
                    &mut fixtures,
                    &mut room_fixture_ids,
                    &mut next_fixture_id,
                    FixtureSpec {
                        id: fixture_id,
                        layer: FixtureLayer::Machine,
                    },
                    at,
                    face_toward(at, center),
                    room,
                    network,
                    offset as u16,
                );
            }
        }
        let program = if room_type.definition_id.contains("-compact-")
            || room_type.definition_id.contains("-micro-")
        {
            compact_room_program(
                &room_type.department_id,
                &room_type.role,
                layout.seed ^ u64::from(room.id),
            )
        } else {
            room_program(
                &room_type.department_id,
                &room_type.role,
                layout.seed ^ u64::from(room.id),
            )
        };
        let protected_approaches = room_door_approaches(&layout, room, &tiles, center);
        // Catalog fragments carry the room author's visual composition, while
        // the program carries its guaranteed workflow. Give the authored
        // motif first choice of a wall/center anchor, then ask the workflow
        // placer to compose around it. If a fragment cannot coexist with the
        // required workflow it is discarded atomically and the functional
        // program still succeeds.
        let fragment_reserved = reserved
            .iter()
            .chain(occupied.iter())
            .chain(required_access.iter())
            .chain(protected_approaches.iter())
            .copied()
            .collect::<BTreeSet<_>>();
        let mut fragment_placements = authored_fragment_composition(
            &layout,
            room_type,
            layout.seed ^ u64::from(room.id).rotate_left(17),
            &tiles,
            &fragment_reserved,
            &door_tiles,
            center,
        );
        let mut fragment_blocking = blocking.clone();
        let mut fragment_access = required_access.clone();
        let mut fragments_valid = true;
        let fragment_positions = fragment_placements
            .iter()
            .map(|placement| placement.at)
            .collect::<BTreeSet<_>>();
        for placement in &mut fragment_placements {
            if !fixture_blocks_on_layer(&placement.fixture_id, placement.layer) {
                continue;
            }
            fragment_blocking.insert(placement.at);
            let Some((access, facing)) = [
                placement.facing,
                Facing::North,
                Facing::East,
                Facing::South,
                Facing::West,
            ]
            .into_iter()
            .map(|facing| (step_facing(placement.at, facing), facing))
            .find(|(access, _)| {
                tiles.contains(access)
                    && !fragment_blocking.contains(access)
                    && !fragment_positions.contains(access)
                    && !door_tiles.contains(access)
                    && !protected_approaches.contains(access)
            }) else {
                fragments_valid = false;
                break;
            };
            placement.facing = facing;
            fragment_access.insert(access);
        }
        fragments_valid = fragments_valid
            && !fragment_placements.is_empty()
            && room_walkable_connected(&tiles, &fragment_blocking, layout.width, layout.height);
        let fragment_occupied = fragment_placements
            .iter()
            .map(|placement| placement.at)
            .chain(occupied.iter().copied())
            .collect::<BTreeSet<_>>();
        let program_with_fragments = fragments_valid.then(|| {
            place_room_program(
                &layout,
                &program,
                &tiles,
                &reserved,
                &door_tiles,
                center,
                &fragment_blocking,
                &fragment_access,
                &fragment_occupied,
                &protected_approaches,
            )
        });
        let (program_placements, use_fragments) = match program_with_fragments {
            Some(Ok(placements))
                if fixture_repetitions_within_limits(
                    fragment_placements.iter().chain(placements.iter()),
                ) && placement_seats_are_paired(
                    fragment_placements.iter().chain(placements.iter()),
                ) =>
            {
                (placements, true)
            }
            _ => {
                let primary = place_room_program(
                    &layout,
                    &program,
                    &tiles,
                    &reserved,
                    &door_tiles,
                    center,
                    &blocking,
                    &required_access,
                    &occupied,
                    &protected_approaches,
                );
                match primary {
                    Ok(placements) => (placements, false),
                    Err(primary_error)
                        if !room_type.definition_id.contains("-compact-")
                            && !room_type.definition_id.contains("-micro-") =>
                    {
                        // Irregular but structurally valid envelopes can meet a
                        // full program's area requirement without containing
                        // its two large fixture clusters. Fall back to the
                        // role-specific compact workflow, never generic decor
                        // and never a DM-side materialization failure.
                        let compact = compact_room_program(
                            &room_type.department_id,
                            &room_type.role,
                            layout.seed ^ u64::from(room.id),
                        );
                        let placements = place_room_program(
                            &layout,
                            &compact,
                            &tiles,
                            &reserved,
                            &door_tiles,
                            center,
                            &blocking,
                            &required_access,
                            &occupied,
                            &protected_approaches,
                        )
                        .map_err(|compact_error| {
                            LayoutError(format!(
                                "{}; compact role-specific fallback also failed: {}",
                                primary_error.0, compact_error.0
                            ))
                        })?;
                        (placements, false)
                    }
                    Err(error) => return Err(error),
                }
            }
        };
        if use_fragments {
            let fixture_offset = room_fixture_ids.len();
            for (index, placement) in fragment_placements.into_iter().enumerate() {
                if let Some(selection) = floor_candidates
                    .iter()
                    .position(|candidate| *candidate == placement.at)
                {
                    floor_candidates.remove(selection);
                }
                occupied.insert(placement.at);
                push_authored_fixture(
                    &mut fixtures,
                    &mut room_fixture_ids,
                    &mut next_fixture_id,
                    &placement.fixture_id,
                    placement.layer,
                    placement.at,
                    placement.facing,
                    room,
                    fixture_offset.saturating_add(index) as u16,
                );
            }
            blocking = fragment_blocking;
            required_access = fragment_access;
        }
        let program_offset = room_fixture_ids.len();
        for (index, placement) in program_placements.into_iter().enumerate() {
            if let Some(selection) = floor_candidates
                .iter()
                .position(|candidate| *candidate == placement.at)
            {
                floor_candidates.remove(selection);
            }
            occupied.insert(placement.at);
            if fixture_blocks_on_layer(&placement.fixture_id, placement.layer) {
                blocking.insert(placement.at);
                required_access.insert(step_facing(placement.at, placement.facing));
            }
            push_authored_fixture(
                &mut fixtures,
                &mut room_fixture_ids,
                &mut next_fixture_id,
                &placement.fixture_id,
                placement.layer,
                placement.at,
                placement.facing,
                room,
                program_offset.saturating_add(index) as u16,
            );
        }

        prune_excess_room_repetitions(
            &room_type.role,
            &tiles,
            &door_tiles,
            &mut floor_candidates,
            &mut occupied,
            &mut blocking,
            &mut fixtures,
            &mut room_fixture_ids,
        );
        prune_orphaned_seats(
            &tiles,
            &door_tiles,
            &mut floor_candidates,
            &mut occupied,
            &mut fixtures,
            &mut room_fixture_ids,
        );
        // Authored machines establish the room's permanent operating aisles.
        // Reserve those complete door-to-machine paths before any density
        // furnishing is allowed to consume the remaining floor.
        let authored_walkable = tiles
            .difference(&blocking)
            .copied()
            .collect::<BTreeSet<_>>();
        connect_to_circulation(
            &mut circulation,
            required_access.iter().copied(),
            &authored_walkable,
            layout.width,
            layout.height,
        )?;
        let mut protected_circulation = circulation.iter().copied().collect::<BTreeSet<_>>();
        occupied.extend(circulation.iter().copied());
        floor_candidates.retain(|point| !protected_circulation.contains(point));
        add_tabletop_charger_supports(
            room,
            &mut fixtures,
            &mut room_fixture_ids,
            &mut next_fixture_id,
        );

        // Match the measured Southern Cross furnishing envelope with
        // additional role-specific activity clusters. Infrastructure and wall
        // services do not count: an APC, vent, and light cannot make an empty
        // room pass this stage.
        let profile = counterpart_profile(&room_type.role);
        fill_to_counterpart_density(
            &layout,
            room,
            &room_type.role,
            &tiles,
            &door_tiles,
            center,
            &mut floor_candidates,
            &mut occupied,
            &mut blocking,
            &mut required_access,
            &mut protected_circulation,
            &mut fixtures,
            &mut room_fixture_ids,
            &mut next_fixture_id,
            profile,
        )?;
        blocking = room_fixture_ids
            .iter()
            .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
            .filter(|fixture| fixture.blocks_movement)
            .map(|fixture| fixture.at)
            .collect();
        orient_perimeter_fixtures_into_room(
            room,
            &tiles,
            &blocking,
            &room_fixture_ids,
            &mut fixtures,
            center,
        );
        required_access = room_fixture_ids
            .iter()
            .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
            .flat_map(|fixture| fixture.required_access.iter().copied())
            .collect();
        let walkable: BTreeSet<Point> = tiles.difference(&blocking).copied().collect();
        circulation.clear();
        circulation.push(center);
        connect_to_circulation(
            &mut circulation,
            room_door_approaches(&layout, room, &tiles, center)
                .into_iter()
                .chain(required_access.iter().copied()),
            &walkable,
            layout.width,
            layout.height,
        )?;
        expand_circulation_coverage(&mut circulation, &walkable, layout.width, layout.height)?;

        let floor_occupied = room_fixture_ids
            .iter()
            .filter(|id| {
                fixtures.iter().any(|fixture| {
                    fixture.id == **id
                        && fixture.layer != FixtureLayer::Wall
                        && fixture.layer != FixtureLayer::Ceiling
                        && !matches!(
                            fixture.fixture_id.as_str(),
                            "vent" | "scrubber" | "charger_table"
                        )
                })
            })
            .count();
        let occupancy_micros =
            (floor_occupied as u64 * 1_000_000 / tiles.len().max(1) as u64) as u32;
        rooms.push(RoomBlueprint {
            allocation_id: format!("room-allocation-{}", room.id),
            room_id: room.id,
            department_id: room.department_id,
            semantic_role: room_type.role.clone(),
            selected_variant: program.id,
            area_name: format!(
                "{} {} {}",
                mapping.metadata.name,
                department_name(mapping, room.department_id),
                title(&room_type.role)
            ),
            aesthetic_id: room_type.aesthetic_id.clone(),
            floor_style: floor_style(&room_type.aesthetic_id, &room_type.role).into(),
            accent_style: accent_style(&room_type.department_id, &room_type.role).into(),
            activity_center: center,
            circulation,
            fixture_ids: room_fixture_ids,
            occupancy_micros,
        });
    }

    relocate_wall_services_away_from_furniture(&layout, &mut fixtures);
    prune_orphaned_seats_after_wall_layout(&layout, &mut rooms, &mut fixtures);
    orient_seats_toward_supports(&rooms, &mut fixtures);
    let networks = plan_networks(&layout, &mut fixtures);
    let mut blueprint = StationBlueprint {
        schema: "dq.station.blueprint".into(),
        major: 1,
        minor: 0,
        catalog_hash: mapping.catalog_hash.clone(),
        layout,
        rooms,
        fixtures,
        networks,
        quality: BTreeMap::new(),
        sprite_previews: mapping.sprite_previews.clone(),
    };
    blueprint.quality = validate_station_blueprint(&blueprint)?;
    Ok(blueprint)
}

fn relocate_wall_services_away_from_furniture(
    layout: &StationLayout,
    fixtures: &mut [FixturePlacement],
) {
    let door_tiles = layout
        .doors
        .iter()
        .map(|door| door.at)
        .collect::<BTreeSet<_>>();
    for room in &layout.rooms {
        let room_id = Some(room.id);
        let room_tiles = room.tiles.iter().copied().collect::<BTreeSet<_>>();
        let candidates = wall_fixture_candidates(layout, &room_tiles, &door_tiles)
            .into_iter()
            .collect::<Vec<_>>();
        if candidates.is_empty() {
            continue;
        }
        let service_indices = fixtures
            .iter()
            .enumerate()
            .filter(|(_, fixture)| {
                fixture.room_id == room_id
                    && fixture.layer == FixtureLayer::Wall
                    && fixture_is_wall_mounted(&fixture.fixture_id)
                    && fixture.layer == FixtureLayer::Wall
            })
            .map(|(index, _)| index)
            .collect::<Vec<_>>();
        let mut used = fixtures
            .iter()
            .filter(|fixture| {
                fixture.room_id == room_id
                    && fixture.layer == FixtureLayer::Wall
                    && !fixture_is_wall_mounted(&fixture.fixture_id)
            })
            .map(|fixture| fixture.at)
            .collect::<BTreeSet<_>>();
        for (ordinal, fixture_index) in service_indices.iter().copied().enumerate() {
            let preferred = if service_indices.len() <= 1 {
                0
            } else {
                ordinal * (candidates.len() - 1) / (service_indices.len() - 1)
            };
            let Some(selection) = (0..candidates.len())
                .filter(|index| !used.contains(&candidates[*index].0))
                .min_by_key(|index| index.abs_diff(preferred))
            else {
                break;
            };
            let (at, facing) = candidates[selection];
            used.insert(at);
            fixtures[fixture_index].at = at;
            fixtures[fixture_index].facing = facing;
        }
    }
}

fn prune_orphaned_seats_after_wall_layout(
    layout: &StationLayout,
    rooms: &mut [RoomBlueprint],
    fixtures: &mut Vec<FixturePlacement>,
) {
    let snapshot = fixtures.clone();
    let remove_ids = snapshot
        .iter()
        .filter(|fixture| {
            (fixture.fixture_id.contains("chair") || fixture.fixture_id.contains("stool"))
                && !snapshot.iter().any(|other| {
                    fixture.room_id == other.room_id
                        && fixture.id != other.id
                        && other.layer != FixtureLayer::Wall
                        && other.layer != FixtureLayer::Ceiling
                        && rooms.iter().any(|room| {
                            Some(room.room_id) == other.room_id
                                && room.fixture_ids.contains(&other.id)
                        })
                        && distance(fixture.at, other.at) == 1
                        && fixture_supports_seat(&other.fixture_id)
                })
        })
        .map(|fixture| fixture.id)
        .collect::<BTreeSet<_>>();
    if remove_ids.is_empty() {
        return;
    }
    fixtures.retain(|fixture| !remove_ids.contains(&fixture.id));
    for room in rooms {
        room.fixture_ids.retain(|id| !remove_ids.contains(id));
        let tile_count = layout
            .rooms
            .iter()
            .find(|structural| structural.id == room.room_id)
            .map(|structural| structural.tiles.len())
            .unwrap_or(1);
        let occupied = room
            .fixture_ids
            .iter()
            .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
            .filter(|fixture| {
                fixture.layer != FixtureLayer::Wall
                    && fixture.layer != FixtureLayer::Ceiling
                    && !matches!(
                        fixture.fixture_id.as_str(),
                        "vent" | "scrubber" | "charger_table"
                    )
            })
            .count();
        room.occupancy_micros = (occupied as u64 * 1_000_000 / tile_count.max(1) as u64) as u32;
    }
}

fn orient_seats_toward_supports(rooms: &[RoomBlueprint], fixtures: &mut [FixturePlacement]) {
    let snapshot = fixtures.to_vec();
    for seat in fixtures.iter_mut().filter(|fixture| {
        fixture.fixture_id.contains("chair")
            || matches!(
                fixture.fixture_id.as_str(),
                "stool" | "visitor_bench" | "waiting_bench" | "executive_chair"
            )
    }) {
        let Some(room) = rooms.iter().find(|room| Some(room.room_id) == seat.room_id) else {
            continue;
        };
        let support = snapshot
            .iter()
            .filter(|other| {
                other.id != seat.id
                    && other.room_id == seat.room_id
                    && room.fixture_ids.contains(&other.id)
                    && distance(seat.at, other.at) == 1
                    && fixture_supports_seat(&other.fixture_id)
            })
            .min_by_key(|other| (other.id, other.at.y, other.at.x));
        if let Some(support) = support {
            // `facing` is the object's visual/DM direction. Interaction access
            // is stored independently in `required_access`, so a chair should
            // look toward its desk/table without moving the protected aisle.
            seat.facing = face_toward(seat.at, support.at);
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn fill_to_counterpart_density(
    layout: &StationLayout,
    room: &Room,
    role: &str,
    tiles: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    center: Point,
    floor_candidates: &mut Vec<Point>,
    occupied: &mut BTreeSet<Point>,
    blocking: &mut BTreeSet<Point>,
    required_access: &mut BTreeSet<Point>,
    protected_circulation: &mut BTreeSet<Point>,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
    next_fixture_id: &mut u32,
    profile: CounterpartProfile,
) -> Result<(), LayoutError> {
    let mut palette = semantic_fixture_program(role);
    palette.extend(semantic_fillers(role));
    palette.retain(|spec| {
        !spec.id.contains("chair")
            && !matches!(spec.id, "stool" | "visitor_bench" | "waiting_bench")
            && !fixture_is_wall_mounted(spec.id)
            && !spec.id.contains("table")
            && !spec.id.contains("desk")
    });
    let mut seen_palette = BTreeSet::new();
    palette.retain(|spec| seen_palette.insert(spec.id));
    if palette.is_empty() {
        return Ok(());
    }
    let functional = |fixture: &&FixturePlacement| {
        fixture.room_id == Some(room.id)
            && fixture.layer != FixtureLayer::Wall
            && fixture.layer != FixtureLayer::Ceiling
            && !matches!(
                fixture.fixture_id.as_str(),
                "vent" | "scrubber" | "charger_table"
            )
    };
    let target_density = profile
        .target_occupancy_micros
        .clamp(MIN_OCCUPANCY_MICROS, MAX_OCCUPANCY_MICROS);
    let target_count =
        (u64::from(target_density) * tiles.len() as u64).div_ceil(1_000_000) as usize;
    // Leave one non-seat fixture of headroom for final wall-service relocation.
    // That pass can invalidate and prune a chair/support pairing; without this
    // reserve an otherwise authored room landed just below its visible-density
    // floor after finalization.
    let target_count = target_count
        .max(profile.minimum_fixture_count)
        .saturating_add(usize::from(tiles.len() >= 20));
    let mut placed_count = fixtures.iter().filter(functional).count();
    let mut repeat_counts = BTreeMap::<String, usize>::new();
    for fixture in fixtures.iter().filter(functional) {
        *repeat_counts.entry(fixture.fixture_id.clone()).or_default() += 1;
    }
    let mut iteration = 0usize;
    let mut active_cluster = None;
    while placed_count < target_count && !floor_candidates.is_empty() {
        let spec = palette
            .iter()
            .cycle()
            .skip(iteration % palette.len())
            .take(palette.len())
            .find(|spec| {
                repeat_counts.get(spec.id).copied().unwrap_or(0)
                    < fixture_repeat_limit_for_role(role, spec.id)
            })
            .copied();
        let Some(spec) = spec else {
            break;
        };
        let establish_new_cluster = active_cluster.is_none() || iteration % 6 == 0;
        let mut candidates = floor_candidates
            .iter()
            .copied()
            .filter(|point| {
                !occupied.contains(point)
                    && !required_access.contains(point)
                    && !protected_circulation.contains(point)
                    && !doors.contains(point)
            })
            .collect::<Vec<_>>();
        candidates.sort_by_key(|point| {
            let nearest = occupied
                .iter()
                .map(|other| distance(*point, *other))
                .min()
                .unwrap_or(distance(*point, center));
            let distribution = if establish_new_cluster {
                u16::MAX - nearest
            } else {
                distance(*point, active_cluster.unwrap_or(center))
            };
            (
                u8::from(
                    fixture_prefers_corner(spec.id) && wall_neighbor_count(layout, *point) < 2,
                ),
                u8::from(fixture_prefers_perimeter(spec.id) && !adjacent_to_wall(layout, *point)),
                distribution,
                composition_hash(layout.seed ^ iteration as u64, *point),
            )
        });
        let selected = candidates.into_iter().find_map(|at| {
            if !fixture_blocks(spec.id) {
                return Some((at, face_toward(at, center), None));
            }
            let mut trial_blocking = blocking.clone();
            trial_blocking.insert(at);
            if !room_walkable_connected(tiles, &trial_blocking, layout.width, layout.height) {
                return None;
            }
            [Facing::North, Facing::East, Facing::South, Facing::West]
                .into_iter()
                .map(|facing| (step_facing(at, facing), facing))
                .find(|(access, _)| {
                    tiles.contains(access)
                        && !trial_blocking.contains(access)
                        && !occupied.contains(access)
                        && !doors.contains(access)
                })
                .map(|(access, facing)| (at, facing, Some(access)))
        });
        let Some((at, facing, access)) = selected else {
            repeat_counts.insert(spec.id.into(), fixture_repeat_limit_for_role(role, spec.id));
            iteration += 1;
            if iteration > palette.len().saturating_mul(4) {
                break;
            }
            continue;
        };
        floor_candidates.retain(|point| *point != at);
        occupied.insert(at);
        if establish_new_cluster {
            active_cluster = Some(at);
        }
        if fixture_blocks(spec.id) {
            blocking.insert(at);
        }
        if let Some(access) = access {
            let walkable = tiles.difference(blocking).copied().collect::<BTreeSet<_>>();
            let mut protected_route = protected_circulation.iter().copied().collect::<Vec<_>>();
            if protected_route.is_empty() {
                protected_route.push(center);
            }
            connect_to_circulation(
                &mut protected_route,
                [access],
                &walkable,
                layout.width,
                layout.height,
            )?;
            protected_circulation.extend(protected_route.iter().copied());
            required_access.insert(access);
            occupied.extend(protected_route.iter().copied());
            floor_candidates.retain(|point| !protected_circulation.contains(point));
        }
        let variant = room_fixture_ids.len() as u16;
        push_fixture(
            fixtures,
            room_fixture_ids,
            next_fixture_id,
            spec,
            at,
            facing,
            room,
            None,
            variant,
        );
        *repeat_counts.entry(spec.id.into()).or_default() += 1;
        placed_count += 1;
        iteration += 1;
    }
    Ok(())
}

fn place_room_program(
    layout: &StationLayout,
    program: &RoomProgram,
    tiles: &BTreeSet<Point>,
    reserved: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    center: Point,
    initial_blocking: &BTreeSet<Point>,
    initial_required_access: &BTreeSet<Point>,
    initial_occupied: &BTreeSet<Point>,
    protected_approaches: &BTreeSet<Point>,
) -> Result<Vec<AuthoredCompositionPlacement>, LayoutError> {
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
struct ZonePlacementEnv<'a> {
    layout: &'a StationLayout,
    tiles: &'a BTreeSet<Point>,
    doors: &'a BTreeSet<Point>,
    center: Point,
}

/// Tries to place every fixture of `zone`, anchored at `anchor` and rotated
/// `turns` quarter-turns (see `program_rotate_offset`), without colliding
/// with `occupied`/`env.doors`/`blocking`/`required_access` and without
/// leaving the room's walkable area disconnected. Returns the placements
/// plus the blocking/access point sets they would add, or `None` if this
/// anchor/rotation doesn't fit -- the caller then retries with the next
/// rotation, and failing all 4, the next anchor.
fn try_place_zone_at(
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

#[allow(clippy::too_many_arguments)]
fn place_adaptive_activity_zone(
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

#[allow(clippy::too_many_arguments)]
fn place_adaptive_fixture_sequence(
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

fn program_rotate_offset(dx: i16, dy: i16, turns: usize) -> (i16, i16) {
    match turns % 4 {
        0 => (dx, dy),
        1 => (-dy, dx),
        2 => (-dx, -dy),
        _ => (dy, -dx),
    }
}

fn wall_fixture_facing(layout: &StationLayout, at: Point) -> Option<Facing> {
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

fn opposite_facing(facing: Facing) -> Facing {
    match facing {
        Facing::North => Facing::South,
        Facing::East => Facing::West,
        Facing::South => Facing::North,
        Facing::West => Facing::East,
    }
}

fn stable_text_hash(value: &str) -> u64 {
    value.bytes().fold(0xcbf29ce484222325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3)
    })
}

fn room_walkable_connected(
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

fn largest_region_size(
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

fn push_fixture(
    fixtures: &mut Vec<FixturePlacement>,
    room_ids: &mut Vec<u32>,
    next: &mut u32,
    spec: FixtureSpec,
    at: Point,
    facing: Facing,
    room: &Room,
    network_id: Option<String>,
    variant: u16,
) {
    let id = *next;
    *next += 1;
    fixtures.push(FixturePlacement {
        id,
        fixture_id: spec.id.into(),
        at,
        facing,
        layer: spec.layer,
        department_id: room.department_id,
        room_id: Some(room.id),
        network_id,
        variant,
        blocks_movement: fixture_blocks_on_layer(spec.id, spec.layer),
        required_access: if fixture_blocks_on_layer(spec.id, spec.layer) {
            vec![step_facing(at, facing)]
        } else {
            Vec::new()
        },
    });
    room_ids.push(id);
}

fn push_authored_fixture(
    fixtures: &mut Vec<FixturePlacement>,
    room_ids: &mut Vec<u32>,
    next: &mut u32,
    fixture_id: &str,
    layer: FixtureLayer,
    at: Point,
    facing: Facing,
    room: &Room,
    variant: u16,
) {
    let id = *next;
    *next += 1;
    let blocks_movement = fixture_blocks_on_layer(fixture_id, layer);
    fixtures.push(FixturePlacement {
        id,
        fixture_id: fixture_id.to_string(),
        at,
        facing,
        layer,
        department_id: room.department_id,
        room_id: Some(room.id),
        network_id: None,
        variant,
        blocks_movement,
        required_access: if blocks_movement {
            vec![step_facing(at, facing)]
        } else {
            Vec::new()
        },
    });
    room_ids.push(id);
}

fn room_center(room: &Room, tiles: &BTreeSet<Point>) -> Point {
    let target = Point {
        x: room.bounds.x + room.bounds.width / 2,
        y: room.bounds.y + room.bounds.height / 2,
    };
    tiles
        .iter()
        .copied()
        .min_by_key(|p| (distance(*p, target), p.y, p.x))
        .unwrap_or(target)
}

fn room_door_approaches(
    layout: &StationLayout,
    room: &Room,
    allowed: &BTreeSet<Point>,
    center: Point,
) -> BTreeSet<Point> {
    let mut approaches = BTreeSet::new();
    for door in room.door_ids.iter().filter_map(|id| {
        layout
            .doors
            .iter()
            .find(|door| door.id == *id)
            .map(|door| door.at)
    }) {
        if let Some(approach) = neighbors(layout, door)
            .into_iter()
            .filter(|point| allowed.contains(point))
            .min_by_key(|point| {
                (
                    !approaches.contains(point),
                    distance(*point, center),
                    point.y,
                    point.x,
                )
            })
        {
            approaches.insert(approach);
        }
    }
    approaches
}

fn authored_fragment_composition(
    layout: &StationLayout,
    room_type: &CatalogRoomWire,
    seed: u64,
    tiles: &BTreeSet<Point>,
    reserved: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    center: Point,
) -> Vec<AuthoredCompositionPlacement> {
    let usable = room_type
        .fragments
        .iter()
        .filter(|fragment| !fragment.features.is_empty())
        .collect::<Vec<_>>();
    if usable.is_empty() {
        return Vec::new();
    }
    let start = usize::try_from(seed % usable.len() as u64).unwrap_or(0);
    let motif_target = (tiles.len() / 28).clamp(1, 3).min(usable.len());
    let mut result = Vec::new();
    let mut claimed = BTreeSet::new();
    for offset in 0..usable.len() {
        if result.len() / 4 >= motif_target {
            break;
        }
        let fragment = usable[(start + offset) % usable.len()];
        let mut origins = tiles.iter().copied().collect::<Vec<_>>();
        origins.sort_by_key(|origin| {
            let points = fragment
                .features
                .iter()
                .filter_map(|feature| fragment_feature_point(*origin, feature))
                .collect::<Vec<_>>();
            let perimeter = points
                .iter()
                .filter(|point| {
                    point_neighbors(**point, u16::MAX, u16::MAX)
                        .into_iter()
                        .any(|neighbor| !tiles.contains(&neighbor))
                })
                .count();
            let door_distance = points
                .iter()
                .flat_map(|point| doors.iter().map(move |door| distance(*point, *door)))
                .min()
                .unwrap_or(u16::MAX);
            let center_distance = points
                .iter()
                .map(|point| distance(*point, center))
                .min()
                .unwrap_or(u16::MAX);
            let anchor_score = match fragment.anchor_kind.as_str() {
                "wall" => usize::MAX - perimeter,
                "entrance" | "door" => usize::from(door_distance),
                _ => usize::from(center_distance),
            };
            (
                anchor_score,
                composition_hash(seed ^ hash_text(&fragment.id), *origin),
            )
        });
        for origin in origins {
            let Some(points) = fragment
                .features
                .iter()
                .map(|feature| fragment_feature_point(origin, feature))
                .collect::<Option<Vec<_>>>()
            else {
                continue;
            };
            if points.iter().any(|point| {
                !tiles.contains(point)
                    || reserved.contains(point)
                    || doors.contains(point)
                    || claimed.contains(point)
                    || claimed
                        .iter()
                        .any(|occupied| distance(*occupied, *point) < 2)
            }) || points.iter().copied().collect::<BTreeSet<_>>().len() != points.len()
            {
                continue;
            }
            let wall_facings = fragment
                .features
                .iter()
                .zip(&points)
                .map(|(feature, point)| {
                    if feature.placement_kind != "wall" {
                        return Some(face_toward(*point, center));
                    }
                    directed_neighbors(layout, *point)
                        .into_iter()
                        .find_map(|(neighbor, facing)| {
                            matches!(
                                layout.tile(neighbor).class,
                                TileClass::Hull | TileClass::Structure | TileClass::Partition
                            )
                            .then_some(facing)
                        })
                })
                .collect::<Option<Vec<_>>>();
            let Some(wall_facings) = wall_facings else {
                continue;
            };
            claimed.extend(points.iter().copied());
            result.extend(fragment.features.iter().zip(points).zip(wall_facings).map(
                |((feature, at), facing)| AuthoredCompositionPlacement {
                    at,
                    facing,
                    fixture_id: feature.id.clone(),
                    layer: if feature.placement_kind == "wall" {
                        FixtureLayer::Wall
                    } else {
                        FixtureLayer::Furniture
                    },
                },
            ));
            break;
        }
    }
    result
}

fn fragment_feature_point(origin: Point, feature: &FragmentFeatureWire) -> Option<Point> {
    let x = i32::from(origin.x) + i32::from(feature.dx) - 1;
    let y = i32::from(origin.y) + i32::from(feature.dy) - 1;
    (x >= 0 && y >= 0 && x <= i32::from(u16::MAX) && y <= i32::from(u16::MAX)).then_some(Point {
        x: x as u16,
        y: y as u16,
    })
}

fn hash_text(value: &str) -> u64 {
    value.bytes().fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x1000_0000_01b3)
    })
}

fn expand_circulation_coverage(
    circulation: &mut Vec<Point>,
    allowed: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> Result<(), LayoutError> {
    let mut connected: BTreeSet<Point> = circulation.iter().copied().collect();
    // Grow sparse, deterministic aisle branches through the furnished room
    // until every usable floor tile is on or cardinally adjacent to one.
    loop {
        let target = allowed
            .iter()
            .copied()
            .filter_map(|point| {
                let nearest = connected
                    .iter()
                    .map(|aisle| distance(point, *aisle))
                    .min()
                    .unwrap_or(u16::MAX);
                (nearest > 1).then_some((nearest, point))
            })
            .max_by_key(|(nearest, point)| (*nearest, point.y, point.x))
            .map(|(_, point)| point);
        let Some(target) = target else {
            break;
        };
        connect_points(&mut connected, [target], allowed, width, height)?;
    }
    *circulation = connected.into_iter().collect();
    Ok(())
}

fn connect_to_circulation(
    circulation: &mut Vec<Point>,
    terminals: impl IntoIterator<Item = Point>,
    allowed: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> Result<(), LayoutError> {
    let mut connected: BTreeSet<Point> = circulation.iter().copied().collect();
    connect_points(&mut connected, terminals, allowed, width, height)?;
    *circulation = connected.into_iter().collect();
    Ok(())
}

fn connect_points(
    circulation: &mut BTreeSet<Point>,
    terminals: impl IntoIterator<Item = Point>,
    allowed: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> Result<(), LayoutError> {
    for terminal in terminals {
        if circulation.contains(&terminal) {
            continue;
        }
        let mut goals: Vec<Point> = circulation.iter().copied().collect();
        goals.sort_by_key(|goal| (distance(terminal, *goal), goal.y, goal.x));
        let path = goals
            .into_iter()
            .find_map(|goal| shortest_path(terminal, goal, allowed, width, height))
            .ok_or_else(|| {
                LayoutError(format!(
                    "cannot connect room circulation terminal at {},{}",
                    terminal.x, terminal.y
                ))
            })?;
        circulation.extend(path);
    }
    Ok(())
}

fn shortest_path(
    start: Point,
    goal: Point,
    allowed: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> Option<Vec<Point>> {
    let mut queue = VecDeque::from([start]);
    let mut previous = BTreeMap::new();
    previous.insert(start, start);
    while let Some(point) = queue.pop_front() {
        if point == goal {
            break;
        }
        for next in point_neighbors(point, width, height) {
            if allowed.contains(&next) && !previous.contains_key(&next) {
                previous.insert(next, point);
                queue.push_back(next);
            }
        }
    }
    if !previous.contains_key(&goal) {
        return None;
    }
    let mut path = vec![goal];
    let mut at = goal;
    while at != start {
        at = previous[&at];
        path.push(at);
    }
    path.reverse();
    Some(path)
}

fn wall_fixture_candidates(
    layout: &StationLayout,
    tiles: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
) -> Vec<(Point, Facing)> {
    let mut result = Vec::new();
    for point in tiles {
        if doors.contains(point) {
            continue;
        }
        for (next, facing) in directed_neighbors(layout, *point) {
            if matches!(
                layout.tile(next).class,
                TileClass::Hull | TileClass::Structure | TileClass::Partition
            ) {
                result.push((*point, facing));
                break;
            }
        }
    }
    result.sort_by_key(|(p, f)| (p.y, p.x, *f as u8));
    result
}

fn plan_networks(
    layout: &StationLayout,
    fixtures: &mut [FixturePlacement],
) -> Vec<UtilityNetworkBlueprint> {
    let backbone: Vec<Point> = layout
        .tiles
        .iter()
        .enumerate()
        .filter_map(|(index, cell)| {
            matches!(cell.class, TileClass::Maintenance | TileClass::Local).then_some(Point {
                x: index as u16 % layout.width,
                y: index as u16 / layout.width,
            })
        })
        .collect();
    ["power", "atmos-supply", "atmos-return"]
        .into_iter()
        .map(|kind| UtilityNetworkBlueprint {
            id: format!("station-{kind}"),
            kind: kind.into(),
            backbone: backbone.clone(),
            endpoint_fixture_ids: fixtures
                .iter_mut()
                .filter_map(|fixture| {
                    let matches = (kind == "power" && fixture.fixture_id == "apc")
                        || fixture.network_id.as_deref() == Some(kind);
                    if matches {
                        fixture.network_id = Some(format!("station-{kind}"));
                        Some(fixture.id)
                    } else {
                        None
                    }
                })
                .collect(),
        })
        .collect()
}

fn semantic_composition(
    role: &str,
    seed: u64,
    tiles: &BTreeSet<Point>,
    reserved: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    center: Point,
) -> Vec<CompositionPlacement> {
    let profile = counterpart_profile(role);
    let furniture = |id| FixtureSpec {
        id,
        layer: FixtureLayer::Furniture,
    };
    let machine = |id| FixtureSpec {
        id,
        layer: FixtureLayer::Machine,
    };
    let cells = if has(role, &["surgery", "treatment", "exam", "medical"]) {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("operating_table"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: machine("anesthetic"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: machine("medical_console"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("instrument_table"),
            },
            CompositionCell {
                dx: 2,
                dy: 0,
                spec: furniture("medical_cabinet"),
            },
        ]
    } else if has(role, &["laboratory", "research", "analysis"]) {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("experiment_table"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: machine("analyzer"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: machine("research_console"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("reagent_storage"),
            },
            CompositionCell {
                dx: 0,
                dy: -1,
                spec: furniture("stool"),
            },
        ]
    } else if has(role, &["security", "armory", "brig", "evidence"]) {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: machine("security_console"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("weapon_rack"),
            },
            CompositionCell {
                dx: 2,
                dy: 0,
                spec: furniture("secure_locker"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("chair"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("evidence_cabinet"),
            },
        ]
    } else if has(role, &["engineering", "workshop", "equipment", "power"]) {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("workbench"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("tool_rack"),
            },
            CompositionCell {
                dx: 2,
                dy: 0,
                spec: furniture("parts_bin"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: machine("engineering_console"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("stool"),
            },
        ]
    } else if has(role, &["command", "operations", "meeting", "briefing"]) {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("conference_table"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("conference_table"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("executive_chair"),
            },
            CompositionCell {
                dx: 2,
                dy: 0,
                spec: furniture("executive_chair"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: machine("command_console"),
            },
        ]
    } else if has(role, &["kitchen", "galley", "food"]) {
        vec![
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: machine("grill"),
            },
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("food_prep"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("sink"),
            },
            CompositionCell {
                dx: 2,
                dy: 0,
                spec: furniture("fridge"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("serving_counter"),
            },
        ]
    } else if has(role, &["hydro", "garden", "botany"]) {
        vec![
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("hydroponics_tray"),
            },
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("hydroponics_tray"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("hydroponics_tray"),
            },
            CompositionCell {
                dx: -1,
                dy: 1,
                spec: furniture("hydroponics_tray"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: machine("plant_analyzer"),
            },
            CompositionCell {
                dx: 1,
                dy: 1,
                spec: furniture("produce_bin"),
            },
        ]
    } else if has(role, &["warehouse", "sorting", "inventory"]) {
        vec![
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: machine("disposal_unit"),
            },
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("supply_crate"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("loading_table"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("crate_rack"),
            },
            CompositionCell {
                dx: 0,
                dy: -1,
                spec: machine("cargo_console"),
            },
        ]
    } else if has(role, &["cargo", "storage"]) {
        vec![
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("crate_rack"),
            },
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("loading_table"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("crate_rack"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: machine("package_scanner"),
            },
            CompositionCell {
                dx: 0,
                dy: -1,
                spec: furniture("freight_cart"),
            },
        ]
    } else if has(role, &["ai", "core", "satellite", "monitoring"]) {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: machine("ai_core"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("server_rack"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("server_rack"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: machine("coolant_unit"),
            },
            CompositionCell {
                dx: 0,
                dy: -1,
                spec: machine("control_console"),
            },
        ]
    } else if has(role, &["reception", "foyer", "liaison"]) {
        vec![
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("reception_desk"),
            },
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: machine("visitor_console"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: furniture("reception_desk"),
            },
            CompositionCell {
                dx: -1,
                dy: 2,
                spec: furniture("waiting_bench"),
            },
            CompositionCell {
                dx: 1,
                dy: 2,
                spec: furniture("waiting_bench"),
            },
        ]
    } else {
        vec![
            CompositionCell {
                dx: 0,
                dy: 0,
                spec: furniture("worktable"),
            },
            CompositionCell {
                dx: 1,
                dy: 0,
                spec: machine("role_console"),
            },
            CompositionCell {
                dx: -1,
                dy: 0,
                spec: furniture("department_locker"),
            },
            CompositionCell {
                dx: 0,
                dy: 1,
                spec: furniture("chair"),
            },
        ]
    };

    let mut anchors = tiles
        .iter()
        .copied()
        .filter(|point| !reserved.contains(point) && !doors.contains(point))
        .collect::<Vec<_>>();
    anchors.sort_by_key(|point| {
        let center_distance = distance(*point, center);
        let perimeter_distance = tiles
            .iter()
            .filter(|tile| {
                point_neighbors(**tile, u16::MAX, u16::MAX)
                    .into_iter()
                    .any(|neighbor| !tiles.contains(&neighbor))
            })
            .map(|edge| distance(*point, *edge))
            .min()
            .unwrap_or(0);
        let entrance_distance = doors
            .iter()
            .map(|door| distance(*point, *door))
            .min()
            .unwrap_or(center_distance);
        let anchor_score = match profile.anchor {
            CompositionAnchor::Center => center_distance,
            CompositionAnchor::Perimeter => perimeter_distance,
            CompositionAnchor::Entrance => entrance_distance,
        };
        (
            anchor_score,
            composition_hash(seed, *point),
            point.y,
            point.x,
        )
    });
    let start_rotation = usize::try_from(seed & 3).unwrap_or(0);
    let composition_sizes = [cells.len(), cells.len().min(3)];
    for composition_size in composition_sizes {
        for rotation_offset in 0..4 {
            let rotation = (start_rotation + rotation_offset) % 4;
            for anchor in &anchors {
                let transformed = cells
                    .iter()
                    .take(composition_size)
                    .filter_map(|cell| {
                        let (dx, dy) = rotate_offset(cell.dx, cell.dy, rotation);
                        let x = i32::from(anchor.x) + i32::from(dx);
                        let y = i32::from(anchor.y) + i32::from(dy);
                        if x < 0 || y < 0 {
                            return None;
                        }
                        Some((
                            Point {
                                x: u16::try_from(x).ok()?,
                                y: u16::try_from(y).ok()?,
                            },
                            cell.spec,
                        ))
                    })
                    .collect::<Vec<_>>();
                if transformed.len() != composition_size
                    || transformed.iter().any(|(at, _)| {
                        !tiles.contains(at) || reserved.contains(at) || doors.contains(at)
                    })
                {
                    continue;
                }
                return transformed
                    .into_iter()
                    .map(|(at, spec)| CompositionPlacement {
                        at,
                        facing: if at == *anchor {
                            face_toward(at, center)
                        } else {
                            face_toward(at, *anchor)
                        },
                        spec,
                    })
                    .collect();
            }
        }
    }
    Vec::new()
}

fn counterpart_profile(role: &str) -> CounterpartProfile {
    let (reference_role, anchor, minimum_cluster_micros) = if has(role, &["surgery"]) {
        ("surgery", CompositionAnchor::Center, 650_000)
    } else if has(role, &["treatment", "exam", "emergency"]) {
        ("treatment", CompositionAnchor::Center, 650_000)
    } else if has(role, &["ward", "recovery"]) {
        ("ward", CompositionAnchor::Perimeter, 600_000)
    } else if has(role, &["laboratory", "research", "analysis"]) {
        ("laboratory", CompositionAnchor::Center, 650_000)
    } else if has(role, &["ai", "core", "server"]) {
        ("ai", CompositionAnchor::Center, 650_000)
    } else if has(role, &["armory"]) {
        ("armory", CompositionAnchor::Perimeter, 650_000)
    } else if has(role, &["brig", "interrogation", "checkpoint"]) {
        ("brig", CompositionAnchor::Entrance, 600_000)
    } else if has(role, &["security", "evidence", "locker-room"]) {
        ("security", CompositionAnchor::Entrance, 600_000)
    } else if has(
        role,
        &["operations", "communications", "briefing", "meeting"],
    ) {
        ("operations", CompositionAnchor::Center, 650_000)
    } else if has(role, &["office", "records", "liaison"]) {
        ("office", CompositionAnchor::Center, 600_000)
    } else if has(role, &["reception", "foyer"]) {
        ("reception", CompositionAnchor::Entrance, 600_000)
    } else if has(
        role,
        &["storage", "warehouse", "cargo", "inventory", "equipment"],
    ) {
        ("storage", CompositionAnchor::Perimeter, 600_000)
    } else if has(role, &["workshop", "engineering", "power", "tool-room"]) {
        ("workshop", CompositionAnchor::Perimeter, 600_000)
    } else if has(role, &["atmospherics", "maintenance"]) {
        ("atmospherics", CompositionAnchor::Perimeter, 550_000)
    } else if has(role, &["dispatch", "processing", "cargo"]) {
        ("cargo", CompositionAnchor::Perimeter, 600_000)
    } else if has(role, &["docking", "customs", "control"]) {
        ("docking", CompositionAnchor::Entrance, 550_000)
    } else if has(role, &["robotics"]) {
        ("robotics", CompositionAnchor::Center, 600_000)
    } else {
        ("general", CompositionAnchor::Center, 550_000)
    };
    let measured = southern_cross_reference()
        .profiles
        .get(reference_role)
        .or_else(|| southern_cross_reference().profiles.get("general"))
        .expect("Southern Cross reference must contain a general profile");
    CounterpartProfile {
        anchor,
        minimum_cluster_micros,
        // The DMM contains incidental item subfamilies that the blueprint
        // intentionally represents as one semantic fixture category.
        minimum_unique_fixtures: measured.unique_fixture_types_p25.clamp(4, 8),
        // Very large hangars legitimately lower the mapped p25. Generated
        // activity rooms are smaller, so never accept the visually empty tail.
        minimum_occupancy_micros: measured.occupancy_p25_micros.clamp(250_000, 550_000),
        target_occupancy_micros: measured.occupancy_median_micros.clamp(320_000, 550_000),
        maximum_empty_region_micros: measured.largest_empty_region_p75_micros.min(750_000),
        // Absolute counts are size-sensitive; cap the mapped p25 while density
        // and empty-region ratios carry the scale-independent comparison.
        minimum_fixture_count: measured.fixture_count_p25.clamp(4, 12),
    }
}

fn rotate_offset(dx: i16, dy: i16, rotation: usize) -> (i16, i16) {
    match rotation % 4 {
        0 => (dx, dy),
        1 => (-dy, dx),
        2 => (-dx, -dy),
        _ => (dy, -dx),
    }
}

fn composition_hash(mut seed: u64, point: Point) -> u64 {
    seed ^= u64::from(point.x) << 32 | u64::from(point.y);
    seed ^= seed >> 30;
    seed = seed.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    seed ^= seed >> 27;
    seed = seed.wrapping_mul(0x94d0_49bb_1331_11eb);
    seed ^ (seed >> 31)
}

fn semantic_fixture_program(role: &str) -> Vec<FixtureSpec> {
    let ids: &[&str] = if has(role, &["armory"]) {
        &[
            "armory_autolathe",
            "secure_locker",
            "weapon_rack",
            "security_console",
        ]
    } else if has(role, &["evidence"]) {
        &[
            "security_records",
            "filing_cabinet",
            "evidence_cabinet",
            "secure_locker",
        ]
    } else if has(role, &["records", "archive"]) {
        &[
            "role_console",
            "filing_cabinet",
            "id_console",
            "worktable",
            "chair",
        ]
    } else if has(role, &["robotics", "server-closet"]) {
        &["robotics_console", "autolathe", "server_rack", "worktable"]
    } else if has(role, &["interrogation", "checkpoint"]) {
        &[
            "security_records",
            "reinforced_table",
            "chair",
            "secure_locker",
        ]
    } else if has(role, &["pharmacy"]) {
        &["chem_master", "reagent_grinder", "sink", "medical_cabinet"]
    } else if has(role, &["recovery"]) {
        &["sleeper", "iv_drip", "medical_bed", "medical_cabinet"]
    } else if has(role, &["maintenance"]) {
        &["autolathe", "air_sensor", "workbench", "tool_rack"]
    } else if has(role, &["dispatch"]) {
        &[
            "supply_console",
            "communications_console",
            "loading_table",
            "crate_rack",
        ]
    } else if has(role, &["customs"]) {
        &["id_console", "security_records", "filing_cabinet", "chair"]
    } else if has(role, &["exam"]) {
        &["sink", "medical_vendor", "medical_bed", "medical_cabinet"]
    } else if has(role, &["surgery", "treatment"]) {
        &[
            "operating_table",
            "medical_console",
            "anesthetic",
            "medical_cabinet",
            "sink",
        ]
    } else if has(role, &["laboratory", "research", "analysis"]) {
        &[
            "research_console",
            "experiment_table",
            "analyzer",
            "reagent_storage",
            "server",
        ]
    } else if has(role, &["security", "armory", "brig", "evidence"]) {
        &[
            "security_console",
            "security_records",
            "weapon_rack",
            "secure_locker",
            "evidence_cabinet",
            "flash",
        ]
    } else if has(role, &["workshop", "equipment", "tool-room"]) {
        &["autolathe", "electrical_locker", "workbench", "tool_rack"]
    } else if has(role, &["engineering", "power"]) {
        &[
            "engineering_console",
            "workbench",
            "tool_rack",
            "parts_bin",
            "generator_control",
        ]
    } else if has(role, &["command", "operations", "meeting", "briefing"]) {
        &[
            "command_console",
            "holotable",
            "conference_table",
            "executive_chair",
            "filing_cabinet",
        ]
    } else if has(role, &["kitchen", "galley", "food"]) {
        &["grill", "food_prep", "sink", "fridge", "serving_counter"]
    } else if has(role, &["hydro", "garden", "botany"]) {
        &[
            "hydroponics_tray",
            "seed_extractor",
            "plant_analyzer",
            "water_tank",
            "produce_bin",
        ]
    } else if has(
        role,
        &["warehouse", "cargo", "sorting", "storage", "inventory"],
    ) {
        &[
            "supply_crate",
            "disposal_unit",
            "cargo_console",
            "loading_table",
            "crate_rack",
            "package_scanner",
        ]
    } else if has(role, &["ai", "core", "satellite", "monitoring"]) {
        &[
            "ai_core",
            "server_rack",
            "control_console",
            "coolant_unit",
            "data_terminal",
        ]
    } else if has(role, &["reception", "foyer", "liaison"]) {
        &[
            "reception_desk",
            "visitor_console",
            "filing_cabinet",
            "waiting_bench",
            "plant",
        ]
    } else {
        &[
            "role_console",
            "worktable",
            "department_locker",
            "filing_cabinet",
            "chair",
        ]
    };
    ids.iter()
        .map(|id| FixtureSpec {
            id,
            layer: if id.contains("console") || id.contains("analyzer") || id.contains("core") {
                FixtureLayer::Machine
            } else {
                FixtureLayer::Furniture
            },
        })
        .collect()
}

fn compact_department_fixture_program(department_id: &str) -> Vec<FixtureSpec> {
    let ids: &[&str] = match department_id {
        "command" => &["role_console", "filing_cabinet"],
        "ai" => &["ai_core", "filing_cabinet"],
        "security" => &["server_rack", "secure_locker"],
        "medical" => &["sleeper", "medical_locker"],
        "engineering" => &["autolathe", "electrical_locker"],
        "logistics" => &["cargo_console", "supply_crate"],
        "docking" => &["communications_console", "secure_locker"],
        _ => &["role_console", "filing_cabinet"],
    };
    ids.iter()
        .map(|id| FixtureSpec {
            id,
            layer: if id.contains("console")
                || matches!(*id, "ai_core" | "server_rack" | "sleeper" | "autolathe")
            {
                FixtureLayer::Machine
            } else {
                FixtureLayer::Furniture
            },
        })
        .collect()
}

fn semantic_fillers(role: &str) -> Vec<FixtureSpec> {
    let ids: &[&str] = if has(
        role,
        &[
            "storage",
            "warehouse",
            "cargo",
            "equipment",
            "inventory",
            "sorting",
        ],
    ) {
        &[
            "crate_rack",
            "supply_crate",
            "shelf",
            "pallet",
            "freight_cart",
            "packing_table",
            "manifest_board",
            "cargo_bin",
        ]
    } else if has(role, &["medical", "treatment", "surgery", "recovery"]) {
        &[
            "medical_bed",
            "privacy_screen",
            "medical_cabinet",
            "stool",
            "iv_stand",
            "instrument_table",
            "wash_station",
            "medicine_cart",
        ]
    } else if has(
        role,
        &[
            "security",
            "brig",
            "armory",
            "evidence",
            "checkpoint",
            "interrogation",
        ],
    ) {
        &[
            "reinforced_table",
            "secure_locker",
            "evidence_cabinet",
            "weapon_rack",
            "filing_cabinet",
            "security_records",
        ]
    } else if has(role, &["ai", "core", "server", "monitoring", "satellite"]) {
        &[
            "server_rack",
            "data_terminal",
            "coolant_unit",
            "parts_cabinet",
            "worktable",
            "filing_cabinet",
        ]
    } else if has(
        role,
        &[
            "engineering",
            "power",
            "atmospherics",
            "workshop",
            "tool-room",
            "maintenance",
        ],
    ) {
        &[
            "workbench",
            "tool_rack",
            "parts_bin",
            "electrical_locker",
            "tool_cart",
            "parts_cabinet",
        ]
    } else if has(role, &["laboratory", "research", "analysis", "robotics"]) {
        &[
            "experiment_table",
            "analyzer",
            "reagent_storage",
            "server_rack",
            "parts_cabinet",
            "worktable",
        ]
    } else if has(role, &["meeting", "briefing", "reception", "foyer"]) {
        &[
            "chair",
            "table",
            "plant",
            "notice_board",
            "visitor_bench",
            "display_case",
            "water_cooler",
            "side_table",
        ]
    } else {
        &[
            "worktable",
            "locker",
            "shelf",
            "filing_cabinet",
            "side_table",
            "display_case",
            "notice_board",
        ]
    };
    ids.iter()
        .map(|id| FixtureSpec {
            id,
            layer: FixtureLayer::Furniture,
        })
        .collect()
}

fn target_density(role: &str) -> u32 {
    if has(role, &["storage", "warehouse", "workshop", "laboratory"]) {
        540_000
    } else if has(role, &["foyer", "reception", "meeting"]) {
        420_000
    } else {
        480_000
    }
    .clamp(MIN_OCCUPANCY_MICROS, MAX_OCCUPANCY_MICROS)
}
fn safe_spread_candidate(
    candidates: &[Point],
    blocking: &BTreeSet<Point>,
    required_access: &BTreeSet<Point>,
    tiles: &BTreeSet<Point>,
    center: Point,
    salt: usize,
    width: u16,
    height: u16,
    fixture_id: &str,
    prefer_cluster: bool,
) -> Option<usize> {
    let mut allowed: Vec<usize> = (0..candidates.len())
        .filter(|index| {
            let candidate = candidates[*index];
            if required_access.contains(&candidate) {
                return false;
            }
            if !fixture_blocks(fixture_id) {
                return true;
            }
            let access = step_facing(candidate, face_toward(candidate, center));
            tiles.contains(&access)
                && !blocking.contains(&access)
                && placement_preserves_walkability(tiles, blocking, candidate, width, height)
        })
        .collect();
    allowed.sort_by_key(|index| {
        let point = candidates[*index];
        let spread = blocking
            .iter()
            .map(|other| distance(point, *other))
            .min()
            .unwrap_or(distance(point, center));
        let spread_key = if prefer_cluster {
            spread
        } else {
            u16::MAX - spread
        };
        (spread_key, (*index + salt) % 7, distance(point, center))
    });
    allowed.into_iter().next()
}

fn placement_preserves_walkability(
    tiles: &BTreeSet<Point>,
    blocking: &BTreeSet<Point>,
    candidate: Point,
    width: u16,
    height: u16,
) -> bool {
    let remaining: BTreeSet<Point> = tiles
        .iter()
        .copied()
        .filter(|point| !blocking.contains(point) && *point != candidate)
        .collect();
    let Some(start) = remaining.iter().next().copied() else {
        return false;
    };
    let mut reached = BTreeSet::from([start]);
    let mut queue = VecDeque::from([start]);
    while let Some(point) = queue.pop_front() {
        for next in point_neighbors(point, width, height) {
            if remaining.contains(&next) && reached.insert(next) {
                queue.push_back(next);
            }
        }
    }
    reached.len() == remaining.len()
}

fn fixture_blocks(id: &str) -> bool {
    // Be conservative here: this flag protects actual player navigation, not
    // visual overlap. Most live furniture and machinery types are dense (and
    // several historically misclassified exceptions, including cabinets and
    // racks, caused Rust-valid paths to be blocked after DM materialization).
    // Only turf-integrated atmospheric endpoints are known walk-through.
    !matches!(
        id,
        "vent"
            | "scrubber"
            | "wall_light"
            | "air_alarm"
            | "fire_alarm"
            | "apc"
            | "notice_board"
            | "manifest_board"
    )
}

fn fixture_blocks_on_layer(id: &str, layer: FixtureLayer) -> bool {
    layer != FixtureLayer::Wall && layer != FixtureLayer::Ceiling && fixture_blocks(id)
}

fn fixture_is_wall_mounted(id: &str) -> bool {
    matches!(
        id,
        "wall_light" | "air_alarm" | "fire_alarm" | "apc" | "notice_board" | "manifest_board"
    )
}

fn fixture_prefers_corner(id: &str) -> bool {
    matches!(
        id,
        "plant" | "display_case" | "water_cooler" | "cargo_bin" | "tool_cart"
    )
}

fn fixture_prefers_perimeter(id: &str) -> bool {
    fixture_prefers_corner(id)
        || id.contains("locker")
        || id.contains("cabinet")
        || id.contains("rack")
        || id.contains("console")
        || matches!(
            id,
            "shelf"
                | "server"
                | "server_rack"
                | "autolathe"
                | "armory_autolathe"
                | "fridge"
                | "medical_vendor"
                | "engineering_vendor"
        )
}

fn wall_neighbor_count(layout: &StationLayout, point: Point) -> usize {
    directed_neighbors(layout, point)
        .into_iter()
        .filter(|(neighbor, _)| {
            matches!(
                layout.tile(*neighbor).class,
                TileClass::Hull | TileClass::Structure | TileClass::Partition
            )
        })
        .count()
}

fn fixture_requires_fixed_facing(id: &str) -> bool {
    matches!(id, "sink" | "wash_station")
}
fn fixture_repeat_limit(id: &str) -> usize {
    if id == "wall_light" {
        16
    } else if matches!(id, "vent" | "scrubber" | "air_alarm" | "fire_alarm" | "apc")
        || id.contains("chair")
        || id.contains("table")
        || id.contains("bed")
        || matches!(id, "stool" | "visitor_bench" | "supply_crate" | "pallet")
    {
        4
    } else if id.contains("locker") || id.contains("cabinet") || id.contains("rack") {
        3
    } else {
        // A specialized machine or decoration should normally appear once,
        // with a second copy available for authored paired workstations.
        // Role-specific capacity fixtures receive narrow exceptions below.
        2
    }
}

fn fixture_repeat_limit_for_role(role: &str, id: &str) -> usize {
    match (role, id) {
        ("records" | "archive", "filing_cabinet") => 6,
        ("evidence", "evidence_cabinet") => 5,
        ("armory", "weapon_rack" | "secure_locker") => 5,
        ("server-closet" | "support" | "secure-storage", "server_rack") => 4,
        ("recovery" | "ward", "medical_bed" | "iv_stand" | "privacy_screen") => 5,
        ("storage" | "supply" | "warehouse", "supply_crate" | "pallet" | "storage_rack") => 5,
        ("locker-room", id) if id.contains("locker") => 6,
        ("meeting" | "briefing" | "canteen", id)
            if id.contains("chair") || id.contains("table") =>
        {
            6
        }
        _ => fixture_repeat_limit(id),
    }
}

fn add_tabletop_charger_supports(
    room: &Room,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
    next_fixture_id: &mut u32,
) {
    let chargers = room_fixture_ids
        .iter()
        .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
        .filter(|fixture| fixture.fixture_id == "equipment_recharger")
        .map(|fixture| (fixture.at, fixture.facing, fixture.variant))
        .collect::<Vec<_>>();
    for (at, facing, variant) in chargers {
        let id = *next_fixture_id;
        *next_fixture_id += 1;
        fixtures.push(FixturePlacement {
            id,
            fixture_id: "charger_table".into(),
            at,
            facing,
            layer: FixtureLayer::Furniture,
            department_id: room.department_id,
            room_id: Some(room.id),
            network_id: None,
            variant,
            blocks_movement: true,
            required_access: Vec::new(),
        });
        room_fixture_ids.push(id);
    }
    // Materialization and preview rendering must instantiate the support
    // before the tabletop machine occupying the same turf.
    fixtures.sort_by_key(|fixture| {
        (
            fixture.room_id,
            fixture.at,
            u8::from(fixture.fixture_id != "charger_table"),
            fixture.id,
        )
    });
}

fn orient_perimeter_fixtures_into_room(
    room: &Room,
    tiles: &BTreeSet<Point>,
    blocking: &BTreeSet<Point>,
    room_fixture_ids: &[u32],
    fixtures: &mut [FixturePlacement],
    center: Point,
) {
    for fixture in fixtures.iter_mut().filter(|fixture| {
        fixture.room_id == Some(room.id)
            && room_fixture_ids.contains(&fixture.id)
            && fixture.layer != FixtureLayer::Wall
            && fixture.layer != FixtureLayer::Ceiling
            && fixture_prefers_perimeter(&fixture.fixture_id)
    }) {
        let mut facings = [Facing::North, Facing::East, Facing::South, Facing::West]
            .into_iter()
            .filter_map(|facing| {
                let access = step_facing(fixture.at, facing);
                (tiles.contains(&access) && !blocking.contains(&access)).then_some((facing, access))
            })
            .collect::<Vec<_>>();
        facings.sort_by_key(|(_, access)| (distance(*access, center), access.y, access.x));
        let Some((facing, access)) = facings.first().copied() else {
            continue;
        };
        fixture.facing = facing;
        if fixture.blocks_movement {
            fixture.required_access = vec![access];
        }
    }
}

fn prune_orphaned_seats(
    tiles: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    floor_candidates: &mut Vec<Point>,
    occupied: &mut BTreeSet<Point>,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
) {
    let room_fixtures = room_fixture_ids
        .iter()
        .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
        .collect::<Vec<_>>();
    let remove_ids = room_fixtures
        .iter()
        .filter(|fixture| {
            (fixture.fixture_id.contains("chair") || fixture.fixture_id.contains("stool"))
                && !room_fixtures.iter().any(|other| {
                    fixture.id != other.id
                        && distance(fixture.at, other.at) == 1
                        && fixture_supports_seat(&other.fixture_id)
                })
        })
        .map(|fixture| fixture.id)
        .collect::<BTreeSet<_>>();
    for fixture in room_fixtures {
        if remove_ids.contains(&fixture.id) {
            occupied.remove(&fixture.at);
            if tiles.contains(&fixture.at) && !doors.contains(&fixture.at) {
                floor_candidates.push(fixture.at);
            }
        }
    }
    room_fixture_ids.retain(|id| !remove_ids.contains(id));
    fixtures.retain(|fixture| !remove_ids.contains(&fixture.id));
    floor_candidates.sort_unstable();
    floor_candidates.dedup();
}

fn fixture_supports_seat(id: &str) -> bool {
    // charger_table is a same-tile render support for a recharger, not usable
    // furniture. Counting it paired nearby chairs that became visibly orphaned
    // once semantic validation intentionally hid the support object.
    id != "charger_table"
        && (id.contains("table")
            || id.contains("desk")
            || id.contains("bench")
            || id.contains("console")
            || id.contains("monitor")
            || id.contains("bed")
            || matches!(id, "visitor_bench" | "waiting_bench" | "side_table"))
}

#[allow(clippy::too_many_arguments)]
fn prune_excess_room_repetitions(
    role: &str,
    tiles: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    floor_candidates: &mut Vec<Point>,
    occupied: &mut BTreeSet<Point>,
    blocking: &mut BTreeSet<Point>,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
) {
    let mut counts = BTreeMap::<String, usize>::new();
    let mut remove_ids = BTreeSet::new();
    for fixture_id in room_fixture_ids.iter().copied() {
        let Some(fixture) = fixtures.iter().find(|fixture| fixture.id == fixture_id) else {
            continue;
        };
        if fixture.layer == FixtureLayer::Wall || fixture.layer == FixtureLayer::Ceiling {
            continue;
        }
        let count = counts.entry(fixture.fixture_id.clone()).or_default();
        *count += 1;
        if *count > fixture_repeat_limit_for_role(role, &fixture.fixture_id) {
            remove_ids.insert(fixture_id);
            occupied.remove(&fixture.at);
            blocking.remove(&fixture.at);
            if tiles.contains(&fixture.at) && !doors.contains(&fixture.at) {
                floor_candidates.push(fixture.at);
            }
        }
    }
    if remove_ids.is_empty() {
        return;
    }
    room_fixture_ids.retain(|id| !remove_ids.contains(id));
    fixtures.retain(|fixture| !remove_ids.contains(&fixture.id));
    floor_candidates.sort_unstable();
    floor_candidates.dedup();
}

fn fixture_repetitions_within_limits<'a>(
    placements: impl IntoIterator<Item = &'a AuthoredCompositionPlacement>,
) -> bool {
    let mut counts = BTreeMap::<&str, usize>::new();
    for placement in placements {
        let count = counts.entry(placement.fixture_id.as_str()).or_default();
        *count += 1;
        if *count > fixture_repeat_limit(&placement.fixture_id) {
            return false;
        }
    }
    true
}

fn placement_seats_are_paired<'a>(
    placements: impl IntoIterator<Item = &'a AuthoredCompositionPlacement>,
) -> bool {
    let placements = placements.into_iter().collect::<Vec<_>>();
    placements.iter().all(|chair| {
        let is_seat = chair.fixture_id.contains("chair")
            || matches!(chair.fixture_id.as_str(), "stool" | "executive_chair");
        !is_seat
            || placements.iter().any(|other| {
                chair.at != other.at
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
            })
    })
}

fn step_facing(point: Point, facing: Facing) -> Point {
    match facing {
        Facing::North => Point {
            x: point.x,
            y: point.y.saturating_add(1),
        },
        Facing::South => Point {
            x: point.x,
            y: point.y.saturating_sub(1),
        },
        Facing::East => Point {
            x: point.x.saturating_add(1),
            y: point.y,
        },
        Facing::West => Point {
            x: point.x.saturating_sub(1),
            y: point.y,
        },
    }
}
fn face_toward(from: Point, to: Point) -> Facing {
    if from.x.abs_diff(to.x) >= from.y.abs_diff(to.y) {
        if from.x < to.x {
            Facing::East
        } else {
            Facing::West
        }
    } else if from.y < to.y {
        Facing::North
    } else {
        Facing::South
    }
}
fn distance(a: Point, b: Point) -> u16 {
    a.x.abs_diff(b.x) + a.y.abs_diff(b.y)
}
fn neighbors(layout: &StationLayout, p: Point) -> Vec<Point> {
    point_neighbors(p, layout.width, layout.height)
}
fn point_neighbors(p: Point, width: u16, height: u16) -> Vec<Point> {
    let mut v = Vec::new();
    if p.x > 0 {
        v.push(Point { x: p.x - 1, y: p.y })
    }
    if p.x + 1 < width {
        v.push(Point { x: p.x + 1, y: p.y })
    }
    if p.y > 0 {
        v.push(Point { x: p.x, y: p.y - 1 })
    }
    if p.y + 1 < height {
        v.push(Point { x: p.x, y: p.y + 1 })
    }
    v
}
fn directed_neighbors(layout: &StationLayout, p: Point) -> Vec<(Point, Facing)> {
    point_neighbors(p, layout.width, layout.height)
        .into_iter()
        .map(|q| {
            (
                q,
                if q.x < p.x {
                    Facing::West
                } else if q.x > p.x {
                    Facing::East
                } else if q.y < p.y {
                    Facing::South
                } else {
                    Facing::North
                },
            )
        })
        .collect()
}
fn adjacent_to_wall(layout: &StationLayout, p: Point) -> bool {
    neighbors(layout, p).into_iter().any(|q| {
        matches!(
            layout.tile(q).class,
            TileClass::Hull | TileClass::Structure | TileClass::Partition
        )
    })
}
fn has(value: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| value.contains(needle))
}
fn department_name(mapping: &CatalogMapping, id: u16) -> &str {
    mapping
        .departments
        .get(&id)
        .map(|d| d.name.as_str())
        .unwrap_or("Department")
}
fn select_richest_variant<'a>(
    mapping: &'a CatalogMapping,
    room: &Room,
    role: &str,
) -> &'a CatalogRoomWire {
    let assigned = mapping
        .rooms
        .get(&room.room_type_id)
        .expect("assigned room variant exists");
    let width = room.bounds.width;
    let height = room.bounds.height;
    let area = room.tiles.len() as u32;
    mapping
        .rooms
        .values()
        .filter(|variant| {
            let program = if variant.definition_id.contains("-compact-")
                || variant.definition_id.contains("-micro-")
            {
                compact_room_program(&variant.department_id, &variant.role, 0)
            } else {
                room_program(&variant.department_id, &variant.role, 0)
            };
            // Semantic role names are intentionally reused across departments
            // (reception, storage, operations, equipment). Never enrich a
            // room with another department's same-named program.
            variant.department_id == assigned.department_id
                && variant.role == role
                && area
                    >= variant
                        .minimum_usable_tiles
                        .max(variant.content_area)
                        .max(program.minimum_area)
                && ((width <= variant.max_width + 3 && height <= variant.max_height + 3)
                    || (height <= variant.max_width + 3 && width <= variant.max_height + 3))
        })
        .max_by_key(|variant| {
            let program = if variant.definition_id.contains("-compact-")
                || variant.definition_id.contains("-micro-")
            {
                compact_room_program(&variant.department_id, &variant.role, 0)
            } else {
                room_program(&variant.department_id, &variant.role, 0)
            };
            (
                variant
                    .minimum_usable_tiles
                    .max(variant.content_area)
                    .max(program.minimum_area),
                variant.ideal_usable_tiles.max(program.ideal_area),
            )
        })
        .unwrap_or_else(|| {
            mapping
                .rooms
                .get(&room.room_type_id)
                .expect("assigned room variant exists")
        })
}
fn title(value: &str) -> String {
    value
        .split('-')
        .map(|part| {
            let mut chars = part.chars();
            chars
                .next()
                .map(|first| first.to_uppercase().collect::<String>() + chars.as_str())
                .unwrap_or_default()
        })
        .collect::<Vec<_>>()
        .join(" ")
}
fn floor_style(aesthetic: &str, role: &str) -> &'static str {
    if has(role, &["ai", "core"]) {
        "reinforced-tech"
    } else if has(role, &["medical", "surgery", "treatment"]) {
        "sterile-white"
    } else if has(role, &["engineering", "workshop", "maintenance"]) {
        "industrial-grid"
    } else if aesthetic.contains("command") {
        "executive"
    } else {
        "department-tile"
    }
}
fn accent_style(department: &str, _role: &str) -> &'static str {
    // Accent colour communicates departmental ownership. A room's role may
    // select its tile material/pattern, but must never make (for example) an
    // engineering storeroom look like part of cargo.
    match department {
        "command" => "command-blue",
        "ai" => "ai-cyan",
        "security" => "security-red",
        "medical" => "medical-blue",
        "engineering" => "engineering-yellow",
        "logistics" | "cargo" => "cargo-brown",
        "science" | "research" => "science-purple",
        "docking" => "docking-gray",
        _ => "neutral-gray",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn southern_cross_reference_is_live_and_actionable() {
        let reference = southern_cross_reference();
        for role in [
            "general",
            "operations",
            "security",
            "surgery",
            "treatment",
            "ward",
            "workshop",
        ] {
            let profile = reference
                .profiles
                .get(role)
                .unwrap_or_else(|| panic!("missing measured Southern Cross role {role}"));
            assert!(profile.occupancy_median_micros >= profile.occupancy_p25_micros);
            assert!(profile.fixture_count_p25 > 0);
            assert!(profile.unique_fixture_types_p25 > 0);
            assert!(profile.largest_empty_region_p75_micros < 1_000_000);
        }
    }

    #[test]
    fn counterpart_profiles_require_density_and_bounded_empty_space() {
        for role in [
            "operations",
            "armory",
            "surgery",
            "treatment",
            "ward",
            "laboratory",
            "storage",
        ] {
            let profile = counterpart_profile(role);
            assert!(profile.minimum_occupancy_micros >= 250_000, "{role}");
            assert!(
                profile.target_occupancy_micros >= profile.minimum_occupancy_micros,
                "{role}"
            );
            assert!(profile.maximum_empty_region_micros <= 750_000, "{role}");
            assert!(profile.minimum_unique_fixtures >= 4, "{role}");
            assert!(profile.minimum_fixture_count >= 4, "{role}");
        }
    }

    #[test]
    fn specialized_equipment_cannot_be_used_as_density_spam() {
        for role in ["operations", "equipment", "armory", "laboratory"] {
            assert_eq!(
                fixture_repeat_limit_for_role(role, "equipment_recharger"),
                2
            );
            assert_eq!(fixture_repeat_limit_for_role(role, "armory_autolathe"), 2);
            assert_eq!(fixture_repeat_limit_for_role(role, "role_console"), 2);
        }
        assert_eq!(
            fixture_repeat_limit_for_role("surgery", "medical_cabinet"),
            3
        );
        assert_eq!(
            fixture_repeat_limit_for_role("records", "filing_cabinet"),
            6
        );
    }

    #[test]
    fn zone_placement_retries_every_rotation_before_giving_up_on_an_anchor() {
        // Regression test for a bug clippy::never_loop caught during the
        // rewrite/rustaudit pass: the rotation retry used to always try only
        // `rotation_offset`'s own turn and give up on the whole anchor
        // instead of trying the other 3 rotations. Two tiles in a vertical
        // strip; a fixture offset one cell to the *east* of the anchor only
        // lands on a real tile once rotated a quarter turn (which redirects
        // the offset to the *north* tile instead).
        let layout = StationLayout {
            seed: 1,
            width: 1,
            height: 2,
            archetype: MacroArchetype::Cross,
            tiles: vec![TileCell::default(); 2],
            departments: vec![],
            rooms: vec![],
            doors: vec![],
            public_circulation: vec![],
            maintenance: vec![],
            structure: vec![],
            hull: vec![],
            graph: LayoutGraph::default(),
            metadata: BTreeMap::new(),
        };
        let tiles = BTreeSet::from([Point { x: 0, y: 0 }, Point { x: 0, y: 1 }]);
        let env = ZonePlacementEnv {
            layout: &layout,
            tiles: &tiles,
            doors: &BTreeSet::new(),
            center: Point { x: 0, y: 0 },
        };
        let empty = BTreeSet::new();
        let zone = ActivityZone {
            id: "test-zone",
            anchor: ProgramAnchor::Center,
            required: true,
            repeatable: false,
            fixtures: vec![super::super::program::ProgramFixture {
                id: "vent",
                dx: 1,
                dy: 0,
                layer: ProgramLayer::Furniture,
            }],
        };
        let anchor = Point { x: 0, y: 0 };

        // Unrotated (turns = 0), the fixture's (dx=1, dy=0) offset lands on
        // (1, 0), which isn't one of the room's two tiles: this rotation
        // must fail.
        assert!(
            try_place_zone_at(&env, &empty, &empty, &empty, &zone, anchor, 0).is_none(),
            "turns=0 should not fit: (1,0) is not a tile in this room"
        );

        // Rotated one quarter turn, (dx=1, dy=0) becomes (0, 1) (see
        // `program_rotate_offset`), landing on the room's other tile: this
        // rotation must succeed. Before the fix, the caller never reached
        // this rotation at all for a given anchor.
        let placed = try_place_zone_at(&env, &empty, &empty, &empty, &zone, anchor, 1);
        let (placements, _blocking, _access) =
            placed.expect("turns=1 should fit: (0,1) is the room's other tile");
        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].at, Point { x: 0, y: 1 });
    }
}
