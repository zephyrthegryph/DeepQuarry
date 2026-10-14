use super::lookup;

/// Names handled by intrinsic named-call lowering before authored dispatch.
/// Conservative across arities: an unsupported intrinsic arity is not evidence
/// that an authored procedure was selected.
pub fn is_intrinsic_named_call(name: &str) -> bool {
    lookup(name).is_some()
        || matches!(
            name,
            "input"
                | "nameof"
                | "rgb"
                | "."
                | ".."
                | "rand"
                | "isnull"
                | "ceil"
                | "floor"
                | "round"
                | "regex"
                | "length"
                | "copytext"
                | "text2num"
                | "findtext"
                | "clamp"
                | "min"
                | "max"
                | "file"
                | "icon"
                | "sound"
                | "newlist"
                | "list"
                | "new"
                | "sleep"
                | "alert"
                | "time2text"
                | "json_encode"
        )
}
