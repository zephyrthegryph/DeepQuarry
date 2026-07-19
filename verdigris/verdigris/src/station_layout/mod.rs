//! Deterministic, host-testable station architecture generation.

mod contract;
mod error;
mod ffi;
mod model;
mod render;
mod structural;

pub use contract::{decode_catalog, encode_plan};
pub use error::LayoutError;
pub use model::*;
pub use render::render_svg;
pub use structural::{generate_station_layout as generate, validate_station_structure};

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    fn request(seed: u64) -> LayoutRequest {
        let departments = (1..=7)
            .map(|department_id| {
                let room_types = (1..=6)
                    .map(|room_index| RoomType {
                        id: (department_id - 1) * 6 + room_index,
                        name: format!("room-{department_id}-{room_index}"),
                        min_width: if room_index == 1 { 7 } else { 4 },
                        max_width: 14,
                        min_height: if room_index == 1 { 6 } else { 4 },
                        max_height: 14,
                        min_count: u16::from(room_index <= 4),
                        max_count: 6,
                        entrances: 1,
                        content_area: if room_index == 1 { 42 } else { 24 },
                    })
                    .collect();
                DepartmentRequest {
                    id: department_id,
                    name: format!("Department {department_id}"),
                    weight: 10,
                    room_types,
                }
            })
            .collect();
        LayoutRequest {
            settings: StationSettings {
                seed,
                width: 112,
                height: 112,
                hull_thickness: 1,
                corridor_width: 3,
                maintenance_width: 3,
                room_jitter: 3,
            },
            departments,
        }
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
}
