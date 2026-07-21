use super::error::LayoutError;
use super::model::{
    Department, Door, LayoutGraph, LayoutRequest, MacroArchetype, Point, Rect, Room, RoomType,
    StationLayout, TileCell, TileClass,
};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

const MAINTENANCE_WIDTH: u16 = 2;
// A logical cell contains its walkable interior followed by one structural
// boundary tile. Main and local corridors deliberately share this compact
// module so intersections cannot accidentally widen maintenance.
const PITCH: u16 = MAINTENANCE_WIDTH + 1;
const INTERIOR: u16 = PITCH - 1;
const DOOR_FLAG: u32 = 1;

fn projected_room_tile_area(cells: &BTreeSet<CellPoint>) -> usize {
    let interiors = cells.len() * usize::from(INTERIOR).pow(2);
    let shared_edges = cells
        .iter()
        .map(|point| {
            usize::from(cells.contains(&CellPoint {
                x: point.x.saturating_add(1),
                y: point.y,
            })) + usize::from(cells.contains(&CellPoint {
                x: point.x,
                y: point.y.saturating_add(1),
            }))
        })
        .sum::<usize>();
    let shared_vertices = cells
        .iter()
        .filter(|point| {
            let Some(east_x) = point.x.checked_add(1) else {
                return false;
            };
            let Some(north_y) = point.y.checked_add(1) else {
                return false;
            };
            cells.contains(&CellPoint {
                x: east_x,
                y: point.y,
            }) && cells.contains(&CellPoint {
                x: point.x,
                y: north_y,
            }) && cells.contains(&CellPoint {
                x: east_x,
                y: north_y,
            })
        })
        .count();
    interiors + shared_edges * usize::from(INTERIOR) + shared_vertices
}

fn projected_room_dimensions(cells: &BTreeSet<CellPoint>) -> (usize, usize) {
    let Some(min_x) = cells.iter().map(|point| point.x).min() else {
        return (0, 0);
    };
    let max_x = cells.iter().map(|point| point.x).max().unwrap_or(min_x);
    let min_y = cells.iter().map(|point| point.y).min().unwrap_or(0);
    let max_y = cells.iter().map(|point| point.y).max().unwrap_or(min_y);
    (
        usize::from(max_x - min_x) * usize::from(PITCH) + usize::from(INTERIOR),
        usize::from(max_y - min_y) * usize::from(PITCH) + usize::from(INTERIOR),
    )
}

fn room_shape_fits(room: &RoomType, cells: &BTreeSet<CellPoint>) -> bool {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    if area < (room.content_area as usize).min(usize::from(INTERIOR).pow(2))
        || area > usize::from(room.max_width) * usize::from(room.max_height)
        || width < usize::from(INTERIOR)
        || height < usize::from(INTERIOR)
    {
        return false;
    }
    // Irregular rooms are composed from several rectangular lobes. Bounding-box
    // dimensions are useful for rejecting slivers, but do not describe the
    // usable dimensions of an L-shaped room well enough to enforce maxima.
    true
}

fn room_shape_score(room: &RoomType, cells: &BTreeSet<CellPoint>) -> usize {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let area_error = area.abs_diff(room.ideal_area as usize);
    let aspect_penalty = width.max(height).saturating_sub(width.min(height));
    area_error * 8 + aspect_penalty
}

fn room_logical_capacity(room: &RoomType) -> usize {
    let physical_capacity = usize::from(room.max_width) * usize::from(room.max_height);
    (physical_capacity / usize::from(PITCH).pow(2)).max(1)
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
struct CellPoint {
    x: u16,
    y: u16,
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
enum Space {
    Exterior,
    Public,
    Maintenance,
    Common(u16),
    Room { department: u16, room: u16 },
}

impl Space {
    fn department(self) -> Option<u16> {
        match self {
            Self::Common(department) | Self::Room { department, .. } => Some(department),
            _ => None,
        }
    }

    fn room(self) -> Option<u16> {
        match self {
            Self::Room { room, .. } => Some(room),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PortalKind {
    Room,
    Public,
    Maintenance,
    RoomMaintenance,
    PublicMaintenance,
    MaintenanceChoke,
}

#[derive(Clone, Copy, Debug)]
struct Portal {
    left: CellPoint,
    right: CellPoint,
    department: u16,
    room: Option<u16>,
    kind: PortalKind,
}

#[derive(Clone, Debug)]
struct RoomPlan {
    id: u16,
    department: u16,
    room_type: u16,
}

#[derive(Clone, Debug)]
struct LogicalPlan {
    width: u16,
    height: u16,
    origin: Point,
    cells: Vec<Space>,
    rooms: Vec<RoomPlan>,
    portals: Vec<Portal>,
    department_centers: BTreeMap<u16, CellPoint>,
    department_edges: Vec<(u16, u16)>,
}

impl LogicalPlan {
    fn index(&self, point: CellPoint) -> usize {
        usize::from(point.y) * usize::from(self.width) + usize::from(point.x)
    }

    fn get(&self, point: CellPoint) -> Space {
        self.cells[self.index(point)]
    }

    fn set(&mut self, point: CellPoint, value: Space) {
        let index = self.index(point);
        self.cells[index] = value;
    }

    fn points(&self) -> impl Iterator<Item = CellPoint> + '_ {
        (0..self.height).flat_map(|y| (0..self.width).map(move |x| CellPoint { x, y }))
    }

    fn neighbors(&self, point: CellPoint) -> impl Iterator<Item = CellPoint> + '_ {
        cardinal_cells(point, self.width, self.height).into_iter()
    }
}

#[derive(Clone, Copy)]
struct Rng(u64);

impl Rng {
    fn new(seed: u64) -> Self {
        Self(mix(seed ^ 0xd1b5_4a32_d192_ed03))
    }

    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0 = self.0.wrapping_mul(0x2545_f491_4f6c_dd1d);
        self.0
    }

    fn choose(&mut self, length: usize) -> usize {
        (self.next() % length as u64) as usize
    }

    fn signed(&mut self, radius: i16) -> i16 {
        (self.next() % u64::from((radius * 2 + 1) as u16)) as i16 - radius
    }
}

pub fn generate_station_layout(request: &LayoutRequest) -> Result<StationLayout, LayoutError> {
    if request.departments.is_empty() {
        return Err(LayoutError(
            "station catalog contains no departments".into(),
        ));
    }
    if request.settings.width < 64 || request.settings.height < 64 {
        return Err(LayoutError(
            "structural station generator requires at least a 64x64 canvas".into(),
        ));
    }
    let public_seed = request.settings.seed;
    let mut last_error = None;
    // A catalog-valid seed must not become a hard runtime failure merely
    // because one randomized center/claim arrangement cannot expose every
    // required room frontage. Retry a bounded deterministic sequence while
    // retaining the caller's public seed in the result.
    for attempt in 0_u64..16 {
        let mut candidate = request.clone();
        candidate.settings.seed = public_seed.wrapping_add(attempt.wrapping_mul(0x9e37_79b9));
        let generated = (|| {
            let logical = build_logical_plan(&candidate)?;
            let mut station = rasterize(&candidate, &logical)?;
            validate_station_structure(&station)?;
            station.seed = public_seed;
            Ok(station)
        })();
        match generated {
            Ok(station) => return Ok(station),
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error
        .unwrap_or_else(|| LayoutError("station generation exhausted its candidates".into())))
}

fn build_logical_plan(request: &LayoutRequest) -> Result<LogicalPlan, LayoutError> {
    let width = (request.settings.width - 3) / PITCH;
    let height = (request.settings.height - 3) / PITCH;
    if width < 15 || height < 15 {
        return Err(LayoutError("logical station canvas is too small".into()));
    }
    let span_x = width * PITCH + 1;
    let span_y = height * PITCH + 1;
    let origin = Point {
        x: (request.settings.width - span_x) / 2,
        y: (request.settings.height - span_y) / 2,
    };
    let mut plan = LogicalPlan {
        width,
        height,
        origin,
        cells: vec![Space::Exterior; usize::from(width) * usize::from(height)],
        rooms: Vec::new(),
        portals: Vec::new(),
        department_centers: BTreeMap::new(),
        department_edges: Vec::new(),
    };
    let silhouette: BTreeSet<_> = plan
        .points()
        .filter(|point| in_rounded_silhouette(*point, width, height))
        .collect();
    let mut outer_maintenance: BTreeSet<_> = silhouette
        .iter()
        .copied()
        .filter(|point| {
            cardinal_cells(*point, width, height)
                .into_iter()
                .any(|neighbor| !silhouette.contains(&neighbor))
                || point.x == 0
                || point.y == 0
                || point.x + 1 == width
                || point.y + 1 == height
        })
        .collect();
    loop {
        let components = connected_components(&outer_maintenance, width, height);
        if components.len() <= 1 {
            break;
        }
        let root = components
            .iter()
            .max_by_key(|component| component.len())
            .cloned()
            .ok_or_else(|| LayoutError("exterior maintenance loop is empty".into()))?;
        let source = components
            .iter()
            .filter(|component| **component != root)
            .min_by_key(|component| {
                component
                    .iter()
                    .flat_map(|left| root.iter().map(move |right| cell_distance(*left, *right)))
                    .min()
                    .unwrap_or(u16::MAX)
            })
            .cloned()
            .ok_or_else(|| LayoutError("exterior maintenance loop has no segment".into()))?;
        let path = shortest_path_between_sets(&source, &root, &silhouette, width, height)
            .ok_or_else(|| LayoutError("cannot close exterior maintenance loop".into()))?;
        outer_maintenance.extend(path);
    }
    loop {
        let endpoints: Vec<_> = outer_maintenance
            .iter()
            .copied()
            .filter(|point| {
                cardinal_cells(*point, width, height)
                    .into_iter()
                    .filter(|neighbor| outer_maintenance.contains(neighbor))
                    .count()
                    < 2
            })
            .collect();
        if endpoints.is_empty() {
            break;
        }
        if endpoints.len() < 2 {
            return Err(LayoutError(
                "exterior maintenance loop has an unmatched endpoint".into(),
            ));
        }
        let (left, right) = endpoints
            .iter()
            .enumerate()
            .flat_map(|(index, left)| {
                endpoints
                    .iter()
                    .skip(index + 1)
                    .map(move |right| (*left, *right))
            })
            .min_by_key(|(left, right)| cell_distance(*left, *right))
            .ok_or_else(|| LayoutError("exterior maintenance loop cannot close".into()))?;
        let before = outer_maintenance.len();
        let path = shortest_path_between_sets(
            &BTreeSet::from([left]),
            &BTreeSet::from([right]),
            &silhouette,
            width,
            height,
        )
        .ok_or_else(|| LayoutError("cannot route exterior maintenance corner".into()))?;
        outer_maintenance.extend(path);
        if outer_maintenance.len() == before {
            return Err(LayoutError(
                "exterior maintenance corner closure made no progress".into(),
            ));
        }
    }
    for point in &outer_maintenance {
        plan.set(*point, Space::Maintenance);
    }

    let mut rng = Rng::new(request.settings.seed);
    let mut centers = place_centers(request, &silhouette, &outer_maintenance, &mut rng)?;
    let frontages: Vec<_> = centers
        .iter()
        .map(|center| frontage_toward_center(*center, width, height))
        .collect();
    let tree = minimum_spanning_tree(&frontages, &mut rng);
    plan.department_edges = tree
        .iter()
        .map(|(left, right)| {
            (
                request.departments[*left].id,
                request.departments[*right].id,
            )
        })
        .collect();
    let mut public = BTreeSet::new();
    let hub = CellPoint {
        x: (i32::from(width / 2) + i32::from(rng.signed(1))) as u16,
        y: (i32::from(height / 2) + i32::from(rng.signed(1))) as u16,
    };
    // The public hall follows the department minimum-spanning tree. A hub-star
    // partitions the silhouette into centerless lobes that later become giant
    // accidental concourses; a tree connects every frontage without enclosing
    // unrelated floor area.
    for (edge_index, (left, right)) in tree.iter().copied().enumerate() {
        let from = frontages[left];
        let to = frontages[right];
        let horizontal_first =
            (hash_cell(request.settings.seed ^ edge_index as u64, from) & 1) == 0;
        let bend = if horizontal_first {
            CellPoint { x: to.x, y: from.y }
        } else {
            CellPoint { x: from.x, y: to.y }
        };
        carve_logical_segment(&mut public, from, bend, &silhouette, &outer_maintenance);
        carve_logical_segment(&mut public, bend, to, &silhouette, &outer_maintenance);
    }
    for point in &public {
        plan.set(*point, Space::Public);
    }
    for index in 0..centers.len() {
        if public.contains(&centers[index]) || cell_distance(centers[index], hub) <= 4 {
            centers[index] = silhouette
                .iter()
                .copied()
                .filter(|point| !public.contains(point) && !outer_maintenance.contains(point))
                .filter(|point| {
                    centers.iter().enumerate().all(|(other_index, other)| {
                        other_index == index || cell_distance(*other, *point) >= 3
                    })
                })
                .min_by_key(|point| {
                    (
                        cell_distance(*point, centers[index]),
                        hash_cell(request.settings.seed ^ index as u64, *point),
                    )
                })
                .ok_or_else(|| {
                    LayoutError(
                        "cannot relocate a department center around the public trunk".into(),
                    )
                })?;
        }
    }
    let mut claimable: BTreeSet<_> = silhouette
        .iter()
        .copied()
        .filter(|point| !public.contains(point) && plan.get(*point) != Space::Maintenance)
        .collect();
    for component in connected_components(&claimable, width, height) {
        if component.len() >= 16 {
            continue;
        }
        for point in component {
            claimable.remove(&point);
            plan.set(point, Space::Maintenance);
        }
    }
    let claim_components = connected_components(&claimable, width, height);
    if claim_components.len() > centers.len() {
        return Err(LayoutError(format!(
            "public circulation divides the station into {} department regions for {} departments",
            claim_components.len(),
            centers.len()
        )));
    }
    loop {
        let empty_component = claim_components
            .iter()
            .find(|component| !centers.iter().any(|center| component.contains(center)));
        let Some(empty_component) = empty_component else {
            break;
        };
        let donor_index = (0..centers.len())
            .filter(|index| {
                claim_components.iter().any(|component| {
                    component.contains(&centers[*index])
                        && centers
                            .iter()
                            .filter(|center| component.contains(center))
                            .count()
                            > 1
                })
            })
            .max_by_key(|index| {
                empty_component
                    .iter()
                    .map(|point| cell_distance(centers[*index], *point))
                    .min()
                    .unwrap_or(0)
            })
            .ok_or_else(|| LayoutError("cannot seed every department region".into()))?;
        centers[donor_index] = empty_component
            .iter()
            .copied()
            .min_by_key(|point| {
                (
                    cell_distance(*point, hub),
                    hash_cell(request.settings.seed ^ donor_index as u64, *point),
                )
            })
            .ok_or_else(|| LayoutError("department region has no floor".into()))?;
    }
    for (department, center) in request.departments.iter().zip(&centers) {
        plan.department_centers.insert(department.id, *center);
    }

    grow_department_claims(request, &mut plan, &silhouette, &centers, &public, &mut rng)?;
    insert_internal_maintenance(&mut plan, request)?;
    assign_department_common_and_rooms(&mut plan, request, &mut rng)?;
    assign_portals(&mut plan, request)?;
    validate_logical_plan(&plan, request)?;
    Ok(plan)
}

fn in_rounded_silhouette(point: CellPoint, width: u16, height: u16) -> bool {
    let margin = 1i32;
    let radius = 3i32;
    let x = i32::from(point.x);
    let y = i32::from(point.y);
    let right = i32::from(width) - 1 - margin;
    let top = i32::from(height) - 1 - margin;
    if x < margin || y < margin || x > right || y > top {
        return false;
    }
    let dx = if x < margin + radius {
        margin + radius - x
    } else if x > right - radius {
        x - (right - radius)
    } else {
        0
    };
    let dy = if y < margin + radius {
        margin + radius - y
    } else if y > top - radius {
        y - (top - radius)
    } else {
        0
    };
    dx * dx + dy * dy <= radius * radius + 1
}

fn place_centers(
    request: &LayoutRequest,
    silhouette: &BTreeSet<CellPoint>,
    maintenance: &BTreeSet<CellPoint>,
    rng: &mut Rng,
) -> Result<Vec<CellPoint>, LayoutError> {
    let width = (request.settings.width - 3) / PITCH;
    let height = (request.settings.height - 3) / PITCH;
    let cx = i16::try_from(width / 2).unwrap();
    let cy = i16::try_from(height / 2).unwrap();
    let rx = i16::try_from(width / 3).unwrap().max(5);
    let ry = i16::try_from(height / 3).unwrap().max(5);
    let pattern = [
        (-3, -3),
        (0, -3),
        (3, -3),
        (3, 0),
        (3, 3),
        (0, 3),
        (-3, 3),
        (-3, 0),
    ];
    let omitted = (request.departments.len() < pattern.len()).then(|| rng.choose(pattern.len()));
    let rotation = rng.choose(pattern.len());
    let slots: Vec<_> = (0..pattern.len())
        .map(|index| (index + rotation) % pattern.len())
        .filter(|index| Some(*index) != omitted)
        .collect();
    let mut centers = Vec::new();
    for index in 0..request.departments.len() {
        let (px, py) = pattern[slots[index % slots.len()]];
        let mut candidate = CellPoint {
            x: (cx + px * rx / 3 + rng.signed(1)).clamp(2, i16::try_from(width).unwrap() - 3)
                as u16,
            y: (cy + py * ry / 3 + rng.signed(1)).clamp(2, i16::try_from(height).unwrap() - 3)
                as u16,
        };
        if !silhouette.contains(&candidate)
            || maintenance.contains(&candidate)
            || centers
                .iter()
                .any(|other| cell_distance(*other, candidate) < 4)
        {
            candidate = silhouette
                .iter()
                .copied()
                .filter(|point| !maintenance.contains(point))
                .filter(|point| {
                    centers
                        .iter()
                        .all(|other| cell_distance(*other, *point) >= 4)
                })
                .max_by_key(|point| {
                    centers
                        .iter()
                        .map(|other| cell_distance(*other, *point))
                        .min()
                        .unwrap_or(u16::MAX)
                })
                .ok_or_else(|| LayoutError("cannot place separated department centers".into()))?;
        }
        centers.push(candidate);
    }
    Ok(centers)
}

fn frontage_toward_center(point: CellPoint, width: u16, height: u16) -> CellPoint {
    let cx = width / 2;
    let cy = height / 2;
    let mut result = point;
    for _ in 0..2 {
        let dx = i32::from(cx) - i32::from(result.x);
        let dy = i32::from(cy) - i32::from(result.y);
        if dx.abs() >= dy.abs() && dx != 0 {
            result.x = (i32::from(result.x) + dx.signum()) as u16;
        } else if dy != 0 {
            result.y = (i32::from(result.y) + dy.signum()) as u16;
        }
    }
    result
}

fn minimum_spanning_tree(points: &[CellPoint], rng: &mut Rng) -> Vec<(usize, usize)> {
    let mut reached = BTreeSet::from([0usize]);
    let mut edges = Vec::new();
    while reached.len() < points.len() {
        let mut choices = Vec::new();
        for &left in &reached {
            for right in 0..points.len() {
                if !reached.contains(&right) {
                    choices.push((
                        cell_distance(points[left], points[right]),
                        rng.next(),
                        left,
                        right,
                    ));
                }
            }
        }
        choices.sort();
        let (_, _, left, right) = choices[0];
        reached.insert(right);
        edges.push((left, right));
    }
    edges
}

fn carve_logical_segment(
    output: &mut BTreeSet<CellPoint>,
    from: CellPoint,
    to: CellPoint,
    silhouette: &BTreeSet<CellPoint>,
    maintenance: &BTreeSet<CellPoint>,
) {
    let mut cursor = from;
    loop {
        if silhouette.contains(&cursor) && !maintenance.contains(&cursor) {
            output.insert(cursor);
        }
        if cursor == to {
            break;
        }
        if cursor.x != to.x {
            cursor.x =
                (i32::from(cursor.x) + (i32::from(to.x) - i32::from(cursor.x)).signum()) as u16;
        } else {
            cursor.y =
                (i32::from(cursor.y) + (i32::from(to.y) - i32::from(cursor.y)).signum()) as u16;
        }
    }
}

fn grow_department_claims(
    request: &LayoutRequest,
    plan: &mut LogicalPlan,
    silhouette: &BTreeSet<CellPoint>,
    centers: &[CellPoint],
    public: &BTreeSet<CellPoint>,
    _rng: &mut Rng,
) -> Result<(), LayoutError> {
    let mut owner = BTreeMap::new();
    for (index, center) in centers.iter().copied().enumerate() {
        if public.contains(&center) || plan.get(center) == Space::Maintenance {
            return Err(LayoutError(format!(
                "department center {index} intersects circulation"
            )));
        }
        owner.insert(center, index);
    }
    let mut claimable: BTreeSet<_> = silhouette
        .iter()
        .copied()
        .filter(|point| !public.contains(point) && plan.get(*point) != Space::Maintenance)
        .collect();
    for component in connected_components(&claimable, plan.width, plan.height) {
        if centers.iter().any(|center| component.contains(center)) {
            continue;
        }
        for point in component {
            claimable.remove(&point);
            return Err(LayoutError(format!(
                "department region containing {point:?} has no center"
            )));
        }
    }
    let mut frontier: VecDeque<_> = centers
        .iter()
        .copied()
        .enumerate()
        .map(|(index, point)| (point, index))
        .collect();
    while let Some((point, department_index)) = frontier.pop_front() {
        let mut neighbors: Vec<_> = cardinal_cells(point, plan.width, plan.height)
            .into_iter()
            .filter(|neighbor| claimable.contains(neighbor) && !owner.contains_key(neighbor))
            .collect();
        neighbors.sort_by_key(|point| {
            hash_cell(request.settings.seed ^ department_index as u64, *point)
        });
        for neighbor in neighbors {
            owner.insert(neighbor, department_index);
            frontier.push_back((neighbor, department_index));
        }
    }
    if let Some(unclaimed) = claimable.iter().find(|point| !owner.contains_key(point)) {
        return Err(LayoutError(format!(
            "claimable cell {unclaimed:?} was not reached by multi-source growth"
        )));
    }
    for (point, department_index) in owner {
        plan.set(
            point,
            Space::Common(request.departments[department_index].id),
        );
    }
    rebalance_department_claims(plan, request, centers)?;
    Ok(())
}

fn rebalance_department_claims(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
    centers: &[CellPoint],
) -> Result<(), LayoutError> {
    for (department_index, department) in request.departments.iter().enumerate() {
        loop {
            let owned: BTreeSet<_> = plan
                .points()
                .filter(|point| plan.get(*point).department() == Some(department.id))
                .collect();
            if owned.len() >= 16 {
                break;
            }
            let mut candidates = Vec::new();
            for target_neighbor in &owned {
                for candidate in plan.neighbors(*target_neighbor) {
                    let Some(donor_id) = plan.get(candidate).department() else {
                        continue;
                    };
                    if donor_id == department.id {
                        continue;
                    }
                    let donor_remaining: BTreeSet<_> = plan
                        .points()
                        .filter(|point| {
                            *point != candidate && plan.get(*point).department() == Some(donor_id)
                        })
                        .collect();
                    if donor_remaining.len() < 16
                        || !cells_connected(&donor_remaining, plan.width, plan.height)
                    {
                        continue;
                    }
                    candidates.push(candidate);
                }
            }
            candidates.sort_by_key(|point| {
                (
                    cell_distance(*point, centers[department_index]),
                    hash_cell(request.settings.seed ^ u64::from(department.id), *point),
                    *point,
                )
            });
            let Some(candidate) = candidates.into_iter().next() else {
                return Err(LayoutError(format!(
                    "cannot rebalance a connected minimum claim for department {}",
                    department.id
                )));
            };
            plan.set(candidate, Space::Common(department.id));
        }
    }
    Ok(())
}

fn insert_internal_maintenance(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
) -> Result<(), LayoutError> {
    let snapshot = plan.cells.clone();
    let get = |point: CellPoint| {
        snapshot[usize::from(point.y) * usize::from(plan.width) + usize::from(point.x)]
    };
    let mut raw = BTreeSet::new();
    for point in plan.points() {
        let Space::Common(owner) = get(point) else {
            continue;
        };
        let smaller_neighbor = plan
            .neighbors(point)
            .filter_map(|neighbor| get(neighbor).department())
            .any(|neighbor_owner| neighbor_owner < owner);
        if smaller_neighbor {
            raw.insert(point);
        }
    }
    // Every department-to-department edge is maintenance unless public circulation
    // already separates the departments.  Keeping corners here is essential: thinning
    // this set to straight runs creates gaps at turns and leaves isolated boundary strips.
    let mut candidates: Vec<_> = raw.into_iter().collect();
    candidates.sort_by_key(|point| hash_cell(request.settings.seed ^ 0x8ed1, *point));
    for point in candidates {
        let Some(owner) = plan.get(point).department() else {
            continue;
        };
        let remaining: BTreeSet<_> = plan
            .points()
            .filter(|candidate| {
                *candidate != point && plan.get(*candidate).department() == Some(owner)
            })
            .collect();
        if remaining.len() >= 16 && cells_connected(&remaining, plan.width, plan.height) {
            plan.set(point, Space::Maintenance);
        }
    }
    let mut blocked_connectors: BTreeSet<CellPoint> = BTreeSet::new();
    loop {
        let maintenance: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Maintenance)
            .collect();
        let components = connected_components(&maintenance, plan.width, plan.height);
        if components.len() <= 1 {
            break;
        }
        let root = components
            .iter()
            .max_by_key(|component| {
                component
                    .iter()
                    .filter(|point| {
                        plan.neighbors(**point)
                            .any(|neighbor| plan.get(neighbor) == Space::Exterior)
                    })
                    .count()
            })
            .cloned()
            .ok_or_else(|| LayoutError("maintenance network has no exterior loop".into()))?;
        let source = components
            .iter()
            .filter(|component| **component != root)
            .min_by_key(|component| {
                component
                    .iter()
                    .flat_map(|left| root.iter().map(move |right| cell_distance(*left, *right)))
                    .min()
                    .unwrap_or(u16::MAX)
            })
            .cloned()
            .ok_or_else(|| LayoutError("maintenance connector has no source".into()))?;
        let mut allowed = maintenance.clone();
        for point in plan.points() {
            let adjacent_owners: BTreeSet<_> = plan
                .neighbors(point)
                .filter_map(|neighbor| plan.get(neighbor).department())
                .collect();
            let public_crossing = plan.get(point) == Space::Public
                && adjacent_owners.iter().all(|owner| {
                    plan.points().any(|department_cell| {
                        plan.get(department_cell).department() == Some(*owner)
                            && plan.neighbors(department_cell).any(|neighbor| {
                                neighbor != point && plan.get(neighbor) == Space::Public
                            })
                    })
                });
            if (plan.get(point).department().is_some() || public_crossing)
                && !blocked_connectors.contains(&point)
            {
                allowed.insert(point);
            }
        }
        let path = shortest_path_between_sets(&source, &root, &allowed, plan.width, plan.height)
            .ok_or_else(|| {
                LayoutError("cannot connect maintenance without severing a department".into())
            })?;
        let before = maintenance.len();
        for point in path {
            if plan.get(point) == Space::Public {
                plan.set(point, Space::Maintenance);
                continue;
            }
            let Some(owner) = plan.get(point).department() else {
                continue;
            };
            let remaining: BTreeSet<_> = plan
                .points()
                .filter(|candidate| {
                    *candidate != point && plan.get(*candidate).department() == Some(owner)
                })
                .collect();
            if remaining.len() >= 16 && cells_connected(&remaining, plan.width, plan.height) {
                plan.set(point, Space::Maintenance);
            } else {
                blocked_connectors.insert(point);
            }
        }
        let after = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Maintenance)
            .count();
        if after == before && blocked_connectors.is_empty() {
            return Err(LayoutError("maintenance connector made no progress".into()));
        }
    }
    // A department enclosed by public circulation still needs a direct service
    // boundary. Extend the connected maintenance network through the shortest
    // non-exterior route, while preserving both the public hall and department.
    for department in &request.departments {
        if !boundary_edges(plan, Space::Common(department.id), Space::Maintenance).is_empty() {
            continue;
        }
        let maintenance: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Maintenance)
            .collect();
        let department_cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .collect();
        let public_cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Public)
            .collect();
        let safe_public: BTreeSet<_> = public_cells
            .iter()
            .copied()
            .filter(|point| {
                let remaining: BTreeSet<_> = public_cells
                    .iter()
                    .copied()
                    .filter(|candidate| candidate != point)
                    .collect();
                remaining.is_empty() || cells_connected(&remaining, plan.width, plan.height)
            })
            .collect();
        let safe_department_cells: BTreeSet<_> = plan
            .points()
            .filter(|point| {
                let Some(owner) = plan.get(*point).department() else {
                    return false;
                };
                let remaining: BTreeSet<_> = plan
                    .points()
                    .filter(|candidate| {
                        *candidate != *point && plan.get(*candidate).department() == Some(owner)
                    })
                    .collect();
                remaining.len() >= 16 && cells_connected(&remaining, plan.width, plan.height)
            })
            .collect();
        let allowed: BTreeSet<_> = plan
            .points()
            .filter(|point| {
                plan.get(*point) == Space::Maintenance
                    || safe_public.contains(point)
                    || safe_department_cells.contains(point)
            })
            .collect();
        let Some(path) = shortest_path_between_sets(
            &maintenance,
            &department_cells,
            &allowed,
            plan.width,
            plan.height,
        ) else {
            // If every public boundary tile is an articulation point, move the
            // hall one cell into the department and reuse its former tile as
            // the service spur. This preserves both networks instead of
            // accepting an inaccessible department or rerolling the seed.
            let mut bridged = false;
            for (department_point, public_point) in
                boundary_edges(plan, Space::Common(department.id), Space::Public)
            {
                let public_neighbors: BTreeSet<_> = plan
                    .neighbors(public_point)
                    .filter(|neighbor| public_cells.contains(neighbor))
                    .collect();
                if public_neighbors.len() < 2 {
                    continue;
                }
                let first = BTreeSet::from([*public_neighbors.iter().next().unwrap()]);
                let last = BTreeSet::from([*public_neighbors.iter().next_back().unwrap()]);
                let mut detour_allowed = public_cells.clone();
                detour_allowed.remove(&public_point);
                detour_allowed.extend(department_cells.iter().copied());
                let Some(detour) = shortest_path_between_sets(
                    &first,
                    &last,
                    &detour_allowed,
                    plan.width,
                    plan.height,
                ) else {
                    continue;
                };
                let claimed: BTreeSet<_> = detour
                    .iter()
                    .copied()
                    .filter(|point| department_cells.contains(point))
                    .collect();
                if !claimed.contains(&department_point) {
                    continue;
                }
                let remaining_department: BTreeSet<_> =
                    department_cells.difference(&claimed).copied().collect();
                if remaining_department.len() < 16
                    || !cells_connected(&remaining_department, plan.width, plan.height)
                {
                    continue;
                }
                let mut revised_public = public_cells.clone();
                revised_public.remove(&public_point);
                revised_public.extend(claimed.iter().copied());
                if !cells_connected(&revised_public, plan.width, plan.height) {
                    continue;
                }
                for point in claimed {
                    plan.set(point, Space::Public);
                }
                plan.set(public_point, Space::Maintenance);
                bridged = true;
                break;
            }
            if !bridged {
                continue;
            }
            continue;
        };
        for point in path
            .into_iter()
            .skip(1)
            .rev()
            .skip(1)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
        {
            match plan.get(point) {
                Space::Public => {
                    plan.set(point, Space::Maintenance);
                }
                Space::Common(owner) => {
                    let remaining: BTreeSet<_> = plan
                        .points()
                        .filter(|candidate| {
                            *candidate != point && plan.get(*candidate).department() == Some(owner)
                        })
                        .collect();
                    if remaining.len() < 16 || !cells_connected(&remaining, plan.width, plan.height)
                    {
                        return Err(LayoutError(format!(
                            "maintenance spur would sever department {}",
                            owner
                        )));
                    }
                    plan.set(point, Space::Maintenance);
                }
                _ => {}
            }
        }
    }

    // Pull short service fingers into larger departments.  These remain part
    // of the single maintenance network, but create useful internal service
    // frontage instead of confining every access door to the outer perimeter.
    // Each claimed cell is checked independently so a spur can never sever the
    // department it enters.
    for department in &request.departments {
        let mut department_cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .collect();
        if department_cells.len() < 32 {
            continue;
        }
        let center = nearest_in_set(plan.department_centers[&department.id], &department_cells)
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {} has no service center",
                    department.id
                ))
            })?;
        let mut anchors: Vec<_> = department_cells
            .iter()
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| plan.get(neighbor) == Space::Maintenance)
            })
            .collect();
        anchors.sort_by_key(|point| {
            (
                hash_cell(
                    request.settings.seed ^ 0x7365_7276_6963_65 ^ u64::from(department.id),
                    *point,
                ),
                *point,
            )
        });
        let mut selected = Vec::new();
        for anchor in anchors {
            if selected.len() >= 2
                || selected
                    .iter()
                    .any(|chosen| cell_distance(*chosen, anchor) < 6)
            {
                continue;
            }
            let Some(path) = ordered_shortest_path_in_set(
                anchor,
                center,
                &department_cells,
                plan.width,
                plan.height,
            ) else {
                continue;
            };
            let depth = 2 + usize::try_from(
                hash_cell(request.settings.seed ^ 0x6669_6e67_6572, anchor) % 3,
            )
            .unwrap_or(0);
            let mut carved_any = false;
            for point in path.into_iter().take(depth) {
                let mut remaining = department_cells.clone();
                remaining.remove(&point);
                if remaining.len() < 16 || !cells_connected(&remaining, plan.width, plan.height) {
                    break;
                }
                plan.set(point, Space::Maintenance);
                department_cells = remaining;
                carved_any = true;
            }
            if carved_any {
                selected.push(anchor);
            }
        }
    }
    for department in &request.departments {
        let cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .collect();
        if cells.len() < 16 || !cells_connected(&cells, plan.width, plan.height) {
            return Err(LayoutError(format!(
                "maintenance partition left department {} with invalid ownership",
                department.id
            )));
        }
    }
    let maintenance: BTreeSet<_> = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Maintenance)
        .collect();
    if !cells_connected(&maintenance, plan.width, plan.height) {
        return Err(LayoutError(
            "department maintenance buffers do not join the exterior loop".into(),
        ));
    }
    Ok(())
}

fn assign_department_common_and_rooms(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
    rng: &mut Rng,
) -> Result<(), LayoutError> {
    let mut next_room_id = 1u16;
    for department in &request.departments {
        let department_cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Common(department.id))
            .collect();
        let frontage = department_cells
            .iter()
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| plan.get(neighbor) == Space::Public)
            })
            .min_by_key(|point| cell_distance(*point, plan.department_centers[&department.id]))
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {} does not border its public hall",
                    department.id
                ))
            })?;
        let center = nearest_in_set(plan.department_centers[&department.id], &department_cells)
            .ok_or_else(|| {
                LayoutError(format!("department {} has no owned center", department.id))
            })?;
        let mut common =
            shortest_path_in_set(frontage, center, &department_cells, plan.width, plan.height)
                .ok_or_else(|| {
                    LayoutError(format!(
                        "department {} frontage cannot reach its center",
                        department.id
                    ))
                })?;

        let maintenance_components =
            adjacent_components(&department_cells, Space::Maintenance, plan);
        for component in maintenance_components {
            let access = department_cells
                .iter()
                .copied()
                .filter(|point| {
                    plan.neighbors(*point)
                        .any(|neighbor| component.contains(&neighbor))
                })
                .min_by_key(|point| cell_distance(*point, center))
                .ok_or_else(|| {
                    LayoutError("maintenance component lost its department boundary".into())
                })?;
            let path =
                shortest_path_in_set(center, access, &department_cells, plan.width, plan.height)
                    .ok_or_else(|| {
                        LayoutError(format!(
                            "department {} cannot reach maintenance",
                            department.id
                        ))
                    })?;
            common.extend(path);
        }
        common.insert(frontage);
        common.insert(center);
        let required_count: usize = department
            .room_types
            .iter()
            .map(|room| usize::from(room.min_count))
            .sum();
        let desired_count = required_count;
        // Grow a real departmental hallway tree before assigning rooms.  A frontage-only
        // strip can expose enough cells to satisfy the door count while leaving the whole
        // department as a handful of oversized rooms.  The coverage constraint forces
        // circulation into the department interior; the frontage constraint gives every
        // planned room a distinct place to meet that circulation.
        for _ in 0..department_cells.len() {
            let frontage_count = department_cells
                .difference(&common)
                .filter(|point| {
                    plan.neighbors(**point)
                        .any(|neighbor| common.contains(&neighbor))
                })
                .count();
            let farthest = department_cells
                .difference(&common)
                .copied()
                .max_by_key(|point| {
                    common
                        .iter()
                        .map(|hall| cell_distance(*hall, *point))
                        .min()
                        .unwrap_or(0)
                });
            let maximum_depth = farthest
                .map(|point| {
                    common
                        .iter()
                        .map(|hall| cell_distance(*hall, point))
                        .min()
                        .unwrap_or(0)
                })
                .unwrap_or(0);
            if frontage_count >= desired_count && maximum_depth <= 3 {
                break;
            }
            let target = farthest.ok_or_else(|| {
                LayoutError(format!(
                    "department {} has no floor left for required rooms",
                    department.id
                ))
            })?;
            let branch_origin = common
                .iter()
                .copied()
                .min_by_key(|hall| cell_distance(*hall, target))
                .ok_or_else(|| LayoutError("department hallway has no origin".into()))?;
            let mut branch = shortest_path_in_set(
                branch_origin,
                target,
                &department_cells,
                plan.width,
                plan.height,
            )
            .ok_or_else(|| LayoutError("cannot extend department common floor".into()))?;
            branch.remove(&target);
            common.extend(branch);
        }

        // Every non-circulation lobe becomes a room. Absorbing small lobes into
        // common floor creates enormous unfurnished departmental voids which are
        // neither corridors nor purposeful rooms.
        // Each independently seeded room needs its own frontage cell. A large,
        // shallow lobe can be close to a hallway everywhere while exposing only one
        // usable frontage, which forces the entire lobe into one oversized room.
        // Extend circulation fingers until every lobe exposes enough distinct
        // frontages for its authored maximum capacity.
        let maximum_room_area = department
            .room_types
            .iter()
            .map(|room| usize::from(room.max_width) * usize::from(room.max_height))
            .max()
            .unwrap_or(1);
        for _ in 0..department_cells.len() {
            let components = connected_components(
                &department_cells.difference(&common).copied().collect(),
                plan.width,
                plan.height,
            );
            let deficient = components.into_iter().find(|component| {
                let required_frontages = projected_room_tile_area(component)
                    .saturating_mul(5)
                    .div_ceil(maximum_room_area.saturating_mul(3));
                let available_frontages = component
                    .iter()
                    .filter(|point| {
                        plan.neighbors(**point)
                            .any(|neighbor| common.contains(&neighbor))
                    })
                    .count();
                available_frontages < required_frontages
            });
            let Some(component) = deficient else {
                break;
            };
            let target = component
                .iter()
                .copied()
                .max_by_key(|point| {
                    common
                        .iter()
                        .map(|hall| cell_distance(*hall, *point))
                        .min()
                        .unwrap_or(0)
                })
                .ok_or_else(|| LayoutError("deficient room lobe is empty".into()))?;
            let hall_anchor = common
                .iter()
                .copied()
                .min_by_key(|hall| cell_distance(*hall, target))
                .ok_or_else(|| LayoutError("department circulation has no finger origin".into()))?;
            let mut finger = shortest_path_in_set(
                hall_anchor,
                target,
                &department_cells,
                plan.width,
                plan.height,
            )
            .ok_or_else(|| LayoutError("cannot extend room-frontage circulation".into()))?;
            finger.remove(&target);
            let old_len = common.len();
            common.extend(finger);
            if common.len() == old_len {
                return Err(LayoutError(
                    "room-frontage circulation could not make progress".into(),
                ));
            }
        }
        let minimum_room_area = department
            .room_types
            .iter()
            .filter(|room| room.max_count > 0)
            .map(|room| room.content_area as usize)
            .min()
            .unwrap_or(1);
        let undersized_lobes = connected_components(
            &department_cells.difference(&common).copied().collect(),
            plan.width,
            plan.height,
        )
        .into_iter()
        .filter(|component| projected_room_tile_area(component) < minimum_room_area)
        .collect::<Vec<_>>();
        for lobe in undersized_lobes {
            common.extend(lobe);
        }
        let mut components = connected_components(
            &department_cells.difference(&common).copied().collect(),
            plan.width,
            plan.height,
        );
        components.sort_by_key(|component| Reverse(component.len()));
        let required_room_slots: usize = components
            .iter()
            .map(|component| {
                projected_room_tile_area(component)
                    .saturating_mul(5)
                    .div_ceil(maximum_room_area.saturating_mul(3))
            })
            .sum();
        let room_floor_area = components.iter().map(BTreeSet::len).sum();
        let mut instances = room_instances(
            department,
            room_floor_area,
            components.len().max(required_room_slots),
        );
        if instances.len() < components.len() {
            return Err(LayoutError(format!(
                "department {} has more room lobes than permitted room instances",
                department.id
            )));
        }
        if instances.is_empty() {
            return Err(LayoutError(format!(
                "department {} has no room instances",
                department.id
            )));
        }

        let candidates: Vec<_> = department_cells
            .difference(&common)
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| common.contains(&neighbor))
            })
            .collect();
        if candidates.len() < required_count {
            return Err(LayoutError(format!(
                "department {} has {} room frontages for {required_count} required rooms",
                department.id,
                candidates.len()
            )));
        }
        instances.truncate(candidates.len().max(components.len()));
        let mut seeds = choose_room_seeds(&components, &candidates, instances.len(), rng)?;
        let (mut assignments, residual) = grow_rooms(
            &department_cells.difference(&common).copied().collect(),
            &seeds,
            &instances,
            plan.width,
            plan.height,
            rng,
        )?;
        if !residual.is_empty() {
            for component in connected_components(&residual, plan.width, plan.height) {
                connect_residual_circulation(
                    component,
                    &mut common,
                    &mut assignments,
                    &seeds,
                    plan.width,
                    plan.height,
                )?;
            }
        }
        while assignments.len() > required_count {
            let Some(shape_index) = assignments
                .iter()
                .position(|shape| projected_room_tile_area(shape) < minimum_room_area)
            else {
                break;
            };
            let mut counts = BTreeMap::new();
            for room in &instances {
                *counts.entry(room.id).or_insert(0usize) += 1;
            }
            let optional_index = instances.iter().position(|room| {
                counts.get(&room.id).copied().unwrap_or(0) > usize::from(room.min_count)
            });
            let Some(optional_index) = optional_index else {
                break;
            };
            common.extend(assignments.remove(shape_index));
            seeds.remove(shape_index);
            instances.remove(optional_index);
        }
        rebalance_shapes_for_programs(
            &mut assignments,
            &instances,
            &seeds,
            &mut common,
            plan.width,
            plan.height,
        );
        let matched_types = match_room_types_to_shapes(&instances, &assignments).ok_or_else(|| {
            let shapes = assignments
                .iter()
                .map(|shape| {
                    let (width, height) = projected_room_dimensions(shape);
                    format!("{}:{}x{}", projected_room_tile_area(shape), width, height)
                })
                .collect::<Vec<_>>()
                .join(",");
            let programs = instances
                .iter()
                .map(|room| {
                    format!(
                        "{}:{}..{}",
                        room.name,
                        room.content_area,
                        u32::from(room.max_width) * u32::from(room.max_height)
                    )
                })
                .collect::<Vec<_>>()
                .join(",");
            LayoutError(format!(
                "department {} could not match its authored room programs [{programs}] to generated geometry ({shapes})",
                department.id,
            ))
        })?;
        compact_department_circulation(
            plan,
            department.id,
            &mut common,
            &mut assignments,
            &matched_types,
        );
        for (room_type, cells) in matched_types.into_iter().zip(assignments) {
            if cells.is_empty() {
                return Err(LayoutError(format!(
                    "department {} produced an empty room",
                    department.id
                )));
            }
            let room_id = next_room_id;
            next_room_id = next_room_id
                .checked_add(1)
                .ok_or_else(|| LayoutError("station contains too many rooms".into()))?;
            for point in &cells {
                plan.set(
                    *point,
                    Space::Room {
                        department: department.id,
                        room: room_id,
                    },
                );
            }
            plan.rooms.push(RoomPlan {
                id: room_id,
                department: department.id,
                room_type: room_type.id,
            });
        }
    }
    Ok(())
}

fn compact_department_circulation(
    plan: &LogicalPlan,
    department: u16,
    common: &mut BTreeSet<CellPoint>,
    rooms: &mut [BTreeSet<CellPoint>],
    room_types: &[&RoomType],
) {
    loop {
        let mut changed = false;
        let candidates: Vec<_> = common.iter().copied().collect();
        for point in candidates {
            // These cells are explicit interfaces and must remain circulation.
            if plan
                .neighbors(point)
                .any(|neighbor| matches!(plan.get(neighbor), Space::Public | Space::Maintenance))
            {
                continue;
            }
            let adjacent_rooms: Vec<_> = rooms
                .iter()
                .enumerate()
                .filter(|(_, room)| {
                    plan.neighbors(point)
                        .any(|neighbor| room.contains(&neighbor))
                })
                .map(|(index, _)| index)
                .collect();
            let mut reduced_common = common.clone();
            reduced_common.remove(&point);
            if reduced_common.is_empty()
                || !cells_connected(&reduced_common, plan.width, plan.height)
            {
                continue;
            }
            let Some(recipient) = adjacent_rooms.into_iter().find(|index| {
                let mut enlarged = rooms[*index].clone();
                enlarged.insert(point);
                if !room_shape_fits(room_types[*index], &enlarged) {
                    return false;
                }
                rooms.iter().enumerate().all(|(room_index, room)| {
                    let candidate = if room_index == *index {
                        &enlarged
                    } else {
                        room
                    };
                    candidate.iter().any(|room_point| {
                        plan.neighbors(*room_point)
                            .any(|neighbor| reduced_common.contains(&neighbor))
                    })
                })
            }) else {
                continue;
            };
            common.remove(&point);
            rooms[recipient].insert(point);
            changed = true;
        }
        if !changed {
            break;
        }
    }

    debug_assert!(
        common
            .iter()
            .all(|point| { plan.get(*point).department() == Some(department) })
    );
}

fn connect_residual_circulation(
    component: BTreeSet<CellPoint>,
    common: &mut BTreeSet<CellPoint>,
    assignments: &mut [BTreeSet<CellPoint>],
    seeds: &[CellPoint],
    width: u16,
    height: u16,
) -> Result<(), LayoutError> {
    let mut circulation = component;
    while !circulation.iter().any(|point| {
        cardinal_cells(*point, width, height)
            .into_iter()
            .any(|neighbor| common.contains(&neighbor))
    }) {
        let mut candidates = Vec::new();
        for (room_index, room) in assignments.iter().enumerate() {
            if room.len() <= 1 {
                continue;
            }
            for point in room.iter().copied() {
                if point == seeds[room_index]
                    || !cardinal_cells(point, width, height)
                        .into_iter()
                        .any(|neighbor| circulation.contains(&neighbor))
                {
                    continue;
                }
                let mut reduced = room.clone();
                reduced.remove(&point);
                if connected_components(&reduced, width, height).len() != 1 {
                    continue;
                }
                let distance = common
                    .iter()
                    .map(|target| cell_distance(point, *target))
                    .min()
                    .unwrap_or(u16::MAX);
                candidates.push((distance, room_index, point));
            }
        }
        candidates.sort_unstable();
        let Some((_, room_index, point)) = candidates.first().copied() else {
            return Err(LayoutError(
                "cannot connect residual circulation without disconnecting a room".into(),
            ));
        };
        assignments[room_index].remove(&point);
        circulation.insert(point);
    }
    common.extend(circulation);
    Ok(())
}

fn rebalance_shapes_for_programs(
    shapes: &mut [BTreeSet<CellPoint>],
    room_types: &[&RoomType],
    seeds: &[CellPoint],
    circulation: &mut BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) {
    let minimum_area = room_types
        .iter()
        .map(|room| room.content_area as usize)
        .min()
        .unwrap_or(1);
    let maximum_area = room_types
        .iter()
        .map(|room| usize::from(room.max_width) * usize::from(room.max_height))
        .max()
        .unwrap_or(usize::MAX);
    for _ in 0..shapes.len().saturating_mul(32) {
        if match_room_types_to_shapes(room_types, shapes).is_some() {
            return;
        }
        let mut capacity_order = room_types
            .iter()
            .map(|room| usize::from(room.max_width) * usize::from(room.max_height))
            .collect::<Vec<_>>();
        capacity_order.sort_by_key(|capacity| Reverse(*capacity));
        let mut area_order = (0..shapes.len()).collect::<Vec<_>>();
        area_order.sort_by_key(|index| Reverse(projected_room_tile_area(&shapes[*index])));
        let oversized = area_order
            .iter()
            .enumerate()
            .filter(|(rank, index)| {
                projected_room_tile_area(&shapes[**index]) > capacity_order[*rank]
            })
            .max_by_key(|(rank, index)| {
                projected_room_tile_area(&shapes[**index]) - capacity_order[*rank]
            })
            .map(|(_, index)| *index);
        if let Some(donor) = oversized {
            let mut transfer = None;
            for cell in shapes[donor].iter().copied() {
                if cell == seeds[donor] {
                    continue;
                }
                let mut reduced = shapes[donor].clone();
                reduced.remove(&cell);
                if connected_components(&reduced, width, height).len() != 1
                    || projected_room_tile_area(&reduced) < minimum_area
                {
                    continue;
                }
                for recipient in 0..shapes.len() {
                    if recipient == donor
                        || !cardinal_cells(cell, width, height)
                            .into_iter()
                            .any(|neighbor| shapes[recipient].contains(&neighbor))
                    {
                        continue;
                    }
                    let mut expanded = shapes[recipient].clone();
                    expanded.insert(cell);
                    if projected_room_tile_area(&expanded) <= maximum_area {
                        transfer = Some((recipient, cell));
                        break;
                    }
                }
                if transfer.is_some() {
                    break;
                }
            }
            if let Some((recipient, cell)) = transfer {
                shapes[donor].remove(&cell);
                shapes[recipient].insert(cell);
                continue;
            }
            let circulation_cell = shapes[donor].iter().copied().find(|cell| {
                if *cell == seeds[donor]
                    || !cardinal_cells(*cell, width, height)
                        .into_iter()
                        .any(|neighbor| circulation.contains(&neighbor))
                {
                    return false;
                }
                let mut reduced = shapes[donor].clone();
                reduced.remove(cell);
                connected_components(&reduced, width, height).len() == 1
                    && projected_room_tile_area(&reduced) >= minimum_area
            });
            let Some(cell) = circulation_cell else {
                return;
            };
            shapes[donor].remove(&cell);
            circulation.insert(cell);
            continue;
        }
        let mut shape_order: Vec<_> = (0..shapes.len()).collect();
        shape_order.sort_by_key(|index| Reverse(projected_room_tile_area(&shapes[*index])));
        let mut demands = room_types
            .iter()
            .map(|room| room.content_area as usize)
            .collect::<Vec<_>>();
        demands.sort_by_key(|area| Reverse(*area));
        let Some(recipient) = shape_order.iter().enumerate().find_map(|(rank, index)| {
            (projected_room_tile_area(&shapes[*index]) < demands[rank]).then_some(*index)
        }) else {
            return;
        };
        let mut transfer = None;
        for donor in shape_order {
            if donor == recipient {
                continue;
            }
            for cell in shapes[donor].iter().copied() {
                if cell == seeds[donor]
                    || !cardinal_cells(cell, width, height)
                        .into_iter()
                        .any(|neighbor| shapes[recipient].contains(&neighbor))
                {
                    continue;
                }
                let mut reduced = shapes[donor].clone();
                reduced.remove(&cell);
                if connected_components(&reduced, width, height).len() == 1
                    && projected_room_tile_area(&reduced) >= minimum_area
                {
                    transfer = Some((donor, cell));
                    break;
                }
            }
            if transfer.is_some() {
                break;
            }
        }
        let Some((donor, cell)) = transfer else {
            return;
        };
        shapes[donor].remove(&cell);
        shapes[recipient].insert(cell);
    }
}

fn room_instances<'a>(
    department: &'a super::model::DepartmentRequest,
    area: usize,
    minimum_components: usize,
) -> Vec<&'a RoomType> {
    let mut instances = Vec::new();
    for room_type in &department.room_types {
        for _ in 0..room_type.min_count {
            instances.push(room_type);
        }
    }
    let catalog_maximum = department
        .room_types
        .iter()
        .map(|room| usize::from(room.max_count))
        .sum::<usize>();
    let mut counts: BTreeMap<u16, u16> = BTreeMap::new();
    for room in &instances {
        *counts.entry(room.id).or_default() += 1;
    }
    let maximum = catalog_maximum.min(instances.len().saturating_add(4).max(minimum_components));
    // Room programs describe usable floor, while department territory must also
    // pay for its local hallway and partition walls. Allocate no more than two
    // thirds of the territory to declared room minima; growth distributes the
    // remaining floor without creating undersized token rooms.
    let content_budget = area
        .saturating_mul(usize::from(INTERIOR).pow(2) + usize::from(INTERIOR))
        .saturating_mul(2)
        / 3;
    let mut committed_content: usize = instances
        .iter()
        .map(|room| room.ideal_area.max(room.content_area).max(1) as usize)
        .sum();
    let mut committed_capacity: usize = instances
        .iter()
        .map(|room| room_logical_capacity(room))
        .sum();
    while instances.len() < maximum.max(instances.len()) {
        if instances.len() >= minimum_components
            && (committed_capacity >= area || committed_content >= content_budget)
        {
            break;
        }
        let Some(room) = department
            .room_types
            .iter()
            .filter(|room| counts.get(&room.id).copied().unwrap_or(0) < room.max_count)
            .filter(|room| {
                instances.len() < minimum_components
                    || committed_capacity < area
                    || committed_content + room.ideal_area.max(room.content_area).max(1) as usize
                        <= content_budget
            })
            .min_by_key(|room| {
                (
                    counts.get(&room.id).copied().unwrap_or(0),
                    Reverse(u32::from(room.max_width) * u32::from(room.max_height)),
                    room.id,
                )
            })
        else {
            break;
        };
        *counts.entry(room.id).or_default() += 1;
        committed_content += room.ideal_area.max(room.content_area).max(1) as usize;
        committed_capacity += room_logical_capacity(room);
        instances.push(room);
    }
    instances.sort_by_key(|room| Reverse(room.ideal_area));
    instances
}

fn match_room_types_to_shapes<'a>(
    room_types: &[&'a RoomType],
    shapes: &[BTreeSet<CellPoint>],
) -> Option<Vec<&'a RoomType>> {
    if room_types.len() != shapes.len() {
        return None;
    }
    let mut shape_order: Vec<usize> = (0..shapes.len()).collect();
    shape_order.sort_by_key(|shape_index| {
        room_types
            .iter()
            .filter(|room| room_shape_fits(room, &shapes[*shape_index]))
            .count()
    });
    let candidates = shapes
        .iter()
        .map(|shape| {
            let mut choices = room_types
                .iter()
                .enumerate()
                .filter_map(|(index, room)| room_shape_fits(room, shape).then_some(index))
                .collect::<Vec<_>>();
            choices.sort_by_key(|index| room_shape_score(room_types[*index], shape));
            choices
        })
        .collect::<Vec<_>>();
    let mut type_to_shape = vec![None; room_types.len()];
    fn augment(
        shape_index: usize,
        candidates: &[Vec<usize>],
        type_to_shape: &mut [Option<usize>],
        visited_types: &mut [bool],
    ) -> bool {
        for &type_index in &candidates[shape_index] {
            if visited_types[type_index] {
                continue;
            }
            visited_types[type_index] = true;
            let can_claim = type_to_shape[type_index].is_none()
                || augment(
                    type_to_shape[type_index].unwrap(),
                    candidates,
                    type_to_shape,
                    visited_types,
                );
            if can_claim {
                type_to_shape[type_index] = Some(shape_index);
                return true;
            }
        }
        false
    }
    for shape_index in shape_order {
        let mut visited_types = vec![false; room_types.len()];
        if !augment(
            shape_index,
            &candidates,
            &mut type_to_shape,
            &mut visited_types,
        ) {
            return None;
        }
    }
    let mut result = vec![None; shapes.len()];
    for (type_index, shape_index) in type_to_shape.into_iter().enumerate() {
        result[shape_index?] = Some(room_types[type_index]);
    }
    Some(result.into_iter().map(Option::unwrap).collect())
}

fn choose_room_seeds(
    components: &[BTreeSet<CellPoint>],
    candidates: &[CellPoint],
    count: usize,
    rng: &mut Rng,
) -> Result<Vec<CellPoint>, LayoutError> {
    let candidate_set: BTreeSet<_> = candidates.iter().copied().collect();
    if count < components.len() {
        return Err(LayoutError(
            "room count cannot cover every department-floor component".into(),
        ));
    }
    let mut quotas = vec![1usize; components.len()];
    for _ in components.len()..count {
        let index = (0..components.len())
            .filter(|index| {
                components[*index].intersection(&candidate_set).count() > quotas[*index]
            })
            .max_by_key(|index| {
                (
                    components[*index].len() * 1024 / quotas[*index],
                    Reverse(*index),
                )
            })
            .ok_or_else(|| {
                LayoutError(
                    "department common floor has insufficient distinct room boundaries".into(),
                )
            })?;
        quotas[index] += 1;
    }
    let mut seeds = Vec::new();
    for (component, quota) in components.iter().zip(quotas) {
        let component_candidates: Vec<_> =
            component.intersection(&candidate_set).copied().collect();
        let mut component_seeds = Vec::new();
        for _ in 0..quota {
            let seed = component_candidates
                .iter()
                .copied()
                .filter(|point| !component_seeds.contains(point))
                .max_by_key(|point| {
                    (
                        component_seeds
                            .iter()
                            .map(|seed| cell_distance(*seed, *point))
                            .min()
                            .unwrap_or(u16::MAX),
                        hash_cell(rng.0 ^ component_seeds.len() as u64, *point),
                    )
                })
                .ok_or_else(|| {
                    LayoutError("not enough separated room frontages in a department lobe".into())
                })?;
            component_seeds.push(seed);
        }
        seeds.extend(component_seeds);
    }
    Ok(seeds)
}

fn grow_rooms(
    available: &BTreeSet<CellPoint>,
    seeds: &[CellPoint],
    room_types: &[&RoomType],
    width: u16,
    height: u16,
    rng: &mut Rng,
) -> Result<(Vec<BTreeSet<CellPoint>>, BTreeSet<CellPoint>), LayoutError> {
    let mut rooms: Vec<BTreeSet<_>> = seeds.iter().map(|seed| BTreeSet::from([*seed])).collect();
    let mut owner: BTreeMap<_, _> = seeds
        .iter()
        .enumerate()
        .map(|(index, seed)| (*seed, index))
        .collect();
    let mut frontiers: Vec<VecDeque<_>> =
        seeds.iter().map(|seed| VecDeque::from([*seed])).collect();
    let mut growth_iterations = 0usize;
    let maximum_growth_iterations = available
        .len()
        .saturating_mul(rooms.len().max(1))
        .saturating_mul(8);
    while owner.len() < available.len() {
        growth_iterations += 1;
        if growth_iterations > maximum_growth_iterations {
            return Err(LayoutError(format!(
                "room growth exceeded its {}-iteration structural bound with {} of {} logical cells assigned",
                maximum_growth_iterations,
                owner.len(),
                available.len()
            )));
        }
        let mut order: Vec<_> = (0..rooms.len())
            .filter(|index| {
                projected_room_tile_area(&rooms[*index])
                    < usize::from(room_types[*index].max_width)
                        * usize::from(room_types[*index].max_height)
            })
            .collect();
        order.sort_by_key(|index| {
            let target = room_types[*index]
                .ideal_area
                .max(room_types[*index].content_area)
                .max(1) as usize;
            (
                projected_room_tile_area(&rooms[*index])
                    >= room_types[*index].content_area as usize,
                projected_room_tile_area(&rooms[*index]) * 1000 / target,
                hash_cell(rng.0 ^ owner.len() as u64, seeds[*index]),
            )
        });
        let mut progressed = false;
        for index in order {
            let Some(point) = frontiers[index].pop_front() else {
                continue;
            };
            let mut options: Vec<_> = cardinal_cells(point, width, height)
                .into_iter()
                .filter(|point| {
                    if !available.contains(point) || owner.contains_key(point) {
                        return false;
                    }
                    let mut projected = rooms[index].clone();
                    projected.insert(*point);
                    projected_room_tile_area(&projected)
                        <= usize::from(room_types[index].max_width)
                            * usize::from(room_types[index].max_height)
                })
                .collect();
            options.sort_by_key(|point| {
                let same_neighbors = cardinal_cells(*point, width, height)
                    .into_iter()
                    .filter(|neighbor| owner.get(neighbor) == Some(&index))
                    .count();
                let unclaimed_neighbors = cardinal_cells(*point, width, height)
                    .into_iter()
                    .filter(|neighbor| {
                        available.contains(neighbor) && !owner.contains_key(neighbor)
                    })
                    .count();
                let mut projected = rooms[index].clone();
                projected.insert(*point);
                (
                    room_shape_score(room_types[index], &projected),
                    unclaimed_neighbors,
                    Reverse(same_neighbors),
                    cell_distance(*point, seeds[index]),
                    hash_cell(rng.0 ^ index as u64, *point),
                )
            });
            for option in options.into_iter().take(1) {
                owner.insert(option, index);
                rooms[index].insert(option);
                frontiers[index].push_back(option);
                frontiers[index].push_back(point);
                progressed = true;
            }
        }
        if !progressed {
            let candidate = available
                .iter()
                .filter(|point| !owner.contains_key(point))
                .find_map(|point| {
                    cardinal_cells(*point, width, height)
                        .into_iter()
                        .filter_map(|neighbor| owner.get(&neighbor).copied())
                        .find(|index| {
                            let mut projected = rooms[*index].clone();
                            projected.insert(*point);
                            projected_room_tile_area(&projected)
                                <= usize::from(room_types[*index].max_width)
                                    * usize::from(room_types[*index].max_height)
                        })
                        .map(|index| (*point, index))
                });
            if let Some((point, index)) = candidate {
                owner.insert(point, index);
                rooms[index].insert(point);
                frontiers[index].push_back(point);
                continue;
            }
            let mut repaired = false;
            'repair: for point in available.iter().filter(|point| !owner.contains_key(point)) {
                let donor_indices: BTreeSet<_> = cardinal_cells(*point, width, height)
                    .into_iter()
                    .filter_map(|neighbor| owner.get(&neighbor).copied())
                    .collect();
                for donor in donor_indices {
                    for donor_cell in rooms[donor].iter().copied().collect::<Vec<_>>() {
                        if donor_cell == seeds[donor] {
                            continue;
                        }
                        for recipient in cardinal_cells(donor_cell, width, height)
                            .into_iter()
                            .filter_map(|neighbor| owner.get(&neighbor).copied())
                            .filter(|recipient| *recipient != donor)
                        {
                            let mut new_donor = rooms[donor].clone();
                            new_donor.remove(&donor_cell);
                            new_donor.insert(*point);
                            if connected_components(&new_donor, width, height).len() != 1
                                || projected_room_tile_area(&new_donor)
                                    > usize::from(room_types[donor].max_width)
                                        * usize::from(room_types[donor].max_height)
                            {
                                continue;
                            }
                            let mut new_recipient = rooms[recipient].clone();
                            new_recipient.insert(donor_cell);
                            if projected_room_tile_area(&new_recipient)
                                > usize::from(room_types[recipient].max_width)
                                    * usize::from(room_types[recipient].max_height)
                            {
                                continue;
                            }
                            rooms[donor] = new_donor;
                            rooms[recipient] = new_recipient;
                            owner.insert(*point, donor);
                            owner.insert(donor_cell, recipient);
                            frontiers[donor].push_back(*point);
                            frontiers[recipient].push_back(donor_cell);
                            repaired = true;
                            break 'repair;
                        }
                    }
                }
            }
            if repaired {
                continue;
            }
            let unclaimed: BTreeSet<_> = available
                .iter()
                .copied()
                .filter(|point| !owner.contains_key(point))
                .collect();
            let mut absorbed_component = false;
            let maximum_program_area = room_types
                .iter()
                .map(|room| usize::from(room.max_width) * usize::from(room.max_height))
                .max()
                .unwrap_or(1);
            for component in connected_components(&unclaimed, width, height) {
                let recipient = (0..rooms.len())
                    .filter(|index| {
                        let touches = component.iter().any(|point| {
                            cardinal_cells(*point, width, height)
                                .into_iter()
                                .any(|neighbor| rooms[*index].contains(&neighbor))
                        });
                        touches
                    })
                    .min_by_key(|index| {
                        let mut combined = rooms[*index].clone();
                        combined.extend(component.iter().copied());
                        (
                            projected_room_tile_area(&combined) > maximum_program_area,
                            projected_room_tile_area(&combined),
                            *index,
                        )
                    });
                let Some(recipient) = recipient else {
                    continue;
                };
                for point in component {
                    owner.insert(point, recipient);
                    rooms[recipient].insert(point);
                    frontiers[recipient].push_back(point);
                }
                absorbed_component = true;
            }
            if absorbed_component {
                continue;
            }
            return Ok((rooms, unclaimed));
        }
    }
    Ok((rooms, BTreeSet::new()))
}

fn assign_portals(plan: &mut LogicalPlan, request: &LayoutRequest) -> Result<(), LayoutError> {
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
                    .find(|room_type| room_type.id == room.room_type)
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
            return Err(LayoutError(format!(
                "room {} has no common-floor boundary",
                room.id
            )));
        }

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
        let public_edge = boundary_edges(plan, Space::Common(department.id), Space::Public)
            .into_iter()
            .filter(|edge| !used_edges.contains(&normalize_edge(edge.0, edge.1)))
            .min_by_key(|(left, right)| {
                (
                    cell_distance(*left, plan.department_centers[&department.id]),
                    *right,
                )
            })
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {} has no public portal edge",
                    department.id
                ))
            })?;
        used_edges.insert(normalize_edge(public_edge.0, public_edge.1));
        plan.portals.push(Portal {
            left: public_edge.0,
            right: public_edge.1,
            department: department.id,
            room: None,
            kind: PortalKind::Public,
        });
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
    choke_candidates.sort_by_key(|(left, right)| {
        hash_cell(request.settings.seed ^ 0x6d61_696e_745f_646f, *left)
            ^ hash_cell(request.settings.seed, *right)
    });
    let choke_target = (maintenance.len() / 14).max(4);
    let mut selected_chokes: Vec<(CellPoint, CellPoint)> = Vec::new();
    for edge in choke_candidates {
        if selected_chokes.len() >= choke_target
            || selected_chokes
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

fn boundary_edges(plan: &LogicalPlan, left: Space, right: Space) -> Vec<(CellPoint, CellPoint)> {
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

fn normalize_edge(left: CellPoint, right: CellPoint) -> (CellPoint, CellPoint) {
    if left <= right {
        (left, right)
    } else {
        (right, left)
    }
}

fn rasterize(request: &LayoutRequest, plan: &LogicalPlan) -> Result<StationLayout, LayoutError> {
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
    let choke_edges: BTreeSet<_> = plan
        .portals
        .iter()
        .filter(|portal| portal.kind == PortalKind::MaintenanceChoke)
        .map(|portal| normalize_edge(portal.left, portal.right))
        .collect();

    for point in plan.points() {
        let space = plan.get(point);
        if space == Space::Exterior {
            continue;
        }
        for dy in 1..=INTERIOR {
            for dx in 1..=INTERIOR {
                tiles[index(lattice_point(point, dx, dy))] = logical_floor(space);
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
                for dy in 1..=INTERIOR {
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
                for dx in 1..=INTERIOR {
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
            if vertex_requires_post(quartet) {
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
            room_type_id: room_plan.room_type,
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

fn logical_boundary_class(left: Space, right: Space) -> TileClass {
    if left == Space::Exterior || right == Space::Exterior {
        TileClass::Structure
    } else if left.department().is_some() || right.department().is_some() {
        TileClass::Partition
    } else {
        TileClass::Structure
    }
}

fn vertex_requires_post(quartet: [Space; 4]) -> bool {
    quartet.iter().any(|space| *space != Space::Exterior)
        && !quartet.iter().all(|space| *space == quartet[0])
}

fn logical_vertex_class(quartet: [Space; 4]) -> TileClass {
    if quartet.contains(&Space::Exterior) {
        TileClass::Structure
    } else if quartet.iter().any(|space| space.department().is_some()) {
        TileClass::Partition
    } else {
        TileClass::Structure
    }
}

fn validate_raster_against_logical(
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
    for point in plan.points() {
        let space = plan.get(point);
        if space != Space::Exterior {
            for dy in 1..=INTERIOR {
                for dx in 1..=INTERIOR {
                    let tile = layout.tiles[index(lattice_point(point, dx, dy))];
                    if !tile.class.walkable()
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
                let expected_open = (space == other && !has_portal) || (has_portal && offset == 1);
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
            let tile_point = lattice_point(point, PITCH, PITCH);
            let tile = layout.tiles[index(tile_point)];
            if vertex_requires_post(quartet) && !is_wall(tile.class) {
                return Err(LayoutError(format!(
                    "mixed logical vertex at {point:?} lacks a wall post"
                )));
            }
            if quartet.iter().all(|space| *space == quartet[0])
                && quartet[0] != Space::Exterior
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

fn raster_portal(portal: Portal, plan: &LogicalPlan) -> Point {
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

fn validate_logical_plan(plan: &LogicalPlan, request: &LayoutRequest) -> Result<(), LayoutError> {
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
        if !plan
            .portals
            .iter()
            .any(|portal| portal.department == department.id && portal.kind == PortalKind::Public)
        {
            return Err(LayoutError(format!(
                "department {} has no public portal",
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
        return Err(LayoutError(format!(
            "{} walkable station tiles are unreachable",
            walkable.len() - reached.len()
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

fn is_wall(class: TileClass) -> bool {
    matches!(
        class,
        TileClass::Hull | TileClass::Structure | TileClass::Partition
    )
}

fn adjacent_components(
    department: &BTreeSet<CellPoint>,
    target: Space,
    plan: &LogicalPlan,
) -> Vec<BTreeSet<CellPoint>> {
    let target_cells: BTreeSet<_> = plan
        .points()
        .filter(|point| plan.get(*point) == target)
        .collect();
    connected_components(&target_cells, plan.width, plan.height)
        .into_iter()
        .filter(|component| {
            department.iter().any(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| component.contains(&neighbor))
            })
        })
        .collect()
}

fn shortest_path_between_sets(
    starts: &BTreeSet<CellPoint>,
    goals: &BTreeSet<CellPoint>,
    allowed: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Option<Vec<CellPoint>> {
    let mut frontier: VecDeque<_> = starts.iter().copied().collect();
    let mut previous: BTreeMap<_, _> = starts.iter().map(|point| (*point, *point)).collect();
    let goal = loop {
        let point = frontier.pop_front()?;
        if goals.contains(&point) {
            break point;
        }
        for neighbor in cardinal_cells(point, width, height) {
            if allowed.contains(&neighbor) && !previous.contains_key(&neighbor) {
                previous.insert(neighbor, point);
                frontier.push_back(neighbor);
            }
        }
    };
    let mut path = Vec::new();
    let mut cursor = goal;
    loop {
        path.push(cursor);
        let prior = previous[&cursor];
        if prior == cursor {
            break;
        }
        cursor = prior;
    }
    Some(path)
}

fn shortest_path_in_set(
    start: CellPoint,
    goal: CellPoint,
    allowed: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Option<BTreeSet<CellPoint>> {
    let mut frontier = VecDeque::from([start]);
    let mut previous = BTreeMap::from([(start, start)]);
    while let Some(point) = frontier.pop_front() {
        if point == goal {
            break;
        }
        for neighbor in cardinal_cells(point, width, height) {
            if allowed.contains(&neighbor) && !previous.contains_key(&neighbor) {
                previous.insert(neighbor, point);
                frontier.push_back(neighbor);
            }
        }
    }
    if !previous.contains_key(&goal) {
        return None;
    }
    let mut path = BTreeSet::new();
    let mut cursor = goal;
    loop {
        path.insert(cursor);
        if cursor == start {
            break;
        }
        cursor = previous[&cursor];
    }
    Some(path)
}

fn ordered_shortest_path_in_set(
    start: CellPoint,
    goal: CellPoint,
    allowed: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Option<Vec<CellPoint>> {
    let mut frontier = VecDeque::from([start]);
    let mut previous = BTreeMap::from([(start, start)]);
    while let Some(point) = frontier.pop_front() {
        if point == goal {
            break;
        }
        for neighbor in cardinal_cells(point, width, height) {
            if allowed.contains(&neighbor) && !previous.contains_key(&neighbor) {
                previous.insert(neighbor, point);
                frontier.push_back(neighbor);
            }
        }
    }
    if !previous.contains_key(&goal) {
        return None;
    }
    let mut path = Vec::new();
    let mut cursor = goal;
    loop {
        path.push(cursor);
        if cursor == start {
            break;
        }
        cursor = previous[&cursor];
    }
    path.reverse();
    Some(path)
}

fn nearest_in_set(point: CellPoint, set: &BTreeSet<CellPoint>) -> Option<CellPoint> {
    set.iter()
        .copied()
        .min_by_key(|candidate| cell_distance(*candidate, point))
}

fn connected_components(
    points: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Vec<BTreeSet<CellPoint>> {
    let mut remaining = points.clone();
    let mut components = Vec::new();
    while let Some(seed) = remaining.first().copied() {
        let mut component = BTreeSet::new();
        let mut frontier = VecDeque::from([seed]);
        while let Some(point) = frontier.pop_front() {
            if !remaining.remove(&point) {
                continue;
            }
            component.insert(point);
            frontier.extend(cardinal_cells(point, width, height));
        }
        components.push(component);
    }
    components
}

fn cells_connected(points: &BTreeSet<CellPoint>, width: u16, height: u16) -> bool {
    points.is_empty() || connected_components(points, width, height).len() == 1
}

fn point_components(points: &BTreeSet<Point>, width: u16, height: u16) -> Vec<BTreeSet<Point>> {
    let mut remaining = points.clone();
    let mut components = Vec::new();
    while let Some(seed) = remaining.first().copied() {
        let mut component = BTreeSet::new();
        let mut frontier = VecDeque::from([seed]);
        while let Some(point) = frontier.pop_front() {
            if !remaining.remove(&point) {
                continue;
            }
            component.insert(point);
            frontier.extend(cardinal_points(point, width, height));
        }
        components.push(component);
    }
    components
}

fn points_connected(points: &BTreeSet<Point>, width: u16, height: u16) -> bool {
    points.is_empty() || point_components(points, width, height).len() == 1
}

fn flood_points(
    start: Point,
    allowed: &BTreeSet<Point>,
    width: u16,
    height: u16,
) -> BTreeSet<Point> {
    let mut reached = BTreeSet::new();
    let mut frontier = VecDeque::from([start]);
    while let Some(point) = frontier.pop_front() {
        if !allowed.contains(&point) || !reached.insert(point) {
            continue;
        }
        frontier.extend(cardinal_points(point, width, height));
    }
    reached
}

fn exterior_flood(tiles: &[TileCell], width: u16, height: u16) -> BTreeSet<Point> {
    let index = |point: Point| usize::from(point.y) * usize::from(width) + usize::from(point.x);
    let mut exterior = BTreeSet::new();
    let mut frontier = VecDeque::new();
    for x in 0..width {
        frontier.push_back(Point { x, y: 0 });
        frontier.push_back(Point { x, y: height - 1 });
    }
    for y in 0..height {
        frontier.push_back(Point { x: 0, y });
        frontier.push_back(Point { x: width - 1, y });
    }
    while let Some(point) = frontier.pop_front() {
        if tiles[index(point)].class != TileClass::Exterior || !exterior.insert(point) {
            continue;
        }
        frontier.extend(cardinal_points(point, width, height));
    }
    exterior
}

fn bounds(points: &[Point]) -> Result<Rect, LayoutError> {
    let min_x = points
        .iter()
        .map(|point| point.x)
        .min()
        .ok_or_else(|| LayoutError("cannot bound an empty region".into()))?;
    let max_x = points.iter().map(|point| point.x).max().unwrap();
    let min_y = points.iter().map(|point| point.y).min().unwrap();
    let max_y = points.iter().map(|point| point.y).max().unwrap();
    Ok(Rect {
        x: min_x,
        y: min_y,
        width: max_x - min_x + 1,
        height: max_y - min_y + 1,
    })
}

fn points_with_class(tiles: &[TileCell], width: u16, class: TileClass) -> Vec<Point> {
    tiles
        .iter()
        .enumerate()
        .filter(|(_, tile)| tile.class == class)
        .map(|(index, _)| Point {
            x: (index % usize::from(width)) as u16,
            y: (index / usize::from(width)) as u16,
        })
        .collect()
}

fn cardinal_cells(point: CellPoint, width: u16, height: u16) -> Vec<CellPoint> {
    let mut result = Vec::with_capacity(4);
    if point.x > 0 {
        result.push(CellPoint {
            x: point.x - 1,
            y: point.y,
        });
    }
    if point.x + 1 < width {
        result.push(CellPoint {
            x: point.x + 1,
            y: point.y,
        });
    }
    if point.y > 0 {
        result.push(CellPoint {
            x: point.x,
            y: point.y - 1,
        });
    }
    if point.y + 1 < height {
        result.push(CellPoint {
            x: point.x,
            y: point.y + 1,
        });
    }
    result
}

fn cardinal_points(point: Point, width: u16, height: u16) -> Vec<Point> {
    let mut result = Vec::with_capacity(4);
    if point.x > 0 {
        result.push(Point {
            x: point.x - 1,
            y: point.y,
        });
    }
    if point.x + 1 < width {
        result.push(Point {
            x: point.x + 1,
            y: point.y,
        });
    }
    if point.y > 0 {
        result.push(Point {
            x: point.x,
            y: point.y - 1,
        });
    }
    if point.y + 1 < height {
        result.push(Point {
            x: point.x,
            y: point.y + 1,
        });
    }
    result
}

fn cell_distance(left: CellPoint, right: CellPoint) -> u16 {
    left.x.abs_diff(right.x) + left.y.abs_diff(right.y)
}

fn hash_cell(seed: u64, point: CellPoint) -> u64 {
    mix(seed ^ (u64::from(point.x) << 32) ^ u64::from(point.y))
}

fn mix(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maintenance_module_has_exactly_two_walkable_tiles() {
        assert_eq!(MAINTENANCE_WIDTH, 2);
        assert_eq!(INTERIOR, MAINTENANCE_WIDTH);
        assert_eq!(PITCH, MAINTENANCE_WIDTH + 1);
    }

    #[test]
    fn every_mixed_logical_vertex_requires_a_wall_post() {
        let spaces = [
            Space::Exterior,
            Space::Public,
            Space::Maintenance,
            Space::Common(1),
            Space::Room {
                department: 1,
                room: 1,
            },
        ];
        for &south_west in &spaces {
            for &south_east in &spaces {
                for &north_west in &spaces {
                    for &north_east in &spaces {
                        let quartet = [south_west, south_east, north_west, north_east];
                        let occupied = quartet.iter().any(|space| *space != Space::Exterior);
                        let uniform = quartet.iter().all(|space| *space == quartet[0]);
                        assert_eq!(vertex_requires_post(quartet), occupied && !uniform);
                    }
                }
            }
        }
    }

    #[test]
    fn every_distinct_space_pair_has_a_structural_boundary_class() {
        let spaces = [
            Space::Exterior,
            Space::Public,
            Space::Maintenance,
            Space::Common(1),
            Space::Common(2),
            Space::Room {
                department: 1,
                room: 1,
            },
        ];
        for &left in &spaces {
            for &right in &spaces {
                if left == right {
                    continue;
                }
                assert!(is_wall(logical_boundary_class(left, right)));
                assert_eq!(
                    logical_boundary_class(left, right),
                    logical_boundary_class(right, left)
                );
            }
        }
    }
}
