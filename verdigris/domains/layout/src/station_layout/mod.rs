//! Deterministic, host-testable station architecture generation.

mod content;
mod contract;
mod error;
mod jobs;
mod model;
mod program;
mod render;
mod structural;

pub use content::{generate_station_blueprint, validate_station_blueprint};
pub use contract::{decode_catalog, encode_plan};
pub use error::LayoutError;
pub use jobs::{PLANNING_JOB, generate_catalog_plan, plan_catalog_job, plan_section};
pub use model::*;
pub use render::{
    render_blueprint_png, render_blueprint_sprites, render_blueprint_svg, render_png, render_svg,
};
pub use structural::{generate_station_layout as generate, validate_station_structure};

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    pub(super) fn request(seed: u64) -> LayoutRequest {
        let departments = (1..=7)
            .map(|department_id| {
                let room_types = (1..=6)
                    .flat_map(|room_index| {
                        let name = format!("room-{department_id}-{room_index}");
                        let base_id = (department_id - 1) * 12 + (room_index - 1) * 2 + 1;
                        [
                            RoomType {
                                id: base_id,
                                name: name.clone(),
                                min_width: if room_index == 1 { 7 } else { 3 },
                                max_width: 14,
                                min_height: if room_index == 1 { 6 } else { 3 },
                                max_height: 14,
                                min_count: u16::from(room_index <= 4),
                                max_count: 6,
                                entrances: 1,
                                content_area: if room_index == 1 { 21 } else { 9 },
                                ideal_area: if room_index == 1 { 54 } else { 21 },
                                min_short_side: 3,
                                max_aspect_ratio_millis: 4000,
                                requires_center_activity: false,
                            },
                            RoomType {
                                id: base_id + 1,
                                name,
                                min_width: 1,
                                max_width: 5,
                                min_height: 1,
                                max_height: 5,
                                min_count: 0,
                                max_count: 12,
                                entrances: 1,
                                content_area: 1,
                                ideal_area: 4,
                                min_short_side: 1,
                                max_aspect_ratio_millis: 6000,
                                requires_center_activity: false,
                            },
                        ]
                    })
                    .collect();
                DepartmentRequest {
                    id: department_id,
                    name: format!("Department {department_id}"),
                    weight: 10,
                    minimum_area: 24,
                    maximum_area: 100,
                    desired_area: 64,
                    room_types,
                }
            })
            .collect();
        LayoutRequest {
            settings: StationSettings {
                seed,
                width: 160,
                height: 160,
                hull_thickness: 1,
                corridor_width: 3,
                maintenance_width: STATION_MAINTENANCE_WIDTH,
                room_jitter: 3,
            },
            departments,
        }
    }

    fn live_catalog_shape_request(seed: u64) -> LayoutRequest {
        let mut request = request(seed);
        for department in &mut request.departments {
            let mut variants = Vec::new();
            for role in 1..=8u16 {
                let base_id = (department.id - 1) * 24 + (role - 1) * 3 + 1;
                let name = format!("role-{}-{role}", department.id);
                variants.push(RoomType {
                    id: base_id,
                    name: name.clone(),
                    min_width: 3,
                    max_width: 11,
                    min_height: 3,
                    max_height: 11,
                    min_count: u16::from(role == 1),
                    max_count: 3,
                    entrances: 1,
                    content_area: 21,
                    ideal_area: 29,
                    min_short_side: 2,
                    max_aspect_ratio_millis: 3800,
                    requires_center_activity: false,
                });
                variants.push(RoomType {
                    id: base_id + 2,
                    name: name.clone(),
                    min_width: 1,
                    max_width: 5,
                    min_height: 1,
                    max_height: 5,
                    min_count: 0,
                    max_count: 12,
                    entrances: 1,
                    content_area: 1,
                    ideal_area: 4,
                    min_short_side: 1,
                    max_aspect_ratio_millis: 6000,
                    requires_center_activity: false,
                });
                variants.push(RoomType {
                    id: base_id + 1,
                    name: name.clone(),
                    min_width: 3,
                    max_width: 7,
                    min_height: 3,
                    max_height: 7,
                    min_count: 0,
                    max_count: 3,
                    entrances: 1,
                    content_area: 9,
                    ideal_area: 12,
                    min_short_side: 3,
                    max_aspect_ratio_millis: 6000,
                    requires_center_activity: false,
                });
            }
            department.room_types = variants;
        }
        request
    }

    #[test]
    fn deterministic_layout_round_trips_through_json() {
        let first = generate(&request(41)).unwrap();
        let second = generate(&request(41)).unwrap();
        assert_eq!(
            serde_json::to_vec(&first).unwrap(),
            serde_json::to_vec(&second).unwrap()
        );
        let decoded: StationLayout =
            serde_json::from_slice(&serde_json::to_vec(&first).unwrap()).unwrap();
        validate_station_structure(&decoded).unwrap();
    }

    #[test]
    fn random_seeds_are_real_layouts_not_reflections_of_a_canonical_seed() {
        let mut signatures = BTreeSet::new();
        for seed in 1..=64 {
            let layout =
                generate(&request(seed)).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            validate_station_structure(&layout).unwrap();
            signatures.insert(
                layout
                    .tiles
                    .iter()
                    .map(|tile| (tile.class as u8, tile.owner, tile.room, tile.flags))
                    .collect::<Vec<_>>(),
            );
        }
        assert!(
            signatures.len() >= 48,
            "only {} genuinely distinct layouts",
            signatures.len()
        );
    }

    #[test]
    fn random_seeds_vary_physical_department_adjacency() {
        let mut signatures = BTreeSet::new();
        for seed in 1..=32 {
            let layout =
                generate(&request(seed)).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            assert_eq!(
                layout.graph.department_edges.len(),
                layout.departments.len() - 1
            );
            let mut edges = layout
                .graph
                .department_edges
                .iter()
                .map(|(left, right)| (*left.min(right), *left.max(right)))
                .collect::<Vec<_>>();
            edges.sort_unstable();
            signatures.insert(edges);
        }
        assert!(
            signatures.len() >= 8,
            "only {} physical department adjacency graphs",
            signatures.len()
        );
    }

    #[test]
    fn every_room_type_minimum_is_instantiated() {
        for seed in 100..116 {
            let request = request(seed);
            let layout = generate(&request).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            for department in &request.departments {
                for room_type in &department.room_types {
                    let count = layout
                        .rooms
                        .iter()
                        .filter(|room| {
                            room.department_id == department.id && room.room_type_id == room_type.id
                        })
                        .count();
                    assert!(count >= usize::from(room_type.min_count));
                    assert!(count <= usize::from(room_type.max_count));
                }
            }
        }
    }

    #[test]
    fn generated_geometry_has_no_unowned_interior_openings() {
        for seed in 200..232 {
            let layout =
                generate(&request(seed)).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            for room in &layout.rooms {
                assert!(!room.tiles.is_empty());
                assert!(!room.door_ids.is_empty());
            }
            assert!(layout.doors.iter().any(|door| door.connects_maintenance));
            validate_station_structure(&layout).unwrap();
        }
    }

    #[test]
    fn live_catalog_variants_do_not_collapse_into_local_hall_fields() {
        for seed in 1_000..1_064 {
            let layout = generate(&live_catalog_shape_request(seed))
                .unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            validate_station_structure(&layout).unwrap();
            let local = layout
                .tiles
                .iter()
                .filter(|tile| tile.class == TileClass::Local)
                .count();
            let rooms = layout
                .tiles
                .iter()
                .filter(|tile| tile.class == TileClass::Room)
                .count();
            assert!(
                local <= rooms,
                "seed {seed}: local circulation {local} exceeded the {rooms} room tiles"
            );
            for department in &layout.departments {
                let department_local = layout
                    .tiles
                    .iter()
                    .filter(|tile| {
                        tile.class == TileClass::Local && tile.owner == Some(department.id)
                    })
                    .count();
                let department_rooms = layout
                    .tiles
                    .iter()
                    .filter(|tile| {
                        tile.class == TileClass::Room && tile.owner == Some(department.id)
                    })
                    .count();
                assert!(
                    department_local <= department_rooms.saturating_mul(2),
                    "seed {seed}: department {} had {department_local} local tiles for {department_rooms} room tiles",
                    department.id
                );
                let distinct_roles = layout
                    .rooms
                    .iter()
                    .filter(|room| room.department_id == department.id)
                    .filter_map(|room| {
                        live_catalog_shape_request(seed)
                            .departments
                            .iter()
                            .find(|candidate| candidate.id == department.id)
                            .and_then(|candidate| {
                                candidate
                                    .room_types
                                    .iter()
                                    .find(|room_type| room_type.id == room.room_type_id)
                            })
                            .map(|room_type| room_type.name.clone())
                    })
                    .collect::<BTreeSet<_>>();
                assert!(
                    distinct_roles.len() >= 3,
                    "seed {seed}: department {} had only {} semantic rooms",
                    department.id,
                    distinct_roles.len()
                );
            }
        }
    }

    #[test]
    fn architectural_layout_matches_reference_proportions() {
        for seed in [9_2817, 314_159, 8_675_309, 2_607_281, 771_204, 4_200_731] {
            let layout = generate(&live_catalog_shape_request(seed))
                .unwrap_or_else(|error| panic!("seed {seed}: {error}"));
            let mut sizes = layout
                .rooms
                .iter()
                .map(|room| room.tiles.len())
                .collect::<Vec<_>>();
            sizes.sort_unstable();
            let median_size = sizes[sizes.len() / 2];
            let small_rooms = sizes.iter().filter(|size| **size <= 16).count();
            assert!(
                (30..=90).contains(&median_size),
                "seed {seed}: median room size {median_size} fell outside the Southern Cross reference band"
            );
            assert!(
                small_rooms * 10 <= sizes.len(),
                "seed {seed}: {small_rooms}/{} rooms were tiny",
                sizes.len()
            );

            let mut fill_millis = layout
                .rooms
                .iter()
                .map(|room| {
                    let min_x = room.tiles.iter().map(|point| point.x).min().unwrap();
                    let max_x = room.tiles.iter().map(|point| point.x).max().unwrap();
                    let min_y = room.tiles.iter().map(|point| point.y).min().unwrap();
                    let max_y = room.tiles.iter().map(|point| point.y).max().unwrap();
                    let envelope = usize::from(max_x - min_x + 1) * usize::from(max_y - min_y + 1);
                    room.tiles.len() * 1_000 / envelope.max(1)
                })
                .collect::<Vec<_>>();
            fill_millis.sort_unstable();
            let median_fill = fill_millis[fill_millis.len() / 2];
            let articulated_rooms = fill_millis.iter().filter(|fill| **fill < 980).count();
            assert!(
                median_fill >= 900,
                "seed {seed}: median room envelope fill was only {median_fill}‰"
            );
            assert!(
                articulated_rooms * 6 >= fill_millis.len(),
                "seed {seed}: only {articulated_rooms}/{} rooms had authored-suite articulation",
                fill_millis.len()
            );
            assert!(
                articulated_rooms * 5 <= fill_millis.len() * 3,
                "seed {seed}: {articulated_rooms}/{} rooms were irregular; the rectangular majority was lost",
                fill_millis.len()
            );

            let mut longest_public_run = 0usize;
            for y in 0..layout.height {
                let mut run = 0usize;
                for x in 0..layout.width {
                    if layout.tile(Point { x, y }).class == TileClass::Public {
                        run += 1;
                        longest_public_run = longest_public_run.max(run);
                    } else {
                        run = 0;
                    }
                }
            }
            for x in 0..layout.width {
                let mut run = 0usize;
                for y in 0..layout.height {
                    if layout.tile(Point { x, y }).class == TileClass::Public {
                        run += 1;
                        longest_public_run = longest_public_run.max(run);
                    } else {
                        run = 0;
                    }
                }
            }
            assert!(
                longest_public_run <= 55,
                "seed {seed}: public corridor ran straight for {longest_public_run} tiles"
            );
        }
    }
}
