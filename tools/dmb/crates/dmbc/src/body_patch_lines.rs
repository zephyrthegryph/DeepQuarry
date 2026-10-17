//! Exact line maps for edits that move code without changing it: comment and blank lines, and
//! directive lines (a new `#define`), outside procedure bodies.
//!
//! The body patch (`crate::body_patch`) relowers bodies whose position changed and shifts every
//! debug line the retained output holds. A shift from a body that grew is derived from body line
//! counts alone; a shift from trivia between declarations is not. It is derived here from the old
//! and new text of the files that changed: the significant tokens outside every body must be the
//! same sequence in both, and the k-th token's old and new line give the map.
//!
//! Soundness: the map is built only from a token-for-token match of everything outside bodies
//! (indentation of each line's first token included), so a declaration, an initializer or any
//! other code can only have moved, never changed. A body's own text is covered by its digest. When
//! directive lines differ, the caller must already know the expanded text is unchanged (the
//! expanded-text skeleton hash is equal); otherwise directives are compared like any other token.
use dm_syntax::TokenKind;

/// One significant token: its line, kind, text, and the whitespace that led its line (empty unless
/// it is the first token on the line).
#[derive(Debug, Eq, PartialEq)]
struct Significant<'a> {
    line: u32,
    kind: TokenKind,
    text: &'a str,
    indent: &'a str,
}

/// Whether directive lines take part in the comparison.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Directives {
    /// Directive lines are skipped (the expanded text is known to be unchanged).
    Inert,
    /// Directive lines are compared token for token.
    Compared,
}

/// Inclusive source line ranges of bodies, sorted by start.
pub(crate) type Ranges = [(u32, u32)];

fn in_ranges(ranges: &Ranges, line: u32) -> bool {
    let at = ranges.partition_point(|&(start, _)| start <= line);
    at > 0 && line <= ranges[at - 1].1
}

fn significant<'a>(text: &'a str, ranges: &Ranges, directives: Directives) -> Vec<Significant<'a>> {
    let lexed = dm_syntax::lex_spans(text);
    let mut out = Vec::new();
    let mut line = 1u32;
    let mut line_start = true;
    let mut directive = false;
    let mut continued = false;
    let mut indent = "";
    for token in &lexed.tokens {
        let piece = token.text(text);
        match token.kind {
            TokenKind::Newline => {
                if !continued {
                    directive = false;
                }
                line_start = true;
                indent = "";
                line += 1;
                continue;
            }
            TokenKind::Whitespace => {
                if line_start {
                    indent = piece;
                }
                continue;
            }
            TokenKind::Comment => {
                line += piece.bytes().filter(|&byte| byte == b'\n').count() as u32;
                continue;
            }
            _ => {}
        }
        let first = line_start;
        if line_start {
            directive = directive || piece == "#";
            line_start = false;
        }
        continued = piece == "\\";
        let start_line = line;
        line += piece.bytes().filter(|&byte| byte == b'\n').count() as u32;
        if (directive && directives == Directives::Inert) || in_ranges(ranges, start_line) {
            continue;
        }
        out.push(Significant {
            line: start_line,
            kind: token.kind,
            text: piece,
            indent: if first { indent } else { "" },
        });
    }
    out
}

/// `(old line, new line)` for the first token of every line outside the bodies, or why the two
/// texts differ by more than moved code.
pub(crate) fn gap_pairs(
    old: &str,
    old_bodies: &Ranges,
    new: &str,
    new_bodies: &Ranges,
    directives: Directives,
) -> Result<Vec<(u32, u32)>, String> {
    let old = significant(old, old_bodies, directives);
    let new = significant(new, new_bodies, directives);
    if old.len() != new.len() {
        return Err(format!(
            "{} tokens outside bodies became {}",
            old.len(),
            new.len()
        ));
    }
    let mut pairs: Vec<(u32, u32)> = Vec::new();
    for (old, new) in old.iter().zip(&new) {
        if old.kind != new.kind || old.text != new.text || old.indent != new.indent {
            return Err(format!(
                "code outside bodies changed at line {} ({:?} -> {:?})",
                old.line, old.text, new.text
            ));
        }
        if pairs.last().is_none_or(|&(line, _)| line != old.line) {
            pairs.push((old.line, new.line));
        }
    }
    Ok(pairs)
}

/// Piecewise-constant shift steps `(last line before the step, cumulative delta)` from sorted
/// `(old line, new line)` pairs; `None` when the pairs disagree about a line or reorder lines.
pub(crate) fn steps(mut pairs: Vec<(u32, u32)>) -> Option<Vec<(usize, isize)>> {
    pairs.sort();
    pairs.dedup();
    for window in pairs.windows(2) {
        if window[0].0 == window[1].0 || window[0].1 >= window[1].1 {
            return None;
        }
    }
    let mut steps = Vec::new();
    let mut delta = 0isize;
    for (old, new) in pairs {
        let now = new as isize - old as isize;
        if now != delta {
            steps.push((old as usize - 1, now));
            delta = now;
        }
    }
    Some(steps)
}

#[cfg(test)]
mod tests {
    use super::*;

    const OLD: &str = "/proc/a()\n\treturn 1\n\n/datum/x\n\tvar/v = 1\n/proc/b()\n\treturn 2\n";

    #[test]
    fn inserted_comment_and_blank_lines_shift_what_follows() {
        let new = "/proc/a()\n\treturn 1\n\n// note\n\n/datum/x\n\tvar/v = 1\n/proc/b()\n\treturn 2\n";
        // Bodies: a at 1..=2, b at 6..=7 (old); a at 1..=2, b at 8..=9 (new).
        let pairs = gap_pairs(OLD, &[(1, 2), (6, 7)], new, &[(1, 2), (8, 9)], Directives::Compared)
            .unwrap();
        assert_eq!(pairs, [(4, 6), (5, 7)]);
        let mut all = pairs;
        all.extend([(1, 1), (6, 8)]);
        let steps = steps(all).unwrap();
        assert_eq!(steps, vec![(3, 2)]);
    }

    #[test]
    fn a_new_directive_line_only_shifts_when_directives_are_inert() {
        let new = "/proc/a()\n\treturn 1\n\n#define X 1\n/datum/x\n\tvar/v = 1\n/proc/b()\n\treturn 2\n";
        let ranges_old = [(1, 2), (6, 7)];
        let ranges_new = [(1, 2), (7, 8)];
        assert!(gap_pairs(OLD, &ranges_old, new, &ranges_new, Directives::Compared).is_err());
        let pairs = gap_pairs(OLD, &ranges_old, new, &ranges_new, Directives::Inert).unwrap();
        assert_eq!(pairs, [(4, 5), (5, 6)]);
    }

    #[test]
    fn changed_code_outside_a_body_is_refused() {
        let new = OLD.replace("var/v = 1", "var/v = 2");
        let error = gap_pairs(OLD, &[(1, 2), (6, 7)], &new, &[(1, 2), (6, 7)], Directives::Inert)
            .unwrap_err();
        assert!(error.contains("changed at line 5"), "{error}");
    }

    #[test]
    fn indentation_changes_are_refused_and_body_edits_are_ignored() {
        let moved = OLD.replace("\tvar/v = 1", "\t\tvar/v = 1");
        assert!(gap_pairs(OLD, &[(1, 2), (6, 7)], &moved, &[(1, 2), (6, 7)], Directives::Inert).is_err());
        let edited = OLD.replace("return 2", "return 2 + 3 + 4");
        assert_eq!(
            gap_pairs(OLD, &[(1, 2), (6, 7)], &edited, &[(1, 2), (6, 7)], Directives::Inert).unwrap(),
            [(4, 4), (5, 5)]
        );
    }

    #[test]
    fn steps_reject_contradictions() {
        assert_eq!(steps(vec![(3, 3), (4, 4)]).unwrap(), Vec::<(usize, isize)>::new());
        assert!(steps(vec![(3, 4), (3, 5)]).is_none());
        assert!(steps(vec![(3, 6), (4, 5)]).is_none());
        assert_eq!(steps(vec![(3, 3), (9, 11)]).unwrap(), vec![(8, 2)]);
    }
}
