use super::*;

/// The output accumulators every fixture placed in a room is pushed into,
/// grouped so `push_fixture`/`push_authored_fixture` stay under clippy's
/// argument limit instead of threading each of these through separately.
pub(super) struct FixtureSink<'a> {
    pub(super) fixtures: &'a mut Vec<FixturePlacement>,
    pub(super) room_ids: &'a mut Vec<u32>,
    pub(super) next: &'a mut u32,
}

pub(super) fn push_fixture(
    sink: &mut FixtureSink<'_>,
    spec: FixtureSpec,
    at: Point,
    facing: Facing,
    room: &Room,
    network_id: Option<String>,
    variant: u16,
) {
    let id = *sink.next;
    *sink.next += 1;
    sink.fixtures.push(FixturePlacement {
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
    sink.room_ids.push(id);
}

pub(super) fn push_authored_fixture(
    sink: &mut FixtureSink<'_>,
    fixture_id: &str,
    layer: FixtureLayer,
    at: Point,
    facing: Facing,
    room: &Room,
    variant: u16,
) {
    let id = *sink.next;
    *sink.next += 1;
    let blocks_movement = fixture_blocks_on_layer(fixture_id, layer);
    sink.fixtures.push(FixturePlacement {
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
    sink.room_ids.push(id);
}

pub(super) fn room_center(room: &Room, tiles: &BTreeSet<Point>) -> Point {
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

pub(super) fn room_door_approaches(
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

pub(super) fn authored_fragment_composition(
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

pub(super) fn fragment_feature_point(origin: Point, feature: &FragmentFeatureWire) -> Option<Point> {
    let x = i32::from(origin.x) + i32::from(feature.dx) - 1;
    let y = i32::from(origin.y) + i32::from(feature.dy) - 1;
    (x >= 0 && y >= 0 && x <= i32::from(u16::MAX) && y <= i32::from(u16::MAX)).then_some(Point {
        x: x as u16,
        y: y as u16,
    })
}

pub(super) fn hash_text(value: &str) -> u64 {
    value.bytes().fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
        (hash ^ u64::from(byte)).wrapping_mul(0x1000_0000_01b3)
    })
}

pub(super) fn expand_circulation_coverage(
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

pub(super) fn connect_to_circulation(
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

pub(super) fn connect_points(
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

pub(super) fn shortest_path(
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

pub(super) fn wall_fixture_candidates(
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
