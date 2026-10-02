//! Immutable expansion pieces. An edited generation shares untouched pieces;
//! the current parser bridge materializes one contiguous view when requested.
use dm_preprocess::PreprocessedProject;
use dm_syntax::{Span, TokenKind};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, path::PathBuf, sync::Arc};

#[derive(Clone, Debug)]
pub struct ExpandedSegment {
    pub text: Arc<str>,
    pub digest: [u8; 32],
}
#[derive(Clone, Debug, Default)]
pub struct SegmentedExpansion {
    pub segments: Vec<Arc<ExpandedSegment>>,
    pub bytes: usize,
}
impl SegmentedExpansion {
    pub fn from_text(text: &str) -> Self {
        let mut segments = Vec::new();
        let mut start = 0;
        for (offset, byte) in text.bytes().enumerate() {
            if byte == b'\n' && offset + 1 - start >= 64 * 1024 {
                segments.push(segment(&text[start..offset + 1]));
                start = offset + 1;
            }
        }
        if start != text.len() {
            segments.push(segment(&text[start..]));
        }
        Self {
            segments,
            bytes: text.len(),
        }
    }
    pub fn materialize(&self) -> String {
        let mut text = String::with_capacity(self.bytes);
        for piece in &self.segments {
            text.push_str(&piece.text);
        }
        text
    }
    /// Non-overlapping replacements in the previous generation's coordinates.
    /// Whole untouched pieces retain both their allocation and content identity.
    fn splice(&self, replacements: &[(Span, String)]) -> Option<Self> {
        let mut output = Vec::new();
        let mut cursor = 0;
        for (span, replacement) in replacements {
            if span.start < cursor || span.end < span.start || span.end > self.bytes {
                return None;
            }
            self.append_range(cursor, span.start, &mut output)?;
            if !replacement.is_empty() {
                output.push(segment(replacement));
            }
            cursor = span.end;
        }
        self.append_range(cursor, self.bytes, &mut output)?;
        let bytes = output.iter().map(|piece| piece.text.len()).sum();
        Some(Self {
            segments: output,
            bytes,
        })
    }
    fn append_range(
        &self,
        start: usize,
        end: usize,
        output: &mut Vec<Arc<ExpandedSegment>>,
    ) -> Option<()> {
        let mut position = 0;
        for piece in &self.segments {
            let next = position + piece.text.len();
            if position >= end {
                break;
            }
            if next > start {
                let a = start.saturating_sub(position);
                let b = end.min(next) - position;
                if a == 0 && b == piece.text.len() {
                    output.push(Arc::clone(piece));
                } else if a < b {
                    output.push(segment(piece.text.get(a..b)?));
                }
            }
            position = next;
        }
        Some(())
    }
}
fn segment(text: &str) -> Arc<ExpandedSegment> {
    Arc::new(ExpandedSegment {
        text: Arc::from(text),
        digest: Sha256::digest(text.as_bytes()).into(),
    })
}

/// Directly splice dependency-proven preprocessing-neutral source edits.
/// The macro universe includes definitions that are later undefined, so a final
/// macro table alone can never bless a new identifier. Quoted/interpolated text,
/// directives, continuations and line-count changes retain ordered replay.
pub(crate) fn splice_source_edits(
    previous: &PreprocessedProject,
    pieces: &SegmentedExpansion,
    changed: &BTreeMap<PathBuf, (Arc<str>, Arc<str>)>,
    macro_names: &std::collections::BTreeSet<String>,
) -> Option<(PreprocessedProject, SegmentedExpansion)> {
    if changed.is_empty() || !previous.diagnostics.is_empty() {
        return None;
    }
    let mut lines = BTreeMap::new();
    for (path, (before, after)) in changed {
        let old: Vec<_> = before.split_inclusive('\n').collect();
        let new: Vec<_> = after.split_inclusive('\n').collect();
        if old.len() != new.len() {
            return splice_raw_units(previous, pieces, changed, macro_names);
        }
        for (index, (old, new)) in old.into_iter().zip(new).enumerate() {
            if old == new {
                continue;
            }
            let a = dm_syntax::lex_spans(old);
            let b = dm_syntax::lex_spans(new);
            if !a.diagnostics.is_empty() || !b.diagnostics.is_empty() {
                return None;
            }
            for (lexed, text) in [(&a, old), (&b, new)] {
                for token in &lexed.tokens {
                    if matches!(
                        token.kind,
                        TokenKind::String
                            | TokenKind::Resource
                            | TokenKind::Interpolation
                            | TokenKind::Comment
                            | TokenKind::Unknown
                    ) {
                        return None;
                    }
                    if token.kind == TokenKind::Ident && macro_names.contains(token.text(text)) {
                        return None;
                    }
                }
            }
            // This line may otherwise alter lexical state of following lines.
            let guarded = |text: &str| {
                text.chars().any(|c| {
                    c == '#' || c == char::from(92) || c == char::from(34) || c == char::from(39)
                })
            };
            if guarded(old) || guarded(new) {
                return None;
            }
            lines.insert((path.clone(), index + 1), (old.to_owned(), new.to_owned()));
        }
    }
    if lines.is_empty() {
        return None;
    }
    let offsets: Vec<_> = std::iter::once(0)
        .chain(
            previous
                .text
                .match_indices('\n')
                .map(|(offset, _)| offset + 1),
        )
        .collect();
    let mut replacements = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for origin in &previous.origins {
        let key = (origin.path.as_ref().clone(), origin.source_line);
        let Some((before, after)) = lines.get(&key) else {
            continue;
        };
        let start = *offsets.get(origin.output_line.checked_sub(1)?)?;
        let end = offsets
            .get(origin.output_line)
            .copied()
            .unwrap_or(previous.text.len());
        if previous.text.get(start..end)? != before {
            return None;
        }
        replacements.push((Span::new(start, end), after.clone()));
        seen.insert(key);
    }
    if seen.len() != lines.len() {
        return None;
    }
    replacements.sort_by_key(|(span, _)| span.start);
    if replacements
        .windows(2)
        .any(|pair| pair[0].0.end > pair[1].0.start)
    {
        return None;
    }
    let pieces = pieces.splice(&replacements)?;
    let mut project = PreprocessedProject {
        text: pieces.materialize(),
        units: previous.units.clone(),
        unit_digests: previous.unit_digests.clone(),
        origins: previous.origins.clone(),
        dependencies: previous.dependencies.clone(),
        map_includes: previous.map_includes.clone(),
        skin_includes: previous.skin_includes.clone(),
        file_dirs: previous.file_dirs.clone(),
        diagnostics: previous.diagnostics.clone(),
        final_macros: previous.final_macros.clone(),
    };
    let translate = |offset: usize| -> Option<usize> {
        let mut delta: i64 = 0;
        for (span, text) in &replacements {
            if span.end > offset {
                break;
            }
            delta = delta.checked_add(text.len() as i64 - (span.end - span.start) as i64)?;
        }
        usize::try_from((offset as i64).checked_add(delta)?).ok()
    };
    for (index, unit) in project.units.iter_mut().enumerate() {
        let old = unit.output_span;
        unit.output_span = Span::new(translate(old.start)?, translate(old.end)?);
        if replacements
            .iter()
            .any(|(span, _)| span.start < old.end && span.end > old.start)
        {
            *project.unit_digests.get_mut(index)? =
                Sha256::digest(project.text.get(unit.output_span.range())?.as_bytes()).into();
        }
    }
    Some((project, pieces))
}

/// Line-count and structural changes can bypass ordered expansion when an entire
/// authored leaf is macro-independent and its previous expansion was byte-exact.
fn splice_raw_units(
    previous: &PreprocessedProject,
    pieces: &SegmentedExpansion,
    changed: &BTreeMap<PathBuf, (Arc<str>, Arc<str>)>,
    macro_names: &std::collections::BTreeSet<String>,
) -> Option<(PreprocessedProject, SegmentedExpansion)> {
    let mut replacements = Vec::new();
    let mut matched = std::collections::BTreeSet::new();
    for (path, (before, after)) in changed {
        for text in [before.as_ref(), after.as_ref()] {
            if text.contains('#') || text.contains(char::from(92)) {
                return None;
            }
            let lexed = dm_syntax::lex_spans(text);
            if !lexed.diagnostics.is_empty()
                || lexed.tokens.iter().any(|token| {
                    matches!(
                        token.kind,
                        TokenKind::String
                            | TokenKind::Resource
                            | TokenKind::Interpolation
                            | TokenKind::Comment
                            | TokenKind::Unknown
                    ) || (token.kind == TokenKind::Ident && macro_names.contains(token.text(text)))
                })
            {
                return None;
            }
        }
        // Preprocessing always terminates an emitted source line with LF.
        let normalize = |text: &str| {
            let mut result = text.replace("\r\n", "\n");
            if !result.is_empty() && !result.ends_with('\n') {
                result.push('\n');
            }
            result
        };
        let before = normalize(before);
        let after = normalize(after);
        for unit in previous.units.iter().filter(|unit| &unit.path == path) {
            if previous.text.get(unit.output_span.range())? != before {
                return None;
            }
            replacements.push((unit.output_span, after.clone(), Arc::new(path.clone())));
            matched.insert(path.clone());
        }
    }
    if matched.len() != changed.len() || replacements.is_empty() {
        return None;
    }
    replacements.sort_by_key(|(span, _, _)| span.start);
    if replacements
        .windows(2)
        .any(|pair| pair[0].0.end > pair[1].0.start)
    {
        return None;
    }
    let edits: Vec<_> = replacements
        .iter()
        .map(|(span, text, _)| (*span, text.clone()))
        .collect();
    let pieces = pieces.splice(&edits)?;
    let mut project = PreprocessedProject {
        text: pieces.materialize(),
        units: previous.units.clone(),
        unit_digests: previous.unit_digests.clone(),
        origins: Vec::new(),
        dependencies: previous.dependencies.clone(),
        map_includes: previous.map_includes.clone(),
        skin_includes: previous.skin_includes.clone(),
        file_dirs: previous.file_dirs.clone(),
        diagnostics: previous.diagnostics.clone(),
        final_macros: previous.final_macros.clone(),
    };
    let offsets: Vec<_> = std::iter::once(0)
        .chain(
            previous
                .text
                .match_indices('\n')
                .map(|(offset, _)| offset + 1),
        )
        .collect();
    let mut origin_index = 0;
    let mut line_delta: i64 = 0;
    for (span, text, path) in &replacements {
        while let Some(origin) = previous.origins.get(origin_index) {
            let offset = *offsets.get(origin.output_line.checked_sub(1)?)?;
            if offset >= span.start {
                break;
            }
            let mut origin = origin.clone();
            origin.output_line = usize::try_from(origin.output_line as i64 + line_delta).ok()?;
            project.origins.push(origin);
            origin_index += 1;
        }
        let first_line = previous.origins.get(origin_index)?.output_line;
        let mut old_count = 0;
        while let Some(origin) = previous.origins.get(origin_index) {
            let offset = *offsets.get(origin.output_line.checked_sub(1)?)?;
            if offset >= span.end {
                break;
            }
            if origin.path.as_ref() != path.as_ref() {
                return None;
            }
            old_count += 1;
            origin_index += 1;
        }
        let mut new_count = 0;
        for (line, _) in text.split_inclusive('\n').enumerate() {
            project.origins.push(dm_preprocess::Origin {
                output_line: usize::try_from(first_line as i64 + line_delta).ok()? + line,
                path: Arc::clone(path),
                source_line: line + 1,
            });
            new_count += 1;
        }
        line_delta += new_count as i64 - old_count as i64;
    }
    for origin in &previous.origins[origin_index..] {
        let mut origin = origin.clone();
        origin.output_line = usize::try_from(origin.output_line as i64 + line_delta).ok()?;
        project.origins.push(origin);
    }
    let translate = |offset: usize| -> Option<usize> {
        let mut delta: i64 = 0;
        for (span, text, _) in &replacements {
            if span.end > offset {
                break;
            }
            delta += text.len() as i64 - (span.end - span.start) as i64;
        }
        usize::try_from(offset as i64 + delta).ok()
    };
    for (index, unit) in project.units.iter_mut().enumerate() {
        let old = unit.output_span;
        unit.output_span = Span::new(translate(old.start)?, translate(old.end)?);
        if let Some((_, text, _)) = replacements.iter().find(|(span, _, _)| *span == old) {
            unit.source_lines = text.split_inclusive('\n').count();
        }
        if replacements
            .iter()
            .any(|(span, _, _)| span.start < old.end && span.end > old.start)
        {
            *project.unit_digests.get_mut(index)? =
                Sha256::digest(project.text.get(unit.output_span.range())?.as_bytes()).into();
        }
    }
    Some((project, pieces))
}
