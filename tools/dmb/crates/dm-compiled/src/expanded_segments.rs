//! Immutable expansion pieces consumed directly by the production frontend.
//! An edited generation shares untouched pieces and per-piece line indexes.
use dm_preprocess::PreprocessedProject;
use dm_syntax::{Span, TokenKind};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, path::PathBuf, sync::Arc};

#[derive(Clone, Debug)]
pub struct ExpandedSegment {
    pub text: Arc<str>,
    pub content_len: usize,
    pub blob: Option<Arc<PathBuf>>,
    pub non_boundaries: Arc<[usize]>,
    pub digest: [u8; 32],
    pub lines: Arc<[usize]>,
}
#[derive(Clone, Debug, Default)]
pub struct SegmentedExpansion {
    pub segments: Vec<Arc<ExpandedSegment>>,
    pub bytes: usize,
}
impl SegmentedExpansion {
    pub fn from_pieces(pieces: Vec<Arc<str>>) -> Self {
        let bytes = pieces.iter().map(|piece| piece.len()).sum();
        Self { segments: pieces.into_iter().map(|text| {
            let digest = Sha256::digest(text.as_bytes()).into();
            let lines = text.match_indices('\n').map(|(at, _)| at+1).collect::<Vec<_>>().into();
            Arc::new(ExpandedSegment { content_len:text.len(),non_boundaries:utf8_boundaries(&text),blob:None,text,digest,lines })
        }).collect(), bytes }
    }
    pub fn source(&self) -> dm_syntax::SegmentedSource {
        dm_syntax::SegmentedSource::with_backings(self.segments.iter().map(|piece| (Arc::clone(&piece.text),piece.content_len,Arc::clone(&piece.lines),Arc::clone(&piece.non_boundaries),piece.blob.clone(),piece.digest)))
    }
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
    pub fn materialize(&self) -> Result<String,String> {
        let mut text=String::with_capacity(self.bytes);
        self.source().visit_pieces(|piece|text.push_str(piece))?;
        Ok(text)
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
        let bytes = output.iter().map(|piece| piece.content_len).sum();
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
            let next = position + piece.content_len;
            if position >= end {
                break;
            }
            if next > start {
                let a = start.saturating_sub(position);
                let b = end.min(next) - position;
                if a == 0 && b == piece.content_len {
                    output.push(Arc::clone(piece));
                } else if a < b {
                    let text=piece.content().ok()?;output.push(segment(text.get(a..b)?));
                }
            }
            position = next;
        }
        Some(())
    }
}
fn utf8_boundaries(text:&str)->Arc<[usize]> {text.bytes().enumerate().filter_map(|(at,byte)|((byte&0xc0)==0x80).then_some(at)).collect::<Vec<_>>().into()}
impl ExpandedSegment {
    pub fn content(&self)->std::io::Result<Arc<str>> {
        if self.text.len()==self.content_len {return Ok(Arc::clone(&self.text));}
        let blob=self.blob.as_ref().ok_or_else(||std::io::Error::other("expanded source has no backing"))?;
        use std::io::Read;let mut bytes=Vec::new();
        std::fs::File::open(blob.as_ref())?.take(self.content_len as u64+1).read_to_end(&mut bytes)?;
        if bytes.len()!=self.content_len || <[u8;32]>::from(Sha256::digest(&bytes))!=self.digest {return Err(std::io::Error::other("invalid expanded source artifact"));}
        String::from_utf8(bytes).map(Arc::from).map_err(std::io::Error::other)
    }
}
impl SegmentedExpansion {
    /// Hash overlapping include intervals in a single verified chunk traversal.
    /// Each active hasher sees exactly its original flat byte stream. Decoded
    /// chunks live only for this iteration, never in a process-wide memo.
    fn digest_ranges(&self, ranges: &[(usize, Span)]) -> Option<Vec<(usize, [u8; 32])>> {
        let mut events = BTreeMap::<usize, (Vec<usize>, Vec<usize>)>::new();
        let mut result = Vec::with_capacity(ranges.len());
        for &(id, span) in ranges {
            if span.start > span.end || span.end > self.bytes { return None; }
            if span.start == span.end {
                result.push((id, Sha256::digest([]).into()));
            } else {
                events.entry(span.start).or_default().0.push(id);
                events.entry(span.end).or_default().1.push(id);
            }
        }
        let mut events = events.into_iter().peekable();
        let mut active = BTreeMap::<usize, Sha256>::new();
        let mut offset = 0;
        for piece in &self.segments {
            let end = offset + piece.content_len;
            // Only load a chunk when an active interval or a start inside it
            // requires bytes. Metadata-only gaps do not touch the CAS.
            let needed = !active.is_empty() || events.peek().is_some_and(|(at, _)| *at < end);
            let text = if needed { Some(piece.content().ok()?) } else { None };
            let mut cursor = offset;
            while let Some((at, _)) = events.peek() {
                if *at > end { break; }
                let (at, (starts, finishes)) = events.next()?;
                if at < cursor { return None; }
                if !active.is_empty() && at > cursor {
                    let bytes = text.as_ref()?.as_bytes().get(cursor-offset..at-offset)?;
                    for hash in active.values_mut() { hash.update(bytes); }
                }
                for id in finishes { result.push((id, active.remove(&id)?.finalize().into())); }
                for id in starts { active.insert(id, Sha256::new()); }
                cursor = at;
            }
            if !active.is_empty() && cursor < end {
                let bytes = text.as_ref()?.as_bytes().get(cursor-offset..)?;
                for hash in active.values_mut() { hash.update(bytes); }
            }
            offset = end;
            if events.peek().is_none() && active.is_empty() { break; }
        }
        if events.peek().is_some() || !active.is_empty() { return None; }
        Some(result)
    }
    pub(crate) fn attach_backings(&mut self,root:&std::path::Path) {
        for piece in &mut self.segments {
            if piece.blob.is_some() {continue;}
            let piece=Arc::make_mut(piece);let digest=piece.digest.iter().map(|byte|format!("{byte:02x}")).collect::<String>();
            piece.blob=Some(Arc::new(root.join("prepared-input-chunk-v2").join(&digest[..2]).join(digest)));
        }
    }
    pub(crate) fn evict_payloads(&mut self) {
        for piece in &mut self.segments {if piece.blob.is_some() {Arc::make_mut(piece).text=Arc::from("");}}
    }
}
fn segment(text: &str) -> Arc<ExpandedSegment> {
    Arc::new(ExpandedSegment {
        text: Arc::from(text),content_len:text.len(),blob:None,non_boundaries:utf8_boundaries(text),
        digest: Sha256::digest(text.as_bytes()).into(),
        lines: text.match_indices('\n').map(|(at, _)| at+1).collect::<Vec<_>>().into(),
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
    let source = pieces.source();
    let offsets = source.line_starts();
    let mut replacements = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for origin in previous.origin_iter() {
        let key = (origin.path.as_ref().clone(), origin.source_line);
        let Some((before, after)) = lines.get(&key) else {
            continue;
        };
        let start = *offsets.get(origin.output_line.checked_sub(1)?)?;
        let end = offsets
            .get(origin.output_line)
            .copied()
            .unwrap_or(pieces.bytes);
        if source.slice(Span::new(start, end))?.as_ref() != before {
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
        text: String::new(),
        units: previous.units.clone(),
        unit_digests: previous.unit_digests.clone(),
        origins: previous.origins.clone(),
        origin_map: previous.origin_map.clone(),
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
    let mut changed_hashes = Vec::new();
    for (index, unit) in project.units.iter_mut().enumerate() {
        let old = unit.output_span;
        unit.output_span = Span::new(translate(old.start)?, translate(old.end)?);
        if replacements
            .iter()
            .any(|(span, _)| span.start < old.end && span.end > old.start)
        {
            changed_hashes.push((index, unit.output_span));
        }
    }
    for (index, digest) in pieces.digest_ranges(&changed_hashes)? {
        *project.unit_digests.get_mut(index)? = digest;
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
    let old_source = pieces.source();
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
            if pieces.source().slice(unit.output_span)?.as_ref() != before {
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
        text: String::new(),
        units: previous.units.clone(),
        unit_digests: previous.unit_digests.clone(),
        origins: Vec::new(),
        origin_map: None,
        dependencies: previous.dependencies.clone(),
        map_includes: previous.map_includes.clone(),
        skin_includes: previous.skin_includes.clone(),
        file_dirs: previous.file_dirs.clone(),
        diagnostics: previous.diagnostics.clone(),
        final_macros: previous.final_macros.clone(),
    };
    // Origins before the edit use the previous generation's shared line table.
    let offsets = old_source.line_starts();
    let mut origin_index = 0;
    let mut line_delta: i64 = 0;
    for (span, text, path) in &replacements {
        while let Some(origin) = previous.origin_get(origin_index) {
            let offset = *offsets.get(origin.output_line.checked_sub(1)?)?;
            if offset >= span.start {
                break;
            }
            let mut origin = origin.clone();
            origin.output_line = usize::try_from(origin.output_line as i64 + line_delta).ok()?;
            project.origins.push(origin);
            origin_index += 1;
        }
        let first_line = previous.origin_get(origin_index)?.output_line;
        let mut old_count = 0;
        while let Some(origin) = previous.origin_get(origin_index) {
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
    for origin in previous.origin_iter().skip(origin_index) {
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
    let mut changed_hashes = Vec::new();
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
            changed_hashes.push((index, unit.output_span));
        }
    }
    for (index, digest) in pieces.digest_ranges(&changed_hashes)? {
        *project.unit_digests.get_mut(index)? = digest;
    }
    Some((project, pieces))
}
