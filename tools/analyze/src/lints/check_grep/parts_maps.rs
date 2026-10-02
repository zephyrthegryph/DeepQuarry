//! `check_grep.sh` section "map issues" (and the map checks of the PCRE2 section).

use super::framework::*;

pub fn parts() -> Vec<Part> {
    vec![
        // `grep -El`: the files that have a one-line `"a" = (...)` definition.
        Part::new(
            "tgm",
            "TGM",
            "Non-TGM formatted map detected. Please convert it using Map Merger!",
            Files::Maps,
            Find::FileAny(r#"^".+" = \(.+\)"#.to_string()),
        ),
        Part::new(
            "iconstate_tags",
            "iconstate tags",
            "tag vars from icon state generation detected in maps, please remove them.",
            Files::Maps,
            line_g(r#"^\ttag = \"icon"#),
        ),
        Part::new(
            "suspicious_symbols_in_maps",
            "suspicious symbols in maps",
            "potential html code in maps detected.",
            Files::Maps,
            line_g(r"[<>]"),
        ),
        Part::new(
            "step_xy",
            "step_[xy]",
            "The variables 'step_x' and 'step_y' are present on a map, and they 'break' movement ingame.",
            Files::Maps,
            line(r"step_[xy]"),
        )
        .allow(Allow::Strict),
        // `grep -Pzo A || grep -Pzo B || grep -Pzo C`: the first alternative with a hit is the only
        // one that prints, so only that one counts (group "apc").
        Part::new(
            "wrongly_offset_apcs",
            "wrongly offset APCs",
            "found an APC with a manually set pixel_x or pixel_y that is not +-25.",
            Files::Maps,
            multi_z(r"/obj/structure/machinery/power/apc[/\w]*?\{\n[^}]*?pixel_[xy] = -?[013-9]\d*?[^\d]*?\s*?\},?\n", None),
        )
        .needle("/power/apc").group("apc"),
        Part::new(
            "wrongly_offset_apcs__2",
            "wrongly offset APCs",
            "found an APC with a manually set pixel_x or pixel_y that is not +-25.",
            Files::Maps,
            multi_z(r"/obj/structure/machinery/power/apc[/\w]*?\{\n[^}]*?pixel_[xy] = -?\d+?[0-46-9][^\d]*?\s*?\},?\n", None),
        )
        .needle("/power/apc").group("apc"),
        Part::new(
            "wrongly_offset_apcs__3",
            "wrongly offset APCs",
            "found an APC with a manually set pixel_x or pixel_y that is not +-25.",
            Files::Maps,
            multi_z(r"/obj/structure/machinery/power/apc[/\w]*?\{\n[^}]*?pixel_[xy] = -?\d{3,1000}[^\d]*?\s*?\},?\n", None),
        )
        .needle("/power/apc").group("apc"),
        Part::new(
            "vareditted_areas",
            "vareditted areas",
            "Vareditted /area path use detected in maps, please replace with proper paths.",
            Files::Maps,
            line_g(r"^/area/.+[\{]"),
        ),
        Part::new(
            "base_turf_usage",
            "base /turf usage",
            "base /turf path use detected in maps, please replace with proper paths.",
            Files::Maps,
            line_g(r"\W\/turf\s*[,\){]"),
        ),
        // `*.dme` at the repo root: done by the lint's scan_tree.
        Part::new(
            "test_map_included",
            "test map included",
            "A map containing the word 'test' is included. This is not allowed to be committed.",
            Files::Maps,
            Find::Tree,
        ),
        // ---- the PCRE2 section ----
        Part::new(
            "empty_variable_values",
            "empty variable values",
            "Empty variable value list detected in map file. Please remove the curly brackets entirely.",
            Files::Maps,
            multi_u("\\{\\n\\t\\},"),
        )
        .allow(Allow::Strict)
        .needle("{\n\t},"),
        Part::new(
            "tag",
            "tag",
            "A map has 'tag' set on an atom. It may cause problems and should be removed.",
            Files::Maps,
            line(r"( |\t|;|\{)tag( ?)="),
        )
        .allow(Allow::Strict),
    ]
}
