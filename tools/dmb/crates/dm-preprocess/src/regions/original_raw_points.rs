//! Physical ORIGINAL byte coordinates over the actual current raw loan. This
//! resource-only index is not source/EOF/model authority; no decoded text used.
use crate::macro_expansion::OriginalMacroRows;use dm_syntax::{SettingAdmission,OriginalLexicalNoticePoint,OriginalLexicalPointKind};use std::io;
pub(super) struct OriginalRawPointIndex {
    starts: LineStarts,
    indexed: usize,
    bom: usize,
    // A physical-row query may scan ahead through its own line without
    // issuing the next line's point or allocating its start index early.
    scanned_line_end: usize,
}

// One width per opened source, chosen before its first allocation. Each start
// is the byte after a consumed LF, so it never exceeds the original byte length.
enum LineStarts {
    Short(OriginalMacroRows<u16>),
    Compact(OriginalMacroRows<u32>),
    Wide(OriginalMacroRows<usize>),
}

impl LineStarts {
    fn new(source_len: usize, a: &SettingAdmission<'_>) -> io::Result<Self> {
        if usize::BITS > u16::BITS && u16::try_from(source_len).is_ok() {
            Ok(Self::Short(OriginalMacroRows::new(a)?))
        } else if usize::BITS > u32::BITS && u32::try_from(source_len).is_ok() {
            Ok(Self::Compact(OriginalMacroRows::new(a)?))
        } else {
            Ok(Self::Wide(OriginalMacroRows::new(a)?))
        }
    }

    fn push(&mut self, start: usize, a: &SettingAdmission<'_>) -> io::Result<()> {
        match self {
            Self::Short(starts) => starts.push(
                u16::try_from(start).map_err(|_| io::ErrorKind::InvalidInput)?,
                a,
            ),
            Self::Compact(starts) => starts.push(
                u32::try_from(start).map_err(|_| io::ErrorKind::InvalidInput)?,
                a,
            ),
            Self::Wide(starts) => starts.push(start, a),
        }
    }

    fn at_or_before(&self, offset: usize) -> Option<(usize, usize)> {
        match self {
            Self::Short(starts) => actual_line_start(starts.as_slice(), offset, usize::from),
            Self::Compact(starts) => actual_line_start(starts.as_slice(), offset, |start| start as usize),
            Self::Wide(starts) => actual_line_start(starts.as_slice(), offset, |start| start),
        }
    }

    fn get(&self, index: usize) -> Option<usize> {
        match self {
            Self::Short(starts) => starts.as_slice().get(index).map(|&start| usize::from(start)),
            Self::Compact(starts) => starts.as_slice().get(index).map(|&start| start as usize),
            Self::Wide(starts) => starts.as_slice().get(index).copied(),
        }
    }
}
#[cfg(debug_assertions)]
#[derive(Debug, Default)]
pub(super) struct PhysicalLineStartCensus {
    short_occurrences: usize,
    compact_occurrences: usize,
    wide_occurrences: usize,
    rows: usize,
    short_bytes: usize,
    compact_bytes: usize,
    wide_bytes: usize,
    saved_short_bytes: usize,
}

impl OriginalRawPointIndex {
    #[cfg(debug_assertions)]
    pub(super) fn record_line_starts(&self, census: &mut PhysicalLineStartCensus) {
        let (len, capacity, width, occurrences, bytes) = match &self.starts {
            LineStarts::Short(rows) => (rows.len(), rows.capacity(), 2, &mut census.short_occurrences, &mut census.short_bytes),
            LineStarts::Compact(rows) => (rows.len(), rows.capacity(), 4, &mut census.compact_occurrences, &mut census.compact_bytes),
            LineStarts::Wide(rows) => (rows.len(), rows.capacity(), std::mem::size_of::<usize>(), &mut census.wide_occurrences, &mut census.wide_bytes),
        };
        *occurrences += 1;
        *bytes += capacity * width;
        census.rows += len;
        // The prior 32/64-bit representation had four bytes at the same
        // logical capacity. Measure only this changed allocation.
        if width == 2 {
            census.saved_short_bytes += capacity * 2;
        }
    }
}

// The previous demand has already extended the real starts roster through
// offset. Its last entry therefore answers every current/forward point.
// Historical macro-definition offsets use the unchanged full search.
fn actual_line_start<T: Copy>(starts: &[T], offset: usize, decode: impl Fn(T) -> usize) -> Option<(usize, usize)> {
    let last = decode(*starts.last()?);
    if last <= offset {
        return Some((starts.len(), last));
    }
    let count = starts.partition_point(|&start| decode(start) <= offset);
    Some((count, decode(*starts.get(count.checked_sub(1)?)?)))
}

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(super) struct OriginalRawPoint{pub(super) line:usize,pub(super) column:usize}
const MAX_PHYSICAL_SCAN: usize = 64;

impl OriginalRawPointIndex{
 pub(super) fn new(bytes:&[u8],a:&SettingAdmission<'_>)->io::Result<Self>{let bom=if bytes.starts_with(&[0xef,0xbb,0xbf]){3}else{0};let mut starts=LineStarts::new(bytes.len(),a)?;starts.push(bom,a)?;Ok(Self{starts,indexed:bom,bom,scanned_line_end:0})}
 /// Index only actual demanded byte frontier; later earlier token spans use
 /// this SAME line roster without rescanning or a separate source store.
 pub(super) fn at(&mut self,bytes:&[u8],offset:usize,a:&SettingAdmission<'_>)->io::Result<OriginalRawPoint>{
  if offset<self.bom||offset>bytes.len()||self.indexed>bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}
  let width = if a.uses_bounded_static_lookup_checkpoints() { MAX_PHYSICAL_SCAN } else { 1 };
  while self.indexed < offset {
   a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
   let end = offset.min(self.indexed.saturating_add(width));
   if let Some(lf) = bytes[self.indexed..end].iter().position(|&byte| byte == b'\n') {
    let start = self.indexed + lf + 1;
    self.starts.push(start, a)?;
    self.indexed = start;
   } else {
    self.indexed = end;
   }
  }
  let (line,start)=self.starts.at_or_before(offset).ok_or(io::ErrorKind::InvalidData)?;
  Ok(OriginalRawPoint{line,column:offset-start+1})
 }
 pub(super) fn line_start(&self,line:usize)->Option<usize>{self.starts.get(line.checked_sub(1)?)}

 /// A repeated query over this exact byte view has no unissued scanning
 /// only when the requested point and both physical boundaries remain known.
 pub(super) fn contains_issued_row(&self,bytes_len:usize,offset:usize,line:usize,row:dm_syntax::Span)->bool{
  if offset<self.bom||offset>self.indexed||self.indexed>bytes_len||self.line_start(line)!=Some(row.start){return false}
  let end=self.starts.get(line).or_else(||(self.scanned_line_end>self.indexed).then_some(self.scanned_line_end))
   .or_else(||(self.indexed==bytes_len).then_some(self.indexed));
  end==Some(row.end)&&row.end<=bytes_len
 }

 /// End of an issued line on this index's SAME raw acquisition.
 pub(super) fn line_end_using(&mut self,bytes:&[u8],line:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  let poll=||a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e));
  poll()?;
  if self.indexed>bytes.len()||self.line_start(line).is_none(){return Err(io::ErrorKind::InvalidInput.into())}
  // Old lines already have their following start. Otherwise this is the
  // one current indexed line, and a cached end ahead of indexed is its end.
  if let Some(end)=self.starts.get(line){return Ok(end)}
  if self.scanned_line_end>self.indexed {
   if self.scanned_line_end>bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}
   return Ok(self.scanned_line_end)
  }
  let mut end=self.indexed;
  let width = if a.uses_bounded_static_lookup_checkpoints() { MAX_PHYSICAL_SCAN } else { 1 };
  while end<bytes.len(){
   poll()?;
   let next = bytes.len().min(end.saturating_add(width));
   if let Some(lf) = bytes[end..next].iter().position(|&byte| byte == b'\n') {
    end += lf + 1;
    break;
   }
   end = next;
  }
  self.scanned_line_end=end;
  Ok(end)
 }
 pub(super) fn notice(&mut self,bytes:&[u8],notice:OriginalLexicalNoticePoint,a:&SettingAdmission<'_>)->io::Result<OriginalRawPoint>{
  match notice.kind(){OriginalLexicalPointKind::ConsumedByte=>{if notice.offset()>=bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}self.at(bytes,notice.offset(),a)},OriginalLexicalPointKind::TrackerAtEof=>{if notice.offset()!=bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}let mut point=self.at(bytes,bytes.len(),a)?;point.column=point.column.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?;Ok(point)}}
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn actual_raw_point_roster_preserves_byte_columns_bom_crlf_backward_spans_and_eof_zero_column(){
  let bytes=b"\xef\xbb\xbf\xc3\xa9\r\nx\n";let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut index=OriginalRawPointIndex::new(bytes,&a).unwrap();assert_eq!(index.at(bytes,3,&a).unwrap(),OriginalRawPoint{line:1,column:1});assert_eq!(index.at(bytes,4,&a).unwrap(),OriginalRawPoint{line:1,column:2});assert_eq!(index.at(bytes,7,&a).unwrap(),OriginalRawPoint{line:2,column:1});assert_eq!(index.at(bytes,5,&a).unwrap(),OriginalRawPoint{line:1,column:3});assert_eq!(index.notice(bytes,OriginalLexicalNoticePoint::eof(bytes.len()),&a).unwrap(),OriginalRawPoint{line:3,column:0});drop(index);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn bounded_physical_scans_keep_exact_points_and_line_boundaries() {
     let mut bytes = b"\xef\xbb\xbf".to_vec();
     bytes.extend(std::iter::repeat_n(b'x', MAX_PHYSICAL_SCAN + 2));
     bytes.extend_from_slice(b"\r\n\xc3\xa9\nlast");
     let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let ordinary = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
     let bounded = SettingAdmission::new(&used, 1 << 20, &|| Ok(())).with_bounded_static_lookup_checkpoints();
     let mut expected = OriginalRawPointIndex::new(&bytes, &ordinary).unwrap();
     let mut actual = OriginalRawPointIndex::new(&bytes, &bounded).unwrap();
     for offset in [3, 4, MAX_PHYSICAL_SCAN + 7, bytes.len(), 3] {
         let point = expected.at(&bytes, offset, &ordinary).unwrap();
         assert_eq!(actual.at(&bytes, offset, &bounded).unwrap(), point);
         assert_eq!(actual.line_end_using(&bytes, point.line, &bounded).unwrap(),
             expected.line_end_using(&bytes, point.line, &ordinary).unwrap());
     }
 }

 #[test]
 fn current_line_reads_one_issued_start_while_backwards_offsets_stay_exact() {
     use std::cell::Cell;
     let starts = [3u32, 8, 15, 16, 500, 16_384];
     let observed = Cell::new(0);
     let decode = |start: u32| { observed.set(observed.get()+1); start as usize };
     assert_eq!(actual_line_start(&starts, 16_384, decode), Some((6, 16_384)));
     assert_eq!(observed.get(), 1);
     assert_eq!(actual_line_start(&starts, 19_999, decode), Some((6, 16_384)));
     assert_eq!(observed.get(), 2);
     assert_eq!(actual_line_start(&starts, 499, decode), Some((4, 16)));
     assert_eq!(actual_line_start(&starts, 3, decode), Some((1, 3)));
     assert_eq!(actual_line_start(&starts, 2, decode), None);

     let wide = [0usize, 4, usize::MAX - 1];
     assert_eq!(actual_line_start(&wide, usize::MAX, |start| start), Some((3, usize::MAX-1)));
     assert_eq!(actual_line_start(&wide, 4, |start| start), Some((2, 4)));
 }

 #[test]
 fn repeated_physical_rows_reuse_only_the_same_issued_line_end() {
     use std::cell::Cell;

     let source=format!("{}\r\nnext\nend","a".repeat(16_384));
     let bytes=source.as_bytes();
     let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let calls=Cell::new(0);
     let count=||{calls.set(calls.get()+1);Ok(())};
     let a=SettingAdmission::new(&used,1<<20,&count);
     let mut index=OriginalRawPointIndex::new(bytes,&a).unwrap();
     let first=index.at(bytes,3,&a).unwrap();
     let before=calls.get();
     assert_eq!(index.line_end_using(bytes,first.line,&a).unwrap(),16_386);
     assert!(calls.get()-before>16_000,"first demand actually scans the long remainder");
     assert_eq!(index.indexed,3);
     assert_eq!(index.line_start(2),None,"scanning an envelope must not issue a future point");

     for at in [3,6,200,400,7] {
         let point=index.at(bytes,at,&a).unwrap();
         let before=calls.get();
         assert_eq!(index.line_end_using(bytes,point.line,&a).unwrap(),16_386);
         assert_eq!(calls.get()-before,1,"same line must not rescan its suffix");
     }
     let cancelled=||Err(io::Error::from_raw_os_error(1450));
     let stopped=SettingAdmission::new(&used,1<<20,&cancelled);
     assert_eq!(index.line_end_using(bytes,first.line,&stopped).unwrap_err().raw_os_error(),Some(1450));

     let second=index.at(bytes,16_386,&a).unwrap();
     assert_eq!(second,OriginalRawPoint{line:2,column:1});
     assert_eq!(index.line_end_using(bytes,second.line,&a).unwrap(),16_391);
     let before=calls.get();
     assert_eq!(index.line_end_using(bytes,first.line,&a).unwrap(),16_386);
     assert_eq!(calls.get()-before,1,"historical line uses the existing next start");
     let third=index.at(bytes,16_391,&a).unwrap();
     assert_eq!(third,OriginalRawPoint{line:3,column:1});
     assert_eq!(index.line_end_using(bytes,third.line,&a).unwrap(),bytes.len());
     let eof=index.at(bytes,bytes.len(),&a).unwrap();
     assert_eq!(index.line_end_using(bytes,eof.line,&a).unwrap(),bytes.len());
     drop(index);
     assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn actual_source_line_starts_stay_exact_under_compact_allocation_cap() {
     let mut bytes = b"x\n".repeat(2048);
     bytes.resize(65_536, b'x');
     let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
     // The largest exact overlap is 2,048 old + 4,096 new four-byte starts.
     // This cap cannot admit the former eight-byte growth on 64-bit.
     let a = SettingAdmission::new(&used, 32 << 10, &|| Ok(()));
     let mut index = OriginalRawPointIndex::new(&bytes, &a).unwrap();
     assert_eq!(index.notice(&bytes, OriginalLexicalNoticePoint::eof(bytes.len()), &a).unwrap(),
         OriginalRawPoint { line: 2049, column: 61_440 });
     assert_eq!(index.at(&bytes, 1023, &a).unwrap(), OriginalRawPoint { line: 512, column: 2 });
     assert_eq!(index.line_start(1), Some(0));
     assert_eq!(index.line_start(2049), Some(4096));
     assert_eq!(index.line_start(2050), None);
     assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (4096 * std::mem::size_of::<u32>()));
     drop(index);
     assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[cfg(any(target_pointer_width = "32", target_pointer_width = "64"))]
 #[test]
 fn physical_line_starts_use_exact_short_boundary_and_funded_fallback() {
     let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
     let used = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
     let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
     for (length, width) in [(65_535, 2), (65_536, 4)] {
         let mut bytes = vec![b'x'; length];
         bytes[..6].copy_from_slice(b"\xef\xbb\xbfX\r\n");
         bytes[length - 1] = b'\n';
         let mut points = OriginalRawPointIndex::new(&bytes, &a).unwrap();
         assert_eq!(matches!(points.starts, LineStarts::Short(_)), width == 2);
         assert_eq!(points.notice(&bytes, OriginalLexicalNoticePoint::eof(length), &a).unwrap(),
             OriginalRawPoint { line: 3, column: 0 });
         assert_eq!(points.at(&bytes, 4, &a).unwrap(), OriginalRawPoint { line: 1, column: 2 });
         assert_eq!(points.line_end_using(&bytes, 1, &a).unwrap(), 6);
         assert_eq!(points.line_start(3), Some(length));
         assert_eq!(points.line_end_using(&bytes, 2, &a).unwrap(), length);
         assert_eq!(used.load(Ordering::Acquire), fixed + 4 * width);
         drop(points);
         assert_eq!(used.load(Ordering::Acquire), fixed);
     }
 }

 #[cfg(any(target_pointer_width = "32", target_pointer_width = "64"))]
 #[test]
 fn short_physical_start_growth_denial_preserves_preceding_rows() {
     let bytes = b"x\nx\nx\nx\nx\n";
     let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
     let used = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
     // One byte short of holding the previous 4 and candidate 8 u16 rows.
     let a = SettingAdmission::new(&used, fixed + 8 + 16 - 1, &|| Ok(()));
     let mut points = OriginalRawPointIndex::new(bytes, &a).unwrap();
     assert_eq!(points.at(bytes, 6, &a).unwrap(), OriginalRawPoint { line: 4, column: 1 });
     assert_eq!(points.at(bytes, 8, &a).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
     assert_eq!(points.line_start(4), Some(6));
     assert_eq!(points.line_start(5), None);
     assert_eq!(used.load(Ordering::Acquire), fixed + 8);
     drop(points);
     assert_eq!(used.load(Ordering::Acquire), fixed);
 }

 #[cfg(target_pointer_width = "64")]
 #[test]
 fn declared_raw_width_uses_exact_wide_fallback_beyond_u32_without_allocating_source() {
     let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let a = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (1024), &|| Ok(()));
     let boundary = u32::MAX as usize;
     let mut compact = LineStarts::new(boundary, &a).unwrap();
     assert!(matches!(compact, LineStarts::Compact(_)));
     compact.push(boundary, &a).unwrap();
     assert_eq!(compact.get(0), Some(boundary));

     let mut wide = LineStarts::new(boundary + 2, &a).unwrap();
     assert!(matches!(wide, LineStarts::Wide(_)));
     for start in [0, boundary, boundary + 1, boundary + 2] {
         wide.push(start, &a).unwrap();
     }
     assert_eq!(wide.at_or_before(boundary + 1), Some((3, boundary + 1)));
     assert_eq!(wide.get(3), Some(boundary + 2));
     drop((compact, wide));
     assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}
