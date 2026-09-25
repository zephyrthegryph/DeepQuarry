use super::error::LayoutError;
use super::model::{
    Department, DepartmentRequest, Door, LayoutGraph, LayoutRequest, MacroArchetype, Point, Rect,
    Room, RoomType, STATION_MAINTENANCE_WIDTH, StationLayout, TileCell, TileClass,
};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
mod geometry;
mod pack;
mod plan;
mod portals;
mod raster;
mod shapes;
mod validate;
use self::geometry::*;
use self::pack::*;
use self::plan::*;
use self::portals::*;
use self::raster::*;
use self::shapes::*;
use self::validate::*;
pub use self::validate::validate_station_structure;

// A logical cell contains its walkable interior followed by one structural
// boundary tile. Main and local corridors deliberately share this compact
// module so intersections cannot accidentally widen maintenance.
const PITCH: u16 = STATION_MAINTENANCE_WIDTH + 1;
const INTERIOR: u16 = PITCH - 1;
const DOOR_FLAG: u32 = 1;

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
