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
            let public_ratio = public_circulation_quality(&station);
            let public_congestion = public_congestion_quality(&station);
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
            // These are candidate-ranking metrics, not validity constraints.
            // A structurally valid live seed must never fail because every
            // deterministic candidate is wider than the preferred envelope.
            if public_ratio > u32::MAX || public_congestion > u32::MAX {
                return Err(LayoutError(format!(
                    "public circulation exceeds the authored-map envelope ({public_ratio}‰ ratio, {public_congestion}‰ local congestion)"
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

fn public_circulation_quality(station: &StationLayout) -> u32 {
    let room_tiles = station
        .tiles
        .iter()
        .filter(|tile| tile.class == TileClass::Room)
        .count()
        .max(1);
    let public_tiles = station
        .tiles
        .iter()
        .filter(|tile| tile.class == TileClass::Public)
        .count();
    (public_tiles.saturating_mul(1000) / room_tiles) as u32
}

fn public_congestion_quality(station: &StationLayout) -> u32 {
    const WINDOW: u16 = 12;
    if station.width < WINDOW || station.height < WINDOW {
        return 0;
    }
    let mut worst = 0usize;
    for origin_y in 0..=station.height - WINDOW {
        for origin_x in 0..=station.width - WINDOW {
            let public = (origin_y..origin_y + WINDOW)
                .flat_map(|y| (origin_x..origin_x + WINDOW).map(move |x| Point { x, y }))
                .filter(|point| station.tile(*point).class == TileClass::Public)
                .count();
            worst = worst.max(public);
        }
    }
    (worst.saturating_mul(1000) / usize::from(WINDOW).pow(2)) as u32
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

fn department_coverage_quality(station: &StationLayout) -> u32 {
    let mut worst_millis = 0u32;
    for department in &station.departments {
        let room_tiles = station
            .tiles
            .iter()
            .filter(|tile| tile.class == TileClass::Room && tile.owner == Some(department.id))
            .count();
        let local_tiles = station
            .tiles
            .iter()
            .filter(|tile| tile.class == TileClass::Local && tile.owner == Some(department.id))
            .count();
        let ratio = if room_tiles == 0 {
            u32::MAX
        } else {
            (local_tiles.saturating_mul(1000) / room_tiles) as u32
        };
        worst_millis = worst_millis.max(ratio);
    }
    worst_millis
}

fn maintenance_coverage_quality(station: &StationLayout) -> u32 {
    let room_tiles = station
        .tiles
        .iter()
        .filter(|tile| tile.class == TileClass::Room)
        .count()
        .max(1);
    let maintenance_tiles = station
        .tiles
        .iter()
        .filter(|tile| tile.class == TileClass::Maintenance)
        .count();
    (maintenance_tiles.saturating_mul(1000) / room_tiles) as u32
}

fn maintenance_congestion_quality(station: &StationLayout) -> u32 {
    const WINDOW: u16 = 12;
    if station.width < WINDOW || station.height < WINDOW {
        return 0;
    }
    let mut worst = 0usize;
    for origin_y in 0..=station.height - WINDOW {
        for origin_x in 0..=station.width - WINDOW {
            let mut maintenance = 0usize;
            for y in origin_y..origin_y + WINDOW {
                for x in origin_x..origin_x + WINDOW {
                    if station.tile(Point { x, y }).class == TileClass::Maintenance {
                        maintenance += 1;
                    }
                }
            }
            worst = worst.max(maintenance);
        }
    }
    (worst.saturating_mul(1000) / usize::from(WINDOW).pow(2)) as u32
}

fn room_size_quality(station: &StationLayout) -> (u32, u32) {
    let room_count = station.rooms.len().max(1);
    let total_tiles = station
        .rooms
        .iter()
        .map(|room| room.tiles.len())
        .sum::<usize>();
    let tiny_rooms = station
        .rooms
        .iter()
        .filter(|room| room.tiles.len() <= 16)
        .count();
    (
        (total_tiles.saturating_mul(1000) / room_count) as u32,
        (tiny_rooms.saturating_mul(1000) / room_count) as u32,
    )
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

fn sculpt_architectural_outline(plan: &mut LogicalPlan, seed: u64) {
    let departments = plan
        .rooms
        .iter()
        .map(|room| room.department)
        .collect::<BTreeSet<_>>();
    for department in departments {
        let mut room_sizes = BTreeMap::<u16, usize>::new();
        for point in plan.points() {
            if let Space::Room {
                department: owner,
                room,
            } = plan.get(point)
                && owner == department
            {
                *room_sizes.entry(room).or_default() += 1;
            }
        }
        let mut candidates = plan
            .points()
            .filter_map(|point| {
                let Space::Room {
                    department: owner,
                    room,
                } = plan.get(point)
                else {
                    return None;
                };
                if owner != department || room_sizes.get(&room).copied().unwrap_or(0) <= 2 {
                    return None;
                }
                let west = point.x == 0
                    || plan.get(CellPoint {
                        x: point.x - 1,
                        y: point.y,
                    }) == Space::Exterior;
                let east = point.x + 1 >= plan.width
                    || plan.get(CellPoint {
                        x: point.x + 1,
                        y: point.y,
                    }) == Space::Exterior;
                let south = point.y == 0
                    || plan.get(CellPoint {
                        x: point.x,
                        y: point.y - 1,
                    }) == Space::Exterior;
                let north = point.y + 1 >= plan.height
                    || plan.get(CellPoint {
                        x: point.x,
                        y: point.y + 1,
                    }) == Space::Exterior;
                ((west || east) && (south || north)).then_some((point, room))
            })
            .collect::<Vec<_>>();
        candidates.sort_by_key(|(point, room)| {
            hash_cell(seed ^ u64::from(department) ^ u64::from(*room), *point)
        });
        let notch_count =
            1 + usize::try_from(hash64(seed ^ u64::from(department)) & 1).unwrap_or(0);
        let mut notched_rooms = BTreeSet::new();
        for (point, room) in candidates {
            if notched_rooms.contains(&room) {
                continue;
            }
            let Some(contract) = plan.rooms.iter().find(|planned| planned.id == room) else {
                continue;
            };
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
            if cells_connected(&remaining, plan.width, plan.height)
                && room_shape_fits(&contract.room_type, &remaining)
            {
                plan.set(point, Space::Exterior);
                notched_rooms.insert(room);
                if notched_rooms.len() >= notch_count {
                    break;
                }
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
    if horizontal_hall && block.max_y - block.min_y + 1 <= 6 {
        hall_axis = if shallow_axis_hash & 1 == 0 {
            block.min_y
        } else {
            block.max_y
        };
    } else if !horizontal_hall && block.max_x - block.min_x + 1 <= 6 {
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
            {
                if plan.get(point) != Space::Public {
                    plan.set(point, Space::Common(department.id));
                }
            }
        }
    }
    // Shallow blocks need a two-module circulation band. With one row, the
    // remaining five modules rasterize to fourteen floor tiles—deeper than
    // any authored room envelope—and the splitter is forced to cut across
    // frontage. Two rows leave an eleven-tile-deep bay that can be divided
    // only along the hall while every resulting room retains direct frontage.
    if horizontal_hall && block.max_y - block.min_y + 1 <= 6 {
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
    } else if !horizontal_hall && block.max_x - block.min_x + 1 <= 6 {
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
                partition_axis_weighted(min_x, max_x, 2, seed ^ 0x7465_726d_78)
            {
                zones.push((part_min, part_max, min_y, max_y));
            }
        } else if height >= 8 && height > width {
            for (part_min, part_max) in
                partition_axis_weighted(min_y, max_y, 2, seed ^ 0x7465_726d_79)
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

fn partition_axis(minimum: u16, maximum: u16, desired: usize) -> Vec<(u16, u16)> {
    let length = usize::from(maximum - minimum + 1);
    let count = desired.min(length.div_ceil(2).max(1));
    let mut result = Vec::with_capacity(count);
    let mut start = minimum;
    for index in 0..count {
        let remaining = usize::from(maximum - start + 1);
        let segments = count - index;
        let size = remaining.div_ceil(segments) as u16;
        let end = (start + size - 1).min(maximum);
        result.push((start, end));
        start = end.saturating_add(1);
    }
    result
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

fn build_content_aware_plan(request: &LayoutRequest) -> Result<LogicalPlan, LayoutError> {
    let trace = std::env::var_os("DQ_LAYOUT_TRACE").is_some();
    let canvas_width = (request.settings.width - 3) / PITCH;
    let canvas_height = (request.settings.height - 3) / PITCH;
    // The supplied dimensions are a canvas ceiling, not a command to fill the
    // entire z-level. Size the actual hull from authored department demand;
    // filling a 112x112 canvas with a small catalog was the source of thousand-
    // tile anonymous department concourses.
    let demanded_cells = request
        .departments
        .iter()
        .map(|department| {
            let required_tiles = usize::try_from(department.minimum_area)
                .unwrap_or(usize::MAX)
                .max(minimum_semantic_room_tiles(department));
            required_tiles
                .div_ceil(usize::from(INTERIOR).pow(2))
                .max(12)
        })
        .sum::<usize>();
    // Scale from authored demand rather than filling the entire canvas. A
    // logical cell expands to a multi-tile module at rasterization time. Six
    // modules per demand cell leaves room for circulation and maintenance
    // without creating territory the authored catalog cannot furnish.
    // Keep a large station without handing the room partitioner an effectively
    // empty second station's worth of residual floor. Ten logical cells per
    // demand cell leaves generous circulation/maintenance and yields useful
    // 30-80 tile rooms on the raster grid.
    let target_cells = demanded_cells.saturating_mul(6);
    let mut target_side = 15u16;
    while usize::from(target_side).pow(2) < target_cells {
        target_side = target_side.saturating_add(1);
    }
    let catalog_has_variants = request.departments.iter().any(|department| {
        department
            .room_types
            .iter()
            .map(|room| room.name.as_str())
            .collect::<BTreeSet<_>>()
            .len()
            < department.room_types.len()
    });
    let width = if catalog_has_variants {
        target_side.min(canvas_width).max(15)
    } else {
        canvas_width
    };
    let height = if catalog_has_variants {
        target_side.min(canvas_height).max(15)
    } else {
        canvas_height
    };
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
        maintenance_barriers: BTreeSet::new(),
        department_centers: BTreeMap::new(),
        department_edges: Vec::new(),
    };
    let silhouette: BTreeSet<_> = plan
        .points()
        .filter(|point| {
            if catalog_has_variants {
                in_seeded_silhouette(*point, width, height, request.settings.seed)
            } else {
                in_rounded_silhouette(*point, width, height)
            }
        })
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
    if trace {
        eprintln!(
            "layout: boundary extracted ({} cells)",
            outer_maintenance.len()
        );
    }
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
    if trace {
        eprintln!("layout: silhouette complete");
    }
    let mut centers = place_centers(request, &silhouette, &outer_maintenance, &mut rng)?;
    let frontages: Vec<_> = centers
        .iter()
        .map(|center| frontage_toward_center(*center, width, height))
        .collect();
    let mut public = BTreeSet::new();
    let hub = CellPoint {
        x: (i32::from(width / 2) + i32::from(rng.signed(1))) as u16,
        y: (i32::from(height / 2) + i32::from(rng.signed(1))) as u16,
    };
    // Connect each department to the existing public tree at its nearest point.
    // Independently rasterizing every abstract MST edge as an L path allowed
    // those paths to cross and form accidental loops, which enclosed seven
    // wildly unequal department islands. Incremental first-contact routing is
    // physically acyclic: each new branch stops as soon as it reaches the
    // already-connected hall.
    public.insert(frontages[0]);
    let mut connected = BTreeSet::from([0usize]);
    while connected.len() < frontages.len() {
        let child = (0..frontages.len())
            .filter(|index| !connected.contains(index))
            .min_by_key(|index| {
                (
                    public
                        .iter()
                        .map(|hall| cell_distance(frontages[*index], *hall))
                        .min()
                        .unwrap_or(u16::MAX),
                    hash_cell(request.settings.seed ^ *index as u64, frontages[*index]),
                )
            })
            .ok_or_else(|| LayoutError("public hall has no unconnected department".into()))?;
        let parent = connected
            .iter()
            .copied()
            .min_by_key(|index| cell_distance(frontages[*index], frontages[child]))
            .expect("the public tree has a connected root");
        let allowed = silhouette
            .difference(&outer_maintenance)
            .copied()
            .collect::<BTreeSet<_>>();
        let branch =
            attach_branch_to_public_tree(frontages[child], &public, &allowed, width, height)
                .ok_or_else(|| {
                    LayoutError("cannot attach department to public hall tree".into())
                })?;
        public.extend(branch);
        plan.department_edges.push((
            request.departments[parent].id,
            request.departments[child].id,
        ));
        connected.insert(child);
    }
    for point in &public {
        plan.set(*point, Space::Public);
    }
    if trace {
        eprintln!("layout: public graph complete");
    }
    for index in 0..centers.len() {
        if public.contains(&centers[index]) || cell_distance(centers[index], hub) <= 4 {
            centers[index] = silhouette
                .iter()
                .copied()
                .filter(|point| !public.contains(point) && !outer_maintenance.contains(point))
                .filter(|point| {
                    center_has_clear_core(*point, &silhouette, &public, &outer_maintenance)
                })
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
    // Removing tiny hall-cut components may invalidate a center that was valid
    // before cleanup. Relocate it onto a real 2x2 claimable core now, before
    // ownership growth consumes the stale coordinate.
    for index in 0..centers.len() {
        if claimable.contains(&centers[index])
            && center_has_core(centers[index], &claimable, &BTreeSet::new())
        {
            continue;
        }
        centers[index] = claimable
            .iter()
            .copied()
            .filter(|point| center_has_core(*point, &claimable, &BTreeSet::new()))
            .filter(|point| {
                centers.iter().enumerate().all(|(other_index, other)| {
                    other_index == index || cell_distance(*other, *point) >= 4
                })
            })
            .min_by_key(|point| {
                (
                    cell_distance(*point, centers[index]),
                    hash_cell(request.settings.seed ^ index as u64, *point),
                )
            })
            .ok_or_else(|| {
                LayoutError("cannot relocate department center after component cleanup".into())
            })?;
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
            .filter(|point| center_has_clear_core(*point, &silhouette, &public, &outer_maintenance))
            .min_by_key(|point| {
                (
                    cell_distance(*point, hub),
                    hash_cell(request.settings.seed ^ donor_index as u64, *point),
                )
            })
            .ok_or_else(|| LayoutError("department region has no floor".into()))?;
    }
    // Public circulation can divide the claimable station into lobes. Seeding
    // each lobe once is insufficient: a large lobe with one center becomes one
    // enormous department while several centers fight over a small lobe.
    // Allocate center counts proportionally to component area before claiming.
    let mut desired_centers = vec![1usize; claim_components.len()];
    for _ in claim_components.len()..centers.len() {
        let recipient = (0..claim_components.len())
            .max_by_key(|index| {
                (
                    claim_components[*index].len() * 1_000 / desired_centers[*index],
                    Reverse(*index),
                )
            })
            .expect("at least one claim component exists");
        desired_centers[recipient] += 1;
    }
    loop {
        let current_counts = claim_components
            .iter()
            .map(|component| {
                centers
                    .iter()
                    .filter(|center| component.contains(center))
                    .count()
            })
            .collect::<Vec<_>>();
        let Some(target_component) = (0..claim_components.len())
            .filter(|index| current_counts[*index] < desired_centers[*index])
            .max_by_key(|index| desired_centers[*index] - current_counts[*index])
        else {
            break;
        };
        let donor_component = (0..claim_components.len())
            .filter(|index| current_counts[*index] > desired_centers[*index])
            .max_by_key(|index| current_counts[*index] - desired_centers[*index])
            .ok_or_else(|| LayoutError("cannot balance department centers across lobes".into()))?;
        let donor_index = centers
            .iter()
            .enumerate()
            .filter(|(_, center)| claim_components[donor_component].contains(center))
            .max_by_key(|(index, center)| {
                (
                    cell_distance(**center, hub),
                    hash_cell(request.settings.seed ^ *index as u64, **center),
                )
            })
            .map(|(index, _)| index)
            .expect("donor component has a center");
        centers[donor_index] = claim_components[target_component]
            .iter()
            .copied()
            .filter(|point| center_has_core(*point, &claimable, &BTreeSet::new()))
            .filter(|point| {
                centers.iter().enumerate().all(|(other_index, other)| {
                    other_index == donor_index || cell_distance(*other, *point) >= 4
                })
            })
            .max_by_key(|point| {
                (
                    centers
                        .iter()
                        .enumerate()
                        .filter(|(index, _)| *index != donor_index)
                        .filter(|(_, center)| claim_components[target_component].contains(center))
                        .map(|(_, center)| cell_distance(*center, *point))
                        .min()
                        .unwrap_or(u16::MAX),
                    hash_cell(request.settings.seed ^ donor_index as u64, *point),
                )
            })
            .ok_or_else(|| LayoutError("balanced department lobe has no center core".into()))?;
    }
    for (department, center) in request.departments.iter().zip(&centers) {
        plan.department_centers.insert(department.id, *center);
    }
    if trace {
        eprintln!("layout: centers balanced");
    }

    grow_department_claims(request, &mut plan, &silhouette, &centers, &public, &mut rng)?;
    if trace {
        eprintln!("layout: department claims complete");
    }
    insert_internal_maintenance(&mut plan, request)?;
    if trace {
        eprintln!("layout: maintenance complete");
    }
    assign_department_common_and_rooms(&mut plan, request, &mut rng)?;
    if trace {
        eprintln!("layout: rooms complete");
    }
    assign_portals(&mut plan, request)?;
    if trace {
        eprintln!("layout: portals complete");
    }
    validate_logical_plan(&plan, request)?;
    Ok(plan)
}

fn in_seeded_silhouette(point: CellPoint, width: u16, height: u16, seed: u64) -> bool {
    let x = i32::from(point.x);
    let y = i32::from(point.y);
    let w = i32::from(width);
    let h = i32::from(height);
    let margin = 2;
    let right = w - 1 - margin;
    let top = h - 1 - margin;
    if x < margin || x > right || y < margin || y > top {
        return false;
    }
    // A convex, asymmetric chamfered hull keeps the topology simple for room
    // claiming while avoiding the old rounded rectangle. Each corner receives
    // a stable seeded cut depth, so seeds differ in outline without producing
    // narrow appendages or disconnected bays.
    let span = (width.min(height) / 6).clamp(4, 8);
    let cut = |salt: u64| 3 + i32::try_from(hash64(seed ^ salt) % u64::from(span)).unwrap_or(0);
    let south_west = cut(0x11);
    let south_east = cut(0x22);
    let north_west = cut(0x33);
    let north_east = cut(0x44);
    let local_x = x - margin;
    let local_y = y - margin;
    let local_right = right - x;
    let local_top = top - y;
    local_x + local_y >= south_west
        && local_right + local_y >= south_east
        && local_x + local_top >= north_west
        && local_right + local_top >= north_east
}

fn in_rounded_silhouette(point: CellPoint, width: u16, height: u16) -> bool {
    let margin = 1i32;
    let radius = 3i32;
    let x = i32::from(point.x);
    let y = i32::from(point.y);
    let right = i32::from(width) - 1 - margin;
    let top = i32::from(height) - 1 - margin;
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
    x >= margin && x <= right && y >= margin && y <= top && dx * dx + dy * dy <= radius * radius + 1
}

fn hash64(mut value: u64) -> u64 {
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

fn place_centers(
    request: &LayoutRequest,
    silhouette: &BTreeSet<CellPoint>,
    maintenance: &BTreeSet<CellPoint>,
    rng: &mut Rng,
) -> Result<Vec<CellPoint>, LayoutError> {
    let width = silhouette.iter().map(|point| point.x).max().unwrap_or(0) + 1;
    let height = silhouette.iter().map(|point| point.y).max().unwrap_or(0) + 1;
    let centroid = CellPoint {
        x: width / 2,
        y: height / 2,
    };
    let candidates = silhouette
        .iter()
        .copied()
        .filter(|point| !maintenance.contains(point))
        .filter(|point| center_has_core(*point, silhouette, maintenance))
        .collect::<Vec<_>>();
    if candidates.len() < request.departments.len() {
        return Err(LayoutError(
            "not enough valid cells for department centres".into(),
        ));
    }

    // Seed one department near the centroid, then use deterministic farthest
    // point sampling. The old fixed eight-slot ring left the middle unowned
    // and gave corner departments enormous exterior wedges. Farthest sampling
    // adapts to every generated silhouette and supplies even spatial coverage
    // without forcing departments into an artificial compass rose.
    let mut centers = Vec::new();
    for index in 0..request.departments.len() {
        let candidate = candidates
            .iter()
            .copied()
            .filter(|point| {
                centers
                    .iter()
                    .all(|other| cell_distance(*other, *point) >= 4)
            })
            .min_by_key(|point| {
                if centers.is_empty() {
                    (
                        cell_distance(*point, centroid),
                        hash_cell(request.settings.seed ^ rng.0 ^ index as u64, *point),
                    )
                } else {
                    (
                        u16::MAX
                            - centers
                                .iter()
                                .map(|other| cell_distance(*other, *point))
                                .min()
                                .unwrap_or(0),
                        hash_cell(request.settings.seed ^ index as u64, *point),
                    )
                }
            })
            .ok_or_else(|| LayoutError("cannot place separated department centers".into()))?;
        centers.push(candidate);
    }
    // Relax the farthest-point seeds toward the centroids of their Voronoi
    // regions. This removes the edge bias of the initial sampling while
    // retaining organic, seed-dependent placement.
    for _ in 0..6 {
        let mut regions = vec![Vec::new(); centers.len()];
        for point in candidates.iter().copied() {
            let owner = centers
                .iter()
                .enumerate()
                .min_by_key(|(index, center)| {
                    (
                        cell_distance(**center, point),
                        hash_cell(request.settings.seed ^ *index as u64, point),
                    )
                })
                .map(|(index, _)| index)
                .expect("at least one department centre");
            regions[owner].push(point);
        }
        let previous = centers.clone();
        for index in 0..centers.len() {
            if regions[index].is_empty() {
                continue;
            }
            let centroid_x = regions[index]
                .iter()
                .map(|point| usize::from(point.x))
                .sum::<usize>()
                / regions[index].len();
            let centroid_y = regions[index]
                .iter()
                .map(|point| usize::from(point.y))
                .sum::<usize>()
                / regions[index].len();
            if let Some(candidate) = candidates
                .iter()
                .copied()
                .filter(|point| {
                    centers.iter().enumerate().all(|(other_index, other)| {
                        other_index == index || cell_distance(*other, *point) >= 4
                    })
                })
                .min_by_key(|point| {
                    (
                        usize::from(point.x).abs_diff(centroid_x)
                            + usize::from(point.y).abs_diff(centroid_y),
                        hash_cell(request.settings.seed ^ index as u64, *point),
                    )
                })
            {
                centers[index] = candidate;
            }
        }
        if centers == previous {
            break;
        }
    }
    Ok(centers)
}

fn center_has_core(
    center: CellPoint,
    silhouette: &BTreeSet<CellPoint>,
    maintenance: &BTreeSet<CellPoint>,
) -> bool {
    for base_x in [center.x.checked_sub(1), Some(center.x)]
        .into_iter()
        .flatten()
    {
        for base_y in [center.y.checked_sub(1), Some(center.y)]
            .into_iter()
            .flatten()
        {
            let cells = [
                CellPoint {
                    x: base_x,
                    y: base_y,
                },
                CellPoint {
                    x: base_x + 1,
                    y: base_y,
                },
                CellPoint {
                    x: base_x,
                    y: base_y + 1,
                },
                CellPoint {
                    x: base_x + 1,
                    y: base_y + 1,
                },
            ];
            if cells
                .iter()
                .all(|point| silhouette.contains(point) && !maintenance.contains(point))
            {
                return true;
            }
        }
    }
    false
}

fn center_has_clear_core(
    center: CellPoint,
    silhouette: &BTreeSet<CellPoint>,
    first: &BTreeSet<CellPoint>,
    second: &BTreeSet<CellPoint>,
) -> bool {
    for base_x in [center.x.checked_sub(1), Some(center.x)]
        .into_iter()
        .flatten()
    {
        for base_y in [center.y.checked_sub(1), Some(center.y)]
            .into_iter()
            .flatten()
        {
            let cells = [
                CellPoint {
                    x: base_x,
                    y: base_y,
                },
                CellPoint {
                    x: base_x + 1,
                    y: base_y,
                },
                CellPoint {
                    x: base_x,
                    y: base_y + 1,
                },
                CellPoint {
                    x: base_x + 1,
                    y: base_y + 1,
                },
            ];
            if cells.iter().all(|point| {
                silhouette.contains(point) && !first.contains(point) && !second.contains(point)
            }) {
                return true;
            }
        }
    }
    false
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
    // Bootstrap every department with a chunky 2x2 logical core before the
    // multi-source claim. Pure point-seeded Voronoi growth can assign an ample
    // area as a two-cell-wide strip; no later room partition can fit several
    // center-activity programs into that geometry.
    for (index, center) in centers.iter().copied().enumerate() {
        let mut blocks = Vec::new();
        for x_offset in 0..2u16 {
            let Some(base_x) = center.x.checked_sub(x_offset) else {
                continue;
            };
            for y_offset in 0..2u16 {
                let Some(base_y) = center.y.checked_sub(y_offset) else {
                    continue;
                };
                let mut block = Vec::new();
                for dx in 0..2u16 {
                    for dy in 0..2u16 {
                        block.push(CellPoint {
                            x: base_x + dx,
                            y: base_y + dy,
                        });
                    }
                }
                if block
                    .iter()
                    .all(|point| claimable.contains(point) && !owner.contains_key(point))
                {
                    blocks.push(block);
                }
            }
        }
        blocks.sort_by_key(|block| {
            let centroid_x = block
                .iter()
                .map(|point| usize::from(point.x))
                .sum::<usize>()
                / block.len();
            let centroid_y = block
                .iter()
                .map(|point| usize::from(point.y))
                .sum::<usize>()
                / block.len();
            (
                usize::from(center.x).abs_diff(centroid_x)
                    + usize::from(center.y).abs_diff(centroid_y),
                hash_cell(request.settings.seed ^ index as u64, block[0]),
            )
        });
        let block = blocks.into_iter().next().ok_or_else(|| LayoutError(format!(
            "department {} at {:?} has no non-overlapping 2x2 macro core ({} claimable, {} already owned)",
            request.departments[index].id, center, claimable.len(), owner.len()
        )))?;
        for point in block {
            owner.insert(point, index);
        }
    }
    // Start with the true geometric partition. Public halls are holes in the
    // claimable domain, so a region can occasionally be cut into two pieces;
    // those detached pieces are transferred whole across a shared boundary
    // below instead of distorting every territory during growth.
    for point in claimable.iter().copied() {
        if owner.contains_key(&point) {
            continue;
        }
        let department_index = centers
            .iter()
            .enumerate()
            .min_by_key(|(index, center)| {
                (
                    cell_distance(**center, point),
                    hash_cell(request.settings.seed ^ *index as u64, point),
                )
            })
            .map(|(index, _)| index)
            .expect("validated requests always have department centres");
        owner.insert(point, department_index);
    }
    for department_index in 0..centers.len() {
        let cells = owner
            .iter()
            .filter_map(|(point, owner_index)| (*owner_index == department_index).then_some(*point))
            .collect::<BTreeSet<_>>();
        let components = connected_components(&cells, plan.width, plan.height);
        let keeper = components
            .iter()
            .position(|component| component.contains(&centers[department_index]))
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {} centre was cut out of its territory",
                    request.departments[department_index].id
                ))
            })?;
        for component in components
            .into_iter()
            .enumerate()
            .filter_map(|(index, component)| (index != keeper).then_some(component))
        {
            let recipient = component
                .iter()
                .flat_map(|point| cardinal_cells(*point, plan.width, plan.height))
                .filter_map(|neighbor| owner.get(&neighbor).copied())
                .filter(|candidate| *candidate != department_index)
                .min_by_key(|candidate| {
                    component
                        .iter()
                        .map(|point| cell_distance(centers[*candidate], *point))
                        .min()
                        .unwrap_or(u16::MAX)
                })
                .ok_or_else(|| {
                    LayoutError("detached department island has no adjacent territory".into())
                })?;
            for point in component {
                owner.insert(point, recipient);
            }
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

fn smooth_department_claims(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
    centers: &[CellPoint],
) {
    let protected = centers.iter().copied().collect::<BTreeSet<_>>();
    let width = plan.width;
    for _ in 0..8 {
        let mut changed = false;
        let snapshot = plan.cells.clone();
        let get = |point: CellPoint| {
            snapshot[usize::from(point.y) * usize::from(width) + usize::from(point.x)]
        };
        let candidates = plan
            .points()
            .filter(|point| !protected.contains(point))
            .filter_map(|point| {
                let current = get(point).department()?;
                let mut counts = BTreeMap::<u16, usize>::new();
                for neighbor in plan.neighbors(point) {
                    if let Some(owner) = get(neighbor).department() {
                        *counts.entry(owner).or_default() += 1;
                    }
                }
                let current_neighbors = counts.get(&current).copied().unwrap_or(0);
                let (&target, &target_neighbors) = counts
                    .iter()
                    .filter(|(owner, _)| **owner != current)
                    .max_by_key(|(owner, count)| (**count, Reverse(**owner)))?;
                (target_neighbors >= 2 && target_neighbors > current_neighbors).then_some((
                    point,
                    current,
                    target,
                    target_neighbors,
                ))
            })
            .collect::<Vec<_>>();
        for (point, current, target, _) in candidates {
            if plan.get(point).department() != Some(current)
                || !plan
                    .neighbors(point)
                    .any(|neighbor| plan.get(neighbor).department() == Some(target))
            {
                continue;
            }
            let remaining = plan
                .points()
                .filter(|candidate| {
                    *candidate != point && plan.get(*candidate).department() == Some(current)
                })
                .collect::<BTreeSet<_>>();
            if remaining.len() < minimum_department_claim(request, current)
                || !cells_connected(&remaining, plan.width, plan.height)
            {
                continue;
            }
            plan.set(point, Space::Common(target));
            changed = true;
        }
        if !changed {
            break;
        }
    }
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

fn validate_department_claims(
    plan: &LogicalPlan,
    request: &LayoutRequest,
    centers: &[CellPoint],
) -> Result<(), LayoutError> {
    let mut normalized_claims = Vec::with_capacity(request.departments.len());
    for (department, center) in request.departments.iter().zip(centers) {
        let claim = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .collect::<BTreeSet<_>>();
        if !claim.contains(center) {
            return Err(LayoutError(format!(
                "department {} does not own its centre at {center:?}",
                department.id
            )));
        }
        if claim.len() < minimum_department_claim(request, department.id) {
            return Err(LayoutError(format!(
                "department {} retained only {} cells",
                department.id,
                claim.len()
            )));
        }
        if !cells_connected(&claim, plan.width, plan.height) {
            return Err(LayoutError(format!(
                "department {} territory is disconnected",
                department.id
            )));
        }
        normalized_claims.push(
            claim.len().saturating_mul(1_000_000)
                / usize::try_from(department.desired_area).unwrap_or(1).max(1),
        );
    }
    let smallest = normalized_claims.iter().copied().min().unwrap_or(1).max(1);
    let largest = normalized_claims.iter().copied().max().unwrap_or(smallest);
    // Organic hulls and public-hall cuts legitimately vary department area;
    // reject true runaway ownership, not a harmless 2.6:1 edge department.
    if largest > smallest.saturating_mul(4) {
        return Err(LayoutError(format!(
            "geometric department partition is imbalanced ({smallest}..{largest} normalized)"
        )));
    }
    Ok(())
}

fn rebalance_department_claims(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
    centers: &[CellPoint],
) -> Result<(), LayoutError> {
    validate_department_claims(plan, request, centers)
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

fn insert_internal_maintenance(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
) -> Result<(), LayoutError> {
    let snapshot = plan.cells.clone();
    let snapshot_width = plan.width;
    let get = |point: CellPoint| {
        snapshot[usize::from(point.y) * usize::from(snapshot_width) + usize::from(point.x)]
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
        if remaining.len() >= minimum_department_claim(request, owner)
            && cells_connected(&remaining, plan.width, plan.height)
            && remaining.iter().any(|cell| {
                plan.neighbors(*cell)
                    .any(|neighbor| plan.get(neighbor) == Space::Public)
            })
        {
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
        let Some(path) =
            shortest_path_between_sets(&source, &root, &allowed, plan.width, plan.height)
        else {
            // A seam is only maintenance when it belongs to the connected
            // service network. If every possible connector would sever a
            // department, restore this isolated seam to its original claim;
            // retaining it is exactly what produced maintenance-shaped rooms.
            for point in &source {
                plan.set(*point, get(*point));
            }
            blocked_connectors.clear();
            continue;
        };
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
            if remaining.len() >= minimum_department_claim(request, owner)
                && cells_connected(&remaining, plan.width, plan.height)
                && remaining.iter().any(|cell| {
                    plan.neighbors(*cell)
                        .any(|neighbor| plan.get(neighbor) == Space::Public)
                })
            {
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
            for point in &source {
                plan.set(*point, get(*point));
            }
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
                remaining.len() >= minimum_department_claim(request, owner)
                    && cells_connected(&remaining, plan.width, plan.height)
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
                let first = BTreeSet::from([*public_neighbors
                    .iter()
                    .next()
                    .expect("invariant: checked len() >= 2 above")]);
                let last = BTreeSet::from([*public_neighbors
                    .iter()
                    .next_back()
                    .expect("invariant: checked len() >= 2 above")]);
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
                if remaining_department.len() < minimum_department_claim(request, department.id)
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
                    if remaining.len() < minimum_department_claim(request, owner)
                        || !cells_connected(&remaining, plan.width, plan.height)
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
        // Room-envelope variants do not imply a larger service network. One
        // short spur provides internal maintenance frontage without consuming
        // department-sized fields of usable room territory.
        let service_fingers = 1;
        let service_separation = 6;
        let service_base_depth = 2;
        let service_depth_variance = 2;
        let mut selected = Vec::new();
        for anchor in anchors {
            if selected.len() >= service_fingers
                || selected
                    .iter()
                    .any(|chosen| cell_distance(*chosen, anchor) < service_separation)
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
            let depth = service_base_depth
                + usize::try_from(
                    hash_cell(request.settings.seed ^ 0x6669_6e67_6572, anchor)
                        % service_depth_variance,
                )
                .unwrap_or(0);
            let mut carved_any = false;
            for point in path.into_iter().take(depth) {
                let mut remaining = department_cells.clone();
                remaining.remove(&point);
                if remaining.len() < minimum_department_claim(request, department.id)
                    || !cells_connected(&remaining, plan.width, plan.height)
                {
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
    thin_maintenance_fields(plan);
    for department in &request.departments {
        let cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point).department() == Some(department.id))
            .collect();
        if cells.len() < minimum_department_claim(request, department.id)
            || !cells_connected(&cells, plan.width, plan.height)
        {
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

fn thin_maintenance_fields(plan: &mut LogicalPlan) {
    loop {
        let maintenance: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Maintenance)
            .collect();
        let mut broad = Vec::new();
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
            if block.iter().all(|cell| maintenance.contains(cell)) {
                broad.extend(block);
            }
        }
        broad.sort_by_key(|point| {
            let has_owner = plan
                .neighbors(*point)
                .any(|neighbor| plan.get(neighbor).department().is_some());
            (
                !has_owner,
                std::cmp::Reverse(
                    cardinal_cells(*point, plan.width, plan.height)
                        .into_iter()
                        .filter(|neighbor| maintenance.contains(neighbor))
                        .count(),
                ),
            )
        });
        broad.dedup();
        let Some(removable) = broad.into_iter().find(|point| {
            let reduced: BTreeSet<_> = maintenance
                .iter()
                .copied()
                .filter(|cell| cell != point)
                .collect();
            let has_owner = plan
                .neighbors(*point)
                .any(|neighbor| plan.get(neighbor).department().is_some());
            !reduced.is_empty() && cells_connected(&reduced, plan.width, plan.height) && has_owner
        }) else {
            break;
        };
        let adjacent_owner = plan
            .neighbors(removable)
            .filter_map(|neighbor| plan.get(neighbor).department())
            .min_by_key(|owner| {
                plan.points()
                    .filter(|point| plan.get(*point).department() == Some(*owner))
                    .count()
            });
        let Some(owner) = adjacent_owner else {
            break;
        };
        plan.set(removable, Space::Common(owner));
    }
}

fn assign_department_common_and_rooms(
    plan: &mut LogicalPlan,
    request: &LayoutRequest,
    rng: &mut Rng,
) -> Result<(), LayoutError> {
    let mut next_room_id = 1u16;
    for department in &request.departments {
        if std::env::var_os("DQ_LAYOUT_TRACE").is_some() {
            eprintln!("layout: partitioning department {}", department.id);
        }
        let department_cells: BTreeSet<_> = plan
            .points()
            .filter(|point| plan.get(*point) == Space::Common(department.id))
            .collect();
        let mut frontage = department_cells
            .iter()
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| plan.get(neighbor) == Space::Public)
            })
            .min_by_key(|point| cell_distance(*point, plan.department_centers[&department.id]));
        if frontage.is_none() {
            // A connected service band may legitimately separate a department
            // from the public spine. Use the department-side maintenance
            // frontage; portal construction will place both access doors.
            frontage = department_cells.iter().copied().find(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| plan.get(neighbor) == Space::Maintenance)
            });
        }
        let frontage = frontage.ok_or_else(|| {
            LayoutError(format!(
                "department {} does not border its public hall",
                department.id
            ))
        })?;
        let requested_center =
            nearest_in_set(plan.department_centers[&department.id], &department_cells).ok_or_else(
                || LayoutError(format!("department {} has no owned center", department.id)),
            )?;
        let boundary: Vec<_> = department_cells
            .iter()
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| !department_cells.contains(&neighbor))
            })
            .collect();
        let center = department_cells
            .iter()
            .copied()
            .max_by_key(|point| {
                let clearance = boundary
                    .iter()
                    .map(|edge| cell_distance(*point, *edge))
                    .min()
                    .unwrap_or(0);
                (
                    clearance,
                    Reverse(cell_distance(*point, requested_center)),
                    Reverse(*point),
                )
            })
            .unwrap_or(requested_center);
        let mut common =
            shortest_path_in_set(frontage, center, &department_cells, plan.width, plan.height)
                .ok_or_else(|| {
                    LayoutError(format!(
                        "department {} frontage cannot reach its center",
                        department.id
                    ))
                })?;
        // This is the department's semantic spine, not merely temporary room
        // frontage. Preserve it through the later compaction pass so an
        // alternate service-edge route cannot replace the interior hallway.
        let primary_spine = common.clone();

        let maintenance_components =
            adjacent_components(&department_cells, Space::Maintenance, plan);
        // Maintenance is validated as one station-wide network. A department
        // therefore needs one intentional service connection, not a separate
        // orange local hallway branch to every place that network happens to
        // touch its boundary.
        if let Some(access) = maintenance_components
            .iter()
            .flat_map(|component| {
                department_cells.iter().copied().filter(|point| {
                    plan.neighbors(*point)
                        .any(|neighbor| component.contains(&neighbor))
                })
            })
            .min_by_key(|point| cell_distance(*point, center))
        {
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
        // Give every authored role one room before repeating any role.  A
        // department catalog is the design vocabulary DM supplied; treating
        // only min_count entries as rooms left most of the claimed territory
        // as anonymous local floor and made the required rooms enormous.
        // Frontage and partitioning are therefore planned for the complete
        // first pass through that vocabulary.
        // Add two optional programs per department without over-carving the
        // compact department into hallway branches. Additional role variety
        // comes from seed/catalog variation across generated stations.
        let catalog_room_limit = department
            .room_types
            .iter()
            .map(|room| usize::from(room.max_count))
            .sum::<usize>();
        // Cover large claims with a few controlled repeats instead of leaving
        // entire residual lobes as anonymous local circulation. Compact
        // variants make the smallest of these allocations intentional; the
        // cap keeps repetition below the authored vocabulary count.
        let maximum_room_area = department
            .room_types
            .iter()
            .filter(|room| room.max_count > 0)
            .map(|room| usize::from(room.max_width) * usize::from(room.max_height))
            .max()
            .unwrap_or(1)
            // A rare 11x11 authored program must not define the average room
            // capacity for an enlarged department. Use a practical 7x7
            // planning envelope so extra area produces additional rooms.
            .min(49)
            .max(1);
        let coverage_room_count = department_cells
            .len()
            .saturating_mul(usize::from(INTERIOR).pow(2))
            // Keep individual rooms comfortably below their authored maximum
            // while reserving roughly 40% for partitions and circulation.
            .saturating_mul(5)
            .div_ceil(maximum_room_area.saturating_mul(3))
            .max(required_count);
        let semantic_role_count = department
            .room_types
            .iter()
            .filter(|room| room.max_count > 0)
            .map(|room| room.name.as_str())
            .collect::<BTreeSet<_>>()
            .len();
        // Full, compact, and micro contracts share one semantic name. Cover the
        // territory with enough actual rooms, then let `room_instances` spread
        // those slots across the authored vocabulary before repeating roles.
        // Capping the slot count at the number of semantic names left every
        // large department with a giant anonymous local-hall field.
        let desired_room_count = coverage_room_count
            // A role is a real place, not a filler token. Excess territory is
            // returned to circulation/maintenance instead of cloning rooms.
            .min(semantic_role_count)
            .max(required_count)
            .min(catalog_room_limit);
        // A straight spine exposes many room frontages along the same run. Do
        // not carve one hallway branch per desired room: that was slicing broad
        // department floor into narrow residual ribbons which later became
        // enormous local-hall fields.
        let hallway_frontage_target = desired_room_count.max(required_count);
        // Grow only enough departmental circulation to provide the required
        // room frontages. The previous maximum-depth rule chased every remote
        // tile with a hallway finger before rooms existed. Those fingers sliced
        // otherwise healthy territory into 2-tile ribbons and made valid room
        // programs structurally impossible.
        for _ in 0..department_cells.len() {
            let frontage_count = department_cells
                .difference(&common)
                .filter(|point| {
                    plan.neighbors(**point)
                        .any(|neighbor| common.contains(&neighbor))
                })
                .count();
            if frontage_count >= hallway_frontage_target {
                break;
            }
            let target = department_cells
                .difference(&common)
                .copied()
                .max_by_key(|point| {
                    common
                        .iter()
                        .map(|hall| cell_distance(*hall, *point))
                        .min()
                        .unwrap_or(0)
                })
                .ok_or_else(|| {
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

        // Every non-circulation lobe becomes one or more rooms. Room seeds and
        // balanced growth divide broad territory; hallways must not pre-divide it
        // into narrow anonymous strips.
        let minimum_room_area = department
            .room_types
            .iter()
            .filter(|room| room.max_count > 0)
            .map(|room| room_minimum_area(room))
            .min()
            .unwrap_or(1);
        let minimum_short_side = department
            .room_types
            .iter()
            .filter(|room| room.max_count > 0)
            .map(|room| usize::from(room.min_short_side))
            .min()
            .unwrap_or(3);
        let undersized_lobes = connected_components(
            &department_cells.difference(&common).copied().collect(),
            plan.width,
            plan.height,
        )
        .into_iter()
        .filter(|component| {
            let (component_width, component_height) = projected_room_dimensions(component);
            projected_room_tile_area(component) < minimum_room_area
                || component_width.min(component_height) < minimum_short_side
        })
        .collect::<Vec<_>>();
        for lobe in undersized_lobes {
            common.extend(lobe);
        }
        // Absorbing an unusable bay can consume one of the frontage cells
        // counted above. Re-establish only the missing frontage here; do not
        // regrow the old depth-seeking hallway tree.
        while department_cells
            .difference(&common)
            .filter(|point| {
                plan.neighbors(**point)
                    .any(|neighbor| common.contains(&neighbor))
            })
            .count()
            < hallway_frontage_target
        {
            let target = department_cells
                .difference(&common)
                .copied()
                .max_by_key(|point| {
                    common
                        .iter()
                        .map(|hall| cell_distance(*hall, *point))
                        .min()
                        .unwrap_or(0)
                })
                .ok_or_else(|| {
                    LayoutError(format!(
                        "department {} cannot restore required room frontage",
                        department.id
                    ))
                })?;
            let origin = common
                .iter()
                .copied()
                .min_by_key(|hall| cell_distance(*hall, target))
                .ok_or_else(|| LayoutError("department circulation is empty".into()))?;
            let mut branch =
                shortest_path_in_set(origin, target, &department_cells, plan.width, plan.height)
                    .ok_or_else(|| LayoutError("cannot restore room frontage".into()))?;
            branch.remove(&target);
            let before = common.len();
            common.extend(branch);
            if common.len() == before {
                // The existing spine already reaches the best remaining cell.
                // Continue with the real frontage count instead of failing or
                // carving a duplicate hallway loop to satisfy a soft target.
                break;
            }
        }
        let repaired_lobes = connected_components(
            &department_cells.difference(&common).copied().collect(),
            plan.width,
            plan.height,
        );
        // Frontage restoration can cut off a tiny bay after the first cleanup
        // pass. Such a bay is circulation/utility space, never a room: retaining
        // it forces an otherwise valid authored program into impossible 2x2
        // geometry. Normalize once more after hallway repair.
        for lobe in repaired_lobes.iter().filter(|component| {
            let (component_width, component_height) = projected_room_dimensions(component);
            projected_room_tile_area(component) < minimum_room_area
                || component_width.min(component_height) < minimum_short_side
        }) {
            common.extend(lobe.iter().copied());
        }
        thin_common_fields(&mut common, &primary_spine, plan.width, plan.height);
        // Thinning can expose isolated one-cell bays that did not exist during
        // the pre-thin cleanup. They project to 2x2 physical rooms and cannot
        // carry even the compact authored program (door route + utility socket
        // + two fixtures). Normalize after the final hallway mutation as well.
        for lobe in connected_components(
            &department_cells.difference(&common).copied().collect(),
            plan.width,
            plan.height,
        )
        .iter()
        .filter(|component| {
            let (component_width, component_height) = projected_room_dimensions(component);
            projected_room_tile_area(component) < minimum_room_area
                || component_width.min(component_height) < minimum_short_side
        }) {
            common.extend(lobe.iter().copied());
        }
        let mut components = connected_components(
            &department_cells.difference(&common).copied().collect(),
            plan.width,
            plan.height,
        );
        components.sort_by_key(|component| Reverse(component.len()));
        // Ask the partitioner for the full authored vocabulary when the
        // existing hallway geometry naturally exposes enough frontages. The
        // hallway itself is only extended for `desired_count`, so compact
        // departments are not carved apart merely to force every optional
        // role into one station.
        let required_room_slots = desired_room_count.max(components.len());
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

        let mut candidates: Vec<_> = department_cells
            .difference(&common)
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| common.contains(&neighbor))
            })
            .collect();
        let frontage_candidates: BTreeSet<_> = candidates.iter().copied().collect();
        if candidates.len() < required_count {
            return Err(LayoutError(format!(
                "department {} has {} room frontages for {required_count} required rooms",
                department.id,
                candidates.len()
            )));
        }
        // Frontage-adjacent cells remain preferred, but center programs may
        // begin one logical cell deeper when a narrow hallway edge offers no
        // 2x2 activity lobe. Their grown room must still acquire a real common
        // boundary, which assign_portals validates later.
        for point in department_cells.difference(&common).copied() {
            let distance_to_common = common
                .iter()
                .map(|hall| cell_distance(*hall, point))
                .min()
                .unwrap_or(u16::MAX);
            if distance_to_common <= 2 && !candidates.contains(&point) {
                candidates.push(point);
            }
        }
        // Every initial room owns a distinct doorway frontage. Distance-two
        // cells are useful alternate seeds for center lobes, but are not extra
        // door slots; counting them here overbooked the hallway and forced
        // later floor into corridor/maintenance-shaped pseudo-rooms.
        instances.truncate(frontage_candidates.len());
        let mut seeds = choose_room_seeds(&components, &candidates, instances.len(), rng)?;
        // room_instances is ordered from the largest authored program to the
        // smallest. Pair those programs with seeds that own the broadest
        // nearest territory instead of depending on component iteration
        // order; otherwise a center-activity room can start in a shallow bay
        // while a reception seed consumes the only broad lobe.
        let available_room_floor: BTreeSet<_> =
            department_cells.difference(&common).copied().collect();
        let mut seed_capacity = vec![0usize; seeds.len()];
        let mut seed_center_blocks = vec![0usize; seeds.len()];
        for point in &available_room_floor {
            if let Some((index, _)) = seeds
                .iter()
                .enumerate()
                .min_by_key(|(index, seed)| (cell_distance(**seed, *point), *index))
            {
                seed_capacity[index] += 1;
            }
        }
        for (index, seed) in seeds.iter().enumerate() {
            for base_x in [seed.x.checked_sub(1), Some(seed.x)].into_iter().flatten() {
                for base_y in [seed.y.checked_sub(1), Some(seed.y)].into_iter().flatten() {
                    let Some(east) = base_x.checked_add(1) else {
                        continue;
                    };
                    let Some(north) = base_y.checked_add(1) else {
                        continue;
                    };
                    let block = [
                        CellPoint {
                            x: base_x,
                            y: base_y,
                        },
                        CellPoint { x: east, y: base_y },
                        CellPoint {
                            x: base_x,
                            y: north,
                        },
                        CellPoint { x: east, y: north },
                    ];
                    if block
                        .iter()
                        .all(|point| available_room_floor.contains(point))
                    {
                        seed_center_blocks[index] += 1;
                    }
                }
            }
        }
        let mut seed_order: Vec<_> = (0..seeds.len()).collect();
        seed_order.sort_by_key(|index| {
            (
                Reverse(seed_center_blocks[*index]),
                Reverse(seed_capacity[*index]),
                seeds[*index],
            )
        });
        seeds = seed_order.into_iter().map(|index| seeds[index]).collect();
        let (mut assignments, residual) = grow_rooms(
            &available_room_floor,
            &frontage_candidates,
            &seeds,
            &instances,
            plan.width,
            plan.height,
            rng,
        )?;
        if !residual.is_empty() {
            let mut semantic_counts = BTreeMap::<&str, usize>::new();
            for room in &instances {
                *semantic_counts.entry(room.name.as_str()).or_default() += 1;
            }
            for component in connected_components(&residual, plan.width, plan.height) {
                let merge = assignments
                    .iter()
                    .enumerate()
                    .filter(|(_, room)| {
                        component.iter().any(|point| {
                            plan.neighbors(*point)
                                .any(|neighbor| room.contains(&neighbor))
                        })
                    })
                    .filter_map(|(index, room)| {
                        let mut combined = room.clone();
                        combined.extend(component.iter().copied());
                        department
                            .room_types
                            .iter()
                            .filter(|variant| room_shape_fits(variant, &combined))
                            .min_by_key(|variant| {
                                (
                                    semantic_counts
                                        .get(variant.name.as_str())
                                        .copied()
                                        .unwrap_or(0),
                                    room_shape_score(variant, &combined),
                                    variant.id,
                                )
                            })
                            .map(|variant| {
                                (
                                    projected_room_tile_area(&combined),
                                    index,
                                    combined,
                                    variant,
                                )
                            })
                    })
                    .min_by_key(|(area, index, _, variant)| {
                        (
                            semantic_counts
                                .get(variant.name.as_str())
                                .copied()
                                .unwrap_or(0),
                            *area,
                            *index,
                        )
                    });
                if let Some((_, index, combined, variant)) = merge {
                    let old_name = instances[index].name.as_str();
                    if let Some(count) = semantic_counts.get_mut(old_name) {
                        *count = count.saturating_sub(1);
                    }
                    *semantic_counts.entry(variant.name.as_str()).or_default() += 1;
                    instances[index] = variant;
                    assignments[index] = combined;
                    continue;
                }
                let mut has_frontage = component.iter().any(|point| {
                    plan.neighbors(*point)
                        .any(|neighbor| common.contains(&neighbor))
                });
                if !has_frontage {
                    has_frontage = carve_residual_room_frontage(
                        &component,
                        &mut common,
                        &mut assignments,
                        &instances,
                        department,
                        plan.width,
                        plan.height,
                    );
                }
                if !has_frontage && component.len() <= 3 {
                    // A sub-room remnant with no legal doorway cannot be a
                    // maintenance room or an inaccessible closet. Absorb only
                    // this tightly bounded notch into department circulation;
                    // larger residuals remain hard errors and must be
                    // repartitioned by another deterministic candidate.
                    common.extend(component.iter().copied());
                    continue;
                }
                let room_type = department
                    .room_types
                    .iter()
                    .filter(|room| room.min_short_side <= 1)
                    .filter(|room| room_shape_fits(room, &component))
                    .min_by_key(|room| {
                        (
                            semantic_counts
                                .get(room.name.as_str())
                                .copied()
                                .unwrap_or(0),
                            room_shape_score(room, &component),
                            room.id,
                        )
                    });
                let Some(room_type) = room_type else {
                    // Residual geometry is not permission to fabricate dozens
                    // of utility closets. Preserve it as department
                    // circulation; the later compaction/service pass reduces
                    // it to a connected access skeleton or maintenance.
                    common.extend(component.iter().copied());
                    continue;
                };
                *semantic_counts.entry(room_type.name.as_str()).or_default() += 1;
                instances.push(room_type);
                seeds.push(
                    *component
                        .iter()
                        .next()
                        .ok_or_else(|| LayoutError("residual room component was empty".into()))?,
                );
                assignments.push(component);
            }
        }
        expand_excess_singletons(
            &mut assignments,
            &instances,
            &seeds,
            &mut common,
            &primary_spine,
            plan.width,
            plan.height,
        );
        // Optional rooms are real authored programs, not disposable geometry.
        // Keep their cells in the partition and let the constraint rebalance
        // repair undersized shapes. Dropping the first small optional shape
        // here was the direct source of giant anonymous local-floor regions.
        rebalance_shapes_for_programs(
            &mut assignments,
            &instances,
            &seeds,
            &mut common,
            plan.width,
            plan.height,
        );
        // Partition growth can leave a final one-module pocket even though the
        // pre-partition floor had no undersized lobes. If no authored variant
        // can inhabit it, make those few cells part of department circulation
        // and remove an optional program. Never fabricate a four-tile room that
        // cannot hold its doorway, utilities, and signature furnishing.
        let unusable_shapes = assignments
            .iter()
            .enumerate()
            .filter_map(|(index, shape)| {
                (!department
                    .room_types
                    .iter()
                    .any(|room| room_shape_fits(room, shape)))
                .then_some(index)
            })
            .collect::<Vec<_>>();
        for index in unusable_shapes.iter().rev().copied() {
            let replacement = split_shape_for_authored_rooms(
                &assignments[index],
                &department.room_types,
                plan.width,
                plan.height,
                8,
                None,
            );
            let Some(replacement) = replacement else {
                let displaced = instances[index];
                let semantic_count = instances
                    .iter()
                    .filter(|room| room.name == displaced.name)
                    .count();
                let required_count = department
                    .room_types
                    .iter()
                    .filter(|room| room.name == displaced.name)
                    .map(|room| usize::from(room.min_count))
                    .max()
                    .unwrap_or(0);
                if semantic_count <= required_count {
                    let replacement_slot = assignments
                        .iter()
                        .enumerate()
                        .filter(|(candidate, _)| *candidate != index)
                        .filter(|(candidate, _)| {
                            let current = instances[*candidate];
                            let current_count = instances
                                .iter()
                                .filter(|room| room.name == current.name)
                                .count();
                            let current_required = department
                                .room_types
                                .iter()
                                .filter(|room| room.name == current.name)
                                .map(|room| usize::from(room.min_count))
                                .max()
                                .unwrap_or(0);
                            current_count > current_required
                        })
                        .filter_map(|(candidate, shape)| {
                            department
                                .room_types
                                .iter()
                                .filter(|room| room.name == displaced.name)
                                .filter(|room| room_shape_fits(room, shape))
                                .min_by_key(|room| room_shape_score(room, shape))
                                .map(|room| (candidate, room))
                        })
                        .min_by_key(|(candidate, room)| {
                            room_shape_score(room, &assignments[*candidate])
                        });
                    let Some((replacement_slot, replacement_type)) = replacement_slot else {
                        return Err(LayoutError(format!(
                            "department {} cannot preserve required {} while absorbing unusable residual geometry",
                            department.id, displaced.name
                        )));
                    };
                    instances[replacement_slot] = replacement_type;
                }
                common.extend(assignments[index].iter().copied());
                assignments.remove(index);
                instances.remove(index);
                seeds.remove(index);
                continue;
            };
            assignments.remove(index);
            instances.remove(index);
            seeds.remove(index);
            for (shape, variant) in replacement {
                seeds.push(
                    *shape
                        .iter()
                        .next()
                        .ok_or_else(|| LayoutError("split room was empty".into()))?,
                );
                assignments.push(shape);
                instances.push(variant);
            }
        }
        // A few compact infill rooms are legitimate when an irregular
        // department boundary cannot be covered by the authored target count.
        // Keep a hard ceiling so residual space can never explode into the
        // hundreds of micro-rooms produced by the old fallback.
        let room_budget = desired_room_count.saturating_mul(2).saturating_add(4);
        if assignments.len() > room_budget {
            return Err(LayoutError(format!(
                "department {} produced {} rooms against a budget of {room_budget}",
                department.id,
                assignments.len()
            )));
        }
        let unusable_shapes = assignments
            .iter()
            .enumerate()
            .filter_map(|(index, shape)| {
                (!department
                    .room_types
                    .iter()
                    .any(|room| room_shape_fits(room, shape)))
                .then_some(index)
            })
            .collect::<Vec<_>>();
        if !unusable_shapes.is_empty() {
            let details = unusable_shapes
                .iter()
                .map(|index| {
                    let shape = &assignments[*index];
                    let (width, height) = projected_room_dimensions(shape);
                    format!(
                        "#{index} area={} {}x{}",
                        projected_room_tile_area(shape),
                        width,
                        height
                    )
                })
                .collect::<Vec<_>>()
                .join(", ");
            return Err(LayoutError(format!(
                "department {} produced {} partitions without an authored room envelope ({details})",
                department.id,
                unusable_shapes.len()
            )));
        }
        if assignments.len() < semantic_role_count.min(3) {
            return Err(LayoutError(format!(
                "department {} retained only {} authored room partitions",
                department.id,
                assignments.len()
            )));
        }
        let mut matched_types = match_room_variants_to_shapes(department, &instances, &assignments)
            .ok_or_else(|| {
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
            &primary_spine,
        );
        ensure_room_hall_frontages(
            &mut common,
            &mut assignments,
            &mut matched_types,
            plan.width,
            plan.height,
            department.id,
        )?;
        grow_maintenance_through_excess_common(plan, &mut common, &assignments);
        let residual =
            reduce_common_to_access_skeleton(plan, department.id, &mut common, &assignments)?;
        absorb_residual_into_rooms(
            &residual,
            &mut common,
            &mut assignments,
            &mut matched_types,
            &department.room_types,
            plan.width,
            plan.height,
        )?;
        grow_maintenance_through_excess_common(plan, &mut common, &assignments);
        // Residual infill can touch two separated lobes of the same room
        // across the reduced hallway skeleton. Preserve each lobe as its own
        // authored room instead of exporting one disconnected room ID.
        for index in (0..assignments.len()).rev() {
            let mut components = connected_components(&assignments[index], plan.width, plan.height);
            if components.len() <= 1 {
                continue;
            }
            components.sort_by_key(|component| Reverse(component.len()));
            assignments[index] = components.remove(0);
            let original_type = matched_types[index];
            for component in components {
                let room_type = std::iter::once(original_type)
                    .chain(department.room_types.iter())
                    .find(|room_type| room_shape_fits(room_type, &component))
                    .ok_or_else(|| {
                        LayoutError(format!(
                            "department {} disconnected room lobe has no authored envelope",
                            department.id
                        ))
                    })?;
                assignments.push(component);
                matched_types.push(room_type);
            }
        }
        if assignments.len() > room_budget {
            return Err(LayoutError(format!(
                "department {} disconnected-room repair exceeded its room budget",
                department.id
            )));
        }
        // Residual shaping may leave a sliver that satisfies no authored room
        // envelope. It is circulation/service space, not a reason to invent a
        // generic room or reject the whole station.
        for index in (0..assignments.len()).rev() {
            if department
                .room_types
                .iter()
                .any(|variant| room_shape_fits(variant, &assignments[index]))
            {
                continue;
            }
            common.extend(assignments.remove(index));
            matched_types.remove(index);
        }
        matched_types = match_room_variants_to_shapes(department, &matched_types, &assignments)
            .or_else(|| relaxed_room_variant_rematch(department, &matched_types, &assignments))
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {} has residual geometry with no authored room envelope",
                    department.id
                ))
            })?;
        let assignment_owner = assignments
            .iter()
            .enumerate()
            .flat_map(|(index, room)| room.iter().map(move |point| (*point, index)))
            .collect::<BTreeMap<_, _>>();
        if let Some(orphan_index) = assignments.iter().enumerate().position(|(index, room)| {
            let has_common = room.iter().any(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| common.contains(&neighbor))
            });
            let has_room_access = room.iter().any(|point| {
                plan.neighbors(*point).any(|neighbor| {
                    assignment_owner
                        .get(&neighbor)
                        .is_some_and(|neighbor_index| *neighbor_index != index)
                })
            });
            !has_common && !has_room_access
        }) {
            return Err(LayoutError(format!(
                "department {} rebalance left room {} ({:?}, seed {:?}) without common frontage",
                department.id,
                orphan_index,
                projected_room_dimensions(&assignments[orphan_index]),
                seeds.get(orphan_index)
            )));
        }
        for (room_type, cells) in matched_types.into_iter().zip(assignments) {
            if cells.is_empty() {
                return Err(LayoutError(format!(
                    "department {} produced an empty room",
                    department.id
                )));
            }
            if !room_shape_fits(room_type, &cells) {
                return Err(LayoutError(format!(
                    "department {} matched {} (variant {}) to incompatible geometry (area {})",
                    department.id,
                    room_type.name,
                    room_type.id,
                    projected_room_tile_area(&cells),
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
                room_type: room_type.clone(),
            });
        }
        if std::env::var_os("DQ_LAYOUT_TRACE").is_some() {
            eprintln!("layout: department {} partitioned", department.id);
        }
    }
    Ok(())
}

fn expand_excess_singletons(
    shapes: &mut [BTreeSet<CellPoint>],
    room_types: &[&RoomType],
    seeds: &[CellPoint],
    common: &mut BTreeSet<CellPoint>,
    protected: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) {
    let singleton_limit = shapes.len().div_ceil(6);
    while shapes.iter().filter(|shape| shape.len() == 1).count() > singleton_limit {
        let Some(recipient) = shapes.iter().position(|shape| shape.len() == 1) else {
            break;
        };
        let recipient_cell = *shapes[recipient]
            .iter()
            .next()
            .expect("singleton has a cell");
        let common_growth = cardinal_cells(recipient_cell, width, height)
            .into_iter()
            .filter(|cell| common.contains(cell) && !protected.contains(cell))
            .find(|cell| {
                let reduced = common
                    .iter()
                    .copied()
                    .filter(|candidate| candidate != cell)
                    .collect::<BTreeSet<_>>();
                if reduced.is_empty() || !cells_connected(&reduced, width, height) {
                    return false;
                }
                let mut expanded = shapes[recipient].clone();
                expanded.insert(*cell);
                room_types
                    .iter()
                    .any(|room| room_shape_within_maximum(room, &expanded))
                    && shapes.iter().enumerate().all(|(index, shape)| {
                        index == recipient
                            || shape.iter().any(|point| {
                                cardinal_cells(*point, width, height)
                                    .into_iter()
                                    .any(|neighbor| reduced.contains(&neighbor))
                            })
                    })
            });
        if let Some(cell) = common_growth {
            common.remove(&cell);
            shapes[recipient].insert(cell);
            continue;
        }
        let mut transfer = None;
        for donor in 0..shapes.len() {
            if donor == recipient || shapes[donor].len() <= 2 {
                continue;
            }
            for cell in shapes[donor].iter().copied() {
                if cell == seeds[donor]
                    || !cardinal_cells(cell, width, height)
                        .into_iter()
                        .any(|neighbor| neighbor == recipient_cell)
                {
                    continue;
                }
                let mut reduced = shapes[donor].clone();
                reduced.remove(&cell);
                if !cells_connected(&reduced, width, height)
                    || !reduced.iter().any(|point| {
                        cardinal_cells(*point, width, height)
                            .into_iter()
                            .any(|neighbor| common.contains(&neighbor))
                    })
                    || !room_types
                        .iter()
                        .any(|room| room_shape_within_maximum(room, &reduced))
                {
                    continue;
                }
                let mut expanded = shapes[recipient].clone();
                expanded.insert(cell);
                if room_types
                    .iter()
                    .any(|room| room_shape_within_maximum(room, &expanded))
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
            break;
        };
        shapes[donor].remove(&cell);
        shapes[recipient].insert(cell);
    }
}

fn thin_common_fields(
    common: &mut BTreeSet<CellPoint>,
    protected: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) {
    loop {
        let mut candidates = Vec::new();
        for point in common.iter().copied() {
            let Some(east) = point.x.checked_add(1) else {
                continue;
            };
            let Some(north) = point.y.checked_add(1) else {
                continue;
            };
            let block = [
                point,
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
            if block.iter().all(|cell| common.contains(cell)) {
                candidates.extend(block.into_iter().filter(|cell| !protected.contains(cell)));
            }
        }
        candidates.sort_by_key(|point| {
            Reverse(
                cardinal_cells(*point, width, height)
                    .into_iter()
                    .filter(|neighbor| common.contains(neighbor))
                    .count(),
            )
        });
        candidates.dedup();
        let Some(removable) = candidates.into_iter().find(|point| {
            let reduced = common
                .iter()
                .copied()
                .filter(|cell| cell != point)
                .collect::<BTreeSet<_>>();
            !reduced.is_empty() && cells_connected(&reduced, width, height)
        }) else {
            break;
        };
        common.remove(&removable);
    }
}

fn compact_department_circulation(
    plan: &LogicalPlan,
    department: u16,
    common: &mut BTreeSet<CellPoint>,
    rooms: &mut [BTreeSet<CellPoint>],
    room_types: &[&RoomType],
    primary_spine: &BTreeSet<CellPoint>,
) {
    loop {
        let mut changed = false;
        let candidates: Vec<_> = common.iter().copied().collect();
        for point in candidates {
            if primary_spine.contains(&point) {
                continue;
            }
            // Public frontage is the department's required entrance. Maintenance
            // frontage may be absorbed into a room, creating a useful service
            // door instead of preserving a hallway around the department edge.
            if plan
                .neighbors(point)
                .any(|neighbor| plan.get(neighbor) == Space::Public)
            {
                continue;
            }
            let mut adjacent_rooms: Vec<_> = rooms
                .iter()
                .enumerate()
                .filter(|(_, room)| {
                    plan.neighbors(point)
                        .any(|neighbor| room.contains(&neighbor))
                })
                .map(|(index, _)| index)
                .collect();
            adjacent_rooms.sort_by_key(|index| {
                (
                    projected_room_tile_area(&rooms[*index]),
                    room_shape_score(room_types[*index], &rooms[*index]),
                    *index,
                )
            });
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

/// Turns surplus departmental concourse into the station's service network.
/// Growth is monotonic from existing maintenance, so it cannot create an
/// isolated maintenance pocket. A cell is surrendered only if local
/// circulation remains one connected component, still reaches the public hall,
/// and every room retains at least one local-hall frontage.
fn grow_maintenance_through_excess_common(
    plan: &mut LogicalPlan,
    common: &mut BTreeSet<CellPoint>,
    rooms: &[BTreeSet<CellPoint>],
) {
    loop {
        let mut candidates = common
            .iter()
            .copied()
            .filter(|point| {
                plan.neighbors(*point)
                    .any(|neighbor| plan.get(neighbor) == Space::Maintenance)
            })
            .collect::<Vec<_>>();
        candidates.sort_by_key(|point| {
            (
                Reverse(
                    plan.neighbors(*point)
                        .filter(|neighbor| plan.get(*neighbor) == Space::Maintenance)
                        .count(),
                ),
                Reverse(
                    plan.neighbors(*point)
                        .filter(|neighbor| common.contains(neighbor))
                        .count(),
                ),
                *point,
            )
        });
        let removable = candidates.into_iter().find(|point| {
            let reduced = common
                .iter()
                .copied()
                .filter(|candidate| candidate != point)
                .collect::<BTreeSet<_>>();
            !reduced.is_empty()
                && cells_connected(&reduced, plan.width, plan.height)
                && reduced.iter().any(|hall| {
                    plan.neighbors(*hall)
                        .any(|neighbor| plan.get(neighbor) == Space::Public)
                })
                && rooms.iter().all(|room| {
                    room.iter().any(|room_cell| {
                        plan.neighbors(*room_cell)
                            .any(|neighbor| reduced.contains(&neighbor))
                    })
                })
        });
        let Some(removable) = removable else {
            break;
        };
        common.remove(&removable);
        plan.set(removable, Space::Maintenance);
    }
}

/// Replace broad anonymous department floor with the smallest connected local
/// circulation tree that reaches the public hall and every room. Any omitted
/// module is returned for assignment to a real authored micro room.
fn reduce_common_to_access_skeleton(
    plan: &mut LogicalPlan,
    department: u16,
    common: &mut BTreeSet<CellPoint>,
    rooms: &[BTreeSet<CellPoint>],
) -> Result<BTreeSet<CellPoint>, LayoutError> {
    if !common.iter().any(|point| {
        plan.neighbors(*point)
            .any(|neighbor| plan.get(neighbor) == Space::Public)
    }) {
        return Err(LayoutError(format!(
            "department {department} has no public frontage for its access skeleton"
        )));
    }
    if rooms.iter().any(|room| {
        !room.iter().any(|point| {
            plan.neighbors(*point)
                .any(|neighbor| common.contains(&neighbor))
        })
    }) {
        return Err(LayoutError(format!(
            "department {department} has a room without local-hall frontage"
        )));
    }

    let original = common.clone();
    let mut skeleton = BTreeSet::new();
    for component in connected_components(common, plan.width, plan.height) {
        let component_rooms = rooms
            .iter()
            .filter_map(|room| {
                let frontages = room
                    .iter()
                    .flat_map(|point| plan.neighbors(*point))
                    .filter(|point| component.contains(point))
                    .collect::<BTreeSet<_>>();
                (!frontages.is_empty()).then_some(frontages)
            })
            .collect::<Vec<_>>();
        let public_root = component.iter().copied().find(|point| {
            plan.neighbors(*point)
                .any(|neighbor| plan.get(neighbor) == Space::Public)
        });
        if component_rooms.is_empty() && public_root.is_none() {
            return Err(LayoutError(format!(
                "department {department} has ownerless residual circulation"
            )));
        }
        let root = public_root
            .or_else(|| {
                component_rooms
                    .first()
                    .and_then(|set| set.iter().copied().next())
            })
            .ok_or_else(|| LayoutError("local circulation component has no root".into()))?;
        let mut component_skeleton = BTreeSet::from([root]);
        let mut pending = component_rooms;
        while !pending.is_empty() {
            let mut best: Option<(usize, Vec<CellPoint>)> = None;
            for (index, frontages) in pending.iter().enumerate() {
                let path = shortest_path_between_sets(
                    frontages,
                    &component_skeleton,
                    &component,
                    plan.width,
                    plan.height,
                )
                .ok_or_else(|| {
                    LayoutError(format!(
                        "department {department} has an unreachable room frontage"
                    ))
                })?;
                if best
                    .as_ref()
                    .is_none_or(|(_, best_path)| path.len() < best_path.len())
                {
                    best = Some((index, path));
                }
            }
            let (index, path) = best.ok_or_else(|| {
                LayoutError(format!(
                    "department {department} could not extend its access skeleton"
                ))
            })?;
            component_skeleton.extend(path);
            pending.swap_remove(index);
        }
        // Every cell omitted from the hallway becomes a one-module authored
        // room, so the retained hallway must dominate the component: each
        // residual cell needs a cardinal frontage for its real door.
        loop {
            let target = component.iter().copied().find(|point| {
                !component_skeleton.contains(point)
                    && !plan
                        .neighbors(*point)
                        .any(|neighbor| component_skeleton.contains(&neighbor))
            });
            let Some(target) = target else {
                break;
            };
            let starts = BTreeSet::from([target]);
            let mut path = shortest_path_between_sets(
                &starts,
                &component_skeleton,
                &component,
                plan.width,
                plan.height,
            )
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {department} cannot dominate its residual room floor"
                ))
            })?;
            path.retain(|point| *point != target);
            component_skeleton.extend(path);
        }
        skeleton.extend(component_skeleton);
    }
    // Strip every redundant logical module from the access tree. Shortest-path
    // unions can leave parallel runs and 2x2 concourse blocks even though a
    // one-module-wide route reaches the same rooms. Removed modules become
    // authored room floor below.
    loop {
        let removable = skeleton.iter().copied().find(|point| {
            let reduced = skeleton
                .iter()
                .copied()
                .filter(|candidate| candidate != point)
                .collect::<BTreeSet<_>>();
            !reduced.is_empty()
                && cells_connected(&reduced, plan.width, plan.height)
                && reduced.iter().any(|hall| {
                    plan.neighbors(*hall)
                        .any(|neighbor| plan.get(neighbor) == Space::Public)
                })
                && rooms.iter().all(|room| {
                    room.iter().any(|room_cell| {
                        plan.neighbors(*room_cell)
                            .any(|neighbor| reduced.contains(&neighbor))
                    })
                })
        });
        let Some(removable) = removable else {
            break;
        };
        skeleton.remove(&removable);
    }
    if !rooms.iter().all(|room| {
        room.iter().any(|room_cell| {
            plan.neighbors(*room_cell)
                .any(|neighbor| skeleton.contains(&neighbor))
        })
    }) {
        return Err(LayoutError(format!(
            "department {department} access skeleton lost a room frontage"
        )));
    }
    let residual_rooms = original
        .difference(&skeleton)
        .copied()
        .collect::<BTreeSet<_>>();
    *common = skeleton;
    Ok(residual_rooms)
}

fn ensure_room_hall_frontages(
    common: &mut BTreeSet<CellPoint>,
    rooms: &mut Vec<BTreeSet<CellPoint>>,
    room_types: &mut Vec<&RoomType>,
    width: u16,
    height: u16,
    department: u16,
) -> Result<(), LayoutError> {
    loop {
        let Some(orphan_index) = rooms.iter().position(|room| {
            !room.iter().any(|point| {
                cardinal_cells(*point, width, height)
                    .into_iter()
                    .any(|neighbor| common.contains(&neighbor))
            })
        }) else {
            break;
        };
        let recipient = rooms
            .iter()
            .enumerate()
            .filter(|(index, _)| *index != orphan_index)
            .filter_map(|(index, room)| {
                let shared_edges = rooms[orphan_index]
                    .iter()
                    .flat_map(|point| cardinal_cells(*point, width, height))
                    .filter(|neighbor| room.contains(neighbor))
                    .count();
                (shared_edges > 0).then_some((Reverse(shared_edges), room.len(), index))
            })
            .min()
            .map(|(_, _, index)| index)
            .ok_or_else(|| {
                LayoutError(format!(
                    "department {department} has an isolated room without hall frontage"
                ))
            })?;
        let orphan_frontier = rooms[orphan_index]
            .iter()
            .flat_map(|point| cardinal_cells(*point, width, height))
            .filter(|point| rooms[recipient].contains(point))
            .collect::<BTreeSet<_>>();
        let allowed = rooms[recipient]
            .iter()
            .chain(common.iter())
            .copied()
            .collect::<BTreeSet<_>>();
        if let Some(path) =
            shortest_path_between_sets(&orphan_frontier, common, &allowed, width, height)
        {
            let cut = path
                .into_iter()
                .filter(|point| rooms[recipient].contains(point))
                .collect::<BTreeSet<_>>();
            let reduced = rooms[recipient]
                .difference(&cut)
                .copied()
                .collect::<BTreeSet<_>>();
            if !cut.is_empty()
                && !reduced.is_empty()
                && cells_connected(&reduced, width, height)
                && room_shape_within_maximum(room_types[recipient], &reduced)
            {
                rooms[recipient] = reduced;
                common.extend(cut);
                continue;
            }
        }
        let mut combined = rooms[recipient].clone();
        combined.extend(rooms[orphan_index].iter().copied());
        if !room_shape_within_maximum(room_types[recipient], &combined) {
            return Err(LayoutError(format!(
                "department {department} cannot give an isolated room a hall frontage without oversizing its neighbor"
            )));
        }
        let orphan = rooms.remove(orphan_index);
        room_types.remove(orphan_index);
        let recipient = recipient - usize::from(recipient > orphan_index);
        rooms[recipient].extend(orphan);
        if !cells_connected(&rooms[recipient], width, height) {
            return Err(LayoutError(format!(
                "department {department} could not merge an inaccessible room"
            )));
        }
    }
    Ok(())
}

fn absorb_residual_into_rooms<'a>(
    residual: &BTreeSet<CellPoint>,
    common: &mut BTreeSet<CellPoint>,
    rooms: &mut Vec<BTreeSet<CellPoint>>,
    room_types: &mut Vec<&'a RoomType>,
    variants: &'a [RoomType],
    width: u16,
    height: u16,
) -> Result<(), LayoutError> {
    let mut pending = residual.clone();
    while !pending.is_empty() {
        let mut best = None;
        for point in pending.iter().copied() {
            for (room_index, room) in rooms.iter().enumerate() {
                let shared_edges = cardinal_cells(point, width, height)
                    .into_iter()
                    .filter(|neighbor| room.contains(neighbor))
                    .count();
                if shared_edges == 0 {
                    continue;
                }
                let mut combined = room.clone();
                combined.insert(point);
                if !room_shape_within_maximum(room_types[room_index], &combined) {
                    continue;
                }
                let score = (
                    Reverse(shared_edges),
                    room.len(),
                    projected_room_dimensions(room)
                        .0
                        .abs_diff(projected_room_dimensions(room).1),
                    point,
                    room_index,
                );
                if best.as_ref().is_none_or(|(known, _, _)| score < *known) {
                    best = Some((score, point, room_index));
                }
            }
        }
        let Some((_, point, room_index)) = best else {
            let seed = pending
                .iter()
                .copied()
                .filter(|point| {
                    cardinal_cells(*point, width, height)
                        .into_iter()
                        .any(|neighbor| common.contains(&neighbor))
                })
                .min_by_key(|point| {
                    (
                        pending
                            .iter()
                            .map(|other| usize::from(cell_distance(*point, *other)))
                            .sum::<usize>(),
                        *point,
                    )
                })
                .or_else(|| pending.iter().next().copied())
                .ok_or_else(|| LayoutError("residual department floor is empty".into()))?;
            let target_area = variants
                .iter()
                .map(|variant| variant.ideal_area.max(variant.content_area) as usize)
                .min()
                .unwrap_or(1)
                .max(1);
            let mut new_room = BTreeSet::from([seed]);
            loop {
                let current_area = projected_room_tile_area(&new_room);
                if current_area >= target_area {
                    break;
                }
                let candidate = pending
                    .iter()
                    .copied()
                    .filter(|candidate| !new_room.contains(candidate))
                    .filter(|candidate| {
                        cardinal_cells(*candidate, width, height)
                            .into_iter()
                            .any(|neighbor| new_room.contains(&neighbor))
                    })
                    .filter_map(|candidate| {
                        let mut combined = new_room.clone();
                        combined.insert(candidate);
                        variants
                            .iter()
                            .any(|variant| room_shape_within_maximum(variant, &combined))
                            .then_some((
                                projected_room_dimensions(&combined)
                                    .0
                                    .abs_diff(projected_room_dimensions(&combined).1),
                                candidate,
                            ))
                    })
                    .min()
                    .map(|(_, candidate)| candidate);
                let Some(candidate) = candidate else {
                    break;
                };
                new_room.insert(candidate);
            }
            let variant = variants
                .iter()
                .filter(|variant| room_shape_fits(variant, &new_room))
                .min_by_key(|variant| {
                    (
                        room_types
                            .iter()
                            .filter(|known| known.id == variant.id)
                            .count(),
                        room_shape_score(variant, &new_room),
                    )
                });
            let Some(variant) = variant else {
                // This is circulation-shaped remainder, not a license to emit
                // an undersized generic closet. Add it to the connected local
                // aisle one piece at a time; the later service-space pass can
                // classify excess aisle as maintenance.
                common.extend(new_room.iter().copied());
                pending.retain(|cell| !new_room.contains(cell));
                continue;
            };
            pending.retain(|cell| !new_room.contains(cell));
            rooms.push(new_room);
            room_types.push(variant);
            continue;
        };
        rooms[room_index].insert(point);
        pending.remove(&point);
    }
    if rooms.iter().any(|room| {
        !room.iter().any(|point| {
            cardinal_cells(*point, width, height)
                .into_iter()
                .any(|neighbor| common.contains(&neighbor))
        })
    }) {
        return Err(LayoutError(
            "elastic room expansion removed a local-hall frontage".into(),
        ));
    }
    Ok(())
}

fn connect_residual_circulation(
    component: BTreeSet<CellPoint>,
    common: &mut BTreeSet<CellPoint>,
    assignments: &mut [BTreeSet<CellPoint>],
    room_types: &[&RoomType],
    minimum_room_area: usize,
    width: u16,
    height: u16,
) -> Result<(), LayoutError> {
    // Prefer one coherent cut from the residual bay to existing circulation.
    // The older cell-at-a-time heuristic could choose the locally nearest
    // boundary tile, then discover that it had walked into an articulation
    // point and report failure even though another route existed. Build the
    // route only through floor that is individually safe to relinquish, then
    // validate the complete cut before committing it.
    let mut allowed = component.clone();
    allowed.extend(common.iter().copied());
    for room in assignments.iter() {
        for point in room.iter().copied() {
            let mut reduced = room.clone();
            reduced.remove(&point);
            if !reduced.is_empty() && cells_connected(&reduced, width, height) {
                allowed.insert(point);
            }
        }
    }
    if let Some(path) = shortest_path_between_sets(&component, common, &allowed, width, height) {
        let cut: BTreeSet<_> = path
            .into_iter()
            .filter(|point| !component.contains(point) && !common.contains(point))
            .collect();
        let reduced_rooms: Vec<_> = assignments
            .iter()
            .map(|room| room.difference(&cut).copied().collect::<BTreeSet<_>>())
            .collect();
        let resulting_circulation: BTreeSet<_> = common
            .iter()
            .chain(component.iter())
            .chain(cut.iter())
            .copied()
            .collect();
        if reduced_rooms.iter().enumerate().all(|(index, room)| {
            !room.is_empty()
                && cells_connected(room, width, height)
                && projected_room_tile_area(room) >= minimum_room_area
                && room_shape_within_maximum(room_types[index], room)
                && (!room_types[index].requires_center_activity || room_has_center_lobe(room))
                && room.iter().any(|point| {
                    cardinal_cells(*point, width, height)
                        .into_iter()
                        .any(|neighbor| resulting_circulation.contains(&neighbor))
                })
        }) {
            for (room, reduced) in assignments.iter_mut().zip(reduced_rooms) {
                *room = reduced;
            }
            common.extend(component);
            common.extend(cut);
            return Ok(());
        }
    }

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
                if !cardinal_cells(point, width, height)
                    .into_iter()
                    .any(|neighbor| circulation.contains(&neighbor))
                {
                    continue;
                }
                let mut reduced = room.clone();
                reduced.remove(&point);
                // A seed is only a growth origin, not permanent structure.  It
                // may be reassigned to circulation once the room has other
                // connected floor; treating it as immutable can trap an
                // otherwise valid residual bay behind the room frontage.
                if reduced.is_empty()
                    || connected_components(&reduced, width, height).len() != 1
                    || projected_room_tile_area(&reduced) < minimum_room_area
                    || !room_shape_within_maximum(room_types[room_index], &reduced)
                    || (room_types[room_index].requires_center_activity
                        && !room_has_center_lobe(&reduced))
                {
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
            // Every single boundary tile is currently an articulation point.
            // Do not tunnel through a valid authored room merely to join a
            // small leftover lobby. The lobby is still connected through the
            // room doors emitted on its boundaries, and final raster
            // validation proves whole-station walkability. Keeping these few
            // cells as local circulation preserves room programs and avoids a
            // destructive retry loop.
            common.extend(circulation);
            return Ok(());
        };
        assignments[room_index].remove(&point);
        circulation.insert(point);
    }
    common.extend(circulation);
    Ok(())
}

fn carve_residual_room_frontage(
    component: &BTreeSet<CellPoint>,
    common: &mut BTreeSet<CellPoint>,
    assignments: &mut [BTreeSet<CellPoint>],
    room_types: &[&RoomType],
    department: &super::model::DepartmentRequest,
    width: u16,
    height: u16,
) -> bool {
    let mut allowed = component.clone();
    allowed.extend(common.iter().copied());
    for room in assignments.iter() {
        for point in room.iter().copied() {
            let mut reduced = room.clone();
            reduced.remove(&point);
            if !reduced.is_empty() && cells_connected(&reduced, width, height) {
                allowed.insert(point);
            }
        }
    }
    let Some(path) = shortest_path_between_sets(component, common, &allowed, width, height) else {
        return false;
    };
    let cut = path
        .into_iter()
        .filter(|point| !component.contains(point) && !common.contains(point))
        .collect::<BTreeSet<_>>();
    let reduced_rooms = assignments
        .iter()
        .map(|room| room.difference(&cut).copied().collect::<BTreeSet<_>>())
        .collect::<Vec<_>>();
    if !reduced_rooms.iter().enumerate().all(|(index, room)| {
        !room.is_empty()
            && cells_connected(room, width, height)
            && department.room_types.iter().any(|variant| {
                variant.name == room_types[index].name && room_shape_fits(variant, room)
            })
    }) {
        return false;
    }
    for (room, reduced) in assignments.iter_mut().zip(reduced_rooms) {
        *room = reduced;
    }
    common.extend(cut);
    component.iter().any(|point| {
        cardinal_cells(*point, width, height)
            .into_iter()
            .any(|neighbor| common.contains(&neighbor))
    })
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
        .map(|room| room_minimum_area(room))
        .min()
        .unwrap_or(1);
    // Real catalogs contain several mutually exclusive room envelopes. Give
    // constrained shapes enough local transfers to form a thick 2x2 lobe and
    // resolve candidate contention, rather than stopping after an area-only
    // adjustment.
    for _ in 0..shapes.len().saturating_mul(32) {
        if match_room_types_to_shapes(room_types, shapes).is_some() {
            return;
        }

        // A doorway seed can be left in a shallow bay after the balanced
        // flood meets another room.  Do not preserve that accidental hallway
        // geometry by accepting a sliver or by hoping a later type matching
        // pass can hide it.  Let a shape which fits no authored program claim
        // adjacent non-essential circulation while the hallway remains
        // connected and the room keeps hallway frontage.  This converts local
        // one-cell bays into chunky room lobes at the partitioning stage.
        // Matching can also fail when several shapes are valid only for the
        // same narrow program (for example two reception-shaped strips but
        // only one reception room). Grow the most constrained shapes, not just
        // shapes with zero candidates, until the catalog has a full matching.
        let candidate_counts: Vec<_> = shapes
            .iter()
            .map(|shape| {
                room_types
                    .iter()
                    .filter(|room| room_shape_fits(room, shape))
                    .count()
            })
            .collect();
        let minimum_candidates = candidate_counts.iter().copied().min().unwrap_or(0);
        let invalid_shapes: Vec<_> = candidate_counts
            .iter()
            .enumerate()
            .filter_map(|(index, count)| (*count == minimum_candidates).then_some(index))
            .collect();
        let mut circulation_growth = None;
        for recipient in invalid_shapes {
            let old_score = room_types
                .iter()
                .filter(|room| room_shape_within_maximum(room, &shapes[recipient]))
                .map(|room| room_shape_score(room, &shapes[recipient]))
                .min()
                .unwrap_or(usize::MAX);
            for cell in circulation.iter().copied() {
                if !cardinal_cells(cell, width, height)
                    .into_iter()
                    .any(|neighbor| shapes[recipient].contains(&neighbor))
                {
                    continue;
                }
                let mut reduced_circulation = circulation.clone();
                reduced_circulation.remove(&cell);
                if reduced_circulation.is_empty()
                    || !cells_connected(&reduced_circulation, width, height)
                {
                    continue;
                }
                let mut expanded = shapes[recipient].clone();
                expanded.insert(cell);
                if !room_shape_within_maximum(room_types[recipient], &expanded)
                    || !expanded.iter().any(|point| {
                        cardinal_cells(*point, width, height)
                            .into_iter()
                            .any(|neighbor| reduced_circulation.contains(&neighbor))
                    })
                    || shapes.iter().enumerate().any(|(shape_index, shape)| {
                        let candidate = if shape_index == recipient {
                            &expanded
                        } else {
                            shape
                        };
                        !candidate.iter().any(|point| {
                            cardinal_cells(*point, width, height)
                                .into_iter()
                                .any(|neighbor| reduced_circulation.contains(&neighbor))
                        })
                    })
                {
                    continue;
                }
                let new_score = room_types
                    .iter()
                    .filter(|room| room_shape_within_maximum(room, &expanded))
                    .map(|room| room_shape_score(room, &expanded))
                    .min()
                    .unwrap_or(usize::MAX);
                let new_candidates = room_types
                    .iter()
                    .filter(|room| room_shape_fits(room, &expanded))
                    .count();
                let key = (
                    Reverse(new_candidates),
                    new_score >= old_score,
                    new_score,
                    recipient,
                    cell,
                );
                if circulation_growth
                    .as_ref()
                    .is_none_or(|(best_key, _, _)| key < *best_key)
                {
                    circulation_growth = Some((key, recipient, cell));
                }
            }
        }
        if let Some((_, recipient, cell)) = circulation_growth {
            circulation.remove(&cell);
            shapes[recipient].insert(cell);
            continue;
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
                    || (room_types[donor].requires_center_activity
                        && !room_has_center_lobe(&reduced))
                    || !reduced.iter().any(|point| {
                        cardinal_cells(*point, width, height)
                            .into_iter()
                            .any(|neighbor| circulation.contains(&neighbor))
                    })
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
                    if room_shape_within_maximum(room_types[recipient], &expanded) {
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
                    && (!room_types[donor].requires_center_activity
                        || room_has_center_lobe(&reduced))
            });
            let Some(cell) = circulation_cell else {
                return;
            };
            shapes[donor].remove(&cell);
            circulation.insert(cell);
            continue;
        }

        // Area alone cannot repair a ribbon: it may contain plenty of tiles
        // while having no usable short side. Transfer a boundary module from a
        // neighboring healthy room whenever that improves the recipient's best
        // authored-shape score. This thickens lobes instead of accepting long,
        // empty closets or carving yet another hallway.
        let incompatible = (0..shapes.len()).min_by_key(|index| {
            room_types
                .iter()
                .filter(|room| room_shape_fits(room, &shapes[*index]))
                .count()
        });
        if let Some(recipient) = incompatible {
            let mut best_transfer = None;
            for donor in 0..shapes.len() {
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
                    if connected_components(&reduced, width, height).len() != 1
                        || projected_room_tile_area(&reduced) < minimum_area
                        || (room_types[donor].requires_center_activity
                            && !room_has_center_lobe(&reduced))
                        || !reduced.iter().any(|point| {
                            cardinal_cells(*point, width, height)
                                .into_iter()
                                .any(|neighbor| circulation.contains(&neighbor))
                        })
                    {
                        continue;
                    }
                    let mut expanded = shapes[recipient].clone();
                    expanded.insert(cell);
                    if !room_shape_within_maximum(room_types[recipient], &expanded) {
                        continue;
                    }
                    let new_score = room_types
                        .iter()
                        .filter(|room| room_shape_within_maximum(room, &expanded))
                        .map(|room| room_shape_score(room, &expanded))
                        .min()
                        .unwrap_or(usize::MAX);
                    let new_candidates = room_types
                        .iter()
                        .filter(|room| room_shape_fits(room, &expanded))
                        .count();
                    let key = (Reverse(new_candidates), new_score, donor, cell);
                    if best_transfer
                        .as_ref()
                        .is_none_or(|(best_key, _, _)| key < *best_key)
                    {
                        best_transfer = Some((key, donor, cell));
                    }
                }
            }
            if let Some((_, donor, cell)) = best_transfer {
                shapes[donor].remove(&cell);
                shapes[recipient].insert(cell);
                continue;
            }
        }
        let mut shape_order: Vec<_> = (0..shapes.len()).collect();
        shape_order.sort_by_key(|index| Reverse(projected_room_tile_area(&shapes[*index])));
        let mut demands = room_types
            .iter()
            .map(|room| room_minimum_area(room))
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
                    && (!room_types[donor].requires_center_activity
                        || room_has_center_lobe(&reduced))
                    && reduced.iter().any(|point| {
                        cardinal_cells(*point, width, height)
                            .into_iter()
                            .any(|neighbor| circulation.contains(&neighbor))
                    })
                {
                    let mut expanded = shapes[recipient].clone();
                    expanded.insert(cell);
                    if room_shape_within_maximum(room_types[recipient], &expanded) {
                        transfer = Some((donor, cell));
                        break;
                    }
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
    let mut semantic_counts: BTreeMap<&str, u16> = BTreeMap::new();
    for room in &instances {
        *counts.entry(room.id).or_default() += 1;
        *semantic_counts.entry(room.name.as_str()).or_default() += 1;
    }
    let desired_minimum = instances.len().max(minimum_components);
    let maximum = catalog_maximum;
    let preferred_room_area = area
        .saturating_mul(usize::from(INTERIOR).pow(2) + usize::from(INTERIOR))
        .div_ceil(desired_minimum.max(1));
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
    while instances.len() < maximum {
        if instances.len() >= desired_minimum
            && (committed_capacity >= area || committed_content >= content_budget)
        {
            break;
        }
        let Some(room) = department
            .room_types
            .iter()
            .filter(|room| counts.get(&room.id).copied().unwrap_or(0) < room.max_count)
            .filter(|room| {
                instances.len() < desired_minimum
                    || committed_capacity < area
                    || committed_content + room.ideal_area.max(room.content_area).max(1) as usize
                        <= content_budget
            })
            .min_by_key(|room| {
                (
                    semantic_counts
                        .get(room.name.as_str())
                        .copied()
                        .unwrap_or(0),
                    room.requires_center_activity,
                    usize::try_from(room.ideal_area)
                        .unwrap_or(usize::MAX)
                        .abs_diff(preferred_room_area),
                    room.content_area,
                    counts.get(&room.id).copied().unwrap_or(0),
                    room.id,
                )
            })
        else {
            break;
        };
        *counts.entry(room.id).or_default() += 1;
        *semantic_counts.entry(room.name.as_str()).or_default() += 1;
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
                    type_to_shape[type_index]
                        .expect("invariant: `||` short-circuit means this arm only runs when the left `is_none()` was false"),
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

fn relaxed_room_variant_rematch<'a>(
    department: &'a super::model::DepartmentRequest,
    selected: &[&'a RoomType],
    shapes: &[BTreeSet<CellPoint>],
) -> Option<Vec<&'a RoomType>> {
    if selected.len() != shapes.len() {
        return None;
    }
    shapes
        .iter()
        .enumerate()
        .map(|(index, shape)| {
            department
                .room_types
                .iter()
                .filter(|variant| room_shape_fits(variant, shape))
                .min_by_key(|variant| {
                    (
                        variant.name != selected[index].name,
                        room_shape_score(variant, shape),
                        variant.id,
                    )
                })
        })
        .collect()
}

/// Room growth operates on semantic programs, but an irregular partition can
/// produce a mix of full and compact envelopes. Replace only the geometry
/// variant of an existing semantic slot until every shape has at least one
/// compatible program; never invent a different room purpose.
fn adapt_room_variants_to_shapes<'a>(
    department: &'a super::model::DepartmentRequest,
    room_types: &mut Vec<&'a RoomType>,
    shapes: &[BTreeSet<CellPoint>],
) {
    for _ in 0..room_types.len().saturating_mul(3) {
        if match_room_types_to_shapes(room_types, shapes).is_some() {
            return;
        }
        let Some(shape) = shapes.iter().min_by_key(|shape| {
            room_types
                .iter()
                .filter(|room| room_shape_fits(room, shape))
                .count()
        }) else {
            return;
        };
        let mut counts = BTreeMap::<u16, usize>::new();
        for room in room_types.iter() {
            *counts.entry(room.id).or_default() += 1;
        }
        let replacement = room_types
            .iter()
            .enumerate()
            .filter(|(_, selected)| !room_shape_fits(selected, shape))
            .filter_map(|(index, selected)| {
                department
                    .room_types
                    .iter()
                    .filter(|candidate| candidate.name == selected.name)
                    .filter(|candidate| candidate.id != selected.id)
                    .filter(|candidate| {
                        counts.get(&candidate.id).copied().unwrap_or(0)
                            < usize::from(candidate.max_count)
                    })
                    .filter(|candidate| room_shape_fits(candidate, shape))
                    .min_by_key(|candidate| room_shape_score(candidate, shape))
                    .map(|candidate| (index, candidate))
            })
            .min_by_key(|(_, candidate)| room_shape_score(candidate, shape));
        let Some((index, replacement)) = replacement else {
            return;
        };
        room_types[index] = replacement;
    }
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
                    let mut center_blocks = 0usize;
                    for base_x in [point.x.checked_sub(1), Some(point.x)]
                        .into_iter()
                        .flatten()
                    {
                        for base_y in [point.y.checked_sub(1), Some(point.y)]
                            .into_iter()
                            .flatten()
                        {
                            let Some(east) = base_x.checked_add(1) else {
                                continue;
                            };
                            let Some(north) = base_y.checked_add(1) else {
                                continue;
                            };
                            let block = [
                                CellPoint {
                                    x: base_x,
                                    y: base_y,
                                },
                                CellPoint { x: east, y: base_y },
                                CellPoint {
                                    x: base_x,
                                    y: north,
                                },
                                CellPoint { x: east, y: north },
                            ];
                            if block.iter().all(|cell| component.contains(cell)) {
                                center_blocks += 1;
                            }
                        }
                    }
                    (
                        center_blocks > 0,
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
    frontage_candidates: &BTreeSet<CellPoint>,
    seeds: &[CellPoint],
    room_types: &[&RoomType],
    width: u16,
    height: u16,
    rng: &mut Rng,
) -> Result<(Vec<BTreeSet<CellPoint>>, BTreeSet<CellPoint>), LayoutError> {
    let mut growth_seeds = seeds.to_vec();
    let mut rooms: Vec<BTreeSet<_>> = seeds.iter().map(|_| BTreeSet::new()).collect();
    let mut owner: BTreeMap<CellPoint, usize> = BTreeMap::new();
    let noncenter_count = room_types
        .iter()
        .filter(|room| !room.requires_center_activity)
        .count();
    // Center-activity programs structurally require a real 2x2 logical lobe.
    // Reserve it before general growth so reception/closet seeds cannot claim
    // one of its cells and leave a long room whose bounding box only appears
    // suitable. A seed set without non-overlapping center blocks is retried.
    let mut center_candidates = Vec::new();
    for (index, room_type) in room_types
        .iter()
        .enumerate()
        .filter(|(_, room)| room.requires_center_activity)
    {
        let mut blocks = Vec::new();
        for base in available {
            let base_x = base.x;
            let base_y = base.y;
            let Some(east) = base_x.checked_add(1) else {
                continue;
            };
            let Some(north) = base_y.checked_add(1) else {
                continue;
            };
            if east >= width || north >= height {
                continue;
            }
            let block = BTreeSet::from([
                CellPoint {
                    x: base_x,
                    y: base_y,
                },
                CellPoint { x: east, y: base_y },
                CellPoint {
                    x: base_x,
                    y: north,
                },
                CellPoint { x: east, y: north },
            ]);
            if block.iter().all(|point| available.contains(point)) {
                let Some(path) = shortest_path_between_sets(
                    &block,
                    frontage_candidates,
                    available,
                    width,
                    height,
                ) else {
                    continue;
                };
                let mut territory = block;
                territory.extend(path);
                if room_shape_within_maximum(room_type, &territory) && !blocks.contains(&territory)
                {
                    blocks.push(territory);
                }
            }
        }
        blocks.sort_by_key(|block| {
            (
                !block
                    .iter()
                    .any(|point| frontage_candidates.contains(point)),
                block
                    .iter()
                    .flat_map(|point| {
                        frontage_candidates
                            .iter()
                            .map(move |frontage| cell_distance(*point, *frontage))
                    })
                    .min()
                    .unwrap_or(u16::MAX),
                hash_cell(
                    rng.0 ^ index as u64,
                    *block
                        .iter()
                        .next()
                        .expect("invariant: a room-shape candidate block always has at least one cell"),
                ),
            )
        });
        // Keep the best frontage-near candidates and bound the otherwise
        // exponential joint 2x2 assignment search on large departments.
        blocks.truncate(64);
        if blocks.is_empty() {
            return Err(LayoutError(format!(
                "center-activity room {} has no available 2x2 seed lobe",
                room_type.name
            )));
        }
        center_candidates.push((index, blocks));
    }
    center_candidates.sort_by_key(|(index, blocks)| (blocks.len(), *index));
    fn assign_center_blocks(
        candidates: &[(usize, Vec<BTreeSet<CellPoint>>)],
        candidate_index: usize,
        occupied: &mut BTreeSet<CellPoint>,
        assignments: &mut Vec<(usize, BTreeSet<CellPoint>)>,
        frontages: &BTreeSet<CellPoint>,
        required_free_frontages: usize,
        budget: &mut usize,
    ) -> bool {
        if *budget == 0 {
            return false;
        }
        *budget -= 1;
        if candidate_index == candidates.len() {
            return frontages.difference(occupied).count() >= required_free_frontages;
        }
        let (room_index, blocks) = &candidates[candidate_index];
        for block in blocks {
            if block.iter().any(|point| occupied.contains(point)) {
                continue;
            }
            let additions: Vec<_> = block
                .iter()
                .copied()
                .filter(|point| !occupied.contains(point))
                .collect();
            for point in &additions {
                occupied.insert(*point);
            }
            assignments.push((*room_index, block.clone()));
            if assign_center_blocks(
                candidates,
                candidate_index + 1,
                occupied,
                assignments,
                frontages,
                required_free_frontages,
                budget,
            ) {
                return true;
            }
            assignments.pop();
            for point in additions {
                occupied.remove(&point);
            }
        }
        false
    }
    let mut occupied = BTreeSet::new();
    let mut center_assignments = Vec::new();
    // This is a constrained set-packing search. Large station catalogs can
    // contain many center-activity rooms, so an unlucky seed must never turn
    // it into an unbounded 64^N search on the native worker. Ten thousand
    // deterministic nodes is ample for the spacious production canvas; a
    // harder arrangement is retried by the outer candidate loop.
    let mut center_assignment_budget = 10_000usize;
    if !assign_center_blocks(
        &center_candidates,
        0,
        &mut occupied,
        &mut center_assignments,
        frontage_candidates,
        noncenter_count,
        &mut center_assignment_budget,
    ) {
        let names = center_candidates
            .iter()
            .map(|(index, _)| room_types[*index].name.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        return Err(LayoutError(format!(
            "center-activity rooms [{names}] have no non-overlapping 2x2 seed lobes"
        )));
    }
    for (index, block) in center_assignments {
        for point in block {
            owner.insert(point, index);
            rooms[index].insert(point);
        }
    }
    for (index, room_type) in room_types.iter().enumerate() {
        if room_type.requires_center_activity {
            growth_seeds[index] = rooms[index]
                .iter()
                .copied()
                .find(|point| frontage_candidates.contains(point))
                .unwrap_or(seeds[index]);
            continue;
        }
        let preferred = seeds[index];
        let seed = if frontage_candidates.contains(&preferred) && !owner.contains_key(&preferred) {
            preferred
        } else {
            let frontage_seed = frontage_candidates
                .iter()
                .copied()
                .filter(|point| !owner.contains_key(point))
                .max_by_key(|point| {
                    let separation = owner
                        .keys()
                        .map(|owned| cell_distance(*owned, *point))
                        .min()
                        .unwrap_or(u16::MAX);
                    (separation, hash_cell(rng.0 ^ index as u64, *point))
                });
            if let Some(seed) = frontage_seed {
                seed
            } else {
                let allowed: BTreeSet<_> = available
                    .iter()
                    .copied()
                    .filter(|point| !owner.contains_key(point))
                    .collect();
                let mut options = Vec::new();
                for candidate in &allowed {
                    let source = BTreeSet::from([*candidate]);
                    let Some(path) = shortest_path_between_sets(
                        &source,
                        frontage_candidates,
                        &allowed,
                        width,
                        height,
                    ) else {
                        continue;
                    };
                    let territory: BTreeSet<_> = path.into_iter().collect();
                    if room_shape_within_maximum(room_type, &territory) {
                        options.push((territory.len(), *candidate, territory));
                    }
                }
                options.sort_by_key(|(length, candidate, _)| (*length, *candidate));
                let Some((_, seed, territory)) = options.into_iter().next() else {
                    return Err(LayoutError(format!(
                        "room {} has no reachable unclaimed seed",
                        room_type.name
                    )));
                };
                for point in territory {
                    owner.insert(point, index);
                    rooms[index].insert(point);
                }
                seed
            }
        };
        growth_seeds[index] = seed;
        owner.insert(seed, index);
        rooms[index].insert(seed);
        // Center-activity programs need an atomic 2-module seed to preserve a
        // real activity lobe. Ordinary rooms begin from one frontage module;
        // reserving pairs for every room starved later seeds even though the
        // global growth pass had ample floor. Final contract validation still
        // rejects any room that fails to reach its authored minimum.
        if rooms[index].len() == 1 && room_type.requires_center_activity {
            let mut seed_extensions = cardinal_cells(seed, width, height)
                .into_iter()
                .filter(|point| {
                    if !available.contains(point) || owner.contains_key(point) {
                        return false;
                    }
                    let mut projected = rooms[index].clone();
                    projected.insert(*point);
                    room_shape_within_maximum(room_type, &projected)
                })
                .collect::<Vec<_>>();
            seed_extensions.sort_by_key(|point| {
                (
                    Reverse(
                        cardinal_cells(*point, width, height)
                            .into_iter()
                            .filter(|neighbor| {
                                available.contains(neighbor) && !owner.contains_key(neighbor)
                            })
                            .count(),
                    ),
                    hash_cell(rng.0 ^ index as u64, *point),
                )
            });
            if let Some(extension) = seed_extensions.into_iter().next() {
                owner.insert(extension, index);
                rooms[index].insert(extension);
            } else {
                // The preferred frontage may have been enclosed by earlier
                // two-module reservations. Re-select the pair atomically
                // instead of keeping an impossible singleton or failing a
                // layout that still has ample connected frontage elsewhere.
                owner.remove(&seed);
                rooms[index].remove(&seed);
                let mut pairs = frontage_candidates
                    .iter()
                    .copied()
                    .filter(|frontage_seed| !owner.contains_key(frontage_seed))
                    .flat_map(|frontage_seed| {
                        cardinal_cells(frontage_seed, width, height)
                            .into_iter()
                            .map(move |extension| (frontage_seed, extension))
                    })
                    .filter(|(_, extension)| {
                        available.contains(extension) && !owner.contains_key(extension)
                    })
                    .filter(|(frontage_seed, extension)| {
                        let projected = BTreeSet::from([*frontage_seed, *extension]);
                        room_shape_within_maximum(room_type, &projected)
                    })
                    .collect::<Vec<_>>();
                pairs.sort_by_key(|(frontage_seed, extension)| {
                    (
                        Reverse(
                            owner
                                .keys()
                                .map(|owned| cell_distance(*owned, *frontage_seed))
                                .min()
                                .unwrap_or(u16::MAX),
                        ),
                        hash_cell(rng.0 ^ index as u64, *extension),
                    )
                });
                if let Some((replacement_seed, extension)) = pairs.into_iter().next() {
                    growth_seeds[index] = replacement_seed;
                    owner.insert(replacement_seed, index);
                    owner.insert(extension, index);
                    rooms[index].insert(replacement_seed);
                    rooms[index].insert(extension);
                } else {
                    // Frontage can be temporarily saturated by seeds selected
                    // for later rooms. Keep the valid singleton and let the
                    // global growth pass expand it; final contract validation
                    // still rejects an actually undersized authored room.
                    owner.insert(seed, index);
                    rooms[index].insert(seed);
                }
            }
        }
    }
    let seeds = growth_seeds.as_slice();
    let mut frontiers: Vec<VecDeque<_>> = rooms
        .iter()
        .map(|room| room.iter().copied().collect())
        .collect();
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
            .filter(|index| room_shape_within_maximum(room_types[*index], &rooms[*index]))
            .collect();
        order.sort_by_key(|index| {
            let target = room_types[*index]
                .ideal_area
                .max(room_types[*index].content_area)
                .max(1) as usize;
            (
                projected_room_tile_area(&rooms[*index]) >= room_minimum_area(room_types[*index]),
                // Before every room reaches its authored minimum, grow the
                // smallest shape first. Ratio-to-ideal favored large programs
                // and starved later optional rooms into one-cell closets.
                projected_room_tile_area(&rooms[*index]),
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
                    room_shape_within_maximum(room_types[index], &projected)
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
                    // Preserve open territory in front of every growing room.
                    // Taking cul-de-sacs first lets one seed wrap around and
                    // strand another seed as a one-cell-wide sliver. Prefer
                    // cells which continue into the largest unclaimed front;
                    // the shape score still keeps the resulting lobe compact.
                    Reverse(unclaimed_neighbors),
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
                            room_shape_within_maximum(room_types[*index], &projected)
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
                                || !room_shape_within_maximum(room_types[donor], &new_donor)
                            {
                                continue;
                            }
                            let mut new_recipient = rooms[recipient].clone();
                            new_recipient.insert(donor_cell);
                            if !room_shape_within_maximum(room_types[recipient], &new_recipient) {
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
                .map(|room| {
                    usize::try_from(room.ideal_area)
                        .unwrap_or(usize::MAX)
                        .saturating_mul(2)
                        .max(room_minimum_area(room))
                })
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
                        if !touches {
                            return false;
                        }
                        let mut combined = rooms[*index].clone();
                        combined.extend(component.iter().copied());
                        room_shape_within_maximum(room_types[*index], &combined)
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
            .into_iter()
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

/// Attaches one new branch to exactly one point of an existing public tree.
/// Keeping the branch away from every other tree edge prevents incidental
/// side-by-side contact from creating a closed hallway loop.
fn attach_branch_to_public_tree(
    start: CellPoint,
    public: &BTreeSet<CellPoint>,
    allowed: &BTreeSet<CellPoint>,
    width: u16,
    height: u16,
) -> Option<BTreeSet<CellPoint>> {
    let mut blocked = public.clone();
    for hall in public {
        blocked.extend(cardinal_cells(*hall, width, height));
    }
    let mut route_floor = allowed
        .difference(&blocked)
        .copied()
        .collect::<BTreeSet<_>>();
    route_floor.insert(start);
    let mut best = None;
    for attachment in public {
        for approach in cardinal_cells(*attachment, width, height) {
            if public.contains(&approach) || !allowed.contains(&approach) {
                continue;
            }
            route_floor.insert(approach);
            if let Some(mut path) =
                shortest_path_in_set(start, approach, &route_floor, width, height)
            {
                path.insert(*attachment);
                if best
                    .as_ref()
                    .is_none_or(|known: &BTreeSet<CellPoint>| path.len() < known.len())
                {
                    best = Some(path);
                }
            }
            route_floor.remove(&approach);
        }
    }
    best
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
