//! Scalar-result policy from the pinned legacy Analyze reference. These names
//! are NOT resolution: use only after the native source query proves that no
//! source implementation shadows the builtin. Engine-selected methods also need
//! their receiver contract; unknown/dynamic calls are never accepted by spelling.
pub(crate) const BUILTIN_VALUE_CALLS: &[&str] = &[
    "rand", "prob", "round", "floor", "ceil", "abs", "min", "max", "sqrt", "sin", "cos", "num2text", "text2num", "list2params", "length", "lowertext", "uppertext", "copytext",
    "replacetext", "findtext", "jointext", "get_dist", "nameof", "ckey", "clamp", "isnull", "initial", "md5", "replacetextEx", "turn", "get_dir", "html_decode", "html_encode",
    "text2ascii", "ascii2text", "file2text", "rgb", "istype", "ispath", "islist", "isnum", "istext", "time2text", "addtext", "splittext", "json_encode", "text2path", "trim",
    "ref", "url_encode", "url_decode", "sha1", "findtextEx", "findlasttext", "findlasttextEx", "findtext_char", "length_char", "copytext_char", "sorttext", "sorttextEx", "log", "tan", "arcsin", "arccos", "arctan", "sign", "text",
    "roll", "cmptext", "cmptextEx", "lentext", "winget", "fexists", "file", "hascall",
];

pub(crate) const WORLD_VALUE_VARS: &[&str] = &[
    "time", "timeofday", "realtime", "tick_lag", "tick_usage", "cpu", "map_cpu", "maxx", "maxy", "maxz", "fps", "byond_version", "byond_build", "port", "address", "name", "version",
];
