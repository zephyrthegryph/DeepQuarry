//! `check_grep.sh` section "code issues", first half: bindings, life, pipelines, heat, tools,
//! interactions, robots and the body model (up to the admin-rights ratchet).
//!
//! Every `$grep` of the script is `allow_grep` ([`Allow::Strict`]); a plain `grep` is [`Allow::None`].
//! Each `grep -v` after the search is a filter over the printed `file:line:text`.

use super::framework::*;

const LIFE_HOOKS: &str = "addictions|ambience|blood|breath|breathing|changeling|chemical_smoke|chemicals_in_body|confused|darksight|defib_timer|diseases|disabilities|drugged|environment|environment_special|guts|heartbeat|hud_icons_health|hud_list|instability|light|medical_side_effects|modifiers|mutations|nif|npc|organs|pain|paralysed|phobias|post_breath|pulse|radiation|random_events|regular_hud_updates|regular_status_updates|sensory_recovery|shock|silent|sleeping|slurring|special|species_components|statuses|stomach|stunned|stuttering|supernatural|temperature_damage|tf_holder|vision|vr_derez|weakened";

pub fn parts() -> Vec<Part> {
    vec![
        Part::new(
            "call_ext_outside_generated_bindings",
            "call_ext outside generated bindings",
            "call_ext/load_ext outside the generated verdigris bindings. Declare the Rust function with #[auxmacros::bind], run tools/build/build.sh verdigris-bindings, and call the generated vg_* proc.",
            Files::Code,
            line(r"call_ext|load_ext|VERDIGRIS_CALL"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("call_ext_allow"), drop(r":\s*//|:\s*\*|// .*call_ext")]),
        Part::new(
            "holder_call_proc_ref_only",
            "holder_call: PROC_REF only",
            "holder_call(owner, proc, with) takes a PROC_REF()/TYPE_PROC_REF()/GLOBAL_PROC_REF() (or one stored from them), never a string literal; `with` is the argument list, as after() takes it.",
            Files::Code,
            line(r#"holder_call\([^,()]+,\s*""#),
        )
        .allow(Allow::Strict),
        // R10: the two checks that read their names from the generated bindings are dynamic (scan_tree).
        Part::new(
            "r10_bindings_init_seeds_referenced_outside_a_var_edit",
            "R10 bindings: init_* seeds referenced outside a var-edit",
            "an init_* seed was referenced outside a var-edit. It is a seed, read once at bind; use get_*() for the live value.",
            Files::Code,
            Find::Tree,
        ),
        Part::new(
            "r10_bindings_no_member_var_caching_of_a_binding_read",
            "R10 bindings: no member-var caching of a binding read",
            "a get_*()/*_query_*() result was assigned to a var. Read it again next time; do not cache Rust-owned state across ticks (rust_bindings.md §6).",
            Files::Code,
            Find::Tree,
        ),
        Part::new(
            "life_no_life_procs",
            "life: no Life() procs",
            "Life() proc on a mob. Living mobs: add a /datum/om/stage/life stage (or a variant). Observers: override upkeep().",
            Files::Code,
            line(r"^/mob[a-zA-Z0-9_/]*/(proc/)?Life\("),
        )
        .allow(Allow::Strict),
        Part::new(
            "life_scheduler_no_handle_life_hooks",
            "life scheduler: no handle_* life hooks",
            "handle_* Life hook defined outside Life. Life() steps are /datum/om/stage/life types (code/modules/mob/living/life/).",
            Files::Code,
            line(&format!(r"^/(mob|datum/species|datum/trait)[a-zA-Z0-9_/]*/(proc/)?handle_({})\(", LIFE_HOOKS)),
        )
        .allow(Allow::Strict),
        Part::new(
            "pipelines_idle_and_park_state_in_one_place",
            "pipelines: idle and park state in one place",
            "direct write to a pipeline's idle or park state. Raise a channel with changed().",
            Files::Code,
            line(r"\.(asleep|parked|parked_index|idle_frames)\s*[|&+-]?=[^=]|\.bits\[[^]]*\]\s*[|&]?=[^=]"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("pipelines_allow"), Flt::DropLit("var/")]),
        Part::new(
            "declared_relation_fields_core_owned",
            "declared relation fields: core-owned",
            "direct write to a declared relation field outside code/datums/om/. Establish/break the relation with om_link()/om_unlink() instead -- the core is the only writer of buckled/buckled_mobs, /obj/item/grab's affecting/grabbed_by, and pulling/pulledby.",
            Files::Code,
            line(r"\.(buckled|buckled_mobs|affecting|grabbed_by|pulling|pulledby)\s*[|&+*/-]?=[^=]"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("relation_fields_allow"), Flt::DropLit("var/"), Flt::DropLit("om-field-exempt"), drop(r":[0-9]+:[[:space:]]*//")]),
        Part::new(
            "stored_timer_handles",
            "stored timer handles",
            "a timer id from om_after() is stored or returned. Use a keyed timer: after(E, delay, handler, key = \"name\"), cancel_after(), after_pending(), after_left().",
            Files::Code,
            line(r"([]A-Za-z0-9_.)][[:space:]]*[-+]?=|(^|[^[:alnum:]_])return|LAZYSET\(|LAZYADD\(|list\()[[:space:]]*om_after(_replace|_unique)?\("),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("timer_handles_allow"), drop(r"var/[[:alnum:]_]+[[:space:]]*=[[:space:]]*om_after")]),
        Part::new(
            "gas_mixture_mirror_writes",
            "gas mixture mirror writes",
            "direct write to a gas mixture temperature/volume mirror detected. Use set_temperature() / set_volume() — a raw assignment updates only the DM mirror and is ignored by the Rust atmos arena.",
            Files::Code,
            line(r"(\bair|air_contents|\bair[0-9]|cabin_air|\benvironment)\.(temperature|volume)[[:space:]]*[-+*/]?=[^=]"),
        )
        .allow(Allow::Strict)
        .flt(vec![drop(r"return_temperature|return_volume")]),
        Part::new(
            "rig_cells_move_through_the_power_ledger",
            "rig cells move through the power ledger",
            "a rig cell is drawn or charged directly. Use the rig's draw_power() / add_power() ledger.",
            Files::Under(&["code/modules/clothing/spacesuits/rig", "code/modules/mob/living/carbon/human/species/station/protean/protean_rig.dm"], &["dm"]),
            line(r"\bcell\.(use|give)\("),
        )
        .allow(Allow::Strict)
        .flt(vec![drop(r"cell\.use\(units, FALSE\)|cell\.give\(joules \* CELLRATE, FALSE\)")]),
        Part::new(
            "one_revive_path_return_from_death",
            "one revive path: return_from_death()",
            "hand-rolled revive (living/dead list swap or time-of-death reset). Call L.return_from_death(reason, source, flags).",
            Files::Code,
            line(r"(dead_mob_list\s*-=|dead_mob_list\.Remove\(|living_mob_list\s*(\+=|\|=)|living_mob_list\.Add\(|registry_leave\(REGISTRY_DEAD_MOBS|registry_join\(REGISTRY_LIVING_MOBS|\btimeofdeath\s*=\s*(0|null)\b)"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("revive_allow"), Flt::DropLit("var/")]),
        // dynamic: the generated defines are read from code/__defines/verdigris/_bindings.dm
        Part::new(
            "thermal_constants_generated_not_redefined_h1",
            "thermal constants: generated, not redefined (H1)",
            "a generated verdigris constant is redefined in DM. Change it in the Rust source (@dm-define) and regenerate the bindings.",
            Files::Code,
            Find::Tree,
        ),
        Part::new(
            "thermal_constants_no_hardcoded_body_temperatures_or_human_heat_capacities_h1",
            "thermal constants: no hardcoded body temperatures or human heat capacities (H1)",
            "hardcoded body temperature or human heat capacity. Use BODYTEMP_NORMAL / HUMAN_HEAT_CAPACITY (generated from verdigris/domains/heat/src/consts.rs).",
            Files::Code,
            line(r"\b(310(\.(15|055|0?5))?|280000|249840)\b"),
        )
        .allow(Allow::Strict)
        .flt(vec![
            Flt::Strip,
            keep(r"^[^:]+:[0-9]+:.*\b(310(\.(15|055|0?5))?|280000|249840)\b"),
            Flt::KeepI("temp|heat|capacit".to_string()),
            Flt::DropPaths("thermal_allow"),
        ]),
        Part::new(
            "thermal_constants_no_hardcoded_body_temperatures_or_human_heat_capacities_h1__t0c_37",
            "thermal constants: no hardcoded body temperatures or human heat capacities (H1)",
            "T0C + 37 is BODYTEMP_NORMAL.",
            Files::Code,
            line(r"^[^/]*(\bT0C[[:space:]]*\+[[:space:]]*37\b|\b37[[:space:]]*\+[[:space:]]*T0C\b)"),
        )
        .allow(Allow::Strict),
        Part::new(
            "one_temperature_api_no_ad_hoc_return_temperature_procs_h1",
            "one temperature API: no ad-hoc return_temperature procs (H1)",
            "return_temperature() is only the gas mixture accessor. Atoms override get_temperature() / get_interior_temperature() (code/modules/heat/heat.dm).",
            Files::Code,
            line(r"^/[A-Za-z0-9_/]*/return_temperature\("),
        )
        .allow(Allow::Strict)
        .flt(vec![drop(r"^code/ATMOSPHERICS/gasmixtures/gas_mixture\.dm:[0-9]*:/datum/gas_mixture/proc/return_temperature\(")]),
        Part::new(
            "one_temperature_api_a_turf_keeps_no_live_temperature_of_its_own",
            "one temperature API: a turf keeps no live temperature of its own",
            "a turf has no temperature var. Read get_temperature(), write add_heat()/set_temperature(); initial_temperature is only the seed.",
            Files::Code,
            line(r"\b(T|turf|target_turf|new_turf|floor|modeled_location|loc_as_turf|simulated_turf|exterior_turf)\.temperature"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::Strip, keep(r"\.temperature")]),
        Part::new(
            "input_modifier_ladders",
            "input: modifier ladders",
            "a click modifier check outside the input router. Add a row to a click table in code/modules/keybindings/router.dm and branch on the INPUT_ACTION_* it produces.",
            Files::Code,
            line(r#"\bmodifiers\[\s*"(shift|ctrl|alt|middle|right|left|xbutton1|xbutton2)"|LAZYACCESS\(\s*modifiers\s*,\s*(SHIFT_CLICK|CTRL_CLICK|ALT_CLICK|MIDDLE_CLICK|RIGHT_CLICK|LEFT_CLICK|BUTTON4|BUTTON5)|\bmodifiers\[\s*(SHIFT_CLICK|CTRL_CLICK|ALT_CLICK|MIDDLE_CLICK|RIGHT_CLICK|LEFT_CLICK|BUTTON4|BUTTON5)\s*\]"#),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("input_ladder_allow")]),
        // rg -PUn over `code --glob '*.dm'`, then `grep -E '_act'`
        Part::new(
            "tools_act_procs_that_bounce_into_attackby",
            "tools: *_act procs that bounce into attackby",
            "a *_act tool hook calls attackby(). Do the tool's work in the hook with use_tool().",
            Files::Code,
            multi_u(r"^/[^\n]*/(screwdriver|crowbar|wrench|wirecutter|multitool|welder)_act(_secondary)?\([^\n]*\)\n(?:(?:\t[^\n]*|[ \t]*)\n)*?\t[^\n]*(?<![.\w])attackby\("),
        )
        .allow(Allow::Strict)
        .flt(vec![keep(r"_act")])
        .needle("attackby("),
        Part::new(
            "tools_istype_checks_on_tool_types",
            "tools: istype checks on tool types",
            "an istype() check on a tool type. Use has_tool_quality(TOOL_*), or get_welder()/get_multitool() to read the tool.",
            Files::Code,
            line(r"istype\([^,]+,\s*/obj/item/(tool|weldingtool|multitool)\b"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("tool_istype_allow")]),
        Part::new(
            "tools_deprecated_is_tool_helpers",
            "tools: deprecated is_<tool>() helpers",
            "is_<tool>() helpers are gone. Use has_tool_quality(TOOL_*).",
            Files::Code,
            line(r"\.is_(screwdriver|wrench|crowbar|wirecutter|multitool|welder)\(\)"),
        )
        .allow(Allow::Strict),
        Part::new(
            "interactions_no_legacy_handlers_or_object_verbs_i7",
            "interactions: no legacy handlers or object verbs (I7)",
            "object verbs are interactions now. Declare an INTERACT_VERB (code/__defines/interactions.dm) instead.",
            Files::Code,
            line(r"^/(obj|turf)(/[A-Za-z0-9_]+)*/verb/[A-Za-z0-9_]+\("),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("i7_verb_allow")]),
        // grep -R: dot-files included, no allow_grep
        Part::new(
            "robot_cell_writes_outside_the_power_ledger",
            "robot cell writes outside the power ledger",
            "direct robot cell write detected. Use draw_power() / add_power() with ROBOT_CELL_JOULES().",
            Files::Under(&["code/modules/mob/living/silicon/robot"], &["dm"]),
            line(r"\bcell\.(charge[[:space:]]*[-+*/]?=[^=]|use\(|give\(|checked_use\()"),
        )
        .flt(vec![drop(r"/robot/robot\.dm:")]),
        Part::new(
            "body_factors_no_chemical_effects",
            "body factors: no chemical effects",
            "chem_effects / add_chemical_effect detected. Declare body factors on the reagent (factors = alist(BF_X = value)) and read them with factor(BF_X).",
            Files::Code,
            line(r"\b(add_chemical_effect|remove_chemical_effect|chem_effects)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "biology_no_issynthetic",
            "biology: no isSynthetic",
            "isSynthetic() detected. Use HAS_SYNTHETIC_BIOLOGY(mob) / mob.biology(), body.biology_of(part), or robolimb_model().",
            Files::Code,
            line(r"\bisSynthetic\("),
        )
        .allow(Allow::Strict),
        Part::new(
            "organs_construction_predicates",
            "organs: construction predicates",
            "raw robotic threshold detected. Use is_robotic() / is_assisted() / is_organic() / is_nanoform().",
            Files::Code,
            line(r"robotic\s*(>=\s*ORGAN_(ROBOT|ASSISTED|NANOFORM)|<\s*ORGAN_(ROBOT|ASSISTED)|>\s*ORGAN_ASSISTED|<=\s*ORGAN_ASSISTED)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "nutrition_writes",
            "nutrition writes",
            "raw nutrition write detected. Use adjust_nutrition() / set_nutrition().",
            Files::Code,
            line(r"(\.nutrition\s*(\+=|-=|=[^=])|^\s+nutrition\s*(\+=|-=))"),
        )
        .allow(Allow::Strict),
        Part::new(
            "physiology_no_asphyxia_injury",
            "physiology: no asphyxia injury",
            "asphyxia injury detected. Model the mechanism (restriction, breath quality, factor) or use add_oxygen_debt() / oxygen_debt().",
            Files::Code,
            line(r"\b(INJURY_ASPHYXIA|INJURY_CATEGORY_ASPHYXIA|BF_INCOMING_ASPHYXIA)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "body_factors_no_mechanical_effects",
            "body factors: no mechanical effects",
            "mechanical_effects / vital_effects / od_boost detected. Declare body factors on the affliction (factors = alist(BF_X = value)).",
            Files::Code,
            line(r"\b(mechanical_effects|vital_effects|od_boost|get_vital_effects)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "body_factors_no_modifier_numeric_fields",
            "body factors: no modifier numeric fields",
            "a removed modifier numeric field is referenced. Declare it in the body effect's factors table and read factor(BF_X).",
            Files::Code,
            line(r"\b(endurance_flat|endurance_percent|disable_duration_percent|incoming_[a-z]+_percent|outgoing_melee_damage_percent|bleeding_rate_percent|metabolism_percent|icon_scale_[xy]_percent|attack_speed_percent|accuracy_dispersion|pain_immunity|pulse_modifier|pulse_set_level|emp_modifier|explosion_modifier|[a-z]+_injury_resistance|[a-z]+_physical_resistance|[a-z]+_thermal_resistance)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "body_factors_no_modifier_numeric_fields__2",
            "body factors: no modifier numeric fields",
            "a modifier's slowdown/evasion/accuracy/... is read directly. Those are body factors: read factor(BF_X) on the holder.",
            Files::Code,
            line(r"\b(M|mod|modifier)\.(slowdown|haste|evasion|accuracy|siemens_coefficient|heat_protection|cold_protection|vision_flags|armor_percent)\b"),
        )
        .allow(Allow::Strict),
        Part::new(
            "heat_direct_bodytemperature_writes_h2",
            "heat: direct bodytemperature writes (H2)",
            "bodytemperature written directly. Use add_heat(), adjust_bodytemperature() or set_bodytemperature().",
            Files::Code,
            line(r"(^|[^A-Za-z0-9_])bodytemperature\s*([-+*/]?=[^=]|\+\+|--)"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("bodytemp_allow"), drop(r":\s*//|var/")]),
    ]
}
