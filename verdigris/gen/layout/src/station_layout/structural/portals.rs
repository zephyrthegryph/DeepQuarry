use super::*;

/// Room growth operates on semantic programs, but an irregular partition can
/// produce a mix of full and compact envelopes. Replace only the geometry
/// variant of an existing semantic slot until every shape has at least one
/// compatible program; never invent a different room purpose.
pub(super) fn extend_common_halls_to_every_room(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
    for room_index in 0..plan.rooms.len() {
        let room = plan.rooms[room_index].clone();
        let room_space = Space::Room {
            department: room.department,
            room: room.id,
        };
        if !boundary_edges(plan, room_space, Space::Common(room.department)).is_empty() {
            continue;
        }
        let starts = plan
            .points()
            .filter(|point| plan.get(*point) == room_space)
            .collect::<BTreeSet<_>>();
        let goals = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Common(room.department))
            .collect::<BTreeSet<_>>();
        let allowed = plan
            .points()
            .filter(|point| {
                matches!(
                    plan.get(*point),
                    Space::Common(department) | Space::Room { department, .. }
                        if department == room.department
                )
            })
            .collect::<BTreeSet<_>>();
        let department_cells = allowed.iter().copied().collect::<Vec<_>>();
        let min_x = department_cells
            .iter()
            .map(|point| point.x)
            .min()
            .unwrap_or(0);
        let max_x = department_cells
            .iter()
            .map(|point| point.x)
            .max()
            .unwrap_or(0);
        let min_y = department_cells
            .iter()
            .map(|point| point.y)
            .min()
            .unwrap_or(0);
        let max_y = department_cells
            .iter()
            .map(|point| point.y)
            .max()
            .unwrap_or(0);
        let safe_allowed = plan
            .points()
            .filter(|point| {
                (point.x >= min_x.saturating_sub(1)
                    && point.x <= max_x.saturating_add(1).min(plan.width - 1)
                    && point.y >= min_y.saturating_sub(1)
                    && point.y <= max_y.saturating_add(1).min(plan.height - 1)
                    && (plan.get(*point) == Space::Exterior
                        || matches!(plan.get(*point), Space::Common(department) if department == room.department)))
                    || plan.get(*point) == room_space
            })
            .collect::<BTreeSet<_>>();
        // A multi-source BFS commits whichever equally short branch its queue
        // happens to discover first. In a packed suite that branch can cut an
        // adjacent room at an articulation point even though another edge of
        // the orphan room has a completely safe route. Try every room boundary
        // origin, shortest-first, and commit only a branch which preserves all
        // neighboring room components and their authored minimum footprint.
        let mut ordered_starts = starts.iter().copied().collect::<Vec<_>>();
        ordered_starts.sort_by_key(|start| {
            (
                goals
                    .iter()
                    .map(|goal| cell_distance(*start, *goal))
                    .min()
                    .unwrap_or(u16::MAX),
                hash_cell(u64::from(room.id), *start),
            )
        });
        let mut connected = false;
        for start in ordered_starts {
            let start_set = BTreeSet::from([start]);
            let path = shortest_path_between_sets(
                &start_set,
                &goals,
                &safe_allowed,
                plan.width,
                plan.height,
            )
            .or_else(|| {
                shortest_path_between_sets(&start_set, &goals, &allowed, plan.width, plan.height)
            });
            let Some(path) = path else {
                continue;
            };
            let mut changed = Vec::new();
            for point in path {
                if plan.get(point) != room_space
                    && plan.get(point) != Space::Common(room.department)
                {
                    changed.push((point, plan.get(point)));
                    plan.set(point, Space::Common(room.department));
                }
            }
            let affected = changed
                .iter()
                .filter_map(|(_, space)| space.room())
                .collect::<BTreeSet<_>>();
            let valid = !boundary_edges(plan, room_space, Space::Common(room.department))
                .is_empty()
                && affected.iter().all(|affected_id| {
                    let Some(affected_room) =
                        plan.rooms.iter().find(|other| other.id == *affected_id)
                    else {
                        return false;
                    };
                    let cells = plan
                        .points()
                        .filter(|point| plan.get(*point).room() == Some(*affected_id))
                        .collect::<BTreeSet<_>>();
                    !cells.is_empty()
                        && cells_connected(&cells, plan.width, plan.height)
                        && projected_room_tile_area(&cells)
                            >= room_minimum_area(&affected_room.room_type).div_ceil(2)
                });
            if valid {
                connected = true;
                break;
            }
            for (point, space) in changed {
                plan.set(point, space);
            }
        }
        if !connected {
            return Err(LayoutError(format!(
                "room {} needs a department hall branch that would disconnect a neighboring room",
                room.id
            )));
        }
    }
    Ok(())
}

pub(super) fn assign_portals(plan: &mut LogicalPlan, request: &LayoutRequest) -> Result<(), LayoutError> {
    let mut used_edges = BTreeSet::new();
    for room in &plan.rooms {
        let room_space = Space::Room {
            department: room.department,
            room: room.id,
        };
        let mut hall_edges = boundary_edges(plan, room_space, Space::Common(room.department));
        hall_edges.sort_by_key(|(left, right)| {
            (
                hash_cell(request.settings.seed ^ u64::from(room.id), *left),
                *right,
            )
        });
        let desired_hall_doors = request
            .departments
            .iter()
            .find(|department| department.id == room.department)
            .and_then(|department| {
                department
                    .room_types
                    .iter()
                    .find(|room_type| room_type.id == room.room_type.id)
            })
            .map(|room_type| usize::from(room_type.entrances.max(1)))
            .unwrap_or(2);
        let mut selected_hall: Vec<(CellPoint, CellPoint)> = Vec::new();
        for edge in hall_edges {
            if selected_hall.len() >= desired_hall_doors
                || selected_hall
                    .iter()
                    .any(|selected| cell_distance(selected.0, edge.0) < 3)
            {
                continue;
            }
            used_edges.insert(normalize_edge(edge.0, edge.1));
            plan.portals.push(Portal {
                left: edge.0,
                right: edge.1,
                department: room.department,
                room: Some(room.id),
                kind: PortalKind::Room,
            });
            selected_hall.push(edge);
        }
        if selected_hall.is_empty() {
            let cells = plan
                .cells
                .iter()
                .enumerate()
                .filter_map(|(index, space)| {
                    (*space == room_space).then_some(CellPoint {
                        x: (index % usize::from(plan.width)) as u16,
                        y: (index / usize::from(plan.width)) as u16,
                    })
                })
                .collect::<Vec<_>>();
            return Err(LayoutError(format!(
                "room {} ({}) in department {} has no direct department hallway frontage; cells={cells:?}",
                room.id, room.room_type.name, room.department
            )));
        }
        // Public-facing rooms may additionally open onto the main corridor,
        // but this never replaces their required departmental-hall door.
        if room_allows_main_corridor_entrance(&room.room_type) {
            if let Some(edge) = boundary_edges(plan, room_space, Space::Public)
                .into_iter()
                .filter(|edge| !used_edges.contains(&normalize_edge(edge.0, edge.1)))
                .min_by_key(|(left, right)| {
                    (
                        hash_cell(
                            request.settings.seed ^ 0x7075_626c_6963_0000 ^ u64::from(room.id),
                            *left,
                        ),
                        *right,
                    )
                })
            {
                used_edges.insert(normalize_edge(edge.0, edge.1));
                plan.portals.push(Portal {
                    left: edge.0,
                    right: edge.1,
                    department: room.department,
                    room: Some(room.id),
                    kind: PortalKind::Public,
                });
            }
        }
        // A maintenance boundary retains its explicit service door so it
        // never becomes a misleading inaccessible passage.
        let service_edge = boundary_edges(plan, room_space, Space::Maintenance)
            .into_iter()
            .filter(|edge| !used_edges.contains(&normalize_edge(edge.0, edge.1)))
            .min_by_key(|(left, right)| {
                (
                    hash_cell(
                        request.settings.seed ^ 0x7365_7276_6963_6500 ^ u64::from(room.id),
                        *left,
                    ),
                    *right,
                )
            });
        if let Some(edge) = service_edge {
            used_edges.insert(normalize_edge(edge.0, edge.1));
            plan.portals.push(Portal {
                left: edge.0,
                right: edge.1,
                department: room.department,
                room: Some(room.id),
                kind: PortalKind::RoomMaintenance,
            });
        }
    }
    for department in &request.departments {
        let mut department_public_edges =
            boundary_edges(plan, Space::Common(department.id), Space::Public);
        department_public_edges.sort_by_key(|(left, right)| {
            (
                cell_distance(*left, plan.department_centers[&department.id]),
                hash_cell(request.settings.seed ^ u64::from(department.id), *right),
            )
        });
        let public_edge = department_public_edges
            .iter()
            .copied()
            .filter(|edge| !used_edges.contains(&normalize_edge(edge.0, edge.1)))
            .min_by_key(|(left, right)| {
                (
                    cell_distance(*left, plan.department_centers[&department.id]),
                    *right,
                )
            });
        if let Some(public_edge) = public_edge {
            used_edges.insert(normalize_edge(public_edge.0, public_edge.1));
            plan.portals.push(Portal {
                left: public_edge.0,
                right: public_edge.1,
                department: department.id,
                room: None,
                kind: PortalKind::Public,
            });
            let mut selected_public = vec![public_edge];
            let public_target = department_public_edges.len().div_ceil(8).clamp(2, 4);
            for edge in department_public_edges {
                if selected_public.len() >= public_target
                    || used_edges.contains(&normalize_edge(edge.0, edge.1))
                    || selected_public
                        .iter()
                        .any(|selected| cell_distance(selected.0, edge.0) < 4)
                {
                    continue;
                }
                used_edges.insert(normalize_edge(edge.0, edge.1));
                plan.portals.push(Portal {
                    left: edge.0,
                    right: edge.1,
                    department: department.id,
                    room: None,
                    kind: PortalKind::Public,
                });
                selected_public.push(edge);
            }
        }
        // A public trunk can divide the comb into several local-hall
        // components. Give each component exactly one public junction so no
        // short branch becomes a sealed hallway island.
        let common_cells = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Common(department.id))
            .collect::<BTreeSet<_>>();
        for component in connected_components(&common_cells, plan.width, plan.height) {
            if plan.portals.iter().any(|portal| {
                portal.department == department.id
                    && portal.kind == PortalKind::Public
                    && (component.contains(&portal.left) || component.contains(&portal.right))
            }) {
                continue;
            }
            let mut edge = None;
            'component_edge: for point in &component {
                for neighbor in plan.neighbors(*point) {
                    let candidate = (*point, neighbor);
                    if plan.get(neighbor) == Space::Public
                        && !used_edges.contains(&normalize_edge(candidate.0, candidate.1))
                    {
                        edge = Some(candidate);
                        break 'component_edge;
                    }
                }
            }
            if let Some(edge) = edge {
                used_edges.insert(normalize_edge(edge.0, edge.1));
                plan.portals.push(Portal {
                    left: edge.0,
                    right: edge.1,
                    department: department.id,
                    room: None,
                    kind: PortalKind::Public,
                });
            }
        }
        let mut access_edges =
            boundary_edges(plan, Space::Common(department.id), Space::Maintenance);
        access_edges.sort_by_key(|(left, right)| {
            (
                cell_distance(*left, plan.department_centers[&department.id]),
                hash_cell(request.settings.seed ^ u64::from(department.id), *right),
            )
        });
        let mut selected_access: Vec<(CellPoint, CellPoint)> = Vec::new();
        for edge in access_edges {
            if selected_access.len() >= 4
                || used_edges.contains(&normalize_edge(edge.0, edge.1))
                || selected_access
                    .iter()
                    .any(|selected| cell_distance(selected.0, edge.0) < 2)
            {
                continue;
            }
            used_edges.insert(normalize_edge(edge.0, edge.1));
            plan.portals.push(Portal {
                left: edge.0,
                right: edge.1,
                department: department.id,
                room: None,
                kind: PortalKind::Maintenance,
            });
            selected_access.push(edge);
        }
        let has_room_maintenance_access = plan.portals.iter().any(|portal| {
            portal.department == department.id && portal.kind == PortalKind::RoomMaintenance
        });
        let _ = has_room_maintenance_access;
    }

    let mut public_maintenance = boundary_edges(plan, Space::Public, Space::Maintenance);
    public_maintenance.sort_by_key(|(left, right)| {
        hash_cell(request.settings.seed ^ 0x7075_626d_6169_6e74, *left)
            ^ hash_cell(request.settings.seed, *right)
    });
    let mut selected_public_maintenance: Vec<(CellPoint, CellPoint)> = Vec::new();
    let public_cells: BTreeSet<_> = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Public)
        .collect();
    for component in connected_components(&public_cells, plan.width, plan.height) {
        let edge = public_maintenance
            .iter()
            .copied()
            .find(|edge| {
                component.contains(&edge.0) && !used_edges.contains(&normalize_edge(edge.0, edge.1))
            })
            .ok_or_else(|| {
                LayoutError("public circulation component has no maintenance access".into())
            })?;
        let department = plan
            .department_centers
            .iter()
            .min_by_key(|(_, center)| cell_distance(**center, edge.0))
            .map(|(department, _)| *department)
            .ok_or_else(|| LayoutError("public maintenance door has no owner".into()))?;
        used_edges.insert(normalize_edge(edge.0, edge.1));
        plan.portals.push(Portal {
            left: edge.0,
            right: edge.1,
            department,
            room: None,
            kind: PortalKind::PublicMaintenance,
        });
        selected_public_maintenance.push(edge);
    }
    let public_maintenance_target = (public_maintenance.len() / 10)
        .clamp(2, 6)
        .max(selected_public_maintenance.len());
    for edge in public_maintenance {
        if selected_public_maintenance.len() >= public_maintenance_target
            || used_edges.contains(&normalize_edge(edge.0, edge.1))
            || selected_public_maintenance
                .iter()
                .any(|selected| cell_distance(selected.0, edge.0) < 4)
        {
            continue;
        }
        let department = plan
            .department_centers
            .iter()
            .min_by_key(|(_, center)| cell_distance(**center, edge.0))
            .map(|(department, _)| *department)
            .ok_or_else(|| LayoutError("public maintenance door has no owner".into()))?;
        used_edges.insert(normalize_edge(edge.0, edge.1));
        plan.portals.push(Portal {
            left: edge.0,
            right: edge.1,
            department,
            room: None,
            kind: PortalKind::PublicMaintenance,
        });
        selected_public_maintenance.push(edge);
    }

    let maintenance: BTreeSet<_> = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Maintenance)
        .collect();
    let degree = |point: CellPoint| {
        plan.neighbors(point)
            .filter(|neighbor| maintenance.contains(neighbor))
            .count()
    };
    let mut choke_candidates = Vec::new();
    for left in &maintenance {
        for right in plan
            .neighbors(*left)
            .filter(|right| maintenance.contains(right))
        {
            if *left >= right || degree(*left) != 2 || degree(right) != 2 {
                continue;
            }
            let aligned = if left.x != right.x {
                maintenance.contains(&CellPoint {
                    x: left.x.saturating_sub(1),
                    y: left.y,
                }) && maintenance.contains(&CellPoint {
                    x: right.x + 1,
                    y: right.y,
                })
            } else {
                maintenance.contains(&CellPoint {
                    x: left.x,
                    y: left.y.saturating_sub(1),
                }) && maintenance.contains(&CellPoint {
                    x: right.x,
                    y: right.y + 1,
                })
            };
            if aligned {
                choke_candidates.push((*left, right));
            }
        }
    }
    // A widened turn or unavoidable articulation may retain a 2x2 logical
    // maintenance bay. Split every such bay with a real wall/door boundary
    // instead of deleting floor into an opaque structural block. Alternating
    // orientation produces a connected serpentine service route.
    let mut broad_chokes = BTreeSet::new();
    for point in &maintenance {
        let Some(east) = point.x.checked_add(1) else {
            continue;
        };
        let Some(north) = point.y.checked_add(1) else {
            continue;
        };
        let block = [
            *point,
            CellPoint {
                x: east,
                y: point.y,
            },
            CellPoint {
                x: point.x,
                y: north,
            },
            CellPoint { x: east, y: north },
        ];
        if !block.iter().all(|cell| maintenance.contains(cell)) {
            continue;
        }
        let (edge, companion) = if hash_cell(request.settings.seed ^ 0x6d61_7a65, *point) & 1 == 0 {
            (
                (
                    *point,
                    CellPoint {
                        x: east,
                        y: point.y,
                    },
                ),
                (
                    CellPoint {
                        x: point.x,
                        y: north,
                    },
                    CellPoint { x: east, y: north },
                ),
            )
        } else {
            (
                (
                    *point,
                    CellPoint {
                        x: point.x,
                        y: north,
                    },
                ),
                (
                    CellPoint {
                        x: east,
                        y: point.y,
                    },
                    CellPoint { x: east, y: north },
                ),
            )
        };
        broad_chokes.insert(normalize_edge(edge.0, edge.1));
        plan.maintenance_barriers
            .insert(normalize_edge(companion.0, companion.1));
        choke_candidates.push(edge);
    }
    choke_candidates.retain(|edge| {
        !plan
            .maintenance_barriers
            .contains(&normalize_edge(edge.0, edge.1))
    });
    choke_candidates.sort();
    choke_candidates.dedup();
    choke_candidates.sort_by_key(|(left, right)| {
        hash_cell(request.settings.seed ^ 0x6d61_696e_745f_646f, *left)
            ^ hash_cell(request.settings.seed, *right)
    });
    let choke_target = (maintenance.len() / 14).max(4) + broad_chokes.len();
    let mut selected_chokes: Vec<(CellPoint, CellPoint)> = Vec::new();
    for edge in choke_candidates {
        let required_broad_choke = broad_chokes.contains(&normalize_edge(edge.0, edge.1));
        if (!required_broad_choke
            && (selected_chokes.len() >= choke_target
                || selected_chokes
                    .iter()
                    .any(|selected| cell_distance(selected.0, edge.0) < 4)))
            || selected_chokes.iter().any(|selected| {
                normalize_edge(selected.0, selected.1) == normalize_edge(edge.0, edge.1)
            })
        {
            continue;
        }
        let department = plan
            .department_centers
            .iter()
            .min_by_key(|(_, center)| cell_distance(**center, edge.0))
            .map(|(department, _)| *department)
            .ok_or_else(|| LayoutError("maintenance choke has no owning department".into()))?;
        plan.portals.push(Portal {
            left: edge.0,
            right: edge.1,
            department,
            room: None,
            kind: PortalKind::MaintenanceChoke,
        });
        selected_chokes.push(edge);
    }
    Ok(())
}

pub(super) fn boundary_edges(plan: &LogicalPlan, left: Space, right: Space) -> Vec<(CellPoint, CellPoint)> {
    let mut edges = Vec::new();
    for point in plan.points().filter(|point| plan.get(*point) == left) {
        for neighbor in plan
            .neighbors(point)
            .filter(|neighbor| plan.get(*neighbor) == right)
        {
            edges.push((point, neighbor));
        }
    }
    edges
}

pub(super) fn normalize_edge(left: CellPoint, right: CellPoint) -> (CellPoint, CellPoint) {
    if left <= right {
        (left, right)
    } else {
        (right, left)
    }
}
