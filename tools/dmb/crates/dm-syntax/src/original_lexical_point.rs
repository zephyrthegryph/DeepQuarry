//! Actual raw lexer location DATA, not source/EOF/model authority. An EOF read
//! differs from the next-byte boundary (old tracker retains column or advances
//! to column0 after LF); current physical frame resolves this exact descriptor.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalLexicalPointKind{ConsumedByte,TrackerAtEof}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalLexicalNoticePoint{offset:usize,kind:OriginalLexicalPointKind}
impl OriginalLexicalNoticePoint{pub fn consumed(offset:usize)->Self{Self{offset,kind:OriginalLexicalPointKind::ConsumedByte}}pub fn eof(offset:usize)->Self{Self{offset,kind:OriginalLexicalPointKind::TrackerAtEof}}pub fn offset(self)->usize{self.offset}pub fn kind(self)->OriginalLexicalPointKind{self.kind}}
