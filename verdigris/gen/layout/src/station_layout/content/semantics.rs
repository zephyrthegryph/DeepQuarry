use super::*;

pub(super) fn plan_networks(
    layout: &StationLayout,
    fixtures: &mut [FixturePlacement],
) -> Vec<UtilityNetworkBlueprint> {
    let backbone: Vec<Point> = layout
        .tiles
        .iter()
        .enumerate()
        .filter_map(|(index, cell)| {
            matches!(cell.class, TileClass::Maintenance | TileClass::Local).then_some(Point {
                x: index as u16 % layout.width,
                y: index as u16 / layout.width,
            })
        })
        .collect();
    ["power", "atmos-supply", "atmos-return"]
        .into_iter()
        .map(|kind| UtilityNetworkBlueprint {
            id: format!("station-{kind}"),
            kind: kind.into(),
            backbone: backbone.clone(),
            endpoint_fixture_ids: fixtures
                .iter_mut()
                .filter_map(|fixture| {
                    let matches = (kind == "power" && fixture.fixture_id == "apc")
                        || fixture.network_id.as_deref() == Some(kind);
                    if matches {
                        fixture.network_id = Some(format!("station-{kind}"));
                        Some(fixture.id)
                    } else {
                        None
                    }
                })
                .collect(),
        })
        .collect()
}

pub(super) fn counterpart_profile(role: &str) -> CounterpartProfile {
    let (reference_role, minimum_cluster_micros) = if has(role, &["surgery"]) {
        ("surgery", 650_000)
    } else if has(role, &["treatment", "exam", "emergency"]) {
        ("treatment", 650_000)
    } else if has(role, &["ward", "recovery"]) {
        ("ward", 600_000)
    } else if has(role, &["laboratory", "research", "analysis"]) {
        ("laboratory", 650_000)
    } else if has(role, &["ai", "core", "server"]) {
        ("ai", 650_000)
    } else if has(role, &["armory"]) {
        ("armory", 650_000)
    } else if has(role, &["brig", "interrogation", "checkpoint"]) {
        ("brig", 600_000)
    } else if has(role, &["security", "evidence", "locker-room"]) {
        ("security", 600_000)
    } else if has(
        role,
        &["operations", "communications", "briefing", "meeting"],
    ) {
        ("operations", 650_000)
    } else if has(role, &["office", "records", "liaison"]) {
        ("office", 600_000)
    } else if has(role, &["reception", "foyer"]) {
        ("reception", 600_000)
    } else if has(
        role,
        &["storage", "warehouse", "cargo", "inventory", "equipment"],
    ) {
        ("storage", 600_000)
    } else if has(role, &["workshop", "engineering", "power", "tool-room"]) {
        ("workshop", 600_000)
    } else if has(role, &["atmospherics", "maintenance"]) {
        ("atmospherics", 550_000)
    } else if has(role, &["dispatch", "processing", "cargo"]) {
        ("cargo", 600_000)
    } else if has(role, &["docking", "customs", "control"]) {
        ("docking", 550_000)
    } else if has(role, &["robotics"]) {
        ("robotics", 600_000)
    } else {
        ("general", 550_000)
    };
    let measured = southern_cross_reference()
        .profiles
        .get(reference_role)
        .or_else(|| southern_cross_reference().profiles.get("general"))
        .expect("Southern Cross reference must contain a general profile");
    CounterpartProfile {
        minimum_cluster_micros,
        // The DMM contains incidental item subfamilies that the blueprint
        // intentionally represents as one semantic fixture category.
        minimum_unique_fixtures: measured.unique_fixture_types_p25.clamp(4, 8),
        // Very large hangars legitimately lower the mapped p25. Generated
        // activity rooms are smaller, so never accept the visually empty tail.
        minimum_occupancy_micros: measured.occupancy_p25_micros.clamp(250_000, 550_000),
        target_occupancy_micros: measured.occupancy_median_micros.clamp(320_000, 550_000),
        maximum_empty_region_micros: measured.largest_empty_region_p75_micros.min(750_000),
        // Absolute counts are size-sensitive; cap the mapped p25 while density
        // and empty-region ratios carry the scale-independent comparison.
        minimum_fixture_count: measured.fixture_count_p25.clamp(4, 12),
    }
}

pub(super) fn composition_hash(mut seed: u64, point: Point) -> u64 {
    seed ^= u64::from(point.x) << 32 | u64::from(point.y);
    seed ^= seed >> 30;
    seed = seed.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    seed ^= seed >> 27;
    seed = seed.wrapping_mul(0x94d0_49bb_1331_11eb);
    seed ^ (seed >> 31)
}

pub(super) fn semantic_fixture_program(role: &str) -> Vec<FixtureSpec> {
    let ids: &[&str] = if has(role, &["armory"]) {
        &[
            "armory_autolathe",
            "secure_locker",
            "weapon_rack",
            "security_console",
        ]
    } else if has(role, &["evidence"]) {
        &[
            "security_records",
            "filing_cabinet",
            "evidence_cabinet",
            "secure_locker",
        ]
    } else if has(role, &["records", "archive"]) {
        &[
            "role_console",
            "filing_cabinet",
            "id_console",
            "worktable",
            "chair",
        ]
    } else if has(role, &["robotics", "server-closet"]) {
        &["robotics_console", "autolathe", "server_rack", "worktable"]
    } else if has(role, &["interrogation", "checkpoint"]) {
        &[
            "security_records",
            "reinforced_table",
            "chair",
            "secure_locker",
        ]
    } else if has(role, &["pharmacy"]) {
        &["chem_master", "reagent_grinder", "sink", "medical_cabinet"]
    } else if has(role, &["recovery"]) {
        &["sleeper", "iv_drip", "medical_bed", "medical_cabinet"]
    } else if has(role, &["maintenance"]) {
        &["autolathe", "air_sensor", "workbench", "tool_rack"]
    } else if has(role, &["dispatch"]) {
        &[
            "supply_console",
            "communications_console",
            "loading_table",
            "crate_rack",
        ]
    } else if has(role, &["customs"]) {
        &["id_console", "security_records", "filing_cabinet", "chair"]
    } else if has(role, &["exam"]) {
        &["sink", "medical_vendor", "medical_bed", "medical_cabinet"]
    } else if has(role, &["surgery", "treatment"]) {
        &[
            "operating_table",
            "medical_console",
            "anesthetic",
            "medical_cabinet",
            "sink",
        ]
    } else if has(role, &["laboratory", "research", "analysis"]) {
        &[
            "research_console",
            "experiment_table",
            "analyzer",
            "reagent_storage",
            "server",
        ]
    } else if has(role, &["security", "armory", "brig", "evidence"]) {
        &[
            "security_console",
            "security_records",
            "weapon_rack",
            "secure_locker",
            "evidence_cabinet",
            "flash",
        ]
    } else if has(role, &["workshop", "equipment", "tool-room"]) {
        &["autolathe", "electrical_locker", "workbench", "tool_rack"]
    } else if has(role, &["engineering", "power"]) {
        &[
            "engineering_console",
            "workbench",
            "tool_rack",
            "parts_bin",
            "generator_control",
        ]
    } else if has(role, &["command", "operations", "meeting", "briefing"]) {
        &[
            "command_console",
            "holotable",
            "conference_table",
            "executive_chair",
            "filing_cabinet",
        ]
    } else if has(role, &["kitchen", "galley", "food"]) {
        &["grill", "food_prep", "sink", "fridge", "serving_counter"]
    } else if has(role, &["hydro", "garden", "botany"]) {
        &[
            "hydroponics_tray",
            "seed_extractor",
            "plant_analyzer",
            "water_tank",
            "produce_bin",
        ]
    } else if has(
        role,
        &["warehouse", "cargo", "sorting", "storage", "inventory"],
    ) {
        &[
            "supply_crate",
            "disposal_unit",
            "cargo_console",
            "loading_table",
            "crate_rack",
            "package_scanner",
        ]
    } else if has(role, &["ai", "core", "satellite", "monitoring"]) {
        &[
            "ai_core",
            "server_rack",
            "control_console",
            "coolant_unit",
            "data_terminal",
        ]
    } else if has(role, &["reception", "foyer", "liaison"]) {
        &[
            "reception_desk",
            "visitor_console",
            "filing_cabinet",
            "waiting_bench",
            "plant",
        ]
    } else {
        &[
            "role_console",
            "worktable",
            "department_locker",
            "filing_cabinet",
            "chair",
        ]
    };
    ids.iter()
        .map(|id| FixtureSpec {
            id,
            layer: if id.contains("console") || id.contains("analyzer") || id.contains("core") {
                FixtureLayer::Machine
            } else {
                FixtureLayer::Furniture
            },
        })
        .collect()
}

pub(super) fn semantic_fillers(role: &str) -> Vec<FixtureSpec> {
    let ids: &[&str] = if has(
        role,
        &[
            "storage",
            "warehouse",
            "cargo",
            "equipment",
            "inventory",
            "sorting",
        ],
    ) {
        &[
            "crate_rack",
            "supply_crate",
            "shelf",
            "pallet",
            "freight_cart",
            "packing_table",
            "manifest_board",
            "cargo_bin",
        ]
    } else if has(role, &["medical", "treatment", "surgery", "recovery"]) {
        &[
            "medical_bed",
            "privacy_screen",
            "medical_cabinet",
            "stool",
            "iv_stand",
            "instrument_table",
            "wash_station",
            "medicine_cart",
        ]
    } else if has(
        role,
        &[
            "security",
            "brig",
            "armory",
            "evidence",
            "checkpoint",
            "interrogation",
        ],
    ) {
        &[
            "reinforced_table",
            "secure_locker",
            "evidence_cabinet",
            "weapon_rack",
            "filing_cabinet",
            "security_records",
        ]
    } else if has(role, &["ai", "core", "server", "monitoring", "satellite"]) {
        &[
            "server_rack",
            "data_terminal",
            "coolant_unit",
            "parts_cabinet",
            "worktable",
            "filing_cabinet",
        ]
    } else if has(
        role,
        &[
            "engineering",
            "power",
            "atmospherics",
            "workshop",
            "tool-room",
            "maintenance",
        ],
    ) {
        &[
            "workbench",
            "tool_rack",
            "parts_bin",
            "electrical_locker",
            "tool_cart",
            "parts_cabinet",
        ]
    } else if has(role, &["laboratory", "research", "analysis", "robotics"]) {
        &[
            "experiment_table",
            "analyzer",
            "reagent_storage",
            "server_rack",
            "parts_cabinet",
            "worktable",
        ]
    } else if has(role, &["meeting", "briefing", "reception", "foyer"]) {
        &[
            "chair",
            "table",
            "plant",
            "notice_board",
            "visitor_bench",
            "display_case",
            "water_cooler",
            "side_table",
        ]
    } else {
        &[
            "worktable",
            "locker",
            "shelf",
            "filing_cabinet",
            "side_table",
            "display_case",
            "notice_board",
        ]
    };
    ids.iter()
        .map(|id| FixtureSpec {
            id,
            layer: FixtureLayer::Furniture,
        })
        .collect()
}

pub(super) fn fixture_blocks(id: &str) -> bool {
    // Be conservative here: this flag protects actual player navigation, not
    // visual overlap. Most live furniture and machinery types are dense (and
    // several historically misclassified exceptions, including cabinets and
    // racks, caused Rust-valid paths to be blocked after DM materialization).
    // Only turf-integrated atmospheric endpoints are known walk-through.
    !matches!(
        id,
        "vent"
            | "scrubber"
            | "wall_light"
            | "air_alarm"
            | "fire_alarm"
            | "apc"
            | "notice_board"
            | "manifest_board"
    )
}

pub(super) fn fixture_blocks_on_layer(id: &str, layer: FixtureLayer) -> bool {
    layer != FixtureLayer::Wall && layer != FixtureLayer::Ceiling && fixture_blocks(id)
}

pub(super) fn fixture_is_wall_mounted(id: &str) -> bool {
    matches!(
        id,
        "wall_light" | "air_alarm" | "fire_alarm" | "apc" | "notice_board" | "manifest_board"
    )
}

pub(super) fn fixture_prefers_corner(id: &str) -> bool {
    matches!(
        id,
        "plant" | "display_case" | "water_cooler" | "cargo_bin" | "tool_cart"
    )
}

pub(super) fn fixture_prefers_perimeter(id: &str) -> bool {
    fixture_prefers_corner(id)
        || id.contains("locker")
        || id.contains("cabinet")
        || id.contains("rack")
        || id.contains("console")
        || matches!(
            id,
            "shelf"
                | "server"
                | "server_rack"
                | "autolathe"
                | "armory_autolathe"
                | "fridge"
                | "medical_vendor"
                | "engineering_vendor"
        )
}

pub(super) fn wall_neighbor_count(layout: &StationLayout, point: Point) -> usize {
    directed_neighbors(layout, point)
        .into_iter()
        .filter(|(neighbor, _)| {
            matches!(
                layout.tile(*neighbor).class,
                TileClass::Hull | TileClass::Structure | TileClass::Partition
            )
        })
        .count()
}

pub(super) fn fixture_requires_fixed_facing(id: &str) -> bool {
    matches!(id, "sink" | "wash_station")
}
pub(super) fn fixture_repeat_limit(id: &str) -> usize {
    if id == "wall_light" {
        16
    } else if matches!(id, "vent" | "scrubber" | "air_alarm" | "fire_alarm" | "apc")
        || id.contains("chair")
        || id.contains("table")
        || id.contains("bed")
        || matches!(id, "stool" | "visitor_bench" | "supply_crate" | "pallet")
    {
        4
    } else if id.contains("locker") || id.contains("cabinet") || id.contains("rack") {
        3
    } else {
        // A specialized machine or decoration should normally appear once,
        // with a second copy available for authored paired workstations.
        // Role-specific capacity fixtures receive narrow exceptions below.
        2
    }
}

pub(super) fn fixture_repeat_limit_for_role(role: &str, id: &str) -> usize {
    match (role, id) {
        ("records" | "archive", "filing_cabinet") => 6,
        ("evidence", "evidence_cabinet") => 5,
        ("armory", "weapon_rack" | "secure_locker") => 5,
        ("server-closet" | "support" | "secure-storage", "server_rack") => 4,
        ("recovery" | "ward", "medical_bed" | "iv_stand" | "privacy_screen") => 5,
        ("storage" | "supply" | "warehouse", "supply_crate" | "pallet" | "storage_rack") => 5,
        ("locker-room", id) if id.contains("locker") => 6,
        ("meeting" | "briefing" | "canteen", id)
            if id.contains("chair") || id.contains("table") =>
        {
            6
        }
        _ => fixture_repeat_limit(id),
    }
}

pub(super) fn add_tabletop_charger_supports(
    room: &Room,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
    next_fixture_id: &mut u32,
) {
    let chargers = room_fixture_ids
        .iter()
        .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
        .filter(|fixture| fixture.fixture_id == "equipment_recharger")
        .map(|fixture| (fixture.at, fixture.facing, fixture.variant))
        .collect::<Vec<_>>();
    for (at, facing, variant) in chargers {
        let id = *next_fixture_id;
        *next_fixture_id += 1;
        fixtures.push(FixturePlacement {
            id,
            fixture_id: "charger_table".into(),
            at,
            facing,
            layer: FixtureLayer::Furniture,
            department_id: room.department_id,
            room_id: Some(room.id),
            network_id: None,
            variant,
            blocks_movement: true,
            required_access: Vec::new(),
        });
        room_fixture_ids.push(id);
    }
    // Materialization and preview rendering must instantiate the support
    // before the tabletop machine occupying the same turf.
    fixtures.sort_by_key(|fixture| {
        (
            fixture.room_id,
            fixture.at,
            u8::from(fixture.fixture_id != "charger_table"),
            fixture.id,
        )
    });
}

pub(super) fn orient_perimeter_fixtures_into_room(
    room: &Room,
    tiles: &BTreeSet<Point>,
    blocking: &BTreeSet<Point>,
    room_fixture_ids: &[u32],
    fixtures: &mut [FixturePlacement],
    center: Point,
) {
    for fixture in fixtures.iter_mut().filter(|fixture| {
        fixture.room_id == Some(room.id)
            && room_fixture_ids.contains(&fixture.id)
            && fixture.layer != FixtureLayer::Wall
            && fixture.layer != FixtureLayer::Ceiling
            && fixture_prefers_perimeter(&fixture.fixture_id)
    }) {
        let mut facings = [Facing::North, Facing::East, Facing::South, Facing::West]
            .into_iter()
            .filter_map(|facing| {
                let access = step_facing(fixture.at, facing);
                (tiles.contains(&access) && !blocking.contains(&access)).then_some((facing, access))
            })
            .collect::<Vec<_>>();
        facings.sort_by_key(|(_, access)| (distance(*access, center), access.y, access.x));
        let Some((facing, access)) = facings.first().copied() else {
            continue;
        };
        fixture.facing = facing;
        if fixture.blocks_movement {
            fixture.required_access = vec![access];
        }
    }
}

pub(super) fn prune_orphaned_seats(
    tiles: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    floor_candidates: &mut Vec<Point>,
    occupied: &mut BTreeSet<Point>,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
) {
    let room_fixtures = room_fixture_ids
        .iter()
        .filter_map(|id| fixtures.iter().find(|fixture| fixture.id == *id))
        .collect::<Vec<_>>();
    let remove_ids = room_fixtures
        .iter()
        .filter(|fixture| {
            (fixture.fixture_id.contains("chair") || fixture.fixture_id.contains("stool"))
                && !room_fixtures.iter().any(|other| {
                    fixture.id != other.id
                        && distance(fixture.at, other.at) == 1
                        && fixture_supports_seat(&other.fixture_id)
                })
        })
        .map(|fixture| fixture.id)
        .collect::<BTreeSet<_>>();
    for fixture in room_fixtures {
        if remove_ids.contains(&fixture.id) {
            occupied.remove(&fixture.at);
            if tiles.contains(&fixture.at) && !doors.contains(&fixture.at) {
                floor_candidates.push(fixture.at);
            }
        }
    }
    room_fixture_ids.retain(|id| !remove_ids.contains(id));
    fixtures.retain(|fixture| !remove_ids.contains(&fixture.id));
    floor_candidates.sort_unstable();
    floor_candidates.dedup();
}

pub(super) fn fixture_supports_seat(id: &str) -> bool {
    // charger_table is a same-tile render support for a recharger, not usable
    // furniture. Counting it paired nearby chairs that became visibly orphaned
    // once semantic validation intentionally hid the support object.
    id != "charger_table"
        && (id.contains("table")
            || id.contains("desk")
            || id.contains("bench")
            || id.contains("console")
            || id.contains("monitor")
            || id.contains("bed")
            || matches!(id, "visitor_bench" | "waiting_bench" | "side_table"))
}

// Mutates 5 independent pieces of the same room-fill working set in
// place; bundling them into a struct here would just move the same
// 8-field initializer into the single call site instead of removing it.
#[allow(clippy::too_many_arguments)]
pub(super) fn prune_excess_room_repetitions(
    role: &str,
    tiles: &BTreeSet<Point>,
    doors: &BTreeSet<Point>,
    floor_candidates: &mut Vec<Point>,
    occupied: &mut BTreeSet<Point>,
    blocking: &mut BTreeSet<Point>,
    fixtures: &mut Vec<FixturePlacement>,
    room_fixture_ids: &mut Vec<u32>,
) {
    let mut counts = BTreeMap::<String, usize>::new();
    let mut remove_ids = BTreeSet::new();
    for fixture_id in room_fixture_ids.iter().copied() {
        let Some(fixture) = fixtures.iter().find(|fixture| fixture.id == fixture_id) else {
            continue;
        };
        if fixture.layer == FixtureLayer::Wall || fixture.layer == FixtureLayer::Ceiling {
            continue;
        }
        let count = counts.entry(fixture.fixture_id.clone()).or_default();
        *count += 1;
        if *count > fixture_repeat_limit_for_role(role, &fixture.fixture_id) {
            remove_ids.insert(fixture_id);
            occupied.remove(&fixture.at);
            blocking.remove(&fixture.at);
            if tiles.contains(&fixture.at) && !doors.contains(&fixture.at) {
                floor_candidates.push(fixture.at);
            }
        }
    }
    if remove_ids.is_empty() {
        return;
    }
    room_fixture_ids.retain(|id| !remove_ids.contains(id));
    fixtures.retain(|fixture| !remove_ids.contains(&fixture.id));
    floor_candidates.sort_unstable();
    floor_candidates.dedup();
}

pub(super) fn fixture_repetitions_within_limits<'a>(
    placements: impl IntoIterator<Item = &'a AuthoredCompositionPlacement>,
) -> bool {
    let mut counts = BTreeMap::<&str, usize>::new();
    for placement in placements {
        let count = counts.entry(placement.fixture_id.as_str()).or_default();
        *count += 1;
        if *count > fixture_repeat_limit(&placement.fixture_id) {
            return false;
        }
    }
    true
}

pub(super) fn placement_seats_are_paired<'a>(
    placements: impl IntoIterator<Item = &'a AuthoredCompositionPlacement>,
) -> bool {
    let placements = placements.into_iter().collect::<Vec<_>>();
    placements.iter().all(|chair| {
        let is_seat = chair.fixture_id.contains("chair")
            || matches!(chair.fixture_id.as_str(), "stool" | "executive_chair");
        !is_seat
            || placements.iter().any(|other| {
                chair.at != other.at
                    && distance(chair.at, other.at) == 1
                    && (other.fixture_id.contains("table")
                        || other.fixture_id.contains("desk")
                        || other.fixture_id.contains("bench")
                        || other.fixture_id.contains("console")
                        || other.fixture_id.contains("bed")
                        || matches!(
                            other.fixture_id.as_str(),
                            "visitor_bench" | "waiting_bench" | "side_table"
                        ))
            })
    })
}
