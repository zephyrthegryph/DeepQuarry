use super::contract::CatalogMapping;
use super::error::LayoutError;
use super::model::*;
use super::program::{
    ActivityZone, ProgramAnchor, ProgramLayer, RoomProgram, compact_room_program, room_program,
};
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::OnceLock;
mod fixtures;
mod generate;
mod geometry;
mod placement;
mod semantics;
mod validate;
use self::fixtures::*;
use self::geometry::*;
use self::placement::*;
use self::semantics::*;
pub use self::generate::generate_station_blueprint;
pub use self::validate::validate_station_blueprint;

// Generate above the acceptance floor so final semantic pruning (for example,
// removing chairs whose support moved to a wall) cannot leave the live room
// below 30% visible occupancy.
const MIN_OCCUPANCY_MICROS: u32 = 360_000;
const MAX_OCCUPANCY_MICROS: u32 = 520_000;

#[derive(Clone, Copy)]
struct FixtureSpec {
    id: &'static str,
    layer: FixtureLayer,
}

#[derive(Clone)]
struct AuthoredCompositionPlacement {
    at: Point,
    facing: Facing,
    fixture_id: String,
    layer: FixtureLayer,
}

#[derive(Clone, Copy)]
struct CounterpartProfile {
    minimum_cluster_micros: u32,
    minimum_unique_fixtures: usize,
    minimum_occupancy_micros: u32,
    target_occupancy_micros: u32,
    maximum_empty_region_micros: u32,
    minimum_fixture_count: usize,
}

#[derive(Deserialize)]
struct SouthernCrossReference {
    profiles: BTreeMap<String, SouthernCrossRoleProfile>,
}

#[derive(Clone, Copy, Deserialize)]
struct SouthernCrossRoleProfile {
    occupancy_p25_micros: u32,
    occupancy_median_micros: u32,
    largest_empty_region_p75_micros: u32,
    unique_fixture_types_p25: usize,
    fixture_count_p25: usize,
}

fn southern_cross_reference() -> &'static SouthernCrossReference {
    static REFERENCE: OnceLock<SouthernCrossReference> = OnceLock::new();
    REFERENCE.get_or_init(|| {
        serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../tools/generated_station/southern_cross_reference.json"
        )))
        .expect("measured Southern Cross room reference must remain valid JSON")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn southern_cross_reference_is_live_and_actionable() {
        let reference = southern_cross_reference();
        for role in [
            "general",
            "operations",
            "security",
            "surgery",
            "treatment",
            "ward",
            "workshop",
        ] {
            let profile = reference
                .profiles
                .get(role)
                .unwrap_or_else(|| panic!("missing measured Southern Cross role {role}"));
            assert!(profile.occupancy_median_micros >= profile.occupancy_p25_micros);
            assert!(profile.fixture_count_p25 > 0);
            assert!(profile.unique_fixture_types_p25 > 0);
            assert!(profile.largest_empty_region_p75_micros < 1_000_000);
        }
    }

    #[test]
    fn counterpart_profiles_require_density_and_bounded_empty_space() {
        for role in [
            "operations",
            "armory",
            "surgery",
            "treatment",
            "ward",
            "laboratory",
            "storage",
        ] {
            let profile = counterpart_profile(role);
            assert!(profile.minimum_occupancy_micros >= 250_000, "{role}");
            assert!(
                profile.target_occupancy_micros >= profile.minimum_occupancy_micros,
                "{role}"
            );
            assert!(profile.maximum_empty_region_micros <= 750_000, "{role}");
            assert!(profile.minimum_unique_fixtures >= 4, "{role}");
            assert!(profile.minimum_fixture_count >= 4, "{role}");
        }
    }

    #[test]
    fn specialized_equipment_cannot_be_used_as_density_spam() {
        for role in ["operations", "equipment", "armory", "laboratory"] {
            assert_eq!(
                fixture_repeat_limit_for_role(role, "equipment_recharger"),
                2
            );
            assert_eq!(fixture_repeat_limit_for_role(role, "armory_autolathe"), 2);
            assert_eq!(fixture_repeat_limit_for_role(role, "role_console"), 2);
        }
        assert_eq!(
            fixture_repeat_limit_for_role("surgery", "medical_cabinet"),
            3
        );
        assert_eq!(
            fixture_repeat_limit_for_role("records", "filing_cabinet"),
            6
        );
    }

    #[test]
    fn zone_placement_retries_every_rotation_before_giving_up_on_an_anchor() {
        // Regression test for a bug clippy::never_loop caught during the
        // rewrite/rustaudit pass: the rotation retry used to always try only
        // `rotation_offset`'s own turn and give up on the whole anchor
        // instead of trying the other 3 rotations. Two tiles in a vertical
        // strip; a fixture offset one cell to the *east* of the anchor only
        // lands on a real tile once rotated a quarter turn (which redirects
        // the offset to the *north* tile instead).
        let layout = StationLayout {
            seed: 1,
            width: 1,
            height: 2,
            archetype: MacroArchetype::Cross,
            tiles: vec![TileCell::default(); 2],
            departments: vec![],
            rooms: vec![],
            doors: vec![],
            public_circulation: vec![],
            maintenance: vec![],
            structure: vec![],
            hull: vec![],
            graph: LayoutGraph::default(),
            metadata: BTreeMap::new(),
        };
        let tiles = BTreeSet::from([Point { x: 0, y: 0 }, Point { x: 0, y: 1 }]);
        let env = ZonePlacementEnv {
            layout: &layout,
            tiles: &tiles,
            doors: &BTreeSet::new(),
            center: Point { x: 0, y: 0 },
        };
        let empty = BTreeSet::new();
        let zone = ActivityZone {
            id: "test-zone",
            anchor: ProgramAnchor::Center,
            required: true,
            repeatable: false,
            fixtures: vec![super::super::program::ProgramFixture {
                id: "vent",
                dx: 1,
                dy: 0,
                layer: ProgramLayer::Furniture,
            }],
        };
        let anchor = Point { x: 0, y: 0 };

        // Unrotated (turns = 0), the fixture's (dx=1, dy=0) offset lands on
        // (1, 0), which isn't one of the room's two tiles: this rotation
        // must fail.
        assert!(
            try_place_zone_at(&env, &empty, &empty, &empty, &zone, anchor, 0).is_none(),
            "turns=0 should not fit: (1,0) is not a tile in this room"
        );

        // Rotated one quarter turn, (dx=1, dy=0) becomes (0, 1) (see
        // `program_rotate_offset`), landing on the room's other tile: this
        // rotation must succeed. Before the fix, the caller never reached
        // this rotation at all for a given anchor.
        let placed = try_place_zone_at(&env, &empty, &empty, &empty, &zone, anchor, 1);
        let (placements, _blocking, _access) =
            placed.expect("turns=1 should fit: (0,1) is the room's other tile");
        assert_eq!(placements.len(), 1);
        assert_eq!(placements[0].at, Point { x: 0, y: 1 });
    }
}
