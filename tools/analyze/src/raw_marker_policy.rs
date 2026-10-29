//! Existing raw marker policy over one retained source view; no Decls model.
pub fn strip_comments_keep_strings(text: &str) -> String {
    let b = text.as_bytes();
    let mut out = b.to_vec();
    let mut i = 0;
    let n = b.len();
    while i < n {
        match b[i] {
            b'"' => {
                // A string: skip to the closing quote ("\\" escapes; `[ ]` interpolation is left alone).
                i += 1;
                while i < n && b[i] != b'"' && b[i] != b'\n' {
                    if b[i] == b'\\' && i + 1 < n {
                        i += 1;
                    }
                    i += 1;
                }
                i += 1;
            }
            b'\'' => {
                i += 1;
                while i < n && b[i] != b'\'' && b[i] != b'\n' {
                    i += 1;
                }
                i += 1;
            }
            b'/' if i + 1 < n && b[i + 1] == b'/' => {
                while i < n && b[i] != b'\n' {
                    out[i] = b' ';
                    i += 1;
                }
            }
            b'/' if i + 1 < n && b[i + 1] == b'*' => {
                let mut depth = 0;
                while i < n {
                    if i + 1 < n && b[i] == b'/' && b[i + 1] == b'*' {
                        depth += 1;
                        out[i] = b' ';
                        out[i + 1] = b' ';
                        i += 2;
                    } else if i + 1 < n && b[i] == b'*' && b[i + 1] == b'/' {
                        depth -= 1;
                        out[i] = b' ';
                        out[i + 1] = b' ';
                        i += 2;
                        if depth == 0 {
                            break;
                        }
                    } else {
                        if b[i] != b'\n' {
                            out[i] = b' ';
                        }
                        i += 1;
                    }
                }
            }
            _ => i += 1,
        }
    }
    String::from_utf8(out).unwrap_or_default()
}

pub fn split_args(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    let mut in_str = false;
    let mut prev = '\0';
    for c in s.chars() {
        if in_str {
            cur.push(c);
            if c == '"' && prev != '\\' {
                in_str = false;
            }
            prev = c;
            continue;
        }
        match c {
            '"' => {
                in_str = true;
                cur.push(c);
            }
            '(' | '[' | '{' => {
                depth += 1;
                cur.push(c);
            }
            ')' | ']' | '}' => {
                depth -= 1;
                cur.push(c);
            }
            ',' if depth == 0 => {
                out.push(cur.trim().to_string());
                cur.clear();
            }
            _ => cur.push(c),
        }
        prev = c;
    }
    let last = cur.trim().to_string();
    if !last.is_empty() || !out.is_empty() {
        out.push(last);
    }
    out
}

pub fn matching_paren(s: &str, open: usize) -> Option<usize> {
    let b = s.as_bytes();
    let mut depth = 0i32;
    let mut in_str = false;
    let mut i = open;
    while i < b.len() {
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                in_str = false;
            }
        } else {
            match c {
                b'"' => in_str = true,
                b'(' => depth += 1,
                b')' => {
                    depth -= 1;
                    if depth == 0 {
                        return Some(i);
                    }
                }
                _ => {}
            }
        }
        i += 1;
    }
    None
}

pub(crate) struct StatementMarker<'a> {
    pub name: &'a str,
    pub open: usize,
    pub close: usize,
}
pub(crate) fn statement_marker<'a>(
    text: &str,
    line_offset: usize,
    line: &'a str,
    names: &[&str],
) -> Option<StatementMarker<'a>> {
    let t = line.trim_start();
    if t.starts_with('#') || t.is_empty() {
        return None;
    }
    let name_end = t
        .find(|c: char| !(c.is_alphanumeric() || c == '_'))
        .unwrap_or(t.len());
    let name = &t[..name_end];
    if !names.contains(&name) || !t[name_end..].trim_start().starts_with('(') {
        return None;
    }
    let open = line_offset + line.len() - t.len() + name_end + t[name_end..].find('(')?;
    Some(StatementMarker {
        name,
        open,
        close: matching_paren(text, open)?,
    })
}

/// Original strict UTF8 read_to_string include-order policy.
pub fn dme_include_order(text: &str) -> std::collections::HashMap<String, usize> {
    dme_include_order_view(text, false)
}
/// Acquisition may strip exactly the initial UTF8 BOM; do not copy a source
/// buffer to put it back. Old trim() leaves BOM, so only first line is skipped.
pub fn dme_include_order_view(
    text: &str,
    had_bom: bool,
) -> std::collections::HashMap<String, usize> {
    let mut out = std::collections::HashMap::new();
    for (index, line) in text.lines().enumerate() {
        if index == 0 && had_bom {
            continue;
        }
        let line = line.trim();
        let Some(rest) = line.strip_prefix("#include") else {
            continue;
        };
        let rest = rest.trim();
        let Some(path) = rest.strip_prefix('"').and_then(|r| r.split('"').next()) else {
            continue;
        };
        let rel = path.replace('\\', "/");
        let n = out.len();
        out.entry(rel).or_insert(n);
    }
    out
}
