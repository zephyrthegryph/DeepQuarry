//! `check_grep.sh` section "code issues", second half: the count ratchets (their ceilings are in
//! `tools/ci/lint_scopes.toml`), the damage and body vocabulary, the `grep -R` checks, indentation.

use super::framework::*;

/// The `d3_pool` calls of the script: pattern and the paths it searches.
static D3: &[(&str, &[&str])] = &[
    (r"^[[:space:]]*var/(damage|damage_overlay)\b", &["code/game/turfs/simulated/walls.dm"]),
    (r"^/turf/simulated/wall[^[:space:]]*/(take_damage|update_damage)\(", &["code/game/turfs"]),
    (r"^[[:space:]]+var/integrity\b|\bintegrity[[:space:]]*([-+*/]?=[^=]|\+\+|--)", &["code/modules/blob2"]),
    (r"\bblob_(max_)?health\b", &["code/modules/blob"]),
    (
        r"^[[:space:]]+var/(damage|max_damage|broken_damage|damage_failure)\b|\b(max_damage|broken_damage|damage_failure)\b",
        &["code/modules/modular_computers"],
    ),
    (r"\b(maxintegrity|integrity[[:space:]]*([-+*/]?=[^=]|\+\+|--))|^[[:space:]]+var/integrity\b", &["code/game/objects/items/weapons/tanks"]),
    (r"\bshield_health\b", &["code"]),
    (r"^[[:space:]]+var/hp\b|\bhp[[:space:]]*[-+]?=[^=]", &["code/game/objects/items/shooting_range.dm"]),
    (
        r"^[[:space:]]+var/(strength|max_strength)\b|\.(strength|max_strength)\b",
        &["code/modules/shieldgen/energy_field.dm", "code/modules/shieldgen/shield_gen.dm", "code/modules/xenoarcheaology/effects/forcefield.dm"],
    ),
    (
        r"\bhealth\b",
        &["code/game/objects/items/weapons/material", "code/game/objects/items/weapons/traps.dm", "code/modules/vore/smoleworld"],
    ),
    (r"\.integrity[[:space:]]*([-+*/]?=[^=]|\+\+|--)", &["code/game/mecha"]),
];

const D3_RULES: [&str; 11] = [
    "separate_object_health_pools",
    "separate_object_health_pools__2",
    "separate_object_health_pools__3",
    "separate_object_health_pools__4",
    "separate_object_health_pools__5",
    "separate_object_health_pools__6",
    "separate_object_health_pools__7",
    "separate_object_health_pools__8",
    "separate_object_health_pools__9",
    "separate_object_health_pools__10",
    "separate_object_health_pools__11",
];

const ADMIN: &str = "admin_rights_shrink_only_baseline_one_mechanism_admin_can";

pub fn parts() -> Vec<Part> {
    let mut v = vec![
        // admin_hits: `rg -n` (not allow_grep), then the explicit filters; judged by ceilings.
        Part::new(
            ADMIN,
            "admin rights: shrink-only baseline (one mechanism: admin_can)",
            "check_rights( calls over the ratchet. Use admin_can(client, rights) or declare the rights on the entry point.",
            Files::Code,
            line(r"check_rights\("),
        )
        .flt(vec![Flt::DropLit("code/modules/admin/holder"), Flt::DropLit("proc/check_rights"), drop(r"ALLOW\([^)]*check_grep")]),
        Part::new(
            "admin_rights_shrink_only_baseline_one_mechanism_admin_can__holder",
            "admin rights: shrink-only baseline (one mechanism: admin_can)",
            "raw .holder reads outside modules/admin/holder* over the ratchet. Use admin_can(client, rights).",
            Files::Code,
            line(r"\.holder\b"),
        )
        .flt(vec![
            Flt::DropLit("code/modules/admin/holder"),
            Flt::DropPaths("admin_holder_allow"),
            Flt::DropLit("proc/check_rights"),
            drop(r"ALLOW\([^)]*check_grep"),
            drop(r"nameof\([^)]*\.holder|\.holder\("),
            // receivers that are never a /client: brain/module/io/pin/wire/reagent holders and op/act/ledger contexts
            Flt::DropLit("code/game/objects/effects/effect_system.dm"),
            Flt::DropLit("code/datums/containment/ledger.dm"),
            Flt::DropLit("C.holder.trans_to_holder"),
            Flt::DropLit("// holder.holder is"),
            drop(r"\b(?:brain|ai_brain|module|io|selected_io|linked_pin|wires|reagent|ask|act|op|ctx|reagents|ledger|A|O|D|S|R|W|P|P1|P2|L|holder)\??\.holder\b"),
        ]),
        Part::new(
            "admin_rights_shrink_only_baseline_one_mechanism_admin_can__rights_and",
            "admin rights: shrink-only baseline (one mechanism: admin_can)",
            "'rights & R_' tests outside modules/admin/holder* over the ratchet. Use admin_can(client, rights).",
            Files::Code,
            line(r"rights & R_"),
        )
        .flt(vec![Flt::DropLit("code/modules/admin/holder"), Flt::DropLit("proc/check_rights"), drop(r"ALLOW\([^)]*check_grep")]),
        // `rg -c`: matching lines, no filters, no allow
        Part::new(
            "heat_ratchet_on_fire_act_overrides_h3",
            "heat: ratchet on fire_act() overrides (H3)",
            "fire_act() overrides over the ratchet. Declare a heat rule (code/datums/rules/declarations.dm) or a temperature threshold instead.",
            Files::Code,
            line(r"^/[A-Za-z0-9_/]*/fire_act\("),
        ),
        // Hard ban (temperature and energy writes outside code/domains): DM outside the gas and heat domains never writes a gas's or a solid's temperature or energy.
        Part::new(
            "heat_raw_temperature_writes",
            "heat: raw temperature writes",
            "set_temperature()/add_thermal_energy() outside code/domains/. Declare a heat_link()/heat_pump()/heat_engine() entry, or move heat with heat_move()/heat_add()/heat_set() (code/domains/heat/heat_net.dm).",
            Files::Code,
            line(r"\b(set_temperature|add_thermal_energy)\("),
        )
        .flt(vec![Flt::DropPaths("heat_writes_allow"), drop(r"^[^:]+:\d+:\s*//")])
        .allow(Allow::Strict),
        Part::new(
            "damage_ratchet_on_non_turf_ex_act_overrides_d5",
            "damage: ratchet on non-turf ex_act() overrides (D5)",
            "non-turf ex_act() overrides over the ratchet. Let the blast packet land (max_integrity, armour, BOMB_PROOF); keep only orthogonal effects and chain to ..().",
            Files::Code,
            line(r"^/(atom|obj|mob|area)[A-Za-z0-9_/]*/ex_act\("),
        ),
        Part::new(
            "damage_ratchet_on_atom_break_set_broken_overrides_d4",
            "damage: ratchet on atom_break()/set_broken() overrides (D4)",
            "atom_break()/set_broken() overrides over the ratchet. Declare integrity_failure / broken_icon_state instead.",
            Files::Code,
            line(r"^/[A-Za-z0-9_/]*/(atom_break|set_broken)\("),
        ),
        Part::new(
            "generic_hit_ratchet_on_attack_generic_overrides",
            "generic hit: ratchet on attack_generic() overrides",
            "attack_generic() overrides over the ratchet. Take the generic hit over: extend(/datum/act/hit/generic, instead(then(PROC_REF(x)))) in the type's CAPABILITIES; HOOK_DECLINE lets the default attack land.",
            Files::Code,
            line(r"^/[A-Za-z0-9_/]*/attack_generic\("),
        ),
        // Items, structures, effects and turfs (code/game/objects, code/game/turfs): the legacy forms of the items/structures
        // wave, shrink-only until each reaches zero and becomes a hard ban (tools/codemods/run_items_wave.sh, exclusions.txt).
        Part::new(
            "objects_ratchet_on_legacy_interactions",
            "objects: ratchet on legacy interactions",
            "DECLARE_INTERACTIONS/EXTEND_INTERACTIONS/declare_interactions() in code/game/objects or code/game/turfs over the ratchet. Declare ops in the type's CAPABILITIES (python tools/dx/codemods/interact_declare.py).",
            Files::Code,
            line(r"^(DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\(|^/[A-Za-z0-9_/]*/declare_interactions\("),
        )
        .flt(vec![Flt::Keep(r"^code/game/(objects|turfs)/".into())]),
        Part::new(
            "objects_ratchet_on_tool_act_overrides",
            "objects: ratchet on tool *_act() overrides",
            "screwdriver/crowbar/wrench/wirecutter/multitool/welder _act() overrides in code/game/objects or code/game/turfs over the ratchet. Declare op(\"use_x\", tool(TOOL_X), ...) (python tools/codemods/tool_act.py).",
            Files::Code,
            line(r"^/[A-Za-z0-9_/]*/(screwdriver|crowbar|wrench|wirecutter|multitool|welder)_act\("),
        )
        .flt(vec![Flt::Keep(r"^code/game/(objects|turfs)/".into())]),
        Part::new(
            "objects_ratchet_on_damage_reactions",
            "objects: ratchet on DAMAGE_REACTION",
            "DAMAGE_REACTION in code/game/objects or code/game/turfs over the ratchet. extend(/datum/act/hit/x, instead(...)) or on_notice(/datum/notice/hit/x, ...) (python tools/codemods/damage_reaction.py).",
            Files::Code,
            line(r"^DAMAGE_REACTION(_AFTER)?\("),
        )
        .flt(vec![Flt::Keep(r"^code/game/(objects|turfs)/".into())]),
        Part::new(
            "objects_ratchet_on_declare_emag",
            "objects: ratchet on DECLARE_EMAG",
            "DECLARE_EMAG in code/game/objects or code/game/turfs over the ratchet. emag(then(PROC_REF(x)), repeatable =) in the type's CAPABILITIES (code/library/access/emag.dm).",
            Files::Code,
            line(r"^DECLARE_EMAG(_REPEATABLE)?\("),
        )
        .flt(vec![Flt::Keep(r"^code/game/(objects|turfs)/".into())]),
        Part::new(
            "objects_ratchet_on_periodic",
            "objects: ratchet on DECLARE_PERIODIC and machine_step",
            "DECLARE_PERIODIC*/machine_step in code/game/objects or code/game/turfs over the ratchet. every(interval, then(PROC_REF(x)), when =) in the type's CAPABILITIES.",
            Files::Code,
            line(r"^DECLARE_PERIODIC(_WHILE|_WHILE_ALL)?\(|^/[A-Za-z0-9_/]*/machine_step\("),
        )
        .flt(vec![Flt::Keep(r"^code/game/(objects|turfs)/".into())]),
        // The legacy declaration forms of the sweeps (interactions, damage reactions, emag, periodics, repeats): a hard ban in the folders that reached
        // zero (`legacy_forms_converted` in tools/ci/lint_scopes.toml). A folder is added when its last site is converted, never taken off.
        Part::new(
            "legacy_declaration_forms_banned_in_converted_folders",
            "legacy declaration forms: banned in the converted folders",
            "DECLARE_INTERACTIONS/EXTEND_INTERACTIONS/declare_interactions(), DAMAGE_REACTION(_AFTER), DECLARE_EMAG(_REPEATABLE), DECLARE_PERIODIC* or DECLARE_REPEAT in a folder listed under legacy_forms_converted. Declare op(...) entries, extend(/datum/act/hit/x, ...) or on_notice(/datum/notice/hit/x, ...), emag(then(...)) and every(interval, then(...), when =) in the type's CAPABILITIES block.",
            Files::Code,
            line(r"^(DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\(|^/[A-Za-z0-9_/]+/declare_interactions\(|^DAMAGE_REACTION(_AFTER)?\(|^DECLARE_EMAG(_REPEATABLE)?\(|^DECLARE_PERIODIC(_WHILE|_WHILE_ALL)?\(|^DECLARE_REPEAT\("),
        )
        .flt(vec![Flt::KeepPaths("legacy_forms_converted")])
        .allow(Allow::None),
        Part::new(
            "legacy_field_forms_banned_in_converted_folders",
            "legacy field forms: banned in the field-converted folders",
            "Use TRACKED/TRACKED_BRIDGED or the actual capability state setter; these folders completed their field migration.",
            Files::Code,
            line(r"^(OM_FIELD(_[A-Z_]+)?|OM_DERIVE_FIELD|OM_FLAG_FIELD)\("),
        )
        .flt(vec![Flt::KeepPaths("legacy_fields_converted")])
        .allow(Allow::None),
        // The hand window pushes: a window updates because its ui_data(A) re-runs when something it reads changes (code/modules/tgui/ui_push.dm). A file
        // is listed under `ui_push_converted` when its last SStgui.update_uis() and hand changed() mark is gone; a hard ban there. Files are only ever added.
        Part::new(
            "hand_window_pushes_banned_in_converted_files",
            "hand window pushes: update_uis() and changed() banned in the converted files",
            "SStgui.update_uis() or a hand changed() mark in a file listed under ui_push_converted. Track what the window shows (TRACKED / a setter / a relation) and let ui_data(A) re-run: the framework pushes the window once per frame, and an op handler that returns TRUE updates the acting window.",
            Files::Code,
            line(r"\bupdate_uis\(|\bchanged\("),
        )
        .flt(vec![Flt::KeepPaths("ui_push_converted")]),
        // The timed-action forms (task_timed, task_start, task_busy and the om_task_periodic family): a hard ban in the folders and files that reached
        // zero (`timed_forms_converted` in tools/ci/lint_scopes.toml). A timed action a player does is an op with wait(); a periodic is every().
        Part::new(
            "timed_task_forms_banned_in_converted_folders",
            "timed-action forms: banned in the converted folders",
            "task_timed(), task_start(), task_busy() or om_task_periodic*() in a folder or file listed under timed_forms_converted. A timed action is an op with wait(t) (begins(MSG(x)) for the start message, claims() for exclusivity, stack(T, n) for a cost; doc/rewrite/conversion_guide.md section 12), a periodic is every(interval, then(PROC_REF(x)), when =).",
            Files::Code,
            line(r"^[^/]*\b(task_timed|task_start|task_busy|om_task_periodic|om_task_periodic_stop|om_task_periodic_running)\("),
        )
        .flt(vec![Flt::KeepPaths("timed_forms_converted")])
        .allow(Allow::None),
        Part::new(
            "bump_ratchet_on_bumped_overrides",
            "bump: ratchet on Bumped() overrides",
            "Bumped() overrides over the ratchet. Answer the bump action: on_notice(/datum/notice/bumped, then(PROC_REF(x))) or extend(/datum/act/bump, ...) in the type's CAPABILITIES.",
            Files::Code,
            line(r"^/[A-Za-z0-9_/]*/Bumped\("),
        ),
        Part::new(
            "weapon_vocabulary_injury_kinds_not_damage_types",
            "weapon vocabulary: injury kinds, not damage types",
            "a legacy damage type (damtype / injury_kind_for / check_armour / attack_sharp...) detected. Declare injury_kind = INJURY_X (or injury_kinds) and derive object damage with injury_kind_obj_damage_type().",
            Files::Code,
            line(r"(\.damtype\b|\bvar/damtype\b|^\s*damtype\s*=|\binjury_kind_for\b|\bget_injury_kind\b|\binjure_by_damtype\b|\bpunch_damtype\b|\bcheck_armour\b|\battack_(sharp|edge)\b)"),
        )
        .allow(Allow::Strict),
        Part::new(
            "weapon_vocabulary_injury_kinds_not_damage_types__2",
            "weapon vocabulary: injury kinds, not damage types",
            "damage_type = BRUTE/BURN on a mob-harming type. Declare injury_kind = INJURY_X; obj_integrity damage is derived from it.",
            Files::Code,
            line(r"^\s*(var/)?damage_type\s*=\s*(BRUTE|BURN)\b"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("weapon_damage_type_allow")]),
        Part::new(
            "weapon_vocabulary_injury_kinds_not_damage_types__3",
            "weapon vocabulary: injury kinds, not damage types",
            "a removed damage-type define (TOX/OXY/CLONE/HALLOSS/ELECTROCUTE/BIOACID/SEARING/ELECTROMAG) detected. Use INJURY_* kinds.",
            Files::Code,
            line(r"(#define\s+(TOX|OXY|CLONE|HALLOSS)\b|\b(HALLOSS|ELECTROCUTE|BIOACID|SEARING|ELECTROMAG)\b)"),
        )
        .allow(Allow::Strict),
        Part::new(
            "one_mitigation_pipeline",
            "one mitigation pipeline",
            "a parallel mitigation path detected. Harm goes through injure(); armour is injury_armor(kind, zone); species resistances are factor_baseline BF_INCOMING_*.",
            Files::Code,
            line(r"\b(run_armor_check|getarmor|getarmor_organ|mitigate_injury|factor_armor|get_injury_mod|injury_mod_groups)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "equip_slot_ids",
            "equip slot ids",
            "a numeric equip slot. Use SLOT_ID_* ids and get_equipped_item()/inventory_slot_id().",
            Files::Code,
            line(r#"(\bslot_(l_hand|r_hand|back|belt|wear_id|s_store|l_store|r_store|glasses|wear_mask|gloves|head|shoes|wear_suit|w_uniform|l_ear|r_ear|legs|tie|handcuffed|legcuffed|in_backpack)\b[^"]|\b(SLOT_TOTAL|get_inventory_slot|get_item_by_slot|dq_slot_num|dq_slot_id)\b)"#),
        )
        .allow(Allow::Strict),
        Part::new(
            "interned_armour",
            "interned armour",
            "an armour list detected. Declare armor_spec = \"key=value;...\" and read get_armor().value(key) (code/game/atom/armor.dm).",
            Files::Code,
            line(r"(^\s*(var/(list/)?)?armor\s*=\s*list\s*\(|\barmor\??\[|\.armor\b\s*(=|\[|\?)|\b(own_armor|roll_armor_variance)\b)"),
        )
        .allow(Allow::Strict),
        Part::new(
            "medical_condition_severity_writes",
            "medical condition severity writes",
            "direct medical-condition severity write detected. Use set_severity() or adjust_severity() so condition-dependent systems receive invalidation signals.",
            Files::Under(&["code/modules/medical", "code/modules/contracts"], &["dm"]),
            line(r"\.severity[[:space:]]*[-+*/]?=[^=]"),
        ),
        Part::new(
            "diagnosis_no_four_number_readouts",
            "diagnosis: no four-number readouts",
            "a four-number (brute/burn/tox/oxy) readout detected. Render a diagnosis instead: M.diagnose(/datum/diagnostic_profile/...) and its render_chat() / report_data().",
            Files::Under(&["code", "tgui/packages/tgui/interfaces"], &["dm", "ts", "tsx"]),
            line(r"\b(bruteLoss|oxyLoss|toxLoss|fireLoss|patient_brute|patient_burn|patient_tox|patient_oxy|physicalLoad|asphyxiaLoad|toxicLoad|thermalLoad|damagePanel|scannerFindings|dq_qualitative_damage_panel|dq_qualitative_scanner_findings|dq_crude_scan_readout|dq_externally_visible_symptom_lines)\b|Damage Specifics|Suffocation/Toxin/Burns/Brute"),
        ),
        Part::new(
            "diagnosis_automation_decides_from_treatment_demand",
            "diagnosis: automation decides from treatment demand",
            "automated treatment reading injury loads detected. Decide from M.treatment_demand(/datum/diagnostic_profile/...) (demand_urgency(), best_reagent_for_demand()) and heal with mend(TREAT_*).",
            Files::Under(
                &[
                    "code/modules/mob/living/bot",
                    "code/game/mecha",
                    "code/game/objects/items/weapons/medigun",
                    "code/game/machinery/cryo.dm",
                    "code/game/machinery/rechargestation.dm",
                    "code/game/objects/items/stacks/nanopaste.dm",
                    "code/game/objects/items/robobag.dm",
                    "code/modules/mob/living/simple_mob/subtypes/animal/sif/leech.dm",
                    "code/modules/admin/view_variables",
                ],
                &["dm"],
            ),
            line(r"\binjury_load\(|\b(heal_threshold|treatment_brute|treatment_fire|treatment_tox|treatment_oxy|brute_heal|burn_heal|tox_heal|oxy_heal|clone_heal|hal_heal|adjustDamage)\b"),
        ),
        Part::new(
            "organ_damage_outside_the_body",
            "organ damage outside the body",
            "organ or limb damage/healing outside the body detected. Use injure(kind, amount, organ) to harm and mend(tag, amount, organ) to heal.",
            Files::Under(&["code"], &["dm"]),
            line(r"\b(organ|internal_organ|external_organ|our_organ|affecting|affected|bodypart|brain|my_brain|heart|ht|liver|lungs|kidneys|eyes|stomach|st|limb|[a-z_]*_organ)\??\.(take_damage|heal_damage|damage[[:space:]]*([-+*/]?=[^=]|\+\+|--))|(take_damage|heal_damage)\(.*(LESION_HEAL|/datum/affliction/lesion)|internal_organs_by_name\[[^]]*\]\??\.(take_damage|heal_damage)\(|\.(apply_lesion_damage|apply_wound_damage|restore_lesions|heal_wound_damage)\(|LESION_HEAL_"),
        )
        .flt(vec![Flt::DropPaths("organ_damage_allow"), drop(r"ALLOW\([^)]*check_grep")]),
    ];
    // d3_pool: `grep -RInE --include='*.dm' <pattern> <paths>`
    for (i, (pat, paths)) in D3.iter().enumerate() {
        v.push(Part::new(
            D3_RULES[i],
            "separate object health pools",
            "a separate object health pool was reintroduced. Objects use integrity: take_damage()/repair_damage()/get_integrity(), integrity_failure and atom_destruction().",
            Files::Under(*paths, &["dm"]),
            line(pat),
        ));
    }
    v.extend(vec![
        Part::new(
            "contract_only_physical_types",
            "contract-only physical types",
            "contract-only physical type detected. Store contract identity in generic evidence/components/reagent provenance and use an existing world object.",
            Files::Under(&["code/modules/contracts"], &["dm"]),
            line(r"^/(obj|mob|turf|area)/"),
        )
        .flt(vec![drop(
            r":(/obj/item/paper/(proc/attach_contract_evidence|on_signature|on_field_written)|/mob/living/carbon/human(/proc/(refresh_contract_medical_eligibility|record_clinical_exposure|clinical_exposure_printout|medical_trial_marker_snapshot))?)($|\()",
        )]),
        // plain `grep -P`: no allow_grep
        Part::new("space_indentation", "space indentation", "space indentation detected.", Files::Code, line_g(r"(^ {2})|(^ [^ * ])|(^    +)")).flt(vec![Flt::DropPaths("space_indent_allow")]),
        Part::new(
            "mixed_tab_space_indentation",
            "mixed tab/space indentation",
            "mixed <tab><space> indentation detected.",
            Files::Code,
            line_g(r"^\t+ [^ *]"),
        ),
        Part::new(
            "improperly_pathed_static_lists",
            "improperly pathed static lists",
            "Found incorrect static list definition 'var/list/static/', it should be 'var/static/list/' instead.",
            Files::Code,
            line_i(r"var/list/static/.*"),
        )
        .allow(Allow::Strict),
        Part::new(
            "changelog",
            "changelog",
            "Do not modify the example.yml changelog file.",
            Files::Code,
            Find::Tree,
        ),
        // `{ rg -n '\\(red|...)' || true; } | wc -l`, judged against MACRO_COUNT from dependencies.sh
        Part::new(
            "color_macros",
            "color macros",
            "Do not use any byond color macros (such as \\blue), they are deprecated.",
            Files::Code,
            line(r"\\(red|blue|green|black|b|i[^mnct])"),
        )
        .allow(Allow::Strict),
        Part::new(
            "typescript_react_files",
            "typescript react files",
            "JSX file(s) detected, these must be converted to typescript (TSX).",
            Files::Code,
            Find::Tree,
        ),
        Part::new(
            "balloon_alert_sanity",
            "balloon_alert sanity",
            "Found a balloon alert with improper arguments.",
            Files::Code,
            line(r#"balloon_alert\(".*""#),
        )
        .allow(Allow::Strict),
        Part::new(
            "balloon_alert_span_check",
            "balloon_alert span check",
            "Balloon alerts should never contain spans.",
            Files::Code,
            line(r"balloon_alert\(.*[Ss][Pp][Aa][Nn]"),
        )
        .allow(Allow::Strict),
        Part::new(
            "balloon_alert_idiomatic_usage",
            "balloon_alert idiomatic usage",
            "Balloon alerts should not start with capital letters or whitespace. This includes text like 'AI'. If this is a false positive, wrap the text in UNLINT().",
            Files::Code,
            line(r#"balloon_alert\(.*?,\s*"[\sA-Z]"#),
        )
        .allow(Allow::Strict),
        // the script lists this twice (".proc ref syntax", "proc ref syntax"): one rule
        Part::new(
            "proc_ref_syntax",
            "proc ref syntax",
            "Outdated proc reference use detected in code, please use proc reference helpers.",
            Files::CodeX515,
            line(r"\.proc/"),
        )
        .allow(Allow::Strict),
        // listed twice in the script: one rule
        Part::new(
            "ambiguous_bitwise_or",
            "ambiguous bitwise or",
            "Likely operator order mistake with bitwise OR. Use parentheses to specify intention.",
            Files::Code,
            line_g(r"^(?:[^\/\n]|\/[^\/\n])*(&[ \t]*\w+[ \t]*\|[ \t]*\w+)"),
        ),
        Part::new(
            "dm_copies_of_rust_state",
            "DM copies of Rust state",
            "DM copy of Rust atmos state. Turf adjacency lives in Rust: publish air-block masks with air_update_turf(TRUE) and read with get_atmos_adjacent_turfs() / atmos_adjacent_turfs_bulk() / SSair.air_blocked().",
            Files::Code,
            line(r"\batmos_adjacent_turfs\b|\batmos_supeconductivity\b|\bcurrent_cycle\b|__update_auxtools_turf_adjacency_info|immediate_calculate_adjacent_turfs"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("rust_state_allow"), drop(r":\s*//|:\s*\*")]),
        Part::new(
            "dm_copies_of_rust_state__2",
            "DM copies of Rust state",
            "stringified argument passed to a verdigris bind. Pass numbers (GAS_ID_*, GAS_IDX(path)) across the FFI.",
            Files::Code,
            line(r#"vg_[a-z0-9_]+\([^)]*"\["#),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("rust_state_allow"), drop(r":\s*//|:\s*\*")]),
        Part::new(
            "legacy_equip_restriction_vars",
            "legacy equip restriction vars",
            "legacy can_hold/cant_hold/species_restricted. Use the property registry's predicates and constraints (code/datums/properties/).",
            Files::Code,
            line(r"\b(can_hold|cant_hold|species_restricted)\b"),
        )
        .allow(Allow::Strict)
        .flt(vec![drop(r":\s*//|:\s*\*")]),
        // `{ rg -n ... || true; } | grep -v ... | wc -l`, at most 2
        Part::new(
            "legacy_equip_restriction_vars__slot_flags",
            "legacy equip restriction vars",
            "new raw slot_flags check. Use dq_item_fits_slot_flags() / the wearable constraints.",
            Files::Code,
            line(r"slot_flags\s*&[^=]"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("slot_flags_allow"), drop(r":\s*//")]),
        Part::new(
            "html_tag_matching",
            "html tag matching",
            "Some HTML tags are missing their opening/closing partners. Please correct this.",
            Files::Under(&["code"], &["dm"]),
            Find::Custom(super::tags::mismatch_lines),
        ),
        Part::new(
            "var_in_proc_args",
            "var in proc args",
            "changed files contains proc argument starting with 'var'.",
            Files::Code,
            line_g(r"^/[\w/][^(\s]*\((?:[^)]*,\s*)?var/.*\)"),
        ),
        Part::new(
            "var_in_proc_args__multi_line",
            "var in proc args",
            "changed files contains a multi-line proc argument starting with 'var'.",
            Files::Code,
            multi_z(r"(?m)^/[\w/][^(\s]*\((?:[^()]*?,)?\s*(?:\\\s*)?var/[^\n]*", Some(first_line_has_no_close_paren)),
        ),
        Part::new(
            "unmanaged_global_vars",
            "unmanaged global vars",
            "Unmanaged global var use detected in code, please use the helpers.",
            Files::Code,
            line_g(r"^/*var/"),
        ),
    ]);
    v
}

/// The `(?=[^)\n]*\n)` of the old pattern: after the signature's `(`, the rest of that line holds no
/// `)` and the line ends. It is checked here so the pattern itself can run on the linear engine.
fn first_line_has_no_close_paren(text: &str, start: usize, _end: usize) -> bool {
    let Some(open) = text[start..].find('(') else { return false };
    let rest = &text[start + open + 1..];
    match rest.find('\n') {
        Some(nl) => !rest[..nl].contains(')'),
        None => false,
    }
}
