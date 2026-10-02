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
    disk: Option<std::sync::Weak<std::path::PathBuf>>,
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
    disk: Arc<[Option<Arc<std::path::PathBuf>>]>,
    lengths: Arc<[usize]>,
    digests: Arc<[Option<[u8;32]>]>,
    non_boundaries: Arc<[Arc<[usize]>]>,
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
        let lengths=pieces.iter().map(|piece|piece.len()).collect::<Vec<_>>().into();
        let non_boundaries=pieces.iter().map(|piece|piece.bytes().enumerate().filter_map(|(at,byte)|((byte&0xc0)==0x80).then_some(at)).collect::<Vec<_>>().into()).collect::<Vec<Arc<[usize]>>>().into();
        let disk=vec![None;pieces.len()].into();
        let digests=vec![None;pieces.len()].into();
        Self { pieces: pieces.into(), offsets: offsets.into(), bytes, lines: lines.into(), preceding_lines: preceding_lines.into(),disk,lengths,digests,non_boundaries }
    }
    /// Immutable disk handles retain source layout while decoded payloads can
    /// be evicted. Each visitor or range request loads only its bounded pieces.
    pub fn with_backings(pieces:impl IntoIterator<Item=(Arc<str>,usize,Arc<[usize]>,Arc<[usize]>,Option<Arc<std::path::PathBuf>>,[u8;32])>) -> Self {
        let mut source=Self::default();let mut text=Vec::new();let mut offsets=Vec::new();let mut lines=Vec::new();let mut preceding=Vec::new();let mut disk=Vec::new();let mut lengths=Vec::new();let mut non_boundaries=Vec::new();let mut count=0;let mut digests=Vec::new();
        for (piece,len,piece_lines,utf8,blob,digest) in pieces {
            offsets.push(source.bytes);source.bytes+=len;preceding.push(count);count+=piece_lines.len();
            text.push(piece);lengths.push(len);lines.push(piece_lines);disk.push(blob);non_boundaries.push(utf8);digests.push(Some(digest));
        }
        source.pieces=text.into();source.offsets=offsets.into();source.lines=lines.into();source.preceding_lines=preceding.into();source.disk=disk.into();source.lengths=lengths.into();source.digests=digests.into();source.non_boundaries=non_boundaries.into();source
    }
    fn content(&self,index:usize)->Result<Arc<str>,String> {
        if self.pieces[index].len()==self.lengths[index] {return Ok(Arc::clone(&self.pieces[index]));}
        let path=self.disk[index].as_ref().ok_or("source piece has no disk backing")?;
        let mut bytes=Vec::new();use std::io::Read;
        std::fs::File::open(path.as_ref()).map_err(|error|format!("expanded-cache: {error}"))?.take(self.lengths[index] as u64+1).read_to_end(&mut bytes).map_err(|error|format!("expanded-cache: {error}"))?;
        if bytes.len()!=self.lengths[index] {return Err("expanded-cache: invalid expanded piece length".into());}
        use sha2::Digest;
        if self.digests[index].is_some_and(|expected|<[u8;32]>::from(sha2::Sha256::digest(&bytes))!=expected) {return Err("expanded-cache: invalid expanded piece digest".into());}
        String::from_utf8(bytes).map(Arc::from).map_err(|error|format!("expanded-cache: {error}"))
    }
    pub fn visit_range(&self,span:Span,mut visit:impl FnMut(&str))->Result<(),String> {
        if span.start>span.end || !self.is_char_boundary(span.start) || !self.is_char_boundary(span.end) {return Err("invalid expanded range".into());}
        if span.start==span.end {return Ok(());}
        let first=self.offsets.partition_point(|offset|*offset<=span.start).saturating_sub(1);
        for index in first..self.pieces.len() {
            let offset=self.offsets[index];if offset>=span.end {break;}
            let piece=self.content(index)?;
            visit(&piece[span.start.saturating_sub(offset)..(span.end-offset).min(piece.len())]);
        }
        Ok(())
    }
    pub fn evict_payloads(&mut self) {
        let mut pieces=self.pieces.to_vec();
        for (index,piece) in pieces.iter_mut().enumerate() {if self.disk[index].is_some() {*piece=Arc::from("");}}
        self.pieces=pieces.into();
    }
    pub fn visit_pieces(&self,mut visit:impl FnMut(&str))->Result<(),String> {
        for index in 0..self.pieces.len() {let piece=self.content(index)?;visit(&piece);}Ok(())
    }
    pub fn len(&self) -> usize { self.bytes }
    pub fn is_empty(&self) -> bool { self.bytes == 0 }
    pub fn is_char_boundary(&self, offset: usize) -> bool {
        if offset == self.bytes { return true; }
        if offset > self.bytes { return false; }
        self.offsets.partition_point(|at| *at <= offset).checked_sub(1)
            .is_some_and(|index| self.non_boundaries[index].binary_search(&(offset-self.offsets[index])).is_err())
    }
    pub fn resident_pieces(&self) -> &[Arc<str>] { &self.pieces }
    pub fn piece_offsets(&self) -> &[usize] { &self.offsets }
    /// Compatibility range lookup. Fallible consumers must use `try_slice` so
    /// missing or corrupt cache chunks are not mistaken for invalid spans.
    pub fn slice(&self, span: Span) -> Option<Cow<'_, str>> {
        self.try_slice(span).ok()
    }
    pub fn try_slice(&self, span: Span) -> Result<Cow<'_, str>, String> {
        let invalid = || "source span outside segmented expansion".to_owned();
        if span.start > span.end || !self.is_char_boundary(span.start) || !self.is_char_boundary(span.end) { return Err(invalid()); }
        if span.start == span.end { return Ok(Cow::Borrowed("")); }
        let index = self.offsets.partition_point(|offset| *offset <= span.start).checked_sub(1).ok_or_else(invalid)?;
        let first = self.offsets[index];
        if span.end <= first+self.lengths[index] && self.pieces[index].len()==self.lengths[index] {
            return self.pieces[index].get(span.start-first..span.end-first).map(Cow::Borrowed).ok_or_else(invalid);
        }
        let mut result=String::with_capacity(span.end-span.start);
        for index in index..self.pieces.len() {
            let offset=self.offsets[index];if offset>=span.end {break;}
            let piece=self.content(index)?;
            let a=span.start.saturating_sub(offset);let b=(span.end-offset).min(piece.len());
            result.push_str(piece.get(a..b).ok_or_else(invalid)?);
        }
        Ok(Cow::Owned(result))
    }
    /// Explicit compatibility bridge; never substitutes empty text on failure.
    pub fn try_materialize(&self) -> Result<String, String> {
        self.try_slice(Span::new(0, self.bytes)).map(Cow::into_owned)
    }
    pub fn materialize(&self) -> Result<String, String> {
        self.try_materialize()
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
        for index in 0..self.pieces.len() {
            let piece=self.content(index)?;
            carry.push_str(&piece);
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
        for index in 0..self.pieces.len() {
            let piece=self.content(index)?;
            let disk=self.disk[index].as_ref();
            let identity=disk.map_or_else(||Arc::as_ptr(&self.pieces[index]) as *const () as usize,|path|Arc::as_ptr(path) as usize);
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            carry.hash(&mut hasher);
            let key = (identity, hasher.finish(), index+1 == self.pieces.len(), target, limit);
            let hit = session.transitions.get(&key).is_some_and(|entry| disk.map_or_else(||entry.piece.upgrade().is_some_and(|cached| Arc::ptr_eq(&cached,&self.pieces[index])),|path|entry.disk.as_ref().and_then(|weak|weak.upgrade()).is_some_and(|cached|Arc::ptr_eq(&cached,path))) && &*entry.carry == carry);
            if !hit {
                let incoming: Arc<str> = Arc::from(carry.as_str());
                let mut window = String::with_capacity(carry.len()+piece.len());
                window.push_str(&carry);
                window.push_str(&piece);
                let mut boundaries = Vec::new();
                crate::audit::for_each_top_level_boundary(&window, |at| boundaries.push(at));
                let boundary = if key.2 { window.len() } else { boundaries.last().copied().unwrap_or(0) };
                let mut spans = Vec::new();
                let report = crate::audit::source_chunks_from_boundaries(&window[..boundary], target, limit, &boundaries, |text, offset| spans.push(Span::new(offset, offset+text.len())));
                // The syntax scanner reports a count and first skipped range;
                // no successful production parse can retain skipped input.
                let skipped = report.first_skipped_span.into_iter().collect();
                session.scanned_bytes += window.len();
                let charge = incoming.len()+spans.capacity()*std::mem::size_of::<Span>()+256;
                if session.bytes+charge > 32*1024*1024 || session.transitions.len() >= 8192 { session.clear(); }
                session.bytes += charge;
                session.transitions.insert(key, PieceTransition { piece: Arc::downgrade(&self.pieces[index]), disk:disk.map(Arc::downgrade), carry: incoming, boundary, spans, skipped });
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
                carry.push_str(&piece);
            }
            base += transition.boundary;
            if carry.len() > limit { return Err(format!("declaration at expanded offset {base} exceeds the parse chunk limit of {limit} bytes")); }
        }
        Ok(total)
    }
}
