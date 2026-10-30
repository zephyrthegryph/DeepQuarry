//! Existing dx own-var matching policy, emitted as ephemeral callbacks.
//! This is a source-only generator projection, not another DM parser/model.
use crate::{
    pat,
    util::{py_lstrip, py_rstrip, py_strip},
};
pub fn visit(clean: &str, mut declare: impl FnMut(&str, &str)) {
    let mut current: Option<String> = None;
    let mut group_indent: Option<usize> = None;
    for line in clean.lines() {
        if let Some(m) =
            pat!(r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b")
                .captures(line)
        {
            declare(m.s(1), m.s(2));
            current = None;
            continue;
        }
        if let Some(h) = pat!(r"^(/[\w/]+)\s*$").captures(py_rstrip(line)) {
            current = Some(h.s(1).to_string());
            group_indent = None;
            continue;
        }
        // SYSTEM_DEF(x) declares /datum/system/x through a macro: its indented body is that type's block.
        if let Some(h) = pat!(r"^SYSTEM_DEF\((\w+)\)\s*$").captures(py_rstrip(line)) {
            current = Some(format!("/datum/system/{}", h.s(1)));
            group_indent = None;
            continue;
        }
        if !line.is_empty() && !line.starts_with([' ', '\t']) {
            current = None;
            continue;
        }
        let Some(cur) = &current else { continue };
        if let Some(gi) = group_indent {
            let indent = line.len() - py_lstrip(line).len();
            if !py_strip(line).is_empty() && indent > gi {
                let t = py_strip(line);
                let last = if !line.contains('=') {
                    t.rsplit('/').next().unwrap_or("")
                } else {
                    py_strip(line.split('=').next().unwrap_or(""))
                        .rsplit('/')
                        .next()
                        .unwrap_or("")
                };
                if let Some(name) = pat!(r"\A[A-Za-z_]\w*").find(last) {
                    declare(cur, name.as_str());
                }
                continue;
            }
            group_indent = None;
        }
        if let Some(g) = pat!(r"^(\s+)var\s*$").captures(line) {
            group_indent = Some(g.s(1).len());
            continue;
        }
        if let Some(v) = pat!(r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)").captures(line) {
            declare(cur, v.s(1));
        }
    }
}
