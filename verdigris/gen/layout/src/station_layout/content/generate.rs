use super::*;

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
                    &mut FixtureSink {
                        fixtures: &mut fixtures,
                        room_ids: &mut room_fixture_ids,
                        next: &mut next_fixture_id,
                    },
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
                &mut FixtureSink {
                    fixtures: &mut fixtures,
                    room_ids: &mut room_fixture_ids,
                    next: &mut next_fixture_id,
                },
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
                    &mut FixtureSink {
                        fixtures: &mut fixtures,
                        room_ids: &mut room_fixture_ids,
                        next: &mut next_fixture_id,
                    },
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
        let room_placement_ctx = RoomPlacementContext {
            layout: &layout,
            tiles: &tiles,
            reserved: &reserved,
            doors: &door_tiles,
            center,
            protected_approaches: &protected_approaches,
        };
        let program_with_fragments = fragments_valid.then(|| {
            place_room_program(
                &room_placement_ctx,
                &program,
                &fragment_blocking,
                &fragment_access,
                &fragment_occupied,
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
                    &room_placement_ctx,
                    &program,
                    &blocking,
                    &required_access,
                    &occupied,
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
                            &room_placement_ctx,
                            &compact,
                            &blocking,
                            &required_access,
                            &occupied,
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
                    &mut FixtureSink {
                        fixtures: &mut fixtures,
                        room_ids: &mut room_fixture_ids,
                        next: &mut next_fixture_id,
                    },
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
                &mut FixtureSink {
                    fixtures: &mut fixtures,
                    room_ids: &mut room_fixture_ids,
                    next: &mut next_fixture_id,
                },
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

pub(super) fn relocate_wall_services_away_from_furniture(
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

pub(super) fn prune_orphaned_seats_after_wall_layout(
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

pub(super) fn orient_seats_toward_supports(rooms: &[RoomBlueprint], fixtures: &mut [FixturePlacement]) {
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

// This function's args are the room-fill working set threaded through a
// single call site (generate_station_blueprint): splitting them into a
// context struct plus a separate output-accumulator struct would shuffle
// the same 15 pieces of state one level deeper without reducing what the
// caller has to assemble. Not bundled.
#[allow(clippy::too_many_arguments)]
pub(super) fn fill_to_counterpart_density(
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
            &mut FixtureSink {
                fixtures,
                room_ids: room_fixture_ids,
                next: next_fixture_id,
            },
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
