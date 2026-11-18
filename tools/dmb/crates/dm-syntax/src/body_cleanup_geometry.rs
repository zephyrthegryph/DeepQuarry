//! Resource-only preflight of an already-issued BODY item/token loan.
//! This neither parses source nor issues syntax/source/completeness authority.
use crate::{admitted_worklist::Worklist, Expr, Item, SettingAdmission, SharedSettingRetention, Span, Statement, TokenKind};
use std::{io, mem::size_of};

#[derive(Debug, Clone, Copy)]
pub struct BodyCleanupStartupGeometry {
    bytes: usize,
    items: usize,
    significant_tokens: usize,
    inline_statement_tokens: usize,
}
impl BodyCleanupStartupGeometry {
    pub fn bytes(self) -> usize { self.bytes }
}
fn overflow() -> io::Error { io::Error::new(io::ErrorKind::OutOfMemory, "BODY cleanup geometry overflow") }
fn poll(a: &SettingAdmission<'_>) -> io::Result<()> { a.checkpoint().map_err(|proxy| a.take_operational_error().unwrap_or(proxy)) }

/// The caller must lend the COMPLETE current BODY's genuine primary tokens and
/// entire item forest. Bounds are DATA only; the current owner still validates
/// that loan, its source window, and the final parser product independently.
///
/// Existing expression productions add at most one future-cleanup Expr per
/// consumed significant token: bare `new` adds Call + Ident, but the Ident leaf
/// never enters cleanup. Commas pay for omitted call/constructor values. Native
/// local-array dimensions can be reparsed before replacement; reserve a second
/// copy for every potentially coordinated token inside any square window.
/// Proven Ident leaves are removed using the SAME parser prefix/operator and
/// contextual-call classifiers; their strings/anchors remain ordinary payload.
/// Malformed square-window DATA falls back to two copies of the entire token loan.
/// Parenthesis/brace balance outside dimensions is irrelevant to this bound;
/// the existing local-array producer rejects bad dimension delimiters itself. Literal interpolation expansion is NOT an
/// ordinary-token production: its existing independent admission stays intact.
/// Every statement is an input item, or is introduced by an inline control,
/// label delimiter, comma-local or semicolon. Count all such tokens, including
/// ones used in expressions, as a conservative bound without parsing them.
pub fn body_cleanup_startup_geometry<'s>(
    items: &[Item],
    tokens: impl Iterator<Item = (TokenKind, Span, &'s str)>,
    a: &SettingAdmission<'_>,
) -> io::Result<BodyCleanupStartupGeometry> {
    body_cleanup_startup_geometry_using(items,tokens,a,false,false,false)
}
/// Same preflight for the COMPLETE genuine Original token loan. Its producer
/// classifies static String/Resource separately from Interpolation, and the
/// actual Original parser binds them through from_original_view: no private
/// template AST exists for these scalar DATA tokens. No source grant is issued.
pub fn original_body_cleanup_startup_geometry<'s>(items:&[Item],tokens:impl Iterator<Item=(TokenKind,Span,&'s str)>,a:&SettingAdmission<'_>)->io::Result<BodyCleanupStartupGeometry>{
    body_cleanup_startup_geometry_using(items,tokens,a,true,false,false)
}
/// Same genuine Original producer, with actual serialized-root cleanup peak.
/// Unproved header partitions fall back to the old aggregate. This native-only
/// entry relies on the SAME typed template builder owning all private child
/// payload/cleanup before escape; Interpolation tokens still count as wrappers
/// and their actual flat child tokens remain in the same header bound.
pub fn original_body_cleanup_peak_geometry<'s>(items:&[Item],tokens:impl Iterator<Item=(TokenKind,Span,&'s str)>,a:&SettingAdmission<'_>)->io::Result<BodyCleanupStartupGeometry>{body_cleanup_startup_geometry_using(items,tokens,a,true,true,false)}
/// Resource-only aggregate for a COMPLETE authenticated Original token loan.
/// The primary skeleton may omit executable leaves, so no Item/header MAX is
/// inferred here. The SAME native structural cursor emits at most one root
/// per physical newline plus its final segment; the inline splitter may add
/// segments at braces/semicolons. Existing inline/control/label/comma slots pay
/// statement wrappers and local declarations (including parenthesized ones).
/// Comment/whitespace embedded LF is counted conservatively; literal LF is
/// masked by that cursor and cannot create an executable statement root.
/// Original template child ASTs retain their own independently admitted cleanup.
pub fn original_body_token_cleanup_geometry<'s>(tokens:impl Iterator<Item=(TokenKind,Span,&'s str)>,a:&SettingAdmission<'_>)->io::Result<BodyCleanupStartupGeometry>{body_cleanup_startup_geometry_using(&[],tokens,a,true,false,true)}
fn body_cleanup_startup_geometry_using<'s>(items:&[Item],tokens:impl Iterator<Item=(TokenKind,Span,&'s str)>,a:&SettingAdmission<'_>,original_typed:bool,peak_roots:bool,token_statements:bool)->io::Result<BodyCleanupStartupGeometry>{
    let result = (|| -> io::Result<BodyCleanupStartupGeometry> {
    poll(a)?;
    let mut peaks=if peak_roots{Some(CleanupPeak::new(a)?)}else{None};
    let mut pending = Worklist::new(a)?;
    pending.extend(items.iter())?;
    let mut item_count = 0usize;
    while let Some(item) = pending.pop() {
        poll(a)?;
        item_count = item_count.checked_add(1).ok_or_else(overflow)?;
        if let Some(peaks)=&mut peaks{peaks.header(item.header_span)?;}
        pending.extend(item.children.iter())?;
    }
    drop(pending); // Preflight scratch retires BEFORE the cleanup grant.
    if let Some(peaks)=&mut peaks{peaks.prepare();}
    let mut significant = 0usize;
    let mut statement_lines=1usize;
    let mut cleanup_tokens = 0usize;
    let mut inline = 0usize;
    let mut square_tokens = 0usize;
    let mut square_depth = 0usize;
    let mut malformed = false;
    for (kind, span, spelling) in tokens {
        poll(a)?;
        if let Some(peaks)=&mut peaks{peaks.cover_token(span);}
        if token_statements{
            let newlines=if kind==TokenKind::Newline{spelling.bytes().filter(|&byte|byte==b'\n').count().max(1)}else if matches!(kind,TokenKind::Whitespace|TokenKind::Comment){spelling.bytes().filter(|&byte|byte==b'\n').count()}else{0};
            statement_lines=statement_lines.checked_add(newlines).ok_or_else(overflow)?;
            // Both opening and closing braces can split a nonempty segment.
            // Counting initializer braces too is conservative; string/resource
            // and interpolation spelling never supplies a syntax delimiter.
            if matches!(kind,TokenKind::Punctuation|TokenKind::Operator)&&matches!(spelling,"{"|"}"){statement_lines=statement_lines.checked_add(1).ok_or_else(overflow)?;}
        }
        if matches!(kind, TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment) { continue; }
        significant = significant.checked_add(1).ok_or_else(overflow)?;
        if let Some(peaks)=&mut peaks{peaks.observe(kind,span,spelling)?;}
        let needs_cleanup=!crate::expression_parser::cleanup_leaf_identifier(kind,spelling)
            &&!crate::expression_parser::cleanup_leaf_scalar_token(kind,spelling,original_typed);
        if needs_cleanup { cleanup_tokens=cleanup_tokens.checked_add(1).ok_or_else(overflow)?; }
        // Only genuine delimiter tokens affect this resource mask. A string,
        // resource, interpolation fragment or identifier spelling is not syntax.
        let was_in_square = square_depth != 0;
        if matches!(kind, TokenKind::Punctuation | TokenKind::Operator) {
            match spelling {
                "[" | "?[" => square_depth = square_depth.checked_add(1).ok_or_else(overflow)?,
                "]" if square_depth == 0 => malformed = true,
                "]" => square_depth -= 1,
                _ => (),
            }
        }
        if needs_cleanup && (was_in_square || square_depth != 0) { square_tokens = square_tokens.checked_add(1).ok_or_else(overflow)?; }
        if matches!(spelling, "," | ";" | ":" | "if" | "else" | "for" | "while" | "do" | "spawn" | "switch" | "try" | "catch" | "var") {
            inline = inline.checked_add(1).ok_or_else(overflow)?;
        }
    }
    malformed |= square_depth != 0;
    let peak=match &mut peaks{Some(peaks)=>peaks.finish()?,None=>None};
    let expression_slots=if let Some((expression,actual_inline))=peak{inline=actual_inline;expression}
        else{if malformed { significant.checked_mul(2) }else{cleanup_tokens.checked_add(square_tokens)}.ok_or_else(overflow)?};
    let statement_slots = (if token_statements{statement_lines}else{item_count}).checked_add(inline).ok_or_else(overflow)?;
    // Only NONEMPTY donor Vec metadata enters destructive Statement work.
    // Each row owns a distinct live Statement, so statement_slots bounds rows;
    // existing AST payload accounting retains every donor backing separately.
    let statements = statement_slots.checked_mul(4 * size_of::<Vec<Statement>>()).ok_or_else(overflow)?;
    let expressions = expression_slots.checked_mul(4 * (size_of::<Expr>() + size_of::<SharedSettingRetention>())).ok_or_else(overflow)?;
    let bytes = statements.checked_add(expressions).and_then(|n| n.checked_add(8192)).ok_or_else(overflow)?;
    if bytes>1<<20&&std::env::var_os("DMB_ORIGINAL_TRACE_BODY_PRESSURE").is_some(){
        let diagnostic=peaks.as_ref().map(|p|p.provenance());
        use std::io::Write as _;
        let _=writeln!(std::io::stderr().lock(),"ORIGINAL_BODY_CLEANUP_PEAK_PROVENANCE bytes={bytes} peak_selected={} actual_peak={peak:?} [valid,interpolation,headers,zero_significant_headers,crossing_tokens,token_extent,first_header,last_header,expression_peak,inline,(invalid_spans,overlapping_pairs,outside_extent)]={diagnostic:?}",peak.is_some());
    }
    drop(peaks); // Both scratch buffers retire before the external cleanup grant.
    poll(a)?;
    Ok(BodyCleanupStartupGeometry { bytes, items: item_count, significant_tokens: significant, inline_statement_tokens: inline })
    })();
    // Worklist growth/checkpoints use this SAME admission and may return a
    // sticky kind proxy. Preserve the original IO even on a mid-walk failure.
    result.map_err(|proxy| a.take_operational_error().unwrap_or(proxy))
}

#[derive(Default)]
struct HeaderCleanup {significant:usize,cleanup:usize,squares:usize,square_depth:usize,bad_square:bool,inline:usize,commas:usize,top_commas:usize,bad_groups:bool}
impl HeaderCleanup{
 fn observe(&mut self,kind:TokenKind,spelling:&str,groups:&mut Worklist<'_,'_,u8>)->io::Result<()>{
  self.significant=self.significant.checked_add(1).ok_or_else(overflow)?;
  let coordinated=!crate::expression_parser::cleanup_leaf_identifier(kind,spelling)&&!crate::expression_parser::cleanup_leaf_scalar_token(kind,spelling,true);
  if coordinated{self.cleanup=self.cleanup.checked_add(1).ok_or_else(overflow)?;}
  let was=self.square_depth!=0;
  if matches!(kind,TokenKind::Punctuation|TokenKind::Operator){match spelling{"["|"?["=>self.square_depth=self.square_depth.checked_add(1).ok_or_else(overflow)?,"]" if self.square_depth==0=>self.bad_square=true,"]"=>self.square_depth-=1,_=>()}}
  if coordinated&&(was||self.square_depth!=0){self.squares=self.squares.checked_add(1).ok_or_else(overflow)?;}
  if spelling==","{self.commas=self.commas.checked_add(1).ok_or_else(overflow)?;if groups.as_slice().is_empty(){self.top_commas=self.top_commas.checked_add(1).ok_or_else(overflow)?;}}
  else if matches!(spelling,";"|":"|"if"|"else"|"for"|"while"|"do"|"spawn"|"switch"|"try"|"catch"|"var"){self.inline=self.inline.checked_add(1).ok_or_else(overflow)?;}
  if matches!(kind,TokenKind::Punctuation|TokenKind::Operator){match spelling{
   "("=>groups.push(1)?,"["|"?["=>groups.push(2)?,"{"=>groups.push(3)?,
   ")"=>{if groups.pop()!=Some(1){self.bad_groups=true;}},"]"=>{if groups.pop()!=Some(2){self.bad_groups=true;}},"}"=>{if groups.pop()!=Some(3){self.bad_groups=true;}},_=>()
  }}Ok(())
 }
 fn bounds(&self,unclosed:bool)->io::Result<(usize,usize)>{
  let expression=if self.bad_square||self.square_depth!=0{self.significant.checked_mul(2)}else{self.cleanup.checked_add(self.squares)}.ok_or_else(overflow)?;
  let commas=if self.bad_groups||unclosed{self.commas}else{self.top_commas};
  Ok((expression,self.inline.checked_add(commas).ok_or_else(overflow)?))
 }
}
/// Existing Item.header_span partitions, not another statement parser. Every
/// ordinary statement expression is parsed from a header substring; nested
/// blocks consume their own items. Overlapping/crossing geometry and any
/// missing header coverage retain the complete old bound rather than guessing
/// a scope. Original interpolation children are in the SAME complete flat loan;
/// the typed builder retains their own payload/cleanup before publication.
struct CleanupPeak<'a,'op>{headers:Worklist<'a,'op,Span>,groups:Worklist<'a,'op,u8>,cursor:usize,current:HeaderCleanup,expression:usize,inline:usize,valid:bool,interpolation:bool,token_extent:Option<Span>,zero_significant_headers:usize,crossing_tokens:usize}
impl<'a,'op> CleanupPeak<'a,'op>{
 fn new(a:&'a SettingAdmission<'op>)->io::Result<Self>{Ok(Self{headers:Worklist::new(a)?,groups:Worklist::new(a)?,cursor:0,current:HeaderCleanup::default(),expression:0,inline:0,valid:true,interpolation:false,token_extent:None,zero_significant_headers:0,crossing_tokens:0})}
 fn header(&mut self,span:Span)->io::Result<()>{if span.start>=span.end{self.valid=false;}self.headers.push(span)}
 fn cover_token(&mut self,span:Span){if span.start>span.end{self.valid=false;}self.token_extent=Some(match self.token_extent{Some(prior)=>Span::new(prior.start.min(span.start),prior.end.max(span.end)),None=>span});}
 fn prepare(&mut self){if self.headers.as_slice().is_empty(){self.valid=false;}self.headers.as_mut_slice().sort_unstable_by_key(|span|(span.start,span.end));if self.headers.as_slice().windows(2).any(|pair|pair[0].end>pair[1].start){self.valid=false;}}
 fn finish_header(&mut self)->io::Result<()>{if self.current.significant==0{self.valid=false;self.zero_significant_headers=self.zero_significant_headers.saturating_add(1);}let(expression,inline)=self.current.bounds(!self.groups.as_slice().is_empty())?;self.expression=self.expression.max(expression);self.inline=self.inline.checked_add(inline).ok_or_else(overflow)?;self.current=HeaderCleanup::default();while self.groups.pop().is_some(){}Ok(())}
 fn observe(&mut self,kind:TokenKind,span:Span,spelling:&str)->io::Result<()>{
  if kind==TokenKind::Interpolation{self.interpolation=true;}
  while self.cursor<self.headers.as_slice().len()&&span.start>=self.headers.as_slice()[self.cursor].end{self.finish_header()?;self.cursor+=1;}
  if let Some(header)=self.headers.as_slice().get(self.cursor){
   if span.start>=header.start&&span.end<=header.end{self.current.observe(kind,spelling,&mut self.groups)?;}
   else if span.start<header.end&&span.end>header.start{self.valid=false;self.crossing_tokens=self.crossing_tokens.saturating_add(1);}
  }Ok(())
 }
 // Private diagnostic DATA only. Does not qualify geometry or grant source.
 fn provenance(&self)->(bool,bool,usize,usize,usize,Option<Span>,Option<Span>,Option<Span>,usize,usize,(usize,usize,usize)){
  let headers=self.headers.as_slice();
  (self.valid,self.interpolation,headers.len(),self.zero_significant_headers,self.crossing_tokens,self.token_extent,headers.first().copied(),headers.last().copied(),self.expression,self.inline,
   (headers.iter().filter(|h|h.start>=h.end).count(),headers.windows(2).filter(|p|p[0].end>p[1].start).count(),
   headers.iter().filter(|h|!self.token_extent.is_some_and(|e|h.start>=e.start&&h.end<=e.end)).count()))
 }
 fn finish(&mut self)->io::Result<Option<(usize,usize)>>{
  if !self.token_extent.is_some_and(|extent|self.headers.as_slice().iter().all(|header|header.start>=extent.start&&header.end<=extent.end)){self.valid=false;}
  // Finish every captured header, including ones beyond the last token. An
  // unvisited or trivia-only header cannot qualify a zero cleanup peak.
  while self.cursor<self.headers.as_slice().len(){self.finish_header()?;self.cursor+=1;}
  Ok((self.valid).then_some((self.expression,self.inline)))
 }
}
