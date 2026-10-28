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
    normalize_dots(&p.to_string_lossy().replace('\\', "/"))
}

/// Folds `.` and `..` segments lexically: a file reached through a relative `#include "../../x/y.dm"` is the tree's `code/x/y.dm`, the path
/// every lint and the semantic model key it by (a path left as `code/modules/unit_tests/../../tests/y.dm` matches no tree file).
pub fn normalize_dots(path: &str) -> String {
    if !path.contains("/.") {
        return path.to_string();
    }
    let mut out: Vec<&str> = Vec::new();
    for seg in path.split('/') {
        match seg {
            "." => {}
            ".." if out.last().is_some_and(|l| *l != "..") => {
                out.pop();
            }
            _ => out.push(seg),
        }
    }
    out.join("/")
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

/// CPU time this process has used so far, in milliseconds (for the traces; 0 where unknown).
pub fn cpu_ms() -> u64 {
    #[cfg(windows)]
    {
        #[repr(C)]
        struct FileTime {
            lo: u32,
            hi: u32,
        }
        extern "system" {
            fn GetCurrentProcess() -> isize;
            fn GetProcessTimes(p: isize, c: *mut FileTime, e: *mut FileTime, k: *mut FileTime, u: *mut FileTime) -> i32;
        }
        let z = || FileTime { lo: 0, hi: 0 };
        let (mut c, mut e, mut k, mut u) = (z(), z(), z(), z());
        // SAFETY: plain out-parameters of a documented kernel32 call on the current process.
        let ok = unsafe { GetProcessTimes(GetCurrentProcess(), &mut c, &mut e, &mut k, &mut u) };
        if ok == 0 {
            return 0;
        }
        let t = |f: &FileTime| ((f.hi as u64) << 32 | f.lo as u64) / 10_000;
        t(&k) + t(&u)
    }
    #[cfg(not(windows))]
    {
        0
    }
}

/// CPU time of the calling thread so far, in milliseconds (0 where unknown).
pub fn thread_cpu_ms() -> u64 {
    #[cfg(windows)]
    {
        #[repr(C)]
        struct FileTime {
            lo: u32,
            hi: u32,
        }
        extern "system" {
            fn GetCurrentThread() -> isize;
            fn GetThreadTimes(t: isize, c: *mut FileTime, e: *mut FileTime, k: *mut FileTime, u: *mut FileTime) -> i32;
        }
        let z = || FileTime { lo: 0, hi: 0 };
        let (mut c, mut e, mut k, mut u) = (z(), z(), z(), z());
        // SAFETY: plain out-parameters of a documented kernel32 call on the current thread.
        let ok = unsafe { GetThreadTimes(GetCurrentThread(), &mut c, &mut e, &mut k, &mut u) };
        if ok == 0 {
            return 0;
        }
        let t = |f: &FileTime| ((f.hi as u64) << 32 | f.lo as u64) / 10_000;
        t(&k) + t(&u)
    }
    #[cfg(not(windows))]
    {
        0
    }
}

static CPU_ACCOUNT: std::sync::Mutex<std::collections::BTreeMap<String, u64>> = std::sync::Mutex::new(std::collections::BTreeMap::new());

/// Whether `DQ_CPU_ACCOUNT` is set: worker threads add their CPU time to a table printed at exit.
pub fn cpu_accounting() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("DQ_CPU_ACCOUNT").is_some())
}

pub fn cpu_account(tag: String, ms: u64) {
    *CPU_ACCOUNT.lock().unwrap().entry(tag).or_default() += ms;
}

pub fn cpu_account_report() {
    if !cpu_accounting() {
        return;
    }
    let mut v: Vec<(String, u64)> = CPU_ACCOUNT.lock().unwrap().iter().map(|(k, v)| (k.clone(), *v)).collect();
    v.sort_by(|a, b| b.1.cmp(&a.1));
    eprintln!("CPU total {} ms (main thread {} ms)", cpu_ms(), thread_cpu_ms());
    for (k, ms) in v.iter().take(30) {
        eprintln!("CPU {:>6} ms {}", ms, k);
    }
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

#[cfg(test)]
mod normalize_dots_tests {
    use super::normalize_dots;

    #[test]
    fn folds_relative_include_paths() {
        assert_eq!(normalize_dots("code/modules/unit_tests/../../tests/unit_tests/x.dm"), "code/tests/unit_tests/x.dm");
        assert_eq!(normalize_dots("code/a/./b.dm"), "code/a/b.dm");
        assert_eq!(normalize_dots("code/a/b.dm"), "code/a/b.dm");
        assert_eq!(normalize_dots("../x.dm"), "../x.dm");
    }
}
