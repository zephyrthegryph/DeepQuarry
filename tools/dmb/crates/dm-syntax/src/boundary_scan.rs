//! Resumable extraction of the existing joined-stream root boundary scanner.
//! Checkpoints are between scanner tokens, never arbitrary file boundaries.
use crate::quoted_end;
use std::ops::ControlFlow;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BoundaryCheckpoint {
    offset: usize,
    at_line_start: bool,
    indented: bool,
    delimiter_depth: usize,
}
impl Default for BoundaryCheckpoint {
    fn default() -> Self {
        Self {
            offset: 0,
            at_line_start: true,
            indented: false,
            delimiter_depth: 0,
        }
    }
}
impl BoundaryCheckpoint {
    pub fn offset(self) -> usize {
        self.offset
    }
    /// Bind an already authenticated unchanged prefix to current coordinates.
    /// This scanner API does not itself certify source or revision identity.
    pub fn at_offset(self, offset: usize) -> Self {
        Self { offset, ..self }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BoundaryScanError {
    InvalidOffset,
}
/// Visit exactly the complete scanner's boundaries, starting between tokens.
/// A break leaves the boundary character unconsumed, so resumption is exact.
pub fn scan_top_level_boundaries<B>(
    source: &str,
    checkpoint: BoundaryCheckpoint,
    mut visit: impl FnMut(BoundaryCheckpoint) -> ControlFlow<B>,
) -> Result<ControlFlow<B>, BoundaryScanError> {
    if !source.is_char_boundary(checkpoint.offset) {
        return Err(BoundaryScanError::InvalidOffset);
    }
    let BoundaryCheckpoint {
        offset: mut pos,
        mut at_line_start,
        mut indented,
        mut delimiter_depth,
    } = checkpoint;
    while pos < source.len() {
        let rest = &source[pos..];
        let first = rest.as_bytes()[0];
        if first == b'/' && rest.starts_with("//") {
            pos += rest.find('\n').unwrap_or(rest.len());
            continue;
        }
        if first == b'/' && rest.starts_with("/*") {
            let mut depth = 1usize;
            let mut cursor = 2usize;
            while depth > 0 && cursor + 1 < rest.len() {
                if rest[cursor..].starts_with("/*") {
                    depth += 1;
                    cursor += 2;
                } else if rest[cursor..].starts_with("*/") {
                    depth -= 1;
                    cursor += 2;
                } else {
                    cursor += rest[cursor..].chars().next().unwrap().len_utf8();
                }
            }
            let end = if depth == 0 { cursor } else { rest.len() };
            (at_line_start, indented) =
                after_token_line_start(&rest[..end], at_line_start, indented, true);
            pos += end;
            continue;
        }
        let string = if first == b'@' && rest.starts_with("@{\"") {
            quoted_end(&rest[1..], true, true).map(|end| end + 1)
        } else if first == b'{' && rest.starts_with("{\"") {
            quoted_end(rest, true, false)
        } else if first == b'@' && rest.starts_with("@\"") {
            quoted_end(&rest[1..], false, true).map(|end| end + 1)
        } else if first == b'"' {
            quoted_end(rest, false, false)
        } else {
            None
        };
        if let Some(end) = string {
            (at_line_start, indented) =
                after_token_line_start(&rest[..end], at_line_start, indented, false);
            pos += end;
            continue;
        }
        if first == b'\'' {
            let mut escaped = false;
            let mut end = rest.len();
            for (at, ch) in rest.char_indices().skip(1) {
                if escaped {
                    escaped = false;
                } else if ch == '\\' {
                    escaped = true;
                } else if ch == '\'' {
                    end = at + 1;
                    break;
                }
            }
            (at_line_start, indented) =
                after_token_line_start(&rest[..end], at_line_start, indented, false);
            pos += end;
            continue;
        }
        let ch = if first.is_ascii() {
            char::from(first)
        } else {
            rest.chars().next().unwrap()
        };
        if ch == '\n' {
            at_line_start = true;
            indented = false;
        } else if matches!(ch, ' ' | '\t') && at_line_start {
            indented = true;
        } else if !matches!(ch, ' ' | '\t' | '\r') {
            // Expanded #include directives can leave spaces before the first
            // absolute declaration path of an included file.
            if at_line_start && delimiter_depth == 0 && (!indented || ch == '/') {
                let checkpoint = BoundaryCheckpoint {
                    offset: pos,
                    at_line_start,
                    indented,
                    delimiter_depth,
                };
                if let ControlFlow::Break(value) = visit(checkpoint) {
                    return Ok(ControlFlow::Break(value));
                }
            }
            at_line_start = false;
        }
        match ch {
            '(' | '[' | '{' => delimiter_depth += 1,
            ')' | ']' | '}' => delimiter_depth = delimiter_depth.saturating_sub(1),
            _ => {}
        }
        pos += ch.len_utf8();
    }
    Ok(ControlFlow::Continue(()))
}

pub(crate) fn after_token_line_start(
    token: &str,
    previous: bool,
    previously_indented: bool,
    trivia: bool,
) -> (bool, bool) {
    match token.rfind('\n') {
        Some(at) => {
            let tail = &token[at + 1..];
            (
                tail.bytes()
                    .all(|byte| matches!(byte, b' ' | b'\t' | b'\r')),
                tail.bytes().any(|byte| matches!(byte, b' ' | b'\t')),
            )
        }
        None if trivia => (previous, previously_indented),
        None => (false, previously_indented),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn checkpoints(source: &str) -> Vec<BoundaryCheckpoint> {
        let mut all = Vec::new();
        let _ = scan_top_level_boundaries::<()>(source, BoundaryCheckpoint::default(), |state| {
            all.push(state);
            ControlFlow::Continue(())
        })
        .unwrap();
        all
    }
    #[test]
    fn every_issued_checkpoint_replays_joined_cross_include_suffix() {
        let source = concat!(
            "/datum/base\n",
            "    var/count=1\n",
            "    proc/read()\n        return 1\n",
            "/* nested /* comment */ /proc/nope() */\n",
            "/proc/next()\n    return list(1,\n        2)\n",
            "/proc/final()\n    return 3\n"
        );
        let all = checkpoints(source);
        assert_eq!(
            all.iter().map(|state| state.offset()).collect::<Vec<_>>(),
            [
                0,
                source.find("/proc/next()").unwrap(),
                source.find("/proc/final()").unwrap()
            ]
        );
        for (index, start) in all.iter().copied().enumerate() {
            let mut suffix = Vec::new();
            let _ = scan_top_level_boundaries::<()>(source, start, |state| {
                suffix.push(state);
                ControlFlow::Continue(())
            })
            .unwrap();
            assert_eq!(suffix, all[index..]);
        }
    }
    #[test]
    fn procedure_edit_rebinds_unchanged_suffix_without_scanning_prefix() {
        let before = "/proc/a()\n    return 1\n/proc/b()\n    return 2\n/proc/c()\n    return 3\n";
        let after = before.replace("return 2", "return list(2,3,4,5)");
        let old = checkpoints(before);
        let new = checkpoints(&after);
        let rebound = old[2].at_offset(after.find("/proc/c()").unwrap());
        assert_eq!(rebound, new[2]);
        let mut suffix = Vec::new();
        let _ = scan_top_level_boundaries::<()>(&after, rebound, |state| {
            suffix.push(state);
            ControlFlow::Continue(())
        })
        .unwrap();
        assert_eq!(suffix, new[2..]);
        let mut visited = 0;
        let result = scan_top_level_boundaries(before, old[1], |state| {
            visited += 1;
            ControlFlow::Break(state)
        })
        .unwrap();
        assert_eq!(result, ControlFlow::Break(old[1]));
        assert_eq!(visited, 1);
    }
    #[test]
    fn comments_literals_and_delimiters_never_split_checkpoints() {
        let source = concat!(
            "/proc/a()\n",
            "    var/x={\"first\n/proc/string()\nlast\"}\n",
            "    var/y=@\"raw /proc/raw()\"\n",
            "    var/z='icons/test.dmi'\n",
            "    /* block\n/proc/comment()\n*/ return 1\n",
            "/proc/b()\n    return 2\n"
        );
        assert_eq!(
            checkpoints(source)
                .iter()
                .map(|state| state.offset())
                .collect::<Vec<_>>(),
            [0, source.find("/proc/b()").unwrap()]
        );
        assert_eq!(
            scan_top_level_boundaries::<()>(
                "\u{3b1}",
                BoundaryCheckpoint::default().at_offset(1),
                |_| ControlFlow::Continue(())
            ),
            Err(BoundaryScanError::InvalidOffset)
        );
    }
}
