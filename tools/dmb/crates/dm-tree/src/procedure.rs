//! Parsing of the shared declaration model; data structures live in dm-ir.
use dm_ir::{
    ExpressionToken, Parameter, ProcedureSetting, ProcedureSignature, SettingOperation, SymbolId,
    SymbolTable, SymbolicExpression,
};
use dm_syntax::{Span, TokenKind};
mod original_formal_notices;
pub use original_formal_notices::{OriginalFormalNotice,OriginalFormalNoticeLevel};
mod header;
pub(crate) mod header_input;
pub(crate) mod original_primary_signatures;
use header::{HeaderView, LexedHeader};
pub(crate) use header_input::{HeaderAllocationReceipt, OriginalProcedureHeaders};
fn intern(symbols: &mut SymbolTable, text: &str) -> Result<SymbolId, String> {
    symbols.intern(text).map_err(|error| error.to_string())
}
pub(crate) fn expression(
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<SymbolicExpression, String> {
    let lexed = LexedHeader::new(text);
    if !lexed.valid() {
        return Err("invalid expression tokens in procedure declaration".into());
    }
    expression_view(lexed.view(), symbols)
}
/// A variable input annotation follows its initializer, but is not part of it.
/// Use the shared lexer so quoted or nested `as` text remains expression text.
pub(crate) fn variable_initializer(text: &str) -> Result<&str, String> {
    let lexed = LexedHeader::new(text);
    if !lexed.valid() {
        return Err("invalid variable initializer tokens".into());
    }
    let end = lexed
        .view()
        .top_level()
        .into_iter()
        .find(|(token, _)| *token == "as")
        .map_or(text.len(), |(_, span)| span.start);
    Ok(text[..end].trim_end())
}
fn expression_view(
    view: HeaderView<'_>,
    symbols: &mut SymbolTable,
) -> Result<SymbolicExpression, String> {
    let mut tokens = Vec::new();
    for token in view.tokens() {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            continue;
        }
        tokens.push(ExpressionToken {
            kind: token.kind,
            text: intern(symbols, view.spelling(token))?,
            relative_span: view.relative_span(token),
        });
    }
    if tokens.is_empty() {
        return Err("empty procedure declaration expression".into());
    }
    Ok(SymbolicExpression {
        tokens: tokens.into(),
    })
}
fn top_level_tokens(text: &str) -> Vec<(String, Span)> {
    LexedHeader::new(text)
        .view()
        .top_level()
        .into_iter()
        .map(|(text, span)| (text.to_owned(), span))
        .collect()
}
/// Immutable DATA from the actual native parameter grammar failure and its
/// original primary following token. This is not source/semantic authority.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct OriginalParameterFatal{at:Span,following:OriginalParameterFollowing,prior_outer_block:bool}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub(crate) enum OriginalParameterFollowing {
    MissingDefault(char),
    Head(OriginalFormalHeadFollowing),
    /// The real preceding delimiter anchors this diagnostic. EOF has no token.
    ConsumedEnd,
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum OriginalFormalHeadFollowing{Assignment,Integer(i32),Float(u32)}
impl OriginalParameterFatal{
 pub fn prior_outer_block(self)->bool{self.prior_outer_block}pub fn token_span(self)->Span{self.at}
 // The receipt contains the authentic typed scalar, never a parsed Display
 // spelling. The same numeric writer is also used by the original lexer.
 pub fn write_message(self,mut out:&mut dyn std::fmt::Write)->std::fmt::Result{
  if let OriginalParameterFollowing::Head(head)=self.following{out.write_str("got '")?;match head{OriginalFormalHeadFollowing::Assignment=>out.write_char('=')?,OriginalFormalHeadFollowing::Integer(n)=>dm_syntax::numeric_form::write_original_float(n as f32,&mut out)?,OriginalFormalHeadFollowing::Float(bits)=>dm_syntax::numeric_form::write_original_float(f32::from_bits(bits),&mut out)?}return out.write_str("', expected one of: ')', ',', '...', '/'")}
  match self.following {
   OriginalParameterFollowing::MissingDefault(following)=>{
    let spelling=match following{')'=>")",','=>",",';'=>";",_=>unreachable!("private primary delimiter receipt")};
    dm_syntax::write_original_term_failure(out,Some(dm_syntax::OriginalTokenValue::Punct(spelling)))
   },
   OriginalParameterFollowing::ConsumedEnd=>out.write_str("got EOF, expected one of: ')', ','"),
   OriginalParameterFollowing::Head(_)=>unreachable!("head handled above"),
  }
 }
 pub fn message(self)->String{let mut out=String::new();self.write_message(&mut out).expect("String writer");out}

}
/// Genuine native input cursor failure DATA. Message bytes stay in the
/// existing prepared failure owner; this Copy receipt never owns dynamic text.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct OriginalInputParameterFatal{native:dm_syntax::OriginalInputFailure,at:Span,prior_outer_block:bool}
impl OriginalInputParameterFatal{pub fn token_span(self)->Span{self.at}pub fn prior_outer_block(self)->bool{self.prior_outer_block}pub fn expected(self)->dm_syntax::OriginalInputExpected{self.native.expected()}}
#[derive(Debug)]
pub(crate) struct SignatureError {
    pub(crate) message: String,
    pub(crate) source_span: Option<Span>,
    pub(crate) after_header: bool,
    pub(crate) missing_default_end: Option<usize>,
    pub(crate) original_fatal: Option<OriginalParameterFatal>,
    pub(crate) original_input_fatal:Option<OriginalInputParameterFatal>,
    pub(crate) formal_notices:Vec<OriginalFormalNotice>,
    pub(crate) formal_notices_complete:bool,
}
impl From<String> for SignatureError {
    fn from(message: String) -> Self {
        Self {
            message,
            source_span: None,
            after_header: false,
                    missing_default_end: None,
                    original_fatal: None,original_input_fatal:None,formal_notices:Vec::new(),formal_notices_complete:true,
        }
    }
}
impl From<&str> for SignatureError {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}
impl From<SignatureError> for String {
    fn from(error: SignatureError) -> Self {
        error.message
    }
}
pub(crate) struct ParsedParameterHead{name:Span,declaration:Span,declared_type:Option<SymbolId>,list_element_type:Option<SymbolId>,flags:u32,dialect:FormalDialect,notice_flags:u8,array_element_type:Option<SymbolId>,pending_dimensions:bool,array:Option<std::sync::Arc<dm_ir::ArrayDeclaration>>}
#[cfg(test)]fn parameter(view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable)->Result<Parameter,SignatureError>{parameter_with_dialect(view,start,symbols,FormalDialect::Compiler)}
#[cfg(test)]fn parameter_with_dialect(view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable,dialect:FormalDialect)->Result<Parameter,SignatureError>{
    let text = view.text();
    let (equal, annotation, source, post) = view.parameter_markers_full()?;
    let positions = [
        equal,
        annotation.map(|span| span.start),
        source.map(|span| span.start),
    ];
    let name_end = positions
        .iter()
        .flatten()
        .copied()
        .min()
        .unwrap_or(text.len());
    let head=parameter_head_using(view,start,symbols,name_end,dialect)?;
    parameter_tail_using(view,start,symbols,head,(equal,annotation,source,post))
}
fn parameter_head_using(view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable,name_end:usize,dialect:FormalDialect)->Result<ParsedParameterHead,SignatureError>{
    #[cfg(test)]PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.set(n.get()+1));
    let text=view.text();
    let declaration = text[..name_end].trim();
    // In BYOND a leading slash here issues an absolute type declaration and
    // contributes no argument. The signature-only model cannot issue that
    // declaration; do not silently reinterpret it as a relative typed argument.
    if declaration.starts_with('/') && dialect==FormalDialect::Compiler {
        return Err("unsupported absolute declaration in procedure argument list: requires an issued type declaration, not a parameter".into());
    }
    let declaration = if dialect==FormalDialect::Compiler{declaration.strip_prefix("var/").unwrap_or(declaration)}else{declaration};
    let path = declaration.split('[').next().unwrap().trim();
    let mut parts: Vec<_> = path.trim_matches('/').split('/').map(str::trim).collect();
    let original_var=dialect==FormalDialect::Original0290&&parts.len()>1&&parts.first()==Some(&"var");
    if original_var{parts.remove(0);}
    let name = parts.last().copied().unwrap_or("");
    if parts.iter().any(|part| {
        let offset = part.as_ptr() as usize - text.as_ptr() as usize;
        !view.slice(offset, offset + part.len()).ident()
    }) {
        for part in &parts {
            let offset = part.as_ptr() as usize - text.as_ptr() as usize;
            let part_view = view.slice(offset, offset + part.len());
            if part_view
                .tokens()
                .iter()
                .any(|token| token.kind == TokenKind::Number)
            {
                return Err(SignatureError {
                    message: "bad argument definition".into(),
                    source_span: Some(Span::new(start + offset, start + offset + part.len())),
                    after_header: false,
                    missing_default_end: None,
                    original_fatal: None,original_input_fatal:None,formal_notices:Vec::new(),formal_notices_complete:true,
                });
            }
        }
        return Err("unsupported procedure argument declaration path".into());
    }
    let mut flags = 0;
    let mut type_parts = Vec::new();
    // SAME formal path producer. Original0290 VarTypeBuilder::from_iter
    // consumes flags only while they precede the first type component;
    // ordinary Compiler retains its existing native flag projection.
    let mut original_prefix = true;
    for part in &parts[..parts.len() - 1] {
        if dialect == FormalDialect::Original0290 {
            let flag = if original_prefix { match *part {
                "static" | "global" => Some(1), "const" => Some(4), "tmp" => Some(8),
                "final" | "SpacemanDMM_final" => Some(16),
                "SpacemanDMM_private" => Some(32), "SpacemanDMM_protected" => Some(64),
                _ => None,
            }} else { None };
            match flag { Some(flag) => flags |= flag,
                None => { original_prefix = false; type_parts.push(*part); }
            }
        } else {
            flags |= match *part {
                "static" => 1, "const" => 2, "tmp" => 4, "global" => 8,
                _ => { type_parts.push(*part); 0 }
            };
        }
    }
    let element_type = if type_parts.is_empty() {
        None
    } else {
        Some(intern(symbols, &format!("/{}", type_parts.join("/")))?)
    };
    let declaration_start = declaration.as_ptr() as usize - text.as_ptr() as usize;
    let array = parse_array_view(
        view.slice(declaration_start, declaration_start + declaration.len()),
        element_type,
        symbols,
    )?;
    let authored_type = format!("/{}", type_parts.join("/"));
    let projection = dm_syntax::project_declaration_type(&authored_type);
    let list_element_type = projection
        .list_element_path
        .map(|path| intern(symbols, &format!("/{path}")))
        .transpose()?;
    let declared_type = if array.is_some() {
        Some(intern(symbols, "/list")?)
    } else if type_parts.is_empty() {
        None
    } else {
        Some(intern(
            symbols,
            dm_syntax::project_declaration_type(&format!("/{}", type_parts.join("/"))).runtime_path,
        )?)
    };
    let name_offset=name.as_ptr()as usize-text.as_ptr()as usize;
    Ok(ParsedParameterHead{name:Span::new(name_offset,name_offset+name.len()),declaration:view.slice(0,name_end).trim().span(),declared_type,list_element_type,flags,dialect,notice_flags:if dialect==FormalDialect::Original0290{u8::from(original_var)|if flags&1!=0{2}else{0}}else{0},array_element_type:element_type,pending_dimensions:false,array})
}
fn complete_head_dimensions(head:&mut ParsedParameterHead,view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<(),SignatureError>{
 let markers=view.parameter_markers_full()?;let end=[markers.0,markers.1.map(|span|span.start),markers.2.map(|span|span.start)].into_iter().flatten().min().unwrap_or(view.text().len());let declaration=view.slice(0,end).trim();let bracket=declaration.text().find('[').ok_or("actual dimensioned formal head lacks its opening bracket")?;
 if declaration.slice(0,bracket).trim().span()!=head.declaration{return Err("actual dimensioned head differs from its once-produced path metadata".into())}
 let array=parse_array_view(declaration,head.array_element_type,symbols)?.ok_or("actual dimensioned formal head produced no native array metadata")?;
 head.declared_type=Some(intern(symbols,"/list")?);head.array=Some(array);head.declaration=declaration.span();head.pending_dimensions=false;Ok(())
}
fn parameter_tail_using(view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable,head:ParsedParameterHead,markers:(Option<usize>,Option<Span>,Option<Span>,Option<Span>))->Result<Parameter,SignatureError>{
 let text=view.text();let(equal,annotation,source,post)=markers;let post=if head.dialect==FormalDialect::Original0290{post}else{None};let positions=[equal,annotation.map(|span|span.start),source.map(|span|span.start),post.map(|span|span.start)];let declaration_end=positions.iter().flatten().copied().min().unwrap_or(text.len());
 if view.slice(0,declaration_end).trim().span()!=head.declaration{return Err("prepared formal head differs from the actual completed declaration source".into())}
    fn end(positions: &[Option<usize>], start: usize, len: usize) -> usize {
        positions
            .iter()
            .flatten()
            .copied()
            .filter(|position| *position > start)
            .min()
            .unwrap_or(len)
    }
    let default = equal
        .map(|index| {
            let limit = end(&positions, index, text.len());
            if text[index + 1..limit].trim().is_empty() {
                return Err(SignatureError {
                    message: "missing expression".into(),
                    source_span: Some(Span::new(start + index, start + limit)),
                    after_header: false,
                    missing_default_end: Some(start + limit),
                    original_fatal: None,original_input_fatal:None,formal_notices:Vec::new(),formal_notices_complete:true,
                });
            }
            expression_view(view.slice(index + 1, limit).trim(), symbols)
                .map_err(SignatureError::from)
        })
        .transpose()?;
    let input_annotation = if head.dialect==FormalDialect::Original0290&&source.zip(annotation).is_some_and(|(source,annotation)|source.start<annotation.start){None}else{annotation
        .map(|span| {
            expression_view(
                view.slice(span.end, end(&positions, span.start, text.len()))
                    .trim(),
                symbols,
            )
        })
        .transpose()?};
    let source_expression = source
        .map(|span| {
            expression_view(
                view.slice(span.end, end(&positions, span.start, text.len()))
                    .trim(),
                symbols,
            )
        })
        .transpose()?;
    Ok(Parameter {
        name: intern(symbols, view.text().get(head.name.range()).ok_or("prepared formal name is outside the actual current header")?)?,
        declared_type:head.declared_type,
        list_element_type:head.list_element_type,
        flags:head.flags,
        array:head.array,
        default,
        input_annotation,
        source_expression,
        relative_span: Span::new(start, start + text.len()),
    })
}
pub(crate) struct HeaderTypeDeclaration {
    pub(crate) path: SymbolId,
    pub(crate) relative_span: Span,
}
pub(crate) struct ParsedSignature {
    pub(crate) signature: ProcedureSignature,
    pub(crate) declarations: Vec<HeaderTypeDeclaration>,
    pub(crate) formal_notices:Vec<OriginalFormalNotice>,
    pub(crate) formal_notices_complete:bool,
    pub(crate) original_clauses:Vec<dm_syntax::ParameterClauseSpans>,
    pub(crate) original_clauses_complete:bool,
}
#[cfg(test)]
pub(crate) fn parse_signature(
    arguments: &str,
    trailing: &str,
    symbols: &mut SymbolTable,
) -> Result<ProcedureSignature, String> {
    let parsed = parse_signature_declarations(arguments, trailing, symbols)?;
    if !parsed.declarations.is_empty() {
        return Err("unsupported absolute declaration in signature-only adapter".into());
    }
    Ok(parsed.signature)
}
pub(crate) fn parse_signature_declarations(
    arguments: &str,
    trailing: &str,
    symbols: &mut SymbolTable,
) -> Result<ParsedSignature, SignatureError> {
    // Standalone compatibility entry. The native frontend calls the original
    // issued token-view route below and never enters this lexical adapter.
    let args = LexedHeader::new(arguments);
    let tail = LexedHeader::new(trailing);
    if !args.valid() || !tail.valid() {
        return Err("invalid procedure header tokens".into());
    }
    parse_signature_views(args.view(), tail.view(), symbols)
}
// SAME genuine formal pass may pause before return/as suffix acquisition.
// The owned result moves with its real SymbolTable; it is neither cloned nor
// reinterpreted when the actual remaining header becomes available.
pub(crate) struct ParsedFormalParameters{parameters:Vec<dm_ir::Parameter>,variadic:bool,declarations:Vec<HeaderTypeDeclaration>,formal_notices:Vec<OriginalFormalNotice>,formal_notices_complete:bool,original_clauses:Vec<dm_syntax::ParameterClauseSpans>,original_clauses_complete:bool}
#[derive(Clone,Copy,Eq,PartialEq)]enum FormalDialect{Compiler,Original0290}
pub(crate) struct FormalParameterAccumulator{dialect:FormalDialect,formals:ParsedFormalParameters,prepared_head:Option<ParsedParameterHead>,observed_input:Option<usize>,observed_semicolon:Option<Span>}
impl FormalParameterAccumulator{
 pub(crate) fn new()->Self{Self::with_dialect(FormalDialect::Compiler)}
 // This private metadata mode never grants source/model authority.
 fn new_original()->Self{Self::with_dialect(FormalDialect::Original0290)}
 fn with_dialect(dialect:FormalDialect)->Self{
  #[cfg(test)]SIGNATURE_INTERPRETATIONS.with(|n|n.set(n.get()+1));
  Self{dialect,formals:ParsedFormalParameters{parameters:Vec::new(),variadic:false,declarations:Vec::new(),formal_notices:Vec::new(),formal_notices_complete:true,original_clauses:Vec::new(),original_clauses_complete:true},prepared_head:None,observed_input:None,observed_semicolon:None}
 }
 pub(crate) fn consume(&mut self,view:HeaderView<'_>,start:usize,stop:usize,comma:bool,symbols:&mut SymbolTable)->Result<(),SignatureError>{self.consume_using(view,start,stop,comma,symbols,None)}
 fn consume_produced(&mut self,view:HeaderView<'_>,start:usize,stop:usize,comma:bool,symbols:&mut SymbolTable,clauses:dm_syntax::ParameterClauseSpans)->Result<(),SignatureError>{if self.dialect!=FormalDialect::Original0290||clauses.parameter!=view.span(){return Err("produced formal clauses differ from actual native source scope".into())}self.consume_using(view,start,stop,comma,symbols,Some(clauses))}
 fn consume_using(&mut self,view:HeaderView<'_>,start:usize,stop:usize,comma:bool,symbols:&mut SymbolTable,produced:Option<dm_syntax::ParameterClauseSpans>)->Result<(),SignatureError>{
        let mut view=view;let mut trailing_semicolon=None;
        if self.dialect==FormalDialect::Original0290{if let Some(token)=view.tokens().iter().rev().find(|token|!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment)){if view.spelling(token)==";"{let local=view.relative_span(token);let at=Span::new(start.checked_add(local.start).ok_or("formal semicolon position overflow")?,start.checked_add(local.end).ok_or("formal semicolon position overflow")?);trailing_semicolon=Some(at);view=view.slice(0,local.start);}}}
        let untrimmed = view.text();
        let leading = untrimmed.len() - untrimmed.trim_start().len();
        let text = untrimmed.trim();
        // BYOND accepts an empty signature and a final comma, but an empty
        // slot before a comma is an invalid formal, not an omitted parameter.
        if text.is_empty() && comma {
            return Err(SignatureError {
                message: "bad argument definition".into(),
                source_span: Some(Span::new(start, stop)),
                after_header: true,
                    missing_default_end: None,
                    original_fatal: None,original_input_fatal:None,formal_notices:Vec::new(),formal_notices_complete:true,
            });
        }
        if text == "..." {
            self.formals.variadic = true
        } else if !text.is_empty() {
            if self.formals.variadic {
                return Err("procedure argument follows variadic marker".into());
            }
            if text.starts_with('/') && self.dialect==FormalDialect::Compiler {
                // An absolute path in a formal header declares that type; it
                // does not name a parameter (BYOND 516.1687 compile oracle).
                // More elaborate declaration effects remain explicit gaps.
                dm_ir::TypePath::parse(text).map_err(|_| {
                    "unsupported absolute declaration in procedure argument list".to_string()
                })?;
                let view = view.slice(leading, leading + text.len());
                if text.trim_matches('/').split('/').any(|part| {
                    let offset = part.as_ptr() as usize - text.as_ptr() as usize;
                    matches!(part, "var" | "proc" | "verb")
                        || !view.slice(offset, offset + part.len()).ident()
                }) {
                    return Err(
                        "unsupported absolute declaration in procedure argument list".into(),
                    );
                }
                self.formals.declarations.push(HeaderTypeDeclaration {
                    path: intern(symbols, text)?,
                    relative_span: Span::new(start + leading, start + leading + text.len()),
                });
            } else {
                let view=view.slice(leading,leading+text.len());let start=start+leading;
                let markers=match produced{Some(parts)=>{let relative=|span:Span|->Result<Span,SignatureError>{Ok(Span::new(span.start.checked_sub(view.span().start).ok_or("produced formal marker before actual source")?,span.end.checked_sub(view.span().start).ok_or("produced formal marker before actual source")?))};(parts.assignment.map(relative).transpose()?.map(|span|span.start),parts.annotation.map(relative).transpose()?,parts.source.map(relative).transpose()?,parts.post_source_annotation.map(relative).transpose()?)},None=>view.parameter_markers_full()?};let mut head=match self.prepared_head.take(){Some(head)=>head,None=>{let end=[markers.0,markers.1.map(|span|span.start),markers.2.map(|span|span.start)].into_iter().flatten().min().unwrap_or(view.text().len());parameter_head_using(view,start,symbols,end,self.dialect)?}};
                self.capture_head_notices(&mut head,start);if head.pending_dimensions{complete_head_dimensions(&mut head,view,symbols)?;}let parameter=parameter_tail_using(view,start,symbols,head,markers)?;
                if self.dialect==FormalDialect::Original0290&&markers.1.is_some()&&self.observed_input!=Some(self.formals.parameters.len()){self.formals.formal_notices_complete=false;}
                if let Some(mut parts)=produced{let origin=view.span().start.checked_sub(start).ok_or("produced formal argument origin underflow")?;let shift=|span:Span|->Result<Span,SignatureError>{Ok(Span::new(span.start.checked_sub(origin).ok_or("produced formal marker origin underflow")?,span.end.checked_sub(origin).ok_or("produced formal marker origin underflow")?))};parts.parameter=shift(parts.parameter)?;parts.assignment=parts.assignment.map(shift).transpose()?;parts.annotation=parts.annotation.map(shift).transpose()?;parts.source=parts.source.map(shift).transpose()?;parts.post_source_annotation=parts.post_source_annotation.map(shift).transpose()?;self.formals.original_clauses.push(parts);}else{self.formals.original_clauses_complete=false;}
                self.formals.parameters.push(parameter);self.observed_input=None;
                if let Some(at)=trailing_semicolon{if let Some(observed)=self.observed_semicolon.take(){if observed!=at{return Err("observed original semicolon differs from completed native formal".into())}}else{self.formals.formal_notices.push(OriginalFormalNotice::new(at,original_formal_notices::Kind::Semicolon));}}
            }
        }
  Ok(())
 }
 pub(crate) fn prepare_head(&mut self,view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable)->Result<(),SignatureError>{
  if self.prepared_head.is_some()||self.formals.variadic{return Err("actual formal head is already prepared or follows a variadic marker".into())}
  let text=view.text();let leading=text.len()-text.trim_start().len();let trimmed=text.trim();let view=view.slice(leading,leading+trimmed.len());
  let mut head=parameter_head_using(view,start+leading,symbols,view.text().len(),self.dialect)?;self.capture_head_notices(&mut head,start+leading);self.prepared_head=Some(head);Ok(())
 }
 pub(crate) fn prepare_dimension_head(&mut self,view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable)->Result<(),SignatureError>{
  if let Some(head)=&self.prepared_head{if head.pending_dimensions{return Ok(())}return Err("dimension follows an already completed actual formal declaration".into())}
  self.prepare_head(view,start,symbols)?;self.prepared_head.as_mut().expect("actual prepared path").pending_dimensions=true;Ok(())
 }
 pub(crate) fn admit_prepared_head(&mut self,view:HeaderView<'_>,start:usize,symbols:&mut SymbolTable)->Result<(),SignatureError>{
  let markers=view.parameter_markers_full()?;let end=[markers.0,markers.1.map(|span|span.start),markers.2.map(|span|span.start)].into_iter().flatten().min().unwrap_or(view.text().len());let view=view.slice(0,end).trim();
  if let Some(head)=&mut self.prepared_head{if head.pending_dimensions{return complete_head_dimensions(head,view,symbols)}if head.declaration!=view.span(){return Err("actual later formal marker changed its already-produced native head".into())}return Ok(())}
  self.prepare_head(view,start,symbols)
 }
 pub(crate) fn has_prepared_head(&self)->bool{self.prepared_head.is_some()}
 fn parameter_ordinal(&self)->usize{self.formals.parameters.len()}
 fn mark_semicolon_observed(&mut self,at:Span)->Result<(),SignatureError>{if self.observed_semicolon.replace(at).is_some(){return Err("actual formal semicolon was already observed".into())}Ok(())}
 fn mark_input_observed(&mut self){self.observed_input=Some(self.formals.parameters.len())}
 fn capture_head_notices(&mut self,head:&mut ParsedParameterHead,start:usize){use original_formal_notices::{Kind,OriginalFormalNotice};let at=Span::new(start,start+1);if head.notice_flags&1!=0{self.formals.formal_notices.push(OriginalFormalNotice::new(at,Kind::Var));}if head.notice_flags&2!=0{self.formals.formal_notices.push(OriginalFormalNotice::new(at,Kind::Static));}head.notice_flags=0;}
 fn take_formal_notices(&mut self)->Vec<OriginalFormalNotice>{std::mem::take(&mut self.formals.formal_notices)}

 pub(crate) fn finish(self)->ParsedFormalParameters{self.formals}
}
/// Actual native default roots are moved to the existing header/parameter
/// recipe, never reparsed from their spelling. These outcomes confer no source
/// or compatibility authority until the SAME primary frame joins the receipt.
#[derive(Clone,Copy,Debug,Eq,PartialEq,Ord,PartialOrd)]pub(crate) enum FormalExpressionRole{Dimension(usize),Default,Source}
pub(crate) struct DemandedFormalRoot{pub(crate) role:FormalExpressionRole,pub(crate) enclosure:Option<Span>,pub(crate) parameter:usize,pub(crate) assignment:Span,pub(crate) syntax:dm_syntax::DemandedExpression}
pub(crate) enum DemandedFormalDimension{Complete{root:DemandedFormalRoot,boundary:dm_syntax::Token},Empty{boundary:dm_syntax::Token},Failure(DemandedFormalDefault)}
pub(crate) struct DemandedFormalTermFailure{pub(crate) expected:dm_syntax::NativeTermExpectation,pub(crate) syntax:dm_syntax::DemandedExpression,pub(crate) boundary:Option<dm_syntax::Token>}
pub(crate) enum DemandedFormalDefault{Complete{root:DemandedFormalRoot,boundary:Option<dm_syntax::Token>},ExpectedTerm(DemandedFormalTermFailure),NativeSyntax{syntax:dm_syntax::DemandedExpression,boundary:Option<dm_syntax::Token>}}
impl FormalParameterAccumulator{
 pub(crate) fn default_using(&self,source:&mut dyn dm_syntax::NativeExpressionTokenDemand,clauses:&mut dm_syntax::ParameterClauseCursor,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<DemandedFormalDefault>{
  let assignment=clauses.spans().assignment.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"native default demand began without actual assignment marker"))?;
  let mut input=dm_syntax::ParameterExpressionDemand::new(source,clauses);let original=self.dialect==FormalDialect::Original0290;if original{input=input.original();}let syntax=if original{dm_syntax::parse_original_expression_demanded(&mut input,a)?}else{dm_syntax::parse_expression_demanded(&mut input,a)?};let boundary=input.take_boundary();
  if let Some(expected)=syntax.expected_term(){return Ok(DemandedFormalDefault::ExpectedTerm(DemandedFormalTermFailure{expected,syntax,boundary}))}
  if !syntax.parsed().diagnostics.is_empty(){return Ok(DemandedFormalDefault::NativeSyntax{syntax,boundary})}
  if syntax.parsed().expr.is_none(){return Err(std::io::Error::new(std::io::ErrorKind::Other,"actual native default parser returned neither root nor genuine failure state"))}
  Ok(DemandedFormalDefault::Complete{root:DemandedFormalRoot{role:FormalExpressionRole::Default,enclosure:None,parameter:self.formals.parameters.len(),assignment,syntax},boundary})
 }
}
impl FormalParameterAccumulator{
 pub(crate) fn source_using(&self,source:&mut dyn dm_syntax::NativeExpressionTokenDemand,clauses:&mut dm_syntax::ParameterClauseCursor,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<DemandedFormalDefault>{
  let marker=clauses.spans().source.ok_or(std::io::ErrorKind::InvalidInput)?;let mut input=dm_syntax::ParameterExpressionDemand::for_source(source,clauses);let original=self.dialect==FormalDialect::Original0290;if original{input=input.original();}let syntax=if original{dm_syntax::parse_original_expression_demanded(&mut input,a)?}else{dm_syntax::parse_expression_demanded(&mut input,a)?};let boundary=input.take_boundary();
  if let Some(expected)=syntax.expected_term(){return Ok(DemandedFormalDefault::ExpectedTerm(DemandedFormalTermFailure{expected,syntax,boundary}))}
  if !syntax.parsed().diagnostics.is_empty(){return Ok(DemandedFormalDefault::NativeSyntax{syntax,boundary})}
  if syntax.parsed().expr.is_none(){return Err(std::io::ErrorKind::InvalidData.into())}
  Ok(DemandedFormalDefault::Complete{root:DemandedFormalRoot{role:FormalExpressionRole::Source,enclosure:None,parameter:self.formals.parameters.len(),assignment:marker,syntax},boundary})
 }
 pub(crate) fn dimension_using(&self,source:&mut dyn dm_syntax::NativeExpressionTokenDemand,clauses:&mut dm_syntax::ParameterClauseCursor,opening:Span,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<DemandedFormalDimension>{
  let mut input=dm_syntax::ParameterExpressionDemand::for_dimension(source,clauses);let original=self.dialect==FormalDialect::Original0290;if original{input=input.original();}let syntax=if original{dm_syntax::parse_original_expression_demanded(&mut input,a)?}else{dm_syntax::parse_expression_demanded(&mut input,a)?};let boundary=input.take_boundary();
  let closes=boundary.as_ref().is_some_and(|token|token.kind==TokenKind::Punctuation&&token.text=="]");
  if syntax.expected_term().is_some_and(|event|event.token_span().is_none())&&syntax.tokens().is_empty()&&closes{return Ok(DemandedFormalDimension::Empty{boundary:boundary.expect("actual matching dimension close")})}
  if let Some(expected)=syntax.expected_term(){return Ok(DemandedFormalDimension::Failure(DemandedFormalDefault::ExpectedTerm(DemandedFormalTermFailure{expected,syntax,boundary})))}
  if !syntax.parsed().diagnostics.is_empty(){return Ok(DemandedFormalDimension::Failure(DemandedFormalDefault::NativeSyntax{syntax,boundary}))}
  if !closes||syntax.parsed().expr.is_none(){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual dimension EOF/closing failure is not issued"))}
  let boundary=boundary.expect("actual matching dimension close");let enclosure=Span::new(opening.start,boundary.span.end);
  Ok(DemandedFormalDimension::Complete{root:DemandedFormalRoot{role:FormalExpressionRole::Dimension(ordinal),enclosure:Some(enclosure),parameter:self.formals.parameters.len(),assignment:opening,syntax},boundary})
 }
}
fn parse_formal_parameters_views(arguments_view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedFormalParameters,SignatureError>{
 parse_formals_using(arguments_view,symbols,FormalParameterAccumulator::new())
}
fn parse_original_formal_parameters_views(arguments_view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedFormalParameters,SignatureError>{parse_formals_using(arguments_view,symbols,FormalParameterAccumulator::new_original())}
fn parse_formals_using(arguments_view:HeaderView<'_>,symbols:&mut SymbolTable,mut parser:FormalParameterAccumulator)->Result<ParsedFormalParameters,SignatureError>{
 let arguments=arguments_view.text();let mut start=0;
 let mut stops:Vec<_>=arguments_view.top_level().into_iter().filter(|(token,_)|*token==",").map(|(_,span)|span.start).collect();stops.push(arguments.len());
 for stop in stops{if let Err(mut error)=parser.consume(arguments_view.slice(start,stop),start,stop,stop<arguments.len(),symbols){error.formal_notices=parser.take_formal_notices();error.formal_notices_complete=parser.formals.formal_notices_complete;return Err(error)}start=stop+1;}
 Ok(parser.finish())
}
fn return_annotation_view(trailing: HeaderView<'_>) -> Result<Option<HeaderView<'_>>, &'static str> {
    let trailing = trailing.trim();
    if trailing.text().is_empty() {
        return Ok(None);
    }
    // The Original stream separates tokens by their adjacency needs. In
    // particular, it does not insert a space between 'as' and a type path.
    let marker = trailing.tokens().first().filter(|token| {
        token.kind == TokenKind::Ident
            && token.span.start == trailing.span().start
            && trailing.spelling(token) == "as"
    }).ok_or("unsupported procedure return annotation")?;
    let suffix = trailing.slice(trailing.relative_span(marker).end, trailing.text().len());
    let separator = usize::from(suffix.text().starts_with(' '));
    Ok(Some(suffix.slice(separator, suffix.text().len())))
}

fn finish_signature_views(formals:ParsedFormalParameters,trailing_view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedSignature,SignatureError>{
    let return_annotation = return_annotation_view(trailing_view)?
        .map(|annotation| expression_view(annotation, symbols))
        .transpose()?;
    Ok(ParsedSignature {
        signature: ProcedureSignature {
            parameters: formals.parameters.into(),
            variadic:formals.variadic,
            return_annotation,
        },
        declarations:formals.declarations,formal_notices:formals.formal_notices,formal_notices_complete:formals.formal_notices_complete,original_clauses:formals.original_clauses,original_clauses_complete:formals.original_clauses_complete,
    })
}
fn parse_signature_views(arguments_view:HeaderView<'_>,trailing_view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedSignature,SignatureError>{
 let formals=parse_formal_parameters_views(arguments_view,symbols)?;finish_signature_views(formals,trailing_view,symbols)
}

pub(crate) struct ParsedSetting {
    pub(crate) setting: ProcedureSetting,
    /// RHS extent relative to this exact original setting header, not an Expr.
    pub(crate) value_span: Span,
}
pub(crate) fn parse_setting(
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<ProcedureSetting, String> {
    let text = text
        .trim()
        .strip_prefix("set ")
        .ok_or("expected set declaration")?;
    let (name, operation, value) = if let Some(index) = dm_syntax::top_level_assignment_index(text)
    {
        (
            text[..index].trim(),
            SettingOperation::Assign,
            text[index + 1..].trim(),
        )
    } else {
        let span = top_level_tokens(text)
            .into_iter()
            .find(|(token, _)| token == "in")
            .map(|(_, span)| span)
            .ok_or("set declaration missing assignment or in")?;
        (
            text[..span.start].trim(),
            SettingOperation::In,
            text[span.end..].trim(),
        )
    };
    // Checker annotations are shared source metadata, not runtime ABI settings.
    // Only the native identifier spelling is admitted; ordinary unknown names
    // remain errors. Compile-command policy rejects these annotations separately.
    let checker_name = LexedHeader::new(name);
    let checker_tokens = checker_name.view();
    let checker_setting = name.starts_with("SpacemanDMM_")
        && checker_name.valid()
        && matches!(checker_tokens.tokens(), [token] if token.kind == TokenKind::Ident
            && checker_tokens.spelling(token) == name);
    construct_setting(name, checker_setting, operation, symbols, |symbols| {
        expression(value, symbols)
    })
}

/// Shared setting metadata partition over the SAME existing HeaderView grammar.
/// Native callers supply original cold tokens; compatibility above retains its lexical path.
struct SettingParts<'a> {
    name: HeaderView<'a>,
    operation: SettingOperation,
    value: HeaderView<'a>,
    value_span: Span,
}
fn setting_parts(view: HeaderView<'_>) -> Result<SettingParts<'_>, String> {
    let header = view;
    let view = view.trim();
    let text = view.text();
    let _rest = text
        .strip_prefix("set ")
        .ok_or("expected set declaration")?;
    let rest = view.slice(4, text.len());
    let (name, operation, value) = if let Some(index) = rest.assignment_index() {
        (
            rest.slice(0, index).trim(),
            SettingOperation::Assign,
            rest.slice(index + 1, rest.text().len()).trim(),
        )
    } else {
        let span = rest
            .first_top_level("in")
            .ok_or("set declaration missing assignment or in")?;
        (
            rest.slice(0, span.start).trim(),
            SettingOperation::In,
            rest.slice(span.end, rest.text().len()).trim(),
        )
    };

    let value_span = Span::new(
        value.span().start - header.span().start,
        value.span().end - header.span().start,
    );
    Ok(SettingParts {
        name,
        operation,
        value,
        value_span,
    })
}
#[cfg(test)]
thread_local! {static ORIGINAL_SETTING_PARSES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]
pub(crate) fn original_setting_metadata_parses() -> usize {
    ORIGINAL_SETTING_PARSES.with(|n| n.get())
}
fn parse_setting_view(view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedSetting,String>{parse_setting_view_profile(view,symbols,false)}
fn parse_setting_view_profile(
    view: HeaderView<'_>,
    symbols: &mut SymbolTable,
    checker_diagnostics: bool,
) -> Result<ParsedSetting, String> {
    #[cfg(test)]
    ORIGINAL_SETTING_PARSES.with(|n| n.set(n.get() + 1));
    let parts = setting_parts(view)?;
    let spelling = parts.name.text();
    let checker_setting = (spelling.starts_with("SpacemanDMM_") || checker_diagnostics) && parts.name.ident();
    Ok(ParsedSetting {
        setting: construct_setting(
            spelling,
            checker_setting,
            parts.operation,
            symbols,
            |symbols| expression_view(parts.value, symbols),
        )?,
        value_span: parts.value_span,
    })
}

/// ONE existing setting-name/metadata policy; compatibility keeps its original
/// lexical/error-order path and native views reuse the original primary tokens.
fn construct_setting(
    name: &str,
    checker_setting: bool,
    operation: SettingOperation,
    symbols: &mut SymbolTable,
    value: impl FnOnce(&mut SymbolTable) -> Result<SymbolicExpression, String>,
) -> Result<ProcedureSetting, String> {
    if !checker_setting && !ordinary_compiler_setting_name(name)
    {
        return Err(format!("unknown procedure setting: {name}"));
    }
    Ok(ProcedureSetting {
        name: intern(symbols, name)?,
        operation,
        value: value(symbols)?,
    })
}

pub(crate) fn parse_array(
    declaration: &str,
    element_type: Option<SymbolId>,
    symbols: &mut SymbolTable,
) -> Result<Option<std::sync::Arc<dm_ir::ArrayDeclaration>>, String> {
    let tokens = LexedHeader::new(declaration);
    if !tokens.valid() {
        return Err("invalid array declaration tokens".into());
    }
    parse_array_view(tokens.view(), element_type, symbols)
}
/// Borrowed cursor for the SAME existing suffix grammar. It owns no tokens,
/// source, syntax or semantic roster; metadata and native roots consume it once.
#[cfg(test)]thread_local!{static ARRAY_DIMENSION_STEPS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]pub(crate) fn reset_array_dimension_steps(){ARRAY_DIMENSION_STEPS.with(|n|n.set(0));}
#[cfg(test)]pub(crate) fn array_dimension_steps()->usize{ARRAY_DIMENSION_STEPS.with(std::cell::Cell::get)}
pub(crate) struct ArrayDimensions<'a>{view:HeaderView<'a>,at:usize,depth:usize,start:Option<usize>,count:usize,done:bool}
pub(crate) fn array_dimensions(view:HeaderView<'_>)->ArrayDimensions<'_>{ArrayDimensions{view,at:0,depth:0,start:None,count:0,done:false}}
impl<'a> Iterator for ArrayDimensions<'a>{
 type Item=Result<HeaderView<'a>,String>;
 fn next(&mut self)->Option<Self::Item>{
  if self.done{return None}
  while let Some(token)=self.view.tokens().get(self.at){
   #[cfg(test)]ARRAY_DIMENSION_STEPS.with(|n|n.set(n.get()+1));
   self.at+=1;
   if self.depth==0&&self.count!=0&&self.view.spelling(token)!="["&&!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment){self.done=true;return Some(Err("unsupported text after array declaration".into()))}
   match self.view.spelling(token){
    "["=>{if self.depth==0{self.start=Some(self.view.relative_span(token).end)}self.depth+=1},
    "]"=>{if self.depth==0{self.done=true;return Some(Err("unmatched array declaration bracket".into()))}self.depth-=1;if self.depth==0{let start=self.start.take().expect("outer bracket issued start");let dimension=self.view.slice(start,self.view.relative_span(token).start).trim();self.count+=1;return Some(Ok(dimension))}},
    _=>{},
   }
  }
  self.done=true;if self.depth!=0{Some(Err("unterminated array declaration".into()))}else{None}
 }
}
pub(crate) fn visit_array_dimensions<'a>(view:HeaderView<'a>,mut emit:impl FnMut(usize,HeaderView<'a>)->Result<(),String>)->Result<usize,String>{
 let mut count=0;for dimension in array_dimensions(view){emit(count,dimension?)?;count+=1;}Ok(count)
}
fn parse_array_view(view:HeaderView<'_>,element_type:Option<SymbolId>,symbols:&mut SymbolTable)->Result<Option<std::sync::Arc<dm_ir::ArrayDeclaration>>,String>{
 let mut dimensions=Vec::new();
 visit_array_dimensions(view,|_,dimension|{#[cfg(test)]ARRAY_DIMENSION_ROWS.with(|n|n.set(n.get()+1));dimensions.push(if dimension.text().is_empty(){None}else{Some(expression_view(dimension,symbols)?)});Ok(())})?;
 if dimensions.is_empty(){Ok(None)}else{Ok(Some(std::sync::Arc::new(dm_ir::ArrayDeclaration{dimensions:dimensions.into(),element_type})))}
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn typed_list_formals_retain_distinct_hints_in_signature_identity() {
        let mut symbols = SymbolTable::default();
        let first =
            parse_signature("list/datum/item/values, list/plain", "", &mut symbols).unwrap();
        let equivalent = parse_signature(
            " list / datum / item / values , list / plain ",
            "",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(first.canonical_bytes(), equivalent.canonical_bytes());
        assert_eq!(
            first.parameters[0].declared_type,
            Some(SymbolId::of("/list"))
        );
        assert_eq!(
            first.parameters[0].list_element_type,
            Some(SymbolId::of("/datum/item"))
        );
        assert!(first.parameters[0].array.is_none());
        assert_eq!(first.parameters[1].list_element_type, None);
        let other =
            parse_signature("list/datum/other/values, list/plain", "", &mut symbols).unwrap();
        assert_ne!(first.canonical_bytes(), other.canonical_bytes());
    }
    #[test]
    fn argument_modifiers_arrays_defaults_and_sources_are_retained() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "var/tmp/const/datum/item/items[2][] = list() as anything in world, static/value = 3",
            "",
            &mut symbols,
        )
        .unwrap();
        let parameter = &signature.parameters[0];
        assert_eq!(parameter.flags, 2 | 4);
        assert_eq!(parameter.declared_type, Some(SymbolId::of("/list")));
        let array = parameter.array.as_ref().unwrap();
        assert_eq!(array.element_type, Some(SymbolId::of("/datum/item")));
        assert_eq!(array.dimensions.len(), 2);
        assert!(array.dimensions[0].is_some());
        assert!(array.dimensions[1].is_none());
        assert!(parameter.default.is_some());
        assert!(parameter.input_annotation.is_some());
        assert!(parameter.source_expression.is_some());
        assert_eq!(signature.parameters[1].flags, 1);
        assert_eq!(signature.parameters[1].declared_type, None);
        let plain = parse_signature("value", "", &mut symbols).unwrap();
        let temporary = parse_signature("tmp/value", "", &mut symbols).unwrap();
        let unsized_array = parse_signature("value[]", "", &mut symbols).unwrap();
        let sized = parse_signature("value[2]", "", &mut symbols).unwrap();
        assert_ne!(plain.canonical_bytes(), temporary.canonical_bytes());
        assert_ne!(unsized_array.canonical_bytes(), sized.canonical_bytes());
    }
    #[test]
    fn argument_array_paths_do_not_consume_dimension_paths_or_trailing_junk() {
        let mut symbols = SymbolTable::default();
        let signature =
            parse_signature("datum/item/items[length(/datum/item)]", "", &mut symbols).unwrap();
        assert_eq!(signature.parameters[0].name, SymbolId::of("items"));
        assert_eq!(
            signature.parameters[0].array.as_ref().unwrap().element_type,
            Some(SymbolId::of("/datum/item"))
        );
        for argument in [
            "value[2] garbage",
            "datum//value",
            "value[",
            "value]",
            "value[-\"",
        ] {
            assert!(
                parse_signature(argument, "", &mut symbols).is_err(),
                "{argument}"
            );
        }
    }
    #[test]
    fn absolute_header_declaration_is_not_a_relative_typed_parameter() {
        let mut symbols = SymbolTable::default();
        let relative = parse_signature("datum/marker_target/target", "", &mut symbols).unwrap();
        assert_eq!(relative.parameters.len(), 1);
        assert_eq!(relative.parameters[0].name, SymbolId::of("target"));
        assert_eq!(
            relative.parameters[0].declared_type,
            Some(SymbolId::of("/datum/marker_target"))
        );
        let absolute =
            parse_signature_declarations("/datum/marker_target/target", "", &mut symbols).unwrap();
        assert!(absolute.signature.parameters.is_empty());
        assert_eq!(absolute.declarations.len(), 1);
        assert_eq!(
            absolute.declarations[0].path,
            SymbolId::of("/datum/marker_target/target")
        );
        assert_eq!(absolute.declarations[0].relative_span, Span::new(0, 27));
        for declaration in [
            "/var/value",
            "/datum/marker_target/proc/call",
            "/datum/marker_target/target = 1",
        ] {
            assert!(parse_signature_declarations(declaration, "", &mut symbols).is_err());
        }
    }

    #[test]
    fn absolute_header_effects_do_not_consume_surrounding_parameters() {
        for arguments in [
            "/datum/marker_target/target, other",
            "other, /datum/marker_target/target",
            "other,/datum/marker_target/target",
            "other ,  /datum/marker_target/target",
            "datum/marker_target/other, /datum/marker_target/target, actual_power=1",
        ] {
            let mut symbols = SymbolTable::default();
            let parsed = parse_signature_declarations(arguments, "", &mut symbols).unwrap();
            let expected: &[&str] = if arguments.ends_with("actual_power=1") {
                &["other", "actual_power"]
            } else {
                &["other"]
            };
            let names: Vec<_> = parsed
                .signature
                .parameters
                .iter()
                .map(|parameter| parameter.name)
                .collect();
            assert_eq!(
                names,
                expected
                    .iter()
                    .map(|name| SymbolId::of(name))
                    .collect::<Vec<_>>()
            );
            assert_eq!(parsed.declarations.len(), 1);
            let effect = &parsed.declarations[0];
            assert_eq!(effect.path, SymbolId::of("/datum/marker_target/target"));
            assert_eq!(
                &arguments[effect.relative_span.start..effect.relative_span.end],
                "/datum/marker_target/target"
            );
        }
    }

    #[test]
    fn trailing_argument_path_separator_preserves_name_and_type() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature("obj/instance/", "", &mut symbols).unwrap();
        assert_eq!(signature.parameters[0].name, SymbolId::of("instance"));
        assert_eq!(
            signature.parameters[0].declared_type,
            Some(SymbolId::of("/obj"))
        );
        assert!(signature.parameters[0].array.is_none());
    }
    #[test]
    fn typed_default_input_and_source_are_separate() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "value as text, count = 3 as num, target as obj in view(1)",
            "",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(signature.parameters.len(), 3);
        let count = &signature.parameters[1];
        assert_eq!(symbols.text(count.name), Some("count"));
        assert_eq!(
            symbols.text(count.default.as_ref().unwrap().tokens[0].text),
            Some("3")
        );
        assert_eq!(
            symbols.text(count.input_annotation.as_ref().unwrap().tokens[0].text),
            Some("num")
        );
        assert!(count.source_expression.is_none());
        assert!(signature.parameters[2].source_expression.is_some());
    }
    #[test]
    fn nested_defaults_and_variadic_are_not_split_as_arguments() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "list/items = list(1, list(2,3)), ...",
            " as /datum/result",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(signature.parameters.len(), 1);
        assert_eq!(
            signature.parameters[0].declared_type,
            Some(SymbolId::of("/list"))
        );
        assert!(signature.variadic);
        assert!(signature.return_annotation.is_some());
    }
    #[test]
    fn source_setting_is_typed_without_guessing_wire_flags() {
        let mut symbols = SymbolTable::default();
        let setting = parse_setting("set src in world", &mut symbols).unwrap();
        assert_eq!(setting.operation, SettingOperation::In);
        assert_eq!(symbols.text(setting.name), Some("src"));
        assert_eq!(symbols.text(setting.value.tokens[0].text), Some("world"));
        assert!(parse_setting("set imaginary = 1", &mut symbols).is_err());
    }
    #[test]
    fn checker_prefix_settings_preserve_native_symbolic_metadata() {
        let mut symbols = SymbolTable::default();
        let setting =
            parse_setting("set SpacemanDMM_should_be_pure = candidate", &mut symbols).unwrap();
        assert_eq!(
            symbols.text(setting.name),
            Some("SpacemanDMM_should_be_pure")
        );
        assert_eq!(setting.operation, SettingOperation::Assign);
        assert_eq!(
            symbols.text(setting.value.tokens[0].text),
            Some("candidate")
        );
        for malformed in [
            "set SpacemanDMM_x.y = 1",
            "set SpacemanDMM_x y = 1",
            "set SpacemanDMM_x =",
        ] {
            assert!(
                parse_setting(malformed, &mut symbols).is_err(),
                "{malformed}"
            );
        }
    }
    #[test]
    fn operator_adjacency_is_semantic_not_ordinary_position() {
        let mut symbols = SymbolTable::default();
        let joined = expression("seed++", &mut symbols).unwrap();
        let separated = expression("seed + +", &mut symbols).unwrap();
        assert_ne!(joined.fingerprint(), separated.fingerprint());
        assert_eq!(joined.source_text(&symbols).as_deref(), Some("seed++"));
        assert_eq!(separated.source_text(&symbols).as_deref(), Some("seed + +"));
    }
    #[test]
    fn expression_fingerprint_excludes_relative_whitespace_positions() {
        let mut symbols = SymbolTable::default();
        let compact = expression("seed+1", &mut symbols).unwrap();
        let spaced = expression("seed + 1", &mut symbols).unwrap();
        assert_eq!(compact.fingerprint(), spaced.fingerprint());
        assert_ne!(
            compact.tokens[1].relative_span,
            spaced.tokens[1].relative_span
        );
    }
    #[test]
    fn borrowed_header_views_match_owned_expression_tokens_and_local_spans() {
        fn owned_expression(text: &str, symbols: &mut SymbolTable) -> SymbolicExpression {
            let lexed = dm_syntax::lex(text);
            assert!(lexed.diagnostics.is_empty());
            SymbolicExpression {
                tokens: lexed
                    .tokens
                    .into_iter()
                    .filter(|token| {
                        !matches!(
                            token.kind,
                            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                        )
                    })
                    .map(|token| ExpressionToken {
                        kind: token.kind,
                        text: symbols.intern(&token.text).unwrap(),
                        relative_span: token.span,
                    })
                    .collect::<Vec<_>>()
                    .into(),
            }
        }
        let arguments = "  tmp/datum/item/values[ 2 + length(list(1, 2)) ][ ] = list(\"as\", \"in\", call(1, 2)) as anything | null in world.contents , resource = 'icons/Ã©.dmi' , ...";
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(arguments, "as num | null", &mut symbols).unwrap();
        assert_eq!(signature.parameters.len(), 2);
        assert!(signature.variadic);
        let first = &signature.parameters[0];
        assert_eq!(first.name, SymbolId::of("values"));
        assert_eq!(first.flags, 4);
        assert_eq!(first.declared_type, Some(SymbolId::of("/list")));
        let array = first.array.as_ref().unwrap();
        assert_eq!(array.element_type, Some(SymbolId::of("/datum/item")));
        assert_eq!(
            array.dimensions.as_ref(),
            &[
                Some(owned_expression("2 + length(list(1, 2))", &mut symbols)),
                None
            ]
        );
        assert_eq!(
            first.default,
            Some(owned_expression(
                "list(\"as\", \"in\", call(1, 2))",
                &mut symbols
            ))
        );
        assert_eq!(
            first.input_annotation,
            Some(owned_expression("anything | null", &mut symbols))
        );
        assert_eq!(
            first.source_expression,
            Some(owned_expression("world.contents", &mut symbols))
        );
        let first_end = arguments.find(" , resource").unwrap();
        assert_eq!(first.relative_span, Span::new(2, first_end));
        assert_eq!(
            signature.parameters[1].default,
            Some(owned_expression("'icons/Ã©.dmi'", &mut symbols))
        );
        assert_eq!(
            signature.return_annotation,
            Some(owned_expression("num | null", &mut symbols))
        );
    }
}

#[cfg(test)]
thread_local! { static SIGNATURE_INTERPRETATIONS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) }; }
#[cfg(test)]
pub(crate) fn signature_interpretations() -> usize {
    SIGNATURE_INTERPRETATIONS.with(std::cell::Cell::get)
}

#[cfg(test)]
mod original_setting_partition_tests {
    use super::*;
    #[test]
    fn original_setting_partition_keeps_metadata_and_real_rhs_without_relex() {
        for source in [
            "set name = \"literal = in\"",
            "set src in view(1)",
            "set invisibility = invisibility",
            "set desc = list(1,2)",
            "set SpacemanDMM_should_be_pure = arbitrary",
        ] {
            let mut old_symbols = SymbolTable::default();
            let old = parse_setting(source, &mut old_symbols).unwrap();
            let tokens = dm_syntax::lex_spans(source);
            assert!(tokens.diagnostics.is_empty());
            let view =
                HeaderView::original(source, &tokens.tokens, Span::new(0, source.len())).unwrap();
            let mut native_symbols = SymbolTable::default();
            let before = header::lexical_header_calls();
            let parsed = parse_setting_view(view, &mut native_symbols).unwrap();
            assert_eq!(
                header::lexical_header_calls(),
                before,
                "original token partition must not lex setting/name/value text again"
            );
            assert_eq!(old, parsed.setting);
            if source == "set invisibility = invisibility" {
                assert_eq!(
                    parsed.value_span.start,
                    source.rfind("invisibility").unwrap()
                );
            }
        }
    }
    #[test]
    fn compatibility_setting_errors_keep_name_validation_before_value_lexing() {
        let mut symbols = SymbolTable::default();
        assert_eq!(
            parse_setting("set unknown = \"unterminated", &mut symbols).unwrap_err(),
            "unknown procedure setting: unknown"
        );
        assert_eq!(
            parse_setting("set name = \"unterminated", &mut symbols).unwrap_err(),
            "invalid expression tokens in procedure declaration"
        );
    }
}

fn ordinary_compiler_setting_name(name:&str)->bool{matches!(name,"name"|"desc"|"category"|"src"|"invisibility"|"waitfor"|"hidden"|"background"|"instant"|"popup_menu")}
pub(crate) fn compiler_setting_name(name:&str)->bool{name.starts_with("SpacemanDMM_")||ordinary_compiler_setting_name(name)}
pub(crate) fn settings_compilable(nodes:&[dm_ir::ProcedureSettingNode],symbols:&SymbolTable)->bool{
 fn walk(nodes:&[dm_ir::ProcedureSettingNode],symbols:&SymbolTable,depth:usize)->bool{if depth>256{return false}nodes.iter().all(|node|match node{dm_ir::ProcedureSettingNode::Setting(setting)=>symbols.text(setting.name).is_some_and(compiler_setting_name),dm_ir::ProcedureSettingNode::Conditional{then_branch,else_branch,..}=>walk(then_branch,symbols,depth+1)&&walk(else_branch,symbols,depth+1),dm_ir::ProcedureSettingNode::UnsupportedContext{children,..}=>walk(children,symbols,depth+1)})}walk(nodes,symbols,0)
}

#[cfg(test)]mod demanded_formal_continuation_tests{
 use super::*;
 #[test]fn same_native_formal_parameters_move_once_into_actual_trailing_annotation(){
  for(arguments,trailing)in[("datum/value/p,x=1","as /datum/result"),("/datum/declared,...",""),("x,","")]{let args=LexedHeader::new(arguments);let tail=LexedHeader::new(trailing);let mut whole_symbols=SymbolTable::default();let whole=parse_signature_views(args.view(),tail.view(),&mut whole_symbols).unwrap();let mut symbols=SymbolTable::default();let before=SIGNATURE_INTERPRETATIONS.with(|n|n.get());let formals=parse_formal_parameters_views(args.view(),&mut symbols).unwrap();assert_eq!(SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before+1);let resumed=finish_signature_views(formals,tail.view(),&mut symbols).unwrap();assert_eq!(SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before+1,"actual formal/default parser is never run again for the suffix");assert_eq!(format!("{:?}",resumed.signature),format!("{:?}",whole.signature));assert_eq!(resumed.declarations.iter().map(|d|(d.path,d.relative_span)).collect::<Vec<_>>(),whole.declarations.iter().map(|d|(d.path,d.relative_span)).collect::<Vec<_>>());}
 }
 #[test]fn actual_formal_default_failure_precedes_any_trailing_annotation_interpretation(){let args=LexedHeader::new("value=");let mut symbols=SymbolTable::default();let before=SIGNATURE_INTERPRETATIONS.with(|n|n.get());let error=parse_formal_parameters_views(args.view(),&mut symbols).err().unwrap();assert_eq!(error.message,"missing expression");assert_eq!(error.missing_default_end,Some("value=".len()));assert_eq!(SIGNATURE_INTERPRETATIONS.with(|n|n.get()),before+1);}
}

#[cfg(test)]mod demanded_formal_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
fn frozen_complete_native_formals(arguments_view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedFormalParameters,SignatureError>{
    #[cfg(test)]
    SIGNATURE_INTERPRETATIONS.with(|n| n.set(n.get() + 1));
    let arguments = arguments_view.text();
    let mut parameters = Vec::new();
    let mut declarations = Vec::new();
    let mut variadic = false;
    let mut start = 0;
    let mut stops: Vec<_> = arguments_view
        .top_level()
        .into_iter()
        .filter(|(token, _)| *token == ",")
        .map(|(_, span)| span.start)
        .collect();
    stops.push(arguments.len());
    for stop in stops {
        let untrimmed = &arguments[start..stop];
        let leading = untrimmed.len() - untrimmed.trim_start().len();
        let text = untrimmed.trim();
        // BYOND accepts an empty signature and a final comma, but an empty
        // slot before a comma is an invalid formal, not an omitted parameter.
        if text.is_empty() && stop < arguments.len() {
            return Err(SignatureError {
                message: "bad argument definition".into(),
                source_span: Some(Span::new(start, stop)),
                after_header: true,
                    missing_default_end: None,
                    original_fatal: None,original_input_fatal:None,formal_notices:Vec::new(),formal_notices_complete:true,
            });
        }
        if text == "..." {
            variadic = true
        } else if !text.is_empty() {
            if variadic {
                return Err("procedure argument follows variadic marker".into());
            }
            if text.starts_with('/') {
                // An absolute path in a formal header declares that type; it
                // does not name a parameter (BYOND 516.1687 compile oracle).
                // More elaborate declaration effects remain explicit gaps.
                dm_ir::TypePath::parse(text).map_err(|_| {
                    "unsupported absolute declaration in procedure argument list".to_string()
                })?;
                let view = arguments_view.slice(start + leading, start + leading + text.len());
                if text.trim_matches('/').split('/').any(|part| {
                    let offset = part.as_ptr() as usize - text.as_ptr() as usize;
                    matches!(part, "var" | "proc" | "verb")
                        || !view.slice(offset, offset + part.len()).ident()
                }) {
                    return Err(
                        "unsupported absolute declaration in procedure argument list".into(),
                    );
                }
                declarations.push(HeaderTypeDeclaration {
                    path: intern(symbols, text)?,
                    relative_span: Span::new(start + leading, start + leading + text.len()),
                });
            } else {
                parameters.push(parameter(
                    arguments_view.slice(start + leading, start + leading + text.len()),
                    start + leading,
                    symbols,
                )?);
            }
        }
        start = stop + 1;
    }

 Ok(ParsedFormalParameters{parameters,variadic,declarations,formal_notices:Vec::new(),formal_notices_complete:true,original_clauses:Vec::new(),original_clauses_complete:false})
}

 #[test]fn same_native_formal_accumulator_matches_complete_metadata_and_exact_refusals(){
  for text in["","value=1+2, other","datum/receiver/value[],other=3","/datum/declared,...","x,","x,,y","x=","static/x=1 as num","x,...,later"]{
   let view=LexedHeader::new(text);let mut old_symbols=SymbolTable::default();let old=frozen_complete_native_formals(view.view(),&mut old_symbols);let mut symbols=SymbolTable::default();let current=parse_formal_parameters_views(view.view(),&mut symbols);
   match(old,current){(Ok(old),Ok(current))=>{let a=finish_signature_views(old,LexedHeader::new("").view(),&mut old_symbols).unwrap();let b=finish_signature_views(current,LexedHeader::new("").view(),&mut symbols).unwrap();assert_eq!(format!("{:?}",a.signature),format!("{:?}",b.signature),"{text}");assert_eq!(a.declarations.iter().map(|d|(d.path,d.relative_span)).collect::<Vec<_>>(),b.declarations.iter().map(|d|(d.path,d.relative_span)).collect::<Vec<_>>());},(Err(old),Err(current))=>assert_eq!((old.message,old.source_span,old.after_header,old.missing_default_end),(current.message,current.source_span,current.after_header,current.missing_default_end),"{text}"),_=>panic!("native formal completion changed success/error for {text}")}
  }
 }
 struct Feed{tokens:std::vec::IntoIter<dm_syntax::Token>,pulls:usize}
 impl dm_syntax::NativeExpressionTokenDemand for Feed{fn next_token(&mut self)->std::io::Result<Option<dm_syntax::Token>>{self.pulls+=1;let token=self.tokens.next();if let Some(token)=&token{assert_ne!(token.text,"BAD","native parser demanded future final token after genuine default failure/boundary");}Ok(token)}}
 #[test]fn actual_native_default_failure_stops_at_real_comma_before_requesting_next_formal(){
  for text in["value=, BAD(1)","value=1+, BAD(1)","value=(1+), BAD(1)"]{
   let lexical=dm_syntax::lex(text);let mut iterator=lexical.tokens.into_iter();let mut clauses=dm_syntax::ParameterClauseCursor::new(0);for token in iterator.by_ref(){clauses.push(token.kind,token.span,&token.text);if token.text=="="{break}}
   let mut source=Feed{tokens:iterator,pulls:0};let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,1<<24,&||Ok(()));let accumulator=FormalParameterAccumulator::new();let failure=match accumulator.default_using(&mut source,&mut clauses,&a).unwrap(){DemandedFormalDefault::ExpectedTerm(failure)=>failure,_=>panic!("actual required native primary term was not retained for {text}")};
   if text=="value=, BAD(1)"{assert_eq!(failure.expected.token_span(),None);assert_eq!(failure.boundary.as_ref().map(|t|t.text.as_str()),Some(","));let args=LexedHeader::new("value=");let mut symbols=SymbolTable::default();let mut metadata=FormalParameterAccumulator::new();let error=metadata.consume(args.view(),0,6,true,&mut symbols).unwrap_err();assert_eq!(error.message,"missing expression");assert_eq!(error.missing_default_end,Some(6));}else if text.contains("(1+)"){assert!(failure.boundary.is_none());let token=failure.expected.token_span().unwrap();assert_eq!(&text[token.range()],")");}else{assert_eq!(failure.boundary.as_ref().map(|t|t.text.as_str()),Some(","));assert!(failure.expected.token_span().is_none());}
   drop(failure);assert_eq!(used.load(Ordering::Acquire),0,"actual default roots/scratch release before same resource credit");
  }
 }
 #[test]fn actual_native_valid_default_moves_one_pratt_root_while_metadata_finishes_without_reparse(){
  let text="value=1+2, BAD(1)";let lexical=dm_syntax::lex(text);let mut iterator=lexical.tokens.into_iter();let mut clauses=dm_syntax::ParameterClauseCursor::new(0);for token in iterator.by_ref(){clauses.push(token.kind,token.span,&token.text);if token.text=="="{break}}
  let mut source=Feed{tokens:iterator,pulls:0};let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,1<<24,&||Ok(()));let mut accumulator=FormalParameterAccumulator::new();let(root,boundary)=match accumulator.default_using(&mut source,&mut clauses,&a).unwrap(){DemandedFormalDefault::Complete{root,boundary}=>(root,boundary),_=>panic!("genuine valid default must retain its actual root")};assert_eq!(root.parameter,0);assert_eq!(root.assignment,Span::new(5,6));assert_eq!(boundary.unwrap().text,",");let mut old=dm_syntax::parse_expression("1+2").expr.unwrap();dm_syntax::shift_expression(&mut old,6);assert_eq!(format!("{:?}",root.syntax.parsed().expr.as_ref().unwrap()),format!("{old:?}"));
  let args=LexedHeader::new("value=1+2");let mut symbols=SymbolTable::default();accumulator.consume(args.view(),0,args.view().text().len(),true,&mut symbols).unwrap();let metadata=accumulator.finish();assert_eq!(metadata.parameters.len(),1);assert!(metadata.parameters[0].default.is_some());drop(root);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]thread_local!{static PARAMETER_HEAD_INTERPRETATIONS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}

#[cfg(test)]mod retained_formal_head_tests{
 use super::*;
 #[test]fn actual_native_formal_head_is_interpreted_once_and_completed_tail_matches_whole_metadata(){
  for source in ["value=1+2","obj/item/value=list(1) as obj|null in view(7)","list/obj/value[3]=list(1,2)"," var/tmp/value = 3 "]{
   let lex=LexedHeader::new(source);let equal=lex.view().assignment_index().unwrap();let mut symbols=SymbolTable::default();let mut actual=FormalParameterAccumulator::new();let before=PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get());actual.prepare_head(lex.view().slice(0,equal),0,&mut symbols).unwrap();assert_eq!(PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get()),before+1);actual.consume(lex.view(),0,source.len(),false,&mut symbols).unwrap();assert_eq!(PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get()),before+1);let actual=finish_signature_views(actual.finish(),LexedHeader::new("").view(),&mut symbols).unwrap();
   let expected=parse_signature_declarations(source,"",&mut SymbolTable::default()).unwrap();assert_eq!(actual.signature,expected.signature,"{source}");
  }
 }
 #[test]fn actual_native_required_formal_head_refuses_before_any_default_source_request(){
  for head in ["","1","obj/1"]{let lex=LexedHeader::new(head);let mut symbols=SymbolTable::default();let mut actual=FormalParameterAccumulator::new();assert!(actual.prepare_head(lex.view(),0,&mut symbols).is_err(),"{head}");assert!(actual.prepared_head.is_none());}
 }
}

#[cfg(test)]thread_local!{static ARRAY_DIMENSION_ROWS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]mod streamed_dimension_head_tests{
 use super::*;
 #[test]fn actual_dimensioned_head_keeps_once_native_path_and_dimension_metadata_across_default_source_markers(){
  let source="var/tmp/datum/item/items[1+2][] = list() in world";let lex=LexedHeader::new(source);let equal=lex.view().assignment_index().unwrap();let opening=source.find('[').unwrap();let mut symbols=SymbolTable::default();let mut actual=FormalParameterAccumulator::new();let heads=PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get());let dimensions=ARRAY_DIMENSION_ROWS.with(|n|n.get());actual.prepare_dimension_head(lex.view().slice(0,opening),0,&mut symbols).unwrap();assert_eq!(PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get()),heads+1);assert_eq!(ARRAY_DIMENSION_ROWS.with(|n|n.get()),dimensions);actual.admit_prepared_head(lex.view().slice(0,equal),0,&mut symbols).unwrap();assert_eq!(ARRAY_DIMENSION_ROWS.with(|n|n.get()),dimensions+2);actual.admit_prepared_head(lex.view(),0,&mut symbols).unwrap();assert_eq!(ARRAY_DIMENSION_ROWS.with(|n|n.get()),dimensions+2);actual.consume(lex.view(),0,source.len(),false,&mut symbols).unwrap();assert_eq!(PARAMETER_HEAD_INTERPRETATIONS.with(|n|n.get()),heads+1);assert_eq!(ARRAY_DIMENSION_ROWS.with(|n|n.get()),dimensions+2);let result=finish_signature_views(actual.finish(),LexedHeader::new("").view(),&mut symbols).unwrap();let mut ordinary_symbols=SymbolTable::default();let ordinary=parse_signature_views(lex.view(),LexedHeader::new("").view(),&mut ordinary_symbols).unwrap();assert_eq!(result.signature.canonical_bytes(),ordinary.signature.canonical_bytes());assert_eq!(symbols.len(),ordinary_symbols.len());assert_eq!(result.signature,ordinary.signature);
 }
}

#[cfg(test)]mod original_formal_dialect_tests{
 use super::*;
 fn original(arguments:&str)->ParsedSignature{let lex=LexedHeader::new(arguments);let formals=parse_original_formal_parameters_views(lex.view(),&mut SymbolTable::default()).unwrap();finish_signature_views(formals,LexedHeader::new("").view(),&mut SymbolTable::default()).unwrap()}
 #[test]fn actual_original_absolute_formals_are_parameters_while_compiler_absolute_forms_stay_declarations(){
  for(args,name,kind)in[("/datum/a/value","value",Some(SymbolId::of("/datum/a"))),("/foo","foo",None)]{
   let actual=original(args);assert!(actual.declarations.is_empty());assert_eq!(actual.signature.parameters.len(),1);assert_eq!(actual.signature.parameters[0].name,SymbolId::of(name));assert_eq!(actual.signature.parameters[0].declared_type,kind);
   let native=parse_signature_declarations(args,"",&mut SymbolTable::default()).unwrap();assert!(native.signature.parameters.is_empty());assert_eq!(native.declarations.len(),1);
  }
 }
 #[test]fn actual_original_spaced_var_prefix_and_global_alias_match_real_original_flags_without_native_reclassification(){
  let actual=original("var / static / datum / a / x");let parameter=&actual.signature.parameters[0];assert_eq!(parameter.name,SymbolId::of("x"));assert_eq!(parameter.declared_type,Some(SymbolId::of("/datum/a")));assert_eq!(parameter.flags,1);assert_eq!(original("global/x").signature.parameters[0].flags,1);assert_eq!(parse_signature_declarations("global/x","",&mut SymbolTable::default()).unwrap().signature.parameters[0].flags,8);
 }
}

#[cfg(test)]mod original_formal_notice_producer_tests{
 use super::*;
 #[test]fn actual_original_head_and_semicolon_notices_are_emitted_once_in_consuming_order(){
  let text="var/static/datum/a/value;";let lex=LexedHeader::new(text);let mut symbols=SymbolTable::default();let mut state=FormalParameterAccumulator::new_original();
  let end=text.len()-1;state.prepare_head(lex.view().slice(0,end),0,&mut symbols).unwrap();let once=state.take_formal_notices();assert_eq!(once.iter().map(|n|(n.registration(),n.span())).collect::<Vec<_>>(),vec![((Some("var_in_proc_parameter"),OriginalFormalNoticeLevel::Hint),Span::new(0,1)),((Some("static_in_proc_parameter"),OriginalFormalNoticeLevel::Warning),Span::new(0,1))]);
  state.consume(lex.view(),0,text.len(),false,&mut symbols).unwrap();let final_rows=state.take_formal_notices();assert_eq!(final_rows.len(),1);assert_eq!(final_rows[0].registration(),(Some("semicolon_in_proc_parameter"),OriginalFormalNoticeLevel::Warning));assert_eq!(final_rows[0].span(),Span::new(end,end+1));assert_eq!(state.formals.parameters.len(),1);assert_eq!(state.formals.parameters[0].flags,1);
 }
 #[test]fn actual_prior_head_notices_survive_a_later_native_formal_failure(){
  let text="var/static/x, other=";let lex=LexedHeader::new(text);let failure=parse_original_formal_parameters_views(lex.view(),&mut SymbolTable::default()).err().expect("genuine missing RHS");assert_eq!(failure.missing_default_end,Some(text.len()));assert_eq!(failure.formal_notices.iter().map(|n|n.registration().0).collect::<Vec<_>>(),[Some("var_in_proc_parameter"),Some("static_in_proc_parameter")]);assert!(failure.formal_notices_complete);
 }
}

#[cfg(test)]mod original_formal_flag_prefix_tests{
 use super::*;
 fn one(text:&str,original:bool)->dm_ir::Parameter{let lex=LexedHeader::new(text);let mut symbols=SymbolTable::default();let formals=if original{parse_original_formal_parameters_views(lex.view(),&mut symbols)}else{parse_formal_parameters_views(lex.view(),&mut symbols)}.unwrap();formals.parameters.into_iter().next().unwrap()}
 #[test]fn actual_original_flag_prefix_matches_original_var_type_builder_without_native_flag_changes(){
  for(text,flags)in[("const/tmp/x",4|8),("final/SpacemanDMM_private/SpacemanDMM_protected/x",16|32|64),("SpacemanDMM_final/x",16),("global/x",1)]{assert_eq!(one(text,true).flags,flags,"{text}");}
  let actual=one("datum/static/global/const/tmp/x",true);assert_eq!(actual.flags,0);assert_eq!(actual.declared_type,Some(SymbolId::of("/datum/static/global/const/tmp")));
  let native=one("datum/static/global/const/tmp/x",false);assert_eq!(native.flags,1|8|2|4);assert_eq!(native.declared_type,Some(SymbolId::of("/datum")));assert_eq!(one("const/tmp/x",false).flags,2|4);
 }
}

#[cfg(test)]mod original_formal_numeric_display_controls{
 use super::*;
 #[test]fn original_required_head_integer_uses_pinned_float_token_display_not_decimal_debug(){let reason=OriginalParameterFatal{at:Span::new(0,10),following:OriginalParameterFollowing::Head(OriginalFormalHeadFollowing::Integer(i32::MAX)),prior_outer_block:false};assert_eq!(reason.message(),"got '2.14748e+009', expected one of: ')', ',', '...', '/'");let small=OriginalParameterFatal{following:OriginalParameterFollowing::Head(OriginalFormalHeadFollowing::Integer(1)),..reason};assert_eq!(small.message(),"got '1', expected one of: ')', ',', '...', '/'");}
}

#[cfg(test)]mod original_input_specifier_metadata_controls{use super::*;
 fn parameter(text:&str,original:bool)->dm_ir::Parameter{let input=LexedHeader::new(text);let mut symbols=SymbolTable::default();let formals=if original{parse_original_formal_parameters_views(input.view(),&mut symbols)}else{parse_formal_parameters_views(input.view(),&mut symbols)}.unwrap();formals.parameters.into_iter().next().unwrap()}
 #[test]fn original_optional_post_in_annotation_does_not_change_actual_pre_as_input_or_source_expression(){let leading=parameter("value as mob|obj in list(1)",true);let both=parameter("value as mob|obj in list(1) as text",true);assert_eq!(both.input_annotation,leading.input_annotation);assert_eq!(both.source_expression,leading.source_expression);assert_eq!(both.default,leading.default);let post=parameter("value in list(1) as text",true);assert!(post.input_annotation.is_none());assert_eq!(post.source_expression,parameter("value in list(1)",true).source_expression);}
 #[test]fn compiler_formal_metadata_keeps_its_existing_pre_and_post_in_annotation_partition(){let native=parameter("value as mob|obj in list(1) as text",false);let before=parameter("value as mob|obj in list(1)",false);assert_eq!(native.input_annotation,before.input_annotation);assert_ne!(native.source_expression,before.source_expression);}
}

#[cfg(test)]mod actual_formal_expression_partition_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn metadata(text:&str)->(ParsedFormalParameters,SymbolTable){
  let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut clauses=dm_syntax::ParameterClauseCursor::new(0);let lexical=dm_syntax::lex(text);let mut tokens=lexical.tokens.into_iter();
  loop{let token=tokens.next().unwrap();let assignment=token.text=="=";clauses.push(token.kind,token.span,&token.text);if assignment{break}}
  let mut pull=||Ok(tokens.next());let mut cursor=dm_syntax::ParameterExpressionDemand::new(&mut pull,&mut clauses).original();let root=dm_syntax::parse_original_expression_demanded(&mut cursor,&a).unwrap();assert!(root.parsed().diagnostics.is_empty(),"{:?}",root.parsed().diagnostics);let boundary=cursor.take_boundary();drop(cursor);drop(pull);if let Some(token)=boundary{clauses.push(token.kind,token.span,&token.text);}for token in tokens{clauses.push(token.kind,token.span,&token.text);}let parts=clauses.finish(text.len());
  let lex=LexedHeader::new(text);let mut symbols=SymbolTable::default();let mut state=FormalParameterAccumulator::new_original();state.consume_produced(lex.view(),0,text.len(),false,&mut symbols,parts).unwrap();drop(root);assert_eq!(used.load(Ordering::Acquire),0);(state.finish(),symbols)
 }
 #[test]fn actual_default_binary_in_cannot_become_a_formal_source_in_ir_metadata(){let(formals,symbols)=metadata("value=1 in choices as num");assert!(formals.original_clauses_complete);let parts=formals.original_clauses[0];assert!(parts.source.is_none());let parameter=&formals.parameters[0];assert!(parameter.source_expression.is_none());let default=parameter.default.as_ref().unwrap();assert!(default.tokens.iter().any(|token|symbols.text(token.text)==Some("in")));assert!(parameter.input_annotation.is_some());}
 #[test]fn actual_intrinsic_input_annotations_stay_inside_default_metadata_until_real_formal_as(){let text="value=input() as text in choices as obj as num";let(formals,symbols)=metadata(text);let parts=formals.original_clauses[0];assert_eq!(parts.annotation.unwrap().start,text.rfind("as num").unwrap());assert!(parts.source.is_none());assert!(parts.post_source_annotation.is_none());let parameter=&formals.parameters[0];assert!(parameter.source_expression.is_none());let default=parameter.default.as_ref().unwrap();let end=default.tokens.last().unwrap();assert_eq!(symbols.text(end.text),Some("obj"));assert!(parameter.input_annotation.is_some());}
}
