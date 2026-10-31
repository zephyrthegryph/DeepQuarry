//! Allocation-free logical fingerprints for every report-observable field.
//! Physical Weak/Arc owners remain independently authenticated; their addresses
//! and allocation capacities are not semantic content.
use super::*;
pub(super) struct Fingerprint(xxhash_rust::xxh3::Xxh3);
impl Fingerprint{
 pub(super) fn new(domain:&[u8])->Self{let mut h=Self(xxhash_rust::xxh3::Xxh3::new());h.bytes(domain);h}
 pub(super) fn byte(&mut self,value:u8){self.0.update(&[value]);}
 pub(super) fn bytes(&mut self,value:&[u8]){self.usize(value.len());self.0.update(value);}
 pub(super) fn usize(&mut self,value:usize){self.0.update(&value.to_le_bytes());}
 pub(super) fn u32(&mut self,value:u32){self.0.update(&value.to_le_bytes());}
 pub(super) fn u128(&mut self,value:u128){self.0.update(&value.to_le_bytes());}
 pub(super) fn id(&mut self,value:ProcedureIdentity){self.0.update(&value.owner.bits().to_le_bytes());self.0.update(&value.name.bits().to_le_bytes());self.byte(u8::from(value.verb));self.u32(value.occurrence);}
 pub(super) fn span(&mut self,value:Span){self.usize(value.start);self.usize(value.end);}
 pub(super) fn optional_span(&mut self,value:Option<Span>){match value{None=>self.byte(0),Some(value)=>{self.byte(1);self.span(value);}}}
 pub(super) fn target(&mut self,value:EffectTarget){match value{EffectTarget::Source(id)=>{self.byte(0);self.id(id)},EffectTarget::Builtin(id)=>{self.byte(1);self.0.update(&id.profile().to_le_bytes());self.u32(id.ordinal());}}}
 pub(super) fn parent(&mut self,value:Option<EffectTarget>){match value{None=>self.byte(0),Some(value)=>{self.byte(1);self.target(value)}}}
 fn point(&mut self,value:&SourceNoteOrigin){self.bytes(value.path.as_os_str().as_encoded_bytes());self.usize(value.line);self.usize(value.byte_column);}
 fn origin(&mut self,value:CallOrigin){match value{CallOrigin::Source(span)=>{self.byte(0);self.span(span)},CallOrigin::ImplicitList(dm_syntax::ImplicitListOrigin::ParserSynthetic)=>self.byte(1)}}
 fn effects(&mut self,effects:&[DirectEffect]){self.usize(effects.len());for effect in effects{self.origin(effect.origin);self.bytes(effect.reason.as_bytes());}}
 fn diagnostic(&mut self,row:&Diagnostic){self.bytes(row.family.as_bytes());self.byte(match row.severity{Severity::Disabled=>0,Severity::Warning=>1,Severity::Error=>2});self.span(row.span);self.span(row.expression_span);self.bytes(row.message.as_bytes());self.usize(row.notes.len());for note in &row.notes{self.bytes(note.message.as_bytes());match &note.source{None=>self.byte(0),Some(point)=>{self.byte(1);self.point(point)}}}}
 pub(super) fn body(&mut self,row:&BodyEffects){self.usize(row.ordinal);self.id(row.procedure);self.optional_span(row.pure);self.optional_span(row.sleep.no_sleep);self.optional_span(row.sleep.exempt);self.byte(u8::from(row.sleep.waitfor_disabled));self.effects(&row.blocking);self.parent(row.parent);self.effects(&row.direct);self.usize(row.calls.len());for call in &row.calls{self.target(call.callee);self.origin(call.origin);self.byte(u8::from(call.exact));self.byte(u8::from(call.new_context));}self.usize(row.immediate.len());for diagnostic in &row.immediate{self.diagnostic(diagnostic)}self.optional_span(row.opening_parenthesis);match &row.callable_origin{Ok(point)=>{self.byte(0);self.point(point)},Err(dm_tree::frontend::BorrowedCallableOriginError::Body(message))=>{self.byte(1);self.bytes(message.as_bytes())},Err(dm_tree::frontend::BorrowedCallableOriginError::Projection(message))=>{self.byte(2);self.bytes(message.as_bytes())}}}
 pub(super) fn finish(self)->u128{self.0.digest128()}
}
pub fn report_fingerprint(rows:&[Produced])->u128{let mut hash=Fingerprint::new(b"original-effect-report-fields-v1");hash.usize(rows.len());for row in rows{match row.registration_tag{None=>hash.byte(0),Some(tag)=>{hash.byte(1);hash.bytes(tag.as_bytes())}}hash.byte(match row.severity{DiagnosticSeverity::Error=>0,DiagnosticSeverity::Warning=>1,DiagnosticSeverity::Info=>2,DiagnosticSeverity::Hint=>3});hash.diagnostic(&row.diagnostic);hash.point(&row.origin);}hash.finish()}
