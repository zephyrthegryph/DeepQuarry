//! Sparse raw/decoded coordinate DATA from the SAME native decoder.
//! This is neither source identity nor acquisition authority. The actual frame
//! authenticates its raw/decoded loans and retains these rows under its own
//! admitted storage. A failed visitor must discard partial rows; only success
//! returns the completed geometry. No allocation is performed by this module.
use super::{visit_decoded_source, DecodedSourcePiece};
use dm_syntax::Span;
use std::io;

#[derive(Clone, Copy, Debug)]
pub(crate) struct DecodedPointException { raw: Span, decoded: Span }
impl DecodedPointException {
    pub(crate) fn raw(self) -> Span { self.raw }
    pub(crate) fn decoded(self) -> Span { self.decoded }
}
#[derive(Debug)]
pub(crate) struct DecodedPointGeometry {
    original_len: usize,
    decoded_len: usize,
    exceptions: usize,
}
impl DecodedPointGeometry {
    pub(crate) fn original_len(&self) -> usize { self.original_len }
    pub(crate) fn decoded_len(&self) -> usize { self.decoded_len }
    /// Caller lends the SAME authenticated decoded backing and ordered rows it
    /// stored during the successful visitor. Lengths are geometry checks, not
    /// authority. Lookup never scans or decodes the original source again.
    pub(crate) fn decoded_point(&self, decoded: &str, rows: &[DecodedPointException], raw_point: usize) -> Option<usize> {
        if decoded.len() != self.decoded_len || rows.len() != self.exceptions || raw_point > self.original_len { return None; }
        let end = rows.partition_point(|row| row.raw.start <= raw_point);
        let point = if end == 0 { raw_point } else {
            let row = rows[end - 1];
            if raw_point == row.raw.start { row.decoded.start }
            else if raw_point < row.raw.end { return None; }
            else { raw_point.checked_sub(row.raw.end)?.checked_add(row.decoded.end)? }
        };
        decoded.is_char_boundary(point).then_some(point)
    }
}
// An exact byte loan over this &str already has UTF-8 validity and identical
// byte geometry. Equal content or length alone cannot use this shortcut.
// BOM removal would still change the decoded coordinate space.
fn same_plain_utf8_view(original: &[u8], decoded: &str) -> bool {
    std::ptr::eq(original, decoded.as_bytes()) && !original.starts_with(b"\xef\xbb\xbf")
}

/// Validate against the actual existing decoder and emit only BOM/legacy-byte
/// exceptions. The caller must admit each row BEFORE retaining it. Ordinary
/// UTF8 needs no row; its byte deltas and character boundaries are preserved.
pub(crate) fn visit_decoded_point_exceptions(
    original: &[u8], decoded: &str,
    checkpoint: &mut dyn FnMut() -> io::Result<()>,
    emit: &mut dyn FnMut(DecodedPointException) -> io::Result<()>,
) -> io::Result<DecodedPointGeometry> {
    checkpoint()?;
    if same_plain_utf8_view(original, decoded) {
        // The decoder would visit exactly one UTF-8 piece if nonempty.
        // Preserve that piece's checkpoint and the final geometry checkpoint
        // in addition to the entry checkpoint above.
        if !original.is_empty() {
            checkpoint()?;
        }
        checkpoint()?;
        return Ok(DecodedPointGeometry {
            original_len: original.len(), decoded_len: decoded.len(), exceptions: 0,
        });
    }
    let mut raw_end = 0;
    let mut decoded_end = 0;
    let mut exceptions = 0usize;
    visit_decoded_source(original, |piece| -> io::Result<()> {
        checkpoint()?;
        let exceptional = match piece {
            DecodedSourcePiece::Bom { raw } => {
                if raw.start != raw_end || decoded_end != 0 { return Err(io::ErrorKind::InvalidData.into()); }
                raw_end = raw.end;
                Some(DecodedPointException { raw, decoded: Span::new(0, 0) })
            }
            DecodedSourcePiece::Utf8 { raw, decoded: range, text } => {
                if raw.start != raw_end || range.start != decoded_end || decoded.get(range.range()) != Some(text) {
                    return Err(io::ErrorKind::InvalidData.into());
                }
                raw_end = raw.end; decoded_end = range.end; None
            }
            DecodedSourcePiece::LegacyByte { raw, decoded: range, value } => {
                let mut bytes = [0u8; 4];
                let expected: &str = value.encode_utf8(&mut bytes);
                if raw.start != raw_end || range.start != decoded_end || decoded.get(range.range()) != Some(expected) {
                    return Err(io::ErrorKind::InvalidData.into());
                }
                raw_end = raw.end; decoded_end = range.end;
                Some(DecodedPointException { raw, decoded: range })
            }
        };
        if let Some(row) = exceptional {
            exceptions = exceptions.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            emit(row)?;
        }
        Ok(())
    })?;
    checkpoint()?;
    if raw_end != original.len() || decoded_end != decoded.len() { return Err(io::ErrorKind::InvalidData.into()); }
    Ok(DecodedPointGeometry { original_len: original.len(), decoded_len: decoded.len(), exceptions })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source_decode::decode_source_bytes;
    #[test]
    fn exact_plain_utf8_geometry_uses_the_same_checkpoints_and_char_boundaries() {
        use std::cell::Cell;
        for text in ["", "plain\r\n", "café💩\r\nend"] {
            let backing = text.to_owned();
            let foreign = text.as_bytes().to_vec();
            assert!(same_plain_utf8_view(backing.as_bytes(), &backing));
            if !text.is_empty() {
                assert!(!same_plain_utf8_view(&foreign, &backing),
                    "an independent equal allocation is not the same byte loan");
            }

            let expected_calls = if text.is_empty() { 2 } else { 3 };
            for raw in [backing.as_bytes(), foreign.as_slice()] {
                let calls = Cell::new(0);
                let shape = visit_decoded_point_exceptions(raw, &backing, &mut || {
                    calls.set(calls.get() + 1);
                    Ok(())
                }, &mut |_| panic!("plain UTF-8 has no exception row")).unwrap();
                assert_eq!(calls.get(), expected_calls);
                assert_eq!(shape.original_len(), text.len());
                assert_eq!(shape.decoded_len(), text.len());
                for offset in 0..=text.len() + 1 {
                    assert_eq!(shape.decoded_point(&backing, &[], offset),
                        text.is_char_boundary(offset).then_some(offset));
                }
                for stop in 1..=expected_calls {
                    calls.set(0);
                    let error = visit_decoded_point_exceptions(raw, &backing, &mut || {
                        calls.set(calls.get() + 1);
                        if calls.get() == stop { Err(io::Error::from_raw_os_error(1450)) }
                        else { Ok(()) }
                    }, &mut |_| panic!("no exception can preempt this actual failure")).unwrap_err();
                    assert_eq!(error.raw_os_error(), Some(1450));
                    assert_eq!(calls.get(), stop);
                }
            }
        }
    }

    #[test]
    fn bom_and_legacy_geometry_still_require_the_actual_decoder() {
        let unstripped = "\u{feff}plain".to_owned();
        assert!(!same_plain_utf8_view(unstripped.as_bytes(), &unstripped),
            "an identical str view does not prove BOM-free geometry");
        assert!(visit_decoded_point_exceptions(unstripped.as_bytes(), &unstripped,
            &mut || Ok(()), &mut |_| Ok(())).is_err());

        let raw = b"\xef\xbb\xbfA\xe9\n";
        let decoded = decode_source_bytes(raw);
        assert!(!same_plain_utf8_view(raw, &decoded));
        let mut rows = Vec::new();
        let shape = visit_decoded_point_exceptions(raw, &decoded, &mut || Ok(()),
            &mut |row| { rows.push(row); Ok(()) }).unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].raw(), Span::new(0, 3));
        assert_eq!(rows[0].decoded(), Span::new(0, 0));
        assert_eq!(rows[1].raw(), Span::new(4, 5));
        assert_eq!(rows[1].decoded(), Span::new(1, 3));
        assert_eq!(shape.decoded_point(&decoded, &rows, 2), None);
        assert_eq!(shape.decoded_point(&decoded, &rows, 5), Some(3));
        assert_eq!(shape.decoded_point(&decoded, &rows, raw.len()), Some(decoded.len()));
    }

    #[test]
    fn sparse_point_geometry_preserves_bom_legacy_utf8_boundaries_and_actual_eof() {
        for raw in [&b""[..], &b"plain"[..], &b"\xef\xbb\xbf"[..], &b"\xef\xbb\xbfA\x80\xc3\xa9\xffZ"[..], &b"\xf0\x9f\x92\xa9!"[..], &b"\xf0\x9f"[..]] {
            let decoded = decode_source_bytes(raw); let mut rows = Vec::new();
            let shape = visit_decoded_point_exceptions(raw, &decoded, &mut || Ok(()), &mut |row| { rows.push(row); Ok(()) }).unwrap();
            assert_eq!(shape.original_len(), raw.len()); assert_eq!(shape.decoded_len(), decoded.len());
            let mut expected = std::collections::BTreeMap::new(); expected.insert(0, 0);
            visit_decoded_source(raw, |piece| -> Result<(), ()> { match piece {
                DecodedSourcePiece::Bom { raw } => { expected.insert(raw.end, 0); }
                DecodedSourcePiece::Utf8 { raw, decoded, text } => { for (at, _) in text.char_indices() { expected.insert(raw.start + at, decoded.start + at); } expected.insert(raw.end, decoded.end); }
                DecodedSourcePiece::LegacyByte { raw, decoded, .. } => { expected.insert(raw.start, decoded.start); expected.insert(raw.end, decoded.end); }
            } Ok(()) }).unwrap();
            for point in 0..=raw.len()+1 { assert_eq!(shape.decoded_point(&decoded, &rows, point), expected.get(&point).copied(), "raw={raw:?} point={point}"); }
            for row in &rows { assert!(row.raw().end > row.raw().start); assert!(row.decoded().end >= row.decoded().start); }
        }
    }
    #[test]
    fn sparse_point_geometry_requires_actual_decoded_values_and_complete_rows() {
        let mut rows = Vec::new();
        assert!(visit_decoded_point_exceptions(b"A\x80B", "A?B", &mut || Ok(()), &mut |row| { rows.push(row); Ok(()) }).is_err());
        rows.clear(); let raw = b"A\x80B"; let decoded = decode_source_bytes(raw);
        let shape = visit_decoded_point_exceptions(raw, &decoded, &mut || Ok(()), &mut |row| { rows.push(row); Ok(()) }).unwrap();
        assert_eq!(shape.decoded_point(&decoded, &rows, raw.len()), Some(decoded.len()));
        assert_eq!(shape.decoded_point(&decoded, &[], raw.len()), None);
        assert_eq!(shape.decoded_point("wrong-length", &rows, 0), None);
    }
    #[test]
    fn sparse_point_geometry_preserves_first_emitter_io_and_checkpoint_cancellation() {
        let raw = b"\x80\xffX"; let decoded = decode_source_bytes(raw); let mut calls = 0;
        let error = visit_decoded_point_exceptions(raw, &decoded, &mut || Ok(()), &mut |_| { calls += 1; Err(io::Error::from_raw_os_error(1450)) }).unwrap_err();
        assert_eq!(error.raw_os_error(), Some(1450)); assert_eq!(calls, 1);
        let error = visit_decoded_point_exceptions(raw, &decoded, &mut || Err(io::ErrorKind::Interrupted.into()), &mut |_| panic!("cancel before emit")).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert!(visit_decoded_point_exceptions(raw, &decoded, &mut || Ok(()), &mut |_| Ok(())).is_ok());
    }
}
