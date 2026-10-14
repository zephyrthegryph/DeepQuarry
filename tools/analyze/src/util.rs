//! Small helpers that make Rust string handling match the Python the lints were written in.
//!
//! The old lints were Python: `str.split()`, `str.strip()` and `" ".join(line.split())` use
//! Python's notion of whitespace (Unicode White_Space plus U+001C..U+001F). Findings must be
//! identical, so ports use these instead of the std equivalents wherever whitespace matters.

/// Python's `str.isspace()` for one character.
#[inline]
pub fn is_py_space(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// `str.split()` with no argument: runs of whitespace separate, empty fields are dropped.
pub fn py_split(s: &str) -> impl Iterator<Item = &str> {
    s.split(is_py_space).filter(|p| !p.is_empty())
}

/// `" ".join(s.split())`: the whitespace-normalized text a baseline fingerprint stores.
pub fn normalize_ws(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for part in py_split(s) {
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(part);
    }
    out
}

/// `str.strip()`.
pub fn py_strip(s: &str) -> &str {
    s.trim_matches(is_py_space)
}

/// `str.lstrip()`.
pub fn py_lstrip(s: &str) -> &str {
    s.trim_start_matches(is_py_space)
}

/// `str.rstrip()`.
pub fn py_rstrip(s: &str) -> &str {
    s.trim_end_matches(is_py_space)
}

/// The part of `line` before the first `//` (`line.split("//", 1)[0]`).
pub fn before_slashes(line: &str) -> &str {
    match line.find("//") {
        Some(i) => &line[..i],
        None => line,
    }
}

/// Python's universal-newline translation done by `open(path).read()`: `\r\n` and lone `\r`
/// both become `\n`.
pub fn universal_newlines(s: String) -> String {
    if !s.contains('\r') {
        return s;
    }
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\r' {
            if chars.peek() == Some(&'\n') {
                chars.next();
            }
            out.push('\n');
        } else {
            out.push(c);
        }
    }
    out
}

/// `os.path.relpath(path, root).replace(os.sep, "/")` for a path already under root.
pub fn rel_slash(path: &std::path::Path, root: &std::path::Path) -> String {
    let p = path.strip_prefix(root).unwrap_or(path);
    p.to_string_lossy().replace('\\', "/")
}

/// True when `rel` starts with any of `prefixes` (`rel.startswith(tuple)`).
pub fn starts_with_any<S: AsRef<str>>(rel: &str, prefixes: &[S]) -> bool {
    prefixes.iter().any(|p| rel.starts_with(p.as_ref()))
}

/// `under(path, roots)`: `path` is one of `roots` or a subtype of one (whole path segments).
pub fn under<S: AsRef<str>>(path: &str, roots: &[S]) -> bool {
    !path.is_empty()
        && roots.iter().any(|r| {
            let r = r.as_ref();
            path == r || (path.starts_with(r) && path.as_bytes().get(r.len()) == Some(&b'/'))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_matches_python_join_split() {
        assert_eq!(normalize_ws("\t  qdel(src)  \t// x"), "qdel(src) // x");
        assert_eq!(normalize_ws("a\u{1c}b"), "a b");
        assert_eq!(normalize_ws(""), "");
    }

    #[test]
    fn universal_newlines_translate() {
        assert_eq!(universal_newlines("a\r\nb\rc\n".to_string()), "a\nb\nc\n");
    }

    #[test]
    fn under_whole_segments() {
        assert!(under("/obj/item", &["/obj"]));
        assert!(!under("/object", &["/obj"]));
        assert!(under("/obj", &["/obj"]));
        assert!(!under("", &["/obj"]));
    }
}
