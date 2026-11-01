//! `check_grep.sh` section "regexes requiring PCRE2" (the script skips it when ripgrep lacks PCRE2;
//! the engine always runs it) and the config check at the end. All are `$grep` = `rg -P`
//! ([`Allow::Strict`]).

use super::framework::*;

pub fn parts() -> Vec<Part> {
    vec![
        Part::new(
            "deoptimization_of_range_view_with_as_anything",
            "deoptimization of range/view with as anything",
            "range(), orange(), view(), and oview() perform significantly worse with as anything.",
            Files::Code,
            line(r"var/(?!atom).* as anything in o?(range|view)\("),
        )
        .allow(Allow::Strict)
        .needle(" as anything in "),
        Part::new(
            "to_chat_sanity",
            "to_chat sanity",
            "to_chat() missing arguments.",
            Files::Code,
            line(r"to_chat\((?!.*,).*\)"),
        )
        .allow(Allow::Strict)
        .needle("to_chat("),
        Part::new(
            "timer_flag_sanity",
            "timer flag sanity",
            "TIMER_OVERRIDE used without TIMER_UNIQUE.",
            Files::Code,
            line(r"addtimer\((?=.*TIMER_OVERRIDE)(?!.*TIMER_UNIQUE).*\)"),
        )
        .allow(Allow::Strict)
        .needle("TIMER_OVERRIDE"),
        Part::new(
            "string_built_reactive_keys",
            "string-built reactive keys",
            "World keys are numeric (om_world_publish / om_world_on_key with WORLD_KEY_* and om_world_key_id()), never strings (object_model_core.md §4.8).",
            Files::Code,
            line(r#"(publish_reactive_dependency|hibernate_reactive_machine|wake_reactive_machine)\(|om_world_(publish|on_key)\([^)]*""#),
        )
        .allow(Allow::Strict),
        // `rg -PU '[^\n]$(?!\n)'`: a file whose last line has no newline
        Part::new(
            "trailing_newlines",
            "trailing newlines",
            "File(s) with no trailing newline detected, please add one.",
            Files::Code,
            Find::Custom(no_trailing_newline),
        )
        .allow(Allow::Strict),
        Part::new(
            "improper_atom_initialize_args",
            "improper atom initialize args",
            "Initialize override without 'mapload' argument.",
            Files::Code,
            line(r"^/(obj|mob|turf|area|atom)/.+/Initialize\((?!mapload).*\)"),
        )
        .allow(Allow::Strict)
        .needle("/Initialize("),
        // `rg -n ... | wc -l`, at most 2 (a ceiling in lint_scopes.toml)
        Part::new(
            "improper_atom_new_usage",
            "improper atom New usage",
            "Do not use any New() calls, they've been replaced by Initialize(mapload).",
            Files::Code,
            line(r"^/?(obj|mob|turf|area|atom)/?.*/New\("),
        )
        .allow(Allow::Strict),
        Part::new(
            "legacy_machinery_structural_damage_overrides",
            "legacy machinery structural damage overrides",
            "machinery must use obj_integrity and atom_break/atom_fix/atom_destruction; private take_damage/fall_apart handlers are forbidden.",
            Files::Code,
            line(r"^/obj/machinery[^\n]*/(take_damage|fall_apart)\("),
        )
        .allow(Allow::Strict),
        Part::new(
            "legacy_machinery_common_tool_dispatch",
            "legacy machinery common-tool dispatch",
            "machinery attackby() must not dispatch common tools or legacy deconstruction helpers; use focused *_act hooks/declarative maintenance.",
            Files::Code,
            multi_u(r"^/obj/machinery[^\n]*/attackby\([^\n]*\)\n(?:(?!^/)[\s\S])*?(?:has_tool_quality\(TOOL_|istype\([^\n]*?/obj/item/multitool|default_(?:deconstruction_screwdriver|deconstruction_crowbar|unfasten_wrench)\(|computer_deconstruction_screwdriver\(|alarm_deconstruction_(?:screwdriver|wirecutters)\()"),
        )
        .allow(Allow::Strict)
        .needle("attackby("),
        Part::new(
            "legacy_machinery_common_tool_dispatch__helpers",
            "legacy machinery common-tool dispatch",
            "removed machinery maintenance helpers must not return; use declarative maintenance flags and focused tool hooks.",
            Files::Code,
            line(r"\b(default_deconstruction_screwdriver|default_deconstruction_crowbar|default_unfasten_wrench|computer_deconstruction_screwdriver|alarm_deconstruction_screwdriver|alarm_deconstruction_wirecutters)\s*\("),
        )
        .allow(Allow::Strict),
        // The volatile abductor RTG is the sole allowlisted scenario device (`--glob '!...'`).
        Part::new(
            "legacy_machinery_common_tool_dispatch__qdel_src",
            "legacy machinery common-tool dispatch",
            "machinery structural damage handlers must route through obj_integrity, not qdel(src).",
            Files::Code,
            multi_u(r"^/obj/machinery[^\n]*/(?:ex_act|bullet_act)\([^\n]*\)\n(?:(?:\t.*|\s*)\n?){0,24}?\t*qdel\(src\)"),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("machinery_qdel_allow")])
        .needle("qdel(src)"),
        Part::new(
            "legacy_machinery_common_tool_dispatch__ex_act_take_damage",
            "legacy machinery common-tool dispatch",
            "subtype ex_act must preserve orthogonal effects and chain to generic machinery explosion damage.",
            Files::Code,
            multi_u(r"^/obj/machinery[^\n]*/ex_act\([^\n]*\)\n(?:(?:\t.*|\s*)\n?){0,24}?\t*take_damage\("),
        )
        .allow(Allow::Strict)
        .flt(vec![Flt::DropPaths("machinery_ex_act_allow")])
        .needle("take_damage("),
        Part::new(
            "broken_html",
            "broken html",
            "A broken span tag class is present (check quotes).",
            Files::Code,
            line(r"<\s*span\s+class\s*=\s*('[^'>]+|[^'>]+')\s*>"),
        )
        .allow(Allow::Strict),
        Part::new(
            "old_style_hrefs",
            "old style hrefs",
            "old-style hrefs detected, see ripgrep output.",
            Files::Code,
            line(r#"href[\s='" ]*\?"#),
        )
        .allow(Allow::Strict),
        Part::new(
            "blocking_shell_toast_enabled_in_example_config",
            "blocking shell toast enabled in example config",
            "config/example/config.txt enables TOAST_NOTIFICATION_ON_INIT; it hangs -safe servers after init. Keep it commented.",
            Files::Code,
            Find::Tree,
        ),
    ]
}

/// `[^\n]$(?!\n)` over the whole file: the last character of a text that does not end in a newline.
fn no_trailing_newline(f: &crate::tree::SourceFile) -> Vec<usize> {
    let text = f.text();
    if text.is_empty() || text.ends_with('\n') {
        Vec::new()
    } else {
        vec![f.raw().num_lines()]
    }
}
