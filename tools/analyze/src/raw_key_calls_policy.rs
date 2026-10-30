//! Original key/source call policy over a borrowed, comment-stripped raw view.
//! A declaration DSL policy only; no type/procedure tree or semantic parser.
use crate::raw_marker_policy::{matching_paren,split_args};
/// What a key literal names, by the call it sits in (doc/rewrite/final_api.html section 4,
/// "Three kinds of key").
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum KeyKind {
    Op,
    Capability,
}

#[derive(Clone, Debug)]
pub struct KeyRef {
    pub kind: KeyKind,
    pub key: String,
    /// The call it sits in.
    pub call: String,
    pub rel: String,
    pub line: u32,
}

/// Calls whose string-literal arguments are op keys, and those whose first literal is a capability key.
pub const OP_KEY_CALLS: &[&str] = &[
    "extend",
    "without",
    "on_op",
    "shares_effects",
    "above",
    "perform_op",
    "e0_perform_op",
];
pub const CAP_KEY_CALLS: &[&str] = &["configure"];
/// Calls whose `source =` argument must be a datum or SRC_*, never text or null.
pub const SOURCE_CALLS: &[&str] = &[
    "hold",
    "hold_until",
    "hold_override",
    "grant",
    "release",
    "status_end",
];


pub fn visit_calls(rel: &str, stripped: &str, starts: &[u32], mut key: impl FnMut(KeyRef), mut bad_source: impl FnMut((String,u32,String))) {
    static RE: std::sync::LazyLock<crate::pat::Pat> = std::sync::LazyLock::new(|| {
        crate::pat::Pat::new(
            r"(?<![\w./])(extend|without|on_op|shares_effects|above|perform_op|e0_perform_op|configure|hold|hold_until|hold_override|grant|release|status_end)\s*\(",
        )
    });
    let line_of = |off: usize| -> u32 {
        match starts.binary_search(&(off as u32)) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    };
    for m in RE.captures_iter(stripped) {
        let name = m.s(1);
        let open = m.end(0) - 1;
        let Some(close) = matching_paren(stripped, open) else {
            continue;
        };
        let body = &stripped[open + 1..close];
        let line = line_of(m.start(1));
        let args = split_args(body);
        if OP_KEY_CALLS.contains(&name) {
            for a in &args {
                if let Some(s) = a.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
                    // `[x]` interpolation makes it a runtime value, not a key.
                    if !s.is_empty() && !s.contains('[') && !s.contains(' ') {
                        key(KeyRef {
                            kind: KeyKind::Op,
                            key: s.to_string(),
                            call: name.to_string(),
                            rel: rel.to_string(),
                            line,
                        });
                    }
                }
            }
        }
        if CAP_KEY_CALLS.contains(&name) {
            if let Some(s) = args
                .first()
                .and_then(|a| a.strip_prefix('"'))
                .and_then(|s| s.strip_suffix('"'))
            {
                if !s.is_empty() && !s.contains('[') {
                    key(KeyRef {
                        kind: KeyKind::Capability,
                        key: s.to_string(),
                        call: name.to_string(),
                        rel: rel.to_string(),
                        line,
                    });
                }
            }
        }
        if SOURCE_CALLS.contains(&name) {
            for a in &args {
                let compact = a.replace(' ', "");
                if let Some(v) = compact.strip_prefix("source=") {
                    if v == "null" || v.starts_with('"') {
                        bad_source((rel.to_string(), line, v.to_string()));
                    }
                }
            }
        }
    }
}
