//! Compact layout evidence owned by the EXISTING expanded-origin arena.
//! Mint once during normal region-output joining, using CURRENT PreparedLine
//! views and actual acquisition leases. Never deserialize authority from memo.
use super::{
    prepared_source::PreparedLineView, DirectivePlan, ExpandedOriginArena, ExpandedOriginView,
};
use crate::{SourceAcquisitionIdentity, SourceAcquisitionLease, SourceEncoding};
use dm_syntax::Span;
use std::sync::Arc;
fn body_without_line_ending(text: &str) -> &str {
    let text = text.strip_suffix('\n').unwrap_or(text);
    text.strip_suffix('\r').unwrap_or(text)
}

/// Two bits per existing origin row; no copied text, AST, line table or model.
/// Weak source-binding identities cannot retain raw source or receipts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SparseLayout {
    row: usize,
    source_delta: usize,
    line_delta: usize,
    width: usize,
    terminator: bool,
    /// Exact CURRENT raw CRLF: expanded LF points to its LF, not preceding CR.
    crlf_terminator: bool,
}
pub struct ByteLayoutLedger {
    bindings: Box<[Option<SourceAcquisitionIdentity>]>,
    regions: Arc<[(usize, usize)]>,
    classes: Box<[u64]>,
    /// Sparse physical-row layouts and strict first-line prefixes.
    prefixes: Box<[SparseLayout]>,
    macro_lines: Box<[usize]>,
    rows: usize,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OriginalByteCursor {
    pub line: usize,
    pub byte_column: usize,
    pub source_offset: usize,
}
pub(super) struct ByteLayoutBuilder {
    acquisitions: Arc<[Option<SourceAcquisitionLease>]>,
    regions: Arc<[(usize, usize)]>,
    classes: Vec<u64>,
    prefixes: Vec<SparseLayout>,
    macro_lines: Vec<usize>,
    rows: usize,
}
impl ByteLayoutBuilder {
    /// Same source binding table for every row from this native expansion.
    pub(super) fn for_plan(plan: &DirectivePlan) -> Self {
        Self {
            acquisitions: (0..plan.occurrences.len())
                .map(|i| plan.source_acquisitions.get(&i).cloned())
                .collect(),
            regions: plan
                .regions
                .iter()
                .map(|r| (r.occurrence, r.encounter_ordinal))
                .collect(),
            classes: Vec::new(),
            prefixes: Vec::new(),
            macro_lines: Vec::new(),
            rows: 0,
        }
    }
    #[cfg(test)]
    fn from_bindings(acquisitions: Arc<[Option<SourceAcquisitionLease>]>) -> Self {
        Self {
            acquisitions,
            regions: vec![(0, 0)].into(),
            classes: Vec::new(),
            prefixes: Vec::new(),
            macro_lines: Vec::new(),
            rows: 0,
        }
    }
    pub(super) fn rows(&self) -> usize {
        self.rows
    }
    /// Call ONCE beside each joined native origin row, for cold AND memo hits.
    /// `prepared` comes from CURRENT region.segments' existing line iterator,
    /// never a reconstruction or a stale memo's source binding.
    pub(super) fn record(
        &mut self,
        region: usize,
        prepared: Option<PreparedLineView<'_>>,
        source_line: usize,
        source_span: Span,
        output_part: &str,
        has_macros: bool,
    ) {
        self.record_part(
            region,
            prepared,
            source_line,
            source_span,
            output_part,
            has_macros,
            0,
        );
    }
    fn record_part(
        &mut self,
        region: usize,
        prepared: Option<PreparedLineView<'_>>,
        source_line: usize,
        source_span: Span,
        output_part: &str,
        has_macros: bool,
        part_ordinal: usize,
    ) {
        let mut class = self.regions.get(region).map_or(0, |&(occurrence, _)| {
            self.classify(
                occurrence,
                prepared,
                source_line,
                source_span,
                output_part,
                has_macros,
            )
        });
        if class == 0 {
            let certified = self.regions.get(region).and_then(|&(occurrence, _)| {
                self.physical_layout(
                    occurrence,
                    prepared,
                    source_line,
                    source_span,
                    output_part,
                    has_macros,
                    part_ordinal,
                )
                .or_else(|| {
                    (part_ordinal == 0)
                        .then(|| {
                            self.exact_prefix(
                                occurrence,
                                prepared,
                                source_line,
                                source_span,
                                output_part,
                                has_macros,
                            )
                        })
                        .flatten()
                        .map(|width| SparseLayout {
                            row: self.rows,
                            source_delta: 0,
                            line_delta: 0,
                            width,
                            terminator: false,
                            crlf_terminator: false,
                        })
                })
            });
            if let Some(layout) = certified {
                class = 3;
                self.prefixes.push(layout);
            }
        }
        if self.rows % 32 == 0 {
            self.classes.push(0);
        }
        self.classes[self.rows / 32] |= u64::from(class) << ((self.rows % 32) * 2);
        self.rows += 1;
    }
    /// Split only physical LF boundaries already present in the current issued
    /// PreparedLine. Every raw/prepared physical width must match, preventing a
    /// joined continuation from pretending it is byte-preserving. Comments use
    /// the existing producer's one-byte-per-byte mask; no grammar is rescanned.
    fn record_macro_line(
        &mut self,
        index: usize,
        region: usize,
        line: Option<PreparedLineView<'_>>,
        source_line: usize,
        source_span: Span,
    ) {
        let Some(&(occurrence, _)) = self.regions.get(region) else {
            return;
        };
        let Some(lease) = self.acquisitions.get(occurrence).and_then(Option::as_ref) else {
            return;
        };
        let Some(line) = line else {
            return;
        };
        if !matches!(
            lease.encoding(),
            SourceEncoding::Utf8 | SourceEncoding::SyntheticUtf8
        ) || line.source_span != source_span
            || line.source_line != source_line
            || line.source_lines != 1
        {
            return;
        }
        let Some(raw) = lease.source_text().get(source_span.range()) else {
            return;
        };
        if body_without_line_ending(raw).contains('\n') {
            return;
        }
        self.macro_lines.push(index);
    }
    fn physical_layout(
        &self,
        occurrence: usize,
        line: Option<PreparedLineView<'_>>,
        source_line: usize,
        source_span: Span,
        part: &str,
        has_macros: bool,
        ordinal: usize,
    ) -> Option<SparseLayout> {
        if has_macros {
            return None;
        }
        let lease = self.acquisitions.get(occurrence)?.as_ref()?;
        if !matches!(
            lease.encoding(),
            SourceEncoding::Utf8 | SourceEncoding::SyntheticUtf8
        ) {
            return None;
        }
        let line = line?;
        if line.source_span != source_span || line.source_line != source_line {
            return None;
        }
        let raw = lease.source_text().get(source_span.range())?;
        let raw_body = raw.trim_end_matches(['\r', '\n']);
        let prepared_body = line.text.trim_end_matches(['\r', '\n']);
        let raw_count = raw_body.split('\n').count();
        if raw_count != line.source_lines || raw_count != prepared_body.split('\n').count() {
            return None;
        }
        let mut source_delta = 0;
        let mut selected = None;
        for (index, (raw_part, prepared_part)) in raw_body
            .split('\n')
            .zip(prepared_body.split('\n'))
            .enumerate()
        {
            if raw_part.len() != prepared_part.len() {
                return None;
            }
            if index == ordinal {
                if part != prepared_part {
                    return None;
                }
                selected = Some(SparseLayout {
                    row: self.rows,
                    source_delta,
                    line_delta: index,
                    width: part.len(),
                    terminator: raw.as_bytes().get(source_delta + part.len()) == Some(&b'\n')
                        || raw
                            .as_bytes()
                            .get(source_delta + part.len()..source_delta + part.len() + 2)
                            == Some(b"\r\n"),
                    crlf_terminator: raw
                        .as_bytes()
                        .get(source_delta + part.len()..source_delta + part.len() + 2)
                        == Some(b"\r\n"),
                });
            }
            source_delta = source_delta.checked_add(raw_part.len())?.checked_add(1)?;
        }
        selected
    }
    /// Only exact bytes BEFORE the first altered byte/physical newline are
    /// admitted. This does not interpret continuations, comments or literals.
    /// Later emitted parts need a separate producer-issued physical-row map.
    fn exact_prefix(
        &self,
        occurrence: usize,
        line: Option<PreparedLineView<'_>>,
        source_line: usize,
        source_span: Span,
        part: &str,
        has_macros: bool,
    ) -> Option<usize> {
        if has_macros {
            return None;
        }
        let lease = self.acquisitions.get(occurrence)?.as_ref()?;
        if !matches!(
            lease.encoding(),
            SourceEncoding::Utf8 | SourceEncoding::SyntheticUtf8
        ) {
            return None;
        }
        let line = line?;
        if line.source_span != source_span || line.source_line != source_line {
            return None;
        }
        let raw = lease.source_text().get(source_span.range())?;
        let prefix = raw
            .bytes()
            .zip(line.text.bytes())
            .zip(part.bytes())
            .take_while(|&((raw, prepared), emitted)| {
                raw != b'\n' && raw == prepared && raw == emitted
            })
            .count();
        (prefix > 0).then_some(prefix)
    }
    fn classify(
        &self,
        occurrence: usize,
        line: Option<PreparedLineView<'_>>,
        source_line: usize,
        source_span: Span,
        part: &str,
        has_macros: bool,
    ) -> u8 {
        let Some(lease) = self.acquisitions.get(occurrence).and_then(Option::as_ref) else {
            return 0;
        };
        if !matches!(
            lease.encoding(),
            SourceEncoding::Utf8 | SourceEncoding::SyntheticUtf8
        ) || has_macros
        {
            return 0;
        }
        let Some(line) = line else {
            return 0;
        };
        if line.source_span != source_span
            || line.source_line != source_line
            || line.source_lines != 1
        {
            return 0;
        }
        let Some(raw) = lease.source_text().get(source_span.range()) else {
            return 0;
        };
        let raw_body = body_without_line_ending(raw);
        let prepared_body = body_without_line_ending(line.text.as_ref());
        if raw_body.contains(['\r', '\n'])
            || prepared_body.contains(['\r', '\n'])
            || raw_body.len() != prepared_body.len()
            || part != prepared_body
        {
            return 0;
        }
        // Authority is current native input issuance; these width checks prove
        // only its supported transform. PreparedSource blanks comments one
        // BYTE at a time. Equal text/width never substitutes for a source lease.
        if raw.ends_with("\r\n") {
            // Class1 conflates no-LF source with CRLF. A real CRLF needs the
            // sparse producer's terminator byte evidence; never widen class1.
            0
        } else if raw.ends_with('\n') {
            2
        } else {
            1
        }
    }
    pub(super) fn finish(self) -> ByteLayoutLedger {
        ByteLayoutLedger {
            bindings: self
                .acquisitions
                .iter()
                .map(|lease| lease.as_ref().map(SourceAcquisitionLease::identity))
                .collect(),
            regions: self.regions,
            classes: self.classes.into_boxed_slice(),
            prefixes: self.prefixes.into_boxed_slice(),
            macro_lines: self.macro_lines.into_boxed_slice(),
            rows: self.rows,
        }
    }
}
impl ByteLayoutLedger {
    pub fn regions(&self) -> &Arc<[(usize, usize)]> {
        &self.regions
    }
    pub fn rows(&self) -> usize {
        self.rows
    }
    /// ExpandedOriginArena must get `origin` itself at `index`; do not expose a
    /// public API accepting a caller-supplied origin row/foreign scalar span.
    pub(super) fn locate(
        &self,
        index: usize,
        origin: ExpandedOriginView<'_>,
        occurrence: usize,
        expected: &SourceAcquisitionLease,
        offset: usize,
    ) -> Result<OriginalByteCursor, &'static str> {
        if self.regions.get(origin.region).map(|r| r.0) != Some(occurrence) {
            return Err("original layout belongs to another include occurrence");
        }
        let binding = self
            .bindings
            .get(occurrence)
            .and_then(Option::as_ref)
            .ok_or("original layout acquisition absent")?;
        if !binding.matches(expected) {
            return Err("original layout belongs to another source acquisition binding");
        }
        if index >= self.rows {
            return Err("original layout row unavailable");
        }
        let class = ((self.classes[index / 32] >> ((index % 32) * 2)) & 3) as u8;
        if class == 0 {
            return Err("original layout is not certified");
        }
        if !origin.macro_expansions.is_empty()
            || offset < origin.output_span.start
            || offset >= origin.output_span.end
        {
            return Err("original point is outside certified native interval");
        }
        // Normal expansion appends exactly one LF to each emitted part.
        let body_len = origin
            .output_span
            .end
            .checked_sub(origin.output_span.start)
            .and_then(|width| width.checked_sub(1))
            .ok_or("invalid native line interval")?;
        let delta = offset - origin.output_span.start;
        let layout = if class == 3 {
            let entry = self
                .prefixes
                .binary_search_by_key(&index, |layout| layout.row)
                .map_err(|_| "original point-prefix evidence unavailable")?;
            Some(self.prefixes[entry])
        } else {
            None
        };
        let within_layout = layout.map_or_else(
            || delta < body_len || (delta == body_len && class == 2),
            |layout| delta < layout.width || (delta == layout.width && layout.terminator),
        );
        if !within_layout || delta > body_len {
            return Err("original terminator coordinate is not certified");
        }
        let original_delta = delta
            .checked_add(usize::from(layout.is_some_and(|layout| {
                delta == layout.width && layout.crlf_terminator
            })))
            .ok_or("original CRLF terminator offset overflow")?;
        let source_offset = origin
            .source_span
            .start
            .checked_add(layout.map_or(0, |layout| layout.source_delta))
            .and_then(|start| start.checked_add(original_delta))
            .ok_or("original offset overflow")?;
        if source_offset >= origin.source_span.end
            || !expected.source_text().is_char_boundary(source_offset)
        {
            return Err("original point has no byte boundary");
        }
        Ok(OriginalByteCursor {
            line: origin
                .origin
                .source_line
                .checked_add(layout.map_or(0, |layout| layout.line_delta))
                .ok_or("original source line overflow")?,
            byte_column: original_delta + 1,
            source_offset,
        })
    }
    pub(super) fn locate_macro_line(
        &self,
        index: usize,
        origin: ExpandedOriginView<'_>,
        occurrence: usize,
        expected: &SourceAcquisitionLease,
        offset: usize,
    ) -> Result<usize, &'static str> {
        if self.regions.get(origin.region).map(|r| r.0) != Some(occurrence) {
            return Err("policy line belongs to another occurrence");
        }
        let binding = self
            .bindings
            .get(occurrence)
            .and_then(Option::as_ref)
            .ok_or("policy line acquisition absent")?;
        if !binding.matches(expected) {
            return Err("policy line belongs to another source acquisition binding");
        }
        if origin.macro_expansions.is_empty()
            || offset < origin.output_span.start
            || offset >= origin.output_span.end
            || self.macro_lines.binary_search(&index).is_err()
        {
            return Err("single-physical macro policy line was not issued");
        }
        Ok(origin.origin.source_line)
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(
            self.bindings.as_ptr() as usize,
            self.bindings.len(),
            std::mem::size_of_val(self.bindings.as_ref()),
        );
        visit(
            self.classes.as_ptr() as usize,
            self.classes.len(),
            std::mem::size_of_val(self.classes.as_ref()),
        );
        visit(
            self.macro_lines.as_ptr() as usize,
            self.macro_lines.len(),
            std::mem::size_of_val(self.macro_lines.as_ref()),
        );
        visit(
            self.prefixes.as_ptr() as usize,
            self.prefixes.len(),
            std::mem::size_of_val(self.prefixes.as_ref()),
        );
        visit(
            self.regions.as_ptr() as usize,
            self.regions.len(),
            std::mem::size_of_val(self.regions.as_ref()),
        );
        for binding in self.bindings.iter().flatten() {
            binding.visit_storage(|storage| {
                if let crate::source_acquisition::AcquisitionStorage::Object { address, bytes } =
                    storage
                {
                    visit(address, 1, bytes);
                }
            });
        }
    }
    pub(super) fn equivalent(&self, other: &Self) -> bool {
        self.rows == other.rows
            && self.classes == other.classes
            && self.prefixes == other.prefixes
            && self.macro_lines == other.macro_lines
            && self.regions == other.regions
            && self.bindings.len() == other.bindings.len()
            && self
                .bindings
                .iter()
                .zip(other.bindings.iter())
                .all(|(a, b)| match (a, b) {
                    (Some(a), Some(b)) => a.same_identity(b),
                    (None, None) => true,
                    _ => false,
                })
    }
}

/// Run in normal AND incremental expansion publication after the final native
/// origin-row assembly. CURRENT plan line views are still live here. Cached
/// rows supply no certificate authority; every locator is freshly bound.
pub(super) fn bind_current_layout(
    plan: &DirectivePlan,
    text: &str,
    origins: ExpandedOriginArena,
) -> ExpandedOriginArena {
    let mut builder = ByteLayoutBuilder::for_plan(plan);
    let mut current: Vec<_> = plan
        .regions
        .iter()
        .map(|region| {
            region
                .segments
                .iter()
                .flat_map(|segment| segment.lines.iter())
                .peekable()
        })
        .collect();
    // Per-region part ordinal of the CURRENT prepared logical line. Duplicate
    // text in a later physical part must never impersonate its first prefix.
    let mut emitted_parts = vec![None; plan.regions.len()];
    for origin in origins.iter() {
        let key = (
            origin.source_span.start,
            origin.source_span.end,
            origin.origin.source_line,
        );
        let part_ordinal = match emitted_parts.get_mut(origin.region) {
            Some(state) => {
                let ordinal = match state {
                    Some((previous, count)) if *previous == key => *count,
                    _ => 0,
                };
                *state = Some((key, ordinal + 1));
                ordinal
            }
            None => 0,
        };
        let prepared = current.get_mut(origin.region).and_then(|input| {
            while input.peek().is_some_and(|line| {
                (
                    line.source_span.start,
                    line.source_span.end,
                    line.source_line,
                ) < key
            }) {
                input.next();
            }
            input
                .peek()
                .filter(|line| {
                    (
                        line.source_span.start,
                        line.source_span.end,
                        line.source_line,
                    ) == key
                })
                .copied()
        });
        if origins.single_physical_macro_line(builder.rows()) && !origin.macro_expansions.is_empty()
        {
            builder.record_macro_line(
                builder.rows(),
                origin.region,
                prepared,
                origin.origin.source_line,
                origin.source_span,
            );
        }
        let part = text
            .get(origin.output_span.range())
            .and_then(|part| part.strip_suffix('\n'));
        match part {
            Some(part) => builder.record_part(
                origin.region,
                prepared,
                origin.origin.source_line,
                origin.source_span,
                part,
                !origin.macro_expansions.is_empty(),
                part_ordinal,
            ),
            None => builder.record(
                origin.region,
                None,
                origin.origin.source_line,
                origin.source_span,
                "",
                true,
            ),
        }
    }
    debug_assert_eq!(builder.rows(), origins.len());
    origins.with_byte_layout(builder.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AcquiredSource;
    use std::path::PathBuf;
    #[test]
    fn utf8_comment_tab_width_and_foreign_binding_do_not_depend_on_storage_interning() {
        let raw = "\tvar/x /* é漢 */ = 1\n";
        let heavy = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), 1u64);
        let line = heavy.prepared().lines().iter().next().unwrap();
        let part = line.text.trim_end_matches(['\r', '\n']);
        let prepared_refs = Arc::strong_count(heavy.prepared());
        let mut builder =
            ByteLayoutBuilder::from_bindings(vec![Some(heavy.lease().clone())].into());
        builder.record(0, Some(line), 1, line.source_span, part, false);
        let ledger = builder.finish();
        assert_eq!(
            Arc::strong_count(heavy.prepared()),
            prepared_refs,
            "ledger must not retain PreparedSource"
        );
        let path = Arc::new(PathBuf::from("source.dm"));
        let traces = Arc::new(Vec::new());
        let origin = ExpandedOriginView {
            origin: super::super::origin_arena::OriginView {
                output_line: 1,
                path: &path,
                source_line: 1,
            },
            output_span: Span::new(0, part.len() + 1),
            source_span: line.source_span,
            region: 0,
            macro_expansions: &traces,
        };
        let offset = part.as_bytes().iter().position(|&b| b == b'=').unwrap();
        assert_eq!(
            ledger
                .locate(0, origin, 0, heavy.lease(), offset)
                .unwrap()
                .byte_column,
            20
        );
        assert!(ledger.locate(0, origin, 1, heavy.lease(), offset).is_err());
        let foreign = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), 2u64);
        assert!(Arc::ptr_eq(heavy.prepared(), foreign.prepared()));
        assert!(ledger
            .locate(0, origin, 0, foreign.lease(), offset)
            .is_err());
        let reissued = heavy.reissued(3u64);
        assert!(reissued.lease().same_original_acquisition(heavy.lease()));
        assert!(
            ledger
                .locate(0, origin, 0, reissued.lease(), offset)
                .is_err(),
            "reissue is not implicit locator authority"
        );
    }
    #[test]
    fn expired_layout_identity_does_not_keep_receipt_or_original_binding_alive() {
        let receipt = Arc::new(());
        let dropped = Arc::downgrade(&receipt);
        let heavy = AcquiredSource::from_original_bytes(b"/proc/p()\n".to_vec(), receipt.clone());
        drop(receipt);
        let identity = heavy.lease().identity();
        let line = heavy.prepared().lines().iter().next().unwrap();
        let part = line.text.trim_end_matches(['\r', '\n']);
        let mut builder =
            ByteLayoutBuilder::from_bindings(vec![Some(heavy.lease().clone())].into());
        builder.record(0, Some(line), 1, line.source_span, part, false);
        let ledger = builder.finish();
        drop(heavy);
        assert!(!identity.is_alive());
        assert!(dropped.upgrade().is_none());
        let foreign = AcquiredSource::from_original_bytes(b"/proc/p()\n".to_vec(), ());
        assert!(!identity.matches(foreign.lease()));
        assert_eq!(ledger.rows(), 1);
    }
    #[test]
    fn macros_transformed_lines_and_unknown_encoding_do_not_gain_a_certificate() {
        for (raw, macros) in [("var/x=1\n", true), ("var/x=\\\n  1\n", false)] {
            let heavy = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), ());
            let line = heavy.prepared().lines().iter().next().unwrap();
            let part = line.text.trim_end_matches(['\r', '\n']);
            let mut builder =
                ByteLayoutBuilder::from_bindings(vec![Some(heavy.lease().clone())].into());
            builder.record(
                0,
                Some(line),
                line.source_line,
                line.source_span,
                part,
                macros,
            );
            let ledger = builder.finish();
            assert_eq!(ledger.classes[0] & 3, if macros { 0 } else { 3 });
        }
        let bom = AcquiredSource::from_original_bytes(b"\xef\xbb\xbfvar/x=1\n".to_vec(), ());
        let line = bom.prepared().lines().iter().next().unwrap();
        let mut builder = ByteLayoutBuilder::from_bindings(vec![Some(bom.lease().clone())].into());
        builder.record(
            0,
            Some(line),
            line.source_line,
            line.source_span,
            line.text.trim_end_matches(['\r', '\n']),
            false,
        );
        assert_eq!(builder.finish().classes[0] & 3, 0);
    }
}

#[cfg(test)]
mod point_prefix_tests {
    use super::*;
    use crate::AcquiredSource;
    use std::path::PathBuf;
    fn probe(
        raw: &str,
        requested: &[usize],
        part_ordinal: usize,
    ) -> (u8, Vec<Result<OriginalByteCursor, &'static str>>) {
        let heavy = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), ());
        let line = heavy.prepared().lines().iter().next().unwrap();
        let part = line
            .text
            .trim_end_matches(['\r', '\n'])
            .split('\n')
            .nth(part_ordinal)
            .unwrap();
        let mut builder =
            ByteLayoutBuilder::from_bindings(vec![Some(heavy.lease().clone())].into());
        builder.record_part(
            0,
            Some(line),
            line.source_line,
            line.source_span,
            part,
            false,
            part_ordinal,
        );
        let ledger = builder.finish();
        let path = Arc::new(PathBuf::from("source.dm"));
        let traces = Arc::new(Vec::new());
        let origin = ExpandedOriginView {
            origin: super::super::origin_arena::OriginView {
                output_line: 1,
                path: &path,
                source_line: 1,
            },
            output_span: Span::new(0, part.len() + 1),
            source_span: line.source_span,
            region: 0,
            macro_expansions: &traces,
        };
        (
            ledger.classes[0] as u8 & 3,
            requested
                .iter()
                .map(|&offset| ledger.locate(0, origin, 0, heavy.lease(), offset))
                .collect(),
        )
    }
    #[test]
    fn multiline_first_control_point_and_real_physical_lf_are_certified() {
        let (class, rows) = probe("\tif (\n\t\t!a & b\n\t)\n", &[4, 5], 0);
        assert_eq!(class, 3);
        assert_eq!(
            rows[0].unwrap(),
            OriginalByteCursor {
                line: 1,
                byte_column: 5,
                source_offset: 4
            }
        );
        assert_eq!(rows[1].unwrap().source_offset, 5);
    }
    #[test]
    fn interior_cr_bytes_preserve_original_columns_without_literal_reparsing() {
        let raw = "\tlist(\"\r\"); !a & b\n";
        let offset = raw.find('!').unwrap();
        let (class, rows) = probe(raw, &[offset], 0);
        assert_eq!(class, 3);
        assert_eq!(rows[0].unwrap().byte_column, offset + 1);
    }
    #[test]
    fn explicit_join_certifies_only_exact_prefix_before_transformation() {
        let raw = concat!("\tlist(1); ", "\\", "\n", "\t!a & b\n");
        let (class, rows) = probe(raw, &[1, 10, 11], 0);
        assert_eq!(class, 3);
        assert_eq!(rows[0].unwrap().byte_column, 2);
        // Byte10 is the FIRST differing byte: native TAB vs original slash.
        assert!(
            rows[1].is_err(),
            "the divergence boundary itself is not proof"
        );
        assert!(rows[2].is_err());
    }
    #[test]
    fn later_physical_part_uses_its_own_exact_original_row() {
        let (class, rows) = probe("\tif (\n\t\t!a & b\n\t)\n", &[2], 1);
        assert_eq!(class, 3);
        assert_eq!(
            rows[0].unwrap(),
            OriginalByteCursor {
                line: 2,
                byte_column: 3,
                source_offset: 8
            }
        );
    }
}

#[cfg(test)]
mod physical_layout_extra_tests {
    use super::*;
    use crate::AcquiredSource;
    use std::path::PathBuf;
    fn locate(raw: &str, ordinal: usize, at: usize) -> OriginalByteCursor {
        let heavy = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), ());
        let line = heavy.prepared().lines().iter().next().unwrap();
        let part = line
            .text
            .trim_end_matches(['\r', '\n'])
            .split('\n')
            .nth(ordinal)
            .unwrap();
        let mut builder =
            ByteLayoutBuilder::from_bindings(vec![Some(heavy.lease().clone())].into());
        builder.record_part(
            0,
            Some(line),
            line.source_line,
            line.source_span,
            part,
            false,
            ordinal,
        );
        let ledger = builder.finish();
        let path = Arc::new(PathBuf::from("source.dm"));
        let traces = Arc::new(Vec::new());
        let origin = ExpandedOriginView {
            origin: super::super::origin_arena::OriginView {
                output_line: ordinal + 1,
                path: &path,
                source_line: 1,
            },
            output_span: Span::new(0, part.len() + 1),
            source_span: line.source_span,
            region: 0,
            macro_expansions: &traces,
        };
        ledger.locate(0, origin, 0, heavy.lease(), at).unwrap()
    }
    #[test]
    fn constructor_argument_is_on_its_real_physical_line() {
        let raw = "new req_bool(\n    req_bool(1))\n";
        let point = locate(raw, 1, 4);
        assert_eq!((point.line, point.byte_column), (2, 5));
        assert_eq!(point.source_offset, raw.find("    req_bool").unwrap() + 4);
    }
    #[test]
    fn identical_text_in_later_parts_uses_ordinal_not_text_search() {
        let raw = "list(\n\t\"x\",\n\t\"x\",\n\t\"x\")\n";
        let point = locate(raw, 2, 1);
        assert_eq!(
            (point.line, point.byte_column, point.source_offset),
            (3, 2, 13)
        );
    }
    #[test]
    fn utf8_comment_mask_and_tabs_keep_later_line_byte_widths() {
        let raw = "list(\n\t/* é漢 */ !a & b\n)\n";
        let line = raw.split('\n').nth(1).unwrap();
        let offset = line.find('!').unwrap();
        let point = locate(raw, 1, offset);
        assert_eq!((point.line, point.byte_column), (2, offset + 1));
        assert_eq!(point.source_offset, raw.find('!').unwrap());
    }
    #[test]
    fn empty_physical_literal_line_has_exact_real_lf() {
        let raw = "var/t={\"one\n\nthree\"}\n";
        let point = locate(raw, 1, 0);
        assert_eq!((point.line, point.byte_column), (2, 1));
        assert_eq!(raw.as_bytes()[point.source_offset], b'\n');
    }
}

#[cfg(test)]
mod macro_line_receipt_tests {
    use super::*;
    use crate::{AcquiredSource, SourceProvider, SourceText};
    use std::{path::Path, sync::Mutex};
    struct Source(AcquiredSource);
    impl SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("original acquisition required".into())
        }
        fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(&self, _: &Path, text: &SourceText) -> Option<AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    #[derive(Default)]
    struct DiskMemo(Mutex<Vec<Arc<super::super::region_memo::ExpansionRecord>>>);
    impl super::super::region_memo::ExpansionMemo for DiskMemo {
        fn candidates(&self, key: u128) -> Vec<Arc<super::super::region_memo::ExpansionRecord>> {
            self.0
                .lock()
                .unwrap()
                .iter()
                .filter(|record| record.key() == key)
                .cloned()
                .collect()
        }
        fn insert(&self, record: Arc<super::super::region_memo::ExpansionRecord>) {
            let encoded = record.to_bytes().unwrap();
            let decoded = super::super::region_memo::ExpansionRecord::from_bytes(&encoded).unwrap();
            self.0.lock().unwrap().push(Arc::new(decoded));
        }
    }
    fn fixture(raw: &str) -> (Source, DirectivePlan) {
        let source = Source(AcquiredSource::from_original_bytes(
            raw.as_bytes().to_vec(),
            (),
        ));
        let plan =
            crate::regions::plan_regions(Path::new("macro.dm"), &source, &Default::default());
        assert!(plan.diagnostics.is_empty());
        (source, plan)
    }
    fn query(
        expanded: &super::super::ExpandedRegions,
        plan: &DirectivePlan,
        lease: &SourceAcquisitionLease,
    ) -> Result<usize, &'static str> {
        let offset = expanded.text.find("!a").unwrap();
        let index = expanded
            .origins
            .partition_point(|row| row.output_span.end <= offset);
        let row = expanded.origins.get(index).unwrap();
        let occurrence = plan.regions[row.region].occurrence;
        assert!(!row.macro_expansions.is_empty());
        assert!(
            expanded
                .origins
                .original_byte_cursor(index, occurrence, lease, offset)
                .is_err(),
            "LINE-only receipt must not invent a column"
        );
        expanded
            .origins
            .original_policy_line(index, occurrence, lease, offset)
    }
    #[test]
    fn direct_single_physical_macro_line_has_bound_line_only_receipt() {
        let raw = "#define WRAP(x) x\n/proc/p(a,b)\n\tWRAP(!a & b)\n";
        let (source, plan) = fixture(raw);
        let expanded = crate::regions::expand_regions_text(&plan, 1);
        assert!(expanded.diagnostics.is_empty());
        assert_eq!(query(&expanded, &plan, source.0.lease()).unwrap(), 3);
        let foreign = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), ());
        assert!(query(&expanded, &plan, foreign.lease()).is_err());
        let reissued = source.0.reissued(());
        assert!(query(&expanded, &plan, reissued.lease()).is_err());
    }
    #[test]
    fn held_macro_with_same_first_single_line_span_has_no_receipt() {
        let raw = "#define WRAP(x) x\n/proc/p(a,b)\n\tWRAP(\n#if 1\n\t\t!a & b)\n#endif\n";
        let (source, plan) = fixture(raw);
        let first = plan
            .regions
            .iter()
            .flat_map(|region| region.segments.iter())
            .flat_map(|segment| segment.lines.iter())
            .find(|line| line.text.contains("WRAP("))
            .unwrap();
        assert_eq!(
            first.source_lines, 1,
            "fixture must exercise held join, not only a multiline PreparedLine"
        );
        let expanded = crate::regions::expand_regions_text(&plan, 1);
        assert!(expanded.diagnostics.is_empty());
        assert!(query(&expanded, &plan, source.0.lease()).is_err());
    }
    #[test]
    fn multiline_prepared_macro_never_gains_line_only_receipt() {
        let (source, plan) = fixture("#define WRAP(x) x\n/proc/p(a,b)\n\tWRAP(\n\t\t!a & b)\n");
        let expanded = crate::regions::expand_regions_text(&plan, 1);
        assert!(expanded.diagnostics.is_empty());
        assert!(query(&expanded, &plan, source.0.lease()).is_err());
    }
    #[test]
    fn disk_expansion_fact_is_rebound_to_current_lease_not_old_authority() {
        let raw = "#define WRAP(x) x\n/proc/p(a,b)\n\tWRAP(!a & b)\n";
        let memo = DiskMemo::default();
        let (old, plan) = fixture(raw);
        let cold = crate::regions::expand_regions_text_with_memo(&plan, 1, &memo);
        assert_eq!(query(&cold, &plan, old.0.lease()).unwrap(), 3);
        let (current, plan) = fixture(raw);
        let warm = crate::regions::expand_regions_text_with_memo(&plan, 1, &memo);
        assert_eq!(query(&warm, &plan, current.0.lease()).unwrap(), 3);
        assert!(query(&warm, &plan, old.0.lease()).is_err());
    }
}

#[cfg(test)]
mod crlf_terminator_tests {
    use super::*;
    use crate::AcquiredSource;
    use std::path::PathBuf;
    fn point(raw: &str, at: usize) -> Result<OriginalByteCursor, &'static str> {
        let heavy = AcquiredSource::from_original_bytes(raw.as_bytes().to_vec(), ());
        let line = heavy.prepared().lines().iter().next().unwrap();
        let part = body_without_line_ending(line.text.as_ref());
        let mut builder =
            ByteLayoutBuilder::from_bindings(vec![Some(heavy.lease().clone())].into());
        builder.record(
            0,
            Some(line),
            line.source_line,
            line.source_span,
            part,
            false,
        );
        let ledger = builder.finish();
        let path = Arc::new(PathBuf::from("crlf.dm"));
        let traces = Arc::new(Vec::new());
        let origin = ExpandedOriginView {
            origin: super::super::origin_arena::OriginView {
                output_line: 1,
                path: &path,
                source_line: 1,
            },
            output_span: Span::new(0, part.len() + 1),
            source_span: line.source_span,
            region: 0,
            macro_expansions: &traces,
        };
        ledger.locate(0, origin, 0, heavy.lease(), at)
    }
    #[test]
    fn real_crlf_terminator_maps_to_original_lf_with_pinned_byte_column() {
        let body = "\tvar/SpacemanDMM_private/value";
        assert_eq!(body.len(), 30);
        let raw = format!("{body}\r\n");
        let at = point(&raw, body.len()).unwrap();
        assert_eq!((at.line, at.byte_column, at.source_offset), (1, 32, 31));
        assert_eq!(raw.as_bytes()[at.source_offset], b'\n');
        let before = point(&raw, body.len() - 1).unwrap();
        assert_eq!(
            (before.byte_column, before.source_offset),
            (body.len(), body.len() - 1)
        );
    }
    #[test]
    fn no_lf_and_lone_cr_never_gain_synthetic_terminator_authority() {
        let body = "var/grouped";
        assert!(point(body, body.len()).is_err());
        assert!(point(&format!("{body}\r"), body.len()).is_err());
        let lf = point(&format!("{body}\n"), body.len()).unwrap();
        assert_eq!(
            (lf.byte_column, lf.source_offset),
            (body.len() + 1, body.len())
        );
    }
    #[test]
    fn utf8_comment_mask_and_tabs_keep_body_width_before_real_crlf() {
        let body = "\tvar/value /* é漢 */";
        let raw = format!("{body}\r\n");
        let at = point(&raw, body.len()).unwrap();
        assert_eq!(
            (at.byte_column, at.source_offset),
            (body.len() + 2, body.len() + 1)
        );
        assert_eq!(raw.as_bytes()[at.source_offset], b'\n');
    }
}
