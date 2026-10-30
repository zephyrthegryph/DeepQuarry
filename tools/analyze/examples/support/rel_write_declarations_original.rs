//! Oracle-only frozen original relation index projection; never host dependency.
use dq_analyze::tree::{Tree, CODE_DM};
use std::collections::HashMap;
pub fn declarations(tree: &Tree) -> HashMap<String, Vec<String>> {
    let files = tree.select(&CODE_DM);
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    let own = regex::Regex::new(
        r"\b(?:owns_one|owns_many|ref_one|ref_many|hud_element|profile)\(\s*nameof\((\w+)\)",
    )
    .unwrap();
    let link = regex::Regex::new(r"\blinks?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)").unwrap();
    for f in &files {
        let stripped = dq_analyze::raw_marker_policy::strip_comments_keep_strings(f.text());
        let mut offset = 0;
        for line in stripped.split('\n') {
            let t = line.trim_start();
            if t.starts_with('#') || t.is_empty() {
                offset += line.len() + 1;
                continue;
            }
            if let Some(m)=dq_analyze::pat_match!(r"(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(t){out.entry(m.s(2).to_owned()).or_default().push(m.s(1).to_owned());}
            if let Some(m) = statement_marker(&stripped, offset, line, &["CAPABILITIES"]) {
                let end = if line.len() == t.len() {
                    block_extent(&stripped, m.close)
                } else {
                    None
                };
                let body = match end {
                    Some(end) => block_body(&stripped, m.open + 1, m.close, end),
                    None => stripped[m.open + 1..m.close].to_owned(),
                };
                let args = dq_analyze::raw_marker_policy::split_args(&body);
                if let Some(ty) = args.first() {
                    for c in own.captures_iter(&body) {
                        out.entry(c[1].to_owned()).or_default().push(ty.clone());
                    }
                    for c in link.captures_iter(&body) {
                        out.entry(c[2].to_owned())
                            .or_default()
                            .push(c[1].to_owned());
                        out.entry(c[4].to_owned())
                            .or_default()
                            .push(c[3].to_owned());
                    }
                }
            }
            offset += line.len() + 1;
        }
    }
    // Frozen original declaration-only projection of ownership_index::file_events
    // plus Index's path-order final overwrite, independent of the shared visitor.
    let mut legacy = std::collections::BTreeMap::new();
    for f in &files {
        let raw_lines = f.text().lines().collect::<Vec<_>>();
        let mut declaring: Option<String> = None;
        for (no, line) in f.code().lines().enumerate() {
            let first = line.chars().next();
            if matches!(first, Some('"') | Some('\'')) {
                continue;
            }
            if declaring.is_some() && first.map(dq_analyze::util::is_py_space).unwrap_or(false) {
                if let Some(m)=dq_analyze::pat_match!(r"^\s+\.\s*\+=\s*(owns|shares|proto|rel_one|rel_many)\(\s*nameof\((\w+)\)\s*(?:,\s*(.*?))?\)\s*(?://.*)?$").captures(raw_lines.get(no).copied().unwrap_or("")){
         let func=m.s(1);let opts=m.s(3);
         let private=dq_analyze::pat!(r"\bpolicy\s*=\s*OWN_PRIVATE_COPY\b").is_match(opts);
         let annotate=func=="owns"&&!private&&!opts.contains("policy_proc")&&!opts.contains("if_var")&&dq_analyze::pat!(r"\bpolicy\s*=\s*OWN_NONE\b").is_match(opts);
         legacy.insert((declaring.clone().unwrap(),m.s(2).to_owned()),annotate);
        }
                continue;
            }
            declaring = None;
            if first
                .map(|c| !dq_analyze::util::is_py_space(c))
                .unwrap_or(false)
            {
                if let Some(m) =
                    dq_analyze::pat_match!(r"^(/[\w/]+)/(?:ownership|relations)\(\)").captures(line)
                {
                    declaring = Some(m.s(1).to_owned());
                }
            }
        }
    }
    for ((owner, var), annotate) in legacy {
        if !annotate {
            out.entry(var).or_default().push(owner)
        }
    }
    out
}

pub fn block_extent(text: &str, close: usize) -> Option<usize> {
    let rest = &text[close + 1..];
    let eol = rest.find('\n').unwrap_or(rest.len());
    if !rest[..eol].trim().is_empty() {
        return None;
    }
    let mut pos = close + 1 + eol;
    let mut end: Option<usize> = None;
    while pos < text.len() {
        // `pos` is at a newline; the next line starts after it.
        let ls = pos + 1;
        if ls > text.len() {
            break;
        }
        let le = text[ls..].find('\n').map(|i| ls + i).unwrap_or(text.len());
        let line = &text[ls..le];
        if line.trim().is_empty() {
            pos = le;
            continue;
        }
        if !line.starts_with(|c: char| c.is_whitespace()) {
            break;
        }
        end = Some(ls + line.trim_end().len());
        pos = le;
    }
    end
}

/// The marker body of a block: `text[from..end]` with the header's `)` and each top-level entry-ending newline replaced by a comma
/// (same length, so offsets and lines are unchanged). The engine then reads one argument list in either form.
pub fn block_body(text: &str, from: usize, close: usize, end: usize) -> String {
    let b = text.as_bytes();
    let mut out: Vec<u8> = b[from..end].to_vec();
    out[close - from] = b',';
    let mut depth = 0i32;
    let mut in_str = false;
    let mut pending: Option<usize> = None; // the last depth-0 newline since the previous entry's text
    let mut seen_entry = false;
    let mut i = close + 1;
    while i < end {
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 1;
            } else if c == b'"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if depth == 0 && !c.is_ascii_whitespace() {
            // An entry starts here: the newline before it ended the previous one.
            if let Some(nl) = pending.take() {
                if seen_entry {
                    out[nl - from] = b',';
                }
            }
            seen_entry = true;
        }
        match c {
            b'"' => in_str = true,
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth -= 1,
            b'\n' if depth == 0 => pending = Some(i),
            _ => {}
        }
        i += 1;
    }
    String::from_utf8(out).unwrap_or_default()
}

// Frozen ORIGINAL marker and parenthesis helpers for the oracle only.
// Never call the native policy matcher to validate that same matcher.
fn matching_paren(s: &str, open: usize) -> Option<usize> {
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

struct StatementMarker<'a> {
    pub name: &'a str,
    pub open: usize,
    pub close: usize,
}
fn statement_marker<'a>(
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
