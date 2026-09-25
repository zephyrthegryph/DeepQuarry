#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProgramAnchor {
    Center,
    Perimeter,
    Entrance,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProgramLayer {
    Furniture,
    Machine,
    Wall,
}

#[derive(Clone, Debug)]
pub struct ProgramFixture {
    pub id: &'static str,
    pub dx: i16,
    pub dy: i16,
    pub layer: ProgramLayer,
}

#[derive(Clone, Debug)]
pub struct ActivityZone {
    pub id: &'static str,
    pub anchor: ProgramAnchor,
    pub required: bool,
    pub repeatable: bool,
    pub fixtures: Vec<ProgramFixture>,
}

#[derive(Clone, Debug)]
pub struct RoomProgram {
    pub id: String,
    pub minimum_area: u32,
    pub ideal_area: u32,
    pub maximum_area: u32,
    pub zones: Vec<ActivityZone>,
}

const F: ProgramLayer = ProgramLayer::Furniture;
const M: ProgramLayer = ProgramLayer::Machine;

fn fixture(id: &'static str, dx: i16, dy: i16, layer: ProgramLayer) -> ProgramFixture {
    ProgramFixture { id, dx, dy, layer }
}

fn zone(
    id: &'static str,
    anchor: ProgramAnchor,
    required: bool,
    fixtures: Vec<ProgramFixture>,
) -> ActivityZone {
    ActivityZone {
        id,
        anchor,
        required,
        repeatable: matches!(
            id,
            "waiting"
                | "archive-wall"
                | "bed-row"
                | "locker-bank"
                | "evidence-bank"
                | "cells"
                | "ward-bay"
                | "medical-storage"
                | "equipment-wall"
                | "storage-row"
                | "loading"
                | "sorting-line"
                | "seating"
                | "patient-bay"
        ),
        fixtures,
    }
}

fn support_zone(department: &str, _role: &str, variant: u64) -> ActivityZone {
    use ProgramAnchor::{Center, Entrance, Perimeter};

    let anchor = match variant % 3 {
        0 => Perimeter,
        1 => Center,
        _ => Entrance,
    };
    let (id, fixtures) = match (department, variant % 3) {
        ("command", 0) => (
            "administration-archive",
            vec![
                fixture("filing_cabinet", -2, 0, F),
                fixture("filing_cabinet", -1, 0, F),
                fixture("id_console", 0, 0, M),
                fixture("notice_board", 1, 0, F),
            ],
        ),
        ("command", 1) => (
            "administration-consultation",
            vec![
                fixture("side_table", -1, 0, F),
                fixture("visitor_bench", 0, 0, F),
                fixture("communications_console", 1, 0, M),
                fixture("plant", 2, 0, F),
            ],
        ),
        ("command", _) => (
            "administration-aide",
            vec![
                fixture("worktable", -1, 0, F),
                fixture("work_chair", -1, 1, F),
                fixture("role_console", 0, 0, M),
                fixture("filing_cabinet", 1, 0, F),
            ],
        ),
        ("ai", 0) => (
            "technical-server-bank",
            vec![
                fixture("server_rack", -2, 0, M),
                fixture("server", -1, 0, M),
                fixture("coolant_unit", 0, 0, M),
                fixture("server_rack", 1, 0, M),
            ],
        ),
        ("ai", 1) => (
            "technical-diagnostics",
            vec![
                fixture("crew_monitor", -1, 0, M),
                fixture("worktable", 0, 0, F),
                fixture("operator_chair", 0, 1, F),
                fixture("equipment_recharger", 1, 0, M),
            ],
        ),
        ("ai", _) => (
            "technical-service",
            vec![
                fixture("workbench", -1, 0, F),
                fixture("parts_bin", 0, 0, F),
                fixture("electrical_locker", 1, 0, F),
                fixture("tool_cart", 2, 0, F),
            ],
        ),
        ("security", 0) => (
            "security-ready",
            vec![
                fixture("equipment_recharger", -1, 0, M),
                fixture("department_locker", 0, 0, F),
                fixture("weapon_rack", 1, 0, F),
                fixture("flash", 2, 0, M),
            ],
        ),
        ("security", 1) => (
            "security-records",
            vec![
                fixture("security_records", -1, 0, M),
                fixture("filing_cabinet", 0, 0, F),
                fixture("worktable", 1, 0, F),
                fixture("work_chair", 1, 1, F),
            ],
        ),
        ("security", _) => (
            "security-observation",
            vec![
                fixture("security_console", -1, 0, M),
                fixture("worktable", 0, 0, F),
                fixture("operator_chair", 0, 1, F),
                fixture("secure_locker", 1, 0, F),
            ],
        ),
        ("medical", 0) => (
            "clinical-cleanup",
            vec![
                fixture("wash_station", -1, 0, F),
                fixture("medicine_cart", 0, 0, F),
                fixture("medical_cabinet", 1, 0, F),
                fixture("reagent_storage", 2, 0, F),
            ],
        ),
        ("medical", 1) => (
            "clinical-diagnostics",
            vec![
                fixture("medical_console", -1, 0, M),
                fixture("instrument_table", 0, 0, F),
                fixture("stool", 0, 1, F),
                fixture("analyzer", 1, 0, M),
                fixture("medical_vendor", 2, 0, M),
            ],
        ),
        ("medical", _) => (
            "clinical-preparation",
            vec![
                fixture("instrument_table", -1, 0, F),
                fixture("iv_stand", 0, 0, F),
                fixture("medical_locker", 1, 0, F),
                fixture("privacy_screen", 2, 0, F),
            ],
        ),
        ("engineering", 0) => (
            "engineering-parts",
            vec![
                fixture("parts_cabinet", -1, 0, F),
                fixture("parts_bin", 0, 0, F),
                fixture("tool_rack", 1, 0, F),
                fixture("tool_cart", 2, 0, F),
            ],
        ),
        ("engineering", 1) => (
            "engineering-control",
            vec![
                fixture("engineering_console", -1, 0, M),
                fixture("worktable", 0, 0, F),
                fixture("stool", 0, 1, F),
                fixture("power_monitor", 1, 0, M),
                fixture("electrical_locker", 2, 0, F),
            ],
        ),
        ("engineering", _) => (
            "engineering-service",
            vec![
                fixture("workbench", -1, 0, F),
                fixture("engineering_vendor", 0, 0, M),
                fixture("equipment_recharger", 1, 0, M),
                fixture("air_canister", 2, 0, F),
            ],
        ),
        ("logistics", 0) => (
            "freight-staging",
            vec![
                fixture("pallet", -1, 0, F),
                fixture("supply_crate", 0, 0, F),
                fixture("freight_cart", 1, 0, F),
                fixture("crate_rack", 2, 0, F),
            ],
        ),
        ("logistics", 1) => (
            "freight-accounting",
            vec![
                fixture("manifest_board", -1, 0, F),
                fixture("package_scanner", 0, 0, M),
                fixture("worktable", 1, 0, F),
                fixture("work_chair", 1, 1, F),
            ],
        ),
        ("logistics", _) => (
            "freight-sorting",
            vec![
                fixture("packing_table", -1, 0, F),
                fixture("cargo_bin", 0, 0, F),
                fixture("disposal_unit", 1, 0, M),
                fixture("loading_table", 2, 0, F),
            ],
        ),
        ("docking", 0) => (
            "passenger-waiting",
            vec![
                fixture("visitor_bench", -1, 0, F),
                fixture("side_table", 0, 0, F),
                fixture("visitor_bench", 1, 0, F),
                fixture("plant", 2, 0, F),
            ],
        ),
        ("docking", 1) => (
            "passenger-information",
            vec![
                fixture("display_case", -1, 0, F),
                fixture("visitor_console", 0, 0, M),
                fixture("communications_console", 1, 0, M),
                fixture("water_cooler", 2, 0, F),
            ],
        ),
        ("docking", _) => (
            "passenger-service",
            vec![
                fixture("reception_desk", -1, 0, F),
                fixture("id_console", 0, 0, M),
                fixture("operator_chair", 0, 1, F),
                fixture("department_locker", 1, 0, F),
            ],
        ),
        _ => (
            "general-support",
            vec![
                fixture("shelf", -1, 0, F),
                fixture("worktable", 0, 0, F),
                fixture("work_chair", 0, 1, F),
                fixture("locker", 1, 0, F),
            ],
        ),
    };
    zone(id, anchor, false, fixtures)
}

fn program(
    department: &str,
    role: &str,
    variant: u64,
    minimum_area: u32,
    ideal_area: u32,
    mut zones: Vec<ActivityZone>,
) -> RoomProgram {
    // Every normal-sized room gets a third, purpose-specific work cell.
    // Earlier "variants" only changed the label; this makes the variant alter
    // both where the support activity lives and, for role-sensitive programs,
    // what it contains.
    if zones.len() < 3 {
        zones.push(support_zone(department, role, variant));
    }
    RoomProgram {
        id: format!("{department}-{role}-workflow-{}", variant % 3 + 1),
        minimum_area,
        ideal_area,
        maximum_area: ideal_area.saturating_mul(2).min(64).max(minimum_area),
        zones,
    }
}

/// Functional room programs are the authoritative content and capacity
/// contract. They describe workflows and relationships, never density filler.
pub fn room_program(department: &str, role: &str, variant: u64) -> RoomProgram {
    use ProgramAnchor::{Center, Entrance, Perimeter};
    let program_variant = variant % 3;
    match (department, role) {
        ("command", "reception" | "liaison") => program(
            department,
            role,
            program_variant,
            28,
            44,
            vec![
                zone(
                    "service-frontage",
                    Entrance,
                    true,
                    vec![
                        fixture("reception_desk", -1, 0, F),
                        fixture("visitor_console", 0, 0, M),
                        fixture("reception_desk", 1, 0, F),
                        fixture("work_chair", 0, -1, F),
                    ],
                ),
                zone(
                    "waiting",
                    Perimeter,
                    true,
                    vec![
                        fixture("side_table", 0, 0, F),
                        fixture("visitor_bench", -1, 0, F),
                        fixture("visitor_bench", 1, 0, F),
                        fixture("plant", 2, 0, F),
                    ],
                ),
            ],
        ),
        ("command", "communications" | "operations") => program(
            department,
            role,
            program_variant,
            32,
            52,
            vec![
                zone(
                    "operations-bank",
                    Perimeter,
                    true,
                    vec![
                        fixture("communications_console", -2, 0, M),
                        fixture("crew_monitor", -1, 0, M),
                        fixture("command_console", 0, 0, M),
                        fixture("data_terminal", 1, 0, M),
                        fixture("id_console", 2, 0, M),
                    ],
                ),
                zone(
                    "operator-desks",
                    Center,
                    true,
                    vec![
                        fixture("worktable", -1, 0, F),
                        fixture("operator_chair", -1, -1, F),
                        fixture("worktable", 1, 0, F),
                        fixture("operator_chair", 1, -1, F),
                    ],
                ),
            ],
        ),
        ("command", "meeting" | "briefing") => program(
            department,
            role,
            program_variant,
            36,
            58,
            vec![
                zone(
                    "conference",
                    Center,
                    true,
                    vec![
                        fixture("conference_table", -1, 0, F),
                        fixture("conference_table", 0, 0, F),
                        fixture("conference_table", 1, 0, F),
                        fixture("executive_chair", -1, -1, F),
                        fixture("executive_chair", 0, -1, F),
                        fixture("executive_chair", 1, -1, F),
                        fixture("executive_chair", -1, 1, F),
                        fixture("executive_chair", 1, 1, F),
                    ],
                ),
                zone(
                    "presentation",
                    Perimeter,
                    true,
                    vec![
                        fixture("holotable", 0, 0, M),
                        fixture("communications_console", 1, 0, M),
                    ],
                ),
            ],
        ),
        ("command", "records" | "archive") => program(
            department,
            role,
            program_variant,
            30,
            48,
            vec![
                zone(
                    "archive-wall",
                    Perimeter,
                    true,
                    vec![
                        fixture("filing_cabinet", -2, 0, F),
                        fixture("filing_cabinet", -1, 0, F),
                        fixture("filing_cabinet", 0, 0, F),
                        fixture("filing_cabinet", 1, 0, F),
                        fixture("filing_cabinet", 2, 0, F),
                    ],
                ),
                zone(
                    "records-desk",
                    Center,
                    true,
                    vec![
                        fixture("worktable", 0, 0, F),
                        fixture("role_console", 1, 0, M),
                        fixture("work_chair", 0, -1, F),
                    ],
                ),
            ],
        ),
        ("ai", "core") => program(
            department,
            role,
            program_variant,
            36,
            56,
            vec![
                zone(
                    "core",
                    Center,
                    true,
                    vec![
                        fixture("ai_core", 0, 0, M),
                        fixture("server_rack", -2, 0, M),
                        fixture("server_rack", 2, 0, M),
                        fixture("coolant_unit", 0, -2, M),
                        fixture("control_console", 0, 2, M),
                    ],
                ),
                zone(
                    "upload",
                    Perimeter,
                    true,
                    vec![
                        fixture("ai_upload", -1, 0, M),
                        fixture("data_terminal", 0, 0, M),
                        fixture("robotics_console", 1, 0, M),
                    ],
                ),
            ],
        ),
        ("ai", "robotics") => workshop_program(department, role, program_variant, true),
        ("ai", "server-closet" | "support" | "secure-storage") => program(
            department,
            role,
            program_variant,
            24,
            38,
            vec![
                zone(
                    "server-bank",
                    Perimeter,
                    true,
                    vec![
                        fixture("server_rack", -2, 0, M),
                        fixture("server_rack", -1, 0, M),
                        fixture("coolant_unit", 0, 0, M),
                        fixture("server_rack", 1, 0, M),
                        fixture("server_rack", 2, 0, M),
                    ],
                ),
                zone(
                    "service-console",
                    Entrance,
                    true,
                    vec![
                        fixture("control_console", 0, 0, M),
                        fixture("operator_chair", 0, -1, F),
                    ],
                ),
            ],
        ),
        ("ai", "foyer") => program(
            department,
            role,
            program_variant,
            24,
            38,
            vec![
                zone(
                    "secure-entry",
                    Entrance,
                    true,
                    vec![
                        fixture("reception_desk", -1, 0, F),
                        fixture("id_console", 0, 0, M),
                        fixture("operator_chair", -1, -1, F),
                        fixture("visitor_bench", 1, 0, F),
                    ],
                ),
                zone(
                    "status-display",
                    Perimeter,
                    true,
                    vec![
                        fixture("crew_monitor", -1, 0, M),
                        fixture("notice_board", 0, 0, F),
                        fixture("equipment_recharger", 1, 0, M),
                    ],
                ),
            ],
        ),
        ("ai", "satellite" | "monitoring") => program(
            department,
            role,
            program_variant,
            26,
            42,
            vec![
                zone(
                    "monitoring-bank",
                    Perimeter,
                    true,
                    vec![
                        fixture("ai_upload", -2, 0, M),
                        fixture("crew_monitor", -1, 0, M),
                        fixture("data_terminal", 0, 0, M),
                        fixture("communications_console", 1, 0, M),
                        fixture("server_rack", 2, 0, M),
                    ],
                ),
                zone(
                    "operator",
                    Center,
                    true,
                    vec![
                        fixture("worktable", 0, 0, F),
                        fixture("operator_chair", 0, -1, F),
                    ],
                ),
            ],
        ),
        ("ai", _) => control_room_program(department, role, program_variant),
        ("security", "armory" | "locker-room") => program(
            department,
            role,
            program_variant,
            30,
            48,
            vec![
                zone(
                    "secure-storage",
                    Perimeter,
                    true,
                    vec![
                        fixture("weapon_rack", -2, 0, F),
                        fixture("secure_locker", -1, 0, F),
                        fixture("secure_locker", 0, 0, F),
                        fixture("secure_locker", 1, 0, F),
                        fixture("weapon_rack", 2, 0, F),
                    ],
                ),
                zone(
                    "issue-desk",
                    Entrance,
                    true,
                    vec![
                        fixture("armory_autolathe", -1, 0, M),
                        fixture("reinforced_table", 0, 0, F),
                        fixture("security_console", 1, 0, M),
                    ],
                ),
            ],
        ),
        ("security", "evidence") => program(
            department,
            role,
            program_variant,
            26,
            42,
            vec![
                zone(
                    "evidence-bank",
                    Perimeter,
                    true,
                    vec![
                        fixture("evidence_cabinet", -1, 0, F),
                        fixture("secure_locker", 0, 0, F),
                        fixture("evidence_cabinet", 1, 0, F),
                        fixture("evidence_cabinet", 2, 0, F),
                    ],
                ),
                zone(
                    "records-station",
                    Entrance,
                    true,
                    vec![
                        fixture("security_records", 0, 0, M),
                        fixture("worktable", 1, 0, F),
                        fixture("work_chair", 1, -1, F),
                    ],
                ),
            ],
        ),
        ("security", "interrogation") => program(
            department,
            role,
            program_variant,
            22,
            34,
            vec![
                zone(
                    "interview",
                    Center,
                    true,
                    vec![
                        fixture("reinforced_table", 0, 0, F),
                        fixture("chair", 0, -1, F),
                        fixture("chair", 0, 1, F),
                    ],
                ),
                zone(
                    "control",
                    Entrance,
                    true,
                    vec![
                        fixture("security_console", 0, 0, M),
                        fixture("secure_locker", 1, 0, F),
                    ],
                ),
                zone(
                    "observation",
                    Perimeter,
                    true,
                    vec![
                        fixture("security_records", -1, 0, M),
                        fixture("worktable", 0, 0, F),
                        fixture("work_chair", 0, -1, F),
                        fixture("evidence_cabinet", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("security", "checkpoint") => program(
            department,
            role,
            program_variant,
            24,
            36,
            vec![
                zone(
                    "screening-desk",
                    Entrance,
                    true,
                    vec![
                        fixture("security_console", -1, 0, M),
                        fixture("reinforced_table", 0, 0, F),
                        fixture("operator_chair", 0, -1, F),
                    ],
                ),
                zone(
                    "screening-line",
                    Center,
                    false,
                    vec![
                        fixture("flash", -1, 0, M),
                        fixture("reinforced_table", 0, 0, F),
                        fixture("secure_locker", 1, 0, F),
                        fixture("equipment_recharger", 0, -1, M),
                    ],
                ),
                zone(
                    "checkpoint-waiting",
                    Perimeter,
                    false,
                    vec![
                        fixture("visitor_bench", -1, 0, F),
                        fixture("side_table", 0, 0, F),
                        fixture("visitor_bench", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("security", "brig") => program(
            department,
            role,
            program_variant,
            34,
            54,
            vec![
                zone(
                    "guard-post",
                    Entrance,
                    true,
                    vec![
                        fixture("security_console", -1, 0, M),
                        fixture("reinforced_table", 0, 0, F),
                        fixture("chair", 0, -1, F),
                        fixture("secure_locker", 1, 0, F),
                    ],
                ),
                zone(
                    "bunks",
                    Perimeter,
                    true,
                    vec![
                        fixture("medical_bed", -2, 0, F),
                        fixture("medical_bed", 0, 0, F),
                        fixture("medical_bed", 2, 0, F),
                    ],
                ),
            ],
        ),
        ("security", _) => control_room_program(department, role, program_variant),
        ("medical", "reception") => program(
            department,
            role,
            program_variant,
            28,
            44,
            vec![
                zone(
                    "medical-front-desk",
                    Entrance,
                    true,
                    vec![
                        fixture("reception_desk", -1, 0, F),
                        fixture("medical_console", 0, 0, M),
                        fixture("reception_desk", 1, 0, F),
                        fixture("work_chair", 0, -1, F),
                    ],
                ),
                zone(
                    "medical-waiting",
                    Perimeter,
                    true,
                    vec![
                        fixture("visitor_bench", -2, 0, F),
                        fixture("side_table", -1, 0, F),
                        fixture("visitor_bench", 0, 0, F),
                        fixture("water_cooler", 1, 0, F),
                        fixture("plant", 2, 0, F),
                    ],
                ),
            ],
        ),
        ("medical", "surgery") => program(
            department,
            role,
            program_variant,
            34,
            52,
            vec![
                zone(
                    "operating-theatre",
                    Center,
                    true,
                    vec![
                        fixture("operating_table", 0, 0, F),
                        fixture("medical_console", -2, 0, M),
                        fixture("anesthetic", 2, 0, M),
                        fixture("instrument_table", 0, 2, F),
                        fixture("iv_stand", 1, 1, F),
                    ],
                ),
                zone(
                    "scrub-and-storage",
                    Perimeter,
                    true,
                    vec![
                        fixture("sink", -1, 0, F),
                        fixture("medical_cabinet", 0, 0, F),
                        fixture("medical_cabinet", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("medical", "treatment" | "exam") => program(
            department,
            role,
            program_variant,
            26,
            42,
            vec![
                zone(
                    "patient-bay",
                    Center,
                    true,
                    vec![
                        fixture("medical_bed", 0, 0, F),
                        fixture("iv_stand", 1, 0, F),
                        fixture("instrument_table", -1, 0, F),
                        fixture("privacy_screen", 0, 2, F),
                    ],
                ),
                zone(
                    "exam-storage",
                    Perimeter,
                    true,
                    vec![
                        fixture("medical_console", -1, 0, M),
                        fixture("sink", 0, 0, F),
                        fixture("medical_cabinet", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("medical", "ward" | "recovery") => program(
            department,
            role,
            program_variant,
            38,
            62,
            vec![
                zone(
                    "bed-row",
                    Perimeter,
                    true,
                    vec![
                        fixture("medical_bed", -3, 0, F),
                        fixture("iv_stand", -2, 0, F),
                        fixture("medical_bed", -1, 0, F),
                        fixture("medical_bed", 1, 0, F),
                        fixture("iv_stand", 2, 0, F),
                        fixture("medical_bed", 3, 0, F),
                    ],
                ),
                zone(
                    "nursing-station",
                    Center,
                    true,
                    vec![
                        fixture("medical_console", -1, 0, M),
                        fixture("worktable", 0, 0, F),
                        fixture("work_chair", 0, -1, F),
                        fixture("medical_cabinet", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("medical", "pharmacy") => program(
            department,
            role,
            program_variant,
            28,
            44,
            vec![
                zone(
                    "pharmacy-bench",
                    Perimeter,
                    true,
                    vec![
                        fixture("chem_master", -2, 0, M),
                        fixture("reagent_grinder", -1, 0, M),
                        fixture("sink", 0, 0, F),
                        fixture("medical_cabinet", 1, 0, F),
                        fixture("medical_vendor", 2, 0, M),
                    ],
                ),
                zone(
                    "dispensing",
                    Entrance,
                    true,
                    vec![
                        fixture("reception_desk", 0, 0, F),
                        fixture("stool", 0, -1, F),
                    ],
                ),
            ],
        ),
        ("medical", _) => medical_support_program(department, role, program_variant),
        ("engineering", "power") => program(
            department,
            role,
            program_variant,
            34,
            56,
            vec![
                zone(
                    "power-control",
                    Perimeter,
                    true,
                    vec![
                        fixture("generator_control", -2, 0, M),
                        fixture("engineering_console", -1, 0, M),
                        fixture("power_monitor", 0, 0, M),
                        fixture("electrical_locker", 1, 0, F),
                        fixture("electrical_locker", 2, 0, F),
                    ],
                ),
                zone(
                    "repair-bench",
                    Center,
                    true,
                    vec![
                        fixture("workbench", 0, 0, F),
                        fixture("parts_bin", 1, 0, F),
                        fixture("stool", 0, -1, F),
                    ],
                ),
            ],
        ),
        ("engineering", "atmospherics") => program(
            department,
            role,
            program_variant,
            34,
            56,
            vec![
                zone(
                    "atmos-control",
                    Perimeter,
                    true,
                    vec![
                        fixture("atmos_control", -2, 0, M),
                        fixture("air_sensor", -1, 0, M),
                        fixture("air_canister", 0, 0, F),
                        fixture("oxygen_canister", 1, 0, F),
                        fixture("electrical_locker", 2, 0, F),
                    ],
                ),
                zone(
                    "service-bench",
                    Center,
                    true,
                    vec![
                        fixture("workbench", 0, 0, F),
                        fixture("tool_rack", 1, 0, F),
                        fixture("stool", 0, -1, F),
                    ],
                ),
            ],
        ),
        ("engineering", "foyer") => program(
            department,
            role,
            program_variant,
            24,
            38,
            vec![
                zone(
                    "engineering-entry",
                    Entrance,
                    true,
                    vec![
                        fixture("reception_desk", -1, 0, F),
                        fixture("engineering_console", 0, 0, M),
                        fixture("operator_chair", -1, -1, F),
                        fixture("equipment_recharger", 1, 0, M),
                    ],
                ),
                zone(
                    "safety-issue",
                    Perimeter,
                    true,
                    vec![
                        fixture("department_locker", -1, 0, F),
                        fixture("electrical_locker", 0, 0, F),
                        fixture("notice_board", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("engineering", "storage") => program(
            department,
            role,
            program_variant,
            24,
            40,
            vec![
                zone(
                    "engineering-stores",
                    Perimeter,
                    true,
                    vec![
                        fixture("electrical_locker", -2, 0, F),
                        fixture("parts_cabinet", -1, 0, F),
                        fixture("parts_bin", 0, 0, F),
                        fixture("tool_rack", 1, 0, F),
                        fixture("supply_crate", 2, 0, F),
                    ],
                ),
                zone(
                    "stores-counter",
                    Entrance,
                    true,
                    vec![
                        fixture("worktable", 0, 0, F),
                        fixture("package_scanner", 1, 0, M),
                    ],
                ),
            ],
        ),
        ("engineering", "maintenance" | "tool-room") => program(
            department,
            role,
            program_variant,
            26,
            42,
            vec![
                zone(
                    "tool-wall",
                    Perimeter,
                    true,
                    vec![
                        fixture("tool_rack", -2, 0, F),
                        fixture("electrical_locker", -1, 0, F),
                        fixture("parts_cabinet", 0, 0, F),
                        fixture("tool_cart", 1, 0, F),
                    ],
                ),
                zone(
                    "repair-bay",
                    Center,
                    true,
                    vec![
                        fixture("workbench", -1, 0, F),
                        fixture("workbench", 0, 0, F),
                        fixture("stool", -1, -1, F),
                        fixture("parts_bin", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("engineering", "equipment") => program(
            department,
            role,
            program_variant,
            24,
            38,
            vec![
                zone(
                    "equipment-issue",
                    Perimeter,
                    true,
                    vec![
                        fixture("engineering_vendor", -1, 0, M),
                        fixture("equipment_recharger", 0, 0, M),
                        fixture("department_locker", 1, 0, F),
                        fixture("air_canister", 2, 0, F),
                    ],
                ),
                zone(
                    "issue-desk",
                    Entrance,
                    true,
                    vec![fixture("worktable", 0, 0, F), fixture("stool", 0, -1, F)],
                ),
            ],
        ),
        ("engineering", "workshop") => workshop_program(department, role, program_variant, false),
        ("engineering", _) => workshop_program(department, role, program_variant, false),
        ("logistics", "cargo" | "warehouse" | "inventory" | "storage") => program(
            department,
            role,
            program_variant,
            38,
            64,
            vec![
                zone(
                    "storage-row",
                    Center,
                    true,
                    vec![
                        fixture("crate_rack", -1, -1, F),
                        fixture("supply_crate", 0, -1, F),
                        fixture("crate_rack", 1, -1, F),
                        fixture("pallet", -1, 1, F),
                        fixture("supply_crate", 0, 1, F),
                        fixture("crate_rack", 1, 1, F),
                    ],
                ),
                zone(
                    "loading",
                    Entrance,
                    true,
                    vec![
                        fixture("loading_table", -1, 0, F),
                        fixture("package_scanner", 0, 0, M),
                        fixture("freight_cart", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("logistics", "sorting" | "processing") => program(
            department,
            role,
            program_variant,
            34,
            56,
            vec![
                zone(
                    "sorting-line",
                    Center,
                    true,
                    vec![
                        fixture("loading_table", -2, 0, F),
                        fixture("packing_table", -1, 0, F),
                        fixture("package_scanner", 0, 0, M),
                        fixture("packing_table", 1, 0, F),
                        fixture("disposal_unit", 2, 0, M),
                    ],
                ),
                zone(
                    "dispatch",
                    Entrance,
                    true,
                    vec![
                        fixture("cargo_console", -1, 0, M),
                        fixture("supply_console", 0, 0, M),
                        fixture("manifest_board", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("logistics", _) => logistics_office_program(department, role, program_variant),
        ("docking", "reception") => program(
            department,
            role,
            program_variant,
            28,
            44,
            vec![
                zone(
                    "arrival-desk",
                    Entrance,
                    true,
                    vec![
                        fixture("reception_desk", -1, 0, F),
                        fixture("visitor_console", 0, 0, M),
                        fixture("reception_desk", 1, 0, F),
                        fixture("operator_chair", 0, -1, F),
                    ],
                ),
                zone(
                    "arrival-waiting",
                    Perimeter,
                    true,
                    vec![
                        fixture("visitor_bench", -2, 0, F),
                        fixture("side_table", -1, 0, F),
                        fixture("visitor_bench", 0, 0, F),
                        fixture("display_case", 1, 0, F),
                        fixture("plant", 2, 0, F),
                    ],
                ),
            ],
        ),
        ("docking", "equipment" | "supply") => program(
            department,
            role,
            program_variant,
            24,
            40,
            vec![
                zone(
                    "flight-equipment",
                    Perimeter,
                    true,
                    vec![
                        fixture("oxygen_canister", -2, 0, F),
                        fixture("department_locker", -1, 0, F),
                        fixture("equipment_recharger", 0, 0, M),
                        fixture("supply_crate", 1, 0, F),
                    ],
                ),
                zone(
                    "equipment-counter",
                    Entrance,
                    true,
                    vec![
                        fixture("worktable", 0, 0, F),
                        fixture("package_scanner", 1, 0, M),
                    ],
                ),
            ],
        ),
        ("docking", "lounge" | "berth") => program(
            department,
            role,
            program_variant,
            34,
            54,
            vec![
                zone(
                    "seating",
                    Center,
                    true,
                    vec![
                        fixture("side_table", -1, 0, F),
                        fixture("side_table", 1, 0, F),
                        fixture("visitor_bench", -2, 0, F),
                        fixture("visitor_bench", 0, 0, F),
                        fixture("visitor_bench", 2, 0, F),
                    ],
                ),
                zone(
                    "information",
                    Entrance,
                    true,
                    vec![
                        fixture("visitor_console", -1, 0, M),
                        fixture("communications_console", 0, 0, M),
                        fixture("water_cooler", 1, 0, F),
                    ],
                ),
            ],
        ),
        ("docking", "customs" | "security") => {
            control_room_program(department, role, program_variant)
        }
        ("docking", _) => logistics_office_program(department, role, program_variant),
        _ => coherent_fallback_program(department, role, program_variant),
    }
}

pub fn compact_room_program(department: &str, role: &str, variant: u64) -> RoomProgram {
    let (primary, support, surface, seat, storage) = match (department, role) {
        ("security", "armory" | "locker-room") => (
            "weapon_rack",
            "secure_locker",
            "reinforced_table",
            "stool",
            "department_locker",
        ),
        ("security", "evidence") => (
            "evidence_cabinet",
            "security_records",
            "worktable",
            "work_chair",
            "secure_locker",
        ),
        ("security", "brig") => (
            "security_console",
            "secure_locker",
            "reinforced_table",
            "chair",
            "security_records",
        ),
        ("security", "interrogation") => (
            "security_records",
            "flash",
            "reinforced_table",
            "chair",
            "evidence_cabinet",
        ),
        ("security", "checkpoint") => (
            "security_records",
            "department_locker",
            "reinforced_table",
            "operator_chair",
            "equipment_recharger",
        ),
        ("security", "reception") => (
            "visitor_console",
            "security_records",
            "reception_desk",
            "work_chair",
            "filing_cabinet",
        ),
        ("security", _) => (
            "security_console",
            "security_records",
            "worktable",
            "operator_chair",
            "department_locker",
        ),
        ("medical", "surgery") => (
            "operating_table",
            "instrument_table",
            "medical_bed",
            "stool",
            "medical_cabinet",
        ),
        ("medical", "pharmacy") => (
            "chem_master",
            "medical_cabinet",
            "worktable",
            "stool",
            "medicine_cart",
        ),
        ("medical", "exam") => (
            "sink",
            "medical_vendor",
            "medical_bed",
            "stool",
            "medical_cabinet",
        ),
        ("medical", "ward" | "recovery") => (
            "medical_bed",
            "iv_stand",
            "side_table",
            "stool",
            "privacy_screen",
        ),
        ("medical", "storage") => (
            "medical_locker",
            "medicine_cart",
            "worktable",
            "stool",
            "medical_cabinet",
        ),
        ("medical", "reception") => (
            "medical_console",
            "medical_vendor",
            "reception_desk",
            "work_chair",
            "filing_cabinet",
        ),
        ("medical", _) => (
            "medical_console",
            "medical_cabinet",
            "medical_bed",
            "stool",
            "iv_stand",
        ),
        ("engineering", "power") => (
            "power_monitor",
            "electrical_locker",
            "workbench",
            "stool",
            "parts_bin",
        ),
        ("engineering", "atmospherics") => (
            "atmos_control",
            "air_canister",
            "workbench",
            "stool",
            "tool_rack",
        ),
        ("engineering", "maintenance") => {
            ("air_sensor", "tool_rack", "workbench", "stool", "tool_cart")
        }
        ("engineering", "storage") => (
            "electrical_locker",
            "parts_bin",
            "workbench",
            "stool",
            "tool_rack",
        ),
        ("engineering", "equipment" | "tool-room") => (
            "engineering_vendor",
            "equipment_recharger",
            "workbench",
            "stool",
            "tool_rack",
        ),
        ("engineering", "workshop") => (
            "autolathe",
            "electrical_locker",
            "workbench",
            "stool",
            "tool_cart",
        ),
        ("engineering", _) => (
            "control_console",
            "engineering_vendor",
            "workbench",
            "stool",
            "electrical_locker",
        ),
        ("logistics", "warehouse" | "storage") => (
            "crate_rack",
            "supply_crate",
            "loading_table",
            "stool",
            "freight_cart",
        ),
        ("logistics", "inventory") => (
            "package_scanner",
            "manifest_board",
            "loading_table",
            "work_chair",
            "crate_rack",
        ),
        ("logistics", "sorting" | "processing") => (
            "disposal_unit",
            "package_scanner",
            "packing_table",
            "work_chair",
            "cargo_bin",
        ),
        ("logistics", "reception" | "dispatch") => (
            "supply_console",
            "communications_console",
            "reception_desk",
            "work_chair",
            "manifest_board",
        ),
        ("logistics", _) => (
            "cargo_console",
            "supply_crate",
            "loading_table",
            "stool",
            "freight_cart",
        ),
        ("docking", "berth" | "lounge") => (
            "visitor_bench",
            "water_cooler",
            "side_table",
            "plant",
            "department_locker",
        ),
        ("docking", "equipment" | "supply") => (
            "oxygen_canister",
            "supply_crate",
            "worktable",
            "stool",
            "equipment_recharger",
        ),
        ("docking", "control") => (
            "communications_console",
            "control_console",
            "worktable",
            "operator_chair",
            "security_console",
        ),
        ("docking", "customs" | "security") => (
            "id_console",
            "security_records",
            "reinforced_table",
            "operator_chair",
            "secure_locker",
        ),
        ("docking", _) => (
            "visitor_console",
            "department_locker",
            "reception_desk",
            "work_chair",
            "filing_cabinet",
        ),
        ("ai", "core") => (
            "ai_core",
            "server_rack",
            "data_terminal",
            "coolant_unit",
            "equipment_recharger",
        ),
        ("ai", "robotics") => (
            "robotics_console",
            "autolathe",
            "workbench",
            "stool",
            "parts_bin",
        ),
        ("ai", "monitoring" | "satellite") => (
            "ai_upload",
            "crew_monitor",
            "worktable",
            "operator_chair",
            "server_rack",
        ),
        ("ai", "server-closet") => (
            "robotics_console",
            "autolathe",
            "workbench",
            "stool",
            "server_rack",
        ),
        ("ai", "secure-storage") => (
            "server_rack",
            "coolant_unit",
            "workbench",
            "stool",
            "equipment_recharger",
        ),
        ("ai", _) => (
            "ai_upload",
            "data_terminal",
            "worktable",
            "operator_chair",
            "server",
        ),
        ("command", "meeting" | "briefing") => (
            "conference_table",
            "executive_chair",
            "side_table",
            "visitor_bench",
            "filing_cabinet",
        ),
        ("command", "communications" | "operations") => (
            "communications_console",
            "crew_monitor",
            "worktable",
            "operator_chair",
            "filing_cabinet",
        ),
        ("command", "records" | "archive") => (
            "id_console",
            "filing_cabinet",
            "worktable",
            "work_chair",
            "shelf",
        ),
        ("command", _) => (
            "command_console",
            "filing_cabinet",
            "reception_desk",
            "executive_chair",
            "plant",
        ),
        _ => (
            "role_console",
            "department_locker",
            "worktable",
            "work_chair",
            "filing_cabinet",
        ),
    };
    program(
        department,
        role,
        variant,
        // Two pieces of functional equipment still need a door approach and
        // a connected operating aisle. A single 2x2 logical module has four
        // floor tiles and cannot satisfy that contract without blocking itself.
        20,
        24,
        vec![
            zone(
                "compact-workstation",
                ProgramAnchor::Perimeter,
                true,
                vec![
                    fixture(primary, 0, 0, M),
                    fixture(support, 0, -1, F),
                    fixture(surface, 1, 0, F),
                    fixture(seat, 1, -1, F),
                ],
            ),
            zone(
                "compact-storage",
                ProgramAnchor::Perimeter,
                false,
                vec![fixture(storage, 0, 0, F)],
            ),
        ],
    )
}

fn control_room_program(department: &str, role: &str, variant: u64) -> RoomProgram {
    program(
        department,
        role,
        variant,
        26,
        42,
        vec![
            zone(
                "control-bank",
                ProgramAnchor::Perimeter,
                true,
                vec![
                    fixture("control_console", -2, 0, M),
                    fixture("data_terminal", -1, 0, M),
                    fixture("security_console", 0, 0, M),
                    fixture("communications_console", 1, 0, M),
                    fixture("department_locker", 2, 0, F),
                ],
            ),
            zone(
                "operator",
                ProgramAnchor::Center,
                true,
                vec![
                    fixture("worktable", 0, 0, F),
                    fixture("operator_chair", 0, -1, F),
                ],
            ),
        ],
    )
}

fn workshop_program(department: &str, role: &str, variant: u64, robotics: bool) -> RoomProgram {
    program(
        department,
        role,
        variant,
        32,
        52,
        vec![
            zone(
                "machine-bank",
                ProgramAnchor::Perimeter,
                true,
                if robotics {
                    vec![
                        fixture("robotics_console", -2, 0, M),
                        fixture("autolathe", -1, 0, M),
                        fixture("equipment_recharger", 0, 0, M),
                        fixture("parts_bin", 1, 0, F),
                        fixture("tool_rack", 2, 0, F),
                    ]
                } else {
                    vec![
                        fixture("autolathe", -2, 0, M),
                        fixture("electrical_locker", -1, 0, F),
                        fixture("parts_bin", 0, 0, F),
                        fixture("tool_rack", 1, 0, F),
                        fixture("engineering_vendor", 2, 0, M),
                    ]
                },
            ),
            zone(
                "workbench",
                ProgramAnchor::Center,
                true,
                vec![
                    fixture("workbench", -1, 0, F),
                    fixture("workbench", 0, 0, F),
                    fixture("stool", -1, -1, F),
                    fixture("stool", 0, -1, F),
                    fixture("tool_cart", 1, 0, F),
                ],
            ),
        ],
    )
}

fn medical_support_program(department: &str, role: &str, variant: u64) -> RoomProgram {
    program(
        department,
        role,
        variant,
        24,
        38,
        vec![
            zone(
                "medical-storage",
                ProgramAnchor::Perimeter,
                true,
                vec![
                    fixture("medical_cabinet", -2, 0, F),
                    fixture("medical_locker", -1, 0, F),
                    fixture("medicine_cart", 0, 0, F),
                    fixture("medical_cabinet", 1, 0, F),
                    fixture("medical_vendor", 2, 0, M),
                ],
            ),
            zone(
                "support-desk",
                ProgramAnchor::Entrance,
                true,
                vec![
                    fixture("medical_console", 0, 0, M),
                    fixture("stool", 0, -1, F),
                ],
            ),
        ],
    )
}

fn logistics_office_program(department: &str, role: &str, variant: u64) -> RoomProgram {
    program(
        department,
        role,
        variant,
        26,
        42,
        vec![
            zone(
                "dispatch-bank",
                ProgramAnchor::Center,
                true,
                vec![
                    fixture("cargo_console", -1, 0, M),
                    fixture("supply_console", 0, 0, M),
                    fixture("communications_console", 1, 0, M),
                ],
            ),
            zone(
                "dispatch-records",
                ProgramAnchor::Perimeter,
                false,
                vec![
                    fixture("manifest_board", 0, 0, F),
                    fixture("department_locker", 1, 0, F),
                ],
            ),
            zone(
                "work-desk",
                ProgramAnchor::Center,
                true,
                vec![
                    fixture("worktable", 0, 0, F),
                    fixture("work_chair", 0, -1, F),
                ],
            ),
        ],
    )
}

fn coherent_fallback_program(department: &str, role: &str, variant: u64) -> RoomProgram {
    program(
        department,
        role,
        variant,
        18,
        30,
        vec![zone(
            "workstation",
            ProgramAnchor::Perimeter,
            true,
            vec![
                fixture("worktable", 0, 0, F),
                fixture("role_console", 1, 0, M),
                fixture("work_chair", 0, -1, F),
                fixture("department_locker", -1, 0, F),
            ],
        )],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    const REPRESENTATIVE_ROOMS: &[(&str, &str)] = &[
        ("command", "reception"),
        ("command", "meeting"),
        ("command", "archive"),
        ("ai", "core"),
        ("security", "operations"),
        ("security", "armory"),
        ("security", "brig"),
        ("medical", "surgery"),
        ("medical", "treatment"),
        ("medical", "ward"),
        ("medical", "pharmacy"),
        ("engineering", "power"),
        ("engineering", "atmospherics"),
        ("engineering", "workshop"),
        ("logistics", "inventory"),
        ("logistics", "sorting"),
        ("docking", "reception"),
        ("docking", "berth"),
    ];
    const COMPLETE_CATALOG: &[(&str, &[&str])] = &[
        (
            "command",
            &[
                "reception",
                "operations",
                "communications",
                "meeting",
                "briefing",
                "records",
                "liaison",
                "archive",
            ],
        ),
        (
            "ai",
            &[
                "foyer",
                "core",
                "satellite",
                "support",
                "robotics",
                "monitoring",
                "secure-storage",
                "server-closet",
            ],
        ),
        (
            "security",
            &[
                "reception",
                "operations",
                "brig",
                "armory",
                "interrogation",
                "evidence",
                "locker-room",
                "checkpoint",
            ],
        ),
        (
            "medical",
            &[
                "reception",
                "treatment",
                "surgery",
                "ward",
                "pharmacy",
                "recovery",
                "storage",
                "exam",
            ],
        ),
        (
            "engineering",
            &[
                "foyer",
                "power",
                "atmospherics",
                "workshop",
                "equipment",
                "maintenance",
                "storage",
                "tool-room",
            ],
        ),
        (
            "logistics",
            &[
                "reception",
                "cargo",
                "processing",
                "warehouse",
                "dispatch",
                "sorting",
                "storage",
                "inventory",
            ],
        ),
        (
            "docking",
            &[
                "reception",
                "control",
                "berth",
                "security",
                "customs",
                "lounge",
                "equipment",
                "supply",
            ],
        ),
    ];

    fn assert_program_contract(program: &RoomProgram) {
        assert!(program.minimum_area > 0);
        assert!(program.minimum_area <= program.ideal_area);
        assert!(program.ideal_area <= program.maximum_area);
        assert!(!program.zones.is_empty());
        assert!(program.zones.iter().any(|zone| zone.required));
        for zone in &program.zones {
            assert!(
                !zone.fixtures.is_empty(),
                "{} has an empty zone",
                program.id
            );
            let coordinates = zone
                .fixtures
                .iter()
                .map(|fixture| (fixture.dx, fixture.dy))
                .collect::<BTreeSet<_>>();
            assert_eq!(
                coordinates.len(),
                zone.fixtures.len(),
                "{} stacks authored fixtures in {}",
                program.id,
                zone.id
            );
        }
    }

    #[test]
    fn representative_rooms_have_authored_workflows() {
        for (department, role) in REPRESENTATIVE_ROOMS {
            let program = room_program(department, role, 0);
            assert_program_contract(&program);
            assert!(
                program.zones.len() >= 2,
                "{department}/{role} fell back to a token room"
            );
        }
    }

    #[test]
    fn compact_rooms_are_role_specific_and_furnishable() {
        for (department, role) in REPRESENTATIVE_ROOMS {
            let program = compact_room_program(department, role, 0);
            assert_program_contract(&program);
            let fixture_ids = program
                .zones
                .iter()
                .flat_map(|zone| zone.fixtures.iter().map(|fixture| fixture.id))
                .collect::<BTreeSet<_>>();
            assert!(fixture_ids.len() >= 4);
            assert!(
                !fixture_ids.contains("role_console"),
                "{department}/{role} used the generic compact fallback"
            );
        }
    }

    #[test]
    fn live_catalog_never_uses_the_generic_program() {
        for (department, roles) in COMPLETE_CATALOG {
            for role in *roles {
                let program = room_program(department, role, 0);
                assert!(
                    !program.zones.iter().any(|zone| zone.id == "workstation"),
                    "{department}/{role} used the generic program"
                );
            }
        }
    }

    #[test]
    fn departmental_support_variants_are_materially_distinct() {
        for (department, _) in COMPLETE_CATALOG {
            let signatures = (0..3)
                .map(|variant| {
                    support_zone(department, "support", variant)
                        .fixtures
                        .into_iter()
                        .map(|fixture| fixture.id)
                        .collect::<BTreeSet<_>>()
                })
                .collect::<BTreeSet<_>>();
            assert_eq!(signatures.len(), 3, "{department} repeats support variants");
        }
    }
}
