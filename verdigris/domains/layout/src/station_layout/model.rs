use serde::{Deserialize, Serialize};

pub const STATION_MAINTENANCE_WIDTH: u16 = 2;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum MacroArchetype {
    Cross,
    Ring,
    Bent,
    Branch,
    Courtyard,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum TileClass {
    #[default]
    Exterior,
    Hull,
    Structure,
    Public,
    Local,
    Maintenance,
    DepartmentFloor,
    Partition,
    Room,
}

impl TileClass {
    pub fn walkable(self) -> bool {
        matches!(
            self,
            Self::Public | Self::Local | Self::Maintenance | Self::DepartmentFloor | Self::Room
        )
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct TileCell {
    pub class: TileClass,
    pub owner: Option<u16>,
    pub room: Option<u16>,
    pub flags: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
pub struct Point {
    pub x: u16,
    pub y: u16,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Rect {
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
}

impl Rect {
    pub fn right(self) -> u16 {
        self.x + self.width - 1
    }
    pub fn top(self) -> u16 {
        self.y + self.height - 1
    }
    pub fn area(self) -> usize {
        usize::from(self.width) * usize::from(self.height)
    }
    pub fn contains(self, p: Point) -> bool {
        p.x >= self.x && p.x <= self.right() && p.y >= self.y && p.y <= self.top()
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StationSettings {
    pub seed: u64,
    pub width: u16,
    pub height: u16,
    pub hull_thickness: u16,
    pub corridor_width: u16,
    pub maintenance_width: u16,
    pub room_jitter: u16,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RoomType {
    pub id: u16,
    pub name: String,
    pub min_width: u16,
    pub max_width: u16,
    pub min_height: u16,
    pub max_height: u16,
    pub min_count: u16,
    pub max_count: u16,
    pub entrances: u16,
    pub content_area: u32,
    pub ideal_area: u32,
    pub min_short_side: u16,
    pub max_aspect_ratio_millis: u32,
    pub requires_center_activity: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DepartmentRequest {
    pub id: u16,
    pub name: String,
    pub weight: u16,
    pub minimum_area: u32,
    pub maximum_area: u32,
    pub desired_area: u32,
    pub room_types: Vec<RoomType>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LayoutRequest {
    pub settings: StationSettings,
    pub departments: Vec<DepartmentRequest>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Room {
    pub id: u16,
    pub department_id: u16,
    pub room_type_id: u16,
    pub bounds: Rect,
    pub tiles: Vec<Point>,
    pub door_ids: Vec<u16>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Department {
    pub id: u16,
    pub bounds: Rect,
    pub room_ids: Vec<u16>,
    pub frontage_door: u16,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Door {
    pub id: u16,
    pub at: Point,
    pub room_id: Option<u16>,
    pub department_id: u16,
    pub connects_public: bool,
    #[serde(default)]
    pub connects_maintenance: bool,
    #[serde(default)]
    pub maintenance_choke: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LayoutGraph {
    pub department_edges: Vec<(u16, u16)>,
    pub room_edges: Vec<(u16, u16)>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StationLayout {
    pub seed: u64,
    pub width: u16,
    pub height: u16,
    pub archetype: MacroArchetype,
    pub tiles: Vec<TileCell>,
    pub departments: Vec<Department>,
    pub rooms: Vec<Room>,
    pub doors: Vec<Door>,
    pub public_circulation: Vec<Point>,
    pub maintenance: Vec<Point>,
    pub structure: Vec<Point>,
    pub hull: Vec<Point>,
    pub graph: LayoutGraph,
    pub metadata: BTreeMap<String, String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum Facing {
    North,
    East,
    South,
    West,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum FixtureLayer {
    Floor,
    Furniture,
    Machine,
    Wall,
    Ceiling,
}

/// One exact instruction in the authoritative Rust station blueprint. DM is
/// expected to instantiate this instruction verbatim rather than re-solving it.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FixturePlacement {
    pub id: u32,
    pub fixture_id: String,
    pub at: Point,
    pub facing: Facing,
    pub layer: FixtureLayer,
    pub department_id: u16,
    pub room_id: Option<u16>,
    pub network_id: Option<String>,
    pub variant: u16,
    /// True when the spawned atom occupies its turf for pathing purposes.
    pub blocks_movement: bool,
    /// Floor turfs that must remain clear so this fixture can be approached
    /// and operated. For directional machines this is normally the front tile.
    pub required_access: Vec<Point>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RoomBlueprint {
    pub allocation_id: String,
    pub room_id: u16,
    pub department_id: u16,
    pub semantic_role: String,
    pub selected_variant: String,
    pub area_name: String,
    pub aesthetic_id: String,
    pub floor_style: String,
    pub accent_style: String,
    pub activity_center: Point,
    pub circulation: Vec<Point>,
    pub fixture_ids: Vec<u32>,
    pub occupancy_micros: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct UtilityNetworkBlueprint {
    pub id: String,
    pub kind: String,
    pub backbone: Vec<Point>,
    pub endpoint_fixture_ids: Vec<u32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StationBlueprint {
    pub schema: String,
    pub major: u16,
    pub minor: u16,
    pub catalog_hash: String,
    pub layout: StationLayout,
    pub rooms: Vec<RoomBlueprint>,
    pub fixtures: Vec<FixturePlacement>,
    pub networks: Vec<UtilityNetworkBlueprint>,
    pub quality: BTreeMap<String, u32>,
    #[serde(default)]
    pub sprite_previews: BTreeMap<String, SpritePreview>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TileRun {
    pub x: u16,
    pub len: u16,
    pub class: String,
    pub owner: Option<String>,
    pub zone: Option<String>,
    pub room: Option<String>,
    pub flags: u32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TileRow {
    pub y: u16,
    pub runs: Vec<TileRun>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LayoutWire {
    pub schema: String,
    pub major: u16,
    pub minor: u16,
    pub catalog_hash: String,
    pub seed: String,
    pub width: u16,
    pub height: u16,
    pub archetype: MacroArchetype,
    pub metadata: WireMetadata,
    pub departments: Vec<WireDepartment>,
    pub nodes: Vec<WireNode>,
    pub rooms: Vec<WireRoom>,
    pub doors: Vec<WireDoor>,
    pub edges: Vec<WireEdge>,
    pub tile_rows: Vec<TileRow>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WireMetadata {
    pub station_id: String,
    pub name: String,
    pub architecture_style: String,
    pub faction_id: String,
    pub security_tier: u16,
    pub size_class: String,
    pub layout_archetype: String,
    pub aesthetic_score: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WireDepartment {
    pub id: String,
    pub definition_id: String,
    pub desired_area: u32,
    pub node_id: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WireNode {
    pub id: String,
    pub department_id: String,
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
    pub desired_area: u32,
    pub frontage_x: u16,
    pub frontage_y: u16,
    pub frontage_spine_vertical: bool,
    pub frontage_spine_coordinate: u16,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WireRoom {
    pub id: String,
    pub rust_room_id: u16,
    pub node_id: String,
    pub definition_id: String,
    pub role: String,
    pub frontage_x: u16,
    pub frontage_y: u16,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WireDoor {
    pub id: String,
    pub x: u16,
    pub y: u16,
    pub direction: String,
    pub kind: String,
    pub from_zone: String,
    pub to_zone: String,
    pub owner_id: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WireEdge {
    pub id: String,
    pub from_node: String,
    pub to_node: String,
    pub kind: String,
    pub service_id: Option<String>,
    pub minimum_width: u16,
    pub required: bool,
    pub corridor_class: String,
    pub path: Vec<[u16; 2]>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogWire {
    pub schema: String,
    pub major: u16,
    pub minor: u16,
    pub catalog_hash: String,
    pub seed: String,
    pub width: u16,
    pub height: u16,
    pub metadata: CatalogMetadataWire,
    pub settings: CatalogSettingsWire,
    pub departments: Vec<CatalogDepartmentWire>,
    pub rooms: Vec<CatalogRoomWire>,
    #[serde(default)]
    pub sprite_previews: BTreeMap<String, SpritePreview>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogMetadataWire {
    pub station_id: String,
    pub name: String,
    pub architecture_style: String,
    pub faction_id: String,
    pub security_tier: u16,
    pub size_class: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogSettingsWire {
    pub hull_thickness: u16,
    pub corridor_width: u16,
    pub maintenance_width: u16,
    pub candidate_count: u16,
    pub room_jitter: u16,
    pub architecture_choices: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogDepartmentWire {
    pub id: String,
    pub definition_id: String,
    pub name: String,
    pub weight: u16,
    pub minimum_area: u32,
    pub maximum_area: u32,
    #[serde(default, deserialize_with = "deserialize_boolish")]
    pub critical: bool,
    #[serde(default)]
    pub requires: Vec<CatalogRequirementWire>,
    #[serde(default)]
    pub provides: Vec<CatalogProvisionWire>,
    #[serde(default)]
    pub room_roles: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogRequirementWire {
    pub id: String,
    pub amount: u16,
    #[serde(default, deserialize_with = "deserialize_boolish")]
    pub optional: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogProvisionWire {
    pub id: String,
    pub amount: u16,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatalogRoomWire {
    pub id: String,
    pub department_id: String,
    pub definition_id: String,
    pub role: String,
    pub min_width: u16,
    pub max_width: u16,
    pub min_height: u16,
    pub max_height: u16,
    pub min_count: u16,
    pub max_count: u16,
    pub min_entrances: u16,
    pub max_entrances: u16,
    pub content_area: u32,
    pub minimum_usable_tiles: u32,
    #[serde(default)]
    pub ideal_usable_tiles: u32,
    #[serde(default)]
    pub min_short_side: u16,
    #[serde(default)]
    pub max_aspect_ratio_millis: u32,
    #[serde(default, deserialize_with = "deserialize_boolish")]
    pub requires_center_activity: bool,
    pub density_min_micros: u32,
    pub density_max_micros: u32,
    pub circulation_min_micros: u32,
    pub wall_utilization_micros: u32,
    #[serde(default)]
    pub aesthetic_id: String,
    pub fragments: Vec<FragmentWire>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FragmentWire {
    pub id: String,
    pub width: u16,
    pub height: u16,
    #[serde(default, deserialize_with = "deserialize_boolish")]
    pub allow_rotation: bool,
    #[serde(default, deserialize_with = "deserialize_boolish")]
    pub allow_mirroring: bool,
    #[serde(default)]
    pub anchor_kind: String,
    #[serde(default)]
    pub anchor_edge: Option<String>,
    #[serde(default)]
    pub anchors: Vec<[i16; 2]>,
    #[serde(default)]
    pub occupied_offsets: Vec<[i16; 2]>,
    #[serde(default)]
    pub features: Vec<FragmentFeatureWire>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FragmentFeatureWire {
    pub id: String,
    pub dx: i16,
    pub dy: i16,
    #[serde(default)]
    pub placement_kind: String,
    #[serde(default)]
    pub icon_file: String,
    #[serde(default)]
    pub icon_state: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SpritePreview {
    pub icon_file: String,
    pub icon_state: String,
}

fn deserialize_boolish<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Boolish {
        Boolean(bool),
        Integer(u8),
    }
    match Boolish::deserialize(deserializer)? {
        Boolish::Boolean(value) => Ok(value),
        Boolish::Integer(0) => Ok(false),
        Boolish::Integer(1) => Ok(true),
        Boolish::Integer(value) => Err(serde::de::Error::custom(format!(
            "boolean integer must be 0 or 1, got {value}"
        ))),
    }
}

impl StationLayout {
    pub fn to_wire(&self) -> LayoutWire {
        let mut tile_rows = Vec::new();
        for y in 0..self.height {
            let mut runs = Vec::new();
            let mut x = 0;
            while x < self.width {
                let cell = self.tile(Point { x, y });
                let mut len = 1;
                while x + len < self.width && self.tile(Point { x: x + len, y }) == cell {
                    len += 1;
                }
                runs.push(TileRun {
                    x: x + 1,
                    len,
                    class: tile_class_name(cell.class).into(),
                    owner: cell.owner.map(|id| format!("department-{id}")),
                    zone: cell.owner.map(|id| format!("zone-{id}")),
                    room: cell.room.map(|id| format!("room-{id}")),
                    flags: cell.flags,
                });
                x += len;
            }
            tile_rows.push(TileRow { y: y + 1, runs });
        }
        let departments = self
            .departments
            .iter()
            .map(|d| WireDepartment {
                id: format!("department-{}", d.id),
                definition_id: format!("definition-{}", d.id),
                desired_area: d.bounds.area() as u32,
                node_id: format!("node-{}", d.id),
            })
            .collect();
        let nodes = self
            .departments
            .iter()
            .map(|d| WireNode {
                id: format!("node-{}", d.id),
                department_id: format!("department-{}", d.id),
                x: d.bounds.x + 1,
                y: d.bounds.y + 1,
                width: d.bounds.width,
                height: d.bounds.height,
                desired_area: d.bounds.area() as u32,
                frontage_x: d.bounds.x + 1,
                frontage_y: d.bounds.y + 1,
                frontage_spine_vertical: d.bounds.height >= d.bounds.width,
                frontage_spine_coordinate: if d.bounds.height >= d.bounds.width {
                    d.bounds.x + 1
                } else {
                    d.bounds.y + 1
                },
            })
            .collect();
        let rooms = self
            .rooms
            .iter()
            .map(|r| WireRoom {
                id: format!("room-{}", r.id),
                rust_room_id: r.id,
                node_id: format!("node-{}", r.department_id),
                definition_id: format!("room-definition-{}", r.room_type_id),
                role: format!("room-type-{}", r.room_type_id),
                frontage_x: r.bounds.x + 1,
                frontage_y: r.bounds.y + 1,
            })
            .collect();
        let doors = self
            .doors
            .iter()
            .map(|d| WireDoor {
                id: format!("door-{}", d.id),
                x: d.at.x + 1,
                y: d.at.y + 1,
                direction: "N".into(),
                kind: if d.connects_public {
                    "frontage".into()
                } else {
                    "room".into()
                },
                from_zone: format!("zone-{}", d.department_id),
                to_zone: d
                    .room_id
                    .map_or_else(|| "public".into(), |id| format!("room-{id}")),
                owner_id: format!("department-{}", d.department_id),
            })
            .collect();
        let edges = self
            .graph
            .department_edges
            .iter()
            .enumerate()
            .map(|(i, (a, b))| WireEdge {
                id: format!("edge-{i}"),
                from_node: format!("node-{a}"),
                to_node: format!("node-{b}"),
                kind: "transit".into(),
                service_id: None,
                minimum_width: 2,
                required: true,
                corridor_class: "public".into(),
                path: Vec::new(),
            })
            .collect();
        LayoutWire {
            schema: "dq.station.plan".into(),
            major: 1,
            minor: 0,
            catalog_hash: String::new(),
            seed: self.seed.to_string(),
            width: self.width,
            height: self.height,
            archetype: self.archetype,
            metadata: WireMetadata {
                station_id: format!("station-{}", self.seed),
                name: "Generated Station".into(),
                architecture_style: "industrial".into(),
                faction_id: "corporate".into(),
                security_tier: 1,
                size_class: "standard".into(),
                layout_archetype: format!("{:?}", self.archetype).to_lowercase(),
                aesthetic_score: 0.0,
            },
            departments,
            nodes,
            rooms,
            doors,
            edges,
            tile_rows,
        }
    }
}

impl StationLayout {
    pub fn index(&self, p: Point) -> usize {
        usize::from(p.y) * usize::from(self.width) + usize::from(p.x)
    }
    pub fn tile(&self, p: Point) -> TileCell {
        self.tiles[self.index(p)]
    }
}

fn tile_class_name(class: TileClass) -> &'static str {
    match class {
        TileClass::Exterior => "exterior",
        TileClass::Hull => "hull",
        TileClass::Structure => "structural_fill",
        TileClass::Public => "public_circulation",
        TileClass::Local => "local_circulation",
        TileClass::Maintenance => "maintenance_floor",
        TileClass::DepartmentFloor | TileClass::Room => "department_floor",
        TileClass::Partition => "partition_wall",
    }
}
