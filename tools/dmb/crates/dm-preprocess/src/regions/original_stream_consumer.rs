//! Scoped genuine primary/formal consumer boundary. Traits lend actual data;
//! implementing a consumer does not issue source/model/EOF authority.
use dm_syntax::{OriginalPrimaryLiveHeader,OriginalDeclarationHeaderObserver,OriginalHeaderFlow,NativeExpressionTokenDemand,SpanToken,TokenWindow};
use std::io;
/// Genuine original consumer delivery contract; token grammar is shared. The
/// legacy Analyze producer is NOT the direct checker's lazy Iterator: its real
/// PP worker fills 8192-token batches into a 64-batch synchronous handoff.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalDemandDelivery{CheckerLazy0290,AnalyzeBatch8192x64}
/// A borrowed actual stream. All source/token loans in with_current_source end
/// before another pull; default AST/metadata moves into the existing owner.
pub trait OriginalFormalTokenStream:NativeExpressionTokenDemand{
 fn next_header_token(&mut self)->io::Result<Option<dm_syntax::Token>>;
 fn actual_end(&self)->io::Result<Option<super::original_formal_source::OriginalFormalActualEnd<'_>>>{Ok(None)}
 /// Visit actual producer-owned missing-member recoveries, in parser order.
 /// Default issues no recovery; actual loans cannot be fabricated by callers.
 fn visit_member_recoveries(&self,_read:&mut dyn FnMut(super::original_formal_source::OriginalFormalMemberRecovery<'_>)->io::Result<()>)->io::Result<()>{Ok(())}

 /// A genuine numeric head's SAME just-produced neutral fact. No next pull,
 /// spelling parse, foreign occurrence or external source grant is accepted.
 /// SAME latest produced token VALUE for actual malformed-header display.
 /// This is a short data loan, never a spelling parser or source authority.
 fn current_header_value(&self,_token:SpanToken)->io::Result<dm_syntax::OriginalTokenValue<&str>>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual current header value loan is unissued"))}
 fn current_header_literal(&self,_token:SpanToken)->io::Result<Option<&dm_syntax::OriginalLiteralData>>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual current header literal loan is unissued"))}

 /// The complete prefix is a logical window only. Consumers select the
 /// exact current formal or head interval before calling a dense leaf.
 fn with_current_source(&self,read:&mut dyn FnMut(&str,TokenWindow<'_>)->io::Result<()>)->io::Result<()>;
}
pub trait OriginalPrimaryStreamConsumer:OriginalDeclarationHeaderObserver{
 /// Parse ONLY through genuine formal closing ')'. The later SAME complete
 /// header observer finishes return suffix and adopts the same prepared rows.
 fn callable(&mut self,header:OriginalPrimaryLiveHeader,source:&mut dyn OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>;
}
