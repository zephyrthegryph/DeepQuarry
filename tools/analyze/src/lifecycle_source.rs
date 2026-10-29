//! Shared source indentation rules; no semantic tree, parser or filesystem access.
fn indent(line: &str) -> Option<usize> {
    let line = line.trim_end_matches('\r');
    let t = line.trim_start_matches([' ', '\t']);
    if t.is_empty() || t.starts_with("//") {
        return None;
    }
    Some(line.len() - t.len())
}

/// The 1-based body lines of the definition whose header is line `header` of `lines`: every following line until the first
/// non-blank, non-comment line indented no deeper than the header (the next definition, or the end of the block).
pub fn body_lines(lines: &[&str], header: u32) -> std::ops::Range<usize> {
    let h = header as usize;
    if h == 0 || h > lines.len() {
        return h..h;
    }
    let base = indent(lines[h - 1]).unwrap_or(0);
    let mut end = h + 1;
    while end <= lines.len() {
        if let Some(i) = indent(lines[end - 1]) {
            if i <= base {
                break;
            }
        }
        end += 1;
    }
    (h + 1)..end
}
