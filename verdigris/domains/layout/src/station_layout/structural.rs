use super::error::LayoutError;
use super::model::{
    Department, DepartmentRequest, Door, LayoutGraph, LayoutRequest, MacroArchetype, Point, Rect,
    Room, RoomType, STATION_MAINTENANCE_WIDTH, StationLayout, TileCell, TileClass,
};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

// A logical cell contains its walkable interior followed by one structural
// boundary tile. Main and local corridors deliberately share this compact
// module so intersections cannot accidentally widen maintenance.
const PITCH: u16 = STATION_MAINTENANCE_WIDTH + 1;
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

fn room_has_center_lobe(cells: &BTreeSet<CellPoint>) -> bool {
    cells.iter().any(|point| {
        let Some(east) = point.x.checked_add(1) else {
            return false;
        };
        let Some(north) = point.y.checked_add(1) else {
            return false;
        };
        cells.contains(&CellPoint {
            x: east,
            y: point.y,
        }) && cells.contains(&CellPoint {
            x: point.x,
            y: north,
        }) && cells.contains(&CellPoint { x: east, y: north })
    })
}

fn room_minimum_area(room: &RoomType) -> usize {
    // `content_area` is the authoritative authored capacity contract supplied
    // by DM. Center activity affects shape preference, not whether the planner
    // may silently shrink a complete room program into one logical cell.
    usize::try_from(room.content_area).unwrap_or(usize::MAX)
}

fn room_shape_fits(room: &RoomType, cells: &BTreeSet<CellPoint>) -> bool {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let minimum_area = room_minimum_area(room);
    // Content programs own room capacity. A large residual lobe must become
    // another purposeful room, not stretch one workstation across a hangar.
    let ideal_area = usize::try_from(room.ideal_area).unwrap_or(usize::MAX);
    let maximum_area = if ideal_area >= 40 {
        ideal_area.saturating_add(20)
    } else {
        ideal_area.saturating_mul(2)
    }
    .min(64)
    .max(room_minimum_area(room));
    let maximum_area = maximum_area.saturating_add(
        usize::from(maximum_area < 48) * usize::from(PITCH) * usize::from(INTERIOR),
    );
    // The logical grid advances in multi-tile modules, so a generated lobe can
    // legitimately land between an authored minimum and the next grid pitch.
    // Minimum usable area and short-side thickness express the lower bound;
    // the physical maxima remain hard and may be rotated with the room.
    let pitch_slack = usize::from(PITCH) * 3;
    let direct_envelope = width <= usize::from(room.max_width) + pitch_slack
        && height <= usize::from(room.max_height) + pitch_slack;
    let rotated_envelope = height <= usize::from(room.max_width) + pitch_slack
        && width <= usize::from(room.max_height) + pitch_slack;
    // The structural boundary on the open side completes the apparent room
    // width. Count it for thickness/aspect, but never for usable content area.
    let short_side = width.min(height).saturating_add(1);
    let long_side = width.max(height);
    let aspect_millis = long_side.saturating_mul(1000) / short_side.max(1);
    if area < minimum_area
        || area > maximum_area
        || !(direct_envelope || rotated_envelope)
        || short_side < usize::from(room.min_short_side)
        || aspect_millis > room.max_aspect_ratio_millis as usize
    {
        return false;
    }

    // A room whose authored program uses its center needs a genuine interior
    // lobe, not a one-cell-wide snake whose bounding box merely looks large.
    !room.requires_center_activity || room_has_center_lobe(cells)
}

fn room_shape_within_maximum(room: &RoomType, cells: &BTreeSet<CellPoint>) -> bool {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let slack = usize::from(PITCH) * 3;
    let direct = width <= usize::from(room.max_width) + slack
        && height <= usize::from(room.max_height) + slack;
    let rotated = height <= usize::from(room.max_width) + slack
        && width <= usize::from(room.max_height) + slack;
    let ideal_area = usize::try_from(room.ideal_area).unwrap_or(usize::MAX);
    let maximum_area = if ideal_area >= 40 {
        ideal_area.saturating_add(20)
    } else {
        ideal_area.saturating_mul(2)
    }
    .min(64)
    .max(room_minimum_area(room));
    let maximum_area = maximum_area.saturating_add(
        usize::from(maximum_area < 48) * usize::from(PITCH) * usize::from(INTERIOR),
    );
    if area > maximum_area || !(direct || rotated) {
        return false;
    }
    if area < room_minimum_area(room) {
        return true;
    }
    let short_side = width.min(height).saturating_add(1);
    let long_side = width.max(height);
    short_side >= usize::from(room.min_short_side)
        && long_side.saturating_mul(1000) / short_side.max(1)
            <= room.max_aspect_ratio_millis as usize
}

fn room_shape_score(room: &RoomType, cells: &BTreeSet<CellPoint>) -> usize {
    let area = projected_room_tile_area(cells);
    let (width, height) = projected_room_dimensions(cells);
    let area_error = area.abs_diff(room.ideal_area as usize);
    let aspect_penalty = width.max(height).saturating_sub(width.min(height));
    let logical_width = cells
        .iter()
        .map(|point| point.x)
        .max()
        .zip(cells.iter().map(|point| point.x).min())
        .map_or(0, |(max, min)| usize::from(max - min) + 1);
    let logical_height = cells
        .iter()
        .map(|point| point.y)
        .max()
        .zip(cells.iter().map(|point| point.y).min())
        .map_or(0, |(max, min)| usize::from(max - min) + 1);
    // Missing modules inside the bounding envelope are allowed, producing
    // useful L/T rooms, but are costly enough that long hooks and amoeba-like
    // claims lose to compact alternatives.
    let envelope_voids = logical_width
        .saturating_mul(logical_height)
        .saturating_sub(cells.len());
    let envelope_center_width = usize::from(room.min_width + room.max_width) / 2;
    let envelope_center_height = usize::from(room.min_height + room.max_height) / 2;
    let direct_dimension_error =
        width.abs_diff(envelope_center_width) + height.abs_diff(envelope_center_height);
    let rotated_dimension_error =
        height.abs_diff(envelope_center_width) + width.abs_diff(envelope_center_height);
    area_error * 8
        + aspect_penalty * 12
        + envelope_voids * 18
        + direct_dimension_error.min(rotated_dimension_error) * 3
}

fn split_shape_for_authored_rooms<'a>(
    shape: &BTreeSet<CellPoint>,
    variants: &'a [RoomType],
    width: u16,
    height: u16,
    depth: usize,
    frontage_cut_vertical: Option<bool>,
) -> Option<Vec<(BTreeSet<CellPoint>, &'a RoomType)>> {
    if let Some(variant) = variants
        .iter()
        .filter(|variant| room_shape_fits(variant, shape))
        .min_by_key(|variant| room_shape_score(variant, shape))
    {
        return Some(vec![(shape.clone(), variant)]);
    }
    if depth == 0 || shape.len() < 2 {
        return None;
    }
    let min_x = shape.iter().map(|point| point.x).min()?;
    let max_x = shape.iter().map(|point| point.x).max()?;
    let min_y = shape.iter().map(|point| point.y).min()?;
    let max_y = shape.iter().map(|point| point.y).max()?;
    let mut cuts = Vec::new();
    if max_x > min_x && frontage_cut_vertical != Some(false) {
        for cut in min_x..max_x {
            cuts.push((max_x - min_x, true, cut));
        }
    }
    if max_y > min_y && frontage_cut_vertical != Some(true) {
        for cut in min_y..max_y {
            cuts.push((max_y - min_y, false, cut));
        }
    }
    cuts.sort_by_key(|(span, vertical, cut)| {
        let midpoint = if *vertical {
            min_x + (max_x - min_x) / 2
        } else {
            min_y + (max_y - min_y) / 2
        };
        (Reverse(*span), cut.abs_diff(midpoint))
    });
    cuts.truncate(1);
    for (_, vertical, cut) in cuts {
        let left = shape
            .iter()
            .copied()
            .filter(|point| {
                if vertical {
                    point.x <= cut
                } else {
                    point.y <= cut
                }
            })
            .collect::<BTreeSet<_>>();
        let right = shape.difference(&left).copied().collect::<BTreeSet<_>>();
        if left.is_empty()
            || right.is_empty()
            || !cells_connected(&left, width, height)
            || !cells_connected(&right, width, height)
        {
            continue;
        }
        if let (Some(mut left_rooms), Some(right_rooms)) = (
            split_shape_for_authored_rooms(
                &left,
                variants,
                width,
                height,
                depth - 1,
                frontage_cut_vertical,
            ),
            split_shape_for_authored_rooms(
                &right,
                variants,
                width,
                height,
                depth - 1,
                frontage_cut_vertical,
            ),
        ) {
            left_rooms.extend(right_rooms);
            return Some(left_rooms);
        }
    }
    variants
        .iter()
        .filter(|variant| room_shape_within_maximum(variant, shape))
        .min_by_key(|variant| room_shape_score(variant, shape))
        .map(|variant| vec![(shape.clone(), variant)])
}

fn force_split_authored_shape<'a>(
    shape: &BTreeSet<CellPoint>,
    variants: &'a [RoomType],
    width: u16,
    height: u16,
    frontage_cut_vertical: Option<bool>,
) -> Option<Vec<(BTreeSet<CellPoint>, &'a RoomType)>> {
    let min_x = shape.iter().map(|point| point.x).min()?;
    let max_x = shape.iter().map(|point| point.x).max()?;
    let min_y = shape.iter().map(|point| point.y).min()?;
    let max_y = shape.iter().map(|point| point.y).max()?;
    let mut cuts = Vec::new();
    for cut in min_x..max_x {
        if frontage_cut_vertical == Some(false) {
            continue;
        }
        cuts.push((
            Reverse(max_x - min_x),
            cut.abs_diff((min_x + max_x) / 2),
            true,
            cut,
        ));
    }
    for cut in min_y..max_y {
        if frontage_cut_vertical == Some(true) {
            continue;
        }
        cuts.push((
            Reverse(max_y - min_y),
            cut.abs_diff((min_y + max_y) / 2),
            false,
            cut,
        ));
    }
    cuts.sort();
    for (_, _, vertical, cut) in cuts {
        let left = shape
            .iter()
            .copied()
            .filter(|point| {
                if vertical {
                    point.x <= cut
                } else {
                    point.y <= cut
                }
            })
            .collect::<BTreeSet<_>>();
        let right = shape.difference(&left).copied().collect::<BTreeSet<_>>();
        if left.is_empty()
            || right.is_empty()
            || !cells_connected(&left, width, height)
            || !cells_connected(&right, width, height)
        {
            continue;
        }
        if let (Some(mut left_rooms), Some(right_rooms)) = (
            split_shape_for_authored_rooms(
                &left,
                variants,
                width,
                height,
                6,
                frontage_cut_vertical,
            ),
            split_shape_for_authored_rooms(
                &right,
                variants,
                width,
                height,
                6,
                frontage_cut_vertical,
            ),
        ) {
            left_rooms.extend(right_rooms);
            return Some(left_rooms);
        }
    }
    None
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
    // Preserve the exact compact/full contract chosen by the matcher.
    room_type: RoomType,
}

#[derive(Clone, Debug)]
struct LogicalPlan {
    width: u16,
    height: u16,
    origin: Point,
    cells: Vec<Space>,
    rooms: Vec<RoomPlan>,
    portals: Vec<Portal>,
    maintenance_barriers: BTreeSet<(CellPoint, CellPoint)>,
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
    let mut best_small_room_fallback: Option<(usize, StationLayout)> = None;
    // A catalog-valid seed must not become a hard runtime failure merely
    // because one randomized center/claim arrangement cannot expose every
    // required room frontage. Retry a bounded deterministic sequence while
    // retaining the caller's public seed in the result.
    let attempts = std::env::var("DQ_LAYOUT_ATTEMPTS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(8)
        .clamp(1, 8);
    for attempt in 0_u64..attempts {
        let mut candidate = request.clone();
        candidate.settings.seed = public_seed.wrapping_add(attempt.wrapping_mul(0x9e37_79b9));
        let generated = (|| {
            let logical = build_logical_plan(&candidate)?;
            let mut station = rasterize(&candidate, &logical)?;
            validate_station_structure(&station)?;
            validate_semantic_room_variety(&station, &candidate)?;
            let longest_public_run = longest_public_corridor_run(&station);
            if longest_public_run > 55 {
                return Err(LayoutError(format!(
                    "public corridor ran straight for {longest_public_run} tiles"
                )));
            }
            let tiny_rooms = station
                .rooms
                .iter()
                .filter(|room| room.tiles.len() <= 16)
                .count();
            if tiny_rooms.saturating_mul(10) > station.rooms.len() {
                if best_small_room_fallback
                    .as_ref()
                    .is_none_or(|(known, _)| tiny_rooms < *known)
                {
                    best_small_room_fallback = Some((tiny_rooms, station.clone()));
                }
                return Err(LayoutError(format!(
                    "{tiny_rooms}/{} rooms were below the authored minimum-size mix",
                    station.rooms.len()
                )));
            }
            station.seed = public_seed;
            Ok(station)
        })();
        match generated {
            Ok(station) => {
                // Every accepted candidate has already passed the structural,
                // semantic-variety, and circulation quality gates. Returning
                // the first passing deterministic candidate avoids generating
                // seven stations that will immediately be discarded.
                return Ok(station);
            }
            Err(error) => last_error = Some(error),
        }
    }
    if let Some((_, station)) = best_small_room_fallback {
        return Ok(station);
    }
    Err(last_error
        .unwrap_or_else(|| LayoutError("station generation exhausted its candidates".into())))
}

fn longest_public_corridor_run(station: &StationLayout) -> usize {
    let mut longest = 0usize;
    for y in 0..station.height {
        let mut run = 0usize;
        for x in 0..station.width {
            if station.tile(Point { x, y }).class == TileClass::Public {
                run += 1;
                longest = longest.max(run);
            } else {
                run = 0;
            }
        }
    }
    for x in 0..station.width {
        let mut run = 0usize;
        for y in 0..station.height {
            if station.tile(Point { x, y }).class == TileClass::Public {
                run += 1;
                longest = longest.max(run);
            } else {
                run = 0;
            }
        }
    }
    longest
}

fn validate_semantic_room_variety(
    station: &StationLayout,
    request: &LayoutRequest,
) -> Result<(), LayoutError> {
    for department in &request.departments {
        let roles = station
            .rooms
            .iter()
            .filter(|room| room.department_id == department.id)
            .filter_map(|room| {
                department
                    .room_types
                    .iter()
                    .find(|room_type| room_type.id == room.room_type_id)
                    .map(|room_type| room_type.name.as_str())
            })
            .collect::<BTreeSet<_>>();
        let available_roles = department
            .room_types
            .iter()
            .map(|room| room.name.as_str())
            .collect::<BTreeSet<_>>()
            .len();
        if roles.len() < available_roles.min(3) {
            return Err(LayoutError(format!(
                "department {} retained only {} semantic room roles",
                department.id,
                roles.len()
            )));
        }
    }
    Ok(())
}

#[derive(Clone, Copy, Debug)]
enum BlockFrontage {
    North,
    South,
    East,
    West,
}

#[derive(Clone, Copy, Debug)]
struct DepartmentBlock {
    min_x: u16,
    max_x: u16,
    min_y: u16,
    max_y: u16,
    frontage: BlockFrontage,
}

fn build_logical_plan(request: &LayoutRequest) -> Result<LogicalPlan, LayoutError> {
    build_architectural_plan(request)
}

fn build_architectural_plan(request: &LayoutRequest) -> Result<LogicalPlan, LayoutError> {
    let canvas_width = (request.settings.width - 3) / PITCH;
    let canvas_height = (request.settings.height - 3) / PITCH;
    let available_side = canvas_width.min(canvas_height);
    if available_side < 25 {
        return Err(LayoutError(format!(
            "architectural station canvas requires at least {} physical tiles per side",
            25 * PITCH + 3
        )));
    }
    let side = available_side.min(29);
    let span = side * PITCH + 1;
    let origin = Point {
        x: (request.settings.width - span) / 2,
        y: (request.settings.height - span) / 2,
    };
    let mut plan = LogicalPlan {
        width: side,
        height: side,
        origin,
        cells: vec![Space::Exterior; usize::from(side).pow(2)],
        rooms: Vec::new(),
        portals: Vec::new(),
        maintenance_barriers: BTreeSet::new(),
        department_centers: BTreeMap::new(),
        department_edges: Vec::new(),
    };
    let center_x = side / 2;
    let center_y = side / 2;
    // Keep a recognizable station grammar without making every seed the same
    // four-wing cross.  The two offset-spine orientations are deliberately more
    // common than the cross, matching the asymmetric circulation of authored maps.
    let circulation_grammar = 1 + (hash64(request.settings.seed ^ 0x6d61_6372_6f5f_6772) % 2) as u8;
    let bent_spine = true;
    let transpose_bent_spine = circulation_grammar == 2;
    let upper_spine_x = center_x.saturating_sub(3);
    let lower_spine_x = center_x + 3;
    let jog_start = 3;
    let jog_end = upper_spine_x.saturating_sub(2).max(jog_start + 2);
    let jog_axis = if hash64(request.settings.seed ^ 0x636f_7272_6964_6f72) & 1 == 1 {
        center_y + 1
    } else {
        center_y - 1
    };
    for point in plan.points().collect::<Vec<_>>() {
        if point.x == 0 || point.y == 0 || point.x + 1 == side || point.y + 1 == side {
            plan.set(point, Space::Exterior);
        } else if (if bent_spine {
            if transpose_bent_spine {
                ((point.x == center_x
                    && point.y >= 2
                    && point.y + 2 < side
                    && !(point.y > jog_start && point.y < jog_end))
                    || (point.x == jog_axis && point.y >= jog_start && point.y <= jog_end)
                    || ((point.y == jog_start || point.y == jog_end)
                        && point.x >= center_x.min(jog_axis)
                        && point.x <= center_x.max(jog_axis)))
                    || (point.y == upper_spine_x && point.x >= 2 && point.x <= center_x)
                    || (point.y == lower_spine_x && point.x >= center_x && point.x + 2 < side)
            } else {
                ((point.y == center_y
                    && point.x >= 2
                    && point.x + 2 < side
                    && !(point.x > jog_start && point.x < jog_end))
                    || (point.y == jog_axis && point.x >= jog_start && point.x <= jog_end)
                    || ((point.x == jog_start || point.x == jog_end)
                        && point.y >= center_y.min(jog_axis)
                        && point.y <= center_y.max(jog_axis)))
                    || (point.x == upper_spine_x && point.y >= 2 && point.y <= center_y)
                    || (point.x == lower_spine_x && point.y >= center_y && point.y + 2 < side)
            }
        } else {
            point.x == center_x || point.y == center_y
        }) && point.x >= 2
            && point.y >= 2
            && point.x + 2 < side
            && point.y + 2 < side
        {
            plan.set(point, Space::Public);
        }
    }

    let low_min = 2;
    let low_max_x = center_x - 1;
    let high_min_x = center_x + 1;
    let low_max_y = center_y - 1;
    let high_min_y = center_y + 1;
    let high_max = side - 3;
    let mut quadrant_specs = vec![
        (
            low_min,
            low_max_x,
            high_min_y,
            high_max,
            BlockFrontage::South,
        ),
        (
            high_min_x,
            high_max,
            high_min_y,
            high_max,
            BlockFrontage::South,
        ),
        (low_min, low_max_x, low_min, low_max_y, BlockFrontage::North),
        (
            high_min_x,
            high_max,
            low_min,
            low_max_y,
            BlockFrontage::North,
        ),
    ];
    let mut rng = Rng::new(request.settings.seed);
    for index in (1..quadrant_specs.len()).rev() {
        let other = rng.choose(index + 1);
        quadrant_specs.swap(index, other);
    }
    let mut counts = [2usize, 2, 2, 1];
    if rng.choose(2) == 1 {
        counts.rotate_left(1);
    }
    let mut blocks = Vec::new();
    for ((min_x, max_x, min_y, max_y, horizontal_frontage), count) in
        quadrant_specs.into_iter().zip(counts)
    {
        let use_horizontal = rng.choose(2) == 0;
        if count == 1 {
            blocks.push(DepartmentBlock {
                min_x,
                max_x,
                min_y,
                max_y,
                frontage: if use_horizontal {
                    horizontal_frontage
                } else if max_x < center_x {
                    BlockFrontage::East
                } else {
                    BlockFrontage::West
                },
            });
            continue;
        }
        if use_horizontal {
            let midpoint = i16::try_from(min_x + (max_x - min_x) / 2).unwrap_or(0);
            let margin = ((max_x - min_x).saturating_sub(2) / 2).min(5);
            // Coordinates are station-grid sized (far below i16::MAX), but
            // fall back to the unclamped midpoint rather than panic if a
            // future caller ever passes near-u16::MAX bounds.
            let lo = i16::try_from(min_x + margin).unwrap_or(midpoint);
            let hi = i16::try_from(max_x - margin).unwrap_or(midpoint);
            let separator = u16::try_from((midpoint + rng.signed(1)).clamp(lo.min(hi), lo.max(hi)))
                .unwrap_or(min_x + (max_x - min_x) / 2);
            blocks.push(DepartmentBlock {
                min_x,
                max_x: separator - 1,
                min_y,
                max_y,
                frontage: horizontal_frontage,
            });
            blocks.push(DepartmentBlock {
                min_x: separator + 1,
                max_x,
                min_y,
                max_y,
                frontage: horizontal_frontage,
            });
        } else {
            let midpoint = i16::try_from(min_y + (max_y - min_y) / 2).unwrap_or(0);
            let margin = ((max_y - min_y).saturating_sub(2) / 2).min(5);
            // See the horizontal branch above: fall back rather than panic.
            let lo = i16::try_from(min_y + margin).unwrap_or(midpoint);
            let hi = i16::try_from(max_y - margin).unwrap_or(midpoint);
            let separator = u16::try_from((midpoint + rng.signed(1)).clamp(lo.min(hi), lo.max(hi)))
                .unwrap_or(min_y + (max_y - min_y) / 2);
            let vertical_frontage = if max_x < center_x {
                BlockFrontage::East
            } else {
                BlockFrontage::West
            };
            blocks.push(DepartmentBlock {
                min_x,
                max_x,
                min_y,
                max_y: separator - 1,
                frontage: vertical_frontage,
            });
            blocks.push(DepartmentBlock {
                min_x,
                max_x,
                min_y: separator + 1,
                max_y,
                frontage: vertical_frontage,
            });
        }
    }
    if bent_spine {
        blocks =
            bent_spine_department_blocks(side, center_y, upper_spine_x, lower_spine_x, &mut rng);
        if transpose_bent_spine {
            blocks = blocks.into_iter().map(transpose_department_block).collect();
        }
    }
    blocks.truncate(request.departments.len());
    if blocks.len() != request.departments.len() {
        return Err(LayoutError(
            "architectural grammar could not allocate every department".into(),
        ));
    }
    let mut next_room_id = 1u16;
    // Match program demand to usable territory. Randomly shuffling departments
    // into rectangles made tiny programs inherit huge wings and forced the
    // room allocator to repeat roles merely to consume the excess.
    blocks.sort_by_key(|block| {
        (
            Reverse(
                u32::from(block.max_x - block.min_x + 1) * u32::from(block.max_y - block.min_y + 1),
            ),
            hash64(
                request.settings.seed
                    ^ u64::from(block.min_x).rotate_left(13)
                    ^ u64::from(block.min_y).rotate_left(29),
            ),
        )
    });
    let mut departments = request.departments.iter().collect::<Vec<_>>();
    // Preserve capacity matching while varying equally sized wings. Stable
    // sorting alone assigned the same six major departments to the same six
    // blocks for every seed, making the adjacency graph canonical despite
    // visibly different outlines.
    departments.sort_by_key(|department| {
        (
            Reverse(department.desired_area),
            hash64(request.settings.seed ^ u64::from(department.id)),
        )
    });
    for (department, block) in departments.into_iter().zip(blocks) {
        let block = shape_department_block(block, request.settings.seed, department.id);
        pack_architectural_department(
            &mut plan,
            department,
            block,
            &mut next_room_id,
            request.settings.seed,
        )?;
    }
    consolidate_optional_tiny_rooms(&mut plan, request);
    validate_room_envelopes(&plan, "department packing")?;
    add_secondary_public_crosslinks(&mut plan, request.settings.seed);
    validate_room_envelopes(&plan, "public crosslinks")?;
    articulate_department_suites(&mut plan, request.settings.seed);
    validate_room_envelopes(&plan, "suite articulation")?;
    trim_public_dead_ends(&mut plan);
    validate_room_envelopes(&plan, "public trimming")?;
    derive_maintenance_service_space(&mut plan);
    validate_room_envelopes(&plan, "maintenance derivation")?;
    connect_service_pockets(&mut plan)?;
    validate_room_envelopes(&plan, "service connection")?;
    repair_disconnected_room_ownership(&mut plan)?;
    validate_room_envelopes(&plan, "disconnected-room repair")?;
    extend_common_halls_to_every_room(&mut plan)?;
    validate_room_envelopes(&plan, "minimal hall branches")?;
    assign_portals(&mut plan, request)?;
    ensure_maintenance_component_portals(&mut plan)?;
    derive_department_transit_graph(&mut plan, request.settings.seed);
    validate_logical_plan(&plan, request)?;
    Ok(plan)
}

/// Describe the physical department arrangement, rather than emitting an
/// empty/canonical dependency graph. The graph is a minimum spanning tree over
/// actual suite centers; seed ordering only resolves equally good links.
fn derive_department_transit_graph(plan: &mut LogicalPlan, seed: u64) {
    let centers = plan
        .department_centers
        .iter()
        .map(|(id, center)| (*id, *center))
        .collect::<Vec<_>>();
    if centers.len() < 2 {
        plan.department_edges.clear();
        return;
    }
    let points = centers
        .iter()
        .map(|(_, center)| *center)
        .collect::<Vec<_>>();
    let mut rng = Rng::new(seed ^ 0x7472_616e_7369_745f);
    plan.department_edges = minimum_spanning_tree(&points, &mut rng)
        .into_iter()
        .map(|(left, right)| (centers[left].0, centers[right].0))
        .collect();
}

/// Compact catalog variants are useful for genuine closets, but recursive bay
/// splitting must not turn them into the dominant station grammar.  Fold an
/// optional tiny partition into an adjacent authored room whenever their union
/// has a valid envelope. Required semantic rooms are never removed.
fn consolidate_optional_tiny_rooms(plan: &mut LogicalPlan, request: &LayoutRequest) {
    loop {
        let mut changed = false;
        let room_ids = plan.rooms.iter().map(|room| room.id).collect::<Vec<_>>();
        for room_id in room_ids {
            let Some(room_index) = plan.rooms.iter().position(|room| room.id == room_id) else {
                continue;
            };
            let room = plan.rooms[room_index].clone();
            let cells = plan
                .points()
                .filter(|point| plan.get(*point).room() == Some(room_id))
                .collect::<BTreeSet<_>>();
            if projected_room_tile_area(&cells) > 16 {
                continue;
            }
            let Some(department) = request
                .departments
                .iter()
                .find(|department| department.id == room.department)
            else {
                continue;
            };
            let semantic_count = plan
                .rooms
                .iter()
                .filter(|candidate| {
                    candidate.department == room.department
                        && candidate.room_type.name == room.room_type.name
                })
                .count();
            let exact_count = plan
                .rooms
                .iter()
                .filter(|candidate| {
                    candidate.department == room.department
                        && candidate.room_type.id == room.room_type.id
                })
                .count();
            if exact_count <= usize::from(room.room_type.min_count) {
                continue;
            }
            let required_count = department
                .room_types
                .iter()
                .filter(|variant| variant.name == room.room_type.name)
                .map(|variant| usize::from(variant.min_count))
                .max()
                .unwrap_or(0);
            if semantic_count <= required_count {
                continue;
            }
            let adjacent_ids = cells
                .iter()
                .flat_map(|point| plan.neighbors(*point))
                .filter_map(|point| plan.get(point).room())
                .filter(|other_id| *other_id != room_id)
                .collect::<BTreeSet<_>>();
            let replacement = adjacent_ids
                .into_iter()
                .filter_map(|other_id| {
                    let other_index = plan.rooms.iter().position(|other| {
                        other.id == other_id && other.department == room.department
                    })?;
                    let mut combined = cells.clone();
                    combined.extend(
                        plan.points()
                            .filter(|point| plan.get(*point).room() == Some(other_id)),
                    );
                    department
                        .room_types
                        .iter()
                        .filter(|variant| variant.name == plan.rooms[other_index].room_type.name)
                        .filter(|variant| room_shape_fits(variant, &combined))
                        .min_by_key(|variant| room_shape_score(variant, &combined))
                        .map(|variant| (other_id, other_index, combined, variant.clone()))
                })
                .min_by_key(|(_, _, combined, variant)| room_shape_score(variant, combined));
            let Some((other_id, other_index, combined, variant)) = replacement else {
                // The partition has real hallway frontage but cannot combine
                // with a neighbor without violating that neighbor's authored
                // envelope. It is circulation alcove, not a pretend 2x2 room.
                for point in cells {
                    plan.set(point, Space::Common(room.department));
                }
                plan.rooms.remove(room_index);
                changed = true;
                break;
            };
            for point in combined {
                plan.set(
                    point,
                    Space::Room {
                        department: room.department,
                        room: other_id,
                    },
                );
            }
            plan.rooms[other_index].room_type = variant;
            plan.rooms.remove(room_index);
            changed = true;
            break;
        }
        if !changed {
            break;
        }
    }
}

fn validate_room_envelopes(plan: &LogicalPlan, stage: &str) -> Result<(), LayoutError> {
    for planned_room in &plan.rooms {
        let cells = plan
            .points()
            .filter(|point| {
                plan.get(*point)
                    == (Space::Room {
                        department: planned_room.department,
                        room: planned_room.id,
                    })
            })
            .collect::<BTreeSet<_>>();
        if !room_shape_within_maximum(&planned_room.room_type, &cells) {
            return Err(LayoutError(format!(
                "{stage}: room {} violates its selected authored envelope (area {}, minimum {}, ideal {}, variant {})",
                planned_room.id,
                projected_room_tile_area(&cells),
                room_minimum_area(&planned_room.room_type),
                planned_room.room_type.ideal_area,
                planned_room.room_type.id,
            )));
        }
    }
    Ok(())
}

fn add_secondary_public_crosslinks(plan: &mut LogicalPlan, seed: u64) {
    const REACH: u16 = 3;
    let common_in_direction =
        |plan: &LogicalPlan, point: CellPoint, dx: i16, dy: i16| -> Option<u16> {
            for distance in 1..=REACH {
                let x = i32::from(point.x) + i32::from(dx) * i32::from(distance);
                let y = i32::from(point.y) + i32::from(dy) * i32::from(distance);
                if x < 0 || y < 0 || x >= i32::from(plan.width) || y >= i32::from(plan.height) {
                    break;
                }
                match plan.get(CellPoint {
                    x: u16::try_from(x).ok()?,
                    y: u16::try_from(y).ok()?,
                }) {
                    Space::Common(department) => return Some(department),
                    Space::Exterior => {}
                    _ => break,
                }
            }
            None
        };
    let candidates = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Exterior)
        .filter(|point| {
            common_in_direction(plan, *point, -1, 0)
                .zip(common_in_direction(plan, *point, 1, 0))
                .is_some_and(|(left, right)| left != right)
                || common_in_direction(plan, *point, 0, -1)
                    .zip(common_in_direction(plan, *point, 0, 1))
                    .is_some_and(|(bottom, top)| bottom != top)
        })
        .collect::<BTreeSet<_>>();
    let mut links = connected_components(&candidates, plan.width, plan.height)
        .into_iter()
        .filter(|component| component.len() <= usize::from(REACH))
        .collect::<Vec<_>>();
    links.sort_by_key(|component| {
        component
            .iter()
            .map(|point| hash_cell(seed ^ 0x6372_6f73_736c_696e, *point))
            .min()
            .unwrap_or(u64::MAX)
    });
    let target = 2 + usize::try_from(seed & 1).unwrap_or(0);
    for link in links.into_iter().take(target) {
        for point in link {
            plan.set(point, Space::Public);
        }
    }
}

fn articulate_department_suites(plan: &mut LogicalPlan, seed: u64) {
    let departments = plan
        .rooms
        .iter()
        .map(|room| room.department)
        .collect::<BTreeSet<_>>();
    for department in departments {
        let room_ids = plan
            .rooms
            .iter()
            .filter(|room| room.department == department)
            .map(|room| room.id)
            .collect::<BTreeSet<_>>();
        let vestibule_target = (room_ids.len() / 4).max(1);
        let mut articulated = BTreeSet::new();
        let mut vestibules = plan
            .points()
            .filter_map(|point| {
                let Space::Room {
                    department: owner,
                    room,
                } = plan.get(point)
                else {
                    return None;
                };
                if owner != department {
                    return None;
                }
                plan.neighbors(point)
                    .any(|neighbor| plan.get(neighbor) == Space::Common(department))
                    .then_some((point, room))
            })
            .collect::<Vec<_>>();
        vestibules.sort_by_key(|(point, room)| {
            hash_cell(seed ^ 0x7665_7374_6962_756c ^ u64::from(*room), *point)
        });
        for (point, room) in vestibules {
            if articulated.contains(&room) {
                continue;
            }
            let remaining = plan
                .points()
                .filter(|candidate| {
                    *candidate != point
                        && matches!(
                            plan.get(*candidate),
                            Space::Room {
                                department: owner,
                                room: candidate_room,
                            } if owner == department && candidate_room == room
                        )
                })
                .collect::<BTreeSet<_>>();
            if remaining.len() < 4 || !cells_connected(&remaining, plan.width, plan.height) {
                continue;
            }
            let Some(contract) = plan
                .rooms
                .iter()
                .find(|planned| planned.id == room)
                .map(|planned| &planned.room_type)
            else {
                continue;
            };
            if !room_shape_fits(contract, &remaining) {
                continue;
            }
            plan.set(point, Space::Common(department));
            articulated.insert(room);
            if articulated.len() >= vestibule_target {
                break;
            }
        }
    }
}

fn transpose_department_block(block: DepartmentBlock) -> DepartmentBlock {
    DepartmentBlock {
        min_x: block.min_y,
        max_x: block.max_y,
        min_y: block.min_x,
        max_y: block.max_x,
        frontage: match block.frontage {
            BlockFrontage::East => BlockFrontage::North,
            BlockFrontage::West => BlockFrontage::South,
            BlockFrontage::North => BlockFrontage::East,
            BlockFrontage::South => BlockFrontage::West,
        },
    }
}

fn bent_spine_department_blocks(
    side: u16,
    center_y: u16,
    upper_spine_x: u16,
    lower_spine_x: u16,
    rng: &mut Rng,
) -> Vec<DepartmentBlock> {
    let min = 2;
    let max = side - 3;
    let upper_min_y = min;
    let upper_max_y = center_y - 1;
    let upper_separator = upper_min_y + (upper_max_y - upper_min_y) / 2;
    let mut blocks = vec![
        DepartmentBlock {
            min_x: min,
            max_x: upper_spine_x - 1,
            min_y: upper_min_y,
            max_y: upper_separator - 1,
            frontage: BlockFrontage::East,
        },
        DepartmentBlock {
            min_x: min,
            max_x: upper_spine_x - 1,
            min_y: upper_separator + 1,
            max_y: upper_max_y,
            frontage: BlockFrontage::East,
        },
        DepartmentBlock {
            min_x: upper_spine_x + 1,
            max_x: max,
            min_y: upper_min_y,
            max_y: upper_separator - 1,
            frontage: BlockFrontage::West,
        },
        DepartmentBlock {
            min_x: upper_spine_x + 1,
            max_x: max,
            min_y: upper_separator + 1,
            max_y: upper_max_y,
            frontage: BlockFrontage::West,
        },
    ];
    let lower_min_y = center_y + 1;
    let lower_max_y = max;
    let lower_separator = lower_min_y + (lower_max_y - lower_min_y) / 2;
    let split_left = rng.choose(2) == 0;
    let (split_min_x, split_max_x, split_frontage, single_min_x, single_max_x, single_frontage) =
        if split_left {
            (
                min,
                lower_spine_x - 1,
                BlockFrontage::East,
                lower_spine_x + 1,
                max,
                BlockFrontage::West,
            )
        } else {
            (
                lower_spine_x + 1,
                max,
                BlockFrontage::West,
                min,
                lower_spine_x - 1,
                BlockFrontage::East,
            )
        };
    blocks.push(DepartmentBlock {
        min_x: split_min_x,
        max_x: split_max_x,
        min_y: lower_min_y,
        max_y: lower_separator - 1,
        frontage: split_frontage,
    });
    blocks.push(DepartmentBlock {
        min_x: split_min_x,
        max_x: split_max_x,
        min_y: lower_separator + 1,
        max_y: lower_max_y,
        frontage: split_frontage,
    });
    blocks.push(DepartmentBlock {
        min_x: single_min_x,
        max_x: single_max_x,
        min_y: lower_min_y,
        max_y: lower_max_y,
        frontage: single_frontage,
    });
    blocks
}

fn trim_public_dead_ends(plan: &mut LogicalPlan) {
    loop {
        let removable = plan.points().find(|point| {
            if plan.get(*point) != Space::Public {
                return false;
            }
            let neighbors = plan.neighbors(*point).collect::<Vec<_>>();
            let public_neighbors = neighbors
                .iter()
                .filter(|neighbor| plan.get(**neighbor) == Space::Public)
                .count();
            let serves_department = neighbors.iter().any(|neighbor| {
                matches!(plan.get(*neighbor), Space::Common(_) | Space::Room { .. })
            });
            public_neighbors <= 1 && !serves_department
        });
        let Some(point) = removable else {
            break;
        };
        plan.set(point, Space::Exterior);
    }
}

fn connect_service_pockets(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
    loop {
        let maintenance = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Maintenance)
            .collect::<BTreeSet<_>>();
        let components = connected_components(&maintenance, plan.width, plan.height);
        if components.len() <= 1 {
            return (!maintenance.is_empty()).then_some(()).ok_or_else(|| {
                LayoutError("architectural plan produced no maintenance network".into())
            });
        }
        let network = components
            .iter()
            .max_by_key(|component| component.len())
            .cloned()
            .ok_or_else(|| {
                LayoutError("architectural plan produced no maintenance network".into())
            })?;
        let pocket = components
            .iter()
            .filter(|component| **component != network)
            .min_by_key(|component| {
                component
                    .iter()
                    .flat_map(|point| {
                        network
                            .iter()
                            .map(move |other| cell_distance(*point, *other))
                    })
                    .min()
                    .unwrap_or(u16::MAX)
            })
            .cloned()
            .ok_or_else(|| LayoutError("maintenance pocket selection failed".into()))?;
        let allowed = plan
            .points()
            .filter(|point| matches!(plan.get(*point), Space::Exterior | Space::Maintenance))
            .collect::<BTreeSet<_>>();
        let path = shortest_path_between_sets(&network, &pocket, &allowed, plan.width, plan.height)
            .or_else(|| {
                // A service bay can be enclosed by a department suite after
                // room packing. Route its choke point through local/common
                // circulation, never through an authored room or the public
                // spine. This models the short maintenance cross-passages used
                // on hand-authored stations and keeps the service graph whole.
                let service_or_local = plan
                    .points()
                    .filter(|point| {
                        matches!(
                            plan.get(*point),
                            Space::Exterior | Space::Maintenance | Space::Common(_) | Space::Public
                        )
                    })
                    .collect::<BTreeSet<_>>();
                shortest_path_between_sets(
                    &network,
                    &pocket,
                    &service_or_local,
                    plan.width,
                    plan.height,
                )
            })
            .ok_or_else(|| {
                LayoutError(
                    "maintenance pockets cannot connect without crossing an authored room".into(),
                )
            })?;
        for point in path {
            plan.set(point, Space::Maintenance);
        }
    }
}

fn ensure_maintenance_component_portals(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
    let maintenance = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Maintenance)
        .collect::<BTreeSet<_>>();
    for component in connected_components(&maintenance, plan.width, plan.height) {
        if plan
            .portals
            .iter()
            .any(|portal| component.contains(&portal.left) || component.contains(&portal.right))
        {
            continue;
        }
        let mut candidate = None;
        for maintenance_cell in &component {
            for neighbor in plan.neighbors(*maintenance_cell) {
                let (department, room, kind) = match plan.get(neighbor) {
                    Space::Public => (0, None, PortalKind::PublicMaintenance),
                    Space::Common(department) => (department, None, PortalKind::Maintenance),
                    Space::Room { department, room } => {
                        (department, Some(room), PortalKind::RoomMaintenance)
                    }
                    _ => continue,
                };
                candidate = Some(Portal {
                    left: neighbor,
                    right: *maintenance_cell,
                    department,
                    room,
                    kind,
                });
                break;
            }
            if candidate.is_some() {
                break;
            }
        }
        let portal = candidate.ok_or_else(|| {
            LayoutError("isolated maintenance service space has no accessible boundary".into())
        })?;
        plan.portals.push(portal);
    }
    Ok(())
}

fn shape_department_block(
    mut block: DepartmentBlock,
    seed: u64,
    department: u16,
) -> DepartmentBlock {
    let hash = hash64(seed ^ u64::from(department) ^ 0x626c_6f63_6b5f_7368);
    let depth_trim = 1 + (hash % 3) as u16;
    match block.frontage {
        BlockFrontage::East => {
            block.min_x = (block.min_x + depth_trim).min(block.max_x.saturating_sub(6));
        }
        BlockFrontage::West => {
            block.max_x = block.max_x.saturating_sub(depth_trim).max(block.min_x + 6);
        }
        BlockFrontage::North => {
            block.min_y = (block.min_y + depth_trim).min(block.max_y.saturating_sub(6));
        }
        BlockFrontage::South => {
            block.max_y = block.max_y.saturating_sub(depth_trim).max(block.min_y + 6);
        }
    }
    let cross_span = if matches!(block.frontage, BlockFrontage::North | BlockFrontage::South) {
        block.max_x - block.min_x + 1
    } else {
        block.max_y - block.min_y + 1
    };
    if cross_span >= 9 {
        let trim_low = ((hash >> 8) & 1) as u16;
        let trim_high = ((hash >> 9) & 1) as u16;
        if matches!(block.frontage, BlockFrontage::North | BlockFrontage::South) {
            block.min_x += trim_low;
            block.max_x -= trim_high;
        } else {
            block.min_y += trim_low;
            block.max_y -= trim_high;
        }
    }
    block
}

fn derive_maintenance_service_space(plan: &mut LogicalPlan) {
    let active = plan
        .points()
        .filter(|point| plan.get(*point) != Space::Exterior)
        .collect::<BTreeSet<_>>();
    let service = active
        .iter()
        .flat_map(|point| cardinal_cells(*point, plan.width, plan.height))
        .filter(|point| !active.contains(point))
        .collect::<BTreeSet<_>>();
    for point in service {
        plan.set(point, Space::Maintenance);
    }
    bridge_interdepartment_service_gaps(plan);
}

fn bridge_interdepartment_service_gaps(plan: &mut LogicalPlan) {
    const SEARCH: u16 = 6;
    let exterior = plan
        .points()
        .filter(|point| plan.get(*point) == Space::Exterior)
        .collect::<Vec<_>>();
    let department_in_direction = |plan: &LogicalPlan, point: CellPoint, dx: i16, dy: i16| {
        (1..=SEARCH).find_map(|distance| {
            let x = i32::from(point.x) + i32::from(dx) * i32::from(distance);
            let y = i32::from(point.y) + i32::from(dy) * i32::from(distance);
            if x < 0 || y < 0 || x >= i32::from(plan.width) || y >= i32::from(plan.height) {
                return None;
            }
            match plan.get(CellPoint {
                x: u16::try_from(x).ok()?,
                y: u16::try_from(y).ok()?,
            }) {
                Space::Room { department, .. } | Space::Common(department) => Some(department),
                Space::Public | Space::Maintenance | Space::Exterior => None,
            }
        })
    };
    for point in exterior {
        let west = department_in_direction(plan, point, -1, 0);
        let east = department_in_direction(plan, point, 1, 0);
        let south = department_in_direction(plan, point, 0, -1);
        let north = department_in_direction(plan, point, 0, 1);
        let separates_departments = west.zip(east).is_some_and(|(left, right)| left != right)
            || south.zip(north).is_some_and(|(bottom, top)| bottom != top);
        if separates_departments {
            plan.set(point, Space::Maintenance);
        }
    }
}

fn pack_architectural_department(
    plan: &mut LogicalPlan,
    department: &DepartmentRequest,
    block: DepartmentBlock,
    next_room_id: &mut u16,
    seed: u64,
) -> Result<(), LayoutError> {
    let horizontal_hall = matches!(block.frontage, BlockFrontage::East | BlockFrontage::West);
    let axis_offset =
        (hash64(seed ^ u64::from(department.id) ^ 0x6861_6c6c_5f61_7869) % 3) as i16 - 1;
    let mut hall_axis = if horizontal_hall {
        let margin = ((block.max_y - block.min_y) / 2).min(2);
        u16::try_from(
            (i16::try_from(block.min_y + (block.max_y - block.min_y) / 2).unwrap_or(0)
                + axis_offset)
                .clamp(
                    i16::try_from(block.min_y + margin).unwrap_or(0),
                    i16::try_from(block.max_y - margin).unwrap_or(0),
                ),
        )
        .unwrap_or(block.min_y + (block.max_y - block.min_y) / 2)
    } else {
        let margin = ((block.max_x - block.min_x) / 2).min(2);
        u16::try_from(
            (i16::try_from(block.min_x + (block.max_x - block.min_x) / 2).unwrap_or(0)
                + axis_offset)
                .clamp(
                    i16::try_from(block.min_x + margin).unwrap_or(0),
                    i16::try_from(block.max_x - margin).unwrap_or(0),
                ),
        )
        .unwrap_or(block.min_x + (block.max_x - block.min_x) / 2)
    };
    // A centered spine in a shallow department consumes the only depth that
    // can satisfy real authored rooms (for example a 7x3 reception), leaving
    // two-tile strips which only compact closets can occupy. Put the spine on
    // one edge of shallow blocks. The room bay then retains the full remaining
    // depth and later portal construction connects it without inventing a
    // second cross-corridor through the department.
    let shallow_axis_hash = hash64(seed ^ u64::from(department.id) ^ 0x7368_616c_6c6f_775f);
    if horizontal_hall && block.max_y - block.min_y < 6 {
        hall_axis = if shallow_axis_hash & 1 == 0 {
            block.min_y
        } else {
            block.max_y
        };
    } else if !horizontal_hall && block.max_x - block.min_x < 6 {
        hall_axis = if shallow_axis_hash & 1 == 0 {
            block.min_x
        } else {
            block.max_x
        };
    }
    // End-cap rooms need enough depth for a real authored activity cluster;
    // two logical cells routinely rasterized into the suite's tiny-room tail.
    let terminal_depth = 2u16;
    // A full-width terminal room blocks the department spine. Splitting that
    // end cap then strands all but one child room behind another room. Keep
    // the compact spine continuous and partition rooms along its sides.
    let use_terminal_room = false;
    let mut hall_min_x = block.min_x;
    let mut hall_max_x = block.max_x;
    let mut hall_min_y = block.min_y;
    let mut hall_max_y = block.max_y;
    let terminal = if use_terminal_room {
        match block.frontage {
            BlockFrontage::East => {
                hall_min_x = block.min_x + terminal_depth;
                Some((
                    block.min_x,
                    block.min_x + terminal_depth - 1,
                    block.min_y,
                    block.max_y,
                ))
            }
            BlockFrontage::West => {
                hall_max_x = block.max_x - terminal_depth;
                Some((
                    block.max_x - terminal_depth + 1,
                    block.max_x,
                    block.min_y,
                    block.max_y,
                ))
            }
            BlockFrontage::North => {
                hall_min_y = block.min_y + terminal_depth;
                Some((
                    block.min_x,
                    block.max_x,
                    block.min_y,
                    block.min_y + terminal_depth - 1,
                ))
            }
            BlockFrontage::South => {
                hall_max_y = block.max_y - terminal_depth;
                Some((
                    block.min_x,
                    block.max_x,
                    block.max_y - terminal_depth + 1,
                    block.max_y,
                ))
            }
        }
    } else {
        None
    };
    let center = CellPoint {
        x: if horizontal_hall {
            block.min_x + (block.max_x - block.min_x) / 2
        } else {
            hall_axis
        },
        y: if horizontal_hall {
            hall_axis
        } else {
            block.min_y + (block.max_y - block.min_y) / 2
        },
    };
    plan.department_centers.insert(department.id, center);

    for y in block.min_y..=block.max_y {
        for x in block.min_x..=block.max_x {
            let point = CellPoint { x, y };
            if ((horizontal_hall && y == hall_axis) || (!horizontal_hall && x == hall_axis))
                && x >= hall_min_x
                && x <= hall_max_x
                && y >= hall_min_y
                && y <= hall_max_y
                && plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
        }
    }
    // Shallow blocks need a two-module circulation band. With one row, the
    // remaining five modules rasterize to fourteen floor tiles—deeper than
    // any authored room envelope—and the splitter is forced to cut across
    // frontage. Two rows leave an eleven-tile-deep bay that can be divided
    // only along the hall while every resulting room retains direct frontage.
    if horizontal_hall && block.max_y - block.min_y < 6 {
        let inner_y = if hall_axis == block.min_y {
            hall_axis + 1
        } else {
            hall_axis - 1
        };
        for x in block.min_x..=block.max_x {
            let point = CellPoint { x, y: inner_y };
            if plan.get(point) != Space::Public {
                plan.set(point, Space::Common(department.id));
            }
        }
    } else if !horizontal_hall && block.max_x - block.min_x < 6 {
        let inner_x = if hall_axis == block.min_x {
            hall_axis + 1
        } else {
            hall_axis - 1
        };
        for y in block.min_y..=block.max_y {
            let point = CellPoint { x: inner_x, y };
            if plan.get(point) != Space::Public {
                plan.set(point, Space::Common(department.id));
            }
        }
    } else if horizontal_hall {
        for y in block.min_y + 4..=block.max_y.saturating_sub(4) {
            for x in block.min_x..=block.max_x {
                let point = CellPoint { x, y };
                if plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
            }
        }
    } else {
        for x in block.min_x + 4..=block.max_x.saturating_sub(4) {
            for y in block.min_y..=block.max_y {
                let point = CellPoint { x, y };
                if plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
            }
        }
    }

    // Do not pre-carve a perpendicular cross through every department. Room
    // frontage branches are derived after packing, from actual door demand;
    // carving them up front fragments otherwise valid authored envelopes.

    let mut variants = department
        .room_types
        .iter()
        .filter(|room| room.max_count > 0)
        .collect::<Vec<_>>();
    variants.sort_by_key(|room| {
        (
            room.name.clone(),
            Reverse(room.ideal_area.max(room.content_area)),
            room.id,
        )
    });
    variants.dedup_by(|left, right| left.name == right.name);
    if variants.is_empty() {
        return Err(LayoutError(format!(
            "department {} has no authored room programs",
            department.id
        )));
    }

    let mut zones = Vec::new();
    if horizontal_hall {
        if block.min_y < hall_axis {
            let count = 2;
            for (min_x, max_x) in
                partition_axis_weighted(hall_min_x, hall_max_x, count, seed ^ 0x6c)
            {
                zones.push((min_x, max_x, block.min_y, hall_axis - 1));
            }
        }
        if hall_axis < block.max_y {
            let count = 2;
            for (min_x, max_x) in
                partition_axis_weighted(hall_min_x, hall_max_x, count, seed ^ 0x72)
            {
                zones.push((min_x, max_x, hall_axis + 1, block.max_y));
            }
        }
    } else {
        if block.min_x < hall_axis {
            let count = 2;
            for (min_y, max_y) in
                partition_axis_weighted(hall_min_y, hall_max_y, count, seed ^ 0x6d)
            {
                zones.push((block.min_x, hall_axis - 1, min_y, max_y));
            }
        }
        if hall_axis < block.max_x {
            let count = 2;
            for (min_y, max_y) in
                partition_axis_weighted(hall_min_y, hall_max_y, count, seed ^ 0x75)
            {
                zones.push((hall_axis + 1, block.max_x, min_y, max_y));
            }
        }
    }
    if let Some((min_x, max_x, min_y, max_y)) = terminal {
        let width = max_x - min_x + 1;
        let height = max_y - min_y + 1;
        if width >= 8 && width > height {
            for (part_min, part_max) in
                partition_axis_weighted(min_x, max_x, 2, seed ^ 0x0074_6572_6d78)
            {
                zones.push((part_min, part_max, min_y, max_y));
            }
        } else if height >= 8 && height > width {
            for (part_min, part_max) in
                partition_axis_weighted(min_y, max_y, 2, seed ^ 0x0074_6572_6d79)
            {
                zones.push((min_x, max_x, part_min, part_max));
            }
        } else {
            zones.push((min_x, max_x, min_y, max_y));
        }
    }
    zones.retain(|(min_x, max_x, min_y, max_y)| min_x <= max_x && min_y <= max_y);
    // Split every rectangular bay until it fits an authored content envelope.
    // The former area-only assignment could label a 100-tile bay as a
    // 30-tile reception and leave the decorator no principled way to fill it.
    let mut room_shapes = Vec::new();
    let mut provisional_types = Vec::new();
    for (min_x, max_x, min_y, max_y) in zones {
        let shape = (min_y..=max_y)
            .flat_map(|y| (min_x..=max_x).map(move |x| CellPoint { x, y }))
            .filter(|point| plan.get(*point) == Space::Exterior)
            .collect::<BTreeSet<_>>();
        for component in connected_components(&shape, plan.width, plan.height) {
            let partitions = split_shape_for_authored_rooms(
                &component,
                &department.room_types,
                plan.width,
                plan.height,
                8,
                Some(horizontal_hall),
            )
            .or_else(|| {
                // Unusual clipped bays may not divide along the preferred
                // frontage axis. Split them normally, then let the minimal
                // branch pass connect only the resulting back room(s).
                split_shape_for_authored_rooms(
                    &component,
                    &department.room_types,
                    plan.width,
                    plan.height,
                    8,
                    None,
                )
            });
            let Some(partitions) = partitions else {
                return Err(LayoutError(format!(
                    "department {} has a bay that cannot fit even a compact authored room",
                    department.id
                )));
            };
            for (partition, provisional) in partitions {
                room_shapes.push(partition);
                provisional_types.push(provisional);
            }
        }
    }
    let required_room_count = department
        .room_types
        .iter()
        .fold(BTreeMap::<&str, usize>::new(), |mut counts, room| {
            counts
                .entry(room.name.as_str())
                .and_modify(|count| *count = (*count).max(usize::from(room.min_count)))
                .or_insert(usize::from(room.min_count));
            counts
        })
        .values()
        .sum::<usize>();
    let available_semantics = department
        .room_types
        .iter()
        .map(|room| room.name.as_str())
        .collect::<BTreeSet<_>>()
        .len();
    let minimum_room_count = required_room_count.max(available_semantics.min(3));
    while room_shapes.len() < minimum_room_count {
        let candidate = (0..room_shapes.len())
            .filter_map(|index| {
                force_split_authored_shape(
                    &room_shapes[index],
                    &department.room_types,
                    plan.width,
                    plan.height,
                    Some(horizontal_hall),
                )
                .map(|replacement| (index, replacement))
            })
            .max_by_key(|(index, _)| projected_room_tile_area(&room_shapes[*index]));
        let Some((index, replacement)) = candidate else {
            break;
        };
        room_shapes.remove(index);
        provisional_types.remove(index);
        for (shape, provisional) in replacement {
            room_shapes.push(shape);
            provisional_types.push(provisional);
        }
    }
    // A collection of individually valid bays can still be impossible to
    // assign as a whole (for example, too many large bays that only the
    // department's anchor program can occupy). Keep partitioning the largest
    // splittable bay until the complete authored-program assignment succeeds.
    // This makes feasibility a construction invariant rather than a late
    // validation failure.
    let matched_types = loop {
        if let Some(matched) =
            match_room_variants_to_shapes(department, &provisional_types, &room_shapes)
        {
            break matched;
        }
        let candidate = (0..room_shapes.len())
            .filter_map(|index| {
                force_split_authored_shape(
                    &room_shapes[index],
                    &department.room_types,
                    plan.width,
                    plan.height,
                    Some(horizontal_hall),
                )
                .map(|replacement| (index, replacement))
            })
            .max_by_key(|(index, _)| projected_room_tile_area(&room_shapes[*index]));
        let Some((index, replacement)) = candidate else {
            let geometry = room_shapes
                .iter()
                .map(|shape| {
                    let (width, height) = projected_room_dimensions(shape);
                    format!("{}:{}x{}", projected_room_tile_area(shape), width, height)
                })
                .collect::<Vec<_>>()
                .join(",");
            let required = department
                .room_types
                .iter()
                .filter(|room| room.min_count > 0)
                .map(|room| format!("{}:{}@{}", room.name, room.min_count, room.id))
                .collect::<Vec<_>>()
                .join(",");
            return Err(LayoutError(format!(
                "department {} block {}x{} {:?} cannot assign required authored programs [{required}] to room geometry [{geometry}]",
                department.id,
                block.max_x - block.min_x + 1,
                block.max_y - block.min_y + 1,
                block.frontage,
            )));
        };
        room_shapes.remove(index);
        provisional_types.remove(index);
        for (shape, provisional) in replacement {
            room_shapes.push(shape);
            provisional_types.push(provisional);
        }
    };

    for (room_type, shape) in matched_types.into_iter().zip(room_shapes) {
        let room_id = *next_room_id;
        *next_room_id = next_room_id
            .checked_add(1)
            .ok_or_else(|| LayoutError("station contains too many rooms".into()))?;
        for point in shape {
            if plan.get(point) != Space::Public {
                plan.set(
                    point,
                    Space::Room {
                        department: department.id,
                        room: room_id,
                    },
                );
            }
        }
        plan.rooms.push(RoomPlan {
            id: room_id,
            department: department.id,
            room_type: room_type.clone(),
        });
    }
    Ok(())
}

fn partition_axis_weighted(
    minimum: u16,
    maximum: u16,
    desired: usize,
    seed: u64,
) -> Vec<(u16, u16)> {
    let length = usize::from(maximum - minimum + 1);
    let count = desired.min((length / 2).max(1));
    let mut sizes = vec![2usize; count];
    let mut remaining = length.saturating_sub(count * 2);
    let mut cursor = hash64(seed) as usize;
    while remaining > 0 {
        let index = cursor % count;
        sizes[index] += 1;
        cursor = hash64(cursor as u64 ^ seed) as usize;
        remaining -= 1;
    }
    let mut result = Vec::with_capacity(count);
    let mut start = minimum;
    for size in sizes {
        let end = (start + size as u16 - 1).min(maximum);
        result.push((start, end));
        start = end.saturating_add(1);
    }
    result
}

fn hash64(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
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

fn minimum_department_claim(request: &LayoutRequest, department_id: u16) -> usize {
    let Some(department) = request
        .departments
        .iter()
        .find(|department| department.id == department_id)
    else {
        return 12;
    };
    let required_room_tiles = minimum_semantic_room_tiles(department);
    let requested_tiles = usize::try_from(department.minimum_area)
        .unwrap_or(usize::MAX)
        .max(required_room_tiles);
    let tiles_per_cell = usize::from(INTERIOR).pow(2);
    requested_tiles.div_ceil(tiles_per_cell).max(12)
}

fn minimum_semantic_room_tiles(department: &super::model::DepartmentRequest) -> usize {
    let mut by_role = BTreeMap::<&str, (usize, bool)>::new();
    for room in department
        .room_types
        .iter()
        .filter(|room| room.max_count > 0)
    {
        let area = room_minimum_area(room);
        let standard_envelope = room.min_short_side >= 2 && area > usize::from(INTERIOR).pow(2);
        by_role
            .entry(room.name.as_str())
            .and_modify(|(known_area, known_standard)| {
                if standard_envelope && !*known_standard {
                    *known_area = area;
                    *known_standard = true;
                } else if standard_envelope == *known_standard {
                    *known_area = (*known_area).min(area);
                }
            })
            .or_insert((area, standard_envelope));
    }
    by_role.values().map(|(area, _)| *area).sum()
}

fn target_department_claim(request: &LayoutRequest, department_id: u16) -> usize {
    // Internal maintenance and the local hall are carved after macro claiming.
    // Reserve enough logical territory for those networks without allowing
    // them to consume the authored room-area guarantee.
    let required_rooms = request
        .departments
        .iter()
        .find(|department| department.id == department_id)
        .map(|department| {
            department
                .room_types
                .iter()
                .map(|room| usize::from(room.min_count))
                .sum::<usize>()
        })
        .unwrap_or(4);
    minimum_department_claim(request, department_id)
        .saturating_add(required_rooms)
        .saturating_add(4)
}

fn claim_transfer_candidate(
    plan: &LogicalPlan,
    donor: u16,
    recipient: u16,
    protected_center: CellPoint,
    minimum_donor_cells: usize,
    seed: u64,
) -> Option<CellPoint> {
    let mut boundary = plan
        .points()
        .filter(|point| {
            plan.get(*point).department() == Some(donor)
                && *point != protected_center
                && plan
                    .neighbors(*point)
                    .any(|neighbor| plan.get(neighbor).department() == Some(recipient))
        })
        .collect::<Vec<_>>();
    boundary.sort_by_key(|point| {
        (
            cell_distance(*point, protected_center),
            hash_cell(seed ^ u64::from(recipient), *point),
        )
    });
    boundary.into_iter().find(|candidate| {
        let remaining = plan
            .points()
            .filter(|point| *point != *candidate && plan.get(*point).department() == Some(donor))
            .collect::<BTreeSet<_>>();
        remaining.len() >= minimum_donor_cells
            && cells_connected(&remaining, plan.width, plan.height)
    })
}

#[allow(dead_code)]
fn rebalance_department_claims_legacy(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
    centers: &[CellPoint],
) -> Result<(), LayoutError> {
    let center_by_department = request
        .departments
        .iter()
        .zip(centers)
        .map(|(department, center)| (department.id, *center))
        .collect::<BTreeMap<_, _>>();
    let total_claimed = plan
        .points()
        .filter(|point| plan.get(*point).department().is_some())
        .count();
    // Diffuse excess territory across connected claim boundaries. This is a
    // bounded local equalizer, not the previous path-search repair: every move
    // strictly reduces the largest adjacent normalized size difference and
    // preserves the donor's connectivity.
    for _ in 0..total_claimed.saturating_mul(2) {
        let counts = request
            .departments
            .iter()
            .map(|department| {
                (
                    department.id,
                    plan.points()
                        .filter(|point| plan.get(*point).department() == Some(department.id))
                        .count(),
                )
            })
            .collect::<BTreeMap<_, _>>();
        let mut candidates = Vec::new();
        for point in plan.points() {
            let Some(donor) = plan.get(point).department() else {
                continue;
            };
            if point == center_by_department[&donor] {
                continue;
            }
            let donor_fill = counts[&donor].saturating_mul(1_000_000)
                / target_department_claim(request, donor).max(1);
            for recipient in plan
                .neighbors(point)
                .filter_map(|neighbor| plan.get(neighbor).department())
                .collect::<BTreeSet<_>>()
            {
                if recipient == donor {
                    continue;
                }
                let recipient_fill = counts[&recipient].saturating_mul(1_000_000)
                    / target_department_claim(request, recipient).max(1);
                if donor_fill > recipient_fill.saturating_add(10_000) {
                    candidates.push((donor_fill - recipient_fill, point, donor, recipient));
                }
            }
        }
        candidates.sort_by_key(|(difference, point, donor, recipient)| {
            (
                Reverse(*difference),
                cell_distance(*point, center_by_department[recipient]),
                hash_cell(request.settings.seed ^ u64::from(*donor), *point),
            )
        });
        let mut moved = false;
        for (_, point, donor, recipient) in candidates {
            if plan.get(point).department() != Some(donor)
                || counts[&donor] <= minimum_department_claim(request, donor)
            {
                continue;
            }
            let donor_fill = counts[&donor].saturating_mul(1_000_000)
                / target_department_claim(request, donor).max(1);
            let recipient_fill = counts[&recipient].saturating_mul(1_000_000)
                / target_department_claim(request, recipient).max(1);
            if donor_fill <= recipient_fill.saturating_add(10_000) {
                continue;
            }
            let remaining = plan
                .points()
                .filter(|candidate| {
                    *candidate != point && plan.get(*candidate).department() == Some(donor)
                })
                .collect::<BTreeSet<_>>();
            if !cells_connected(&remaining, plan.width, plan.height) {
                continue;
            }
            plan.set(point, Space::Common(recipient));
            moved = true;
            break;
        }
        if !moved {
            break;
        }
    }
    let mut claim_sizes = Vec::new();
    for department in &request.departments {
        let count = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .count();
        if count < minimum_department_claim(request, department.id) {
            return Err(LayoutError(format!(
                "department {} retained only {count} cells",
                department.id
            )));
        }
        claim_sizes.push(count);
    }
    let smallest = claim_sizes.iter().copied().min().unwrap_or(1).max(1);
    let largest = claim_sizes.iter().copied().max().unwrap_or(smallest);
    if largest.saturating_mul(2) > smallest.saturating_mul(5) {
        let details = request
            .departments
            .iter()
            .zip(&claim_sizes)
            .map(|(department, count)| {
                format!(
                    "{}={count}/{}",
                    department.id,
                    target_department_claim(request, department.id)
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        let component_details = connected_components(
            &plan
                .points()
                .filter(|point| plan.get(*point).department().is_some())
                .collect(),
            plan.width,
            plan.height,
        )
        .into_iter()
        .map(|component| {
            let owners = component
                .iter()
                .filter_map(|point| plan.get(*point).department())
                .collect::<BTreeSet<_>>();
            format!("{}:{owners:?}", component.len())
        })
        .collect::<Vec<_>>()
        .join("|");
        return Err(LayoutError(format!(
            "department claims remain imbalanced ({smallest}..{largest} cells; {details}; components {component_details})"
        )));
    }
    return Ok(());

    #[allow(unreachable_code)]
    {
        let total_claimed = plan
            .points()
            .filter(|point| plan.get(*point).department().is_some())
            .count();
        let minimums = request
            .departments
            .iter()
            .map(|department| {
                (
                    department.id,
                    minimum_department_claim(request, department.id),
                )
            })
            .collect::<BTreeMap<_, _>>();
        let minimum_total = minimums.values().sum::<usize>();
        if minimum_total > total_claimed {
            return Err(LayoutError(format!(
                "department minimums require {minimum_total} cells but only {total_claimed} are claimable"
            )));
        }
        let weights = request
            .departments
            .iter()
            .map(|department| {
                (
                    department.id,
                    target_department_claim(request, department.id),
                )
            })
            .collect::<BTreeMap<_, _>>();
        let weight_total = weights.values().sum::<usize>().max(1);
        let excess = total_claimed - minimum_total;
        let mut targets = minimums.clone();
        let mut assigned = minimum_total;
        for department in &request.departments {
            let share = excess.saturating_mul(weights[&department.id]) / weight_total;
            targets.insert(department.id, minimums[&department.id] + share);
            assigned += share;
        }
        // Integer division leaves only a handful of cells. Distribute them
        // deterministically so the target sum remains exactly the claimable area.
        for department in request.departments.iter().cycle() {
            if assigned >= total_claimed {
                break;
            }
            *targets
                .get_mut(&department.id)
                .expect("department target exists") += 1;
            assigned += 1;
        }
        let center_by_department = request
            .departments
            .iter()
            .zip(centers)
            .map(|(department, center)| (department.id, *center))
            .collect::<BTreeMap<_, _>>();
        for _ in 0..total_claimed.saturating_mul(8) {
            let counts = request
                .departments
                .iter()
                .map(|department| {
                    (
                        department.id,
                        plan.points()
                            .filter(|point| plan.get(*point).department() == Some(department.id))
                            .count(),
                    )
                })
                .collect::<BTreeMap<_, _>>();
            if request
                .departments
                .iter()
                .all(|department| counts[&department.id] >= targets[&department.id])
            {
                break;
            }
            let recipient = request
                .departments
                .iter()
                .filter(|department| counts[&department.id] < targets[&department.id])
                .max_by_key(|department| {
                    (
                        targets[&department.id] - counts[&department.id],
                        Reverse(department.id),
                    )
                })
                .map(|department| department.id)
                .expect("an underfull department exists");
            let mut adjacency = BTreeMap::<u16, BTreeSet<u16>>::new();
            for point in plan.points() {
                let Some(owner) = plan.get(point).department() else {
                    continue;
                };
                for neighbor in plan.neighbors(point) {
                    let Some(other) = plan.get(neighbor).department() else {
                        continue;
                    };
                    if owner != other {
                        adjacency.entry(owner).or_default().insert(other);
                    }
                }
            }
            let mut frontier = VecDeque::from([recipient]);
            let mut previous = BTreeMap::<u16, u16>::new();
            let mut surplus_donor = None;
            while let Some(current) = frontier.pop_front() {
                if current != recipient && counts[&current] > targets[&current] {
                    surplus_donor = Some(current);
                    break;
                }
                for neighbor in adjacency.get(&current).into_iter().flatten() {
                    if *neighbor != recipient
                        && !previous.contains_key(neighbor)
                        && claim_transfer_candidate(
                            plan,
                            *neighbor,
                            current,
                            center_by_department[neighbor],
                            minimums[neighbor],
                            request.settings.seed,
                        )
                        .is_some()
                    {
                        previous.insert(*neighbor, current);
                        frontier.push_back(*neighbor);
                    }
                }
            }
            let Some(surplus_donor) = surplus_donor else {
                break;
            };
            let mut path = vec![surplus_donor];
            while *path.last().expect("path is nonempty") != recipient {
                let current = *path.last().expect("path is nonempty");
                path.push(previous[&current]);
            }
            path.reverse();
            for edge in path.windows(2) {
                let edge_recipient = edge[0];
                let edge_donor = edge[1];
                let moved = claim_transfer_candidate(
                    plan,
                    edge_donor,
                    edge_recipient,
                    center_by_department[&edge_donor],
                    minimums[&edge_donor],
                    request.settings.seed,
                );
                let Some(moved) = moved else {
                    return Err(LayoutError(format!(
                        "cannot route balanced claim from department {edge_donor} to {edge_recipient}"
                    )));
                };
                plan.set(moved, Space::Common(edge_recipient));
            }
        }
        let final_counts = request
            .departments
            .iter()
            .map(|department| {
                (
                    department.id,
                    plan.points()
                        .filter(|point| plan.get(*point).department() == Some(department.id))
                        .count(),
                )
            })
            .collect::<BTreeMap<_, _>>();
        for department in &request.departments {
            let target = targets[&department.id];
            let tolerance = (target / 5).max(3);
            if final_counts[&department.id].abs_diff(target) > tolerance {
                return Err(LayoutError(format!(
                    "department {} retained {} cells against balanced target {target}",
                    department.id, final_counts[&department.id]
                )));
            }
        }
        Ok(())
    }
}

/// Turns surplus departmental concourse into the station's service network.
/// Growth is monotonic from existing maintenance, so it cannot create an
/// isolated maintenance pocket. A cell is surrendered only if local
/// circulation remains one connected component, still reaches the public hall,
/// and every room retains at least one local-hall frontage.
/// Replace broad anonymous department floor with the smallest connected local
/// circulation tree that reaches the public hall and every room. Any omitted
/// module is returned for assignment to a real authored micro room.
fn match_room_variants_to_shapes<'a>(
    department: &'a super::model::DepartmentRequest,
    selected: &[&'a RoomType],
    shapes: &[BTreeSet<CellPoint>],
) -> Option<Vec<&'a RoomType>> {
    if selected.len() != shapes.len() {
        return None;
    }
    let mut candidates = shapes
        .iter()
        .enumerate()
        .map(|(shape_index, shape)| {
            let mut variants = department
                .room_types
                .iter()
                .filter(|variant| room_shape_fits(variant, shape))
                .collect::<Vec<_>>();
            variants.sort_by_key(|variant| {
                (
                    variant.name != selected[shape_index].name,
                    room_shape_score(variant, shape),
                    variant.id,
                )
            });
            (shape_index, variants)
        })
        .collect::<Vec<_>>();
    if candidates.iter().any(|(_, variants)| variants.is_empty()) {
        return None;
    }
    candidates.sort_by_key(|(shape_index, variants)| {
        (
            variants.len(),
            Reverse(projected_room_tile_area(&shapes[*shape_index])),
            *shape_index,
        )
    });

    // Minimum counts are a contract on an exact authored variant, not merely
    // on its semantic family. A compact "surgery" room must not satisfy the
    // catalog's required full surgery suite.
    let mut required_slots = department
        .room_types
        .iter()
        .flat_map(|room| {
            std::iter::repeat_n(
                (room.name.as_str(), Some(room.id)),
                usize::from(room.min_count),
            )
        })
        .collect::<Vec<_>>();
    let minimum_semantic_variety = department
        .room_types
        .iter()
        .map(|room| room.name.as_str())
        .collect::<BTreeSet<_>>()
        .len()
        .min(3)
        .min(shapes.len());
    for semantic in selected
        .iter()
        .map(|room| room.name.as_str())
        .chain(department.room_types.iter().map(|room| room.name.as_str()))
    {
        if required_slots
            .iter()
            .map(|(semantic, _)| *semantic)
            .collect::<BTreeSet<_>>()
            .len()
            >= minimum_semantic_variety
        {
            break;
        }
        if !required_slots
            .iter()
            .any(|(required_semantic, _)| *required_semantic == semantic)
            && candidates
                .iter()
                .any(|(_, variants)| variants.iter().any(|room| room.name == semantic))
        {
            required_slots.push((semantic, None));
        }
    }
    required_slots.sort_by_key(|(semantic, required_id)| {
        candidates
            .iter()
            .filter(|(_, variants)| {
                variants.iter().any(|room| {
                    room.name == *semantic
                        && required_id.is_none_or(|required_id| room.id == required_id)
                })
            })
            .count()
    });

    let mut result = vec![None; shapes.len()];
    let mut counts = BTreeMap::new();
    let slot_candidates = required_slots
        .iter()
        .map(|(semantic, required_id)| {
            let mut choices = candidates
                .iter()
                .flat_map(|(shape_index, variants)| {
                    variants
                        .iter()
                        .filter(|room| {
                            room.name == *semantic
                                && required_id.is_none_or(|required_id| room.id == required_id)
                        })
                        .map(move |room| (*shape_index, *room))
                })
                .collect::<Vec<_>>();
            choices.sort_by_key(|(shape_index, room)| {
                (
                    room_shape_score(room, &shapes[*shape_index]),
                    *shape_index,
                    room.id,
                )
            });
            choices
        })
        .collect::<Vec<_>>();
    if slot_candidates.iter().any(Vec::is_empty) {
        return None;
    }
    let mut slot_order = (0..required_slots.len()).collect::<Vec<_>>();
    slot_order.sort_by_key(|slot| slot_candidates[*slot].len());
    let mut shape_owner = vec![None; shapes.len()];
    let mut chosen_variant = vec![None; required_slots.len()];
    fn augment_required<'a>(
        slot: usize,
        slot_candidates: &[Vec<(usize, &'a RoomType)>],
        shape_owner: &mut [Option<usize>],
        chosen_variant: &mut [Option<&'a RoomType>],
        visited_shapes: &mut [bool],
    ) -> bool {
        for &(shape, variant) in &slot_candidates[slot] {
            if visited_shapes[shape] {
                continue;
            }
            visited_shapes[shape] = true;
            if shape_owner[shape].is_none()
                || augment_required(
                    shape_owner[shape]
                        .expect("invariant: `||` short-circuit means this arm only runs when the left `is_none()` was false"),
                    slot_candidates,
                    shape_owner,
                    chosen_variant,
                    visited_shapes,
                )
            {
                shape_owner[shape] = Some(slot);
                chosen_variant[slot] = Some(variant);
                return true;
            }
        }
        false
    }
    for slot in slot_order {
        if !augment_required(
            slot,
            &slot_candidates,
            &mut shape_owner,
            &mut chosen_variant,
            &mut vec![false; shapes.len()],
        ) {
            return None;
        }
    }
    for (shape, slot) in shape_owner.into_iter().enumerate() {
        if let Some(slot) = slot {
            let variant = chosen_variant[slot]?;
            result[shape] = Some(variant);
            *counts.entry(variant.id).or_default() += 1;
        }
    }
    let mut semantic_counts = BTreeMap::<&str, usize>::new();
    for room in result.iter().flatten() {
        *semantic_counts.entry(room.name.as_str()).or_default() += 1;
    }
    for (shape_index, variants) in &candidates {
        if result[*shape_index].is_some() {
            continue;
        }
        let variant = variants
            .iter()
            .copied()
            .filter(|variant| {
                let limit = if variant.min_short_side <= 1 {
                    candidates.len()
                } else {
                    usize::from(variant.max_count)
                };
                counts.get(&variant.id).copied().unwrap_or(0) < limit
            })
            .min_by_key(|variant| {
                (
                    semantic_counts
                        .get(variant.name.as_str())
                        .copied()
                        .unwrap_or(0),
                    room_shape_score(variant, &shapes[*shape_index]),
                    variant.id,
                )
            })?;
        result[*shape_index] = Some(variant);
        *counts.entry(variant.id).or_default() += 1;
        *semantic_counts.entry(variant.name.as_str()).or_default() += 1;
    }
    Some(result.into_iter().map(Option::unwrap).collect())
}

/// Room growth operates on semantic programs, but an irregular partition can
/// produce a mix of full and compact envelopes. Replace only the geometry
/// variant of an existing semantic slot until every shape has at least one
/// compatible program; never invent a different room purpose.
fn extend_common_halls_to_every_room(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
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
        if (!required_broad_choke && selected_chokes.len() >= choke_target)
            || (!required_broad_choke
                && selected_chokes
                    .iter()
                    .any(|selected| cell_distance(selected.0, edge.0) < 4))
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

fn room_allows_main_corridor_entrance(room_type: &RoomType) -> bool {
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
fn repair_disconnected_room_ownership(plan: &mut LogicalPlan) -> Result<(), LayoutError> {
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

fn is_wall(class: TileClass) -> bool {
    matches!(
        class,
        TileClass::Hull | TileClass::Structure | TileClass::Partition
    )
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

/// Attaches one new branch to exactly one point of an existing public tree.
/// Keeping the branch away from every other tree edge prevents incidental
/// side-by-side contact from creating a closed hallway loop.
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
    let max_x = points
        .iter()
        .map(|point| point.x)
        .max()
        .expect("invariant: `min_x` above already rejected an empty `points`");
    let min_y = points
        .iter()
        .map(|point| point.y)
        .min()
        .expect("invariant: `min_x` above already rejected an empty `points`");
    let max_y = points
        .iter()
        .map(|point| point.y)
        .max()
        .expect("invariant: `min_x` above already rejected an empty `points`");
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
        assert_eq!(STATION_MAINTENANCE_WIDTH, 2);
        assert_eq!(INTERIOR, STATION_MAINTENANCE_WIDTH);
        assert_eq!(PITCH, STATION_MAINTENANCE_WIDTH + 1);
    }

    #[test]
    fn maintenance_never_forms_a_logical_room() {
        for seed in 1..=32 {
            let request = crate::station_layout::tests::request(seed);
            let layout = generate_station_layout(&request)
                .unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            let index =
                |x: u16, y: u16| usize::from(y) * usize::from(layout.width) + usize::from(x);
            for y in 0..layout.height.saturating_sub(PITCH) {
                for x in 0..layout.width.saturating_sub(PITCH) {
                    assert!(
                        !(0..=PITCH).all(|dy| (0..=PITCH).all(|dx| {
                            layout.tiles[index(x + dx, y + dy)].class == TileClass::Maintenance
                        })),
                        "seed {seed} has a room-sized maintenance block at {x},{y}"
                    );
                }
            }
        }
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
