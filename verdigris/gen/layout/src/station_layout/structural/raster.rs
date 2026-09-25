use super::*;

pub(super) fn rasterize(request: &LayoutRequest, plan: &LogicalPlan) -> Result<StationLayout, LayoutError> {
    let mut tiles = vec![
        TileCell::default();
        usize::from(request.settings.width) * usize::from(request.settings.height)
    ];
    let index = |point: Point| {
        usize::from(point.y) * usize::from(request.settings.width) + usize::from(point.x)
    };
    let logical_floor = |space: Space| match space {
        Space::Exterior => TileCell::default(),
        Space::Public => TileCell {
            class: TileClass::Public,
            owner: None,
            room: None,
            flags: 0,
        },
        Space::Maintenance => TileCell {
            class: TileClass::Maintenance,
            owner: None,
            room: None,
            flags: 0,
        },
        Space::Common(owner) => TileCell {
            class: TileClass::Local,
            owner: Some(owner),
            room: None,
            flags: 0,
        },
        Space::Room { department, room } => TileCell {
            class: TileClass::Room,
            owner: Some(department),
            room: Some(room),
            flags: 0,
        },
    };
    let lattice_point = |cell: CellPoint, dx: u16, dy: u16| Point {
        x: plan.origin.x + cell.x * PITCH + dx,
        y: plan.origin.y + cell.y * PITCH + dy,
    };
    let mut choke_edges: BTreeSet<_> = plan
        .portals
        .iter()
        .filter(|portal| portal.kind == PortalKind::MaintenanceChoke)
        .map(|portal| normalize_edge(portal.left, portal.right))
        .collect();
    choke_edges.extend(plan.maintenance_barriers.iter().copied());

    for point in plan.points() {
        let space = plan.get(point);
        if space == Space::Exterior {
            continue;
        }
        for dy in 1..=INTERIOR {
            for dx in 1..=INTERIOR {
                tiles[index(lattice_point(point, dx, dy))] = if matches!(space, Space::Common(_))
                    && (dx > request.settings.corridor_width
                        || dy > request.settings.corridor_width)
                {
                    TileCell {
                        class: TileClass::Structure,
                        owner: space.department(),
                        room: None,
                        flags: 0,
                    }
                } else {
                    logical_floor(space)
                };
            }
        }
    }
    for point in plan.points() {
        let space = plan.get(point);
        if space == Space::Exterior {
            continue;
        }
        if point.x + 1 < plan.width {
            let east_point = CellPoint {
                x: point.x + 1,
                y: point.y,
            };
            if plan.get(east_point) == space
                && !choke_edges.contains(&normalize_edge(point, east_point))
            {
                let span = if matches!(space, Space::Common(_)) {
                    request.settings.corridor_width
                } else {
                    INTERIOR
                };
                for dy in 1..=span {
                    tiles[index(lattice_point(point, PITCH, dy))] = logical_floor(space);
                }
            }
        }
        if point.y + 1 < plan.height {
            let north_point = CellPoint {
                x: point.x,
                y: point.y + 1,
            };
            if plan.get(north_point) == space
                && !choke_edges.contains(&normalize_edge(point, north_point))
            {
                let span = if matches!(space, Space::Common(_)) {
                    request.settings.corridor_width
                } else {
                    INTERIOR
                };
                for dx in 1..=span {
                    tiles[index(lattice_point(point, dx, PITCH))] = logical_floor(space);
                }
            }
        }
        if point.x + 1 < plan.width && point.y + 1 < plan.height {
            let quartet = [
                space,
                plan.get(CellPoint {
                    x: point.x + 1,
                    y: point.y,
                }),
                plan.get(CellPoint {
                    x: point.x,
                    y: point.y + 1,
                }),
                plan.get(CellPoint {
                    x: point.x + 1,
                    y: point.y + 1,
                }),
            ];
            if quartet.iter().all(|candidate| *candidate == space) {
                tiles[index(lattice_point(point, PITCH, PITCH))] = logical_floor(space);
            }
        }
    }

    for point in plan.points() {
        let space = plan.get(point);
        if point.x + 1 < plan.width {
            let east = plan.get(CellPoint {
                x: point.x + 1,
                y: point.y,
            });
            let choke = choke_edges.contains(&normalize_edge(
                point,
                CellPoint {
                    x: point.x + 1,
                    y: point.y,
                },
            ));
            if (east != space || choke) && (space != Space::Exterior || east != Space::Exterior) {
                let class = logical_boundary_class(space, east);
                for dy in 1..=INTERIOR {
                    tiles[index(lattice_point(point, PITCH, dy))] = TileCell {
                        class,
                        owner: if class == TileClass::Partition {
                            space.department().or(east.department())
                        } else {
                            None
                        },
                        room: None,
                        flags: 0,
                    };
                }
            }
        }
        if point.y + 1 < plan.height {
            let north = plan.get(CellPoint {
                x: point.x,
                y: point.y + 1,
            });
            let choke = choke_edges.contains(&normalize_edge(
                point,
                CellPoint {
                    x: point.x,
                    y: point.y + 1,
                },
            ));
            if (north != space || choke) && (space != Space::Exterior || north != Space::Exterior) {
                let class = logical_boundary_class(space, north);
                for dx in 1..=INTERIOR {
                    tiles[index(lattice_point(point, dx, PITCH))] = TileCell {
                        class,
                        owner: if class == TileClass::Partition {
                            space.department().or(north.department())
                        } else {
                            None
                        },
                        room: None,
                        flags: 0,
                    };
                }
            }
        }
        if point.x + 1 < plan.width && point.y + 1 < plan.height {
            let east_point = CellPoint {
                x: point.x + 1,
                y: point.y,
            };
            let north_point = CellPoint {
                x: point.x,
                y: point.y + 1,
            };
            let north_east = CellPoint {
                x: point.x + 1,
                y: point.y + 1,
            };
            let quartet = [
                space,
                plan.get(east_point),
                plan.get(north_point),
                plan.get(north_east),
            ];
            let choke_incident = [
                normalize_edge(point, east_point),
                normalize_edge(point, north_point),
                normalize_edge(north_point, north_east),
                normalize_edge(east_point, north_east),
            ]
            .iter()
            .any(|edge| choke_edges.contains(edge));
            if vertex_requires_post(quartet) || choke_incident {
                tiles[index(lattice_point(point, PITCH, PITCH))] = TileCell {
                    class: logical_vertex_class(quartet),
                    owner: quartet.iter().find_map(|space| space.department()),
                    room: None,
                    flags: 0,
                };
            }
        }
    }

    let mut structural: BTreeSet<_> = (0..request.settings.height)
        .flat_map(|y| (0..request.settings.width).map(move |x| Point { x, y }))
        .filter(|point| is_wall(tiles[index(*point)].class))
        .collect();

    let mut doors = Vec::new();
    for portal in &plan.portals {
        let at = raster_portal(*portal, plan);
        let floor = match portal.kind {
            PortalKind::Room | PortalKind::Public => TileCell {
                class: TileClass::Local,
                owner: Some(portal.department),
                room: None,
                flags: DOOR_FLAG,
            },
            PortalKind::Maintenance
            | PortalKind::RoomMaintenance
            | PortalKind::PublicMaintenance
            | PortalKind::MaintenanceChoke => TileCell {
                class: TileClass::Maintenance,
                owner: Some(portal.department),
                room: None,
                flags: DOOR_FLAG,
            },
        };
        tiles[index(at)] = floor;
        structural.remove(&at);
        doors.push(Door {
            id: u16::try_from(doors.len() + 1)
                .map_err(|_| LayoutError("station contains too many doors".into()))?,
            at,
            room_id: portal.room,
            department_id: portal.department,
            connects_public: matches!(
                portal.kind,
                PortalKind::Public | PortalKind::PublicMaintenance
            ),
            connects_maintenance: matches!(
                portal.kind,
                PortalKind::Maintenance
                    | PortalKind::RoomMaintenance
                    | PortalKind::PublicMaintenance
                    | PortalKind::MaintenanceChoke
            ),
            maintenance_choke: portal.kind == PortalKind::MaintenanceChoke,
        });
    }

    let exterior = exterior_flood(&tiles, request.settings.width, request.settings.height);
    let mut hull = BTreeSet::new();
    for point in &structural {
        if cardinal_points(*point, request.settings.width, request.settings.height)
            .into_iter()
            .any(|neighbor| exterior.contains(&neighbor))
        {
            hull.insert(*point);
        }
    }
    for point in &hull {
        tiles[index(*point)].class = TileClass::Hull;
    }
    structural.retain(|point| !hull.contains(point));

    let mut rooms = Vec::new();
    for room_plan in &plan.rooms {
        let room_tiles: Vec<_> = (0..request.settings.height)
            .flat_map(|y| (0..request.settings.width).map(move |x| Point { x, y }))
            .filter(|point| tiles[index(*point)].room == Some(room_plan.id))
            .collect();
        let bounds = bounds(&room_tiles)?;
        let door_ids = doors
            .iter()
            .filter(|door| door.room_id == Some(room_plan.id))
            .map(|door| door.id)
            .collect();
        rooms.push(Room {
            id: room_plan.id,
            department_id: room_plan.department,
            room_type_id: room_plan.room_type.id,
            bounds,
            tiles: room_tiles,
            door_ids,
        });
    }
    let mut departments = Vec::new();
    for department in &request.departments {
        let department_tiles: Vec<_> = (0..request.settings.height)
            .flat_map(|y| (0..request.settings.width).map(move |x| Point { x, y }))
            .filter(|point| tiles[index(*point)].owner == Some(department.id))
            .collect();
        let frontage_door = doors
            .iter()
            .find(|door| door.department_id == department.id && door.connects_public)
            .map(|door| door.id)
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {} lost its frontage portal",
                    department.id
                ))
            })?;
        departments.push(Department {
            id: department.id,
            bounds: bounds(&department_tiles)?,
            room_ids: rooms
                .iter()
                .filter(|room| room.department_id == department.id)
                .map(|room| room.id)
                .collect(),
            frontage_door,
        });
    }
    let public_circulation = points_with_class(&tiles, request.settings.width, TileClass::Public);
    let maintenance = points_with_class(&tiles, request.settings.width, TileClass::Maintenance);
    let layout = StationLayout {
        seed: request.settings.seed,
        width: request.settings.width,
        height: request.settings.height,
        archetype: match request.settings.seed % 5 {
            0 => MacroArchetype::Cross,
            1 => MacroArchetype::Ring,
            2 => MacroArchetype::Bent,
            3 => MacroArchetype::Branch,
            _ => MacroArchetype::Courtyard,
        },
        tiles,
        departments,
        rooms,
        doors,
        public_circulation,
        maintenance,
        structure: structural.into_iter().collect(),
        hull: hull.into_iter().collect(),
        graph: LayoutGraph {
            department_edges: plan.department_edges.clone(),
            room_edges: Vec::new(),
        },
        metadata: BTreeMap::from([
            ("geometry_model".into(), "structural-lattice-v1".into()),
            ("logical_pitch".into(), PITCH.to_string()),
        ]),
    };
    validate_raster_against_logical(&layout, plan)?;
    Ok(layout)
}

pub(super) fn logical_boundary_class(left: Space, right: Space) -> TileClass {
    if left == Space::Exterior || right == Space::Exterior {
        TileClass::Structure
    } else if left.department().is_some() || right.department().is_some() {
        TileClass::Partition
    } else {
        TileClass::Structure
    }
}

pub(super) fn vertex_requires_post(quartet: [Space; 4]) -> bool {
    quartet.iter().any(|space| *space != Space::Exterior)
        && !quartet.iter().all(|space| *space == quartet[0])
}

pub(super) fn logical_vertex_class(quartet: [Space; 4]) -> TileClass {
    if quartet.contains(&Space::Exterior) {
        TileClass::Structure
    } else if quartet.iter().any(|space| space.department().is_some()) {
        TileClass::Partition
    } else {
        TileClass::Structure
    }
}

pub(super) fn validate_raster_against_logical(
    layout: &StationLayout,
    plan: &LogicalPlan,
) -> Result<(), LayoutError> {
    let index =
        |point: Point| usize::from(point.y) * usize::from(layout.width) + usize::from(point.x);
    let lattice_point = |cell: CellPoint, dx: u16, dy: u16| Point {
        x: plan.origin.x + cell.x * PITCH + dx,
        y: plan.origin.y + cell.y * PITCH + dy,
    };
    let portal_edges: BTreeSet<_> = plan
        .portals
        .iter()
        .map(|portal| normalize_edge(portal.left, portal.right))
        .collect();
    let mut choke_edges: BTreeSet<_> = plan
        .portals
        .iter()
        .filter(|portal| portal.kind == PortalKind::MaintenanceChoke)
        .map(|portal| normalize_edge(portal.left, portal.right))
        .collect();
    choke_edges.extend(plan.maintenance_barriers.iter().copied());
    for point in plan.points() {
        let space = plan.get(point);
        if space != Space::Exterior {
            for dy in 1..=INTERIOR {
                for dx in 1..=INTERIOR {
                    let tile = layout.tiles[index(lattice_point(point, dx, dy))];
                    let class_matches = tile.class.walkable();
                    if !class_matches
                        || tile.owner != space.department()
                        || tile.room != space.room()
                    {
                        return Err(LayoutError(format!(
                            "logical interior {point:?} did not rasterize as {space:?}"
                        )));
                    }
                }
            }
        }
        for neighbor in [
            (point.x + 1 < plan.width).then_some(CellPoint {
                x: point.x + 1,
                y: point.y,
            }),
            (point.y + 1 < plan.height).then_some(CellPoint {
                x: point.x,
                y: point.y + 1,
            }),
        ]
        .into_iter()
        .flatten()
        {
            let other = plan.get(neighbor);
            if space == Space::Exterior && other == Space::Exterior {
                continue;
            }
            let edge = normalize_edge(point, neighbor);
            let has_portal = portal_edges.contains(&edge);
            let has_barrier = plan.maintenance_barriers.contains(&edge);
            let strip: Vec<_> = if point.x != neighbor.x {
                (1..=INTERIOR)
                    .map(|offset| lattice_point(point, PITCH, offset))
                    .collect()
            } else {
                (1..=INTERIOR)
                    .map(|offset| lattice_point(point, offset, PITCH))
                    .collect()
            };
            for (offset, tile_point) in strip.into_iter().enumerate() {
                let tile = layout.tiles[index(tile_point)];
                let expected_open =
                    (space == other && !has_portal && !has_barrier) || (has_portal && offset == 1);
                if expected_open != tile.class.walkable() {
                    return Err(LayoutError(format!(
                        "logical boundary {edge:?} disagrees with raster tile {tile_point:?}"
                    )));
                }
                if has_portal && offset == 1 && tile.flags & DOOR_FLAG == 0 {
                    return Err(LayoutError(format!(
                        "portal boundary {edge:?} lacks its declared door"
                    )));
                }
                if !expected_open && !is_wall(tile.class) {
                    return Err(LayoutError(format!(
                        "logical boundary {edge:?} has no wall at {tile_point:?}"
                    )));
                }
            }
        }
        if point.x + 1 < plan.width && point.y + 1 < plan.height {
            let east_point = CellPoint {
                x: point.x + 1,
                y: point.y,
            };
            let north_point = CellPoint {
                x: point.x,
                y: point.y + 1,
            };
            let north_east = CellPoint {
                x: point.x + 1,
                y: point.y + 1,
            };
            let quartet = [
                space,
                plan.get(east_point),
                plan.get(north_point),
                plan.get(north_east),
            ];
            let choke_incident = [
                normalize_edge(point, east_point),
                normalize_edge(point, north_point),
                normalize_edge(north_point, north_east),
                normalize_edge(east_point, north_east),
            ]
            .iter()
            .any(|edge| choke_edges.contains(edge));
            let tile_point = lattice_point(point, PITCH, PITCH);
            let tile = layout.tiles[index(tile_point)];
            if (vertex_requires_post(quartet) || choke_incident) && !is_wall(tile.class) {
                return Err(LayoutError(format!(
                    "mixed logical vertex at {point:?} lacks a wall post"
                )));
            }
            if quartet.iter().all(|space| *space == quartet[0])
                && quartet[0] != Space::Exterior
                && !choke_incident
                && !tile.class.walkable()
            {
                return Err(LayoutError(format!(
                    "uniform logical vertex at {point:?} contains a wall"
                )));
            }
        }
    }
    Ok(())
}

pub(super) fn raster_portal(portal: Portal, plan: &LogicalPlan) -> Point {
    let left = portal.left;
    let right = portal.right;
    if left.x != right.x {
        let west = if left.x < right.x { left } else { right };
        Point {
            x: plan.origin.x + west.x * PITCH + PITCH,
            y: plan.origin.y + west.y * PITCH + 2,
        }
    } else {
        let south = if left.y < right.y { left } else { right };
        Point {
            x: plan.origin.x + south.x * PITCH + 2,
            y: plan.origin.y + south.y * PITCH + PITCH,
        }
    }
}
