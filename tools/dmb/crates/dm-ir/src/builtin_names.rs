//! Spellings of BYOND built-in variables and procedures on any built-in type.
//!
//! Diagnostics only. When the native model cannot prove that a name is absent
//! (its intrinsic inventory is partial), a name outside these lists cannot be a
//! hidden built-in, so the failure is the author's undefined name rather than a
//! native limitation. The lists deliberately over-include: a spurious entry
//! only turns a source error back into a "native unsupported" fallback.

/// Built-in variable names of every built-in type, plus procedure-scope names.
pub fn is_builtin_var(name: &str) -> bool {
    BUILTIN_VARS.binary_search(&name).is_ok()
}

/// Built-in procedure and verb names of every built-in type.
pub fn is_builtin_proc(name: &str) -> bool {
    BUILTIN_PROCS.binary_search(&name).is_ok()
}

/// Whether a type can inherit a built-in variable `name`. A plain datum (no
/// type in its ancestry under a built-in root other than /datum, see
/// `is_plain_datum_path`) has only the datum built-ins; every other type keeps
/// the conservative union.
pub fn is_builtin_var_in(plain_datum: bool, name: &str) -> bool {
    if plain_datum {
        matches!(name, "parent_type" | "tag" | "type" | "vars")
    } else {
        is_builtin_var(name)
    }
}

/// Procedure counterpart of `is_builtin_var_in`.
pub fn is_builtin_proc_in(plain_datum: bool, name: &str) -> bool {
    if plain_datum {
        matches!(name, "Del" | "New" | "Read" | "Topic" | "Write")
    } else {
        is_builtin_proc(name)
    }
}

/// One type path lies outside every built-in root except /datum. A type is a
/// plain datum only when this holds for each path in its ancestry.
pub fn is_plain_datum_path(owner: &str) -> bool {
    plain_datum(owner)
}

fn plain_datum(owner: &str) -> bool {
    let root = owner.trim_start_matches('/').split('/').next().unwrap_or("");
    !root.is_empty()
        && !matches!(
            root,
            "atom" | "obj" | "mob" | "turf" | "area" | "movable" | "client" | "world" | "image"
                | "mutable_appearance" | "appearance" | "sound" | "icon" | "regex" | "savefile"
                | "list" | "alist" | "exception" | "database" | "particles" | "matrix"
                | "generator" | "callee" | "filters" | "vector" | "pixloc" | "proc" | "verb"
                | "var" | "global"
        )
}

// Sorted (byte order) for binary search; `builtin_lists_are_sorted` checks it.
const BUILTIN_VARS: &[&str] = &[
    "CGI", "address", "alpha", "animate_movement", "appearance", "appearance_flags", "area",
    "args", "authenticate", "blend_mode", "bound1", "bound2", "bound_height", "bound_width",
    "bound_x", "bound_y", "bounds", "byond_build", "byond_version", "cache_lifespan", "callee",
    "caller", "cd", "channel", "ckey", "client", "color", "color_change", "command_text",
    "computer_id", "connection", "contents", "control_freak", "count", "cpu",
    "default_verb_category", "density", "desc", "dir", "drift", "echo", "edge_limit",
    "environment", "eof", "executor", "eye", "fade", "fadein", "falloff", "file", "filters",
    "flags", "fps", "frequency", "friction", "game_state", "gender", "glide_size", "global",
    "gradient", "gravity", "group", "grow", "height", "host", "hub", "hub_password", "icon",
    "icon_h", "icon_size", "icon_state", "icon_w", "icon_z", "images", "inactivity", "index",
    "infra_luminosity", "internet_address", "invisibility", "key", "layer", "lazy_eye", "len",
    "lifespan", "line", "loc", "locs", "log", "loop_checks", "luminosity", "map_cpu", "map_format",
    "maptext", "maptext_height", "maptext_width", "maptext_x", "maptext_y", "match", "maxx",
    "maxy", "maxz", "mob", "mouse_drag_pointer", "mouse_drop_pointer", "mouse_drop_zone",
    "mouse_opacity", "mouse_over_pointer", "mouse_pointer_icon", "movement_mode", "name", "next",
    "offset", "opacity", "overlays", "override", "pan", "params", "parent_type", "particles",
    "perspective", "pitch", "pixel_w", "pixel_x", "pixel_y", "pixel_z", "pixloc", "plane", "port",
    "position", "preload_rsc", "priority", "proc", "process", "reachable", "realtime",
    "render_source", "render_target", "repeat", "rotation", "scale", "screen", "screen_loc",
    "script", "see_in_dark", "see_infrared", "see_invisible", "sight", "sleep_offline", "spawning",
    "spin", "src", "statobj", "statpanel", "status", "step_size", "step_x", "step_y", "suffix",
    "system_type", "tag", "text", "tick_lag", "tick_usage", "time", "timeofday", "timezone",
    "transform", "turf", "type", "underlays", "url", "usr", "vars", "velocity", "verbs", "version",
    "view", "virtual_eye", "vis_contents", "vis_flags", "vis_locs", "visibility", "volume", "wait",
    "width", "world", "x", "y", "z",
];

const BUILTIN_PROCS: &[&str] = &[
    "Add", "AddCredits", "AddText", "Blend", "Bump", "Center", "CheckPassport", "ClearMedal",
    "Click", "Command", "Copy", "Crop", "Cross", "Crossed", "Cut", "DblClick", "Del", "DrawBox",
    "East", "Enter", "Entered", "Error", "Exit", "Exited", "Export", "ExportText", "Find", "Flip",
    "Flush", "GetConfig", "GetCredits", "GetMedal", "GetPixel", "GetScores", "Height",
    "IconStates", "Import", "ImportText", "Insert", "Interpolate", "Invert", "IsBanned",
    "IsSubscribed", "Join", "Lock", "Login", "Logout", "MapColors", "MeasureText", "MouseDown",
    "MouseDrag", "MouseDrop", "MouseEntered", "MouseExited", "MouseMove", "MouseUp", "MouseWheel",
    "Move", "Multiply", "New", "North", "Northeast", "Northwest", "OpenPort", "PayCredits",
    "Profile", "Read", "Reboot", "Remove", "RemoveAll", "RenderIcon", "Replace", "Repop", "Scale",
    "SendPage", "SetConfig", "SetIntensity", "SetMedal", "SetScores", "Shift", "South",
    "Southeast", "Southwest", "Splice", "Stat", "Subtract", "Swap", "SwapColor", "Tick", "Topic",
    "Translate", "Turn", "Uncross", "Uncrossed", "Unlock", "West", "Width", "Write",
];

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn builtin_lists_are_sorted() {
        for list in [BUILTIN_VARS, BUILTIN_PROCS] {
            assert!(list.windows(2).all(|pair| pair[0] < pair[1]), "{list:?}");
        }
        assert!(is_builtin_var("vars") && is_builtin_proc("New"));
        assert!(!is_builtin_var("nonexistent") && !is_builtin_proc("not_a_proc"));
        assert!(is_plain_datum_path("/datum/thing") && is_plain_datum_path("/thing"));
        assert!(!is_plain_datum_path("/obj/thing") && !is_plain_datum_path("/"));
        assert!(!is_builtin_var_in(true, "x") && is_builtin_var_in(false, "x"));
        assert!(is_builtin_var_in(true, "vars") && !is_builtin_proc_in(true, "Bump"));
    }
}
