//! Shared expanded source with bounded contiguous views at parser boundaries.
use crate::{Span, ChunkReport};
use std::{borrow::Cow, sync::Arc, collections::HashMap, hash::{Hash, Hasher}};

#[derive(Default)]
pub struct SegmentedChunkSession {
    transitions: HashMap<(usize, u64, bool, usize, usize), PieceTransition>,
    bytes: usize,
    pub scanned_bytes: usize,
}
struct PieceTransition {
    // Weak identity does not pin previous source revisions. Carry equality and
    // an upgraded pointer check protect hash/address reuse from false hits.
    piece: std::sync::Weak<str>,
    carry: Arc<str>,
    boundary: usize,
    spans: Vec<Span>,
    skipped: Vec<Span>,
}
impl SegmentedChunkSession {
    pub fn resident_bytes(&self) -> usize { self.bytes }
    pub fn clear(&mut self) { self.transitions.clear(); self.bytes = 0; }
}

#[derive(Clone, Debug, Default)]
pub struct SegmentedSource {
    pieces: Arc<[Arc<str>]>,
    offsets: Arc<[usize]>,
    bytes: usize,
    lines: Arc<[Arc<[usize]>]>,
    preceding_lines: Arc<[usize]>,
}
impl SegmentedSource {
    pub fn new(pieces: impl IntoIterator<Item = Arc<str>>) -> Self {
        Self::with_lines(pieces.into_iter().map(|piece| {
            let lines: Arc<[usize]> = piece.match_indices('\n').map(|(at, _)| at+1).collect::<Vec<_>>().into();
            (piece, lines)
        }))
    }
    pub fn with_lines(pieces: impl IntoIterator<Item = (Arc<str>, Arc<[usize]>)>) -> Self {
        let (pieces, lines): (Vec<_>, Vec<_>) = pieces.into_iter().filter(|(piece, _)| !piece.is_empty()).unzip();
        let mut bytes = 0usize;
        let offsets: Vec<_> = pieces.iter().map(|piece| {
            let offset = bytes;
            bytes = bytes.checked_add(piece.len()).expect("expanded source exceeds address space");
            offset
        }).collect();
        let mut count = 0;
        let preceding_lines: Vec<_> = lines.iter().map(|lines| { let before = count; count += lines.len(); before }).collect();
        Self { pieces: pieces.into(), offsets: offsets.into(), bytes, lines: lines.into(), preceding_lines: preceding_lines.into() }
    }
    pub fn len(&self) -> usize { self.bytes }
    pub fn is_empty(&self) -> bool { self.bytes == 0 }
    pub fn is_char_boundary(&self, offset: usize) -> bool {
        if offset == self.bytes { return true; }
        if offset > self.bytes { return false; }
        self.offsets.partition_point(|at| *at <= offset).checked_sub(1)
            .is_some_and(|index| self.pieces[index].is_char_boundary(offset-self.offsets[index]))
    }
    pub fn pieces(&self) -> &[Arc<str>] { &self.pieces }
    pub fn piece_offsets(&self) -> &[usize] { &self.offsets }
    pub fn slice(&self, span: Span) -> Option<Cow<'_, str>> {
        if span.start > span.end || !self.is_char_boundary(span.start) || !self.is_char_boundary(span.end) { return None; }
        if span.start == span.end { return Some(Cow::Borrowed("")); }
        let index = self.offsets.partition_point(|offset| *offset <= span.start).checked_sub(1)?;
        let first = self.offsets[index];
        if span.end <= first + self.pieces[index].len() {
            return self.pieces[index].get(span.start-first..span.end-first).map(Cow::Borrowed);
        }
        let mut result = String::with_capacity(span.end-span.start);
        for (piece, offset) in self.pieces[index..].iter().zip(&self.offsets[index..]) {
            if *offset >= span.end { break; }
            let a = span.start.saturating_sub(*offset);
            let b = (span.end-*offset).min(piece.len());
            result.push_str(piece.get(a..b)?);
        }
        Some(Cow::Owned(result))
    }
    /// Explicit compatibility bridge. Production consumers should request only
    /// the declaration/procedure range they are processing.
    pub fn materialize(&self) -> String {
        self.slice(Span::new(0, self.bytes)).unwrap_or_default().into_owned()
    }
    pub fn line_starts(&self) -> Vec<usize> {
        let mut starts = vec![0];
        for (lines, offset) in self.lines.iter().zip(self.offsets.iter()) {
            starts.extend(lines.iter().map(|at| offset+at));
        }
        starts
    }
    pub fn line_number(&self, offset: usize) -> Option<usize> {
        if offset >= self.bytes { return None; }
        let index = self.offsets.partition_point(|at| *at <= offset).checked_sub(1)?;
        Some(1+self.preceding_lines[index]+self.lines[index].partition_point(|at| *at <= offset-self.offsets[index]))
    }
    /// Carry the unfinished top-level declaration across piece boundaries.
    /// No scanner invocation receives the whole project. Complete declarations
    /// are emitted before the carry buffer is advanced.
    pub fn for_each_chunk(&self, target: usize, limit: usize, mut visit: impl FnMut(&str, usize)) -> Result<ChunkReport, String> {
        let limit = limit.max(1);
        let mut carry = String::new();
        let mut base = 0usize;
        let mut total = ChunkReport::default();
        for (index, piece) in self.pieces.iter().enumerate() {
            carry.push_str(piece);
            let final_piece = index+1 == self.pieces.len();
            let mut boundary = 0;
            if final_piece { boundary = carry.len(); }
            else { crate::audit::for_each_top_level_boundary(&carry, |at| boundary = at); }
            if boundary > 0 {
                let report = crate::for_each_source_chunk_with_limits(&carry[..boundary], target, limit, |text, offset| visit(text, base+offset));
                total.parsed_chunks += report.parsed_chunks;
                total.parsed_bytes += report.parsed_bytes;
                total.skipped_declarations += report.skipped_declarations;
                total.skipped_bytes += report.skipped_bytes;
                if total.first_skipped_span.is_none() { total.first_skipped_span = report.first_skipped_span.map(|span| Span::new(base+span.start, base+span.end)); }
                carry.drain(..boundary);
                base += boundary;
            }
            if carry.len() > limit {
                return Err(format!("declaration at expanded offset {base} exceeds the parse chunk limit of {limit} bytes"));
            }
        }
        Ok(total)
    }
    /// Transition memoization uses shared piece identity and exact incoming
    /// unfinished declaration text. An edit rescans through lexical changes
    /// until the incoming state converges with an unchanged piece.
    pub fn for_each_chunk_cached(&self, session: &mut SegmentedChunkSession, target: usize, limit: usize, mut visit: impl FnMut(&str, usize)) -> Result<ChunkReport, String> {
        session.scanned_bytes = 0;
        let limit = limit.max(1);
        let mut carry = String::new();
        let mut base = 0;
        let mut total = ChunkReport::default();
        for (index, piece) in self.pieces.iter().enumerate() {
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            carry.hash(&mut hasher);
            let key = (Arc::as_ptr(piece) as *const () as usize, hasher.finish(), index+1 == self.pieces.len(), target, limit);
            let hit = session.transitions.get(&key).is_some_and(|entry| entry.piece.upgrade().is_some_and(|cached| Arc::ptr_eq(&cached, piece)) && &*entry.carry == carry);
            if !hit {
                let incoming: Arc<str> = Arc::from(carry.as_str());
                let mut window = String::with_capacity(carry.len()+piece.len());
                window.push_str(&carry);
                window.push_str(piece);
                let mut boundary = 0;
                if key.2 { boundary = window.len(); }
                else { crate::audit::for_each_top_level_boundary(&window, |at| boundary = at); }
                let mut spans = Vec::new();
                let report = crate::for_each_source_chunk_with_limits(&window[..boundary], target, limit, |text, offset| spans.push(Span::new(offset, offset+text.len())));
                // The syntax scanner reports a count and first skipped range;
                // no successful production parse can retain skipped input.
                let skipped = report.first_skipped_span.into_iter().collect();
                session.scanned_bytes += window.len()+boundary;
                let charge = incoming.len()+spans.capacity()*std::mem::size_of::<Span>()+256;
                if session.bytes+charge > 32*1024*1024 || session.transitions.len() >= 8192 { session.clear(); }
                session.bytes += charge;
                session.transitions.insert(key, PieceTransition { piece: Arc::downgrade(piece), carry: incoming, boundary, spans, skipped });
            }
            let transition = &session.transitions[&key];
            let incoming_len = carry.len();
            if let Some(span) = transition.skipped.first() {
                return Err(format!("declaration at expanded offset {} exceeds the parse chunk limit of {limit} bytes", base+span.start));
            }
            for span in &transition.spans {
                if span.end <= incoming_len { visit(&carry[span.range()], base+span.start); }
                else if span.start >= incoming_len { visit(&piece[span.start-incoming_len..span.end-incoming_len], base+span.start); }
                else {
                    let mut joined = String::with_capacity(span.end-span.start);
                    joined.push_str(&carry[span.start..]);
                    joined.push_str(&piece[..span.end-incoming_len]);
                    visit(&joined, base+span.start);
                }
                total.parsed_chunks += 1;
                total.parsed_bytes += span.end-span.start;
            }
            if transition.boundary >= incoming_len {
                carry.clear();
                carry.push_str(&piece[transition.boundary-incoming_len..]);
            } else {
                carry.drain(..transition.boundary);
                carry.push_str(piece);
            }
            base += transition.boundary;
            if carry.len() > limit { return Err(format!("declaration at expanded offset {base} exceeds the parse chunk limit of {limit} bytes")); }
        }
        Ok(total)
    }
}
