use super::*;

pub(super) fn validate_logical_plan(plan: &LogicalPlan, request: &LayoutRequest) -> Result<(), LayoutError> {
    for department in &request.departments {
        let spaces: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .collect();
        if spaces.is_empty() || !cells_connected(&spaces, plan.width, plan.height) {
            return Err(LayoutError(format!(
                "department {} ownership is disconnected",
                department.id
            )));
        }
        let room_ids: BTreeSet<_> = plan
            .rooms
            .iter()
            .filter(|room| room.department == department.id)
            .map(|room| room.id)
            .collect();
        for room_id in room_ids {
            let cells: BTreeSet<_> = plan
                .points()
                .filter(|point| plan.get(*point).room() == Some(room_id))
                .collect();
            if cells.is_empty() || !cells_connected(&cells, plan.width, plan.height) {
                return Err(LayoutError(format!(
                    "room {room_id} ownership is disconnected"
                )));
            }
            let planned_room = plan
                .rooms
                .iter()
                .find(|room| room.id == room_id)
                .ok_or_else(|| LayoutError(format!("room {room_id} lacks a room plan")))?;
            let room_type = &planned_room.room_type;
            if !room_shape_within_maximum(room_type, &cells) {
                return Err(LayoutError(format!(
                    "room {room_id} violates its authored content envelope (area {}, minimum {}, ideal {}, type {})",
                    projected_room_tile_area(&cells),
                    room_minimum_area(room_type),
                    room_type.ideal_area,
                    room_type.name,
                )));
            }
            let portal_count = plan
                .portals
                .iter()
                .filter(|portal| portal.room == Some(room_id))
                .count();
            if portal_count == 0 {
                return Err(LayoutError(format!(
                    "room {room_id} has no declared portal"
                )));
            }
            if !plan
                .portals
                .iter()
                .any(|portal| portal.room == Some(room_id) && portal.kind == PortalKind::Room)
            {
                return Err(LayoutError(format!(
                    "room {room_id} has no departmental hallway door"
                )));
            }
            let room_space = Space::Room {
                department: department.id,
                room: room_id,
            };
            if !boundary_edges(plan, room_space, Space::Maintenance).is_empty()
                && !plan.portals.iter().any(|portal| {
                    portal.room == Some(room_id) && portal.kind == PortalKind::RoomMaintenance
                })
            {
                return Err(LayoutError(format!(
                    "room {room_id} borders maintenance without a service door"
                )));
            }
        }
        if !plan.portals.iter().any(|portal| {
            portal.department == department.id
                && matches!(
                    portal.kind,
                    PortalKind::Public | PortalKind::Maintenance | PortalKind::RoomMaintenance
                )
        }) {
            return Err(LayoutError(format!(
                "department {} has no public or service access portal",
                department.id
            )));
        }
    }
    if !boundary_edges(plan, Space::Public, Space::Maintenance).is_empty()
        && !plan
            .portals
            .iter()
            .any(|portal| portal.kind == PortalKind::PublicMaintenance)
    {
        return Err(LayoutError(
            "public circulation borders maintenance without an access door".into(),
        ));
    }
    let maintenance: BTreeSet<_> = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Maintenance)
        .collect();
    for component in connected_components(&maintenance, plan.width, plan.height) {
        if !plan
            .portals
            .iter()
            .any(|portal| component.contains(&portal.left) || component.contains(&portal.right))
        {
            return Err(LayoutError(
                "maintenance component has no declared entrance".into(),
            ));
        }
    }
    Ok(())
}

pub(super) fn room_allows_main_corridor_entrance(room_type: &RoomType) -> bool {
    let name = room_type.name.to_ascii_lowercase();
    [
        "reception",
        "foyer",
        "lobby",
        "checkpoint",
        "liaison",
        "customs",
        "dispatch",
    ]
    .iter()
    .any(|role| name.contains(role))
}

/// Outline sculpting and service-space derivation may remove a narrow bridge
/// from an otherwise valid room. Convert every detached lobe into department
/// circulation before portals and IDs become immutable.
///
/// Never donate the lobe to a neighboring room. That old repair silently grew
/// an otherwise valid authored room beyond its content envelope and severed
/// the exact geometry/program match established by the packer.
pub(super) fn repair_disconnected_room_ownership(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
    for room in plan.rooms.clone() {
        let room_space = Space::Room {
            department: room.department,
            room: room.id,
        };
        let cells = plan
            .points()
            .filter(|point| plan.get(*point) == room_space)
            .collect::<BTreeSet<_>>();
        let mut components = connected_components(&cells, plan.width, plan.height);
        if components.len() <= 1 {
            continue;
        }
        components.sort_by_key(|component| Reverse(component.len()));
        for component in components.into_iter().skip(1) {
            let has_department_neighbor = component
                .iter()
                .flat_map(|point| plan.neighbors(*point))
                .map(|neighbor| plan.get(neighbor))
                .any(|space| {
                    space == Space::Common(room.department)
                        || matches!(
                            space,
                            Space::Room { department, .. } if department == room.department
                        )
                });
            if !has_department_neighbor {
                return Err(LayoutError(format!(
                    "room {} detached lobe has no department-side owner",
                    room.id
                )));
            }
            for point in component {
                plan.set(point, Space::Common(room.department));
            }
        }
    }
    Ok(())
}

pub fn validate_station_structure(layout: &StationLayout) -> Result<(), LayoutError> {
    if layout.tiles.len() != usize::from(layout.width) * usize::from(layout.height) {
        return Err(LayoutError("tile grid has the wrong size".into()));
    }
    let index =
        |point: Point| usize::from(point.y) * usize::from(layout.width) + usize::from(point.x);
    let door_points: BTreeSet<_> = layout.doors.iter().map(|door| door.at).collect();
    if door_points.len() != layout.doors.len() {
        return Err(LayoutError("multiple doors occupy one tile".into()));
    }
    for door in &layout.doors {
        let horizontal_passage = door.at.x > 0
            && door.at.x + 1 < layout.width
            && layout.tiles[index(Point {
                x: door.at.x - 1,
                y: door.at.y,
            })]
            .class
            .walkable()
            && layout.tiles[index(Point {
                x: door.at.x + 1,
                y: door.at.y,
            })]
            .class
            .walkable();
        let vertical_passage = door.at.y > 0
            && door.at.y + 1 < layout.height
            && layout.tiles[index(Point {
                x: door.at.x,
                y: door.at.y - 1,
            })]
            .class
            .walkable()
            && layout.tiles[index(Point {
                x: door.at.x,
                y: door.at.y + 1,
            })]
            .class
            .walkable();
        let horizontal_flanks = door.at.x > 0
            && door.at.x + 1 < layout.width
            && is_wall(
                layout.tiles[index(Point {
                    x: door.at.x - 1,
                    y: door.at.y,
                })]
                .class,
            )
            && is_wall(
                layout.tiles[index(Point {
                    x: door.at.x + 1,
                    y: door.at.y,
                })]
                .class,
            );
        let vertical_flanks = door.at.y > 0
            && door.at.y + 1 < layout.height
            && is_wall(
                layout.tiles[index(Point {
                    x: door.at.x,
                    y: door.at.y - 1,
                })]
                .class,
            )
            && is_wall(
                layout.tiles[index(Point {
                    x: door.at.x,
                    y: door.at.y + 1,
                })]
                .class,
            );
        if !((horizontal_passage && vertical_flanks) || (vertical_passage && horizontal_flanks)) {
            return Err(LayoutError(format!(
                "door {} lacks a passage axis and two wall flanks",
                door.id
            )));
        }
    }
    for room in &layout.rooms {
        if room.door_ids.is_empty() {
            return Err(LayoutError(format!("room {} has no door", room.id)));
        }
        let has_department_hall_door = room.door_ids.iter().any(|door_id| {
            let Some(door) = layout.doors.iter().find(|door| door.id == *door_id) else {
                return false;
            };
            if door.connects_maintenance {
                return false;
            }
            let neighbors = cardinal_points(door.at, layout.width, layout.height);
            neighbors
                .iter()
                .any(|point| layout.tiles[index(*point)].room == Some(room.id))
                && neighbors.iter().any(|point| {
                    let tile = &layout.tiles[index(*point)];
                    tile.class == TileClass::Local
                        && tile.owner == Some(room.department_id)
                        && tile.room.is_none()
                })
        });
        if !has_department_hall_door {
            return Err(LayoutError(format!(
                "room {} has no door directly onto its department hallway",
                room.id
            )));
        }
        let floor: BTreeSet<_> = room.tiles.iter().copied().collect();
        if !points_connected(&floor, layout.width, layout.height) {
            return Err(LayoutError(format!(
                "room {} floor is disconnected",
                room.id
            )));
        }
    }
    let walkable: BTreeSet<_> = (0..layout.height)
        .flat_map(|y| (0..layout.width).map(move |x| Point { x, y }))
        .filter(|point| layout.tiles[index(*point)].class.walkable())
        .collect();
    let start = layout
        .public_circulation
        .first()
        .copied()
        .ok_or_else(|| LayoutError("station has no public circulation".into()))?;
    let reached = flood_points(start, &walkable, layout.width, layout.height);
    if reached != walkable {
        let unreachable = walkable
            .difference(&reached)
            .map(|point| {
                let tile = layout.tile(*point);
                (*point, tile.class, tile.room)
            })
            .collect::<Vec<_>>();
        return Err(LayoutError(format!(
            "{} walkable station tiles are unreachable: {unreachable:?}",
            unreachable.len()
        )));
    }
    let exterior = exterior_flood(&layout.tiles, layout.width, layout.height);
    if exterior
        .iter()
        .any(|point| layout.tiles[index(*point)].class.walkable())
    {
        return Err(LayoutError("exterior flood reached station floor".into()));
    }
    let maintenance_floor: BTreeSet<_> = layout.maintenance.iter().copied().collect();
    let maintenance_components = point_components(&maintenance_floor, layout.width, layout.height);
    if maintenance_components.len() != 1 {
        return Err(LayoutError(format!(
            "maintenance raster contains {} disconnected networks",
            maintenance_components.len()
        )));
    }
    for component in maintenance_components {
        if !layout.doors.iter().any(|door| {
            door.connects_maintenance
                && cardinal_points(door.at, layout.width, layout.height)
                    .into_iter()
                    .any(|point| component.contains(&point))
        }) {
            return Err(LayoutError(
                "maintenance component lacks a maintenance door".into(),
            ));
        }
    }
    Ok(())
}
