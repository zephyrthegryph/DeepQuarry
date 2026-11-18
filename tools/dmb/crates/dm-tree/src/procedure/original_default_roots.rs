//! Once-produced defaults on the SAME actual header source owner. No parser,
//! semantic table, second AST, or authority from a numeric span is introduced.
use super::OriginalProcedureHeaders;
use crate::procedure::{CompletedFormalRoot,FormalExpressionRole,FormalClauseRows};
use dm_syntax::{Expr,ExprKind,Span,SettingAdmission,SettingExpression,SettingRootLease,TokenKind};
use std::io;
use super::super::original_primary_signatures::{HeaderGeometry,PackedHeader,WideHeader};
fn invalid(text:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,text)}
fn checkpoint(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
pub(in crate::procedure) struct Row{pub(in crate::procedure) header:Span,pub(in crate::procedure) parameter:usize,pub(in crate::procedure) role:FormalExpressionRole,pub(in crate::procedure) enclosure:Option<Span>,pub(in crate::procedure) assignment:Span,pub(in crate::procedure) root:SettingExpression,pub(in crate::procedure) native_children:u8}
struct ClauseRow{geometry:PackedHeader,clauses:FormalClauseRows,_lease:std::sync::Arc<SettingRootLease>}
struct InputRow{header:Span,parameter:usize,marker:Span,span:Span,after_in:bool,input:dm_syntax::RetainedParameterInput}
pub(crate) struct OriginalDefaultRoots{rows:Vec<Row>,inputs:Vec<InputRow>,input_bytes:usize,clauses:ClauseDirectory,last_clause_header:Option<usize>,binding:dm_preprocess::regions::OriginalLiteralSourceBinding,credit:SettingRootLease}
impl std::fmt::Debug for OriginalDefaultRoots{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalDefaultRoots").field("rows",&self.rows.len()).field("directory_grant",&self.credit.bytes()).field("clauses",&self.clauses.rows.len()).field("clause_directory_grant",&self.clauses.storage.as_ref().map(SettingRootLease::bytes)).field("wide_clause_coordinates",&self.clauses.wide.len()).field("wide_clause_directory_grant",&self.clauses.wide_storage.as_ref().map(SettingRootLease::bytes)).field("input_rows",&self.inputs.len()).finish_non_exhaustive()}}
// SAME already-issued coordinate encoding as completed signatures. The normal
// final row is physically48 rather than64bytes on64-bit; arbitrary wide source
// offsets/lengths keep their exact usize values in a sparse funded side column.
#[derive(Default)]struct ClauseDirectory{rows:Vec<ClauseRow>,storage:Option<SettingRootLease>,wide:Vec<WideHeader>,wide_storage:Option<SettingRootLease>}
impl ClauseDirectory{
 fn push(&mut self,geometry:HeaderGeometry,clauses:FormalClauseRows,lease:std::sync::Arc<SettingRootLease>,a:&SettingAdmission<'_>)->io::Result<()>{
  checkpoint(a)?;if !a.matches_lease_domain(&lease){return Err(invalid("clause coordinate payload uses another admission"))}
  let packed=PackedHeader::pack(geometry);let ordinal=self.rows.len();
  // Fund both final physical columns before publishing either row. The SAME
  // existing grow kernel owns old/new overlap and destroys oldVec before credit.
  super::super::original_primary_signatures::grow_funded_rows(&mut self.rows,&mut self.storage,a)?;
  if packed.is_none(){super::super::original_primary_signatures::grow_funded_rows(&mut self.wide,&mut self.wide_storage,a)?;}
  if packed.is_none(){self.wide.push(WideHeader{ordinal,geometry});}
  self.rows.push(ClauseRow{geometry:packed.unwrap_or(PackedHeader::WIDE),clauses,_lease:lease});Ok(())
 }
 fn geometry(&self,ordinal:usize)->Result<HeaderGeometry,&'static str>{
  let row=self.rows.get(ordinal).ok_or("actual clause coordinate ordinal absent")?;
  if let Some(geometry)=row.geometry.unpack(){return Ok(geometry)}
  let index=self.wide.binary_search_by_key(&ordinal,|row|row.ordinal).map_err(|_|"actual wide clause coordinate absent")?;
  Ok(self.wide[index].geometry)
 }
 fn find(&self,start:usize)->Result<Option<usize>,&'static str>{
  let(mut low,mut high)=(0,self.rows.len());while low<high{let mid=low+(high-low)/2;match self.geometry(mid)?.header.start.cmp(&start){std::cmp::Ordering::Less=>low=mid+1,std::cmp::Ordering::Greater=>high=mid,std::cmp::Ordering::Equal=>return Ok(Some(mid))}}Ok(None)
 }
 fn visit_storage(&self,visit:&mut impl FnMut(usize,usize,usize)){
  if self.rows.capacity()!=0{visit(self.rows.as_ptr()as usize,self.rows.len()*std::mem::size_of::<ClauseRow>(),self.rows.capacity()*std::mem::size_of::<ClauseRow>())}
  for row in &self.rows{row.clauses.visit_storage(&mut *visit);row._lease.visit_counter_storage(|p,n|visit(p,n,n));}
  if self.wide.capacity()!=0{visit(self.wide.as_ptr()as usize,self.wide.len()*std::mem::size_of::<WideHeader>(),self.wide.capacity()*std::mem::size_of::<WideHeader>())}
  for credit in [&self.storage,&self.wide_storage].into_iter().flatten(){credit.visit_counter_storage(|p,n|visit(p,n,n));}
 }
}
// The immutable directory's entry capacity is known before any publication.
fn allocate_default_directory(
    count: usize,
    a: &SettingAdmission<'_>,
) -> io::Result<(Vec<Row>, SettingRootLease)> {
    use std::alloc::{alloc, Layout};
    use std::ptr::NonNull;

    checkpoint(a)?;
    let layout = Layout::array::<Row>(count).map_err(|_| io::ErrorKind::OutOfMemory)?;
    let bytes = layout.size().checked_add(std::mem::size_of::<OriginalDefaultRoots>())
        .ok_or(io::ErrorKind::OutOfMemory)?;
    let credit = a.reserve(bytes).map_err(|e| a.take_operational_error().unwrap_or(e))?;
    if count == 0 {
        return Ok((Vec::new(), credit));
    }

    // SAFETY: Row has nonzero size and the full Global allocation is funded
    // before the call. Vec takes that same capacity/layout with length zero.
    let raw = NonNull::new(unsafe { alloc(layout) }.cast::<Row>())
        .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory, "native default directory allocation denied"))?;
    let rows = unsafe { Vec::from_raw_parts(raw.as_ptr(), 0, count) };
    Ok((rows, credit))
}

impl OriginalDefaultRoots{
 pub(super) fn new(count:usize,binding:&dm_preprocess::regions::OriginalLiteralSourceBinding,a:&SettingAdmission<'_>)->io::Result<Self>{
  let (rows,credit)=allocate_default_directory(count,a)?;
  Ok(Self{rows,inputs:Vec::new(),input_bytes:0,clauses:ClauseDirectory::default(),last_clause_header:None,binding:binding.clone(),credit})
 }
 pub(super) fn add_clauses(&mut self,headers:&OriginalProcedureHeaders,header:Span,argument_offset:usize,parameters:&[dm_ir::Parameter],clauses:FormalClauseRows,lease:std::sync::Arc<SettingRootLease>,a:&SettingAdmission<'_>)->io::Result<()>{
  checkpoint(a)?;if !a.matches_lease_domain(&lease)||clauses.len()!=parameters.len()||self.last_clause_header.is_some_and(|start|start>=header.start){return Err(invalid("actual produced formal clauses are foreign or out of order"))}let origin=header.start.checked_add(argument_offset).ok_or(io::ErrorKind::InvalidInput)?;
  let tokens=headers.tokens.window();
  for(parts,parameter)in clauses.iter().zip(parameters){checkpoint(a)?;if parts.parameter.start>parameter.relative_span.start||parts.parameter.end<parameter.relative_span.end{return Err(invalid("actual clause extent differs from parameter metadata"))}for(marker,wanted)in[(parts.assignment,"="),(parts.annotation,"as"),(parts.source,"in"),(parts.post_source_annotation,"as")]{if let Some(marker)=marker{if marker.start<parts.parameter.start||marker.end>parts.parameter.end||marker.start>=marker.end{return Err(invalid("actual formal marker escapes its parameter"))}let span=Span::new(origin.checked_add(marker.start).ok_or(io::ErrorKind::InvalidInput)?,origin.checked_add(marker.end).ok_or(io::ErrorKind::InvalidInput)?);let at=tokens.partition_point(|token|token.span.start<span.start);let token=tokens.get(at).filter(|token|token.span==span).ok_or_else(||invalid("actual marker is not one primary occurrence"))?;if token.text(&headers.source)!=wanted||matches!(token.kind,TokenKind::String|TokenKind::Number|TokenKind::Resource){return Err(invalid("actual formal marker differs from current primary token"))}}}if parts.post_source_annotation.is_some_and(|post|parts.source.is_none_or(|source|source.start>=post.start)){return Err(invalid("post-in annotation lacks its actual source marker"))}}
  // The completed producer still validates order even when this header
  // has no parameter ordinal that a DefaultLoans consumer could request.
  if clauses.len() != 0 {
   self.clauses.push(HeaderGeometry{header,argument_offset},clauses,lease,a)?;
  }
  self.last_clause_header = Some(header.start);
  checkpoint(a)
 }
 fn clauses_for(&self,header:Span,parameter:usize)->Result<dm_syntax::ParameterClauseSpans,&'static str>{let at=self.clauses.find(header.start)?.ok_or("actual produced formal clauses are unissued")?;let row=&self.clauses.rows[at];let geometry=self.clauses.geometry(at)?;if geometry.header!=header{return Err("actual clause header differs")}let mut parts=row.clauses.get(parameter).ok_or("actual clause ordinal absent")?;let origin=geometry.header.start.checked_add(geometry.argument_offset).ok_or("actual clause origin overflow")?;let shift=|span:Span|->Result<Span,&'static str>{Ok(Span::new(span.start.checked_add(origin).ok_or("actual clause coordinate overflow")?,span.end.checked_add(origin).ok_or("actual clause coordinate overflow")?))};parts.parameter=shift(parts.parameter)?;parts.assignment=parts.assignment.map(shift).transpose()?;parts.annotation=parts.annotation.map(shift).transpose()?;parts.source=parts.source.map(shift).transpose()?;parts.post_source_annotation=parts.post_source_annotation.map(shift).transpose()?;Ok(parts)}
 pub(super) fn add(&mut self,headers:&OriginalProcedureHeaders,header:Span,argument_offset:usize,parameter:&dm_ir::Parameter,symbols:&dm_ir::SymbolTable,demanded:CompletedFormalRoot,native_children:u8,a:&SettingAdmission<'_>)->io::Result<()>{
  checkpoint(a)?;if self.rows.len()==self.rows.capacity(){return Err(invalid("actual default directory exceeds its admitted completed cohort"))}
  if self.rows.last().is_some_and(|row|(row.header.start,row.parameter,row.role)>=(header.start,demanded.parameter,demanded.role)){return Err(invalid("actual default directory repeats or reverses primary source order"))}
  let row=retain_completed_formal_root(&headers.source,headers.tokens.window(),||headers.original_literal_facts(),header,argument_offset,parameter,symbols,demanded,native_children,a)?;
  self.rows.push(row);checkpoint(a)
 }
 pub(super) fn add_input(&mut self,headers:&OriginalProcedureHeaders,header:Span,argument_offset:usize,parameter:&dm_ir::Parameter,_symbols:&dm_ir::SymbolTable,ordinal:usize,marker:Span,input:dm_syntax::RetainedParameterInput,a:&SettingAdmission<'_>)->io::Result<()>{
  checkpoint(a)?;if !input.is_admitted_by(a)||self.inputs.last().is_some_and(|row|(row.header.start,row.parameter,row.marker.start)>=(header.start,ordinal,marker.start)){return Err(invalid("actual input annotation is foreign or reverses primary order"))}
  let start=header.start.checked_add(argument_offset).and_then(|v|v.checked_add(parameter.relative_span.start)).ok_or(io::ErrorKind::InvalidInput)?;let end=header.start.checked_add(argument_offset).and_then(|v|v.checked_add(parameter.relative_span.end)).ok_or(io::ErrorKind::InvalidInput)?;
  let tokens=headers.tokens.window();
  let first=tokens.partition_point(|token|token.span.end<=start);let last=tokens.partition_point(|token|token.span.start<end);if first>last{return Err(invalid("actual parameter input range reverses native tokens"))}
  let clauses=self.clauses_for(header,ordinal).map_err(invalid)?;if clauses.parameter.start>start||clauses.parameter.end<end{return Err(invalid("produced clause range differs from current parameter"))}
  let(span,after_in)=match &*input{dm_syntax::ParameterInputSyntax::EmptyParens{span,after_in}|dm_syntax::ParameterInputSyntax::Union{span,after_in,..}=>(*span,*after_in)};
  if (clauses.annotation!=Some(marker)&&clauses.post_source_annotation!=Some(marker))||clauses.source.is_some_and(|source|source.start<marker.start)!=after_in||span.start<marker.end||span.end>clauses.after_original(marker).end{return Err(invalid("actual input annotation differs from completed native clause metadata"))}
  if !after_in&&parameter.input_annotation.is_none(){return Err(invalid("actual completed native input metadata is absent"))}if after_in&&clauses.annotation==Some(marker)&&parameter.input_annotation.is_some(){return Err(invalid("ignored Original input unexpectedly became runtime metadata"))}
  let first=tokens.partition_point(|token|token.span.end<=span.start);let last=tokens.partition_point(|token|token.span.start<span.end);if first>last{return Err(invalid("actual input annotation reverses original occurrences"))}let actual=tokens.range(first,last).ok_or_else(||invalid("actual input annotation interval is absent"))?;let mut actual=actual.iter().filter(|token|!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment));
  match &*input{
   dm_syntax::ParameterInputSyntax::EmptyParens{..}=>{let first=actual.next().ok_or_else(||invalid("actual empty input opening is absent"))?;let last=actual.next().ok_or_else(||invalid("actual empty input closing is absent"))?;if first.kind!=TokenKind::Punctuation||last.kind!=TokenKind::Punctuation||first.text(&headers.source)!="("||last.text(&headers.source)!=")"{return Err(invalid("actual empty input differs from its produced syntax"))}},
   dm_syntax::ParameterInputSyntax::Union{identifiers,..}=>{for(index,id)in identifiers.iter().enumerate(){checkpoint(a)?;if index!=0{let separator=actual.next().ok_or_else(||invalid("actual input union separator is absent"))?;if !matches!(separator.kind,TokenKind::Operator|TokenKind::Punctuation)||separator.text(&headers.source)!="|"{return Err(invalid("actual input union separator differs"))}}let current=actual.next().ok_or_else(||invalid("actual input identifier is absent"))?;if current.kind!=TokenKind::Ident||current.span!=*id{return Err(invalid("actual input identifier differs from produced syntax"))}}},
  }
  if actual.next().is_some(){return Err(invalid("actual input annotation has extra original tokens"))}
  if self.inputs.len()==self.inputs.capacity(){let count=self.inputs.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;let peak=count.checked_mul(4).and_then(|v|v.checked_mul(std::mem::size_of::<InputRow>())).ok_or(io::ErrorKind::OutOfMemory)?;a.grow(&mut self.credit,peak)?;self.inputs.try_reserve_exact(count-self.inputs.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;let bytes=self.inputs.capacity().checked_mul(std::mem::size_of::<InputRow>()).ok_or(io::ErrorKind::OutOfMemory)?;if bytes>peak{return Err(io::ErrorKind::OutOfMemory.into())}let free=self.input_bytes.checked_add(peak).and_then(|v|v.checked_sub(bytes)).ok_or(io::ErrorKind::InvalidData)?;a.shrink(&mut self.credit,free)?;self.input_bytes=bytes;}
  self.inputs.push(InputRow{header,parameter:ordinal,marker,span,after_in,input});checkpoint(a)
 }
 pub(super) fn matches(&self,headers:&OriginalProcedureHeaders,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.credit)&&headers.original_literal_source.get().is_some_and(|holder|holder.view().is_some_and(|view|view.same_producer(&self.binding)))}

#[cfg(test)]
 pub(super) fn clause_storage_for_test(&self) -> (usize, usize) {
  (self.clauses.rows.len(), self.clauses.storage.as_ref().map_or(0, |lease| lease.bytes()))
 }
 pub(super) fn visit_roots(&self,mut visit:impl FnMut(&SettingExpression)){for row in &self.rows{visit(&row.root)}}
 /// DATA count from the exact already-produced header clause row. Missing,
 /// foreign or unfunded children cannot authorize the smaller frontier.
 pub(super) fn produced_parameter_count(&self,headers:&OriginalProcedureHeaders,header:Span,a:&SettingAdmission<'_>)->io::Result<Option<usize>>{
  checkpoint(a)?;if !self.matches(headers,a){return Ok(None)}
  let Some(at)=self.clauses.find(header.start).map_err(invalid)? else{return Ok(None)};
  let row=&self.clauses.rows[at];if self.clauses.geometry(at).map_err(invalid)?.header!=header{return Ok(None)}
  let first=self.rows.partition_point(|row|row.header.start<header.start);let end=self.rows.partition_point(|row|row.header.start<=header.start);
  for child in &self.rows[first..end]{checkpoint(a)?;if child.header!=header||!child.root.is_retained_in(a){return Ok(None)}}
  let first=self.inputs.partition_point(|row|row.header.start<header.start);let end=self.inputs.partition_point(|row|row.header.start<=header.start);
  for child in &self.inputs[first..end]{checkpoint(a)?;if child.header!=header||!child.input.is_admitted_by(a){return Ok(None)}}
  Ok(Some(row.clauses.len()))
 }
 pub(super) fn loan<'a>(&'a self,header:Span,notices:Option<&'a super::super::original_formal_notices::FormalNotices>)->DefaultLoans<'a>{DefaultLoans{owner:self,header,notices}}
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  self.clauses.visit_storage(&mut visit);
  if self.rows.capacity()!=0{visit(self.rows.as_ptr()as usize,self.rows.len()*std::mem::size_of::<Row>(),self.rows.capacity()*std::mem::size_of::<Row>())}self.credit.visit_counter_storage(|p,n|visit(p,n,n));
  if self.inputs.capacity()!=0{visit(self.inputs.as_ptr()as usize,self.inputs.len()*std::mem::size_of::<InputRow>(),self.inputs.capacity()*std::mem::size_of::<InputRow>())}for row in &self.inputs{row.input.visit_storage(&mut visit);}
  for row in &self.rows{row.root.visit_root_storage(|p,n|visit(p,n,n));row.root.visit_retention_storage(|p,n|visit(p,n,n));}
 }
}
/// SAME once-produced root validator, reusable while actual primary rows are
/// borrowed at procedure commit. Caller polls before entering this private loan.
pub(in crate::procedure) fn retain_completed_formal_root<'facts>(
 source:&str,tokens:dm_syntax::TokenWindow<'_>,facts:impl FnOnce()->io::Result<Option<dm_syntax::OriginalLiteralFactsView<'facts>>>,
 header:Span,argument_offset:usize,parameter:&dm_ir::Parameter,symbols:&dm_ir::SymbolTable,demanded:CompletedFormalRoot,native_children:u8,a:&SettingAdmission<'_>,
)->io::Result<Row>{
  let parameter_start=header.start.checked_add(argument_offset).and_then(|n|n.checked_add(parameter.relative_span.start)).ok_or(io::ErrorKind::InvalidInput)?;
  let parameter_end=header.start.checked_add(argument_offset).and_then(|n|n.checked_add(parameter.relative_span.end)).ok_or(io::ErrorKind::InvalidInput)?;
  let expected_marker=match demanded.role{FormalExpressionRole::Default=>"=",FormalExpressionRole::Source=>"in",FormalExpressionRole::Dimension(_)=>"["};
  if demanded.assignment.start<parameter_start||demanded.assignment.end>parameter_end||source.get(demanded.assignment.range())!=Some(expected_marker){return Err(invalid("demanded expression marker differs from its actual parameter source slot"))}
  let expected=match demanded.role{FormalExpressionRole::Default=>parameter.default.as_ref(),FormalExpressionRole::Source=>parameter.source_expression.as_ref(),FormalExpressionRole::Dimension(index)=>parameter.array.as_ref().and_then(|array|array.dimensions.get(index)).and_then(Option::as_ref)}.ok_or_else(||invalid("demanded root has no actual formal expression metadata"))?;
  let first=tokens.partition_point(|token|token.span.end<=demanded.assignment.end);
  let first=(first..tokens.len()).find(|index|tokens.get(*index).is_some_and(|token|!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment))).ok_or_else(||invalid("actual default RHS has no primary token"))?;
  let start=tokens.get(first).ok_or_else(||invalid("actual default token ordinal is absent"))?.span.start;let last=expected.tokens.last().ok_or_else(||invalid("actual formal default token metadata is empty"))?;
  let end=start.checked_add(last.relative_span.end).ok_or(io::ErrorKind::InvalidInput)?;let expression=Span::new(start,end);
  if start<demanded.assignment.end||end>parameter_end||expected.tokens.first().is_none_or(|token|token.relative_span.start!=0){return Err(invalid("actual expression metadata escapes its original parameter source slot"))}
  match demanded.role{FormalExpressionRole::Dimension(_)=>{let brackets=demanded.enclosure.ok_or_else(||invalid("demanded dimension lacks its actual consumed closing bracket"))?;if brackets.start!=demanded.assignment.start||brackets.end>parameter_end||brackets.end<end||{let at=tokens.partition_point(|token|token.span.end<brackets.end);tokens.get(at).is_none_or(|token|token.span.end!=brackets.end||token.text(&source)!="]")}{return Err(invalid("demanded dimension enclosure differs from its native closing occurrence"))}},_=>{if demanded.enclosure.is_some(){return Err(invalid("non-dimension root unexpectedly carries bracket geometry"))}}}

  let last=tokens.partition_point(|token|token.span.start<end);if first>last{return Err(invalid("actual expression token range reverses its geometry"))}let actual=tokens.range(first,last).ok_or_else(||invalid("actual expression token range is absent"))?;
  // Compare the SAME primary token occurrences with their once-produced native
  // symbolic metadata, not another header/expression parser.
  let mut native=actual.iter().filter(|token|!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment));
  for token in expected.tokens.iter(){checkpoint(a)?;let actual=native.next().ok_or_else(||invalid("actual formal metadata has extra RHS tokens"))?;if actual.kind!=token.kind||actual.span.start.checked_sub(start)!=Some(token.relative_span.start)||actual.span.end.checked_sub(start)!=Some(token.relative_span.end)||symbols.text(token.text)!=Some(actual.text(&source)){return Err(invalid("formal default metadata differs from the actual primary RHS occurrences"))}}
  if native.next().is_some(){return Err(invalid("actual primary RHS has extra formal default tokens"))}
  let produced=demanded.syntax.expression();
  if produced.span!=expression{return Err(invalid("demanded root is not the complete actual formal RHS"))}
  // SAME native normalizer only combines adjacent colons. No blanket raw-text
  // equality can authorize another token kind or a different operator stream.
  let mut actual=actual.iter().filter(|token|!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment));
  for token in demanded.syntax.tokens(){checkpoint(a)?;let first=actual.next().ok_or_else(||invalid("demanded default has extra native input tokens"))?;
   if first.span.start!=token.span.start||first.kind!=token.kind||source.get(token.span.range())!=Some(token.text.as_str()){return Err(invalid("demanded input differs from actual primary token kind/span/spelling"))}
   if first.span.end!=token.span.end{let second=actual.next().ok_or_else(||invalid("demanded combined punctuation lacks its actual second primary token"))?;if token.text!="::"||first.text(&source)!=":"||second.text(&source)!=":"||second.kind!=token.kind||first.span.end!=second.span.start||second.span.end!=token.span.end{return Err(invalid("demanded punctuation does not match the same native adjacency normalizer"))}}
  }
  if actual.next().is_some(){return Err(invalid("demanded default omitted actual primary RHS tokens"))}
  let facts=facts()?.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual default has no genuine primary literal binding"))?;let(rows,origin)=facts.raw_parts();
  fn literals(root:&Expr,rows:dm_syntax::OriginalLiteralRows<'_>,origin:usize,a:&SettingAdmission<'_>)->io::Result<()>{
   checkpoint(a)?;let _frame=a.evaluation_frame()?;
   if let ExprKind::Literal(text)=&root.kind{
    if let Some(data)=text.original_data(){let span=Span::new(root.span.start.checked_add(origin).ok_or(io::ErrorKind::InvalidInput)?,root.span.end.checked_add(origin).ok_or(io::ErrorKind::InvalidInput)?);let at=rows.partition_point(|(p,_)|p.start<span.start);let(_,actual)=rows.get(at).filter(|(p,_)|*p==span).ok_or_else(||invalid("demanded literal has no actual same-primary occurrence"))?;if !data.same_owner(actual){return Err(invalid("demanded literal VALUE belongs to another actual primary producer"))}}
    else if text.as_str()!="null"{return Err(io::Error::new(io::ErrorKind::Unsupported,"actual demanded default literal VALUE is unissued"))}
    return Ok(())
   }
   dm_syntax::try_for_each_expression_child(root,|_,child|literals(child,rows,origin,a))
  }
  literals(produced,rows,origin,a)?;
  let root=demanded.syntax.retain(a).map_err(|failure|match failure{dm_syntax::SettingSyntaxFailure::Operational(actual)=>a.take_operational_error().unwrap_or(actual),dm_syntax::SettingSyntaxFailure::Syntax(_)=>invalid("completed demanded root unexpectedly retained syntax diagnostics")})?;
  Ok(Row{header,parameter:demanded.parameter,role:demanded.role,enclosure:demanded.enclosure,assignment:demanded.assignment,root,native_children})
}

pub(super) struct DefaultLoans<'a>{owner:&'a OriginalDefaultRoots,header:Span,notices:Option<&'a super::super::original_formal_notices::FormalNotices>}
impl DefaultLoans<'_>{
 fn root(&self,parameter:usize,role:FormalExpressionRole,marker:Span,enclosure:Option<Span>,expression:Span)->Result<SettingExpression,&'static str>{
  let at=self.owner.rows.binary_search_by_key(&(self.header.start,parameter,role),|row|(row.header.start,row.parameter,row.role)).map_err(|_|"actual demanded formal expression root is unissued")?;let row=&self.owner.rows[at];
  if row.header!=self.header||row.assignment!=marker||row.enclosure!=enclosure||row.root.current_offset()!=0||row.root.original_expression().span!=expression{return Err("actual formal expression root belongs to another header/parameter occurrence")}
  Ok(row.root.clone())
 }
}
impl dm_syntax::ParameterDefaultSyntaxProvider for DefaultLoans<'_>{
 fn native_child_observation(&mut self,parameter:usize,expressions:Option<&dm_syntax::ParameterExpressions>)->Result<Option<(bool,bool,bool)>,&'static str>{
  let _actual_clauses=self.owner.clauses_for(self.header,parameter)?;
  let key=(self.header.start,parameter);
  let first=self.owner.rows.partition_point(|row|(row.header.start,row.parameter)<key);
  let last=self.owner.rows.partition_point(|row|(row.header.start,row.parameter)<=key);
  let rows=&self.owner.rows[first..last];
  let mut complete=true;let mut recovered=false;let mut deferred=false;let mut count=0usize;
  let mut check=|root:&SettingExpression,role:FormalExpressionRole|->Result<(),&'static str>{
   let mut matches=rows.iter().filter(|row|row.header==self.header&&row.parameter==parameter&&row.role==role&&row.root.same_root(root));
   let row=matches.next().ok_or("native formal child has no same-occurrence producer observation")?;
   if matches.next().is_some()||row.root.current_offset()!=0||row.root.original_expression().span!=root.original_expression().span{return Err("native formal child occurrence is ambiguous or projected")}
   complete&=row.native_children&1!=0;recovered|=row.native_children&2!=0;deferred|=row.native_children&4!=0||row.native_children&8==0;count+=1;Ok(())
  };
  if let Some(expressions)=expressions{
   if let Some(root)=expressions.default_root(){check(root,FormalExpressionRole::Default)?;}
   if let Some(root)=expressions.source_root(){check(root,FormalExpressionRole::Source)?;}
   for (index,root) in expressions.dimensions().iter().enumerate(){if let Some(root)=root{check(root,FormalExpressionRole::Dimension(index))?;}}
  }
  if rows.len()!=count{return Err("native formal settlement omitted a produced child")}
  Ok(Some((complete&&!recovered&&!deferred,recovered,deferred)))
 }

 fn produced_clauses(&mut self,parameter:usize,span:Span)->Result<dm_syntax::ParameterClauseSpans,&'static str>{let mut parts=self.owner.clauses_for(self.header,parameter)?;if span.start<parts.parameter.start||span.end>parts.parameter.end{return Err("requested formal clause view escapes actual produced parameter")}for marker in[parts.assignment,parts.annotation,parts.source,parts.post_source_annotation].into_iter().flatten(){if marker.start<span.start||marker.end>span.end{return Err("requested formal view cuts an actual clause marker")}}parts.parameter=span;Ok(parts)}
 fn default_root(&mut self,parameter:usize,assignment:Span,expression:Span)->Result<SettingExpression,&'static str>{self.root(parameter,FormalExpressionRole::Default,assignment,None,expression)}
 fn trailing_semicolon(&mut self,_parameter:usize,at:Span)->Result<(),&'static str>{let notices=self.notices.ok_or("actual original semicolon notice owner absent")?;if !notices.for_header(self.header.start).iter().any(|row|row.notice.is_semicolon()&&row.notice.span()==at){return Err("actual original semicolon was not produced for this header")}Ok(())}
 fn input_annotation(&mut self,parameter:usize,marker:Span,span:Span,after_in:bool)->Result<dm_syntax::RetainedParameterInput,&'static str>{let at=self.owner.inputs.binary_search_by_key(&(self.header.start,parameter,marker.start),|row|(row.header.start,row.parameter,row.marker.start)).map_err(|_|"actual retained input annotation is unissued")?;let row=&self.owner.inputs[at];if row.header!=self.header||row.marker!=marker||row.span!=span||row.after_in!=after_in{return Err("retained input annotation belongs to another actual formal occurrence")}Ok(row.input.clone())}
 fn source_root(&mut self,parameter:usize,marker:Span,expression:Span)->Result<SettingExpression,&'static str>{self.root(parameter,FormalExpressionRole::Source,marker,None,expression)}
 fn dimension_root(&mut self,parameter:usize,index:usize,brackets:Span,expression:Span)->Result<SettingExpression,&'static str>{let at=self.owner.rows.binary_search_by_key(&(self.header.start,parameter,FormalExpressionRole::Dimension(index)),|row|(row.header.start,row.parameter,row.role)).map_err(|_|"actual demanded dimension root is unissued")?;let row=&self.owner.rows[at];self.root(parameter,FormalExpressionRole::Dimension(index),row.assignment,Some(brackets),expression)}
}

#[cfg(test)]
mod default_directory_storage_tests {
    use super::*;
    use std::sync::{atomic::{Ordering}, Arc};

    #[test]
    fn final_default_directory_admits_exact_rows_while_pending_storage_is_live() {
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let pending = healthy.reserve(2048 * 440).unwrap();
        let count = 2048;
        let exact = count * std::mem::size_of::<Row>() + std::mem::size_of::<OriginalDefaultRoots>();
        let live = pending.bytes();
        let low = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (live + exact - 1), &|| Ok(()));
        assert_eq!(allocate_default_directory(count, &low).err().unwrap().kind(),
            io::ErrorKind::OutOfMemory);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (live));

        let exact_admission = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (live + exact), &|| Ok(()));
        let (rows, credit) = allocate_default_directory(count, &exact_admission).unwrap();
        assert_eq!(rows.capacity(), count);
        assert_eq!(rows.len(), 0);
        assert_eq!(credit.bytes(), exact);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (live + exact));
        drop(rows);
        drop(credit);
        drop(pending);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn final_default_directory_keeps_wrapper_only_when_empty_and_propagates_native_io() {
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let (rows, credit) = allocate_default_directory(0, &healthy).unwrap();
        assert_eq!(rows.capacity(), 0);
        assert_eq!(credit.bytes(), std::mem::size_of::<OriginalDefaultRoots>());
        drop(rows);
        drop(credit);

        let fault = || Err(io::Error::from_raw_os_error(1450));
        let failed = SettingAdmission::new(&used, 1 << 20, &fault);
        assert_eq!(allocate_default_directory(1, &failed).err().unwrap().raw_os_error(), Some(1450));
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
}

#[cfg(test)]
mod native_default_row_footprint_tests{
 use super::*;
 #[allow(dead_code)]struct PriorRow{header:Span,parameter:usize,role:FormalExpressionRole,enclosure:Option<Span>,assignment:Span,expression:Span,root:SettingExpression}
 #[test]fn native_default_observation_reports_actual_row_cost(){let prior=std::mem::size_of::<PriorRow>();let current=std::mem::size_of::<Row>();eprintln!("NATIVE_DEFAULT_ROW_SIZE prior={prior} current={current}");assert!(current<=prior,"native observation must not grow actual retained default rows");}
}

#[cfg(test)]mod compact_clause_coordinate_controls{
 use super::*;use std::{sync::{Arc,atomic::Ordering},mem::size_of};
 fn payload(a:&SettingAdmission<'_>)->Arc<SettingRootLease>{Arc::new(a.reserve(size_of::<SettingRootLease>()+2*size_of::<usize>()).unwrap())}
 #[test]fn actual_clause_directory_physically_packs_rows_with_lossless_arbitrary_wide_fallback(){
  let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();let used=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let lease=payload(&a);let mut rows=ClauseDirectory::default();
  #[cfg(target_pointer_width="64")]assert_eq!(size_of::<ClauseRow>(),48);
  let last=usize::from(u16::MAX);let geometries=[HeaderGeometry{header:Span::new(0,0),argument_offset:0},HeaderGeometry{header:Span::new(1,last+1),argument_offset:last},HeaderGeometry{header:Span::new(2,last+3),argument_offset:1},HeaderGeometry{header:Span::new(3,last+5),argument_offset:last+1},HeaderGeometry{header:Span::new(u32::MAX as usize,usize::MAX),argument_offset:usize::MAX}];
  for(ordinal,geometry)in geometries.into_iter().enumerate(){rows.push(geometry,FormalClauseRows::default(),Arc::clone(&lease),&a).unwrap();assert_eq!(rows.geometry(ordinal).unwrap(),geometry);assert_eq!(rows.find(geometry.header.start).unwrap(),Some(ordinal));}
  assert_eq!(rows.wide.len(),3);assert_eq!(rows.find(4).unwrap(),None);assert_eq!(rows.storage.as_ref().unwrap().bytes(),rows.rows.capacity()*size_of::<ClauseRow>());assert_eq!(rows.wide_storage.as_ref().unwrap().bytes(),rows.wide.capacity()*size_of::<WideHeader>());
  let mut observed=Vec::new();rows.visit_storage(&mut|p,n,c|observed.push((p,n,c)));assert!(observed.iter().any(|&(p,_,c)|p==rows.rows.as_ptr()as usize&&c==rows.rows.capacity()*size_of::<ClauseRow>()));assert!(observed.iter().any(|&(p,_,c)|p==rows.wide.as_ptr()as usize&&c==rows.wide.capacity()*size_of::<WideHeader>()));
  drop((rows,lease));assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_clause_wide_denial_and_first_io_never_publish_partial_coordinate(){
  let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();let used=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let lease=payload(&a);let mut rows=ClauseDirectory::default();
  super::super::super::original_primary_signatures::grow_funded_rows(&mut rows.rows,&mut rows.storage,&a).unwrap();let before=used.load(Ordering::Acquire);let wide=HeaderGeometry{header:Span::new(0,1<<16),argument_offset:1};let low=SettingAdmission::new(&used,before,&||Ok(()));assert_eq!(rows.push(wide,FormalClauseRows::default(),Arc::clone(&lease),&low).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(rows.rows.is_empty()&&rows.wide.is_empty());assert_eq!(used.load(Ordering::Acquire),before);
  let fault=||Err(io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&used,8<<20,&fault);assert_eq!(rows.push(wide,FormalClauseRows::default(),Arc::clone(&lease),&failed).unwrap_err().raw_os_error(),Some(1450));assert!(rows.rows.is_empty()&&rows.wide.is_empty());
  rows.push(wide,FormalClauseRows::default(),Arc::clone(&lease),&a).unwrap();assert_eq!(rows.geometry(0).unwrap(),wide);drop((rows,lease));assert_eq!(used.load(Ordering::Acquire),fixed);
 }
}
