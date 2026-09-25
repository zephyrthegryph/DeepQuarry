use super::model::*;
use super::program::{compact_room_program, room_program};
use eyre::{Result, WrapErr, bail};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub struct CatalogMapping {
    pub catalog_hash: String,
    pub metadata: CatalogMetadataWire,
    pub candidate_count: u16,
    pub architecture_choices: Vec<MacroArchetype>,
    pub departments: BTreeMap<u16, CatalogDepartmentWire>,
    pub rooms: BTreeMap<u16, CatalogRoomWire>,
    pub sprite_previews: BTreeMap<String, SpritePreview>,
}

pub fn decode_catalog(json: &str) -> Result<(LayoutRequest, CatalogMapping)> {
    let wire: CatalogWire = serde_json::from_str(json).wrap_err("invalid station catalog JSON")?;
    if wire.schema != "dq.station.catalog" || wire.major != 1 {
        bail!("unsupported station catalog schema");
    }
    validate_metadata(&wire.metadata)?;
    if wire.settings.candidate_count == 0 {
        bail!("candidate_count must be positive");
    }
    if wire.settings.maintenance_width != STATION_MAINTENANCE_WIDTH {
        bail!("maintenance_width must be {STATION_MAINTENANCE_WIDTH} for the structural lattice");
    }
    let architecture_choices = parse_archetypes(&wire.settings.architecture_choices)?;
    let seed = wire
        .seed
        .parse::<u64>()
        .wrap_err("seed must be a decimal u64 string")?;
    let mut department_numbers = BTreeMap::new();
    let mut mapped_departments = BTreeMap::new();
    for (index, department) in wire.departments.into_iter().enumerate() {
        if department.id.is_empty() || department.definition_id.is_empty() {
            bail!("department semantic IDs cannot be empty");
        }
        let numeric = u16::try_from(index + 1)?;
        if department_numbers
            .insert(department.id.clone(), numeric)
            .is_some()
        {
            bail!("duplicate department semantic ID {}", department.id);
        }
        if mapped_departments
            .values()
            .any(|known: &CatalogDepartmentWire| known.definition_id == department.definition_id)
        {
            bail!(
                "duplicate department definition ID {}",
                department.definition_id
            );
        }
        if department.minimum_area == 0 || department.minimum_area > department.maximum_area {
            bail!("department {} has invalid area bounds", department.id);
        }
        validate_capabilities(&department)?;
        mapped_departments.insert(numeric, department);
    }
    let mut catalog_rooms = wire.rooms;
    // Catalog minor 0 omitted micro contracts even though DM already knew how
    // to materialize them. Preserve old logged catalogs and rolling upgrades by
    // deriving the same one-signature-fixture contract from each compact role.
    let known_micro_roles = catalog_rooms
        .iter()
        .filter(|room| room.definition_id.contains("-micro-"))
        .map(|room| (room.department_id.clone(), room.role.clone()))
        .collect::<BTreeSet<_>>();
    let synthesized_micro = catalog_rooms
        .iter()
        .filter(|room| room.definition_id.contains("-compact-"))
        .filter(|room| {
            !known_micro_roles.contains(&(room.department_id.clone(), room.role.clone()))
        })
        .cloned()
        .map(|mut room| {
            room.id = format!("{}-{}-micro", room.department_id, room.role);
            room.definition_id = format!("{}-micro-{}", room.department_id, room.role);
            room.min_width = 1;
            room.max_width = 5;
            room.min_height = 1;
            room.max_height = 5;
            room.min_count = 0;
            room.max_count = 12;
            room.min_entrances = 1;
            room.max_entrances = 1;
            room.content_area = 1;
            room.minimum_usable_tiles = 1;
            room.ideal_usable_tiles = 4;
            room.min_short_side = 1;
            room.max_aspect_ratio_millis = 9000;
            room.requires_center_activity = false;
            room.density_min_micros = 100_000;
            room.density_max_micros = 750_000;
            room.circulation_min_micros = 0;
            room.wall_utilization_micros = 0;
            room.fragments.clear();
            room
        })
        .collect::<Vec<_>>();
    catalog_rooms.extend(synthesized_micro);
    let mut sprite_previews = wire.sprite_previews;
    for room in &catalog_rooms {
        for fragment in &room.fragments {
            for feature in &fragment.features {
                if !feature.id.is_empty() && !feature.icon_file.is_empty() {
                    sprite_previews
                        .entry(feature.id.clone())
                        .or_insert_with(|| SpritePreview {
                            icon_file: feature.icon_file.clone(),
                            icon_state: feature.icon_state.clone(),
                        });
                }
            }
        }
    }
    let mut grouped: BTreeMap<u16, Vec<RoomType>> = BTreeMap::new();
    let mut mapped_rooms = BTreeMap::new();
    let mut room_ids = BTreeSet::new();
    for (index, room) in catalog_rooms.into_iter().enumerate() {
        if room.id.is_empty() || !room_ids.insert(room.id.clone()) {
            bail!("empty or duplicate room semantic ID {}", room.id);
        }
        let department = *department_numbers.get(&room.department_id).ok_or_else(|| {
            eyre::eyre!("room references unknown department {}", room.department_id)
        })?;
        let numeric = u16::try_from(index + 1)?;
        let content_program =
            if room.definition_id.contains("-compact-") || room.definition_id.contains("-micro-") {
                compact_room_program(&room.department_id, &room.role, seed ^ u64::from(numeric))
            } else {
                room_program(&room.department_id, &room.role, seed ^ u64::from(numeric))
            };
        grouped.entry(department).or_default().push(RoomType {
            id: numeric,
            name: room.role.clone(),
            min_width: room.min_width,
            max_width: room.max_width,
            min_height: room.min_height,
            max_height: room.max_height,
            min_count: room.min_count,
            max_count: room.max_count,
            entrances: room.max_entrances.max(room.min_entrances),
            content_area: room
                .minimum_usable_tiles
                .max(room.content_area)
                .max(content_program.minimum_area),
            ideal_area: room
                .ideal_usable_tiles
                .max(room.minimum_usable_tiles)
                .max(room.content_area)
                .max(content_program.ideal_area)
                .min(content_program.maximum_area),
            min_short_side: room.min_short_side.max(1),
            max_aspect_ratio_millis: room.max_aspect_ratio_millis.max(1000),
            requires_center_activity: room.requires_center_activity,
        });
        mapped_rooms.insert(numeric, room);
    }
    let mut departments = Vec::new();
    // A semantic room requirement is satisfied by one of its geometry
    // variants, not by every variant independently. Preserve the exact variant
    // DM marked as required: a full reception contract must not silently become
    // a compact reception merely because both share one semantic role.
    for room_types in grouped.values_mut() {
        let mut required_roles = BTreeSet::new();
        for room in room_types.iter() {
            if room.min_count > 0 {
                required_roles.insert(room.name.clone());
            }
        }
        for role in required_roles {
            let candidates: Vec<usize> = room_types
                .iter()
                .enumerate()
                .filter_map(|(index, room)| (room.name == role).then_some(index))
                .collect();
            let required = candidates
                .iter()
                .map(|index| room_types[*index].min_count)
                .max()
                .unwrap_or(1);
            let required_variant = candidates
                .iter()
                .copied()
                .filter(|index| room_types[*index].min_count > 0)
                .min_by_key(|index| room_types[*index].content_area);
            for index in &candidates {
                room_types[*index].min_count = 0;
            }
            if let Some(index) = required_variant {
                room_types[index].min_count = required;
            }
        }
    }
    for (&numeric, semantic) in &mapped_departments {
        let room_types = grouped.remove(&numeric).unwrap_or_default();
        if room_types.is_empty() {
            bail!("department {} has no room contracts", semantic.id);
        }
        departments.push(DepartmentRequest {
            id: numeric,
            name: semantic.name.clone(),
            weight: semantic.weight,
            minimum_area: semantic.minimum_area,
            maximum_area: semantic.maximum_area,
            desired_area: bounded_desired_area(semantic),
            room_types,
        });
    }
    let request = LayoutRequest {
        settings: StationSettings {
            seed,
            width: wire.width,
            height: wire.height,
            hull_thickness: wire.settings.hull_thickness,
            corridor_width: wire.settings.corridor_width,
            maintenance_width: wire.settings.maintenance_width,
            room_jitter: wire.settings.room_jitter,
        },
        departments,
    };
    Ok((
        request,
        CatalogMapping {
            catalog_hash: wire.catalog_hash,
            metadata: wire.metadata,
            candidate_count: wire.settings.candidate_count,
            architecture_choices,
            departments: mapped_departments,
            rooms: mapped_rooms,
            sprite_previews,
        },
    ))
}

pub fn encode_plan(layout: &StationLayout, mapping: &CatalogMapping) -> Result<String> {
    if !mapping.architecture_choices.contains(&layout.archetype) {
        bail!("planner selected an archetype excluded by the request");
    }
    let mut wire = layout.to_wire();
    wire.catalog_hash = mapping.catalog_hash.clone();
    wire.metadata = WireMetadata {
        station_id: mapping.metadata.station_id.clone(),
        name: mapping.metadata.name.clone(),
        architecture_style: mapping.metadata.architecture_style.clone(),
        faction_id: mapping.metadata.faction_id.clone(),
        security_tier: mapping.metadata.security_tier,
        size_class: mapping.metadata.size_class.clone(),
        layout_archetype: format!("{:?}", layout.archetype).to_lowercase(),
        aesthetic_score: 0.0,
    };
    let dep_ids: BTreeMap<u16, (String, String, String)> = mapping
        .departments
        .iter()
        .map(|(&id, d)| {
            (
                id,
                (
                    format!("{}-1", d.id),
                    d.definition_id.clone(),
                    format!("node-{}", d.id),
                ),
            )
        })
        .collect();
    for department in &mut wire.departments {
        let numeric = department
            .id
            .trim_start_matches("department-")
            .parse::<u16>()?;
        let (ids, definition, node) = &dep_ids[&numeric];
        department.id = ids.clone();
        department.definition_id = definition.clone();
        department.node_id = node.clone();
        department.desired_area = bounded_desired_area(&mapping.departments[&numeric]);
    }
    for node in &mut wire.nodes {
        let numeric = node
            .department_id
            .trim_start_matches("department-")
            .parse::<u16>()?;
        let (ids, _, node_id) = &dep_ids[&numeric];
        node.id = node_id.clone();
        node.department_id = ids.clone();
        node.desired_area = bounded_desired_area(&mapping.departments[&numeric]);
        if let Some((vertical, coordinate)) = local_spine(layout, numeric) {
            node.frontage_spine_vertical = vertical;
            node.frontage_spine_coordinate = coordinate + 1;
        }
        let department = layout
            .departments
            .iter()
            .find(|department| department.id == numeric)
            .ok_or_else(|| eyre::eyre!("node references missing native department {numeric}"))?;
        if let Some(door) = layout
            .doors
            .iter()
            .find(|door| door.id == department.frontage_door)
        {
            // A doorway occupies the boundary and may be rasterized on the
            // public/maintenance side. DM's node frontage is an owned anchor,
            // so export the adjacent department tile rather than blindly
            // exporting the door coordinate.
            let frontage = layout
                .tiles
                .iter()
                .enumerate()
                .filter(|(_, tile)| {
                    tile.owner == Some(numeric) && tile.class != TileClass::Maintenance
                })
                .map(|(index, _)| {
                    (
                        (index % usize::from(layout.width)) as u16,
                        (index / usize::from(layout.width)) as u16,
                    )
                })
                .min_by_key(|(x, y)| (x.abs_diff(door.at.x) + y.abs_diff(door.at.y), *x, *y));
            if let Some((x, y)) = frontage {
                node.frontage_x = x + 1;
                node.frontage_y = y + 1;
            }
        }
    }
    let mut room_ids = BTreeMap::new();
    for (index, room) in wire.rooms.iter_mut().enumerate() {
        let native = &layout.rooms[index];
        let semantic = mapping.rooms.get(&native.room_type_id).ok_or_else(|| {
            eyre::eyre!(
                "layout room {} references unknown catalog room type {}",
                native.id,
                native.room_type_id
            )
        })?;
        let node = &dep_ids[&native.department_id].2;
        let id = format!("{}-{}-{}", node, semantic.role, native.id);
        room.id = id.clone();
        room.node_id = node.clone();
        room.definition_id = semantic.definition_id.clone();
        room.role = semantic.role.clone();
        let frontage = native
            .door_ids
            .iter()
            .find_map(|id| layout.doors.iter().find(|door| door.id == *id));
        let frontage = frontage
            .ok_or_else(|| eyre::eyre!("room {} lacks an actual frontage door", native.id))?;
        room.frontage_x = frontage.at.x + 1;
        room.frontage_y = frontage.at.y + 1;
        room_ids.insert(native.id, id);
    }
    for row in &mut wire.tile_rows {
        for run in &mut row.runs {
            if let Some(owner) = run.owner.take() {
                let numeric = owner.trim_start_matches("department-").parse::<u16>()?;
                run.owner = Some(dep_ids[&numeric].2.clone());
                run.zone = Some(dep_ids[&numeric].2.clone());
            }
            if let Some(room) = run.room.take() {
                let numeric = room.trim_start_matches("room-").parse::<u16>()?;
                run.room = room_ids.get(&numeric).cloned();
                run.zone = run.room.clone();
            }
        }
    }
    for (index, door) in wire.doors.iter_mut().enumerate() {
        let native = &layout.doors[index];
        let node = &dep_ids[&native.department_id].2;
        door.owner_id = node.clone();
        door.id = format!("door-{}", native.id);
        door.from_zone = native
            .room_id
            .and_then(|id| room_ids.get(&id).cloned())
            .unwrap_or_else(|| node.clone());
        door.to_zone = if native.connects_public {
            "public-circulation".into()
        } else {
            node.clone()
        };
        if native.connects_maintenance && native.connects_public {
            door.kind = "maintenance".into();
            door.from_zone = "maintenance".into();
            door.to_zone = "public-circulation".into();
        } else if native.maintenance_choke {
            door.kind = "maintenance".into();
            door.from_zone = "maintenance".into();
            door.to_zone = "maintenance".into();
        } else if native.connects_maintenance {
            door.kind = "maintenance".into();
            door.from_zone = "maintenance".into();
            door.to_zone = native
                .room_id
                .and_then(|id| room_ids.get(&id).cloned())
                .unwrap_or_else(|| node.clone());
        } else if let Some(room_id) = native.room_id {
            door.kind = "room".into();
            door.from_zone = room_ids[&room_id].clone();
            door.to_zone = if native.connects_public {
                "public-circulation".into()
            } else {
                node.clone()
            };
        }
        door.direction = door_direction(layout, native);
    }

    // The rasterized public corridor is authoritative, but DM also consumes a
    // semantic transit graph for capability and service validation. Ensure
    // every department participates in one explicit backbone instead of
    // relying on the smaller set of aesthetic/candidate-scoring edges.
    let mut department_ids = layout
        .departments
        .iter()
        .map(|department| department.id)
        .collect::<Vec<_>>();
    department_ids.sort_unstable();
    for pair in department_ids.windows(2) {
        let from = format!("node-{}", pair[0]);
        let to = format!("node-{}", pair[1]);
        let already_connected = wire.edges.iter().any(|edge| {
            edge.kind == "transit"
                && ((edge.from_node == from && edge.to_node == to)
                    || (edge.from_node == to && edge.to_node == from))
        });
        if !already_connected {
            wire.edges.push(WireEdge {
                id: format!("transit-backbone-{}-{}", pair[0], pair[1]),
                from_node: from,
                to_node: to,
                kind: "transit".into(),
                service_id: None,
                minimum_width: 2,
                required: true,
                corridor_class: "connector".into(),
                path: Vec::new(),
            });
        }
    }

    // Capability dependencies are part of the macro plan.  Emit one physical
    // utility edge from a deterministic provider to every remote consumer so
    // DM can realize the same service graph without reconstructing policy.
    let mut utility_edges = Vec::new();
    for (&consumer_id, consumer) in &mapping.departments {
        for requirement in &consumer.requires {
            let provider = mapping.departments.iter().find(|(provider_id, candidate)| {
                **provider_id != consumer_id
                    && candidate
                        .provides
                        .iter()
                        .any(|provision| provision.id == requirement.id)
            });
            if let Some((&provider_id, _)) = provider {
                utility_edges.push(WireEdge {
                    id: format!("utility-{}-{}-{}", requirement.id, provider_id, consumer_id),
                    from_node: format!("node-{provider_id}"),
                    to_node: format!("node-{consumer_id}"),
                    kind: "utility".into(),
                    service_id: Some(requirement.id.clone()),
                    minimum_width: 1,
                    required: !requirement.optional,
                    corridor_class: "service".into(),
                    path: Vec::new(),
                });
            }
        }
    }
    wire.edges.extend(utility_edges);
    for edge in &mut wire.edges {
        for field in [&mut edge.from_node, &mut edge.to_node] {
            let numeric = field.trim_start_matches("node-").parse::<u16>()?;
            *field = dep_ids[&numeric].2.clone();
        }
        let from = layout
            .departments
            .iter()
            .find(|d| dep_ids[&d.id].2 == edge.from_node)
            .ok_or_else(|| eyre::eyre!("edge has unknown source"))?;
        let to = layout
            .departments
            .iter()
            .find(|d| dep_ids[&d.id].2 == edge.to_node)
            .ok_or_else(|| eyre::eyre!("edge has unknown destination"))?;
        if edge.kind != "transit" {
            continue;
        }
        let start = layout
            .doors
            .iter()
            .find(|d| d.id == from.frontage_door)
            .ok_or_else(|| eyre::eyre!("source frontage missing"))?
            .at;
        let end = layout
            .doors
            .iter()
            .find(|d| d.id == to.frontage_door)
            .ok_or_else(|| eyre::eyre!("destination frontage missing"))?
            .at;
        edge.path = public_path(layout, start, end).ok_or_else(|| {
            eyre::eyre!(
                "no public transit path between {} and {}",
                edge.from_node,
                edge.to_node
            )
        })?;
    }
    serde_json::to_string(&wire).wrap_err("failed to serialize station plan")
}

fn bounded_desired_area(department: &CatalogDepartmentWire) -> u32 {
    let ceiling = department.maximum_area.min(80).max(department.minimum_area);
    department.minimum_area + (ceiling - department.minimum_area) / 2
}

fn local_spine(layout: &StationLayout, department: u16) -> Option<(bool, u16)> {
    let points: Vec<Point> = layout
        .tiles
        .iter()
        .enumerate()
        .filter_map(|(index, cell)| {
            (cell.owner == Some(department) && cell.class == TileClass::Local).then_some(Point {
                x: index as u16 % layout.width,
                y: index as u16 / layout.width,
            })
        })
        .collect();
    let min_x = points.iter().map(|p| p.x).min()?;
    let max_x = points.iter().map(|p| p.x).max()?;
    let min_y = points.iter().map(|p| p.y).min()?;
    let max_y = points.iter().map(|p| p.y).max()?;
    let vertical = max_y - min_y >= max_x - min_x;
    let mut counts = BTreeMap::<u16, usize>::new();
    for point in points {
        *counts
            .entry(if vertical { point.x } else { point.y })
            .or_default() += 1;
    }
    let coordinate = counts
        .into_iter()
        .max_by_key(|(coordinate, count)| (*count, std::cmp::Reverse(*coordinate)))?
        .0;
    Some((vertical, coordinate))
}

fn validate_metadata(metadata: &CatalogMetadataWire) -> Result<()> {
    if metadata.station_id.is_empty()
        || metadata.name.is_empty()
        || metadata.architecture_style.is_empty()
        || metadata.faction_id.is_empty()
        || metadata.size_class.is_empty()
        || metadata.security_tier > 100
    {
        bail!("catalog metadata contains an invalid authoritative field");
    }
    Ok(())
}

fn validate_capabilities(department: &CatalogDepartmentWire) -> Result<()> {
    let mut ids = BTreeSet::new();
    for requirement in &department.requires {
        if requirement.id.is_empty()
            || requirement.amount == 0
            || !ids.insert(("requires", requirement.id.as_str()))
        {
            bail!(
                "department {} has an invalid or duplicate requirement",
                department.id
            );
        }
    }
    for provision in &department.provides {
        if provision.id.is_empty()
            || provision.amount == 0
            || !ids.insert(("provides", provision.id.as_str()))
        {
            bail!(
                "department {} has an invalid or duplicate provision",
                department.id
            );
        }
    }
    Ok(())
}

fn parse_archetypes(values: &[String]) -> Result<Vec<MacroArchetype>> {
    if values.is_empty() {
        bail!("architecture_choices cannot be empty");
    }
    let mut result = Vec::new();
    for value in values {
        let archetype = match value.as_str() {
            "cross" => MacroArchetype::Cross,
            "ring" => MacroArchetype::Ring,
            "bent" => MacroArchetype::Bent,
            "branch" => MacroArchetype::Branch,
            "courtyard" => MacroArchetype::Courtyard,
            _ => bail!("unsupported architecture choice {value}"),
        };
        if result.contains(&archetype) {
            bail!("duplicate architecture choice {value}");
        }
        result.push(archetype);
    }
    Ok(result)
}

fn public_path(layout: &StationLayout, start: Point, end: Point) -> Option<Vec<[u16; 2]>> {
    let mut queue = VecDeque::from([start]);
    let mut previous = BTreeMap::new();
    previous.insert(start, start);
    while let Some(point) = queue.pop_front() {
        if point == end {
            break;
        }
        for (dx, dy) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
            let x = i32::from(point.x) + dx;
            let y = i32::from(point.y) + dy;
            if x < 0 || y < 0 || x >= i32::from(layout.width) || y >= i32::from(layout.height) {
                continue;
            }
            let next = Point {
                x: x as u16,
                y: y as u16,
            };
            if previous.contains_key(&next) {
                continue;
            }
            if next != end && next != start {
                let class = layout.tile(next).class;
                if class != TileClass::Public && class != TileClass::Maintenance {
                    continue;
                }
            }
            previous.insert(next, point);
            queue.push_back(next);
        }
    }
    if !previous.contains_key(&end) {
        return None;
    }
    let mut path = vec![end];
    let mut cursor = end;
    while cursor != start {
        cursor = previous[&cursor];
        path.push(cursor);
    }
    path.reverse();
    Some(path.into_iter().map(|p| [p.x + 1, p.y + 1]).collect())
}

fn door_direction(layout: &StationLayout, door: &Door) -> String {
    for (dx, dy, name) in [(1i32, 0i32, "E"), (-1, 0, "W"), (0, 1, "N"), (0, -1, "S")] {
        let x = i32::from(door.at.x) + dx;
        let y = i32::from(door.at.y) + dy;
        if x < 0 || y < 0 || x >= i32::from(layout.width) || y >= i32::from(layout.height) {
            continue;
        }
        let class = layout
            .tile(Point {
                x: x as u16,
                y: y as u16,
            })
            .class;
        if (door.connects_public && class == TileClass::Public)
            || (!door.connects_public && class == TileClass::Local)
        {
            return name.into();
        }
    }
    "N".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transit_path_is_real_nonempty_and_one_based() {
        let layout = StationLayout {
            seed: 1,
            width: 3,
            height: 1,
            archetype: MacroArchetype::Cross,
            tiles: vec![
                TileCell {
                    class: TileClass::Room,
                    ..Default::default()
                },
                TileCell {
                    class: TileClass::Public,
                    ..Default::default()
                },
                TileCell {
                    class: TileClass::Room,
                    ..Default::default()
                },
            ],
            departments: vec![],
            rooms: vec![],
            doors: vec![],
            public_circulation: vec![Point { x: 1, y: 0 }],
            maintenance: vec![],
            structure: vec![],
            hull: vec![],
            graph: LayoutGraph::default(),
            metadata: BTreeMap::new(),
        };
        assert_eq!(
            public_path(&layout, Point { x: 0, y: 0 }, Point { x: 2, y: 0 }),
            Some(vec![[1, 1], [2, 1], [3, 1]])
        );
    }

    #[test]
    fn transit_path_rejects_a_fake_disconnected_route() {
        let mut layout = StationLayout {
            seed: 1,
            width: 3,
            height: 1,
            archetype: MacroArchetype::Cross,
            tiles: vec![TileCell::default(); 3],
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
        layout.tiles[1].class = TileClass::Structure;
        assert!(public_path(&layout, Point { x: 0, y: 0 }, Point { x: 2, y: 0 }).is_none());
    }
}
