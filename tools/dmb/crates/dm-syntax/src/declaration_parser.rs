#[path="original_declaration_storage.rs"]mod original_storage;
#[path="original_demand_layout.rs"]mod demand_layout;
#[path="original_primary_frames.rs"]mod demand_frames;
#[path="original_primary_assembly.rs"]mod demand_assembly;
pub use demand_assembly::{OriginalCommittedPrimary,OriginalPrimaryDemand,OriginalPrimaryLiveHeader,OriginalPrimaryProducerIdentity};
#[path="original_committed_items.rs"]mod committed_items;
pub use committed_items::{OriginalCommittedItems,OriginalItem,OriginalItems};
#[path="original_primary_literal_facts.rs"]mod literal_facts;
pub use literal_facts::{OriginalPrimaryLiteralFacts,OriginalLiteralFactsView,OriginalLiteralRows,OriginalColonRows};
use super::*;

#[derive(Clone,Debug)]
struct Line {
    indent: usize,
    header_start: usize,
    header_end: usize,
    end: usize,
    explicit_block_opener: bool,
    same_line_body: bool,
}

/// Locate an assignment outside argument lists, indexing, strings, and braces.
pub fn top_level_assignment_index(source: &str) -> Option<usize> {
    top_level_assignment_index_from_span_tokens(source, &lex_spans(source).tokens)
}
/// The SAME assignment partition over already-issued primary tokens.
pub fn top_level_assignment_index_from_span_tokens(
    source: &str,
    tokens: &[SpanToken],
) -> Option<usize> {
    top_level_assignment_index_in_window(source, TokenWindow::from_slice(tokens))
}

fn top_level_assignment_index_in_window(source: &str, tokens: TokenWindow<'_>) -> Option<usize> {
    let mut depth = 0usize;
    for token in tokens.iter() {
        if !matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation) {
            continue;
        }
        match token.text(source) {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth = depth.saturating_sub(1),
            "=" if depth == 0 => return Some(token.span.start),
            _ => {}
        }
    }
    None
}
pub(super) fn classify(header:&str,has_children:bool)->ItemKind{
 let h=header.trim();let tokens=lex_spans(h).tokens;classify_primary_header(h,TokenWindow::from_vec(&tokens),Span::new(0,h.len()),has_children)
}
// SAME native classification judge over the actual already-issued primary
// tokens. The demand route must never lex a completed/partial header again.
fn classify_primary_header(source:&str,tokens:TokenWindow<'_>,span:Span,has_children:bool)->ItemKind{
 let raw=&source[span.range()];let h=raw.trim();let begin=span.start+(raw.len()-raw.trim_start().len());let end=begin+h.len();
 let first=tokens.partition_point(|token|token.span.end<=begin);let last=tokens.partition_point(|token|token.span.start<end);let tokens=tokens.range(first,last).expect("ordered primary header token window");
 let assignment=top_level_assignment_index_in_window(source,tokens).map(|at|at-begin);
 let boundary=tokens.iter().find(|token|matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator)&&matches!(token.text(source),"("|"{"|"=")).map_or(h.len(),|token|token.span.start-begin);
    let definition_prefix = &h[..boundary];
    if h.starts_with("set ")
        || h.starts_with("return")
        || h.starts_with("if(")
        || h.starts_with("if (")
        || h.starts_with("for(")
        || h.starts_with("for (")
        || h.starts_with("while(")
        || h.starts_with("while (")
        || h.starts_with("switch(")
        || h.starts_with("switch (")
        || h.starts_with("spawn(")
        || h.starts_with("spawn (")
        || h.starts_with("else")
        || h.starts_with("try")
        || h.starts_with("catch")
        || h.starts_with("break")
        || h.starts_with("continue")
        || h.starts_with("throw ")
        || h.starts_with(".")
    {
        return ItemKind::Statement;
    }
    if definition_prefix.starts_with("var/")
        || definition_prefix.starts_with("/var/")
        || definition_prefix.contains("/var/")
    {
        return ItemKind::Var;
    }
    if definition_prefix.starts_with("proc/")
        || definition_prefix.starts_with("/proc/")
        || definition_prefix.contains("/proc/")
    {
        // A proc-prefixed group without an opening delimiter is a
        // declaration namespace, not an executable body. Keep descendants
        // in declaration mode so skeleton compaction retains the real leaf.
        return if has_children && boundary == h.len() {
            ItemKind::Type
        } else {
            ItemKind::Proc
        };
    }
    if definition_prefix.starts_with("verb/")
        || definition_prefix.starts_with("/verb/")
        || definition_prefix.contains("/verb/")
    {
        return if has_children && boundary == h.len() {
            ItemKind::Type
        } else {
            ItemKind::Verb
        };
    }
    if h.find('(')
        .is_some_and(|open| h.find('{').is_none_or(|brace| open < brace))
    {
        if let Some(open) = h.find('(') {
            if assignment.is_none_or(|index| index > open) {
                return ItemKind::Proc;
            }
        }
    }
    if (h.starts_with('/') && assignment.is_none())
        || (has_children && assignment.is_none())
        || (!h.is_empty() && h.chars().all(ident_continue))
        || (h.contains('/') && h.split('/').all(|part| {
            let mut chars = part.chars();
            chars.next().is_some_and(|first| first.is_ascii_alphabetic() || first == '_')
                && chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
        }))
    {
        return ItemKind::Type;
    }
    if h.contains('=') || h.ends_with(')') {
        return ItemKind::Statement;
    }
    ItemKind::Unknown
}

/// Parse indentation and declaration nesting, preserving all tokens for later expression parsing.
/// A malformed indentation transition produces a diagnostic and parsing continues.
pub fn parse(source: &str) -> AstFile {
    let parsed = parse_with_body_mode(source, false);
    AstFile {
        items: parsed.items,
        tokens: parsed
            .tokens
            .into_iter()
            .map(|token| Token {
                kind: token.kind,
                span: token.span,
                text: token.text(source).to_owned(),
            })
            .collect(),
        diagnostics: parsed.diagnostics,
    }
}

/// Declaration items and source-backed lexical spans. Token text remains in
/// the caller's source rather than a separately allocated string per token.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct DeclarationSkeleton {
    pub items: Vec<Item>,
    pub tokens: Vec<SpanToken>,
    pub diagnostics: Vec<Diagnostic>,
}

/// Parse declarations and exact procedure envelopes while retaining only
/// setting leaves and their structural context inside executable bodies.
/// Lexical and indentation diagnostics use the same grammar as [`parse`].
pub fn parse_declaration_skeleton(source: &str) -> DeclarationSkeleton {
    parse_with_body_mode(source, true)
}

#[cfg(test)]
thread_local! {static WHOLE_LEX_CALLS:std::cell::Cell<usize>=const {std::cell::Cell::new(0)};}
pub(super) fn parse_with_body_mode(source: &str, skeleton: bool) -> DeclarationSkeleton {
    #[cfg(test)]
    WHOLE_LEX_CALLS.with(|n| n.set(n.get() + 1));
    let lexed = lex_spans(source);
    let (items, mut diagnostics) =
        parse_original_span_range(source, Span::new(0, source.len()), &lexed.tokens, skeleton);
    let mut lexical = lexed.diagnostics;
    lexical.append(&mut diagnostics);
    DeclarationSkeleton {
        items,
        tokens: lexed.tokens,
        diagnostics: lexical,
    }
}
/// Internal grammar over borrowed ORIGINAL primary spans. Does not certify a
/// source acquisition, current semantic owner, or completeness on its own.
pub(super) fn parse_original_span_range(
    source: &str,
    range: Span,
    tokens: &[SpanToken],
    skeleton: bool,
) -> (Vec<Item>, Vec<Diagnostic>) {
    parse_original_span_range_in_window(source,range,TokenWindow::from_slice(tokens),skeleton)
}
pub(super) fn parse_original_span_range_in_window(source:&str,range:Span,tokens:TokenWindow<'_>,skeleton:bool)->(Vec<Item>,Vec<Diagnostic>){
    parse_original_span_range_with_outcome(source,range,tokens,skeleton,None,None)
}
// The rows use sealed TU coordinates, while token spans are local to the
// caller's authenticated SourceText view. This is layout DATA only.
type LayoutLiteralRows<'a> = (OriginalLiteralRows<'a>,usize);
pub(super) fn parse_original_body_span_range_in_window(source:&str,range:Span,tokens:TokenWindow<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>)->(Vec<Item>,Vec<Diagnostic>){
    parse_original_span_range_with_outcome(source,range,tokens,false,None,facts.as_ref().map(|view|view.raw_parts()))
}
fn parse_original_span_range_with_outcome(source:&str,range:Span,tokens:TokenWindow<'_>,skeleton:bool,original:Option<&OriginalParseState<'_,'_,'_>>,facts:Option<LayoutLiteralRows<'_>>)->(Vec<Item>,Vec<Diagnostic>){
    let layout=original.and_then(|state|state.storage.layout(source,tokens,std::mem::size_of::<Line>()));
    if original.is_some()&&layout.is_none(){return(Vec::new(),Vec::new())}
    let lines = original_declaration_lines_in_window(source,range,tokens,original,facts);
    let mut diagnostics = Vec::new();
    let (items, _) = parse_level(
        source,
        &lines,
        0,
        0,
        ParseContext {
            in_body: false,
            skeleton,
            tokens,
            original,
            var_context:None,
        },
        &mut diagnostics,
    );
    (items, diagnostics)
}

fn original_declaration_lines(source:&str,range:Span,tokens:&[SpanToken])->Vec<Line>{original_declaration_lines_with_storage(source,range,tokens,None)}
// Actual native source masks advanced over newly issued complete tokens only.
// Existing primary layout admission owns these buffers; no source/model grant.
#[derive(Default)]struct NativeLayoutMaskCursor{
 visible:String,delimiters:Vec<u8>,multiline_literals:Vec<Span>,tokens:usize,
 #[cfg(test)] visible_appended_bytes:usize,
}
impl NativeLayoutMaskCursor{
 #[cfg(test)]
 fn advance(&mut self,source:&str,range:Span,tokens:&[SpanToken],original:Option<&OriginalParseState<'_,'_,'_>>)->bool{self.advance_with_literal_facts(source,range,TokenWindow::from_slice(tokens),original,None)}
 fn advance_with_literal_facts(&mut self,source:&str,range:Span,tokens:TokenWindow<'_>,original:Option<&OriginalParseState<'_,'_,'_>>,facts:Option<LayoutLiteralRows<'_>>)->bool{
  let Some(text)=source.get(range.range())else{return false};
  if self.visible.len()>text.len()||self.tokens>tokens.len(){return false}
  let old=self.visible.len();let Some(tail)=text.get(old..)else{return false};
  self.delimiters.extend_from_slice(tail.as_bytes());
  // The prior visible prefix is already a valid String. Only append newly
  // issued raw gaps and ASCII masks; never validate or rewrite that prefix.
  let mut visible_cursor=old;
  for token in tokens.range(self.tokens,tokens.len()).expect("checked mask token frontier").iter(){
   if original.is_some_and(|state|!state.poll()){return false}
   if token.span.start<range.start+old||token.span.end>range.end||token.span.end<token.span.start{return false}
   let Some(raw)=source.get(token.span.range())else{return false};
   let multiline=matches!(token.kind,TokenKind::String|TokenKind::Interpolation)&&raw.contains('\n');
   let visible_mask=token.kind==TokenKind::Comment||multiline;
   let delimiter_mask=visible_mask||matches!(token.kind,TokenKind::String|TokenKind::Resource|TokenKind::Interpolation);
   if visible_mask{
    let Some(gap)=text.get(visible_cursor..token.span.start-range.start)else{return false};
    self.append_visible(gap);
   }
   if visible_mask||delimiter_mask{for(at,byte)in raw.as_bytes().iter().enumerate(){
    if at%1024==0&&original.is_some_and(|state|!state.poll()){return false}
    if visible_mask{
     self.visible.push(if matches!(*byte,b'\r'|b'\n'){char::from(*byte)}else{' '});
     #[cfg(test)]{self.visible_appended_bytes+=1;}
    }
    if !matches!(*byte,b'\r'|b'\n')&&delimiter_mask{self.delimiters[token.span.start-range.start+at]=b' ';}
   }}
   if visible_mask{visible_cursor=token.span.end-range.start;}
   if token.kind==TokenKind::Interpolation{
    let Some((facts,origin))=facts else{return false};
    let Some(start)=origin.checked_add(token.span.start)else{return false};
    let Some(finish)=origin.checked_add(token.span.end)else{return false};
    let at=facts.partition_point(|(span,_)|span.start<start);
    let Some((_,data))=facts.get(at).filter(|(span,_)|*span==Span::new(start,finish))else{return false};
    if match data.raw(){Ok(raw)=>raw!=token.text(source),Err(error)=>{if let Some(state)=original{state.storage.a.record_operational_error(error);}return false}}{return false}
    let begin=token.span.start-range.start;let Some(end)=token.span.end.checked_sub(range.start+1)else{return false};if begin>end{return false}
    // Boundary positions are issued by the actual typed fragment product;
    // neither the literal payload nor its child spelling is scanned for '['.
    let value=match data.value(){Ok(value)=>value,Err(error)=>{if let Some(state)=original{state.storage.a.record_operational_error(error);}return false}};
    match value{crate::OriginalTokenValue::InterpBegin(_)=>self.delimiters[end]=b'[',crate::OriginalTokenValue::InterpPart(_)=>{self.delimiters[begin]=b']';self.delimiters[end]=b'[';},crate::OriginalTokenValue::InterpEnd(_)=>self.delimiters[begin]=b']',_=>return false}
   }
   if multiline&&!push_layout(&mut self.multiline_literals,Span::new(token.span.start-range.start,token.span.end-range.start),original){return false}
  }
  let Some(tail)=text.get(visible_cursor..)else{return false};
  self.append_visible(tail);
  self.tokens=tokens.len();true
 }
 fn append_visible(&mut self,raw:&str){
  self.visible.push_str(raw);
  #[cfg(test)]{self.visible_appended_bytes+=raw.len();}
 }
 fn visible(&self)->&str{self.visible.as_str()}
}
fn original_declaration_lines_with_storage(source:&str,range:Span,tokens:&[SpanToken],original:Option<&OriginalParseState<'_,'_,'_>>)->Vec<Line>{
 original_declaration_lines_in_window(source,range,TokenWindow::from_slice(tokens),original,None)
}
fn original_declaration_lines_in_window(source:&str,range:Span,tokens:TokenWindow<'_>,original:Option<&OriginalParseState<'_,'_,'_>>,facts:Option<LayoutLiteralRows<'_>>)->Vec<Line>{
 let mut masks=NativeLayoutMaskCursor::default();if !masks.advance_with_literal_facts(source,range,tokens,original,facts){return Vec::new()}
 let range_source=&source[range.range()];let visible=masks.visible();
 let physical=NativeStructuralCursor::default().advance(visible,&masks.delimiters,&masks.multiline_literals,original,source,tokens,range.start,true).expect("fresh final native structural input has actual mask geometry");
 let mut lines=NativeInlineBlockCursor::default().advance(range_source,&physical,&masks.delimiters,original,source,tokens,range.start);
 for line in &mut lines{line.header_start+=range.start;line.header_end+=range.start;line.end+=range.start;}lines
}

/// Read-only DATA issued by the SAME native primary declaration layout. This
/// cannot issue a frontend, current-source receipt or compiler acceptance.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalOuterTerminatorObservation{first_block_probe:Option<usize>}
impl OriginalOuterTerminatorObservation{pub fn first_block_probe(self)->Option<usize>{self.first_block_probe}}
/// Existing actual callable header roster + its original primary token lease.
/// No body parse or normalized declaration model is built. Explicit empty {},
/// indented bodies and same-line bodies retain their true grammar distinction.
pub fn original_outer_terminator_observation_using(source:&str,tokens:&[SpanToken],headers:&[Span],checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Result<OriginalOuterTerminatorObservation,&'static str>,std::io::Error>{
 original_outer_terminator_observation_in_window_using(source,TokenWindow::from_slice(tokens),headers,checkpoint)
}
pub fn original_outer_terminator_observation_in_window_using(source:&str,tokens:TokenWindow<'_>,headers:&[Span],checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Result<OriginalOuterTerminatorObservation,&'static str>,std::io::Error>{
 checkpoint()?;for token in tokens.iter(){checkpoint()?;if source.get(token.span.range()).is_none(){return Ok(Err("outer terminator primary token escapes current source"))}}
 let lines=original_declaration_lines_in_window(source,Span::new(0,source.len()),tokens,None,None);checkpoint()?;let mut first=None;
 for header in headers{checkpoint()?;let Ok(index)=lines.binary_search_by_key(&header.start,|line|line.header_start)else{return Ok(Err("outer terminator callable header absent from actual primary layout"))};let line=&lines[index];if line.header_end!=header.end{return Ok(Err("outer terminator callable header differs from actual primary layout"))}let indented=lines.get(index+1).is_some_and(|next|next.indent>line.indent);let probe=original_line_outer_probe(source,tokens,line,indented,checkpoint)?;
  if let Some(at)=probe{first=Some(first.map_or(at,|old:usize|old.min(at)));}}
 checkpoint()?;Ok(Ok(OriginalOuterTerminatorObservation{first_block_probe:first}))
}

fn original_line_outer_probe<E>(source:&str,tokens:TokenWindow<'_>,line:&Line,indented:bool,checkpoint:&dyn Fn()->Result<(),E>)->Result<Option<usize>,E>{
 let mut probe=(line.explicit_block_opener||indented&&!line.same_line_body).then_some(line.header_end);
  if line.same_line_body{let start=tokens.partition_point(|token|token.span.start<line.header_end);let mut group=0usize;for token in tokens.iter().skip(start){checkpoint()?;if token.kind==TokenKind::Comment{continue}if group==0&&(token.kind==TokenKind::Newline||matches!(token.text(source),";"|"}")){break}if !matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator){continue}match token.text(source){"("|"["=>{/* Every open consumes one element of this already allocated nonzero-sized token slice. Depth <= tokens.len() < usize::MAX; no allocation or fallible arithmetic occurs. */group+=1},")"|"]"=>{group=group.saturating_sub(1)},"{" if group==0=>{probe=Some(token.span.start);break},_=>{}}}}
 Ok(probe)
}

// SAME physical-layout state carried across native expansion demand pauses.
// This owns scalar/pending-line DATA only; it cannot issue syntax/model/EOF.
#[derive(Default)]struct NativeStructuralCursor{
 offset:usize,pending:Option<Line>,depth:usize,literal_cursor:usize,
 initializer_depth:usize,block_depth:usize,procedure:Option<(usize,usize)>,
 pending_in_body:bool,pending_block_start:usize,pending_physical_indent:usize,procedure_scope_exact:bool,finished:bool,early_physical:Option<usize>,
}
struct NativePrimaryHeaderStart{line:Line}
impl NativeStructuralCursor{
 /// Same physical indentation/procedure-scope transition, also exposed before
 /// complete header lookahead. Neither event nor state certifies source EOF.
 fn begin_physical_scope(&mut self,physical_indent:usize,trimmed:&str){
  if self.pending.is_none()&&!trimmed.is_empty()&&self.early_physical!=Some(self.offset){
   if self.procedure.is_some_and(|(indent,base)|physical_indent<=indent&&self.block_depth<=base){self.procedure=None;}
   self.pending_in_body=self.procedure.is_some();self.pending_block_start=self.block_depth;self.pending_physical_indent=physical_indent;
  }
 }
 fn partial_header_start(&mut self,visible:&str,range_start:usize)->Option<NativePrimaryHeaderStart>{
  if self.finished||self.pending.is_some()||self.early_physical==Some(self.offset)||self.offset>=visible.len(){return None}
  let raw=&visible[self.offset..];let leading=raw.bytes().take_while(|b|matches!(b,b' '|b'\t')).count();let trimmed=raw[leading..].trim_end_matches(['\r','\n',' ','\t']);if trimmed.is_empty(){return None}
  let physical_indent=raw[..leading].bytes().map(|b|if b==b'\t'{4}else{1}).sum();self.begin_physical_scope(physical_indent,trimmed);
  // Formal declarations cannot originate in actual active procedure-body
  // scope. Their ordinary statement route remains with the shared body parser.
  if self.pending_in_body{return None}self.early_physical=Some(self.offset);
  Some(NativePrimaryHeaderStart{line:Line{indent:if trimmed.starts_with('/'){0}else{physical_indent},header_start:range_start+self.offset+leading,header_end:range_start+self.offset+leading+trimmed.len(),end:range_start+visible.len(),explicit_block_opener:false,same_line_body:false}})
 }

 fn advance(&mut self,visible:&str,delimiters:&[u8],multiline_literals:&[Span],original:Option<&OriginalParseState<'_,'_,'_>>,source:&str,tokens:TokenWindow<'_>,range_start:usize,final_input:bool)->std::io::Result<Vec<Line>>{
  if self.finished||self.offset>visible.len()||!visible.is_char_boundary(self.offset)||delimiters.len()!=visible.len(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native structural cursor is finished or outside its actual masked arena"))}
  if !final_input&&!visible.is_empty()&&!visible.ends_with('\n'){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"native structural demand pauses only at an actual physical newline; no fabricated EOF"))}
  let available_start=self.offset;let mut lines=Vec::new();
    for raw in visible[available_start..].split_inclusive('\n') {
        if original.is_some_and(|state|!state.poll()){break}
        while multiline_literals
            .get(self.literal_cursor)
            .is_some_and(|literal| literal.end <= self.offset)
        {
            self.literal_cursor += 1;
        }
        let leading = raw
            .bytes()
            .take_while(|b| *b == b' ' || *b == b'\t')
            .count();
        let trimmed = raw[leading..].trim_end_matches(['\r', '\n', ' ', '\t']);
        let physical_indent:usize=raw[..leading].bytes().map(|byte|if byte==b'\t'{4}else{1}).sum();
        self.begin_physical_scope(physical_indent,trimmed);
        let segment_start=self.pending.as_ref().map_or(self.offset+leading,|line|line.header_start);
        for at in self.offset..self.offset+raw.len(){
            if at%1024==0&&original.is_some_and(|state|!state.poll()){return Ok(lines)}
            match delimiters[at]{
                b'(' | b'['=>self.depth+=1,
                b')' | b']'=>self.depth=self.depth.saturating_sub(1),
                b'{' if self.initializer_depth > 0 || (self.depth == 0
                    && (self.pending_in_body || !typed_procedure_header(visible, delimiters, segment_start, at))
                    && is_object_initializer_primary(&visible[segment_start..at],self.pending_in_body,original.map(|state|(source,tokens,Span::new(range_start+segment_start,range_start+at),state))))=>self.initializer_depth+=1,
                b'}' if self.initializer_depth>0=>self.initializer_depth-=1,
                b'{' if self.depth==0=>self.block_depth+=1,
                b'}' if self.depth==0=>self.block_depth=self.block_depth.saturating_sub(1),
                _=>()
            }
        }
        if !trimmed.is_empty() && !trimmed.starts_with("//") {
            if let Some(line) = self.pending.as_mut() {
                line.header_end = self.offset + leading + trimmed.len();
                line.end = self.offset + raw.len();
            } else {
                // An included file's first line can inherit spaces left by
                // the expanded #include directive. Absolute DM paths declare
                // from the root regardless of that textual indentation.
                // Absolute executable expressions retain the SAME actual body
                // scope. Normalizing them to root indentation would send a
                // static-scope call to the declaration/formal observer.
                if trimmed.starts_with('/')&&self.pending_in_body&&!self.procedure_scope_exact{
                    if let Some(state)=original{if state.operational.borrow().is_none(){*state.unavailable.borrow_mut()=Some("Original absolute-line body scope needs actual indentation provenance");}return Ok(lines)}
                }
                let absolute_body=self.pending_in_body&&(self.procedure_scope_exact||trimmed.find('{').is_some_and(|at|bare_prefab(&trimmed[..at])));
                let indent = if trimmed.starts_with('/') && !absolute_body {
                    0
                } else {
                    raw[..leading]
                        .bytes()
                        .map(|b| if b == b'\t' { 4 } else { 1 })
                        .sum()
                };
                self.pending = Some(Line {
                    indent,
                    header_start: self.offset + leading,
                    header_end: self.offset + leading + trimmed.len(),
                    explicit_block_opener: false,
                    same_line_body: false,
                    end: self.offset + raw.len(),
                });
            }
        } else if let Some(line) = self.pending.as_mut() {
            line.end = self.offset + raw.len();
        }
        let mut inside_literal = false;
        for literal in multiline_literals[self.literal_cursor..]
            .iter()
            .take_while(|literal| literal.start < self.offset + raw.len())
        {
            if let Some(line) = self.pending.as_mut() {
                line.header_end = line.header_end.max(literal.end.min(self.offset + raw.len()));
            }
            inside_literal |= literal.end > self.offset + raw.len();
        }
        if self.depth == 0 && self.initializer_depth==0 && !inside_literal {
            if let Some(line) = self.pending.take() {
                if !self.pending_in_body&&callable_header(&visible[line.header_start..line.header_end]){self.procedure=Some((line.indent,self.pending_block_start));self.procedure_scope_exact=self.pending_physical_indent==line.indent;}
                if !push_layout(&mut lines,line,original){return Ok(lines)}
            }
        }
        self.offset += raw.len();self.early_physical=None;
    }
  if final_input{if let Some(line)=self.pending.take(){if !push_layout(&mut lines,line,original){return Ok(lines)}}self.finished=true;}
  Ok(lines)
 }
}
#[cfg(test)]
fn structural_lines(visible:&str,delimiters:&[u8],multiline_literals:&[Span],original:Option<&OriginalParseState<'_,'_,'_>>,source:&str,tokens:&[SpanToken],range_start:usize)->Vec<Line>{
 NativeStructuralCursor::default().advance(visible,delimiters,multiline_literals,original,source,TokenWindow::from_slice(tokens),range_start,true).expect("fresh final native structural input has actual mask geometry")
}

// SAME native inline/block splitter state; committed physical lines are fed
// once, not reinterpreted as a whole-prefix parse at each demand boundary.
#[derive(Default)]struct NativeInlineBlockCursor{brace_depth:usize,initializer_depth:usize,procedure:Option<(usize,usize)>}
impl NativeInlineBlockCursor{
 /// Project the SAME current inline scope before a callable's formal pull.
 /// A real generated/explicit brace has already updated this state. No
 /// lookahead, scope guess, header relex or alternate traversal is performed.
 fn live_header_start(&mut self,mut start:NativePrimaryHeaderStart)->std::io::Result<Option<NativePrimaryHeaderStart>>{
  if self.procedure.is_some_and(|(indent,base)|start.line.indent<=indent&&self.brace_depth<=base){self.procedure=None;}
  if self.procedure.is_some()||self.initializer_depth!=0{return Ok(None)}
  start.line.indent=start.line.indent.checked_add(self.brace_depth.checked_mul(4).ok_or(std::io::ErrorKind::OutOfMemory)?).ok_or(std::io::ErrorKind::OutOfMemory)?;Ok(Some(start))
 }

 fn advance(&mut self,source:&str,lines:&[Line],delimiters:&[u8],original:Option<&OriginalParseState<'_,'_,'_>>,raw_source:&str,tokens:TokenWindow<'_>,range_start:usize)->Vec<Line>{
  let mut result=Vec::new();
    for line in lines {
        if original.is_some_and(|state|!state.poll()){break}
        if self.procedure.is_some_and(|(indent,base)|line.indent<=indent&&self.brace_depth<=base){self.procedure=None;}
        let in_body=self.procedure.is_some();
        let block_start=self.brace_depth;
        let opens_procedure=callable_header(&source[line.header_start..line.header_end]);
        let mut segment_start = line.header_start;
        let mut paren_depth = 0usize;
        let mut inline_do_if = false;
        for at in line.header_start..line.header_end {
            if at%1024==0&&original.is_some_and(|state|!state.poll()){return result}
            match delimiters[at] {
                b'(' | b'[' => paren_depth += 1,
                b')' | b']' => paren_depth = paren_depth.saturating_sub(1),
                b'{' if paren_depth == 0
                    && (self.initializer_depth > 0
                        || (in_body || self.brace_depth != block_start
                            || !typed_procedure_header(source, delimiters, segment_start, at))
                            && is_object_initializer_primary(&source[segment_start..at],in_body||(opens_procedure&&self.brace_depth>block_start),original.map(|state|(raw_source,tokens,Span::new(range_start+segment_start,range_start+at),state)))) =>
                {
                    self.initializer_depth += 1;
                }
                b'}' if paren_depth == 0 && self.initializer_depth > 0 => {
                    self.initializer_depth -= 1;
                }
                b'{' | b'}' | b';' if paren_depth == 0 && self.initializer_depth == 0 => {
                    let segment = &source[segment_start..at];
                    if delimiters[at] == b';' && !in_body && opens_procedure
                        && segment_start == line.header_start
                    {
                        push_inline_procedure_segment(
                            &mut result, source, delimiters, segment_start, at,
                            line.indent + self.brace_depth * 4, original,
                        );
                    } else if let Some(do_at) = (delimiters[at] == b'{' && !inline_do_if)
                        .then(|| inline_if_do_suffix(segment))
                        .flatten()
                    {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            segment_start + do_at,
                            line.indent + self.brace_depth * 4, original);
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start + do_at,
                            at,
                            line.indent + self.brace_depth * 4 + 4, original);
                        inline_do_if = true;
                    } else {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            at,
                            line.indent + self.brace_depth * 4 + usize::from(inline_do_if) * 4, original);
                    }
                    if delimiters[at] == b'{' {
                        if let Some(header)=result.last_mut(){header.explicit_block_opener=true;}
                        self.brace_depth += 1;
                    } else if delimiters[at] == b'}' {
                        self.brace_depth = self.brace_depth.saturating_sub(1);
                    } else if self.brace_depth == 0
                        && inline_do_if
                        && segment.trim_start().starts_with("while")
                    {
                        inline_do_if = false;
                    }
                    segment_start = at + 1;
                }
                _ => {}
            }
        }
        if !in_body&&callable_header(&source[line.header_start..line.header_end]){self.procedure=Some((line.indent,block_start));}
        let indent = line.indent + self.brace_depth * 4 + usize::from(inline_do_if) * 4;
        push_inline_procedure_segment(
            &mut result, source, delimiters, segment_start, line.header_end, indent, original,
        );
    }
  result
 }
}
#[cfg(test)]
fn split_inline_blocks(source:&str,lines:&[Line],delimiters:&[u8],original:Option<&OriginalParseState<'_,'_,'_>>,raw_source:&str,tokens:&[SpanToken],range_start:usize)->Vec<Line>{
 NativeInlineBlockCursor::default().advance(source,lines,delimiters,original,raw_source,TokenWindow::from_slice(tokens),range_start)
}

fn push_inline_procedure_segment(
    rows: &mut Vec<Line>,
    source: &str,
    delimiters: &[u8],
    start: usize,
    end: usize,
    indent: usize,
    original: Option<&OriginalParseState<'_, '_, '_>>,
) {
    let Some(body_start) = inline_proc_body_start(source, delimiters, start, end) else {
        push_inline_segment(rows, source, start, end, indent, original);
        return;
    };
    let position = rows.len();
    push_inline_segment(rows, source, start, body_start, indent, original);
    if let Some(header) = rows.get_mut(position) {
        header.same_line_body = true;
        push_inline_segment(rows, source, body_start, end, indent + 4, original);
    }
}

fn inline_proc_body_start(
    source: &str,
    delimiters: &[u8],
    start: usize,
    end: usize,
) -> Option<usize> {
    let tail = inline_proc_tail_start(source, delimiters, start, end)?;
    (tail < end && !is_return_annotation(&source[tail..end])).then_some(tail)
}

fn typed_procedure_header(source: &str, delimiters: &[u8], start: usize, end: usize) -> bool {
    callable_header(&source[start..end])
        && inline_proc_tail_start(source, delimiters, start, end)
            .is_some_and(|tail| is_return_annotation(&source[tail..end]))
}

fn is_return_annotation(tail: &str) -> bool {
    // A projected keyword can touch the opening punctuation of a return type.
    tail.strip_prefix("as").and_then(|rest| rest.chars().next())
        .is_some_and(|next| next.is_whitespace() || matches!(next, '/' | '('))
}

fn inline_proc_tail_start(
    source: &str,
    delimiters: &[u8],
    start: usize,
    end: usize,
) -> Option<usize> {
    let segment = source[start..end].trim_start();
    let opening = segment.find('(')?;
    // A value-call inside prefab modifiers is not an inline proc signature.
    if segment.find('{').is_some_and(|brace|brace<opening){return None}
    let prefix = segment[..opening].trim();
    if !(prefix.starts_with("proc/")
        || prefix.starts_with("verb/")
        || prefix.starts_with("/proc/")
        || prefix.starts_with("/verb/")
        || prefix.contains("/proc/")
        || prefix.contains("/verb/")
        || (prefix.starts_with('/')
            && !prefix.chars().any(char::is_whitespace)
            && top_level_assignment_index(prefix).is_none()))
    {
        return None;
    }
    let absolute_open = start + source[start..end].find('(')?;
    let mut depth = 0usize;
    for at in absolute_open..end {
        match delimiters[at] {
            b'(' => depth += 1,
            b')' => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    let body_start =
                        at + 1 + source[at + 1..end].len() - source[at + 1..end].trim_start().len();
                    return Some(body_start);
                }
            }
            _ => {}
        }
    }
    None
}

fn inline_if_do_suffix(segment: &str) -> Option<usize> {
    let trimmed = segment.trim();
    if !(trimmed.starts_with("if(") || trimmed.starts_with("if (")) || !trimmed.ends_with("do") {
        return None;
    }
    let at = segment.rfind("do")?;
    segment[..at]
        .chars()
        .next_back()
        .filter(|ch| ch.is_whitespace())
        .map(|_| at)
}

pub(super) fn bare_prefab(prefix:&str)->bool{let prefix=prefix.trim();prefix.starts_with('/')&&prefix.chars().all(|ch|ident_continue(ch)||matches!(ch,'/'|'.'|':'))}
fn callable_header(header:&str)->bool{
 let header=header.trim();let Some(open)=header.find('(')else{return false};let prefix=header[..open].trim();!prefix.is_empty()&&!prefix.chars().any(char::is_whitespace)&&!prefix.contains(['=','{','}'])&&!matches!(prefix,"if"|"for"|"while"|"switch"|"spawn"|"catch")
}
fn is_object_initializer_primary(prefix:&str,in_body:bool,primary:Option<(&str,TokenWindow<'_>,Span,&OriginalParseState<'_,'_,'_>)>)->bool{
 if let Some((source,tokens,span,state))=primary{if in_body&&bare_prefab(prefix){return true}let token=prefix.split_whitespace().next_back().unwrap_or("");if !token.contains('/')||token.ends_with(')')||token.ends_with(']'){return false}if prefix.contains('=')||prefix.contains('(')||prefix.contains(','){return true}let first=tokens.partition_point(|token|token.span.end<=span.start);let last=tokens.partition_point(|token|token.span.start<span.end);for token in tokens.range(first,last).expect("ordered initializer token window").iter(){if !state.poll(){return false}if token.kind==TokenKind::Ident&&token.text(source)=="new"{return true}}return false}is_object_initializer(prefix,in_body)
}
fn push_layout<T>(rows:&mut Vec<T>,value:T,original:Option<&OriginalParseState<'_,'_,'_>>)->bool{
 if let Some(state)=original{if !state.poll(){return false}if rows.len()==rows.capacity(){let Some(capacity)=rows.capacity().max(2).checked_mul(2)else{return state.storage.fail(std::io::ErrorKind::OutOfMemory.into())};let mut next=Vec::new();if let Err(actual)=next.try_reserve_exact(capacity){return state.storage.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))}let Some(max_capacity)=capacity.checked_mul(4)else{return state.storage.fail(std::io::ErrorKind::OutOfMemory.into())};if next.capacity()>max_capacity{return state.storage.fail(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary layout allocator exceeded admitted token geometry"))}next.append(rows);*rows=next;}}
 rows.push(value);true
}
fn is_object_initializer(prefix: &str,in_body:bool) -> bool {
    if in_body&&bare_prefab(prefix){return true}
    let token = prefix.split_whitespace().next_back().unwrap_or("");
    token.contains('/')
        && !token.ends_with(')')
        && !token.ends_with(']')
        && (prefix.contains('=')
            || lex_spans(prefix)
                .tokens
                .iter()
                .any(|token| token.kind == TokenKind::Ident && token.text(prefix) == "new")
            || prefix.contains('(')
            || prefix.contains(','))
}

fn push_inline_segment(
    lines: &mut Vec<Line>,
    source: &str,
    start: usize,
    end: usize,
    indent: usize,
    original:Option<&OriginalParseState<'_,'_,'_>>,
) {
    let segment = &source[start..end];
    let trimmed_start = segment.len() - segment.trim_start().len();
    let trimmed_end = segment.trim_end().len();
    if trimmed_end <= trimmed_start {
        return;
    }
    push_layout(lines,Line {
        indent,
        header_start: start + trimmed_start,
        header_end: start + trimmed_end,
        explicit_block_opener: false,
        same_line_body: false,
        end: start + trimmed_end,
    },original);
}

/// Only borrowed tokens from THIS primary lex pass participate. Normalized
/// header strings and offsets from another source are never consulted.
/// Reissue only lexical header facts over an existing native declaration roster.
/// This is the SAME primary lexer and cursor rule used during initial parsing;
/// no declaration/body parser, adapter, or semantic model is reconstructed.
pub fn primary_header_cursors(
    source: &str,
    headers: impl IntoIterator<Item = Span>,
) -> Result<Vec<(usize, Option<usize>)>, Vec<Diagnostic>> {
    let lexed = lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err(lexed.diagnostics);
    }
    Ok(headers
        .into_iter()
        .map(|header| {
            (
                header.start,
                source
                    .get(header.range())
                    .and_then(|_| primary_declaration_cursor(source, TokenWindow::from_vec(&lexed.tokens), header)),
            )
        })
        .collect())
}
/// Existing native roster plus its ORIGINAL parent links; no new syntax tree.
#[derive(Clone, Copy)]
pub struct PrimaryHeaderInput {
    pub span: Span,
    pub parent: Option<usize>,
    pub has_children: bool,
}
/// One shared primary lexical query issues cursor AND scoped qualifier facts.
/// Parent indices must refer strictly backward to the borrowed roster.
pub fn primary_header_facts(
    source: &str,
    headers: &[PrimaryHeaderInput],
) -> Result<Vec<(usize, Option<usize>, u8)>, Vec<Diagnostic>> {
    let lexed = lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err(lexed.diagnostics);
    }
    let mut rows = Vec::with_capacity(headers.len());
    let mut contexts = Vec::with_capacity(headers.len());
    for (index, header) in headers.iter().enumerate() {
        let parent = match header.parent {
            Some(parent) if parent < index => contexts[parent],
            Some(_) => None,
            None => None,
        };
        let local = if header.parent.is_some_and(|parent| parent >= index) {
            crate::UNKNOWN_HEADER_QUALIFIERS
        } else {
            crate::declaration_qualifiers::primary_header_qualifiers(
                source,
                TokenWindow::from_vec(&lexed.tokens),
                header.span,
                header.has_children,
            )
        };
        let (flags, context) = crate::inherit_header_qualifiers(local, parent);
        contexts.push(context);
        rows.push((
            header.span.start,
            primary_declaration_cursor(source, TokenWindow::from_vec(&lexed.tokens), header.span),
            flags,
        ));
    }
    Ok(rows)
}
fn primary_declaration_cursor(source: &str, tokens: TokenWindow<'_>, header: Span) -> Option<usize> {
    let first = tokens.partition_point(|token| token.span.end <= header.start);
    let end = tokens.partition_point(|token| token.span.start < header.end);
    let mut depth = 0usize;
    let mut last = None;
    let mut last_end = None;
    for token in tokens.range(first, end)?.iter() {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            continue;
        }
        // Raw preprocessing syntax (notably backslash continuation) has no
        // primary declaration meaning before the existing preprocess pass.
        // Never turn its following newline into an invented declaration token.
        if token.kind == TokenKind::Unknown {
            return None;
        }
        match token.text(source) {
            "=" if depth == 0 => return Some(token.span.start),
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth = depth.checked_sub(1)?,
            _ => (),
        }
        last = Some(token.span.start);
        last_end = Some(token.span.end);
    }
    if depth != 0 {
        return None;
    }
    // Pinned declarations without an initializer observe their terminator.
    // A multiline comment/doc cursor remains unsupported, rather than guessed.
    for token in tokens.iter().skip(end) {
        match token.kind {
            TokenKind::Whitespace => continue,
            TokenKind::Comment => {
                if token.text(source).contains(['\r', '\n']) {
                    return None;
                }
                continue;
            }
            TokenKind::Newline => return Some(token.span.start),
            _ if matches!(token.text(source), ";" | "}" | ",") => return Some(token.span.start),
            _ => return None,
        }
    }
    // Pinned IndentProcessor's final synthetic semicolon uses last_input_loc,
    // not EOF end. A final significant token proves that cursor only if it
    // reaches EOF; trailing whitespace/comments have another token policy.
    if last_end == Some(source.len()) {
        last
    } else {
        None
    }
}

#[derive(Clone, Copy)]
struct ParseContext<'a,'observer,'budget> {
    in_body: bool,
    skeleton: bool,
    tokens: TokenWindow<'a>,
    original:Option<&'a OriginalParseState<'a,'observer,'budget>>,
    var_context:Option<u8>,
}

fn body_keyword(header: &str, keyword: &str) -> bool {
    header
        .trim_start()
        .strip_prefix(keyword)
        .is_some_and(|tail| {
            tail.is_empty() || tail.starts_with(char::is_whitespace) || tail.starts_with('(')
        })
}

pub(crate) const RETURN_BLOCK_UNSUPPORTED: &str = ": missing expression";
pub(crate) fn return_has_block(header: &str, has_children: bool) -> bool {
    has_children && body_keyword(header, "return")
}

fn retain_setting_chains(items:Vec<Item>,original:Option<&OriginalParseState<'_,'_,'_>>)->Vec<Item>{
 fn has_setting(item:&Item,original:Option<&OriginalParseState<'_,'_,'_>>)->bool{
  if original.is_some_and(|state|!state.poll()){return false}
  // In Original skeleton mode each child list has already undergone this
  // same compaction. Every retained nonempty child list contains a real set.
  // Avoid rescanning every surviving descendant at each enclosing level.
  body_keyword(&item.header,"set")||match original{Some(_)=>!item.children.is_empty(),None=>item.children.iter().any(|item|has_setting(item,None))}
 }
 fn discard(item:Item,original:Option<&OriginalParseState<'_,'_,'_>>)->bool{match original{Some(state)=>state.storage.discard_item(item),None=>{drop(item);true}}}
 let old_capacity=items.capacity();let mut input=items.into_iter().peekable();let mut result=Vec::new();
 while let Some(item)=input.next(){if original.is_some_and(|state|!state.poll()){return Vec::new()}
  if body_keyword(&item.header,"if"){
   let mut chain=Vec::new();if !push_layout(&mut chain,item,original){return Vec::new()}
   while input.peek().is_some_and(|item|body_keyword(&item.header,"else")){if !push_layout(&mut chain,input.next().unwrap(),original){return Vec::new()}}
   if chain.iter().any(|item|has_setting(item,original)){for item in chain{if !push_layout(&mut result,item,original){return Vec::new()}}}else{for item in chain{if !discard(item,original){return Vec::new()}}}
  }else if has_setting(&item,original){if !push_layout(&mut result,item,original){return Vec::new()}}else if !discard(item,original){return Vec::new()}
 }
 drop(input);if let Some(state)=original{state.storage.transfer_compacted_vector(old_capacity,result.capacity());}result
}

fn push_primary_item(rows:&mut Vec<Item>,item:Item,original:Option<&OriginalParseState<'_,'_,'_>>)->bool{match original{Some(state)=>state.storage.push(rows,item),None=>{rows.push(item);true}}}
fn original_header_before_child_lookahead(source:&str,line:&Line,context:ParseContext<'_,'_,'_>,items:&mut Vec<Item>)->bool{
 original_header_before_child_lookahead_scoped(source,line,context,items,None)
}
fn original_header_before_child_lookahead_scoped(source:&str,line:&Line,context:ParseContext<'_,'_,'_>,items:&mut Vec<Item>,scoped:Option<&mut dyn OriginalDeclarationHeaderObserver>)->bool{
 if context.original.is_none(){return true}
 let header=&source[line.header_start..line.header_end];let kind=if context.in_body{ItemKind::Statement}else{classify_primary_header(source,context.tokens,Span::new(line.header_start,line.header_end),false)};
        if !context.in_body{if let Some(original)=context.original{
            let first=context.tokens.partition_point(|token|token.span.end<=line.header_start);
            let last=context.tokens.partition_point(|token|token.span.start<line.header_end);
            let header_tokens=context.tokens.range(first,last).expect("ordered comma token window");
            let mut depth=0usize;let mut comma=None;
            for token in header_tokens.iter(){if !original.poll(){break}match token.text(source){"("|"["|"{"=>depth+=1,")"|"]"|"}"=>depth=depth.saturating_sub(1),"," if depth==0=>{comma=Some(token);break},_=>{}}}
            if let Some(comma)=comma{
                let local=crate::declaration_qualifiers::primary_header_qualifiers(source,context.tokens,Span::new(line.header_start,comma.span.start),false);
                let flags=crate::inherit_header_qualifiers(local,context.var_context).0;
                if flags!=crate::UNKNOWN_HEADER_QUALIFIERS{
                    let before=&source[line.header_start..comma.span.start];
                    let mut supported = true;
                    let mut previous_slash = true;
                    let mut saw_ident = false;
                    let mut phase = OriginalDeclarationCommaPhase::Bare;
                    let mut saw_decimal = false;
                    for token in header_tokens.iter() {
                        if token.span.start >= comma.span.start { break; }
                        if !original.poll() { supported = false; break; }
                        if matches!(token.kind, TokenKind::Whitespace | TokenKind::Comment | TokenKind::Newline) { continue; }
                        let text = token.text(source);
                        if phase == OriginalDeclarationCommaPhase::InitializedDecimal {
                            if saw_decimal || token.kind != TokenKind::Number || !crate::expression_parser::original_decimal(text) {
                                supported = false;
                                break;
                            }
                            saw_decimal = true;
                        } else if token.kind == TokenKind::Ident && previous_slash {
                            saw_ident = true;
                            previous_slash = false;
                        } else if text == "/" && !previous_slash {
                            previous_slash = true;
                        } else if text == "/" && !saw_ident && previous_slash {
                            // Leading slash.
                        } else if text == "=" && saw_ident && !previous_slash {
                            phase = OriginalDeclarationCommaPhase::InitializedDecimal;
                        } else {
                            supported = false;
                            break;
                        }
                    }
                    if supported && saw_ident && !previous_slash && (phase == OriginalDeclarationCommaPhase::Bare || saw_decimal) {
                        let prefix_end = line.header_start + before.trim_end().len();
                        let first_header = Span::new(line.header_start, prefix_end);
                        // The bare tree entry registers its field before the next
                        // tree entry sees the comma. The initialized entry requires
                        // a statement terminator before registering anything.
                        if phase == OriginalDeclarationCommaPhase::Bare {
                            let Some(header)=original.storage.text(&source[line.header_start..prefix_end])else{return false};
                            if !original.storage.push(items,Item{kind,header,span:first_header,header_span:first_header,declaration_cursor:Some(comma.span.start),checker_qualifiers:local,original_outer_terminator:Some(false),indent:line.indent,children:Vec::new()}){return false}
                        }
                        *original.fatal.borrow_mut() = Some(OriginalDeclarationFatal { comma: comma.span, first_header, phase });
                    }else if original.operational.borrow().is_none(){*original.unavailable.borrow_mut()=Some("Original class-comma prefix has unissued suffix/initializer parser state");}
                    return false
                }
            }
        }}

 if !context.in_body&&matches!(kind,ItemKind::Proc|ItemKind::Verb){if let Some(original)=context.original.filter(|state|scoped.is_some()||state.observer.is_some()){
            let first=context.tokens.partition_point(|token|token.span.end<=line.header_start);let last=context.tokens.partition_point(|token|token.span.start<line.header_end);
            let header_tokens=context.tokens.range(first,last).expect("ordered callable token window");
            // Group declarations without an argument list are not formal headers.
            let mut callable=false;for token in header_tokens.iter(){if !original.poll(){break}if token.text(source)=="("{callable=true;break}}if original.stopped(){return false}
            if callable{
                let event=OriginalPrimaryHeader{source,tokens:header_tokens,header:Span::new(line.header_start,line.header_end),kind,prior_outer_block:original.first_outer_block.get()};
                let result=if let Some(observer)=scoped{observer.header(event)}else{original.observer.as_ref().expect("actual observer was checked").borrow_mut().header(event)};
                match result{Ok(OriginalHeaderFlow::Continue)=>{},Ok(OriginalHeaderFlow::Stop)=>{original.observer_stop.set(Some(Span::new(line.header_start,line.header_end)));return false},Err(actual)=>{*original.operational.borrow_mut()=Some(actual);return false}}

 }}}true
}
fn parse_level(
    source: &str,
    lines: &[Line],
    mut index: usize,
    indent: usize,
    context: ParseContext<'_,'_,'_>,
    diagnostics: &mut Vec<Diagnostic>,
) -> (Vec<Item>, usize) {
    let _frame=match context.original{Some(state)=>match state.storage.frame(){Some(frame)=>Some(frame),None=>return(Vec::new(),index)},None=>None};
    let mut items = Vec::new();
    let mut saw_item = false;
    while index < lines.len() {
        if context.original.is_some_and(|state|!state.poll()||state.stopped()){break}
        let line = &lines[index];
        if line.indent < indent {
            break;
        }
        if line.indent > indent && saw_item {
            break;
        }
        if line.indent > indent {
            let span=Span::new(line.header_start,line.header_end);let kind=DiagnosticKind::Indentation;let message="unexpected indentation";
            if let Some(state)=context.original{if !state.storage.diagnostic_parts(diagnostics,span,kind,message){break}}else{diagnostics.push(Diagnostic{span,kind,message:message.into()})}
        }
        let mut end = line.end;
        let mut children = Vec::new();
        if !original_header_before_child_lookahead(source,line,context,&mut items){break}
        let has_children = index + 1 < lines.len() && lines[index + 1].indent > line.indent;
        let child=has_children.then(||&lines[index+1]);
        let Some(prepared)=prepare_primary_line(source,line,child,context,diagnostics,false)else{break};
        let kind=prepared.kind;let original_var_context=prepared.var_context;let observed_outer_terminator=prepared.outer;
        if has_children {
            let (parsed, next) = parse_level(
                source,
                lines,
                index + 1,
                lines[index + 1].indent,
                ParseContext {
                    in_body: context.in_body
                        || matches!(kind, ItemKind::Proc | ItemKind::Verb | ItemKind::Statement),
                    tokens: context.tokens,
                    original:context.original,
                    var_context:original_var_context,
                    skeleton: context.skeleton
                        && (context.in_body || !matches!(kind, ItemKind::Statement)),
                },
                diagnostics,
            );
            children = parsed;
            index = next;
            end = if context.skeleton {
                lines[next - 1].end
            } else {
                children.last().map_or(end, |child| child.span.end)
            };
        } else {
            index += 1;
        }
        saw_item = true;
        if !commit_primary_item(source,line,kind,end,children,has_children,observed_outer_terminator,context,&mut items){break}
    }
    let items=if context.skeleton&&context.in_body{
        if let Some(state)=context.original{match state.storage.compact(items.len()){Some(_temporary)=>retain_setting_chains(items,context.original),None=>Vec::new()}}else{retain_setting_chains(items,None)}
    }else{items};
    (items,index)
}

// SAME native classification/qualifier/outer-terminator/return-block judge.
// It is invoked only after a real next-line/EOF decision; fatal header observer
// runs earlier and therefore cannot demand that next line as a side effect.
struct PreparedPrimaryLine{kind:ItemKind,var_context:Option<u8>,outer:Option<bool>}
fn prepare_primary_line(source:&str,line:&Line,child:Option<&Line>,context:ParseContext<'_,'_,'_>,diagnostics:&mut Vec<Diagnostic>,scoped_observer:bool)->Option<PreparedPrimaryLine>{
 let has_children=child.is_some();
        let header = &source[line.header_start..line.header_end];
        let kind = if context.in_body {
            ItemKind::Statement
        } else {
            classify_primary_header(source,context.tokens,Span::new(line.header_start,line.header_end),has_children)
        };
        let original_var_context=if context.original.is_some()&&!context.in_body{crate::inherit_header_qualifiers(crate::declaration_qualifiers::primary_header_qualifiers(source,context.tokens,Span::new(line.header_start,line.header_end),has_children),context.var_context).1}else{None};
        let mut observed_outer_terminator=None;
        if !context.in_body&&matches!(kind,ItemKind::Proc|ItemKind::Verb){if let Some(original)=context.original.filter(|state|state.observer.is_some()||scoped_observer){
            // Same actual primary terminator producer, only prior accepted
            // callables can influence the next header's original fatal state.
            let probe=original_line_outer_probe(source,context.tokens,line,has_children,&||if original.poll(){Ok(())}else{Err(())});
            match probe{Ok(Some(at))=>{observed_outer_terminator=Some(true);original.first_outer_block.set(Some(original.first_outer_block.get().map_or(at,|old|old.min(at))))},Ok(None)=>observed_outer_terminator=Some(false),Err(())=>return None}
        }}
        if context.in_body && return_has_block(header, has_children) {
            // DreamMaker rejects the first indented line under `return`.
            let child = child.expect("actual native return-block child supplied");
            let span=Span::new(child.header_start,child.header_end);let kind=DiagnosticKind::Statement;let message=RETURN_BLOCK_UNSUPPORTED;
            if let Some(state)=context.original{if !state.storage.diagnostic_parts(diagnostics,span,kind,message){return None}}else{diagnostics.push(Diagnostic{span,kind,message:message.into()})}
        }
 Some(PreparedPrimaryLine{kind,var_context:original_var_context,outer:observed_outer_terminator})
}

// SAME native Item/header/cursor/qualifier commit judge, shared by whole
// traversal and forthcoming retained demand frames. This does not acquire IO.
fn commit_primary_item(source:&str,line:&Line,kind:ItemKind,end:usize,children:Vec<Item>,has_children:bool,observed_outer_terminator:Option<bool>,context:ParseContext<'_,'_,'_>,items:&mut Vec<Item>)->bool{
 let header=&source[line.header_start..line.header_end];
        if context.skeleton
            && context.in_body
            && children.is_empty()
            && !["set", "if", "else"]
                .iter()
                .any(|keyword| body_keyword(header, keyword))
        {
            // A discarded executable sibling still separates conditional
            // chains. Retain a zero-allocation delimiter until compaction so
            // a later `else` cannot attach across that original sibling.
            if items.last().is_some_and(|item: &Item| {
                body_keyword(&item.header, "if") || body_keyword(&item.header, "else")
            }) {
                if !push_primary_item(items,Item {
                    kind,
                    header: String::new(),
                    span: Span::new(line.header_start, end),
                    header_span: Span::new(line.header_start, line.header_end),
                    declaration_cursor: None,
                    checker_qualifiers: crate::UNKNOWN_HEADER_QUALIFIERS,
                    original_outer_terminator: Some(false),
                    indent: line.indent,
                    children,
                },context.original){return false}
            }
            return true;
        }
        let owned_header=if let Some(state)=context.original{match state.storage.text(header){Some(header)=>header,None=>return false}}else{header.to_owned()};
        if !push_primary_item(items,Item {
            kind,
            header: owned_header,
            span: Span::new(line.header_start, end),
            header_span: Span::new(line.header_start, line.header_end),
            declaration_cursor: (!context.in_body
                && !matches!(kind, ItemKind::Proc | ItemKind::Verb))
            .then(|| {
                primary_declaration_cursor(
                    source,
                    context.tokens,
                    Span::new(line.header_start, line.header_end),
                )
            })
            .flatten(),
            original_outer_terminator: if !context.in_body&&matches!(kind,ItemKind::Proc|ItemKind::Verb){Some(observed_outer_terminator.unwrap_or_else(||match original_line_outer_probe(source,context.tokens,line,has_children,&||Ok::<(),std::convert::Infallible>(())){Ok(probe)=>probe.is_some(),Err(never)=>match never{}}))}else{Some(false)},
            checker_qualifiers: if !context.in_body
                && !matches!(kind, ItemKind::Proc | ItemKind::Verb)
            {
                crate::declaration_qualifiers::primary_header_qualifiers(
                    source,
                    context.tokens,
                    Span::new(line.header_start, line.header_end),
                    has_children,
                )
            } else {
                crate::UNKNOWN_HEADER_QUALIFIERS
            },
            indent: line.indent,
            children,
        },context.original){return false}
 true
}

#[cfg(test)]
mod primary_declaration_cursor_tests {
    use super::*;
    fn vars(items: &[Item], out: &mut Vec<usize>) {
        for item in items {
            if item.kind == ItemKind::Var && !item.header.trim_end().ends_with('/') {
                if let Some(at) = item.declaration_cursor {
                    out.push(at);
                }
            }
            vars(&item.children, out);
        }
    }
    #[test]
    fn assignment_cursor_is_the_original_primary_equal_before_normalization() {
        let source = "/datum/probe\n    var/item = list(\n        1)\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        let mut cursors = Vec::new();
        vars(&parsed.items, &mut cursors);
        assert_eq!(cursors, [source.find('=').unwrap()]);
        assert_ne!(cursors[0], parsed.items[0].children[0].header_span.start);
    }
    #[test]
    fn semicolon_and_eof_are_real_primary_terminator_cursors() {
        let source = "var/first;var/second";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        assert_eq!(
            parsed.items[0].declaration_cursor,
            Some(source.find(';').unwrap())
        );
        assert_eq!(
            parsed.items[1].declaration_cursor,
            Some(source.find("second").unwrap())
        );
    }
    #[test]
    fn raw_preprocessor_continuation_has_no_primary_cursor_before_preprocessing() {
        let source = "/datum/probe\n    var/item \\\n        = 1\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        assert_eq!(parsed.items[0].children[0].declaration_cursor, None);
    }

    #[test]
    fn balanced_multiline_array_suffix_uses_actual_equal_on_later_line() {
        let source = "/datum/probe\n    var/items[\n        3] = 1\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        assert_eq!(
            parsed.items[0].children[0].declaration_cursor,
            Some(source.find('=').unwrap())
        );
        assert_eq!(parsed.items[0].children.len(), 1);
    }
    #[test]
    fn unknown_multiline_trailing_comment_never_invents_a_suffix_cursor() {
        let source = "var/item /* comment\n remaining */\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed
            .items
            .iter()
            .all(|item| item.declaration_cursor.is_none()));
    }
}

#[cfg(test)]
mod declaration_eof_policy_tests {
    use super::*;
    #[test]
    fn bare_and_array_eof_use_actual_last_token_but_unproved_tail_refuses() {
        for (source, expected) in [
            ("var/value", Some(4)),
            ("var/items[3]", Some(11)),
            ("var/value ", None),
            ("var/value // tail", None),
        ] {
            let parsed = parse_declaration_skeleton(source);
            assert!(parsed.diagnostics.is_empty());
            assert_eq!(parsed.items[0].declaration_cursor, expected, "{source:?}");
        }
    }
}

#[cfg(test)]
mod shared_original_body_tests {
    use super::*;
    fn proc(items: &[Item]) -> &Item {
        for i in items {
            if matches!(i.kind, ItemKind::Proc | ItemKind::Verb) {
                return i;
            }
            if !i.children.is_empty() {
                return proc(&i.children);
            }
        }
        panic!("original procedure")
    }
    #[test]
    fn cold_tokens_feed_body_and_formal_grammar_without_another_whole_lex() {
        for source in [
            "/datum/prefix\n/proc/p(obj/item/x = list(1,2))\n    var/y[6 / 2]\n    return x\n",
            "/datum/holder\n    proc/check(datum/x)\n        if(x) { return x; }\n",
            "/proc/p(value=\"ÃƒÂ©,()\")\r\n    // comment ([])\r\n    return \"text\"\r\n",
        ] {
            let cold = parse_declaration_skeleton(source);
            assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
            let span = proc(&cold.items).span;
            let before = WHOLE_LEX_CALLS.with(|n| n.get());
            let shared =
                crate::parse_proc_with_origins_from_spans(source, span, &cold.tokens, 0).unwrap();
            assert_eq!(
                WHOLE_LEX_CALLS.with(|n| n.get()),
                before,
                "shared body/formal grammar cannot lex full procedure again"
            );
            let old = crate::parse_proc_with_origins_at_span(source, span).unwrap();
            assert_eq!(
                WHOLE_LEX_CALLS.with(|n| n.get()),
                before + 1,
                "compatibility path independently exercises original lexical entry"
            );
            assert_eq!(shared.item, old.item);
            assert_eq!(shared.opening_parenthesis, old.opening_parenthesis);
            assert_eq!(shared.parameters, old.parameters);
        }
    }
    #[test]
    fn original_body_error_locations_and_foreign_range_denial_are_not_empty_success() {
        let source = "/datum/prefix\n/proc/p()\n    return\n        broken()\n";
        let cold = parse_declaration_skeleton(source);
        let span = proc(&cold.items).span;
        let old = crate::parse_proc_with_origins_at_span(source, span)
            .err()
            .unwrap();
        let current = crate::parse_proc_with_origins_from_spans(source, span, &cold.tokens, 0)
            .err()
            .unwrap();
        assert_eq!(current, old);
        let wrong = Span::new(span.start + 1, span.end);
        assert!(crate::parse_proc_with_origins_from_spans(source, wrong, &cold.tokens, 0).is_err());
    }
}

#[cfg(test)]
mod callable_namespace_classification_tests {
    use super::*;
    #[test]
    fn callable_namespace_groups_do_not_enter_executable_body_or_drop_leaf_settings() {
        for source in [
            "/datum/flags\n    proc/final\n        probe()\n            set SpacemanDMM_should_not_override = 1\n            return 0\n",
            "/datum/flags\n    proc\n        final\n            probe()\n                set SpacemanDMM_should_not_override = 1\n                return 0\n",
            "/datum/flags\n    verb\n        present()\n            set name = \"Present\"\n            return 0\n",
            "/datum/flags\n    verb/hidden\n        present()\n            set name = \"Present\"\n            return 0\n",
        ] {
            for skeleton in [false, true] {
                let parsed = parse_with_body_mode(source, skeleton);
                assert!(parsed.diagnostics.is_empty(), "{source:?}: {:?}", parsed.diagnostics);
                let mut item = &parsed.items[0];
                while item.kind == ItemKind::Type {
                    assert_eq!(item.children.len(), 1, "{source:?}");
                    item = &item.children[0];
                }
                assert!(matches!(item.kind, ItemKind::Proc | ItemKind::Verb), "{source:?}");
                assert!(item.header.ends_with("()"), "{source:?}");
                assert_eq!(item.span.start, source.find(&item.header).unwrap());
                assert_eq!(item.children[0].kind, ItemKind::Statement);
                assert!(item.children[0].header.starts_with("set "));
                assert_eq!(item.children.len(), if skeleton { 1 } else { 2 });
            }
        }
    }
}

/// Actual original tree-entry grammar stop, issued only inside the native
/// primary declaration traversal. This DATA grants no model/compile role.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum OriginalDeclarationCommaPhase { Bare, InitializedDecimal }
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct OriginalDeclarationFatal{comma:Span,first_header:Span,phase:OriginalDeclarationCommaPhase}
impl OriginalDeclarationFatal{
 pub fn token_span(self)->Span{self.comma}
 pub fn first_header(self)->Span{self.first_header}
 pub fn first_declaration_registered(self) -> bool { self.phase == OriginalDeclarationCommaPhase::Bare }
 pub fn message(self)->&'static str{match self.phase{
  OriginalDeclarationCommaPhase::Bare => "got ',', expected one of: '/', '[', '=', '(', '{', 'as', 'in', ';', '}'",
  OriginalDeclarationCommaPhase::InitializedDecimal => "got ',', expected one of: operator, field access, 'as', 'in', ';'",
 }}
 pub fn notes(self)->[&'static str;2]{["fatal error: the parser cannot continue","constant evaluation will be skipped"]}
}
/// Borrowed event from the genuine primary header cursor BEFORE child descent.
/// It grants no compile/model role and cannot be constructed by a consumer.
pub struct OriginalPrimaryHeader<'a>{source:&'a str,tokens:TokenWindow<'a>,header:Span,kind:ItemKind,prior_outer_block:Option<usize>}
impl<'a> OriginalPrimaryHeader<'a>{
 pub fn source(&self)->&'a str{self.source}pub fn token_window(&self)->TokenWindow<'a>{self.tokens}pub fn span(&self)->Span{self.header}pub fn kind(&self)->ItemKind{self.kind}pub fn prior_outer_block(&self)->Option<usize>{self.prior_outer_block}
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalHeaderFlow{Continue,Stop}
/// Parser-state observer, not a second header parser. The tree layer lends its
/// existing formal signature producer and retains that producer's exact result.
pub trait OriginalDeclarationHeaderObserver{fn header(&mut self,event:OriginalPrimaryHeader<'_>)->std::io::Result<OriginalHeaderFlow>;}
#[derive(Clone,Debug,Default,Eq,PartialEq)]
pub struct OriginalDeclarationSyntax{pub items:Vec<Item>,pub tokens:crate::SpanTokenStorage,pub diagnostics:Vec<Diagnostic>}
pub struct OriginalDeclarationSkeleton{
 syntax:OriginalDeclarationSyntax,
 literal_facts:Option<OriginalPrimaryLiteralFacts>,
 primary_owner:Option<demand_layout::NativePrimaryLayoutIdentity>,
 fatal:Option<OriginalDeclarationFatal>,
 unavailable:Option<&'static str>,
 observer_stop:Option<Span>,
 _lease:crate::SettingRootLease,
}
impl OriginalDeclarationSkeleton{
 pub fn syntax(&self)->&OriginalDeclarationSyntax{&self.syntax}
 pub fn same_primary_header(&self,header:&OriginalPrimaryLiveHeader)->bool{self.primary_owner.as_ref().is_some_and(|owner|header.matches_owner(owner))}
 pub fn same_primary_producer(&self,identity:&OriginalPrimaryProducerIdentity)->bool{self.primary_owner.as_ref().is_some_and(|owner|identity.matches_owner(owner))}
 pub fn visit_primary_producer_storage(&self,visit:impl FnMut(usize,usize,usize)){if let Some(owner)=&self.primary_owner{owner.visit_storage(visit)}}
 /// Consume the actual primary outcome and transfer ONLY the retained token
 /// allocation credit. The remaining item/diagnostic lease stays on primary;
 /// its final Header/expanded aliases never pin that sibling AST allocation.
 pub fn into_shared_tokens_using(mut self,a:&crate::SettingAdmission<'_>)->std::io::Result<(Self,crate::SharedSpanTokens)>{
  if let Err(status)=a.checkpoint(){return Err(a.take_operational_error().unwrap_or(status))}
  if !a.matches_lease_domain(&self._lease){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"shared primary transfer uses another resource owner"))}
  let tokens=std::mem::take(&mut self.syntax.tokens);
  let shared=match tokens{
   crate::SpanTokenStorage::Shared(shared)=>{if !shared.admitted_by(a){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"shared primary tokens use another resource owner"))}shared},
   crate::SpanTokenStorage::Owned(tokens)=>{let bytes=tokens.capacity().checked_mul(std::mem::size_of::<SpanToken>()).ok_or(std::io::ErrorKind::OutOfMemory)?;let credit=a.split(&mut self._lease,bytes)?;crate::SharedSpanTokens::from_admitted_using(tokens,credit,a)?},
  };
  self.syntax.tokens=shared.clone().into();Ok((self,shared))
 }

 /// None is unissued, distinct from a genuine completed zero-fact roster.
 pub fn original_literal_facts(&self)->Option<OriginalLiteralRows<'_>>{self.literal_facts.as_ref().map(OriginalPrimaryLiteralFacts::rows)}
 pub fn original_literal_fact_owner(&self)->Option<&OriginalPrimaryLiteralFacts>{self.literal_facts.as_ref()}
 /// Move the SAME completed neutral roster into the genuine final source binding.
 /// The actual primary outcome/source extent remains separately authenticated.
 pub fn take_original_literal_fact_owner_using(&mut self,a:&crate::SettingAdmission<'_>)->std::io::Result<Option<OriginalPrimaryLiteralFacts>>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  if !a.matches_lease_domain(&self._lease)||self.literal_facts.as_ref().is_some_and(|facts|!facts.is_admitted_by(a)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual primary fact transfer belongs to another admission"))}
  Ok(self.literal_facts.take())
 }

 pub fn fatal(&self)->Option<OriginalDeclarationFatal>{self.fatal}
 pub fn unavailable(&self)->Option<&'static str>{self.unavailable}
 /// Exact primary header at which the registered producer requested a stop.
 /// This is distinct from an authored parser fatal or semantic unavailability.
 pub fn observer_stop(&self)->Option<Span>{self.observer_stop}

 /// Transfer SAME native primary product, outcome and its real resource owner.
 /// Consumer must preserve diagnostic/partial roles; no frontend is issued.
 pub fn into_parts(self)->(OriginalDeclarationSyntax,Option<OriginalDeclarationFatal>,Option<&'static str>,crate::SettingRootLease){(self.syntax,self.fatal,self.unavailable,self._lease)}
 pub fn into_parts_with_literal_facts(self)->(OriginalDeclarationSyntax,Option<OriginalDeclarationFatal>,Option<&'static str>,crate::SettingRootLease,Option<OriginalPrimaryLiteralFacts>){(self.syntax,self.fatal,self.unavailable,self._lease,self.literal_facts)}
}
struct OriginalParseState<'a,'observer,'budget>{
 storage:original_storage::Storage<'a,'budget>,
 fatal:std::cell::RefCell<Option<OriginalDeclarationFatal>>,
 unavailable:std::cell::RefCell<Option<&'static str>>,
 operational:std::cell::RefCell<Option<std::io::Error>>,
 observer:Option<std::cell::RefCell<&'observer mut dyn OriginalDeclarationHeaderObserver>>,
 observer_stop:std::cell::Cell<Option<Span>>,
 first_outer_block:std::cell::Cell<Option<usize>>,
}
impl OriginalParseState<'_,'_,'_>{
 fn poll(&self)->bool{self.operational.borrow().is_none()&&self.storage.poll()}
 fn stopped(&self)->bool{self.fatal.borrow().is_some()||self.unavailable.borrow().is_some()||self.operational.borrow().is_some()||self.observer_stop.get().is_some()}
}
/// Same lexer/layout/primary parser, explicit Original declaration outcome.
/// Ordinary native parse is unchanged and never consumes this diagnostic role.
pub fn parse_original_declaration_skeleton_using(source:&str,a:&crate::SettingAdmission<'_>)->std::io::Result<OriginalDeclarationSkeleton>{parse_original_declaration_skeleton_with_observer_using(source,a,None)}
pub fn parse_original_declaration_skeleton_with_observer_using(source:&str,a:&crate::SettingAdmission<'_>,observer:Option<&mut dyn OriginalDeclarationHeaderObserver>)->std::io::Result<OriginalDeclarationSkeleton>{
 let checkpoint=||{let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual)}status};checkpoint()?;
 let storage=original_storage::Storage::new(a)?;
 #[cfg(test)]WHOLE_LEX_CALLS.with(|n|n.set(n.get()+1));
 let mut lexed=SpannedLexed::default();
 crate::lexer_items::visit_tokens_and_diagnostics_while(source,|token|storage.push(&mut lexed.tokens,token),|span,kind,message|storage.diagnostic_parts(&mut lexed.diagnostics,span,kind,message));
 if let Some(actual)=storage.take_failure(){return Err(actual)}checkpoint()?;
 let original=OriginalParseState{storage,fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:observer.map(std::cell::RefCell::new),observer_stop:Default::default(),first_outer_block:Default::default()};
 let(items,mut diagnostics)=parse_original_span_range_with_outcome(source,Span::new(0,source.len()),TokenWindow::from_vec(&lexed.tokens),true,Some(&original),None);
 if let Some(actual)=original.operational.into_inner(){return Err(actual)}if let Some(actual)=original.storage.take_failure(){return Err(actual)}
 checkpoint()?;let mut lexical=lexed.diagnostics;for diagnostic in diagnostics.drain(..){if !original.storage.push(&mut lexical,diagnostic){return Err(original.storage.take_failure().unwrap_or_else(||std::io::ErrorKind::OutOfMemory.into()))}}drop(diagnostics);
 let lease=original.storage.finish(&items,lexed.tokens.capacity(),&lexical)?;
 Ok(OriginalDeclarationSkeleton{syntax:OriginalDeclarationSyntax{items,tokens:lexed.tokens.into(),diagnostics:lexical},literal_facts:None,primary_owner:None,fatal:original.fatal.into_inner(),unavailable:original.unavailable.into_inner(),observer_stop:original.observer_stop.get(),_lease:lease})
}

#[cfg(test)]mod original_primary_comma_prefix_tests{
 use super::*;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn original_primary_class_comma_retains_only_real_first_field_and_stops_inside_enclosing_type(){
  for source in ["/datum/holder\n    var/datum/loose\n    var/list/items\n    var/datum/first, second\n/proc/later()\n    return\n","// ÃƒÂ©Ã¦Â¼Â¢ actual original bytes\n/datum/holder\n    var/SpacemanDMM_private/datum/first, second\n/proc/later()\n    return\n","/datum/holder\n    var\n        SpacemanDMM_private\n            datum/first, second\n/proc/later()\n    return\n"]{
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<24,&||Ok(()));let before=WHOLE_LEX_CALLS.with(|n|n.get());let outcome=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(WHOLE_LEX_CALLS.with(|n|n.get()),before+1,"same single primary lexer");assert!(outcome.unavailable().is_none());let fatal=outcome.fatal().unwrap();assert!(fatal.first_declaration_registered());assert_eq!(fatal.token_span(),Span::new(source.find(',').unwrap(),source.find(',').unwrap()+1));assert_eq!(fatal.message(),"got ',', expected one of: '/', '[', '=', '(', '{', 'as', 'in', ';', '}'");assert_eq!(fatal.notes(),["fatal error: the parser cannot continue","constant evaluation will be skipped"]);assert!(outcome.syntax().diagnostics.is_empty());
   fn contains(items:&[Item],name:&str)->bool{items.iter().any(|item|item.header.contains(name)||contains(&item.children,name))}
   assert!(contains(&outcome.syntax().items,"first"));assert!(!contains(&outcome.syntax().items,"second"));assert!(!contains(&outcome.syntax().items,"later"));assert!(!outcome.syntax().items.is_empty(),"genuine prefix is retained, never an empty success");
   let rows=primary_header_facts(source,&[PrimaryHeaderInput{span:fatal.first_header(),parent:None,has_children:false}]).unwrap();assert_eq!(rows[0].1,Some(fatal.token_span().start),"portable primary reissue observes actual comma terminator");
   let native=parse_declaration_skeleton(source);assert!(contains(&native.items,"second"));assert!(contains(&native.items,"later"),"ordinary native producer remains unchanged");
   assert!(counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(outcome);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn original_initialized_class_comma_stops_before_registering_first_variable(){
  let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a = crate::SettingAdmission::new(&counter, 1 << 24, &|| Ok(()));
  let source = "/datum/holder\n    var/kept=7\n    var/first=1, second=2\n/proc/later()\n    return\n";
  let outcome = parse_original_declaration_skeleton_using(source, &a).unwrap();
  assert!(outcome.unavailable().is_none());
  let fatal = outcome.fatal().expect("actual initialized comma frontier");
  assert!(!fatal.first_declaration_registered());
  assert_eq!(&source[fatal.token_span().range()], ",");
  assert_eq!(fatal.token_span().start, source.find(',').unwrap());
  assert_eq!(fatal.message(), "got ',', expected one of: operator, field access, 'as', 'in', ';'");
  assert_eq!(outcome.syntax().items.len(), 1);
  let [kept] = outcome.syntax().items[0].children.as_slice() else { panic!("initialized first variable must not be registered") };
  assert!(kept.header.contains("kept"));

  let nested = "/datum/holder\n    var/list/values=list(1,2)\n";
  let nested = parse_original_declaration_skeleton_using(nested, &a).unwrap();
  assert!(nested.fatal().is_none() && nested.unavailable().is_none());
  assert_eq!(nested.syntax().items[0].children.len(), 1);

  for rhs in ["", "1 + 2", "list(1,2)", "1 as num"] {
   let source = format!("/datum/holder\n    var/first={rhs}, second\n");
   let unissued = parse_original_declaration_skeleton_using(&source, &a).unwrap();
   assert!(unissued.fatal().is_none() && unissued.unavailable().is_some(), "{rhs}");
   assert!(unissued.syntax().items[0].children.is_empty(), "{rhs}");
  }
 }
 #[test]fn original_primary_prefix_keeps_native_typed_cancellation_and_peak_quota_failure(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fault=||Err(std::io::Error::from_raw_os_error(1450));let a=crate::SettingAdmission::new(&counter,1<<24,&fault);assert_eq!(parse_original_declaration_skeleton_using("var/first,second\n",&a).err().unwrap().raw_os_error(),Some(1450));let a=crate::SettingAdmission::new(&counter,crate::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));assert_eq!(parse_original_declaration_skeleton_using("var/first,second\n",&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_primary_header_observer_tests{
 use super::*;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn actual_header_observer_stops_before_fatal_proc_descent_and_future_type_prescan(){
  struct Observe{seen:Vec<(Span,Option<usize>)>}
  impl OriginalDeclarationHeaderObserver for Observe{fn header(&mut self,event:OriginalPrimaryHeader<'_>)->std::io::Result<OriginalHeaderFlow>{assert_eq!(event.source().get(event.span().range()),Some(if self.seen.is_empty(){"/proc/earlier()"}else{"/proc/bad(value=)"}));assert!(event.token_window().iter().all(|token|token.span.start>=event.span().start&&token.span.end<=event.span().end));self.seen.push((event.span(),event.prior_outer_block()));Ok(if self.seen.len()==2{OriginalHeaderFlow::Stop}else{OriginalHeaderFlow::Continue})}}
  let source="/proc/earlier(){}\n/proc/bad(value=)\n    return 1\n/datum/later\n    parent_type=/datum/missing\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<24,&||Ok(()));let mut observer=Observe{seen:Vec::new()};let before=WHOLE_LEX_CALLS.with(|n|n.get());let result=parse_original_declaration_skeleton_with_observer_using(source,&a,Some(&mut observer)).unwrap();assert_eq!(WHOLE_LEX_CALLS.with(|n|n.get()),before+1);assert_eq!(observer.seen.len(),2);assert!(observer.seen[0].1.is_none());assert_eq!(observer.seen[1].1,Some("/proc/earlier()".len()));assert_eq!(result.observer_stop(),Some(observer.seen[1].0));assert_eq!(result.syntax().items.len(),1);assert_eq!(result.syntax().items[0].header,"/proc/earlier()");assert!(result.fatal().is_none());assert!(result.unavailable().is_none());
  let ordinary=parse_declaration_skeleton(source);assert_eq!(ordinary.items.len(),3,"ordinary native primary acceptance unchanged");
 }
 #[test]fn actual_header_observer_operational_failure_is_not_a_source_stop_or_unavailable(){
  struct Fault;impl OriginalDeclarationHeaderObserver for Fault{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->std::io::Result<OriginalHeaderFlow>{Err(std::io::Error::from_raw_os_error(1450))}}
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<24,&||Ok(()));let actual=parse_original_declaration_skeleton_with_observer_using("/proc/p()\n    return\n",&a,Some(&mut Fault)).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_primary_demanded_storage_tests{
 use super::*;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn actual_large_comment_primary_uses_one_native_lexer_and_demanded_layout_storage(){
  let mut source=String::from("// ");source.extend(std::iter::repeat_n('x',9_600_000));source.push_str("\n/datum/actual\n    var/value=1\n");let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let peak=AtomicUsize::new(0);let poll=||{peak.fetch_max(counter.load(Ordering::Acquire),Ordering::AcqRel);Ok(())};let a=crate::SettingAdmission::new(&counter,32<<20,&poll);let before=WHOLE_LEX_CALLS.with(|n|n.get());let result=parse_original_declaration_skeleton_using(&source,&a).unwrap();assert_eq!(WHOLE_LEX_CALLS.with(|n|n.get()),before+1);assert!(result.fatal().is_none());assert!(result.unavailable().is_none());assert!(result.syntax().diagnostics.is_empty());assert_eq!(result.syntax().items.len(),1);assert_eq!(result.syntax().items[0].header,"/datum/actual");assert_eq!(result.syntax().items[0].children.len(),1);assert!(peak.load(Ordering::Acquire)>=source.len()*2,"two actual primary layout masks funded before allocation");assert!(peak.load(Ordering::Acquire)<=32<<20);assert!(result._lease.bytes()<64<<10,"dead layout masks/lines are not retained by primary output");assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+result._lease.bytes());drop(result);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_dense_primary_funds_real_native_token_lines_and_output_capacities(){
  let mut source=String::new();for index in 0..2000{source.push_str(&format!("/datum/node_{index}\n    var/value={index}\n"));}let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,16<<20,&||Ok(()));let before=WHOLE_LEX_CALLS.with(|n|n.get());let result=parse_original_declaration_skeleton_using(&source,&a).unwrap();assert_eq!(WHOLE_LEX_CALLS.with(|n|n.get()),before+1);assert!(result.syntax().diagnostics.is_empty());assert_eq!(result.syntax().items.len(),2000);assert!(result.syntax().items.iter().all(|node|node.children.len()==1));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (result._lease.bytes()));drop(result);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn demanded_primary_token_funding_and_mid_cursor_failure_leave_no_partial_success(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,4097,&||Ok(()));let actual=parse_original_declaration_skeleton_using("/datum/required\n    var/value=1\n",&a).err().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let calls=AtomicUsize::new(0);let fail=||if calls.fetch_add(1,Ordering::AcqRel)==7{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())};let a=crate::SettingAdmission::new(&counter,1<<20,&fail);let actual=parse_original_declaration_skeleton_using("/datum/required\n    var/value=1\n",&a).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_primary_setting_compaction_storage_tests{
 use super::*;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn demanded_primary_compaction_keeps_actual_nested_setting_chains_and_drops_only_unowned_storage(){
  let source="/proc/p()\n    if(1)\n        if(2)\n            set name=\"actual\"\n        else\n            return\n    else\n        return 2\n    if(3)\n        if(4)\n            return 4\n    return 5\n";let ordinary=parse_declaration_skeleton(source);let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let current=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(format!("{:?}",current.syntax().items),format!("{:?}",ordinary.items));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (current._lease.bytes()));drop(current);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_primary_stack_resource_tests{
 use super::*;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn real_primary_deep_declaration_nesting_refuses_worker_stack_resource_without_source_diagnostic(){
  let mut source=String::from("/datum\n");for depth in 1..300{source.push_str(&" ".repeat(depth*4));source.push_str(&format!("node_{depth}\n"));}let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::with_stack_allowance(&counter,4<<20,64<<10,&||Ok(()));let actual=parse_original_declaration_skeleton_using(&source,&a).err().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);assert!(actual.to_string().contains("stack-work"),"actual existing worker-stack refusal retained: {actual}");assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn lexical_diagnostic_string_is_admitted_before_construction_and_failure_never_yields_partial_rows(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let calls=AtomicUsize::new(0);let fail=||if calls.fetch_add(1,Ordering::AcqRel)==3{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())};let a=crate::SettingAdmission::new(&counter,1<<20,&fail);let actual=parse_original_declaration_skeleton_using("var/a=\"unterminated",&a).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_primary_initial_operational_cause_tests{
 use super::*;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn each_real_initial_primary_phase_retains_first_os_failure_and_releases_owned_storage(){
  for fail_at in 0..24{let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let calls=AtomicUsize::new(0);let fault=||if calls.fetch_add(1,Ordering::AcqRel)==fail_at{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())};let a=crate::SettingAdmission::new(&counter,1<<20,&fault);let actual=parse_original_declaration_skeleton_using("/datum/required\n    var/value=1\n",&a).err().expect("real initial native phase reached requested operational fault");assert_eq!(actual.raw_os_error(),Some(1450),"first native failure at callback {fail_at}: {actual}");assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes(),"callback {fail_at}");}
 }
}

#[cfg(test)]mod demanded_native_structural_tests{use super::*;
fn frozen_actual_structural_lines(visible:&str,delimiters:&[u8],multiline_literals:&[Span],original:Option<&OriginalParseState<'_,'_,'_>>,source:&str,tokens:&[SpanToken],range_start:usize)->Vec<Line>{
    let mut lines = Vec::new();
    let mut offset = 0;
    let mut pending: Option<Line> = None;
    let mut depth = 0usize;
    let mut literal_cursor = 0usize;
    let mut initializer_depth=0usize;
    let mut block_depth=0usize;
    let mut procedure:Option<(usize,usize)>=None;
    let mut pending_in_body=false;
    let mut pending_block_start=0usize;
    for raw in visible.split_inclusive('\n') {
        if original.is_some_and(|state|!state.poll()){break}
        while multiline_literals
            .get(literal_cursor)
            .is_some_and(|literal| literal.end <= offset)
        {
            literal_cursor += 1;
        }
        let leading = raw
            .bytes()
            .take_while(|b| *b == b' ' || *b == b'\t')
            .count();
        let trimmed = raw[leading..].trim_end_matches(['\r', '\n', ' ', '\t']);
        let physical_indent:usize=raw[..leading].bytes().map(|byte|if byte==b'\t'{4}else{1}).sum();
        if pending.is_none()&&!trimmed.is_empty(){
            if procedure.is_some_and(|(indent,base)|physical_indent<=indent&&block_depth<=base){procedure=None;}
            pending_in_body=procedure.is_some();pending_block_start=block_depth;
        }
        let segment_start=pending.as_ref().map_or(offset+leading,|line|line.header_start);
        for at in offset..offset+raw.len(){
            if at%1024==0&&original.is_some_and(|state|!state.poll()){return lines}
            match delimiters[at]{
                b'(' | b'['=>depth+=1,
                b')' | b']'=>depth=depth.saturating_sub(1),
                b'{' if initializer_depth>0 || (depth==0&&is_object_initializer_primary(&visible[segment_start..at],pending_in_body,original.map(|state|(source,TokenWindow::from_slice(tokens),Span::new(range_start+segment_start,range_start+at),state))))=>initializer_depth+=1,
                b'}' if initializer_depth>0=>initializer_depth-=1,
                b'{' if depth==0=>block_depth+=1,
                b'}' if depth==0=>block_depth=block_depth.saturating_sub(1),
                _=>()
            }
        }
        if !trimmed.is_empty() && !trimmed.starts_with("//") {
            if let Some(line) = pending.as_mut() {
                line.header_end = offset + leading + trimmed.len();
                line.end = offset + raw.len();
            } else {
                // An included file's first line can inherit spaces left by
                // the expanded #include directive. Absolute DM paths declare
                // from the root regardless of that textual indentation.
                let indent = if trimmed.starts_with('/') && !(pending_in_body&&trimmed.find('{').is_some_and(|at|bare_prefab(&trimmed[..at]))) {
                    0
                } else {
                    raw[..leading]
                        .bytes()
                        .map(|b| if b == b'\t' { 4 } else { 1 })
                        .sum()
                };
                pending = Some(Line {
                    indent,
                    header_start: offset + leading,
                    header_end: offset + leading + trimmed.len(),
                    explicit_block_opener: false,
                    same_line_body: false,
                    end: offset + raw.len(),
                });
            }
        } else if let Some(line) = pending.as_mut() {
            line.end = offset + raw.len();
        }
        let mut inside_literal = false;
        for literal in multiline_literals[literal_cursor..]
            .iter()
            .take_while(|literal| literal.start < offset + raw.len())
        {
            if let Some(line) = pending.as_mut() {
                line.header_end = line.header_end.max(literal.end.min(offset + raw.len()));
            }
            inside_literal |= literal.end > offset + raw.len();
        }
        if depth == 0 && initializer_depth==0 && !inside_literal {
            if let Some(line) = pending.take() {
                if !pending_in_body&&callable_header(&visible[line.header_start..line.header_end]){procedure=Some((line.indent,pending_block_start));}
                if !push_layout(&mut lines,line,original){return lines}
            }
        }
        offset += raw.len();
    }
    if let Some(line) = pending {
        if !push_layout(&mut lines,line,original){return lines}
    }
    lines
}

 fn shape(rows:&[Line])->Vec<(usize,usize,usize,usize,bool,bool)>{rows.iter().map(|x|(x.indent,x.header_start,x.header_end,x.end,x.explicit_block_opener,x.same_line_body)).collect()}
 #[test]fn same_native_structural_state_resumes_real_groups_and_indent_without_replaying_prior_lines(){
  for source in ["/datum/a\n    var/value=1\n/proc/p()\n    return 2\n", "/datum/a\n    var/list/value=list(\n        1,\n        2)\n/proc/p()\n    return 2", "/datum/a {\n var/value=1;\n}\n/proc/p()\n return 3\n"]{
   let tokens=lex_spans(source).tokens;let expected=frozen_actual_structural_lines(source,source.as_bytes(),&[],None,source,&tokens,0);let mut cursor=NativeStructuralCursor::default();let mut actual=Vec::new();let mut end=0;
   for raw in source.split_inclusive('\n'){end+=raw.len();let final_input=end==source.len();actual.extend(cursor.advance(&source[..end],&source.as_bytes()[..end],&[],None,source,TokenWindow::from_vec(&tokens),0,final_input).unwrap());}
   assert_eq!(shape(&actual),shape(&expected));assert!(cursor.finished);assert_eq!(cursor.offset,source.len());assert!(cursor.pending.is_none());
  }
 }
 #[test]fn temporary_physical_boundary_does_not_flush_real_pending_group_as_eof(){
  let source="/datum/a\n    var/list/value=list(\n        1)\n";let cut=source.find("        1").unwrap();let tokens=lex_spans(source).tokens;let mut cursor=NativeStructuralCursor::default();let first=cursor.advance(&source[..cut],&source.as_bytes()[..cut],&[],None,source,TokenWindow::from_vec(&tokens),0,false).unwrap();assert_eq!(first.len(),1);assert!(cursor.pending.is_some());assert_eq!(cursor.depth,1);let next=cursor.advance(source,source.as_bytes(),&[],None,source,TokenWindow::from_vec(&tokens),0,true).unwrap();assert_eq!(next.len(),1);assert!(cursor.pending.is_none());assert_eq!(cursor.depth,0);
 }
 #[test]fn incomplete_physical_fragment_refuses_without_advancing_or_fabricating_layout(){let mut cursor=NativeStructuralCursor::default();let source="/datum/a";let error=cursor.advance(source,source.as_bytes(),&[],None,source,TokenWindow::from_slice(&[]),0,false).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::Unsupported);assert_eq!(cursor.offset,0);assert!(cursor.pending.is_none());assert!(!cursor.finished);}
}

#[cfg(test)]mod demanded_native_mask_tests{use super::*;
fn frozen_actual_original_declaration_lines_with_storage(source:&str,range:Span,tokens:&[SpanToken],original:Option<&OriginalParseState<'_,'_,'_>>)->Vec<Line>{
    // Comments remain in `tokens`, but cannot introduce declarations or alter indentation.
    // A byte-for-byte mask keeps the original source spans valid, including UTF-8 offsets.
    let range_source = &source[range.range()];
    let mut visible = range_source.as_bytes().to_vec();
    for token in tokens {
        if original.is_some_and(|state|!state.poll()){return Vec::new()}
        if token.kind == TokenKind::Comment
            || (token.kind == TokenKind::String && token.text(source).contains('\n'))
        {
            for(index,byte)in visible[token.span.start-range.start..token.span.end-range.start].iter_mut().enumerate(){
                if index%1024==0&&original.is_some_and(|state|!state.poll()){return Vec::new()}
                if !matches!(*byte,b'\r'|b'\n'){
                    *byte = b' ';
                }
            }
        }
    }
    let visible = String::from_utf8(visible).expect("comment mask preserves UTF-8");
    let mut delimiters = visible.as_bytes().to_vec();
    for token in tokens {
        if original.is_some_and(|state|!state.poll()){return Vec::new()}
        if matches!(token.kind, TokenKind::String | TokenKind::Resource) {
            for(index,byte)in delimiters[token.span.start-range.start..token.span.end-range.start].iter_mut().enumerate(){
                if index%1024==0&&original.is_some_and(|state|!state.poll()){return Vec::new()}
                if !matches!(*byte,b'\r'|b'\n'){
                    *byte = b' ';
                }
            }
        }
    }
    let mut multiline_literals=Vec::new();for token in tokens{if original.is_some_and(|state|!state.poll()){return Vec::new()}if token.kind==TokenKind::String&&token.text(source).contains('\n'){if !push_layout(&mut multiline_literals,Span::new(token.span.start-range.start,token.span.end-range.start),original){return Vec::new()}}}
    let mut lines=split_inline_blocks(range_source,&structural_lines(&visible,&delimiters,&multiline_literals,original,source,tokens,range.start),&delimiters,original,source,tokens,range.start);
    for line in &mut lines {
        line.header_start += range.start;
        line.header_end += range.start;
        line.end += range.start;
    }
    lines
}

 fn shape(rows:&[Line])->Vec<(usize,usize,usize,usize,bool,bool)>{rows.iter().map(|x|(x.indent,x.header_start,x.header_end,x.end,x.explicit_block_opener,x.same_line_body)).collect()}
 #[test]fn same_native_mask_kernel_matches_actual_old_utf8_comment_literal_and_resource_layout(){for source in ["/datum/ÃŽÂ±\n    var/value=\"text // not comment\"\n    /* multi\n      comment */ var/next=2\n", "/proc/p()\n    return {\"block\ntext\"}\n/datum/later\n", "/datum/ÃŽÂ±\n    var/icon='icons/a{b}.dmi'\n"]{let tokens=lex_spans(source).tokens;let old=frozen_actual_original_declaration_lines_with_storage(source,Span::new(0,source.len()),&tokens,None);let new=original_declaration_lines_with_storage(source,Span::new(0,source.len()),&tokens,None);assert_eq!(shape(&new),shape(&old));}}
 #[test]
 fn incremental_visible_string_emits_each_new_utf8_byte_once_and_matches_frozen_masks() {
  let source="/datum/\u{3b1}\n    var/value=\"\u{3b2}\"\n    /* \u{3b3}\r\n       \u{3b4} */ var/next=2\n    var/multi={\"\u{3b5}\r\n\u{3b6}\"}\n    var/resource='icons/\u{3b7}.dmi'\n";
  let tokens=lex_spans(source).tokens;
  let mut wanted_visible=source.as_bytes().to_vec();let mut wanted_delimiters=wanted_visible.clone();
  for token in &tokens{
   let raw=token.text(source);let visible=token.kind==TokenKind::Comment||(matches!(token.kind,TokenKind::String|TokenKind::Interpolation)&&raw.contains('\n'));
   let delimiters=visible||matches!(token.kind,TokenKind::String|TokenKind::Resource|TokenKind::Interpolation);
   for at in token.span.range(){if !matches!(source.as_bytes()[at],b'\r'|b'\n'){if visible{wanted_visible[at]=b' ';}if delimiters{wanted_delimiters[at]=b' ';}}}
  }
  let mut masks=NativeLayoutMaskCursor::default();
  for(index,token)in tokens.iter().enumerate(){
   let previous=masks.visible.clone();
   assert!(masks.advance(source,Span::new(0,token.span.end),&tokens[..=index],None));
   assert_eq!(&masks.visible[..previous.len()],previous.as_str(),"settled visible prefix is untouched");
   assert_eq!(masks.visible().len(),token.span.end);
   assert_eq!(masks.visible_appended_bytes,token.span.end,"only new source bytes are transformed, including multi-byte masked characters");
  }
  if masks.visible.len()<source.len(){assert!(masks.advance(source,Span::new(0,source.len()),&tokens,None));}
  assert_eq!(masks.visible().as_bytes(),wanted_visible);assert_eq!(masks.delimiters,wanted_delimiters);
  assert_eq!(masks.visible_appended_bytes,source.len());
  let before=masks.visible_appended_bytes;for _ in 0..1024{assert_eq!(masks.visible().len(),source.len());}assert_eq!(masks.visible_appended_bytes,before,"borrowed visible view performs no append/revalidation pass");
 }
 #[test]
 fn incremental_visible_string_refuses_non_utf8_token_boundaries_without_invalid_string_storage() {
  let source="\u{3b1}";let tokens=[SpanToken{kind:TokenKind::Ident,span:Span::new(0,1)}];
  let mut masks=NativeLayoutMaskCursor::default();assert!(!masks.advance(source,Span::new(0,source.len()),&tokens,None));
  assert!(masks.visible().is_empty());assert_eq!(masks.visible_appended_bytes,0);
 }
 #[test]fn masks_resume_only_new_actual_tokens_without_recopying_or_rewriting_prior_prefix(){let source="/datum/ÃŽÂ±\n    var/a=\"literal\"\n    // comment\n    var/b=2\n";let tokens=lex_spans(source).tokens;let cut=source.find("    //").unwrap();let first=tokens.partition_point(|row|row.span.end<=cut);let mut masks=NativeLayoutMaskCursor::default();assert!(masks.advance(source,Span::new(0,cut),&tokens[..first],None));let prior=masks.visible.clone();assert!(masks.advance(source,Span::new(0,source.len()),&tokens,None));assert_eq!(&masks.visible[..cut],prior.as_str());let mut whole=NativeLayoutMaskCursor::default();assert!(whole.advance(source,Span::new(0,source.len()),&tokens,None));assert_eq!(masks.visible,whole.visible);assert_eq!(masks.delimiters,whole.delimiters);assert_eq!(masks.multiline_literals,whole.multiline_literals);assert_eq!(masks.tokens,tokens.len());}
}

#[cfg(test)]mod demanded_native_inline_tests{use super::*;
fn frozen_actual_split_inline_blocks(source:&str,lines:&[Line],delimiters:&[u8],original:Option<&OriginalParseState<'_,'_,'_>>,raw_source:&str,tokens:&[SpanToken],range_start:usize)->Vec<Line>{
    let mut result = Vec::new();
    let mut brace_depth = 0usize;
    let mut initializer_depth = 0usize;
    let mut procedure:Option<(usize,usize)>=None;
    for line in lines {
        if original.is_some_and(|state|!state.poll()){break}
        if procedure.is_some_and(|(indent,base)|line.indent<=indent&&brace_depth<=base){procedure=None;}
        let in_body=procedure.is_some();
        let block_start=brace_depth;
        let opens_procedure=callable_header(&source[line.header_start..line.header_end]);
        let mut segment_start = line.header_start;
        let mut paren_depth = 0usize;
        let mut inline_do_if = false;
        for at in line.header_start..line.header_end {
            if at%1024==0&&original.is_some_and(|state|!state.poll()){return result}
            match delimiters[at] {
                b'(' | b'[' => paren_depth += 1,
                b')' | b']' => paren_depth = paren_depth.saturating_sub(1),
                b'{' if paren_depth == 0
                    && (initializer_depth > 0
                        || is_object_initializer_primary(&source[segment_start..at],in_body||(opens_procedure&&brace_depth>block_start),original.map(|state|(raw_source,TokenWindow::from_slice(tokens),Span::new(range_start+segment_start,range_start+at),state)))) =>
                {
                    initializer_depth += 1;
                }
                b'}' if paren_depth == 0 && initializer_depth > 0 => {
                    initializer_depth -= 1;
                }
                b'{' | b'}' | b';' if paren_depth == 0 && initializer_depth == 0 => {
                    let segment = &source[segment_start..at];
                    if let Some(do_at) = (delimiters[at] == b'{' && !inline_do_if)
                        .then(|| inline_if_do_suffix(segment))
                        .flatten()
                    {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            segment_start + do_at,
                            line.indent + brace_depth * 4, original);
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start + do_at,
                            at,
                            line.indent + brace_depth * 4 + 4, original);
                        inline_do_if = true;
                    } else {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            at,
                            line.indent + brace_depth * 4 + usize::from(inline_do_if) * 4, original);
                    }
                    if delimiters[at] == b'{' {
                        if let Some(header)=result.last_mut(){header.explicit_block_opener=true;}
                        brace_depth += 1;
                    } else if delimiters[at] == b'}' {
                        brace_depth = brace_depth.saturating_sub(1);
                    } else if brace_depth == 0
                        && inline_do_if
                        && segment.trim_start().starts_with("while")
                    {
                        inline_do_if = false;
                    }
                    segment_start = at + 1;
                }
                _ => {}
            }
        }
        if !in_body&&callable_header(&source[line.header_start..line.header_end]){procedure=Some((line.indent,block_start));}
        let indent = line.indent + brace_depth * 4 + usize::from(inline_do_if) * 4;
        if let Some(body_start) =
            inline_proc_body_start(source, delimiters, segment_start, line.header_end)
        {
            push_inline_segment(&mut result, source, segment_start, body_start, indent, original);
            if let Some(header)=result.last_mut(){header.same_line_body=true;}
            push_inline_segment(&mut result, source, body_start, line.header_end, indent + 4, original);
        } else {
            push_inline_segment(&mut result, source, segment_start, line.header_end, indent, original);
        }
    }
    result
}

 fn shape(rows:&[Line])->Vec<(usize,usize,usize,usize,bool,bool)>{rows.iter().map(|x|(x.indent,x.header_start,x.header_end,x.end,x.explicit_block_opener,x.same_line_body)).collect()}
 #[test]fn same_native_inline_splitter_retains_real_brace_and_procedure_state_across_line_demands(){for source in ["/datum/a {\n var/value=1;\n var/other=2;\n}\n/proc/p()\n return 3\n", "/proc/p() {\n if(1) do {\n return 1;\n } while(0);\n}\n/datum/b\n", "/datum/a\n var/value=new /datum/other {x=1; y=2}\n/proc/p() return 2\n"]{let tokens=lex_spans(source).tokens;let lines=structural_lines(source,source.as_bytes(),&[],None,source,&tokens,0);let expected=frozen_actual_split_inline_blocks(source,&lines,source.as_bytes(),None,source,&tokens,0);let mut cursor=NativeInlineBlockCursor::default();let mut actual=Vec::new();for line in &lines{actual.extend(cursor.advance(source,std::slice::from_ref(line),source.as_bytes(),None,source,TokenWindow::from_vec(&tokens),0));}assert_eq!(shape(&actual),shape(&expected));}}
}

#[cfg(test)]mod actual_absolute_body_scope_tests{
 use super::*;use std::io;use std::sync::{atomic::{AtomicUsize, Ordering}};
 #[test]fn real_static_scope_body_call_does_not_enter_original_formal_declaration_observer(){
  let source="/datum/probe\n    var/charge\n/datum/probe/proc/set_charge(value, datum/probe/other)\n    charge = value\n    /datum/probe::probe(set_other())\n/proc/set_other()\n    return 1\n";
  struct Observe(usize);impl OriginalDeclarationHeaderObserver for Observe{fn header(&mut self,event:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{assert!(!event.source()[event.span().range()].contains("::"),"actual body static-scope expression escaped to formal observer");self.0+=1;Ok(OriginalHeaderFlow::Continue)}}
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut observer=Observe(0);let primary=parse_original_declaration_skeleton_with_observer_using(source,&a,Some(&mut observer)).unwrap();assert_eq!(observer.0,2);assert!(primary.unavailable().is_none());assert!(primary.fatal().is_none());assert!(primary.syntax().diagnostics.is_empty());drop(primary);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let ordinary=crate::parse(source);assert!(ordinary.diagnostics.is_empty());let setter=ordinary.items.iter().find(|item|item.header.contains("/set_charge(")).unwrap();assert!(setter.children.iter().any(|child|child.kind==ItemKind::Statement&&child.header.contains("::probe(set_other())")));assert!(ordinary.items.iter().any(|item|item.header.contains("/set_other()")));
 }
 #[test]fn real_physical_dedent_and_relative_proc_namespaces_keep_declaration_membership(){
  let source="/datum/a\n    proc/first()\n        /datum/a::other()\n    proc/second()\n        return\n/datum/b\n    var/value=1\n";let primary=crate::parse_declaration_skeleton(source);assert!(primary.diagnostics.is_empty());let a=&primary.items[0];assert_eq!(a.kind,ItemKind::Type);assert_eq!(a.children.iter().filter(|item|item.kind==ItemKind::Proc).count(),2);assert_eq!(primary.items[1].header,"/datum/b");
 }
 #[test]fn normalized_header_scope_does_not_invent_original_body_membership_for_absolute_sibling(){
  let source="/datum/a\n    /proc/first()\n        return\n    /proc/second()\n        return\n";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let primary=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(primary.unavailable(),Some("Original absolute-line body scope needs actual indentation provenance"));assert!(primary.fatal().is_none());drop(primary);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  // Ordinary Native keeps its existing absolute-header normalization until a
  // genuine original indent producer, rather than a source-text heuristic,
  // can select the complete Original scope for this expanded-text ambiguity.
  let native=crate::parse(source);assert!(native.diagnostics.is_empty());assert_eq!(native.items.iter().filter(|item|item.kind==ItemKind::Proc).count(),2);
 }
}

#[cfg(test)]mod absolute_scope_prefix_compatibility{
 #[test]fn existing_included_first_line_absolute_header_prefix_normalization_keeps_ordinary_body_and_next_root(){
  let source="    /proc/first()\n    return\n/proc/second()\n    return\n";let parsed=crate::parse(source);assert!(parsed.diagnostics.is_empty());assert_eq!(parsed.items.len(),2);assert!(parsed.items[0].header.contains("first()"));assert_eq!(parsed.items[0].children.len(),1);assert_eq!(parsed.items[0].children[0].header,"return");assert!(parsed.items[1].header.contains("second()"));
 }
}

#[cfg(test)]
mod initializer_token_window_tests {
    use super::*;
    use std::sync::{atomic::{AtomicUsize, Ordering}};

    #[test]
    fn actual_initializer_probe_uses_only_the_requested_absolute_token_range() {
        let source = "new /datum/first\n/datum/plain\nnew /datum/last\n";
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let admission = SettingAdmission::new(&used, 4 << 20, &|| Ok(()));
        let original = OriginalParseState {
            storage: original_storage::Storage::new(&admission).unwrap(),
            fatal: Default::default(), unavailable: Default::default(), operational: Default::default(),
            observer: None, observer_stop: Default::default(), first_outer_block: Default::default(),
        };
        let tokens = lex_spans(source).tokens;
        let all = TokenWindow::from_vec(&tokens);
        let mut start = 0;
        for (raw, expected) in source.split_inclusive('\n').zip([true, false, true]) {
            let prefix = raw.trim_end_matches('\n');
            let span = Span::new(start, start + prefix.len());
            let first = all.partition_point(|token| token.span.end <= span.start);
            let last = all.partition_point(|token| token.span.start < span.end);
            let local = all.range(first, last).unwrap();
            assert_eq!(is_object_initializer_primary(prefix, false, Some((source, all, span, &original))), expected);
            assert_eq!(is_object_initializer_primary(prefix, false, Some((source, local, span, &original))), expected);
            start += raw.len();
        }
        drop(original);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
}

#[cfg(test)]
mod original_body_literal_layout_tests {
    use super::*;
    use crate::{OriginalLiteralData, OriginalStringMode, OriginalTokenValue};
    use std::sync::{atomic::{AtomicUsize, Ordering}};

    #[test]
    fn body_layout_uses_tu_literal_rows_at_exact_local_offsets() {
        let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
        let source="\"a[x]b\"";
        let origin=19;
        let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();
        for (start,end,value) in [(0,3,OriginalTokenValue::InterpBegin("a")),(4,7,OriginalTokenValue::InterpEnd("b"))] {
            let data=OriginalLiteralData::from_value_with_mode_using(source[start..end].into(),value,OriginalStringMode::Normal,&a).unwrap();
            facts.append_actual(Span::new(origin+start,origin+end),data,&a).unwrap();
        }
        facts.seal_actual_frontier(origin+source.len(),&a).unwrap();
        let rows=[SpanToken{kind:TokenKind::Interpolation,span:Span::new(0,3)},SpanToken{kind:TokenKind::Ident,span:Span::new(3,4)},SpanToken{kind:TokenKind::Interpolation,span:Span::new(4,7)}];
        let tokens=TokenWindow::from_slice(&rows);
        let local=Span::new(0,source.len());
        let view=facts.checked_data_window(Span::new(origin,origin+source.len())).unwrap();
        let (rows,offset)=view.raw_parts();
        let mut mask=NativeLayoutMaskCursor::default();
        assert!(mask.advance_with_literal_facts(source,local,tokens,None,Some((rows,offset))));
        assert_eq!(mask.delimiters.as_slice(),b"  [x]  ");
        assert!(!NativeLayoutMaskCursor::default().advance_with_literal_facts(source,local,tokens,None,Some((rows,0))));
        assert!(!NativeLayoutMaskCursor::default().advance_with_literal_facts("\"z[x]b\"",local,tokens,None,Some((rows,offset))));
        assert!(!NativeLayoutMaskCursor::default().advance_with_literal_facts(source,local,tokens,None,None));
        drop(facts);
        assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
    }
}
