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
    Compact(OriginalMacroRows<u32>),
    Wide(OriginalMacroRows<usize>),
}

impl LineStarts {
    fn new(source_len: usize, a: &SettingAdmission<'_>) -> io::Result<Self> {
        if usize::BITS > u32::BITS && u32::try_from(source_len).is_ok() {
            Ok(Self::Compact(OriginalMacroRows::new(a)?))
        } else {
            Ok(Self::Wide(OriginalMacroRows::new(a)?))
        }
    }

    fn push(&mut self, start: usize, a: &SettingAdmission<'_>) -> io::Result<()> {
        match self {
            Self::Compact(starts) => starts.push(
                u32::try_from(start).map_err(|_| io::ErrorKind::InvalidInput)?,
                a,
            ),
            Self::Wide(starts) => starts.push(start, a),
        }
    }

    fn at_or_before(&self, offset: usize) -> Option<(usize, usize)> {
        match self {
            Self::Compact(starts) => actual_line_start(starts.as_slice(), offset, |start| start as usize),
            Self::Wide(starts) => actual_line_start(starts.as_slice(), offset, |start| start),
        }
    }

    fn get(&self, index: usize) -> Option<usize> {
        match self {
            Self::Compact(starts) => starts.as_slice().get(index).map(|&start| start as usize),
            Self::Wide(starts) => starts.as_slice().get(index).copied(),
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
impl OriginalRawPointIndex{
 pub(super) fn new(bytes:&[u8],a:&SettingAdmission<'_>)->io::Result<Self>{let bom=if bytes.starts_with(&[0xef,0xbb,0xbf]){3}else{0};let mut starts=LineStarts::new(bytes.len(),a)?;starts.push(bom,a)?;Ok(Self{starts,indexed:bom,bom,scanned_line_end:0})}
 /// Index only actual demanded byte frontier; later earlier token spans use
 /// this SAME line roster without rescanning or a separate source store.
 pub(super) fn at(&mut self,bytes:&[u8],offset:usize,a:&SettingAdmission<'_>)->io::Result<OriginalRawPoint>{
  if offset<self.bom||offset>bytes.len()||self.indexed>bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}
  while self.indexed<offset{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if bytes[self.indexed]==b'\n'{self.starts.push(self.indexed+1,a)?;}self.indexed+=1;}
  let (line,start)=self.starts.at_or_before(offset).ok_or(io::ErrorKind::InvalidData)?;
  Ok(OriginalRawPoint{line,column:offset-start+1})
 }
 pub(super) fn line_start(&self,line:usize)->Option<usize>{self.starts.get(line.checked_sub(1)?)}
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
  while end<bytes.len(){
   poll()?;
   let byte=bytes[end];
   end+=1;
   if byte==b'\n'{break}
  }
  self.scanned_line_end=end;
  Ok(end)
 }
 pub(super) fn notice(&mut self,bytes:&[u8],notice:OriginalLexicalNoticePoint,a:&SettingAdmission<'_>)->io::Result<OriginalRawPoint>{
  match notice.kind(){OriginalLexicalPointKind::ConsumedByte=>{if notice.offset()>=bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}self.at(bytes,notice.offset(),a)},OriginalLexicalPointKind::TrackerAtEof=>{if notice.offset()!=bytes.len(){return Err(io::ErrorKind::InvalidInput.into())}let mut point=self.at(bytes,bytes.len(),a)?;point.column=point.column.checked_sub(1).ok_or(io::ErrorKind::InvalidData)?;Ok(point)}}
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_raw_point_roster_preserves_byte_columns_bom_crlf_backward_spans_and_eof_zero_column(){
  let bytes=b"\xef\xbb\xbf\xc3\xa9\r\nx\n";let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut index=OriginalRawPointIndex::new(bytes,&a).unwrap();assert_eq!(index.at(bytes,3,&a).unwrap(),OriginalRawPoint{line:1,column:1});assert_eq!(index.at(bytes,4,&a).unwrap(),OriginalRawPoint{line:1,column:2});assert_eq!(index.at(bytes,7,&a).unwrap(),OriginalRawPoint{line:2,column:1});assert_eq!(index.at(bytes,5,&a).unwrap(),OriginalRawPoint{line:1,column:3});assert_eq!(index.notice(bytes,OriginalLexicalNoticePoint::eof(bytes.len()),&a).unwrap(),OriginalRawPoint{line:3,column:0});drop(index);assert_eq!(used.load(Ordering::Acquire),0);
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
     let used=Arc::new(AtomicUsize::new(0));
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
     assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]
 fn actual_source_line_starts_stay_exact_under_compact_allocation_cap() {
     let bytes = b"x\n".repeat(2048);
     let used = Arc::new(AtomicUsize::new(0));
     // The largest exact overlap is 2,048 old + 4,096 new four-byte starts.
     // This cap cannot admit the former eight-byte growth on 64-bit.
     let a = SettingAdmission::new(&used, 32 << 10, &|| Ok(()));
     let mut index = OriginalRawPointIndex::new(&bytes, &a).unwrap();
     assert_eq!(index.notice(&bytes, OriginalLexicalNoticePoint::eof(bytes.len()), &a).unwrap(),
         OriginalRawPoint { line: 2049, column: 0 });
     assert_eq!(index.at(&bytes, 1023, &a).unwrap(), OriginalRawPoint { line: 512, column: 2 });
     assert_eq!(index.line_start(1), Some(0));
     assert_eq!(index.line_start(2049), Some(bytes.len()));
     assert_eq!(index.line_start(2050), None);
     assert_eq!(used.load(Ordering::Acquire), 4096 * std::mem::size_of::<u32>());
     drop(index);
     assert_eq!(used.load(Ordering::Acquire), 0);
 }

 #[cfg(target_pointer_width = "64")]
 #[test]
 fn declared_raw_width_uses_exact_wide_fallback_beyond_u32_without_allocating_source() {
     let used = Arc::new(AtomicUsize::new(0));
     let a = SettingAdmission::new(&used, 1024, &|| Ok(()));
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
     assert_eq!(used.load(Ordering::Acquire), 0);
 }
}
