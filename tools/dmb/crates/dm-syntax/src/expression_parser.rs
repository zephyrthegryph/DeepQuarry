use super::*;

/// Parse the expression subset used by declaration defaults and simple procedure bodies.
/// Invalid or unsupported syntax returns a diagnostic instead of a guessed expression.
pub fn parse_expression(source: &str) -> ParsedExpr {
    let lexical = lex(source);
    finish_expression(lexical.tokens, lexical.diagnostics)
}
/// SAME primary parser for an original literal interpolation child. The
/// literal producer already identified/spliced this genuine child; no consumer
/// reconstructs a declaration expression. Caller reserves its scratch first.
pub(crate) fn parse_expression_with_admission(
    source: &str,
    admission: &crate::SettingAdmission<'_>,
) -> ParsedExpr {
    if admission.checkpoint().is_err() {
        return ParsedExpr {
            original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None,
            expr: None,
            diagnostics: Vec::new(),
        };
    }
    let lexical = lex(source);
    finish_expression_with_admission(lexical.tokens, lexical.diagnostics, Some(admission))
}

/// Existing primary expression parser over already-issued primary body tokens.
/// No lexer/source scan and no second expression tree is involved.
pub(crate) fn parse_expression_span_tokens(source: &str, tokens: &[SpanToken]) -> ParsedExpr {
    let owned = tokens
        .iter()
        .map(|token| Token {
            kind: token.kind,
            span: token.span,
            text: token.text(source).to_owned(),
        })
        .collect();
    finish_expression(owned, Vec::new())
}
/// Existing primary parser over the original owned-token producer. Tokens are
/// temporary parser input, not another semantic/AST owner or a source reparse.
pub(crate) fn parse_expression_tokens(tokens: &[Token]) -> ParsedExpr {
    finish_expression(tokens.to_vec(), Vec::new())
}
/// Same primary grammar, admitted native setting entry. The original owner
/// reserves parser/scratch storage BEFORE calling; this does not grant source
/// authority or establish a new grammar/stack-coverage claim.
pub(crate) fn parse_expression_span_tokens_with_admission(
    source: &str,
    tokens: &[SpanToken],
    current_offset: usize,
    admission: &crate::SettingAdmission<'_>,
) -> ParsedExpr {parse_expression_span_tokens_with_original_literals(source,tokens,current_offset,admission,None)}
pub(crate) fn parse_expression_span_tokens_with_original_literals(
 source:&str,tokens:&[SpanToken],current_offset:usize,admission:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>,
)->ParsedExpr {parse_expression_span_tokens_with_literal_origin(source,tokens,current_offset,0,admission,facts)}
/// SAME parser and original native tokens, normalized to one snippet's local
/// expression coordinates BEFORE parsing. No prior absolute AST is rebound.
pub(crate) fn parse_expression_span_tokens_with_literal_origin(source:&str,tokens:&[SpanToken],current_offset:usize,source_origin:usize,admission:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>)->ParsedExpr{let original=facts.is_some();parse_span_tokens_profile(source,tokens,current_offset,source_origin,admission,facts,original)}
fn parse_span_tokens_profile(source:&str,tokens:&[SpanToken],current_offset:usize,source_origin:usize,admission:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>,original_profile:bool)->ParsedExpr{
    if facts.as_ref().is_some_and(|view|!view.admitted_by(admission)){admission.record_operational_error(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original token facts belong to another resource owner"));return ParsedExpr{expr:None,diagnostics:Vec::new(),original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None}}
    let mut owned = Vec::new();
    for token in tokens {
        if admission.checkpoint().is_err() {
            return ParsedExpr {
                original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None,
                expr: None,
                diagnostics: Vec::new(),
            };
        }
        let Some(text) = source.get(token.span.range()) else {
            admission.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "original setting token range unavailable",
            ));
            return ParsedExpr {
                original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None,
                expr: None,
                diagnostics: Vec::new(),
            };
        };
        let Some(start) = token.span.start.checked_sub(source_origin).and_then(|n|n.checked_add(current_offset)) else {
            admission.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "current setting token offset overflow",
            ));
            return ParsedExpr {
                original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None,
                expr: None,
                diagnostics: Vec::new(),
            };
        };
        let Some(end) = token.span.end.checked_sub(source_origin).and_then(|n|n.checked_add(current_offset)) else {
            admission.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "current setting token end overflow",
            ));
            return ParsedExpr {
                original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None,
                expr: None,
                diagnostics: Vec::new(),
            };
        };
        owned.push(Token {
            kind: token.kind,
            span: Span::new(start, end),
            text: text.to_owned(),
        });
    }
    let colons=facts.as_ref().map(|view|view.raw_colons());
    finish_expression_with_literal_facts(owned,Vec::new(),Some(admission),facts.map(|view|{let(rows,origin)=view.raw_parts();(rows,origin,current_offset,source_origin)}),colons,original_profile,original_profile.then_some((source,current_offset,source_origin)))
}
fn finish_expression(tokens: Vec<Token>, diagnostics: Vec<Diagnostic>) -> ParsedExpr {
    finish_expression_with_admission(tokens, diagnostics, None)
}
fn finish_expression_with_admission(
    tokens: Vec<Token>,
    diagnostics: Vec<Diagnostic>,
    admission: Option<&crate::SettingAdmission<'_>>,
) -> ParsedExpr {finish_expression_with_literal_facts(tokens,diagnostics,admission,None,None,false,None)}
fn finish_expression_with_literal_facts<'facts>(tokens:Vec<Token>,diagnostics:Vec<Diagnostic>,admission:Option<&crate::SettingAdmission<'_>>,literal_facts:Option<(crate::OriginalLiteralRows<'facts>,usize,usize,usize)>,colon_facts:Option<(crate::OriginalColonRows<'facts>,usize)>,original_profile:bool,original_source:Option<(&'facts str,usize,usize)>)->ParsedExpr {
    let mut parser = ExprParser {
        tokens: expression_tokens(tokens),
        index: 0,
        ternary_then_depth: 0,
        original_simple_incomplete:None,original_scope_prefix:None,
        original_profile,
        input_notices:crate::original_input_notices::Builder::default(),constructor_facts:crate::original_constructor_facts::Builder::default(),input_failure:None,
        expected_term:None,expected_delimiter:None,
        demand:None,
        literal_facts,colon_facts,
        original_source,
        diagnostics,
        admission,
    };
    let expr = parser.expression(0);
    if parser.admission.is_some_and(|a| a.is_stopped()) {
        // A recoverable syntax diagnostic is not the actual operation error.
        // Discard any partial grammar recovery; the enclosing checked producer
        // must extract the SAME admission's original IO before publication.
        if let Some(expression) = expr {
            crate::setting_drop::drop_expression(expression, None);
        }
        return ParsedExpr {
            original_simple_expression:None,original_input_notices:None,original_input_failure:None,original_constructor_facts:None,
            expr: None,
            diagnostics: Vec::new(),
        };
    }
    let trailing=parser.peek().map(|token|(token.span,format!("unexpected token in expression: {}",token.text)));
    if let Some((span,message))=trailing{parser.error(span,message);}
    let original_simple_expression=if parser.diagnostics.is_empty(){expr.as_ref().and_then(|expr|original_simple_complete(expr,&parser.tokens,parser.original_profile))}else{parser.original_simple_incomplete};
    ParsedExpr {
        original_simple_expression,
        original_input_failure:parser.input_failure,original_input_notices:parser.original_profile.then(||parser.input_notices.finish()),original_constructor_facts:parser.original_profile.then(||parser.constructor_facts.finish()),
        expr,
        diagnostics: parser.diagnostics,
    }
}

/// Project the existing lossless tokens to primary expression punctuation.
/// Whole and demanded routes use the SAME normalizer and actual adjacency.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct NativeExpressionTokenOccurrence{ordinal:usize,span:Span}
impl NativeExpressionTokenOccurrence{pub(crate) fn issued(ordinal:usize,span:Span)->Self{Self{ordinal,span}}pub fn ordinal(self)->usize{self.ordinal}pub fn span(self)->Span{self.span}}
struct OriginalDemandToken{token:Token,occurrence:NativeExpressionTokenOccurrence,credit:Option<crate::SettingRootLease>}
struct NativeExpressionTokenCursor<'a>{source:&'a mut dyn NativeExpressionTokenDemand,pending:Option<OriginalDemandToken>,next_ordinal:usize,role:NativeExpressionReadRole,boundary:Option<SpanToken>}
impl NativeExpressionTokenCursor<'_>{
 fn significant(&mut self)->std::io::Result<Option<OriginalDemandToken>>{loop{let next=match self.pending.take(){Some(token)=>Some(token),None=>match self.source.read_for_role(self.role)?{NativeExpressionRead::End=>{self.boundary=None;None},NativeExpressionRead::Boundary(actual)=>{self.boundary=Some(actual);None},NativeExpressionRead::Token(token)=>{self.boundary=None;let ordinal=self.next_ordinal;self.next_ordinal=ordinal.checked_add(1).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native expression source-token ordinal overflow"))?;let span=token.span;{let occurrence=NativeExpressionTokenOccurrence{ordinal,span};let credit=self.source.take_token_credit(occurrence)?;Some(OriginalDemandToken{token,occurrence,credit})}}}};match next{Some(token)if token.token.kind==TokenKind::Comment||(!self.source.original_trivia_is_significant()&&matches!(token.token.kind,TokenKind::Whitespace|TokenKind::Newline))=>continue,other=>return Ok(other)}}}
 fn next(&mut self,a:Option<&crate::SettingAdmission<'_>>)->std::io::Result<Option<OriginalDemandToken>>{let Some(mut token)=self.significant()?else{return Ok(None)};
 // Actual final-token VALUE/kind is already the lossless lexer decision.
 // In particular ':' must not request a future token merely to reconstruct
 // punctuation which that producer has already issued.
 let typed=self.source.original_value(token.occurrence)?.is_some();
 if typed{return Ok(Some(token))}
 if self.source.requires_original_values(){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual original punctuation VALUE occurrence is unissued"))}
 if token.token.text==":"{if let Some(next)=self.significant()?{if next.token.text==":"&&token.token.span.end==next.token.span.start{
  if let Some(a)=a{
   if token.credit.is_none(){token.credit=Some(a.reserve(token.token.text.capacity())?)}
   let credit=token.credit.as_mut().unwrap();if !a.matches_lease_domain(credit)||credit.bytes()<token.token.text.capacity(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native punctuation token lacks its actual same-domain raw credit"))}
   if token.token.text.capacity()<2{let bound=8usize;let extra=bound.saturating_sub(credit.bytes());a.grow(credit,extra)?;token.token.text.try_reserve_exact(2-token.token.text.len()).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;if token.token.text.capacity()>bound{return Err(std::io::ErrorKind::OutOfMemory.into())}}
  }
  token.token.text.push(':');token.token.span.end=next.token.span.end;
 }else{self.pending=Some(next)}}}Ok(Some(token))}
}
/// Owned primary token spelling/kind/span only. A preprocessor driver retains
/// its SAME typed literal VALUE/origin ledger separately; no parse result here
/// grants Original literal meaning, source acquisition or declaration authority.
/// None must be a genuine expression delimiter/end in that driver's state,
/// never a temporary physical pause or a fabricated prefix EOF.
/// DATA-only permission while the SAME Pratt primitive consumes its clauses.
#[derive(Clone,Copy,Debug,Default,Eq,PartialEq)]pub struct NativePrimitiveClauseMode{pub as_clause:bool,pub in_clause:bool}
/// The actual consuming grammar position, not a request to replay source.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeExpressionReadRole{Follower,Term,Identifier,PathName{adjacent_to:usize}}
impl NativeExpressionReadRole{pub(crate) fn accepts_parameter_ident(self,span:Span)->bool{match self{Self::Follower=>false,Self::Term|Self::Identifier=>true,Self::PathName{adjacent_to}=>span.start==adjacent_to}}}
/// A held formal boundary is distinct from actual source end. Its token stays
/// with the formal producer; only a later consuming role may accept an Ident.
pub enum NativeExpressionRead{Token(Token),Boundary(SpanToken),End}
pub trait NativeExpressionTokenDemand{
 fn read_for_role(&mut self,_role:NativeExpressionReadRole)->std::io::Result<NativeExpressionRead>{self.next_token().map(|next|match next{Some(token)=>NativeExpressionRead::Token(token),None=>NativeExpressionRead::End})}
 /// Real Original condition queues keep actual whitespace/newline values.
 fn original_trivia_is_significant(&self)->bool{false}
 /// A genuine completed preprocessor condition drains leftover queued tokens
 /// after parsing its first expression, unlike a formal/default expression.
 fn requires_expression_end(&self)->bool{true}
fn begin_expression(&mut self)->std::io::Result<()>{Ok(())}fn next_token(&mut self)->std::io::Result<Option<Token>>;
 /// Move the actual owned spelling credit immediately after this occurrence
 /// was returned. None keeps the ordinary caller-funded fallback. This moves
 /// only resource DATA, never literal/source/compatibility authority.
 fn take_token_credit(&mut self,_occurrence:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::SettingRootLease>>{Ok(None)}
 /// Exact lexer-issued Colon/CloseColon identity. None belongs only to the ordinary compiler route.
 fn original_close_colon(&self,_occurrence:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{Ok(None)}
 /// Actual parser events loan SAME issued occurrences, never spelling guesses.
 fn original_primitive_notice(&mut self,_at:NativeExpressionTokenOccurrence,_kind:crate::OriginalInputNoticeKind)->std::io::Result<()>{Ok(())}
 /// Only a consumer owning the real expression-end/boundary may recover this
 /// branch. Default retains the ordinary parser behavior; None is not universal EOF.
 fn original_missing_member(&mut self,_separator:NativeExpressionTokenOccurrence,_following:Option<NativeExpressionTokenOccurrence>)->std::io::Result<bool>{Ok(false)}

 /// Borrow only the SAME currently produced source range for an eager typed template.
 fn original_template_source(&self,_span:Span)->std::io::Result<Option<&str>>{Ok(None)}
 fn original_value(&self,_occurrence:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{Ok(None)}fn original_literal_data(&self,_occurrence:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalLiteralRef<'_>>>{Ok(None)}fn requires_original_values(&self)->bool{false}
 fn set_original_primitive_clause_mode(&mut self,_mode:NativePrimitiveClauseMode)->std::io::Result<NativePrimitiveClauseMode>{Ok(NativePrimitiveClauseMode::default())}}
impl<F:FnMut()->std::io::Result<Option<Token>>> NativeExpressionTokenDemand for F{fn next_token(&mut self)->std::io::Result<Option<Token>>{self()}}
struct WholeExpressionTokens(std::vec::IntoIter<Token>);
impl NativeExpressionTokenDemand for WholeExpressionTokens{fn next_token(&mut self)->std::io::Result<Option<Token>>{Ok(self.0.next())}}
fn expression_tokens(tokens:Vec<Token>)->Vec<Token>{let mut source=WholeExpressionTokens(tokens.into_iter());let mut cursor=NativeExpressionTokenCursor{source:&mut source,pending:None,next_ordinal:0,role:NativeExpressionReadRole::Follower,boundary:None};let mut output=Vec::new();while let Some(token)=cursor.next(None).expect("owned whole token iterator cannot fail"){output.push(token.token)}output}
struct ExpressionDemandInput<'a>{cursor:NativeExpressionTokenCursor<'a>,exhausted:bool,stopped:bool,failure:Option<std::io::Error>,occurrences:Vec<NativeExpressionTokenOccurrence>,lease:crate::SettingRootLease}
impl ExpressionDemandInput<'_>{
 fn next(&mut self,a:&crate::SettingAdmission<'_>)->std::io::Result<Option<OriginalDemandToken>>{self.cursor.next(Some(a))}
 fn admit_token(&mut self,a:&crate::SettingAdmission<'_>,tokens:&mut Vec<Token>,incoming:&mut OriginalDemandToken)->std::io::Result<()>{
  a.checkpoint()?;
  let token=&incoming.token;
  let adopted=if let Some(credit)=incoming.credit.as_mut(){
   if !a.matches_lease_domain(credit)||credit.bytes()<token.text.capacity(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native expression token lacks its actual same-domain raw capacity credit"))}
   a.absorb(&mut self.lease,credit)?;true
  }else{false};
  // Actual demanded token geometry bounds the SAME grammar's transient AST,
  // copied token spelling, branches and error-unwind live storage. This is a
  // conservative node coordination envelope, not exact allocator/RSS evidence.
  // No unseen source/header/body bytes participate in this admission.
  let nodes=std::mem::size_of::<Expr>().checked_mul(16).and_then(|n|n.checked_add(std::mem::size_of::<Diagnostic>()*4+512)).and_then(|n|n.checked_add(token.text.capacity().checked_mul(16)?)).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"demanded expression token geometry overflow"))?;
  // The existing envelope includes the original spelling once as well as
  // native grammar copies. Adopt that one real allocation instead of charging
  // it a second time; the rest of the envelope is unchanged.
  let nodes=if adopted{nodes.checked_sub(token.text.capacity()).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?}else{nodes};
  a.grow(&mut self.lease,nodes)?;
  if tokens.len()==tokens.capacity(){let capacity=tokens.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;let bound=capacity.checked_mul(4).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;a.grow(&mut self.lease,bound.checked_mul(std::mem::size_of::<Token>()).and_then(|n|n.checked_add(128)).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?)?;a.grow(&mut self.lease,bound.checked_mul(std::mem::size_of::<NativeExpressionTokenOccurrence>()).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?)?;self.occurrences.try_reserve_exact(capacity-self.occurrences.len()).map_err(|actual|std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))?;tokens.try_reserve_exact(capacity-tokens.len()).map_err(|actual|std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))?;if self.occurrences.capacity()>bound||tokens.capacity()>bound{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"demanded expression token capacity exceeded funded geometry"))}}
  Ok(())
 }
}
/// One actual Pratt result plus the same produced token facts and storage
/// owner. No declaration/model/Original compatibility grant is issued here.
/// Field order makes roots/tokens drop before their operation credit.
/// Exact failed delimiter branch from the SAME Original native Pratt.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum NativeDelimiterExpected{GroupRightParen,ConditionalColon,EmptyCall,CallArgumentEnd,IndexRightBracket,Identifier}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct NativeDelimiterExpectation{token:Option<Span>,expected:NativeDelimiterExpected}
impl NativeDelimiterExpectation{pub fn token_span(self)->Option<Span>{self.token}pub fn expected(self)->NativeDelimiterExpected{self.expected}}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct NativeTermExpectation{token:Option<Span>}
impl NativeTermExpectation{pub fn token_span(self)->Option<Span>{self.token}}
pub struct DemandedExpression{parsed:ParsedExpr,tokens:Vec<Token>,expected_term:Option<NativeTermExpectation>,expected_delimiter:Option<NativeDelimiterExpectation>,lease:crate::SettingRootLease}
/// The native root and exact token loan needed for later source binding.
/// Parser-only success/diagnostic products have already served their consumer.
/// Field order keeps the root and tokens funded through destruction.
pub struct CompletedDemandedExpression {
    root: Expr,
    tokens: Vec<Token>,
    lease: crate::SettingRootLease,
}

impl CompletedDemandedExpression {
    pub fn expression(&self) -> &Expr { &self.root }
    pub fn tokens(&self) -> &[Token] { &self.tokens }
    #[cfg(debug_assertions)]
    pub fn retained_bytes_for_trace(&self) -> usize { self.lease.bytes() }
    pub(crate) fn into_parts(self) -> (Expr, Vec<Token>, crate::SettingRootLease) {
        (self.root, self.tokens, self.lease)
    }
}

impl DemandedExpression{
 /// Seal a root after its consumer has processed the live parser notices.
 /// This conveys no primary source authority and moves the exact AST/tokens.
 pub fn into_completed_syntax(mut self, a: &crate::SettingAdmission<'_>) -> std::io::Result<CompletedDemandedExpression> {
    if self.parsed.expr.is_none() || !self.parsed.diagnostics.is_empty()
        || self.parsed.original_input_failure.is_some()
        || self.expected_term.is_some() || self.expected_delimiter.is_some() {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "only an actual completed native expression can be sealed"));
    }
    if !a.matches_lease_domain(&self.lease) {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "completed native expression belongs to another resource owner"));
    }
    self.settle_completed_syntax(a)?;
    let Self { parsed, tokens, lease, .. } = self;
    let ParsedExpr { expr, .. } = parsed;
    Ok(CompletedDemandedExpression { root: expr.expect("checked actual completed root"), tokens, lease })
 }
 #[cfg(debug_assertions)]
 pub fn retained_bytes_for_trace(&self)->usize{self.lease.bytes()}
 /// Reconcile an unpublished completed root after the Pratt cursor and its
 /// transient allocations are gone. Tokens are kept for the SAME-source
 /// proof at formal publication; the root itself lives inline in this row.
 #[doc(hidden)]
 pub fn settle_completed_syntax(&mut self, a: &crate::SettingAdmission<'_>) -> std::io::Result<()> {
    if !self.parsed.diagnostics.is_empty() || self.parsed.original_input_failure.is_some()
        || self.expected_term.is_some() || self.expected_delimiter.is_some() {
        return Ok(());
    }
    let Some(owned) = self.parsed.expr.as_ref().and_then(crate::setting_prepare::demanded_completed_owned_bytes) else {
        return Ok(());
    };
    let overflow = || std::io::Error::from(std::io::ErrorKind::OutOfMemory);
    let rows = self.tokens.capacity().checked_mul(std::mem::size_of::<Token>()).ok_or_else(overflow)?;
    let diagnostics = self.parsed.diagnostics.capacity().checked_mul(std::mem::size_of::<Diagnostic>()).ok_or_else(overflow)?;
    let mut retained = owned.checked_add(rows).and_then(|n| n.checked_add(diagnostics)).ok_or_else(overflow)?;
    for token in &self.tokens {
        retained = retained.checked_add(token.text.capacity()).ok_or_else(overflow)?;
    }
    // Original notice/constructor payloads and literal DATA retain their
    // own leases. A compound root keeps its deferred teardown headroom.
    if let Some(unused) = self.lease.bytes().checked_sub(retained).filter(|n| *n != 0) {
        a.shrink(&mut self.lease, unused).map_err(|e| a.take_operational_error().unwrap_or(e))?;
    }
    Ok(())
 }
 pub fn expected_term(&self)->Option<NativeTermExpectation>{self.expected_term}pub fn expected_delimiter(&self)->Option<NativeDelimiterExpectation>{self.expected_delimiter}pub fn parsed(&self)->&ParsedExpr{&self.parsed}pub fn tokens(&self)->&[Token]{&self.tokens}pub fn into_parts(self)->(ParsedExpr,Vec<Token>,crate::SettingRootLease){(self.parsed,self.tokens,self.lease)}}
pub fn parse_expression_demanded(source:&mut dyn NativeExpressionTokenDemand,admission:&crate::SettingAdmission<'_>)->std::io::Result<DemandedExpression>{parse_demanded_profile(source,admission,false)}
pub fn parse_original_expression_demanded(source:&mut dyn NativeExpressionTokenDemand,admission:&crate::SettingAdmission<'_>)->std::io::Result<DemandedExpression>{parse_demanded_profile(source,admission,true)}
fn parse_demanded_profile(source:&mut dyn NativeExpressionTokenDemand,admission:&crate::SettingAdmission<'_>,original_profile:bool)->std::io::Result<DemandedExpression>{
 source.begin_expression()?;let requires_end=source.requires_expression_end();
 let lease=admission.reserve(0).map_err(|proxy|admission.take_operational_error().unwrap_or(proxy))?;
 let input=ExpressionDemandInput{cursor:NativeExpressionTokenCursor{source,pending:None,next_ordinal:0,role:NativeExpressionReadRole::Follower,boundary:None},exhausted:false,stopped:false,failure:None,occurrences:Vec::new(),lease};
 let mut parser=ExprParser{admission:Some(admission),tokens:Vec::new(),index:0,ternary_then_depth:0,original_simple_incomplete:None,original_scope_prefix:None,original_profile,input_notices:crate::original_input_notices::Builder::default(),constructor_facts:crate::original_constructor_facts::Builder::default(),input_failure:None,expected_term:None,expected_delimiter:None,diagnostics:Vec::new(),literal_facts:None,colon_facts:None,original_source:None,demand:Some(input)};
 let expr=parser.expression(0);
 // Demand-mode recovery never requests a token after the first actual native
 // syntax failure. Ordinary whole expression recovery remains unchanged.
 if requires_end&&parser.diagnostics.is_empty(){let extra=parser.peek().map(|token|(token.span,format!("unexpected token in expression: {}",token.text)));if let Some((span,message))=extra{parser.error(span,message)}}
 let input=parser.demand.take().expect("same demanded parser owner");
 if let Some(actual)=input.failure.or_else(||admission.take_operational_error()){
  if let Some(expression)=expr{crate::setting_drop::drop_expression(expression,None)}return Err(actual)
 }
 if admission.is_stopped(){if let Some(expression)=expr{crate::setting_drop::drop_expression(expression,None)}return Err(admission.checkpoint().err().unwrap_or_else(||std::io::Error::new(std::io::ErrorKind::Other,"native expression operation stopped without a current failure")))}
 let original_simple_expression=if parser.diagnostics.is_empty(){expr.as_ref().and_then(|expr|original_simple_complete(expr,&parser.tokens,parser.original_profile))}else{parser.original_simple_incomplete};
 Ok(DemandedExpression{parsed:ParsedExpr{expr,diagnostics:parser.diagnostics,original_simple_expression,original_input_failure:parser.input_failure,original_input_notices:parser.original_profile.then(||parser.input_notices.finish()),original_constructor_facts:parser.original_profile.then(||parser.constructor_facts.finish())},tokens:parser.tokens,expected_term:parser.expected_term,expected_delimiter:parser.expected_delimiter,lease:input.lease})
}

// Pratt's left fold can create a deep AST WITHOUT deep parser recursion.
// Bound its possible error-unwind destructor work against the host's explicit
// operation stack allowance before another fold. This is never syntax meaning.
fn admitted_drop_shape(root: &Expr, admission: &crate::SettingAdmission<'_>) -> bool {
    let mut pending = vec![(root, 1usize)];
    while let Some((value, depth)) = pending.pop() {
        if admission.admit_drop_depth(depth).is_err() {
            return false;
        }
        let next = depth.saturating_add(1);
        match &value.kind {
            ExprKind::Unary { value, .. }
            | ExprKind::Group(value)
            | ExprKind::TypeFilter { value, .. } => pending.push((value, next)),
            ExprKind::Binary { lhs, rhs, .. } => {
                pending.push((lhs, next));
                pending.push((rhs, next));
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                pending.push((condition, next));
                pending.push((then_value, next));
                pending.push((else_value, next));
            }
            ExprKind::Call { callee, args } => {
                pending.push((callee, next));
                pending.extend(args.iter().map(|a| (a, next)));
            }
            ExprKind::Member { object, .. }
            | ExprKind::StaticMember { object, .. }
            | ExprKind::SafeMember { object, .. } => pending.push((object, next)),
            ExprKind::ObjectInitializer { object, fields } => {
                pending.push((object, next));
                pending.extend(fields.iter().map(|(_, a)| (a, next)));
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                pending.push((object, next));
                pending.push((index, next));
            }
            ExprKind::Ident(_) | ExprKind::TypePath(_) | ExprKind::Literal(_) => (),
        }
    }
    true
}
#[derive(Clone, Copy, Eq, PartialEq)]
enum PostfixMode {
    Expression,
    ConstructorPrefab,
    ConstructorMini,
}

struct ExprParser<'op,'input> {
    admission: Option<&'op crate::SettingAdmission<'op>>,
    tokens: Vec<Token>,
    index: usize,
    ternary_then_depth: usize,
    original_simple_incomplete:Option<OriginalSimpleExpression>,
    // Actual generic-ident prefix branch, never reconstructed from an IR tree.
    original_scope_prefix:Option<usize>,
    original_profile:bool,
    input_notices:crate::original_input_notices::Builder,
    constructor_facts:crate::original_constructor_facts::Builder,
    input_failure:Option<crate::OriginalInputFailure>,
    expected_term:Option<NativeTermExpectation>,expected_delimiter:Option<NativeDelimiterExpectation>,
    diagnostics: Vec<Diagnostic>,
    demand:Option<ExpressionDemandInput<'input>>,
    literal_facts:Option<(crate::OriginalLiteralRows<'input>,usize,usize,usize)>,
    colon_facts:Option<(crate::OriginalColonRows<'input>,usize)>,
    // Exact borrowed parser input only; acquisition authority stays with its provider.
    original_source:Option<(&'input str,usize,usize)>,
}

impl ExprParser<'_,'_> {
    fn original_operational(&mut self,error:std::io::Error){if let Some(input)=&mut self.demand{if input.failure.is_none(){input.failure=Some(error)}input.stopped=true;}else if let Some(a)=self.admission{a.record_operational_error(error);}}
    fn primitive_mode(&mut self,mode:NativePrimitiveClauseMode)->Option<NativePrimitiveClauseMode>{match self.demand.as_mut(){Some(input)=>match input.cursor.source.set_original_primitive_clause_mode(mode){Ok(previous)=>Some(previous),Err(error)=>{self.original_operational(error);None}},None=>Some(NativePrimitiveClauseMode::default())}}
    fn original_delimiter_at(&mut self,expected:NativeDelimiterExpected,token:Option<Span>){if !self.original_profile||self.expected_delimiter.is_some()||self.expected_term.is_some()||self.input_failure.is_some(){return}self.expected_delimiter=Some(NativeDelimiterExpectation{token,expected});}
    fn original_delimiter(&mut self,expected:NativeDelimiterExpected){if !self.original_profile||self.expected_delimiter.is_some()||self.expected_term.is_some()||self.input_failure.is_some(){return}let token=self.peek().map(|token|token.span);self.original_delimiter_at(expected,token);}
    fn original_empty_call_slot(&mut self,start:usize){if !self.original_profile||self.expected_delimiter.is_some()||self.input_failure.is_some(){return}let Some(term)=self.expected_term else{return};let empty=match term.token_span(){None=>self.index==start,Some(span)=>self.index==start+1&&self.tokens.get(start).is_some_and(|token|token.span==span)};if empty{self.expected_delimiter=Some(NativeDelimiterExpectation{token:term.token_span(),expected:NativeDelimiterExpected::EmptyCall});}}

    fn original_implicit_new(&mut self,at:Span,has_args:bool)->Option<()>{if !self.original_profile{return Some(())}let Some(a)=self.admission else{self.original_operational(std::io::ErrorKind::InvalidInput.into());return None};match self.constructor_facts.push(at,has_args,a){Ok(())=>Some(()),Err(error)=>{self.original_operational(error);None}}}
    fn primitive_notice(&mut self,at:Span,kind:crate::OriginalInputNoticeKind)->Option<()>{let Some(a)=self.admission else{self.original_operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original primitive parser event lacks native admission"));return None};let result=(||{self.input_notices.push(at,kind,a)?;if let Some(input)=self.demand.as_mut(){let occurrence=input.occurrences.iter().find(|row|row.span()==at).copied().ok_or(std::io::ErrorKind::InvalidData)?;input.cursor.source.original_primitive_notice(occurrence,kind)?;}Ok(())})();match result{Ok(())=>Some(()),Err(error)=>{self.original_operational(error);None}}}
    fn original_missing_member(&mut self,separator:usize,following:usize)->Option<bool>{if !self.original_profile{return Some(false)}let result=(||{let Some(input)=self.demand.as_mut()else{return Ok(false)};let separator=input.occurrences.get(separator).copied().ok_or(std::io::ErrorKind::InvalidData)?;let next=input.occurrences.get(following).copied();if next.is_none()&&!input.exhausted&&input.cursor.boundary.is_none(){return Err(std::io::ErrorKind::InvalidData.into())}input.cursor.source.original_missing_member(separator,next)})();match result{Ok(value)=>Some(value),Err(error)=>{self.original_operational(error);None}}}

    // SAME consuming union/empty producer as actual formal input clauses.
    fn original_input_types(&mut self,allow_in:bool,outer:NativePrimitiveClauseMode)->Option<(Vec<String>,usize)>{
      self.primitive_mode(NativePrimitiveClauseMode{as_clause:outer.as_clause,in_clause:allow_in||outer.in_clause})?;
      let Some(a)=self.admission else{self.original_operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original input type parser lacks native admission"));return None};
      let mut cursor=match crate::ParameterInputCursor::new(a,false){Ok(cursor)=>cursor,Err(error)=>{self.original_operational(error);return None}};let mut types=Vec::new();
      loop{let flow=match self.peek(){Some(token)=>cursor.feed(token.kind,token.span,&token.text),None=>break};match flow{
        Ok(crate::ParameterInputFlow::Boundary)=>break,
        Ok(crate::ParameterInputFlow::ConsumedIdentifier)=>{let token=self.take()?;if crate::original_input_type_name(&token.text){types.push(token.text)}else{self.primitive_notice(token.span,crate::OriginalInputNoticeKind::BadInputType)?;}},
        Ok(crate::ParameterInputFlow::Consumed)=>{self.take()?;},
        Err(crate::ParameterInputFailure::Operational(error))=>{self.original_operational(error);return None},
        Err(crate::ParameterInputFailure::Syntax{at,receipt,..})=>{self.input_failure=Some(receipt);self.error(at,"invalid native Original input annotation");return None},
      }if cursor.completed_empty(){break}}
      let input=match cursor.finish(){Ok(input)=>input,Err(crate::ParameterInputFailure::Operational(error))=>{self.original_operational(error);return None},Err(crate::ParameterInputFailure::Syntax{at,receipt,..})=>{self.input_failure=Some(receipt);self.error(at,"incomplete native Original input annotation");return None}};
      let end=match &*input{crate::ParameterInputSyntax::EmptyParens{span,..}|crate::ParameterInputSyntax::Union{span,..}=>span.end};Some((types,end))
    }
    fn original_primitive_clauses(&mut self,mut lhs:Expr,closing:Span)->Option<Expr>{
      let(input,locate,start,argument_in,too_many)=match &lhs.kind{ExprKind::Call{callee,args}=>match &callee.kind{ExprKind::Ident(name)if name=="input"=>(true,false,callee.span,false,false),ExprKind::Ident(name)if name=="locate"=>(false,true,callee.span,args.first().is_some_and(|arg|matches!(&arg.kind,ExprKind::Binary{op,..}if op=="in")),args.len()>1),_=>return Some(lhs)},_=>return Some(lhs)};
      let previous=self.primitive_mode(NativePrimitiveClauseMode{as_clause:input,in_clause:true})?;
      let result=(||{
       if locate&&argument_in{self.primitive_notice(closing,crate::OriginalInputNoticeKind::LocateInArgument)?;}
       if input&&self.take_text("as").is_some(){let(types,end)=self.original_input_types(true,previous)?;lhs=Expr{span:Span::new(lhs.span.start,end),kind:ExprKind::TypeFilter{value:Box::new(lhs),types}};}
       self.primitive_mode(NativePrimitiveClauseMode{as_clause:previous.as_clause,in_clause:true})?;
       if self.take_text("in").is_some(){
        if locate&&too_many{self.primitive_notice(start,crate::OriginalInputNoticeKind::LocateTupleIn)?;}
        self.primitive_mode(NativePrimitiveClauseMode{as_clause:input,in_clause:true})?;
        let container=self.expression(0)?;lhs=Expr{span:Span::new(lhs.span.start,container.span.end),kind:ExprKind::Binary{op:"in".into(),lhs:Box::new(lhs),rhs:Box::new(container)}};
        if input{if let Some(marker)=self.take_text("as"){self.primitive_notice(marker.span,crate::OriginalInputNoticeKind::InPrecedesAs)?;let(_,end)=self.original_input_types(false,previous)?;lhs.span.end=end;}}
       }
       Some(lhs)
      })();
      if self.primitive_mode(previous).is_none(){return None}result
    }

    fn ensure(&mut self,index:usize)->bool{
        if self.demand.is_none(){return index<self.tokens.len()}
        if !self.diagnostics.is_empty(){return false}
        while self.tokens.len()<=index{
            let Some(input)=self.demand.as_mut()else{unreachable!()};
            if input.stopped||input.exhausted||self.admission.is_some_and(|a|a.is_stopped()){return false}
            let Some(a)=self.admission else{input.failure=Some(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native expression demand lacks its actual operation admission"));input.stopped=true;return false};
            let result=input.next(a);
            let mut incoming=match result{Ok(Some(token))=>token,Ok(None)=>{input.exhausted=input.cursor.boundary.is_none();return false},Err(actual)=>{input.failure=Some(actual);input.stopped=true;return false}};
            if let Err(actual)=input.admit_token(a,&mut self.tokens,&mut incoming){input.failure=Some(a.take_operational_error().unwrap_or(actual));input.stopped=true;return false}
            input.occurrences.push(incoming.occurrence);self.tokens.push(incoming.token);
        }
        true
    }
    fn peek_at_role(&mut self,index:usize,role:NativeExpressionReadRole)->Option<&Token>{
        let previous=if self.original_profile{self.demand.as_mut().map(|input|{let previous=input.cursor.role;input.cursor.role=role;previous})}else{None};
        let present=self.ensure(index);
        if let Some(previous)=previous{self.demand.as_mut().unwrap().cursor.role=previous;}
        if present{self.tokens.get(index)}else{None}
    }
    fn peek_role(&mut self,role:NativeExpressionReadRole)->Option<&Token>{self.peek_at_role(self.index,role)}
    fn take_role(&mut self,role:NativeExpressionReadRole)->Option<Token>{let token=self.peek_role(role)?.clone();self.index+=1;Some(token)}
    fn peek_at(&mut self,index:usize)->Option<&Token>{if self.ensure(index){self.tokens.get(index)}else{None}}
    pub(super) fn peek(&mut self) -> Option<&Token> {self.peek_at(self.index)}
    pub(super) fn take(&mut self) -> Option<Token> {
        let token = self.peek()?.clone();
        self.index += 1;
        Some(token)
    }
    fn take_text(&mut self, text: &str) -> Option<Token> {
        if self.peek().is_some_and(|t| t.text == text) {
            self.take()
        } else {
            None
        }
    }
    pub(super) fn error(&mut self, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic {
            span,
            kind: DiagnosticKind::Expression,
            message: message.into(),
        });
    }

    pub(super) fn expression(&mut self, min_bp: u8) -> Option<Expr> {
        let admission = self.admission;
        let _frame = match admission {
            Some(admission) => Some(admission.parser_frame().ok()?),
            None => None,
        };
        let prefix_start=self.index;
        let lhs = self.prefix()?;
        let scoped=self.original_scope_prefix==Some(prefix_start);
        self.expression_from(min_bp, lhs, PostfixMode::Expression,scoped)
    }

    // Reuse the primary postfix grammar, but terminate a constructor target
    // after its FIRST argument list. Later follows bind to the new object.
    fn expression_from(&mut self, min_bp: u8, mut lhs: Expr, mode: PostfixMode,mut scoped:bool) -> Option<Expr> {
        loop {
            if let Some(admission) = self.admission {
                if !admitted_drop_shape(&lhs, admission) {
                    crate::setting_drop::drop_expression(lhs, None);
                    return None;
                }
            }
            if self.ternary_then_depth > 0
                && self.peek().is_some_and(|token| token.text == ":")
                && !self.colon_member_before_ternary_separator(&lhs,scoped)
            {
                break;
            }
            if min_bp <= 26 {
                if mode != PostfixMode::ConstructorMini
                    && (!self.original_profile||matches!(lhs.kind,ExprKind::TypePath(_)))
                    && self.peek().is_some_and(|t| t.text == "{")
                {
                    let open = self.take().unwrap();
                    let mut fields = Vec::new();
                    while self.peek().is_some_and(|next| next.text != "}") {
                        let Some(name) = self.take_role(NativeExpressionReadRole::Identifier) else {
                            break;
                        };
                        if name.kind != TokenKind::Ident {
                            self.error(name.span, "expected object initializer field name");
                            break;
                        }
                        if self.take_text("=").is_none() {
                            self.error(name.span, "expected = after object initializer field");
                            break;
                        }
                        let Some(value) = self.expression_nested(0) else {
                            self.error(name.span, "expected object initializer field value");
                            break;
                        };
                        fields.push((name.text, value));
                        if self.take_text(",").is_none() && self.take_text(";").is_none() {
                            break;
                        }
                    }
                    let end = self.take_text("}").map_or_else(
                        || {
                            self.error(open.span, "unclosed object initializer");
                            lhs.span.end
                        },
                        |close| close.span.end,
                    );
                    lhs = Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::ObjectInitializer {
                            object: Box::new(lhs),
                            fields,
                        },
                    };
                    continue;
                }
                if self.original_profile&&mode==PostfixMode::Expression&&self.peek().is_some_and(|token|token.kind==TokenKind::Operator&&matches!(token.text.as_str(),"++"|"--")){let token=self.take()?;let op=if token.text=="++"{"post++"}else{"post--"};lhs=Expr{span:Span::new(lhs.span.start,token.span.end),kind:ExprKind::Unary{op:op.into(),value:Box::new(lhs)}};continue}
                if self.peek().is_some_and(|first|matches!(first.text.as_str(),"+"|"-")){self.ensure(self.index+1);}
                if let (Some(first), Some(second)) =
                    (self.tokens.get(self.index), self.tokens.get(self.index + 1))
                {
                    if mode == PostfixMode::Expression
                        && first.text == second.text
                        && matches!(first.text.as_str(), "+" | "-")
                        && first.span.end == second.span.start
                    {
                        let op = if first.text == "+" {
                            "post++"
                        } else {
                            "post--"
                        };
                        let end = second.span.end;
                        self.index += 2;
                        lhs = Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Unary {
                                op: op.into(),
                                value: Box::new(lhs),
                            },
                        };
                        continue;
                    }
                }
                let question_end=self.peek().filter(|token|token.text=="?").map(|token|token.span.end);
                let single_safe=self.original_profile&&mode!=PostfixMode::ConstructorPrefab&&self.peek().is_some_and(|token|matches!(token.text.as_str(),"?."|"?:")||(token.text=="?["&&mode==PostfixMode::Expression));
                if single_safe||(!self.original_profile&&question_end.is_some()
                    && self.peek_at(self.index + 1).is_some_and(|token| {
                        matches!(token.text.as_str(), "." | ":" | "[")
                            && mode != PostfixMode::ConstructorPrefab
                            && (mode == PostfixMode::Expression || token.text != "[")
                            && question_end==Some(token.span.start)
                    }))
                {
                    if !single_safe{self.take();}
                    let separator_index=self.index;
                    let separator = self.take().unwrap();
                    if matches!(separator.text.as_str(), "." | ":" | "?." | "?:") {
                        let has_name=self.peek_role(NativeExpressionReadRole::Identifier).is_some_and(|token|token.kind==TokenKind::Ident);
                        let(selector,selector_end)=if has_name{let selector=self.take_role(NativeExpressionReadRole::Identifier).unwrap();(selector.text,selector.span.end)}else if self.original_missing_member(separator_index,self.index)==Some(true){(String::new(),separator.span.end)}else{let Some(selector)=self.take()else{self.error(separator.span,"expected safe member name");break};self.error(selector.span,"expected safe member name");break};
                        lhs = Expr {
                            span: Span::new(lhs.span.start, selector_end),
                            kind: ExprKind::SafeMember {
                                object: Box::new(lhs),
                                selector,
                                via_colon: matches!(separator.text.as_str(),":"|"?:"),
                            },
                        };
                    } else {
                        let index = self.expression_nested(0);
                        let end = self.take_text("]").map_or_else(
                            || {
                                self.original_delimiter(NativeDelimiterExpected::IndexRightBracket);self.error(separator.span, "unclosed safe index");
                                lhs.span.end
                            },
                            |token| token.span.end,
                        );
                        if let Some(index) = index {
                            lhs = Expr {
                                span: Span::new(lhs.span.start, end),
                                kind: ExprKind::SafeIndex {
                                    object: Box::new(lhs),
                                    index: Box::new(index),
                                },
                            };
                        }
                    }
                    continue;
                }
                if let Some(open) = self.take_text("(") {
                    scoped=false;
                    let original_pick = self.original_profile && mode == PostfixMode::Expression
                        && matches!(&lhs.kind, ExprKind::Ident(name) if name == "pick");
                    let mut args = Vec::new();
                    if self.peek().is_some_and(|t| t.text != ")") {
                        loop {
                            if let Some(comma) = self.take_text(",") {
                                if original_pick {
                                    // Pinned separated() consumes the forbidden comma, clears its
                                    // expectations, and peeks once for the reported source token.
                                    let following = self.peek().map(|token| token.span);
                                    if let Some(at) = following {
                                        self.input_failure = Some(crate::OriginalInputFailure::new(
                                            Some(at), crate::OriginalInputExpected::EmptyPickArm,
                                        ));
                                    }
                                    self.error(following.unwrap_or(comma.span), "missing Original pick arm");
                                    return None;
                                }
                                let at = comma.span.start;
                                args.push(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                });
                                continue;
                            }
                            let argument_start=self.index;
                            let Some(mut arg) = self.expression_nested(0) else {
                                self.original_empty_call_slot(argument_start);
                                self.error(open.span, "missing call argument");
                                break;
                            };
                            if self.take_text(";").is_some() {
                                let Some(value) = self.expression_nested(0) else {
                                    self.error(arg.span, "missing weighted pick value");
                                    break;
                                };
                                arg = Expr {
                                    span: Span::new(arg.span.start, value.span.end),
                                    kind: ExprKind::Binary {
                                        op: ";".into(),
                                        lhs: Box::new(arg),
                                        rhs: Box::new(value),
                                    },
                                };
                            }
                            args.push(arg);
                            if self.take_text(",").is_none() {
                                break;
                            }
                            if self.peek().is_some_and(|next| next.text == ")") {
                                break;
                            }
                        }
                    }
                    let closing_token=self.take_text(")");
                    let closing_span=closing_token.as_ref().map(|token|token.span);
                    let end = closing_token.map_or_else(
                        || {
                            if args.is_empty(){self.original_delimiter(NativeDelimiterExpected::EmptyCall);}else{self.original_delimiter(NativeDelimiterExpected::CallArgumentEnd);}
                            self.error(open.span, "unclosed call");
                            lhs.span.end
                        },
                        |t| t.span.end,
                    );
                    lhs = Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(lhs),
                            args,
                        },
                    };
                    if mode != PostfixMode::Expression {
                        break;
                    }
                    if self.original_profile{lhs=self.original_primitive_clauses(lhs,closing_span?)?;continue;}
                    // `in` is an optional locate clause, so it belongs inside
                    // an enclosing prefix operator (`!locate(T) in L`).
                    if matches!(&lhs.kind, ExprKind::Call { callee, args }
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate")
                            && args.len() <= 1)
                        && self.take_text("in").is_some()
                    {
                        let container = self.expression(8)?;
                        lhs = Expr {
                            span: Span::new(lhs.span.start, container.span.end),
                            kind: ExprKind::Binary {
                                op: "in".into(),
                                lhs: Box::new(lhs),
                                rhs: Box::new(container),
                            },
                        };
                    }
                    continue;
                }
                if mode == PostfixMode::Expression && self.peek().is_some_and(|t| t.text == "[") {
                    scoped=false;
                    let open = self.take().unwrap();
                    let index = self.expression_nested(0);
                    let end = self.take_text("]").map_or_else(
                        || {
                            self.original_delimiter(NativeDelimiterExpected::IndexRightBracket);
                            self.error(open.span, "unclosed index");
                            lhs.span.end
                        },
                        |t| t.span.end,
                    );
                    if let Some(index) = index {
                        lhs = Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Index {
                                object: Box::new(lhs),
                                index: Box::new(index),
                            },
                        };
                    }
                    continue;
                }
                if mode != PostfixMode::ConstructorPrefab
                    && self
                        .peek()
                        .is_some_and(|t| matches!(t.text.as_str(), "." | ":" | "::"))
                    && self.original_colon_follow_allowed()
                {
                    let separator_index=self.index;
                    let separator = self.take().unwrap();
                    let is_static = separator.text == "::";
                    let has_name=self.peek_role(NativeExpressionReadRole::Identifier).is_some_and(|token|token.kind==TokenKind::Ident);
                    let (selector,selector_end)=if has_name{let selector=self.take_role(NativeExpressionReadRole::Identifier).unwrap();(selector.text,selector.span.end)}else if self.original_missing_member(separator_index,self.index)==Some(true){
                        // Old recoverable follow keeps the empty name AND leaves
                        // the unmatched token untouched. No fabricated Token/EOF.
                        (String::new(),separator.span.end)
                    }else{let Some(selector)=self.take()else{self.error(separator.span,"expected member after selector");break};self.error(selector.span,"expected member name");break};
                    lhs = Expr {
                        span: Span::new(lhs.span.start, selector_end),
                        kind: if is_static {
                            ExprKind::StaticMember {
                                object: Box::new(lhs),
                                selector,
                            }
                        } else {
                            ExprKind::Member {
                                object: Box::new(lhs),
                                selector,
                                via_colon: separator.text == ":",
                            }
                        },
                    };
                    continue;
                }
            }
            if mode != PostfixMode::Expression {
                break;
            }
            if !self.original_profile && min_bp <= 8 && self.take_text("as").is_some() {
                let mut types = Vec::new();
                let mut end = lhs.span.end;
                loop {
                    let Some(kind) = self.take() else {
                        self.error(lhs.span, "missing input type after as");
                        break;
                    };
                    if kind.kind != TokenKind::Ident {
                        self.error(kind.span, "expected input type after as");
                        break;
                    }
                    end = kind.span.end;
                    types.push(kind.text);
                    if self.take_text("|").is_none() {
                        break;
                    }
                }
                lhs = Expr {
                    span: Span::new(lhs.span.start, end),
                    kind: ExprKind::TypeFilter {
                        value: Box::new(lhs),
                        types,
                    },
                };
                continue;
            }
            if min_bp <= 3 && self.take_text("?").is_some() {
                self.ternary_then_depth += 1;
                let then_value = self.expression(0);
                self.ternary_then_depth -= 1;
                let then_value = then_value?;
                if self.take_text(":").is_none() {
                    self.original_delimiter(NativeDelimiterExpected::ConditionalColon);
                    self.error(lhs.span, "ternary expression requires :");
                    return Some(lhs);
                }
                let else_value = self.expression(2)?;
                lhs = Expr {
                    span: Span::new(lhs.span.start, else_value.span.end),
                    kind: ExprKind::Conditional {
                        condition: Box::new(lhs),
                        then_value: Box::new(then_value),
                        else_value: Box::new(else_value),
                    },
                };
                continue;
            }
            let Some((op, width, left_bp, right_bp)) = self.operator() else {
                break;
            };
            if left_bp < min_bp {
                break;
            }
            let original_operator=self.index;
            self.index += width;
            if self.peek_role(NativeExpressionReadRole::Term).is_none() && self.diagnostics.is_empty() {
                if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:None});}
                // Actual selected Pratt operator exhausted its required RHS.
                // This is not a classification of an error string/diagnostic.
                if width==1&&original_operator==1&&self.tokens.len()==2&&simple_arithmetic(&op)&&simple_term(&lhs,&self.tokens[0]){
                    self.original_simple_incomplete=Some(OriginalSimpleExpression{kind:OriginalSimpleKind::MissingArithmeticOperand,span:Span::new(lhs.span.start,self.tokens[original_operator].span.end),operator:Some(self.tokens[original_operator].span),original_profile:self.original_profile});
                }
                self.diagnostics.push(Diagnostic {
                    span: Span::new(lhs.span.end, lhs.span.end),
                    kind: DiagnosticKind::IncompleteExpression,
                    // The recognized binary operator exhausted its expression
                    // input. Use the compiler's general missing-expression
                    // wording; retain operator detail for uncertified recovery.
                    message: "missing expression".into(),
                });
                break;
            }
            let Some(rhs) = self.expression(right_bp) else {
                self.error(lhs.span, format!("missing right operand for {op}"));
                break;
            };
            lhs = Expr {
                span: Span::new(lhs.span.start, rhs.span.end),
                kind: ExprKind::Binary {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
            };
            scoped=false;
        }
        Some(lhs)
    }

    fn original_close_colon_at(&mut self,index:usize)->Option<Option<bool>>{
        let result=(||{
            if let Some(input)=self.demand.as_ref(){let occurrence=input.occurrences.get(index).copied().ok_or(std::io::ErrorKind::InvalidData)?;let value=input.cursor.source.original_close_colon(occurrence)?;if value.is_none()&&input.cursor.source.requires_original_values(){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual Original Colon/CloseColon occurrence is unissued"))}return Ok(value)}
            if !self.original_profile{return Ok(None)}
            let(rows,origin)=self.colon_facts.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"Original whole-token colon facts are unissued"))?;
            let(_,current_offset,source_origin)=self.original_source.ok_or(std::io::ErrorKind::InvalidInput)?;
            let token=self.tokens.get(index).ok_or(std::io::ErrorKind::InvalidData)?;if token.text!=":"||!matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator){return Err(std::io::ErrorKind::InvalidData.into())}
            let actual=Span::new(token.span.start.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).and_then(|n|n.checked_add(origin)).ok_or(std::io::ErrorKind::InvalidInput)?,token.span.end.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).and_then(|n|n.checked_add(origin)).ok_or(std::io::ErrorKind::InvalidInput)?);
            let at=rows.partition_point(|(span,_)|span.start<actual.start);let(_,close)=rows.get(at).filter(|(span,_)|*span==actual).ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"Original whole-token Colon/CloseColon has no SAME issued occurrence"))?;Ok(Some(close))
        })();
        match result{Ok(value)=>Some(value),Err(error)=>{self.original_operational(error);None}}
    }

    fn original_colon_follow_allowed(&mut self)->bool{
        if self.tokens.get(self.index).is_none_or(|token|token.text!=":"){return true}
        !matches!(self.original_close_colon_at(self.index),Some(Some(false))|None)
    }
    fn colon_member_before_ternary_separator(&mut self, lhs: &Expr,scoped:bool) -> bool {
        // Original's token kind already settled this before macro/output padding.
        // Never ask for a future raw token to reconstruct lexical closeness.
        match self.original_close_colon_at(self.index){Some(Some(close))=>return close&&scoped,None=>return false,Some(None)=>()}

        let Some(colon)=self.peek_at(self.index).map(|token|token.span)else{return false};
        let Some((member_span,member_kind))=self.peek_at(self.index+1).map(|token|(token.span,token.kind))else{return false};
        if lhs.span.end!=colon.start||colon.end!=member_span.start||member_kind!=TokenKind::Ident{return false}
        let mut nesting=0usize;let mut cursor=self.index+2;
        while let Some(token)=self.peek_at(cursor){
            match token.text.as_str(){"("|"["|"{"=>nesting+=1,")"|"]"|"}" if nesting==0=>break,")"|"]"|"}"=>nesting-=1,","|";" if nesting==0=>break,":" if nesting==0=>return true,_=>{}}
            cursor+=1;
        }
        false
    }

    fn expression_nested(&mut self, min_bp: u8) -> Option<Expr> {
        let previous = self.ternary_then_depth;
        self.ternary_then_depth = 0;
        let result = self.expression(min_bp);
        self.ternary_then_depth = previous;
        result
    }

    fn original_prefab_tail(&mut self,start:&str,span:Span,namespace_dot:bool)->Option<Expr>{
        let mut path=String::from(start);let mut end=span.end;let mut expects_name=true;
        while let Some(next)=self.peek_role(if expects_name{NativeExpressionReadRole::PathName{adjacent_to:end}}else{NativeExpressionReadRole::Follower}){if next.span.start!=end{break}if next.kind==TokenKind::Ident||next.text=="/"{expects_name=next.text=="/";path.push_str(&next.text);end=next.span.end;self.index+=1;}else if namespace_dot&&next.text=="."&&self.peek_at_role(self.index+1,NativeExpressionReadRole::Identifier).is_some_and(|kind|matches!(kind.text.as_str(),"proc"|"verb"|"var"))&&self.peek_at(self.index+2).is_some_and(|slash|slash.text=="/"){path.push('.');path.push_str(&self.tokens[self.index+1].text);end=self.tokens[self.index+1].span.end;self.index+=2;expects_name=false;}else{break}}
        if path==start&&start!="/"{self.error(span,format!("expected type path after {start}"));None}else{if path!="/"{path.truncate(path.trim_end_matches('/').len());}Some(Expr{span:Span::new(span.start,end),kind:ExprKind::TypePath(path)})}
    }

    fn original_value_for(&self,index:usize)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{let Some(input)=self.demand.as_ref()else{return Ok(None)};let occurrence=input.occurrences.get(index).copied().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"native expression token lacks its actual pull occurrence"))?;input.cursor.source.original_value(occurrence)}
    fn literal_from_token(&mut self,token:Token)->Option<crate::LiteralText>{
        let span=token.span;let admission=self.admission;let index=self.index.checked_sub(1)?;
        let outcome=(||{
         if let Some((rows,origin,current_offset,source_origin))=self.literal_facts{
          let relative=Span::new(span.start.checked_sub(current_offset).ok_or_else(||std::io::Error::from(std::io::ErrorKind::InvalidInput))?,span.end.checked_sub(current_offset).ok_or_else(||std::io::Error::from(std::io::ErrorKind::InvalidInput))?);
          let actual=Span::new(relative.start.checked_add(source_origin).and_then(|n|n.checked_add(origin)).ok_or_else(||std::io::Error::from(std::io::ErrorKind::InvalidInput))?,relative.end.checked_add(source_origin).and_then(|n|n.checked_add(origin)).ok_or_else(||std::io::Error::from(std::io::ErrorKind::InvalidInput))?);
          let at=rows.partition_point(|(candidate,_)|candidate.start<actual.start);
          let(_,data)=rows.get(at).filter(|(candidate,_)|*candidate==actual).ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual Original full-slice literal occurrence is unissued"))?;
          let kind=matches!((token.kind,data.value()?),(TokenKind::Number,crate::OriginalTokenValue::Int(_)|crate::OriginalTokenValue::Float(_))|(TokenKind::String,crate::OriginalTokenValue::String(_))|(TokenKind::Resource,crate::OriginalTokenValue::Resource(_)));
          if !kind||data.raw()?!=token.text{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"Original full-slice literal DATA differs from its exact primary occurrence"))}
          let a=admission.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original full-slice literal lacks its actual native operation admission"))?;
          return crate::LiteralText::from_original_view(data,span.start,a)
         }
         if let Some(input)=self.demand.as_ref(){let occurrence=input.occurrences.get(index).copied().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"native literal lacks actual pull occurrence"))?;
          if let Some(data)=input.cursor.source.original_literal_data(occurrence)?{let admission=admission.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"original literal DATA lacks SAME native expression admission"))?;if data.raw()?!=token.text{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"borrowed original literal DATA differs from actual token spelling occurrence"))}return crate::LiteralText::from_original_view(data,span.start,admission)}
         }
         match self.original_value_for(index)?{
            Some(value)=>{let admission=admission.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"original literal data lacks SAME native expression admission"))?;crate::LiteralText::from_original_value_data(token.text,span.start,value,admission)},
            None if self.demand.as_ref().is_some_and(|input|input.cursor.source.requires_original_values())=>Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual original literal VALUE occurrence is unissued")),
            None=>Ok(crate::LiteralText::at(token.text,span.start)),
        }})();
        match outcome{Ok(value)=>Some(value),Err(actual)=>{if let Some(input)=self.demand.as_mut(){if input.failure.is_none(){input.failure=Some(actual)}input.stopped=true;}else if let Some(a)=admission{a.record_operational_error(actual)}None}}
    }
    fn original_template_part_at(&self,index:usize)->std::io::Result<crate::OriginalLiteralData>{
        if let Some((rows,origin,current_offset,source_origin))=self.literal_facts{
            let token=self.tokens.get(index).ok_or(std::io::ErrorKind::InvalidData)?;
            let actual=Span::new(token.span.start.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).and_then(|n|n.checked_add(origin)).ok_or(std::io::ErrorKind::InvalidInput)?,token.span.end.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).and_then(|n|n.checked_add(origin)).ok_or(std::io::ErrorKind::InvalidInput)?);
            let at=rows.partition_point(|(candidate,_)|candidate.start<actual.start);
            let(_,data)=rows.get(at).filter(|(candidate,_)|*candidate==actual).ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual archived interpolation part lacks its issued exact occurrence"))?;
            if token.kind!=TokenKind::Interpolation||data.raw()?!=token.text{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"archived interpolation DATA differs from the exact parser input"))}return data.detach_using(self.admission.ok_or(std::io::ErrorKind::InvalidInput)?)
        }
        let input=self.demand.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual whole-token interpolation facts are not issued"))?;
        let occurrence=input.occurrences.get(index).copied().ok_or(std::io::ErrorKind::InvalidData)?;
        let data=input.cursor.source.original_literal_data(occurrence)?.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual interpolation part lacks its SAME produced literal DATA"))?;
        let token=self.tokens.get(index).ok_or(std::io::ErrorKind::InvalidData)?;
        if token.kind!=TokenKind::Interpolation||data.raw()?!=token.text{return Err(std::io::ErrorKind::InvalidData.into())}data.detach_using(self.admission.ok_or(std::io::ErrorKind::InvalidInput)?)
    }
    fn original_interpolation(&mut self,begin:Token)->Option<Expr>{
        let a=self.admission?;let result=(||{
            let data=self.original_template_part_at(self.index-1)?;
            if !matches!(data.value(),crate::OriginalTokenValue::InterpBegin(_)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual template prefix is not InterpBegin"))}
            let mut builder=crate::literal::OriginalTemplateBuilder::new(a)?;builder.push(data,begin.span,None,&[],a)?;
            let end=loop{
                a.checkpoint()?;let child_start=self.index;
                let Some(next)=self.peek()else{self.error(begin.span,"expected interpolation part or end");return Ok(None)};
                let empty=if next.kind==TokenKind::Interpolation{matches!(self.original_template_part_at(self.index)?.value(),crate::OriginalTokenValue::InterpPart(_)|crate::OriginalTokenValue::InterpEnd(_))}else{false};
                let child=if empty{None}else{
                    let Some(child)=self.expression_nested(0)else{return Ok(None)};Some(child)
                };
                let child_end=self.index;
                let Some(boundary)=self.take()else{if let Some(child)=child{crate::setting_drop::drop_expression(child,None)}self.error(begin.span,"expected interpolation part or end");return Ok(None)};
                if boundary.kind!=TokenKind::Interpolation{if let Some(child)=child{crate::setting_drop::drop_expression(child,None)}self.error(boundary.span,"expected interpolation part or end");return Ok(None)}
                let data=match self.original_template_part_at(self.index-1){Ok(data)=>data,Err(error)=>{if let Some(child)=child{crate::setting_drop::drop_expression(child,None)}return Err(error)}};
                let ended=match data.value(){crate::OriginalTokenValue::InterpPart(_)=>false,crate::OriginalTokenValue::InterpEnd(_)=>true,_=>{if let Some(child)=child{crate::setting_drop::drop_expression(child,None)}self.error(boundary.span,"expected interpolation part or end");return Ok(None)}};
                builder.push(data,boundary.span,child,&self.tokens[child_start..child_end],a)?;
                if ended{break boundary.span.end}
            };
            let span=Span::new(begin.span.start,end);
            let source=if let Some(input)=self.demand.as_ref(){input.cursor.source.original_template_source(span)?.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual typed template source range is not issued"))?}else{
                let(source,current_offset,source_origin)=self.original_source.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual archived template input borrow is not issued"))?;
                let start=span.start.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).ok_or(std::io::ErrorKind::InvalidInput)?;let end=span.end.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).ok_or(std::io::ErrorKind::InvalidInput)?;
                source.get(start..end).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"archived template exceeds its actual parser input"))?
            };
            let value=builder.finish(source,span.start,a)?;
            Ok(Some(Expr{span,kind:ExprKind::Literal(value)}))
        })();
        match result{Ok(root)=>root,Err(error)=>{self.original_operational(error);None}}
    }

    pub(super) fn prefix(&mut self) -> Option<Expr> {
        let token=match self.take_role(NativeExpressionReadRole::Term){Some(token)=>token,None=>{if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:None});}return None}};
        let span = token.span;
        match token.kind {
            TokenKind::Punctuation | TokenKind::Operator if token.text == "::" => {
                let Some(name) = self.take_role(NativeExpressionReadRole::Identifier) else {
                    self.original_delimiter_at(NativeDelimiterExpected::Identifier,None);
                    self.error(span, "expected global procedure name after ::");
                    return None;
                };
                if name.kind != TokenKind::Ident {
                    self.original_delimiter_at(NativeDelimiterExpected::Identifier,Some(name.span));
                    self.error(name.span, "expected global procedure name after ::");
                    return None;
                }
                // The scope operator is retained by PRIMARY syntax. It is not
                // a member receiver, unscoped identifier or text-side analysis.
                // The primary scope marker also represents the original bare
                // GlobalIdent term. Call dispatch remains decided by postfix ().
                Some(Expr {
                    span: Span::new(span.start, name.span.end),
                    kind: ExprKind::Unary {
                        op: "::".into(),
                        value: Box::new(Expr {
                            span: name.span,
                            kind: ExprKind::Ident(name.text),
                        }),
                    },
                })
            }
            // Pinned input_type accepts the exact empty type tuple in
            // as(()) as well as an absent type in as(). Keep this ONLY in
            // the contextual as primitive; ordinary empty groups stay invalid.
            TokenKind::Ident if token.text == "as"
                && self.peek_at(self.index).is_some_and(|t|t.text=="(")
                && self.peek_at(self.index+1).is_some_and(|t|t.text=="(")
                && self.peek_at(self.index+2).is_some_and(|t|t.text==")")
                && self.peek_at(self.index+3).is_some_and(|t|t.text==")") =>
            {
                let end=self.tokens[self.index+3].span.end;
                self.index+=4;
                Some(Expr{span:Span::new(span.start,end),kind:ExprKind::Call{
                    callee:Box::new(Expr{span,kind:ExprKind::Ident(token.text)}),args:Vec::new(),
                }})
            }
            TokenKind::Ident if token.text == "new" => {
                if self.peek().is_none() {
                    self.original_implicit_new(span,false)?;
                    return Some(Expr {
                        span,
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args: Vec::new(),
                        },
                    });
                }
                if let Some(open) = self.take_text("(") {
                    self.original_implicit_new(span,true)?;
                    let mut args = Vec::new();
                    if self.peek().is_some_and(|next| next.text != ")") {
                        loop {
                            if self.peek().is_some_and(|next| next.text == ",") {
                                let at = self.peek().unwrap().span.start;
                                args.push(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                });
                                self.take();
                                continue;
                            }
                            let Some(arg) = self.expression_nested(0) else {
                                self.error(open.span, "missing constructor argument");
                                break;
                            };
                            args.push(arg);
                            if self.take_text(",").is_none() {
                                break;
                            }
                            if self.peek().is_some_and(|next| next.text == ")") {
                                break;
                            }
                        }
                    }
                    let end = self.take_text(")").map_or_else(
                        || {
                            self.error(open.span, "unclosed constructor");
                            open.span.end
                        },
                        |close| close.span.end,
                    );
                    return Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args,
                        },
                    });
                }
                let target = match self.peek() {
                    Some(next) if next.kind == TokenKind::Ident => {
                        let target = self.take().unwrap();
                        Some((
                            Expr {
                                span: target.span,
                                kind: ExprKind::Ident(target.text),
                            },
                            PostfixMode::ConstructorMini,
                        ))
                    }
                    Some(next) if matches!(next.text.as_str(), "/" | ".") => {
                        let target = self.prefix()?;
                        let mode = if matches!(target.kind, ExprKind::TypePath(_)) {
                            PostfixMode::ConstructorPrefab
                        } else {
                            PostfixMode::ConstructorMini
                        };
                        Some((target, mode))
                    }
                    _ => None,
                };
                let Some((target, mode)) = target else {
                    self.original_implicit_new(span,false)?;
                    // A bare contextual new can precede a delimiter/operator,
                    // not only end-of-input (for example list(new, new)).
                    return Some(Expr {
                        span,
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args: Vec::new(),
                        },
                    });
                };
                let value = self.expression_from(24, target, mode,false)?;
                Some(Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })
            }
            TokenKind::Ident if token.text == "null" => Some(Expr {
                span,
                kind: ExprKind::Literal(crate::LiteralText::at(token.text, span.start)),
            }),
            TokenKind::Ident => {self.original_scope_prefix=Some(self.index-1);Some(Expr {span,kind: ExprKind::Ident(token.text)})},
            TokenKind::Interpolation => self.original_interpolation(token),
            TokenKind::Number | TokenKind::String | TokenKind::Resource => self.literal_from_token(token).map(|value|Expr {span,kind:ExprKind::Literal(value)}),
            TokenKind::Operator if self.original_profile&&token.text=="+"=>{if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:Some(span)})}self.error(span,"Original unary plus is not a term");None},
            TokenKind::Operator if self.original_profile&&matches!(token.text.as_str(),"++"|"--")=>{let value=self.expression(26)?;Some(Expr{span:Span::new(span.start,value.span.end),kind:ExprKind::Unary{op:if token.text=="++"{"pre++".into()}else{"pre--".into()},value:Box::new(value)}})},
            TokenKind::Operator if matches!(token.text.as_str(), "-" | "+" | "!" | "~" | "*" | "&") => {
                if matches!(token.text.as_str(), "-" | "+")
                    && self.peek().is_some_and(|next| {
                        next.text == token.text && next.span.start == token.span.end
                    })
                {
                    self.take();
                    if self.peek().is_none() && self.diagnostics.is_empty() {
                    if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:None});}
                        self.diagnostics.push(Diagnostic {
                            span,
                            kind: DiagnosticKind::IncompleteExpression,
                            message: format!(
                                "missing operand for prefix {}{}",
                                token.text, token.text
                            ),
                        });
                        return None;
                    }
                    let value = self.expression(26)?;
                    return Some(Expr {
                        span: Span::new(span.start, value.span.end),
                        kind: ExprKind::Unary {
                            op: if token.text == "+" {
                                "pre++".into()
                            } else {
                                "pre--".into()
                            },
                            value: Box::new(value),
                        },
                    });
                }
                if self.peek().is_none() && self.diagnostics.is_empty() {
                    if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:None});}
                    self.diagnostics.push(Diagnostic {
                        span,
                        kind: DiagnosticKind::IncompleteExpression,
                        message: format!("missing operand for unary {}", token.text),
                    });
                    return None;
                }
                let value = self.expression(26)?;
                Some(Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })
            }
            TokenKind::Punctuation if token.text == "(" => {
                if self.original_profile{if let Some(close)=self.take_text(")"){self.primitive_notice(close.span,crate::OriginalInputNoticeKind::EmptyParentheses)?;return Some(Expr{span:Span::new(span.start,close.span.end),kind:ExprKind::Literal(crate::LiteralText::at("null".into(),span.start))});}}
                let value = self.expression_nested(0)?;
                let end = self.take_text(")").map_or_else(
                    || {
                        self.original_delimiter(NativeDelimiterExpected::GroupRightParen);
                        if self.peek().is_none() && self.diagnostics.is_empty() {
                            self.diagnostics.push(Diagnostic {
                                span,
                                kind: DiagnosticKind::IncompleteExpression,
                                message: "unclosed group".into(),
                            });
                        } else {
                            self.error(span, "unclosed group");
                        }
                        value.span.end
                    },
                    |t| t.span.end,
                );
                Some(Expr {
                    span: Span::new(span.start, end),
                    kind: ExprKind::Group(Box::new(value)),
                })
            }
            TokenKind::Punctuation if token.text == "/" => self.original_prefab_tail("/",span,true),
            TokenKind::Punctuation if token.text == ":" => {
                if matches!(self.original_close_colon_at(self.index-1),Some(Some(false))|None){self.error(span,"expected term, not an open colon");None}else{self.original_prefab_tail(":",span,false)}
            },
            TokenKind::Punctuation if token.text == ".." => {
                // Original source owns `..` as one Super punctuation token.
                // The compatibility lexer may still issue two separate dots.
                if self.peek().is_none_or(|next| next.text != "(") {
                    self.error(span, "parent call requires an argument list");
                    return None;
                }
                Some(Expr { span, kind: ExprKind::Ident("..".into()) })
            }
            TokenKind::Punctuation if token.text == "." => {
                if let Some(second) = self.take_text(".") {
                    Some(Expr {
                        span: Span::new(span.start, second.span.end),
                        kind: ExprKind::Ident("..".into()),
                    })
                } else if self.peek().is_some_and(|next| next.kind==TokenKind::Ident)
                {
                    self.original_prefab_tail(".",span,false)
                } else {
                    Some(Expr {
                        span,
                        kind: ExprKind::Ident(".".into()),
                    })
                }
            }
            _ => {
                if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:Some(span)});}
                self.error(span, format!("unexpected expression token: {}", token.text));
                None
            }
        }
    }

    fn operator(&mut self) -> Option<(String, usize, u8, u8)> {
        const OPS: &[(&str, u8, u8)] = &[
            ("=", 1, 1),
            ("+=", 1, 1),
            ("-=", 1, 1),
            ("*=", 1, 1),
            ("/=", 1, 1),
            ("%=", 1, 1),
            ("|=", 1, 1),
            ("&=", 1, 1),
            ("^=", 1, 1),
            ("<<=", 1, 1),
            (">>=", 1, 1),
            ("||=", 1, 1),
            ("&&=", 1, 1),
            ("||", 3, 4),
            ("&&", 5, 6),
            // DreamMaker binds the bit operators looser than comparison and shifts looser than relational operators
            // (`a == b | c` is `(a == b) | c`, `a << b < c` is `a << (b < c)`), measured against dm.exe.
            ("|", 7, 8),
            ("^", 9, 10),
            ("&", 11, 12),
            // `in` is the loosest operator of all, below `?:`: `a in b ? c : d` is `a in (b ? c : d)` and
            // `a || b in c` is `(a || b) in c` (dm.exe 516.1687).
            ("in", 0, 1),
            ("==", 13, 14),
            ("!=", 13, 14),
            ("<>", 13, 14),
            ("~=", 13, 14),
            ("~!", 13, 14),
            ("to", 14, 15),
            ("<<", 15, 16),
            (">>", 15, 16),
            ("<=>", 17, 18),
            ("<=", 17, 18),
            (">=", 17, 18),
            ("<", 17, 18),
            (">", 17, 18),
            ("+", 19, 20),
            ("-", 19, 20),
            ("*", 21, 22),
            ("/", 21, 22),
            ("%", 21, 22),
            ("**", 25, 26),
        ];
        let (first_kind,first_start)=self.peek().map(|token|(token.kind,token.span.start))?;
        if !matches!(
            first_kind,
            TokenKind::Operator | TokenKind::Punctuation | TokenKind::Ident
        ) {
            return None;
        }
        // The pinned parser places both in right-binding Strength::Assign.
        // Original lexing already issued one indivisible punctuation token.
        // Keep native compilation unchanged and never join split/macro tokens.
        if self.original_profile {
            let token = self.peek()?;
            if matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation)
                && matches!(token.text.as_str(), ":=" | "%%=")
            {
                return Some((token.text.clone(), 1, 1, 1));
            }
        }
        let mut best: Option<(String, usize, u8, u8)> = None;
        for (op, l, r) in OPS {
            let mut width = 0;
            let mut assembled = String::new();
            while assembled.len()<op.len(){
                let Some(token)=self.peek_at(self.index+width)else{break};
                if token.span.start!=first_start+assembled.len(){break}
                assembled.push_str(&token.text);width+=1;
                if assembled==*op&&best.as_ref().is_none_or(|b|op.len()>b.0.len()){best=Some(((*op).into(),width,*l,*r));}
                if !op.starts_with(&assembled){break}
            }
        }
        // `<>` is DreamMaker's spelling of `!=`.
        if let Some(found) = best.as_mut() {
            if found.0 == "<>" {
                found.0 = "!=".into();
            }
        }
        best
    }
}

#[cfg(test)]
mod incomplete_tests {
    use super::*;
    #[test]
    fn membership_is_below_assignment_and_both_sides_of_ternary() {
        for source in ["a = b in c", "a ? b : c in d"] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            let ExprKind::Binary { op, lhs, .. } = parsed.expr.unwrap().kind else {
                panic!("{source}")
            };
            assert_eq!(op, "in");
            assert!(
                matches!(lhs.kind, ExprKind::Binary { ref op, .. } if op == "=")
                    || matches!(lhs.kind, ExprKind::Conditional { .. }),
                "{source}"
            );
        }
        let parsed = parse_expression("a in b ? c : d");
        let ExprKind::Binary { op, rhs, .. } = parsed.expr.unwrap().kind else {
            panic!()
        };
        assert_eq!(op, "in");
        assert!(matches!(rhs.kind, ExprKind::Conditional { .. }));
        let parsed = parse_expression("a in b = c");
        let ExprKind::Binary { op, rhs, .. } = parsed.expr.unwrap().kind else {
            panic!()
        };
        assert_eq!(op, "in");
        assert!(matches!(rhs.kind, ExprKind::Binary { ref op, .. } if op == "="));
    }
    #[test]
    fn prefix_pointer_dereference_parses_after_a_binary_operator() {
        // DreamMaker 516.1681 accepts `a +* 2` and `a * * 2` (fixtures/diagnostics/cases/bad_operator).
        for source in ["a +* 2", "a * * 2", "*a", "a -* 2"] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
        }
    }
    #[test]
    fn unary_eof_certificates_survive_statement_parsing_at_exact_operand_spans() {
        for (operator, message) in [
            ("!", "missing operand for unary !"),
            ("~", "missing operand for unary ~"),
            ("++", "missing operand for prefix ++"),
        ] {
            let source = format!("// shifted\n/proc/probe()\n    return {operator}\n");
            let ast = crate::parse(&source);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            let parsed = crate::parse_body_items(&ast.items[0].children);
            let diagnostic = parsed
                .diagnostics
                .iter()
                .find(|diagnostic| diagnostic.kind == DiagnosticKind::IncompleteExpression)
                .expect("statement parser must preserve typed EOF certificate");
            assert_eq!(diagnostic.message, message);
            assert_eq!(diagnostic.span.start, source.rfind(operator).unwrap());
        }
        for value in ["!1", "~1", "++value", "!@"] {
            let ast = crate::parse(&format!("/proc/probe()\n    return {value}\n"));
            let parsed = crate::parse_body_items(&ast.items[0].children);
            assert!(!parsed
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == DiagnosticKind::IncompleteExpression));
        }
    }
    #[test]
    fn certified_binary_eof_uses_common_missing_expression_wording() {
        for source in ["1 +", "(1 +", "1 *", "1 &&", "1 =="] {
            let parsed = parse_expression(source);
            let diagnostic = parsed
                .diagnostics
                .iter()
                .find(|d| d.kind == DiagnosticKind::IncompleteExpression)
                .unwrap();
            assert_eq!(diagnostic.message, "missing expression", "{source}");
        }
        let parsed = parse_expression("1 + @");
        assert!(!parsed
            .diagnostics
            .iter()
            .any(|d| d.kind == DiagnosticKind::IncompleteExpression));
    }

    #[test]
    fn only_recognized_eof_failures_are_certified() {
        for source in ["1 +", "(1 +", "(1", "!", "~", "+", "-", "++", "--"] {
            assert!(
                parse_expression(source)
                    .diagnostics
                    .iter()
                    .any(|d| d.kind == DiagnosticKind::IncompleteExpression),
                "{source}"
            );
        }
        for source in [
            "/datum/example",
            "new /datum/example",
            "1 + @",
            "(1 @",
            "list(1,)",
            "!1",
            "~1",
            "+1",
            "-1",
            "++value",
            "--value",
            "!@",
        ] {
            assert!(
                !parse_expression(source)
                    .diagnostics
                    .iter()
                    .any(|d| d.kind == DiagnosticKind::IncompleteExpression),
                "{source}"
            );
        }
    }
}

#[cfg(test)]
mod setting_admission_parser_tests {
    use super::*;
    #[test]
    fn admitted_primary_grammar_keeps_compatibility_tree_and_stops_during_real_parse() {
        let source = "call(1+2,3+4)";
        let lexical = crate::lex_spans(source);
        assert!(lexical.diagnostics.is_empty());
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let polls = std::cell::Cell::new(0);
        let stop_at = lexical.tokens.len() + 3;
        let stopped = || {
            polls.set(polls.get() + 1);
            if polls.get() == stop_at {
                Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "actual primary parser checkpoint",
                ))
            } else {
                Ok(())
            }
        };
        let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &stopped);
        let interrupted =
            parse_expression_span_tokens_with_admission(source, &lexical.tokens, 0, &admission);
        assert!(interrupted.expr.is_none());
        assert!(admission.is_stopped());
        assert_eq!(
            polls.get(),
            stop_at,
            "stop follows token conversion and original grammar entry"
        );
        let actual = admission.take_operational_error().unwrap();
        assert_eq!(actual.kind(), std::io::ErrorKind::Interrupted);
        assert_eq!(actual.to_string(), "actual primary parser checkpoint");
        let healthy = || Ok(());
        let retry = crate::SettingAdmission::new(&counter, 1024 * 1024, &healthy);
        let retried =
            parse_expression_span_tokens_with_admission(source, &lexical.tokens, 0, &retry);
        assert!(retried.diagnostics.is_empty());
        assert_eq!(retried.expr, crate::parse_expression(source).expr);
        assert!(!retry.is_stopped());
    }
}

#[cfg(test)]mod pinned_debug_grammar_gap_tests{
 use super::*;
 fn expression(text:&str)->Expr{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);parsed.expr.unwrap()}
 #[test]fn primary_spaceship_uses_original_relational_precedence_and_exact_adjacent_tokens(){
  for(text,outer)in[("a <=> b","<=>"),("a <=> b << c","<<"),("a <=> b == c","=="),("a <=> b < c","<")]{let expr=expression(text);let ExprKind::Binary{op,lhs,..}=&expr.kind else{panic!("binary")};assert_eq!(op,outer);if outer!="<=>"{assert!(matches!(&lhs.kind,ExprKind::Binary{op,..}if op=="<=>"))}}
  for text in["a < = > b","a <= > b","a < => b"]{assert!(!parse_expression(text).diagnostics.is_empty(),"nonadjacent spelling accepted: {text}")}
 }
 #[test]fn primary_empty_input_type_tuple_is_contextual_and_preserves_complete_original_span(){
  for text in["as(())","as( ( ) )","as(/*a*/ ( /*b*/ ) /*c*/) "]{let expr=expression(text);let ExprKind::Call{callee,args}=&expr.kind else{panic!("as primitive")};assert!(matches!(&callee.kind,ExprKind::Ident(name)if name=="as"));assert!(args.is_empty());assert_eq!(expr.span.start,0);assert_eq!(expr.span.end,text.trim_end().len());}
  for text in["()","f(())","as((()))"]{assert!(!parse_expression(text).diagnostics.is_empty(),"general empty/parenthesized type was admitted: {text}")}
 }
}

#[cfg(test)]mod original_reference_and_prefab_term_tests{
 use super::*;
 #[test]fn primary_original_relative_prefab_reference_and_bare_global_are_distinct_nodes(){
  for text in[".child/type",".proc/run"]{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);assert!(matches!(parsed.expr.unwrap().kind,ExprKind::TypePath(ref path)if path==text));}
  let reference=parse_expression("&value");assert!(reference.diagnostics.is_empty());assert!(matches!(reference.expr.unwrap().kind,ExprKind::Unary{op,value}if op=="&"&&matches!(value.kind,ExprKind::Ident(ref name)if name=="value")));
  let global=parse_expression("::value");assert!(global.diagnostics.is_empty());assert!(matches!(global.expr.unwrap().kind,ExprKind::Unary{op,value}if op=="::"&&matches!(value.kind,ExprKind::Ident(ref name)if name=="value")));
  assert!(matches!(parse_expression("::value()").expr.unwrap().kind,ExprKind::Call{callee,..}if matches!(callee.kind,ExprKind::Unary{ref op,..}if op=="::")));
  assert!(matches!(parse_expression(".()").expr.unwrap().kind,ExprKind::Call{callee,..}if matches!(callee.kind,ExprKind::Ident(ref name)if name==".")));
  assert!(!parse_expression("::").diagnostics.is_empty());assert!(!parse_expression("&").diagnostics.is_empty());
 }
}

/// SAME primary child lexer/parser, retaining ONLY its span/kind geometry for
/// later source diagnostics. No child reparse or owned token spelling survives.
pub(crate) fn parse_expression_with_primary_tokens(source:&str,admission:Option<&crate::SettingAdmission<'_>>)->Result<(ParsedExpr,Vec<SpanToken>),String>{
 if let Some(a)=admission{a.checkpoint().map_err(|_|"interpolation operation stopped".to_owned())?;}
 let lexical=lex(source);let mut spans=Vec::new();let count=lexical.tokens.len();
 spans.try_reserve_exact(count).map_err(|_|{if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary interpolation token geometry allocation refused"));}"primary interpolation token geometry allocation refused".to_owned()})?;
 if spans.capacity()>count.saturating_mul(4){if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary interpolation token geometry exposed excess"));}return Err("primary interpolation token geometry exposed excess".into())}
 for token in &lexical.tokens{if let Some(a)=admission{a.checkpoint().map_err(|_|"interpolation operation stopped".to_owned())?;}spans.push(SpanToken{kind:token.kind,span:token.span});}
 Ok((finish_expression_with_admission(lexical.tokens,lexical.diagnostics,admission),spans))
}

#[cfg(test)]mod original_colon_prefab_primary{
 use super::*;
 #[test]fn primary_colon_prefab_preserves_original_node_and_call_arguments_without_changing_ternary(){for text in[":child",":child/type",":proc/run"]{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);let value=parsed.expr.unwrap();assert_eq!(value.span,Span::new(0,text.len()));assert!(matches!(value.kind,ExprKind::TypePath(ref path)if path==text));}let call=parse_expression("filter(type=:child)");assert!(call.diagnostics.is_empty(),"{:?}",call.diagnostics);let ternary=parse_expression("a ? b : c");assert!(ternary.diagnostics.is_empty());assert!(matches!(ternary.expr.unwrap().kind,ExprKind::Conditional{..}));for text in[":",":(child)"]{assert!(!parse_expression(text).diagnostics.is_empty(),"invalid colon prefab {text}");}}
}

/// Source-neutral private grammar provenance. A caller cannot construct this
/// from diagnostics, an empty parse, a source hash or a semantic-model option.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) struct OriginalSimpleExpression{kind:OriginalSimpleKind,span:Span,operator:Option<Span>,original_profile:bool}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum OriginalSimpleKind{Complete,OrdinaryCallStatement,SimpleAssignmentStatement,PlainAssignment,PostIncrementStatement,PostDecrementStatement,CrashStatement,MissingArithmeticOperand}
impl OriginalSimpleExpression{
 pub(crate) fn kind(self)->OriginalSimpleKind{self.kind}
 pub(crate) fn span(self)->Span{self.span}
 pub(crate) fn operator(self)->Option<Span>{self.operator}
 pub(crate) fn is_original(self)->bool{self.original_profile}
}
fn simple_arithmetic(op:&str)->bool{matches!(op,"+"|"-"|"*"|"/"|"%")}
pub(crate) fn original_ascii_identifier(name:&str)->bool{let mut bytes=name.bytes();bytes.next().is_some_and(|first|first==b'_'||first.is_ascii_alphabetic())&&bytes.all(|byte|byte==b'_'||byte.is_ascii_alphanumeric())}
pub(crate) fn original_decimal(text:&str)->bool{!text.is_empty()&&text.bytes().all(|byte|byte.is_ascii_digit())}
fn simple_term(expr:&Expr,token:&Token)->bool{expr.span==token.span&&match(&expr.kind,token.kind){(ExprKind::Ident(name),TokenKind::Ident)=>name==&token.text&&original_ascii_identifier(name),(ExprKind::Literal(text),TokenKind::Number)=>text.as_str()==token.text.as_str()&&original_decimal(text.as_str()),(ExprKind::Literal(text),TokenKind::Ident)=>text.as_str()=="null"&&token.text=="null",_=>false}}
fn original_zero_call(expr: &Expr, tokens: &[Token], original_profile: bool) -> bool {
    let [head, open, close] = tokens else { return false };
    let ExprKind::Call { callee, args } = &expr.kind else { return false };
    if !args.is_empty() || open.text != "(" || close.text != ")" {
        return false;
    }
    // Original's Super is one punctuation occurrence. Compatibility can
    // produce the same AST from two separate dots.
    let super_token = original_profile
        && head.kind == TokenKind::Punctuation
        && head.text == ".."
        && callee.span == head.span
        && matches!(&callee.kind, ExprKind::Ident(name) if name == "..");
    (head.kind == TokenKind::Ident && matches!(&callee.kind, ExprKind::Ident(_)) && simple_term(callee, head))
        || super_token
}

pub(crate) fn original_ordinary_call_name(name:&str)->bool{
    original_ascii_identifier(name)
        &&!matches!(name,"CRASH"|"as"|"call"|"call_ext"|"catch"|"do"|"else"|"for"|"if"|"input"|"list"|"locate"|"new"|"newlist"|"pick"|"return"|"set"|"spawn"|"switch"|"throw"|"try"|"var"|"while")
}

fn original_positional_statement_call(expr:&Expr,tokens:&[Token])->bool{
    let ExprKind::Call{callee,args}=&expr.kind else{return false};
    let ExprKind::Ident(name)=&callee.kind else{return false};
    // Keep this additional receipt check bounded, with no copied token/AST
    // storage. The parser still accepts larger calls in its other roles.
    if !(1..=16).contains(&args.len())||!original_ordinary_call_name(name){return false}
    let [head,open,tail @ ..,close]=tokens else{return false};
    if !simple_term(callee,head)||open.kind!=TokenKind::Punctuation||close.kind!=TokenKind::Punctuation||open.text!="("||close.text!=")"||expr.span!=Span::new(head.span.start,close.span.end)||tail.len()!=args.len()*2-1{return false}
    args.iter().enumerate().all(|(index,argument)|{
        simple_term(argument,&tail[index*2])
            &&(index==0||(tail[index*2-1].kind==TokenKind::Punctuation&&tail[index*2-1].text==","))
    })
}

fn original_assignment_receiver(expr: &Expr, tokens: &[Token]) -> bool {
    match tokens {
        [name] => matches!(&expr.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
            && simple_term(expr, name),
        [receiver, dot, member] => {
            matches!(&expr.kind, ExprKind::Member { object, selector, via_colon: false }
                if matches!(&object.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
                    && simple_term(object, receiver)
                    && matches!(dot.kind, TokenKind::Punctuation | TokenKind::Operator)
                    && dot.text == "."
                    && member.kind == TokenKind::Ident
                    && selector == &member.text
                    && original_ascii_identifier(selector)
                    && expr.span == Span::new(receiver.span.start, member.span.end))
        }
        _ => false,
    }
}

fn original_assignment_target(expr: &Expr, tokens: &[Token], original_profile: bool, plain_write: bool) -> bool {
    if original_assignment_receiver(expr, tokens) {
        return true;
    }
    let ExprKind::Index { object, index } = &expr.kind else { return false; };
    if original_profile && plain_write && original_plain_index(expr, object, index, tokens, 32) {
        return true;
    }
    let [receiver @ .., open, key, close] = tokens else { return false; };
    let Some(first) = receiver.first() else { return false; };
    original_assignment_receiver(object, receiver)
        && open.kind == TokenKind::Punctuation && open.text == "["
        && close.kind == TokenKind::Punctuation && close.text == "]"
        && expr.span == Span::new(first.span.start, close.span.end)
        && (simple_term(index, key) || original_simple_string_index(expr, tokens, original_profile))
}

// These statement-only cases have a witnessed plain index RHS. Keep the
// lhs roster to an ordinary arithmetic key or two levels of ordinary indices.
fn original_index_write_target(expr: &Expr, tokens: &[Token], augmented: bool) -> bool {
    let ExprKind::Index { object, index } = &expr.kind else { return false; };
    if augmented && original_plain_index(expr, object, index, tokens, 32) {
        return true;
    }
    let receiver_end = tokens.partition_point(|token| token.span.end <= object.span.end);
    let (receiver, tail) = tokens.split_at(receiver_end);
    let (Some(first), [open, key @ .., close]) = (receiver.first(), tail) else { return false; };
    if open.kind != TokenKind::Punctuation || open.text != "["
        || close.kind != TokenKind::Punctuation || close.text != "]"
        || expr.span != Span::new(first.span.start, close.span.end)
    {
        return false;
    }
    if augmented {
        return original_assignment_receiver(object, receiver)
            && matches!(&index.kind, ExprKind::Binary { op, .. }
                if matches!(op.as_str(), "+" | "-" | "*" | "/" | "%"))
            && original_conditional_child(index, key, false, 32);
    }
    let plain_index = |expr: &Expr, tokens: &[Token]| match &expr.kind {
        ExprKind::Index { object, index } => original_plain_index(expr, object, index, tokens, 32),
        _ => false,
    };
    plain_index(object, receiver) && plain_index(index, key)
}

fn original_simple_assignment(expr: &Expr, tokens: &[Token], original_profile: bool) -> bool {
    let ExprKind::Binary { op, lhs, rhs } = &expr.kind else { return false; };
    let target_end = tokens.partition_point(|token| token.span.end <= lhs.span.end);
    let (target, tail) = tokens.split_at(target_end);
    let [assignment, value @ ..] = tail else { return false; };
    let Some(first) = target.first() else { return false; };
    let plain = target.len() == 1;
    let indexed_write = original_profile && matches!(op.as_str(), "=" | "+=")
        && matches!(&rhs.kind, ExprKind::Index { object, index }
            if original_plain_index(rhs, object, index, value, 32))
        && original_index_write_target(lhs, target, op == "+=");
    let return_slot = original_profile
        && matches!(target, [dot] if dot.kind == TokenKind::Punctuation
            && dot.text == "." && dot.span == lhs.span)
        && matches!(&lhs.kind, ExprKind::Ident(name) if name == ".");
    if !(matches!(op.as_str(), "=" | "+=" | "-=" | "*=" | "/=")
        || (plain && matches!(op.as_str(), "%=" | "|=" | "&=" | "^=" | "<<=" | ">>=")))
        || !matches!(assignment.kind, TokenKind::Punctuation | TokenKind::Operator)
        || assignment.text.as_str() != op.as_str()
        || (!return_slot && !indexed_write && !original_assignment_target(lhs, target, original_profile, op == "="))
        || expr.span != Span::new(first.span.start, rhs.span.end)
    {
        return false;
    }
    if return_slot {
        if op == "+=" {
            return original_conditional_child(rhs, value, true, 32);
        }
        return op == "=" && (original_conditional_child(rhs, value, true, 32)
            || (matches!(&rhs.kind, ExprKind::Call { callee, args }
                if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "list"))
                && original_zero_call(rhs, value, true))
            || original_return_slot_mini_constructor(rhs, value));
    }
    if indexed_write || (original_profile && original_plain_assignment(expr, tokens)) {
        return true;
    }
    if original_profile && plain && matches!(op.as_str(), "+=" | "-=")
        && matches!(&lhs.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
    {
        return original_conditional_child(rhs, value, true, 32);
    }
    if original_profile && op == "=" && matches!(&lhs.kind, ExprKind::Index { .. })
        && matches!(&rhs.kind, ExprKind::Index { .. })
        && original_conditional_child(rhs, value, false, 32)
    {
        return true;
    }
    match value {
        [only] => simple_term(rhs, only),
        [receiver, dot, member] => {
            matches!(&rhs.kind, ExprKind::Member { object, selector, via_colon: false }
                if receiver.kind == TokenKind::Ident
                    && simple_term(object, receiver)
                    && dot.text == "."
                    && member.kind == TokenKind::Ident
                    && selector == &member.text
                    && original_ascii_identifier(selector)
                    && rhs.span == Span::new(receiver.span.start, member.span.end))
        }
        _ => false,
    }
}

/// Pinned NewMiniExpr with an ordinary receiver.type and positional args.
fn original_return_slot_mini_constructor(expr: &Expr, tokens: &[Token]) -> bool {
    let [keyword, constructor @ ..] = tokens else { return false };
    let ExprKind::Unary { op, value } = &expr.kind else { return false };
    let ExprKind::Call { callee, .. } = &value.kind else { return false };
    let ExprKind::Member { object, selector, via_colon: false } = &callee.kind else { return false };
    keyword.kind == TokenKind::Ident && keyword.text == "new" && op == "new"
        && expr.span == Span::new(keyword.span.start, value.span.end)
        && selector == "type"
        && matches!(&object.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
        && original_conditional_child(value, constructor, false, 32)
}

fn original_simple_string_index(expr:&Expr,tokens:&[Token],original_profile:bool)->bool{
    let [receiver,open,key,close]=tokens else{return false};
    let ExprKind::Index{object,index}=&expr.kind else{return false};
    if !matches!(&object.kind,ExprKind::Ident(name) if original_ascii_identifier(name))
        || !simple_term(object,receiver)
        || open.kind!=TokenKind::Punctuation || open.text!="["
        || close.kind!=TokenKind::Punctuation || close.text!="]"
        || key.kind!=TokenKind::String || index.span!=key.span
        || expr.span!=Span::new(receiver.span.start,close.span.end)
    {return false}
    let ExprKind::Literal(literal)=&index.kind else{return false};
    let Some(key)=key.text.strip_prefix('"').and_then(|key|key.strip_suffix('"')) else{return false};
    if !original_ascii_identifier(key){return false}
    // The demanded Original parser must supply the actual typed String.
    // The compatibility parser admits only the same unescaped lexical shape.
    match literal.original_value(){
        Some(crate::OriginalTokenValue::String(actual))=>actual==key,
        None=>!original_profile,
        _=>false,
    }
}

// These special returns share a parser AST with many unsupported call forms.
// Check every consumed delimiter and child, and keep the nested topology closed.
fn original_return_list(expr: &Expr, tokens: &[Token]) -> bool {
    fn punct(token: &Token, text: &str) -> bool {
        matches!(token.kind, TokenKind::Punctuation | TokenKind::Operator) && token.text == text
    }

    fn call<'a>(expr: &'a Expr, tokens: &[Token], name: &str) -> Option<&'a [Expr]> {
        let ExprKind::Call { callee, args } = &expr.kind else { return None };
        let [head, open, rest @ .., close] = tokens else { return None };
        if head.kind != TokenKind::Ident || head.text != name || !simple_term(callee, head)
            || !punct(open, "(") || !punct(close, ")")
            || expr.span != Span::new(head.span.start, close.span.end)
        {
            return None;
        }
        let mut remaining = rest;
        for (index, arg) in args.iter().enumerate() {
            if index != 0 {
                let (comma, after) = remaining.split_first()?;
                if !punct(comma, ",") { return None; }
                remaining = after;
            }
            let (actual, after) = remaining.split_at(remaining.partition_point(|token| token.span.end <= arg.span.end));
            if actual.first()?.span.start != arg.span.start || actual.last()?.span.end != arg.span.end {
                return None;
            }
            remaining = after;
        }
        remaining.is_empty().then_some(args)
    }

    fn within<'a>(tokens: &'a [Token], expr: &Expr) -> &'a [Token] {
        let start = tokens.partition_point(|token| token.span.end <= expr.span.start);
        let end = tokens.partition_point(|token| token.span.start < expr.span.end);
        &tokens[start..end]
    }

    fn nameof(expr: &Expr, tokens: &[Token], qualified: bool) -> bool {
        let tokens = within(tokens, expr);
        let Some([arg]) = call(expr, tokens, "nameof") else { return false };
        let actual = within(tokens, arg);
        if !qualified {
            return matches!(actual, [only]
                if matches!(&arg.kind, ExprKind::Ident(name) if original_ascii_identifier(name))
                && simple_term(arg, only));
        }
        let ExprKind::StaticMember { object, selector } = &arg.kind else { return false };
        let ExprKind::TypePath(path) = &object.kind else { return false };
        let [segments @ .., separator, member] = actual else { return false };
        let Some(path) = path.strip_prefix('/') else { return false };
        if segments.is_empty() || segments.len() % 2 != 0 || !punct(separator, "::")
            || member.kind != TokenKind::Ident || &member.text != selector || !original_ascii_identifier(selector)
            || object.span != Span::new(segments[0].span.start, segments[segments.len() - 1].span.end)
        {
            return false;
        }
        let mut parts = path.split('/');
        segments.chunks_exact(2).all(|pair| {
            let name = &pair[1];
            punct(&pair[0], "/") && name.kind == TokenKind::Ident
                && original_ascii_identifier(&name.text) && parts.next() == Some(name.text.as_str())
        }) && parts.next().is_none()
    }

    if tokens.len() > 64 { return false; }
    let Some(args) = call(expr, tokens, "list") else { return false };
    if (2..=16).contains(&args.len()) && args.iter().all(|arg| {
        matches!(within(tokens, arg), [only] if simple_term(arg, only))
    }) {
        return true;
    }
    let [drawn] = args else { return false };
    let Some([value, relation]) = call(drawn, within(tokens, drawn), "drawn_from") else { return false };
    let Some([link, member]) = call(relation, within(tokens, relation), "rel") else { return false };
    nameof(value, tokens, false) && nameof(link, tokens, false) && nameof(member, tokens, true)
}

// Pinned 0290 BINARY_OPS order, weak to strong, for this closed subset.
fn original_binary_binding(op: &str) -> Option<u8> {
    Some(match op {
        "||" => 1,
        "&&" => 2,
        "|" => 3,
        "^" => 4,
        "&" => 5,
        "==" | "!=" => 6,
        "<<" | ">>" => 7,
        "<" | "<=" | ">" | ">=" => 8,
        "+" | "-" => 9,
        "*" | "/" | "%" => 10,
        _ => return None,
    })
}

/// Check the exact token runs already consumed by the Original Pratt parser.
/// This cohort has no dynamic follows, keyed arguments, or bare ternary
/// chains. A group, argument, or typed interpolation starts a new expression.
// The entire membership production permits a name or one ordinary dot field
// on the left and one name on the right. The parser already consumed In at its
// pinned lowest precedence. Ranges, boolean/conditional children, split
// spellings and trailing tokens have no witness here.
fn original_plain_membership(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Binary { op, lhs, rhs } = &expr.kind else { return false; };
    let at = tokens.partition_point(|token| token.span.end <= lhs.span.end);
    let (left, tail) = tokens.split_at(at);
    let [operator, right] = tail else { return false; };
    let Some(first) = left.first() else { return false; };
    let term = |value: &Expr, token: &Token| {
        matches!(&value.kind, ExprKind::Ident(name)
            if name != "in" && (name == "list" || original_ordinary_call_name(name)))
            && simple_term(value, token)
    };
    let receiver = match left {
        [only] => term(lhs, only),
        [_, _, _] => matches!(&lhs.kind, ExprKind::Member { via_colon: false, .. })
            && original_assignment_receiver(lhs, left),
        _ => false,
    };
    op == "in" && operator.kind == TokenKind::Ident && operator.text == "in"
        && expr.span == Span::new(first.span.start, right.span.end)
        && receiver && term(rhs, right)
}

fn original_conditional_child(expr: &Expr, tokens: &[Token], conditional: bool, depth: usize) -> bool {
    original_composed_expression(expr, tokens, conditional, depth, false)
}

fn original_keyword_statement_call(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Call { callee, args } = &expr.kind else { return false };
    let mut receiver = callee.as_ref();
    while let ExprKind::Member { object, selector, via_colon: false } = &receiver.kind {
        if !original_ordinary_call_name(selector) { return false; }
        receiver = object;
    }
    matches!(&receiver.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
        && args.iter().any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="))
        && original_composed_expression(expr, tokens, false, 32, true)
}

fn original_plain_index(
    expr: &Expr, object: &Expr, index: &Expr, tokens: &[Token], depth: usize,
) -> bool {
    // Check the tree's exact consumed bracket range. Only a plain name
    // or a single plain dot field can be indexed or serve as its key;
    // simple literals also work as keys through the existing term witness.
    let receiver_end = tokens.partition_point(|token| token.span.end <= object.span.end);
    let (receiver, tail) = tokens.split_at(receiver_end);
    let [open, key @ .., close] = tail else { return false };
    let Some(first) = receiver.first() else { return false };
    let bracket = |token: &Token, spelling| {
        matches!(token.kind, TokenKind::Punctuation | TokenKind::Operator) && token.text == spelling
    };
    let plain_receiver = original_assignment_receiver(object, receiver)
        // The pinned parser emits Ident for these primitives without an
        // argument list. Here the exact next token is the opening bracket.
        || matches!((&object.kind, receiver), (ExprKind::Ident(name), [only])
            if matches!(name.as_str(), "input" | "list") && simple_term(object, only));
    plain_receiver
        && bracket(open, "[") && bracket(close, "]")
        && expr.span == Span::new(first.span.start, close.span.end)
        && (original_assignment_receiver(index, key)
            || ((matches!(&index.kind, ExprKind::Ident(_) | ExprKind::Literal(_))
                || matches!(&index.kind, ExprKind::Member { object, via_colon: false, .. }
                    if matches!(&object.kind, ExprKind::Ident(name) if matches!(name.as_str(), "input" | "list"))))
                && original_conditional_child(index, key, false, depth)))
}

fn original_nested_string_index(expr: &Expr) -> bool {
    let mut current = expr;
    let mut layers = 0;
    while let ExprKind::Index { object, index } = &current.kind {
        layers += 1;
        if layers > 3 { return false; }
        let ExprKind::Literal(literal) = &index.kind else { return false; };
        if !matches!(literal.original_value(), Some(crate::OriginalTokenValue::String(_))) {
            let Some(parts) = literal.original_prepared_body_parts(index.span) else { return false; };
            let [child] = parts.expressions.as_slice() else { return false; };
            let ExprKind::Ident(name) = &child.kind else { return false; };
            if parts.fragments.len() != 2 || !original_ordinary_call_name(name)
                || literal.as_str().strip_prefix("\"[").and_then(|raw| raw.strip_suffix("]\"")) != Some(name.as_str())
            {
                return false;
            }
        }
        current = object;
    }
    layers >= 2 && matches!(&current.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
}

fn original_composed_expression(
    expr: &Expr, tokens: &[Token], conditional: bool, depth: usize, keyword_call: bool,
) -> bool {
    let Some(depth) = depth.checked_sub(1) else { return false };
    let (Some(first), Some(last)) = (tokens.first(), tokens.last()) else { return false };
    if expr.span != Span::new(first.span.start, last.span.end) { return false; }

    fn punctuation(token: &Token, spelling: &str) -> bool {
        matches!(token.kind, TokenKind::Punctuation | TokenKind::Operator)
            && token.text == spelling
    }
    fn child_prefix<'a>(child: &Expr, tokens: &'a [Token]) -> (&'a [Token], &'a [Token]) {
        tokens.split_at(tokens.partition_point(|token| token.span.end <= child.span.end))
    }

    match &expr.kind {
        // Pinned list/input without an argument list are bare identifiers.
        // Their call productions still have their own syntax.
        ExprKind::Ident(name) => (matches!(name.as_str(), "list" | "input") || original_ordinary_call_name(name))
            && matches!(tokens, [only] if simple_term(expr, only)),
        ExprKind::TypePath(path) => {
            // Pinned prefab term: only an absolute slash/identifier path.
            // Exclude relative/upward and edited prefab productions.
            let Some(path) = path.strip_prefix('/') else { return false };
            let mut actual = tokens.chunks_exact(2);
            for component in path.split('/') {
                let Some([slash, name]) = actual.next() else { return false };
                if !punctuation(slash, "/") || name.kind != TokenKind::Ident
                    || !original_ascii_identifier(component) || name.text != component
                {
                    return false;
                }
            }
            actual.next().is_none() && actual.remainder().is_empty()
        }
        ExprKind::Literal(value) => {
            if matches!(tokens, [only] if simple_term(expr, only)) { return true; }
            if matches!(value.original_value(), Some(crate::OriginalTokenValue::Int(_) | crate::OriginalTokenValue::Float(_))) {
                return matches!(tokens, [only] if only.kind == TokenKind::Number && only.text == value.as_str());
            }
            match value.original_value() {
                Some(crate::OriginalTokenValue::String(_)) => {
                    return matches!(tokens, [only] if only.kind == TokenKind::String && only.text == value.as_str());
                }
                Some(crate::OriginalTokenValue::Resource(_)) => {
                    return matches!(tokens, [only] if only.kind == TokenKind::Resource && only.text == value.as_str());
                }
                _ => {}
            }
            let Some(parts) = value.original_prepared_body_parts(expr.span) else { return false };
            let Some((head, rest)) = tokens.split_first() else { return false };
            let Some((begin, fragments)) = parts.fragments.split_first() else { return false };
            let fragment_matches = |token: &Token, fragment: &crate::literal::LiteralFragment| {
                token.kind == TokenKind::Interpolation
                    && token.span.start.checked_sub(expr.span.start) == Some(fragment.range.start)
                    && token.span.end.checked_sub(expr.span.start) == Some(fragment.range.end)
                    && fragment.original.as_ref().is_some_and(|value| value.raw() == token.text)
            };
            if !fragment_matches(head, begin) || begin.expression.is_some() { return false; }
            let mut remaining = rest;
            let mut children = parts.expressions.iter().enumerate();
            for fragment in fragments {
                if let Some(index) = fragment.expression {
                    let Some((actual, child)) = children.next() else { return false };
                    if index != actual { return false; }
                    let (run, tail) = child_prefix(child, remaining);
                    if !original_conditional_child(child, run, true, depth) { return false; }
                    remaining = tail;
                }
                let Some((boundary, tail)) = remaining.split_first() else { return false };
                if !fragment_matches(boundary, fragment) { return false; }
                remaining = tail;
            }
            remaining.is_empty() && children.next().is_none()
        }
        ExprKind::Member { object, selector, via_colon: false }
        | ExprKind::SafeMember { object, selector, via_colon: false } => {
            let (receiver, tail) = child_prefix(object, tokens);
            let separator = if matches!(&expr.kind, ExprKind::SafeMember { .. }) { "?." } else { "." };
            // Pinned follow() consumes another exact Dot or SafeDot
            // regardless of the preceding dot's null-safe spelling.
            let ordinary_receiver = matches!(&object.kind,
                ExprKind::Ident(_) | ExprKind::Member { via_colon: false, .. }
                    | ExprKind::SafeMember { via_colon: false, .. })
                || (separator == "." && matches!(&object.kind, ExprKind::Call { callee, args }
                    if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(_)
                        | ExprKind::Member { via_colon: false, .. })));
            ordinary_receiver
                && original_conditional_child(object, receiver, false, depth)
                && matches!(tail, [dot, name] if punctuation(dot, separator) && name.kind == TokenKind::Ident
                    && name.text == *selector && original_ascii_identifier(selector))
        }
        ExprKind::Unary { op, value } if matches!(op.as_str(), "!" | "-") => {
            matches!(tokens, [prefix, child @ ..] if punctuation(prefix, op)
                && (matches!(&value.kind, ExprKind::Ident(_) | ExprKind::Group(_)
                    | ExprKind::Call { .. } | ExprKind::Member { via_colon: false, .. }
                    | ExprKind::SafeMember { via_colon: false, .. }
                    | ExprKind::Unary { .. } | ExprKind::Literal(_))
                    // Pinned unary() collects ! before term()/follow() consumes
                    // the complete bracket operand. Reuse the exact bounded
                    // index production, including its receiver/key token spans.
                    || (op == "!" && matches!(&value.kind, ExprKind::Index { object, index }
                        if original_plain_index(value, object, index, child, depth))))
                && original_conditional_child(value, child, false, depth))
        }
        ExprKind::Group(value) => {
            let [open, body @ .., close] = tokens else { return false; };
            if !punctuation(open, "(") || !punctuation(close, ")") { return false; }
            if matches!(&value.kind, ExprKind::Binary { op, .. } if op == "in") {
                return depth != 0 && original_plain_membership(value, body);
            }
            original_conditional_child(value, body, true, depth)
        }
        ExprKind::Index { object, index } => {
            if original_plain_index(expr, object, index, tokens, depth) { return true; }
            let (receiver, tail) = child_prefix(object, tokens);
            (matches!(&object.kind, ExprKind::Ident(_) | ExprKind::Member { via_colon: false, .. })
                || (matches!(&object.kind, ExprKind::Index { .. }) && original_nested_string_index(expr)))
                && original_conditional_child(object, receiver, false, depth)
                && matches!(tail, [open, key @ .., close] if punctuation(open, "[")
                    && punctuation(close, "]")
                    && (matches!(&index.kind, ExprKind::Ident(_) | ExprKind::Literal(_))
                        || matches!(&index.kind, ExprKind::Binary { op, lhs, rhs }
                            if op == "+" && matches!(&lhs.kind, ExprKind::Ident(_))
                                && matches!(&rhs.kind, ExprKind::Literal(value)
                                    if original_decimal(value.as_str()))))
                    && original_conditional_child(index, key, false, depth))
        }
        ExprKind::Call { callee, args } => {
            let (head, rest) = child_prefix(callee, tokens);
            let [open, body @ .., close] = rest else { return false };
            if !punctuation(open, "(") || !punctuation(close, ")") { return false; }
            let list_constructor = matches!(&callee.kind, ExprKind::Ident(name)
                if matches!(name.as_str(), "list" | "alist"));
            let arguments_match = |args: &[Expr], body: &[Token], keyword_call, trailing| {
                let mut remaining = body;
                for (index, argument) in args.iter().enumerate() {
                    if index != 0 {
                        let Some((comma, rest)) = remaining.split_first() else { return false };
                        if !punctuation(comma, ",") { return false; }
                        remaining = rest;
                    }
                    let (run, rest) = child_prefix(argument, remaining);
                    let keyword = keyword_call && match &argument.kind {
                        ExprKind::Binary { op, lhs, rhs } if op == "=" => {
                            let (key, tail) = child_prefix(lhs, run);
                            let bare_key = matches!(&lhs.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
                                && matches!(key, [only] if simple_term(lhs, only));
                            let string_key = list_constructor
                                && matches!((&lhs.kind, key), (ExprKind::Literal(literal), [only])
                                    if only.kind == TokenKind::String && lhs.span == only.span
                                        && literal.as_str() == only.text
                                        && matches!(literal.original_value(), Some(crate::OriginalTokenValue::String(_))));
                            (bare_key || string_key)
                                && tail.split_first().is_some_and(|(equals, value)| punctuation(equals, "=")
                                    && original_conditional_child(rhs, value, true, depth))
                        }
                        _ => false,
                    };
                    if !keyword && !original_conditional_child(argument, run, true, depth) { return false; }
                    remaining = rest;
                }
                // Pinned separated() consumes a trailing comma without
                // adding an expression. The roster above still excludes
                // synthetic nulls from leading or interior empty slots.
                remaining.is_empty() || (trailing && !args.is_empty()
                    && matches!(remaining, [comma] if punctuation(comma, ",")))
            };
            if let Ok(Some(form)) = crate::native_special_forms::chained_dispatch(expr) {
                if let crate::native_special_forms::DispatchTarget::External { .. } = form.target {
                    let ExprKind::Call { callee: primitive, args: targets } = &callee.kind else { return false };
                    let [name, target_open, target_body @ .., target_close] = head else { return false };
                    return callee.span == Span::new(name.span.start, target_close.span.end)
                        && simple_term(primitive, name)
                        && punctuation(target_open, "(") && punctuation(target_close, ")")
                        && arguments_match(targets, target_body, false, false)
                        && arguments_match(args, body, false, false);
                }
            }
            // Pinned coordinate locate is a distinct primitive, not an
            // ordinary call. Keep this proof to three positional arguments.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate") {
                return args.len() == 3 && matches!(head, [name] if simple_term(callee, name))
                    && arguments_match(args, body, false, false);
            }
            // Pinned pick has its own choice grammar. Witness one ordinary,
            // unweighted choice without changing its parser or effect role.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "pick") {
                return args.len() == 1 && matches!(head, [keyword] if simple_term(callee, keyword))
                    && arguments_match(args, body, false, false);
            }
            // Pinned NewImplicit has a separate parenthesized argument list.
            // Require exact positional children and both delimiters.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "new") {
                return args.len() <= 16 && matches!(head, [keyword] if simple_term(callee, keyword))
                    && arguments_match(args, body, false, false);
            }
            // Pinned list and alist share the same constructor argument grammar.
            if list_constructor {
                return matches!(head, [name] if simple_term(callee, name))
                    && arguments_match(args, body, true, true);
            }
            let ordinary = match &callee.kind {
                ExprKind::Ident(name) => original_ordinary_call_name(name),
                ExprKind::Member { selector, via_colon: false, .. }
                | ExprKind::SafeMember { selector, via_colon: false, .. } => original_ordinary_call_name(selector),
                _ => false,
            };
            ordinary && original_conditional_child(callee, head, false, depth)
                && arguments_match(args, body, keyword_call, true)
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let Some(binding) = original_binary_binding(op) else { return false };
            // This pinned subset is left binding. A right child at the same
            // strength, or either looser child, needs an actual Group node.
            let correct_binding = |child: &Expr, minimum| match &child.kind {
                ExprKind::Binary { op, .. } => original_binary_binding(op).is_some_and(|at| at >= minimum),
                _ => true,
            };
            let (left, tail) = child_prefix(lhs, tokens);
            let Some((operator, right)) = tail.split_first() else { return false };
            punctuation(operator, op)
                && correct_binding(lhs, binding)
                && correct_binding(rhs, binding + 1)
                && original_conditional_child(lhs, left, false, depth)
                && original_conditional_child(rhs, right, false, depth)
        }
        ExprKind::Conditional { condition, then_value, else_value } if conditional => {
            let (test, tail) = child_prefix(condition, tokens);
            let Some((question, tail)) = tail.split_first() else { return false };
            let (yes, tail) = child_prefix(then_value, tail);
            let Some((colon, no)) = tail.split_first() else { return false };
            // The same Original Pratt branch already distinguished Colon/
            // CloseColon at this consumed separator, using the live scope.
            punctuation(question, "?") && punctuation(colon, ":")
                && original_conditional_child(condition, test, false, depth)
                && original_conditional_child(then_value, yes, false, depth)
                && original_conditional_child(else_value, no, false, depth)
        }
        _ => false,
    }
}

fn original_post_update(expr: &Expr, tokens: &[Token]) -> Option<OriginalSimpleKind> {
    let [name, operator] = tokens else { return None; };
    let ExprKind::Unary { op, value } = &expr.kind else { return None; };
    if !matches!(&value.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
        || !simple_term(value, name) || operator.kind != TokenKind::Operator
        || expr.span != Span::new(name.span.start, operator.span.end)
    {
        return None;
    }
    match (op.as_str(), operator.text.as_str()) {
        ("post++", "++") => Some(OriginalSimpleKind::PostIncrementStatement),
        ("post--", "--") => Some(OriginalSimpleKind::PostDecrementStatement),
        _ => None,
    }
}

fn original_crash_statement(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Call { callee, args } = &expr.kind else { return false };
    let [keyword, open, expression @ .., close] = tokens else { return false };
    matches!(&callee.kind, ExprKind::Ident(name) if name == "CRASH")
        && simple_term(callee, keyword)
        && open.kind == TokenKind::Punctuation && open.text == "("
        && close.kind == TokenKind::Punctuation && close.text == ")"
        && expr.span == Span::new(keyword.span.start, close.span.end)
        && match args.as_slice() {
            [] => expression.is_empty(),
            [argument] => original_conditional_child(argument, expression, true, 32),
            _ => false,
        }
}

/// A plain assignment may also occupy the root of a return expression.
fn original_plain_assignment(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Binary { op, lhs, rhs } = &expr.kind else { return false };
    let [name, equals, value @ ..] = tokens else { return false };
    op == "="
        && matches!(equals.kind, TokenKind::Operator | TokenKind::Punctuation)
        && equals.text == "="
        && matches!(&lhs.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
        && simple_term(lhs, name)
        && expr.span == Span::new(name.span.start, rhs.span.end)
        && original_conditional_child(rhs, value, true, 32)
}

fn original_grouped_field_assignment(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Group(inner) = &expr.kind else { return false; };
    let ExprKind::Binary { op, lhs, rhs } = &inner.kind else { return false; };
    let [open, body @ .., close] = tokens else { return false; };
    let target_end = body.partition_point(|token| token.span.end <= lhs.span.end);
    let (target, remainder) = body.split_at(target_end);
    let [equals, value @ ..] = remainder else { return false; };
    op == "=" && matches!(&lhs.kind, ExprKind::Member { via_colon: false, .. })
        && open.kind == TokenKind::Punctuation && open.text == "("
        && close.kind == TokenKind::Punctuation && close.text == ")"
        && equals.kind == TokenKind::Operator && equals.text == "="
        && expr.span == Span::new(open.span.start, close.span.end)
        && inner.span == Span::new(lhs.span.start, rhs.span.end)
        && original_assignment_receiver(lhs, target)
        && original_conditional_child(rhs, value, true, 32)
}

fn original_simple_complete(expr:&Expr,tokens:&[Token],original_profile:bool)->Option<OriginalSimpleExpression>{
 let complete=match tokens{
  [only]=>simple_term(expr,only),
  [left,op,right]=>match &expr.kind{ExprKind::Binary{op:actual,lhs,rhs}=>simple_arithmetic(actual)&&op.text.as_str()==actual.as_str()&&simple_term(lhs,left)&&simple_term(rhs,right),ExprKind::Member{object,selector,via_colon:false}=>left.kind==TokenKind::Ident&&op.text=="."&&right.kind==TokenKind::Ident&&selector.as_str()==right.text.as_str()&&original_ascii_identifier(selector)&&matches!(&object.kind,ExprKind::Ident(name)if original_ascii_identifier(name))&&simple_term(object,left),ExprKind::Call{..}=>original_zero_call(expr,tokens,original_profile),_=>false},
  [name,open,arg,close]=>original_simple_string_index(expr,tokens,original_profile)||matches!(&expr.kind,ExprKind::Call{callee,args}if name.kind==TokenKind::Ident&&name.text=="list"&&simple_term(callee,name)&&open.text=="("&&close.text==")"&&matches!(args.as_slice(),[item]if simple_term(item,arg))),
  [_,_,_,dot,selector]=>matches!(&expr.kind,ExprKind::Member{object,selector:name,via_colon:false}if dot.text=="."&&selector.kind==TokenKind::Ident&&name==&selector.text&&original_ascii_identifier(name)&&original_zero_call(object,&tokens[..3],original_profile)),
  _=>false,
 } || (original_profile && original_plain_membership(expr, tokens));
 let original_literal = matches!(&expr.kind, ExprKind::Literal(literal)
     if literal.original_prepared_body_parts(expr.span).is_some()
         || matches!(literal.original_value(), Some(crate::OriginalTokenValue::Int(_)
             | crate::OriginalTokenValue::Float(_) | crate::OriginalTokenValue::String(_)
             | crate::OriginalTokenValue::Resource(_))));
 let original_composed = original_profile
     && (original_literal || matches!(&expr.kind, ExprKind::TypePath(_) | ExprKind::Conditional { .. } | ExprKind::Unary { .. }
         | ExprKind::Call { .. } | ExprKind::Binary { .. } | ExprKind::Group(_)
         | ExprKind::Member { via_colon: false, .. } | ExprKind::SafeMember { via_colon: false, .. }))
     && original_conditional_child(expr, tokens, true, 32);
 let plain_index = original_profile && matches!(&expr.kind, ExprKind::Index { object, index }
     if original_plain_index(expr, object, index, tokens, 32));
 let return_slot = original_profile && matches!((&expr.kind, tokens), (ExprKind::Ident(name), [dot])
     if name == "." && dot.kind == TokenKind::Punctuation && dot.text == "." && dot.span == expr.span);
 let kind=if original_profile&&matches!(&expr.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="CRASH")){if original_crash_statement(expr,tokens){OriginalSimpleKind::CrashStatement}else{return None}}else if complete||original_composed||plain_index||return_slot||original_return_list(expr,tokens){OriginalSimpleKind::Complete}else if original_positional_statement_call(expr,tokens)||(original_profile&&original_keyword_statement_call(expr,tokens)){OriginalSimpleKind::OrdinaryCallStatement}else if original_profile&&original_plain_assignment(expr,tokens){OriginalSimpleKind::PlainAssignment}else if original_simple_assignment(expr,tokens,original_profile)||(original_profile&&original_grouped_field_assignment(expr,tokens)){OriginalSimpleKind::SimpleAssignmentStatement}else if original_profile{original_post_update(expr,tokens)?}else{return None};
 Some(OriginalSimpleExpression{kind,span:expr.span,operator:None,original_profile})
}

#[test]
fn original_bare_list_formal_survives_external_arguments() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    for (source, expected) in [
        ("call_ext(__f)(list, flag)", true),
        ("istype(list)", true),
        ("list.len", true),
        // Compatibility lex() splits &&. The real one-token Original
        // geometry is exercised separately below.
        ("istype(list) && list.len", false),
        ("call_ext(__f)(list(flag))", true),
        ("call_ext(__f)(list = flag)", false),
    ] {
        let tokens: Vec<_> = lex(source).tokens.into_iter()
            .map(|token| SpanToken { kind: token.kind, span: token.span }).collect();
        let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
        if expected {
            assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics);
        }
        assert_eq!(
            parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
            expected.then_some(OriginalSimpleKind::Complete),
            "{source}",
        );
    }

    let source = "istype(list) && list.len";
    let start = source.find("&&").unwrap();
    let mut tokens: Vec<_> = lex(source).tokens.into_iter().map(|token| SpanToken {
        kind: token.kind, span: token.span,
    }).collect();
    let left = tokens.iter().position(|token| token.span == Span::new(start, start + 1)).unwrap();
    assert_eq!(tokens[left + 1].span, Span::new(start + 1, start + 2));
    tokens.splice(left..left + 2, [SpanToken {
        kind: TokenKind::Punctuation,
        span: Span::new(start, start + 2),
    }]);
    let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind), Some(OriginalSimpleKind::Complete));
}

#[cfg(test)]
#[cfg(test)]
#[test]
fn original_external_dispatch_witness_requires_two_complete_call_lists() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    for (source, expected) in [
        ("call_ext(__f)()", true),
        ("call_ext(__f)(src_ref, num_val)", true),
        ("call_ext(__f)(arglist(args))", true),
        ("call_ext(library, function)(arg)", true),
        ("call_ext(__f)", false),
        ("call_ext()()", false),
        ("call_ext(, function)()", false),
        ("call_ext(library, function, extra)()", false),
        ("call_ext(__f)(arg)()", false),
        ("call(__f)(arg)", false),
    ] {
        let tokens: Vec<_> = lex(source).tokens.into_iter()
            .map(|token| SpanToken { kind: token.kind, span: token.span }).collect();
        let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
        if expected {
            assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics);
        }
        assert_eq!(
            parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
            expected.then_some(OriginalSimpleKind::Complete),
            "{source}",
        );
    }
}


#[cfg(test)]
#[test]
fn original_plain_index_key_keeps_bare_primitive_field_tokens() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    for (source, expected) in [
        ("input[input.len]", true),
        ("input[input.key]", true),
        ("list[list.len]", true),
        ("ordinary[ordinary.len]", true),
        ("input[input?.len]", false),
        ("input[input:len]", false),
        ("input[input.len.extra]", false),
        ("input[length(input)]", false),
        ("input[input.len][1]", false),
    ] {
        let tokens = lex(source).tokens.into_iter()
            .map(|token| SpanToken { kind: token.kind, span: token.span }).collect::<Vec<_>>();
        let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
        if expected { assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics); }
        assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
            expected.then_some(OriginalSimpleKind::Complete), "{source}");
    }
}

#[cfg(test)]
#[test]
fn original_composed_list_witness_checks_nested_and_named_arguments() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    for (source, expected) in [
        ("list()", true),
        ("list(list(), list(), 0, 0)", true),
        ("list(key = list(other = value))", true),
        ("alist(key = list(), fallback,)", true),
        ("list(receiver.key = value)", false),
        ("list((key) = value)", false),
        ("list(key =)", false),
    ] {
        let tokens: Vec<_> = lex(source).tokens.into_iter()
            .map(|token| SpanToken { kind: token.kind, span: token.span }).collect();
        let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
        if expected {
            assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics);
        }
        assert_eq!(
            parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
            expected.then_some(OriginalSimpleKind::Complete),
            "{source}",
        );
    }
}

#[cfg(test)]
#[test]
fn original_zero_argument_dot_call_can_receive_a_later_dot_call() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    for (source, expected) in [
        ("SSsounds.ready().talk_sound(voice_sound)", true),
        ("service.ready().ready().value(arg)", true),
        ("service.ready(arg).value(arg)", false),
        ("service:ready().value(arg)", false),
        ("service?.ready().value(arg)", false),
        ("service.ready()?.value(arg)", false),
    ] {
        let tokens: Vec<_> = lex(source).tokens.into_iter()
            .map(|token| SpanToken { kind: token.kind, span: token.span }).collect();
        let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
        if expected {
            assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics);
        }
        assert_eq!(
            parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
            expected.then_some(OriginalSimpleKind::Complete),
            "{source}",
        );
    }
}

#[cfg(test)]
mod original_super_provenance {
    use super::*;


    #[test]
    fn original_zero_parent_call_requires_the_single_super_occurrence() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let source = "..().field";
        let punctuation = |start, end| SpanToken {
            kind: TokenKind::Punctuation,
            span: Span::new(start, end),
        };
        let suffix = [
            punctuation(2, 3),
            punctuation(3, 4),
            punctuation(4, 5),
            SpanToken { kind: TokenKind::Ident, span: Span::new(5, source.len()) },
        ];
        for (mut tokens, certified) in [
            (vec![punctuation(0, 2)], true),
            (vec![punctuation(0, 1), punctuation(1, 2)], false),
        ] {
            tokens.extend_from_slice(&suffix);
            let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
            assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
            assert!(matches!(parsed.expr.as_ref().map(|expr| &expr.kind), Some(ExprKind::Member { object, .. })
                if matches!(&object.kind, ExprKind::Call { callee, args }
                    if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == ".."))));
            assert_eq!(
                parsed.original_simple_expression.map(|proof| (proof.kind(), proof.span())),
                certified.then_some((OriginalSimpleKind::Complete, Span::new(0, source.len()))),
            );
        }
    }
}

#[cfg(test)]mod demanded_expression_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 struct Feed{tokens:std::vec::IntoIter<Token>,pulls:usize,forbid:Option<&'static str>,fail:Option<usize>}
 impl NativeExpressionTokenDemand for Feed{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.fail==Some(self.pulls){return Err(std::io::Error::from_raw_os_error(1450))}let token=self.tokens.next();if let Some(token)=&token{assert_ne!(Some(token.text.as_str()),self.forbid,"parser requested a token beyond its first genuine native syntax failure");}Ok(token)}}
 fn feed(text:&str)->Feed{Feed{tokens:lex(text).tokens.into_iter(),pulls:0,forbid:None,fail:None}}

 #[test]
 fn demanded_completed_syntax_settles_only_dead_pratt_work_and_keeps_token_owner() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
    for (text, settles) in [("owner", true), ("42", true), ("owner.value", true), ("list(1, owner.value)", true), ("(owner+)", false), (r#"list("a[x]b")"#, false)] {
        let mut input = feed(text);
        let mut produced = parse_expression_demanded(&mut input, &admission).unwrap();
        let root_before = produced.parsed.expr.as_ref().map(|root| root as *const Expr);
        let token_before = produced.tokens.as_ptr();
        let before = used.load(Ordering::Acquire);
        assert!(before > 0);
        if settles {
            let failed = crate::SettingAdmission::new(&used, 8 << 20, &|| Err(std::io::Error::from_raw_os_error(1450)));
            assert_eq!(produced.settle_completed_syntax(&failed).unwrap_err().raw_os_error(), Some(1450));
            assert_eq!(used.load(Ordering::Acquire), before);
        }
        produced.settle_completed_syntax(&admission).unwrap();
        let after = used.load(Ordering::Acquire);
        if settles {
            let syntax = produced.parsed.expr.as_ref().unwrap();
            let owned = crate::setting_prepare::demanded_completed_owned_bytes(syntax).unwrap();
            if let ExprKind::Member { object, selector, .. } = &syntax.kind {
                let ExprKind::Ident(name) = &object.kind else { panic!("actual member receiver"); };
                let cleanup = 2 * 4 * (std::mem::size_of::<Expr>() + std::mem::size_of::<crate::SharedSettingRetention>());
                assert_eq!(owned, cleanup + std::mem::size_of::<Expr>() + name.capacity() + selector.capacity());
            }
            assert_eq!(after, owned + produced.tokens.capacity() * std::mem::size_of::<Token>()
                + produced.tokens.iter().map(|token| token.text.capacity()).sum::<usize>());
            assert!(after < before);
        } else {
            assert_eq!(after, before);
        }
        assert_eq!(produced.tokens.as_ptr(), token_before);
        assert_eq!(produced.parsed.expr.as_ref().map(|root| root as *const Expr), root_before);
        if settles {
            let root = crate::retain_demanded_expression(produced, &admission).unwrap();
            assert_eq!(root.original_expression().span, Span::new(0, text.len()));
            drop(root);
        } else {
            drop(produced);
        }
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
 }

 #[test]
 fn demanded_completed_syntax_retains_original_envelope_above_walk_limit() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
    let text = format!("list({})", ["1"; 32].join(","));
    let mut input = feed(&text);
    let mut produced = parse_expression_demanded(&mut input, &admission).unwrap();
    assert!(produced.parsed().diagnostics.is_empty());
    assert!(crate::setting_prepare::demanded_completed_owned_bytes(produced.parsed().expr.as_ref().unwrap()).is_none());
    let before = used.load(Ordering::Acquire);
    produced.settle_completed_syntax(&admission).unwrap();
    assert_eq!(used.load(Ordering::Acquire), before);
    drop(produced);
    assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn completed_demanded_expression_seals_the_exact_root_and_tokens_after_live_notices() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
    let mut input = feed("()");
    let produced = parse_original_expression_demanded(&mut input, &admission).unwrap();
    let notices = produced.parsed().original_input_notices().unwrap().as_slice();
    assert_eq!(notices.len(), 1);
    assert_eq!(notices[0].kind(), crate::OriginalInputNoticeKind::EmptyParentheses);
    let root = produced.parsed().expr.as_ref().unwrap();
    let ExprKind::Literal(literal) = &root.kind else { panic!("actual empty-parentheses recovery"); };
    let literal_storage = literal.raw_storage().as_ptr();
    let token_storage = produced.tokens().as_ptr();
    let pulls = input.pulls;

    let completed = produced.into_completed_syntax(&admission).unwrap();
    assert_eq!(completed.tokens().as_ptr(), token_storage);
    let ExprKind::Literal(literal) = &completed.expression().kind else { panic!("same recovered root"); };
    assert_eq!(literal.raw_storage().as_ptr(), literal_storage);
    let retained = completed.retain(&admission).unwrap();
    let ExprKind::Literal(literal) = &retained.original_expression().kind else { panic!("same published root"); };
    assert_eq!(literal.raw_storage().as_ptr(), literal_storage);
    assert_eq!(input.pulls, pulls);
    drop(retained);
    assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn completed_demanded_expression_rejects_syntax_failure_foreign_owner_and_first_io() {
    use std::io::ErrorKind;
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let foreign_used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
    let foreign = crate::SettingAdmission::new(&foreign_used, 8 << 20, &|| Ok(()));
    let invalid = parse_original_expression_demanded(&mut feed("(1+)"), &a).unwrap();
    assert_eq!(invalid.into_completed_syntax(&a).err().unwrap().kind(), ErrorKind::InvalidData);
    let valid = parse_original_expression_demanded(&mut feed("owner.field"), &a).unwrap();
    assert_eq!(valid.into_completed_syntax(&foreign).err().unwrap().kind(), ErrorKind::InvalidInput);
    let valid = parse_original_expression_demanded(&mut feed("owner.field"), &a).unwrap();
    let fail = crate::SettingAdmission::new(&used, 8 << 20, &|| Err(std::io::Error::from_raw_os_error(1450)));
    assert_eq!(valid.into_completed_syntax(&fail).err().unwrap().raw_os_error(), Some(1450));
    assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    assert_eq!(foreign_used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn original_pick_empty_arms_stop_at_the_reported_post_comma_token() {
  let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
  for (text, value, span) in [
   ("pick(,1)", 1, Span::new(6, 7)),
   ("pick(1,,2)", 2, Span::new(8, 9)),
  ] {
   let mut input = feed(text);
   input.forbid = Some(")");
   let actual = parse_original_expression_demanded(&mut input, &admission).unwrap();
   assert!(actual.parsed().expr.is_none());
   assert_eq!(actual.parsed().diagnostics.len(), 1);
   assert_eq!(actual.tokens().last().unwrap().span, span);
   let failure = actual.parsed().original_input_failure().expect("typed post-comma failure");
   assert_eq!(failure.token_span(), Some(span));
   assert_eq!(failure.expected(), crate::OriginalInputExpected::EmptyPickArm);
   let mut message = String::new();
   crate::write_original_input_failure(&mut message, Some(crate::OriginalTokenValue::Int(value)), failure.expected()).unwrap();
   assert_eq!(message, format!("got '{value}', expected one of: "));
   drop(actual);
   assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
  }
 }

 #[test]
 fn original_pick_keeps_empty_and_weighted_lists_and_ordinary_calls_keep_omissions() {
  let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let admission = crate::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
  for (text, count, weighted) in [("pick()", 0, 0), ("pick(1,)", 1, 0), ("pick(2;1, 4;3,)", 2, 2)] {
   let actual = parse_original_expression_demanded(&mut feed(text), &admission).unwrap();
   assert!(actual.parsed().diagnostics.is_empty(), "{text}: {:?}", actual.parsed().diagnostics);
   let pick = crate::native_special_forms::pick(actual.parsed().expr.as_ref().unwrap()).unwrap();
   assert_eq!(pick.choices().count(), count);
   assert_eq!(pick.choices().filter(|choice| choice.weight.is_some()).count(), weighted);
  }
  for text in ["normal(,1,,2)", "object.pick(,1,,2)", "::pick(,1,,2)"] {
   let actual = parse_original_expression_demanded(&mut feed(text), &admission).unwrap();
   assert!(actual.parsed().diagnostics.is_empty(), "{text}: {:?}", actual.parsed().diagnostics);
   let ExprKind::Call { args, .. } = &actual.parsed().expr.as_ref().unwrap().kind else { panic!("{text}") };
   assert_eq!(args.len(), 4);
   for index in [0, 2] {
    assert!(matches!(&args[index].kind, ExprKind::Literal(value) if value.as_str() == "null"));
    assert_eq!(args[index].span.start, args[index].span.end);
   }
  }
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn same_native_pratt_demand_matches_complete_native_grammar_without_prefix_replay(){
  for text in["1+2*3","a=b in c","a?b:c","a::member","::global_proc(1,2)","new /datum/item(1).field","as(())","a?.field","a?[1]","(a+b)**2","list(1,key=2)","\"ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â½ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â± literal\""]{
   let old=parse_expression(text);let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<24,&||Ok(()));let mut input=feed(text);let actual=parse_expression_demanded(&mut input,&a).unwrap();assert_eq!(format!("{:?}",actual.parsed()),format!("{old:?}"),"{text}");assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes()||actual.tokens().is_empty());drop(actual);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_native_pratt_stops_demand_at_first_unexpected_term_without_requesting_later_tokens(){
  for text in["; BAD(1)","1 bad BAD(1)","(1+) BAD(1)"]{let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<24,&||Ok(()));let mut input=feed(text);input.forbid=Some("BAD");let actual=parse_expression_demanded(&mut input,&a).unwrap();assert!(!actual.parsed().diagnostics.is_empty(),"{text}");if text.starts_with(';'){assert_eq!(actual.expected_term().unwrap().token_span(),Some(Span::new(0,1)));}drop(actual);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 }
 #[test]fn actual_native_pratt_demand_keeps_first_source_io_and_same_budget_oom_without_partial_success(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<24,&||Ok(()));let mut input=feed("1+2");input.fail=Some(2);let error=parse_expression_demanded(&mut input,&a).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(input.pulls,2);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,crate::SettingChargeCounter::root_allocation_bytes() + (1),&||Ok(()));let mut input=feed("1+2");assert_eq!(parse_expression_demanded(&mut input,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod demanded_token_credit_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 struct Feed{token:Option<Token>,credit:Option<crate::SettingRootLease>,fault:bool}
 impl NativeExpressionTokenDemand for Feed{
  fn next_token(&mut self)->std::io::Result<Option<Token>>{Ok(self.token.take())}
  fn take_token_credit(&mut self,occurrence:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::SettingRootLease>>{assert_eq!(occurrence.ordinal(),0);if self.fault{return Err(std::io::Error::from_raw_os_error(1450))}Ok(self.credit.take())}
 }
 fn feed(a:&crate::SettingAdmission<'_>,credit:bool)->Feed{
  // Fixture allocation is admitted before the real raw String is allocated.
  let root=a.reserve(1).unwrap();let mut text=String::with_capacity(1);text.push('1');assert_eq!(text.capacity(),1);
  Feed{token:Some(Token{kind:TokenKind::Number,span:Span::new(0,1),text}),credit:credit.then_some(root),fault:false}
 }
 #[test]fn actual_native_demand_adopts_one_spelling_credit_without_duplicate_charge_and_retains_it_with_result(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<20,&poll);
  let mut prepaid=feed(&a,true);let parsed=parse_expression_demanded(&mut prepaid,&a).unwrap();let adopted=counter.load(Ordering::Acquire);assert!(adopted>0);assert!(prepaid.credit.is_none());assert!(parsed.parsed().diagnostics.is_empty());drop(parsed);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let mut ordinary=feed(&a,false);let parsed=parse_expression_demanded(&mut ordinary,&a).unwrap();assert_eq!(counter.load(Ordering::Acquire),adopted);drop(parsed);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_native_demand_credit_foreign_root_and_first_io_never_issue_partial_success(){
  let one=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let two=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&one,1<<20,&poll);let b=crate::SettingAdmission::new(&two,1<<20,&poll);
  let mut foreign=feed(&b,true);let error=parse_expression_demanded(&mut foreign,&a).err().expect("foreign token must refuse");assert_eq!(error.kind(),std::io::ErrorKind::InvalidInput);drop(foreign);assert_eq!(one.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());assert_eq!(two.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let mut fault=feed(&a,true);fault.fault=true;let error=parse_expression_demanded(&mut fault,&a).err().expect("genuine source IO must refuse");assert_eq!(error.raw_os_error(),Some(1450));drop(fault);assert_eq!(one.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

/// Raw syntax DATA over the SAME original token occurrence view. The caller
/// must authenticate current source/header ownership before lending facts.
pub fn parse_expression_original_token_view(source:&str,tokens:&[SpanToken],source_origin:usize,a:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>)->ParsedExpr{parse_span_tokens_profile(source,tokens,0,source_origin,a,facts,true)}

#[cfg(test)]mod typed_punctuation_demand_control{
 use super::*;
 struct Typed{pulls:usize}
 impl NativeExpressionTokenDemand for Typed{
  fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;assert_eq!(self.pulls,1,"actual typed colon requested a future token");Ok(Some(Token{kind:TokenKind::Punctuation,span:Span::new(0,1),text:":".into()}))}
  fn original_value(&self,_occurrence:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{Ok(Some(crate::OriginalTokenValue::Punct(":")))}
  fn requires_original_values(&self)->bool{true}
 }
 #[test]fn actual_typed_colon_is_not_reconstructed_by_requesting_a_future_raw_token(){let mut source=Typed{pulls:0};let mut cursor=NativeExpressionTokenCursor{source:&mut source,pending:None,next_ordinal:0,role:NativeExpressionReadRole::Follower,boundary:None};let actual=cursor.next(None).unwrap().unwrap();assert_eq!(actual.token.text,":");assert_eq!(actual.token.span,Span::new(0,1));drop(cursor);assert_eq!(source.pulls,1);}
}

#[cfg(test)]mod original_close_colon_transport_controls{
 use super::*;use std::sync::{atomic::{Ordering}};
 // These are final producer values, deliberately independent of authored colon whitespace.
 // The source never lexes or reparses authored strings to recreate closeness.
 struct Feed{rows:Vec<(Token,Option<bool>)>,at:usize,fail_close:bool}
 impl Feed{fn new(rows:&[(TokenKind,&'static str,Option<bool>)])->Self{let mut at=0;Self{rows:rows.iter().map(|&(kind,text,close)|{let span=Span::new(at,at+text.len());at=span.end;(Token{kind,span,text:text.into()},close)}).collect(),at:0,fail_close:false}}}
 impl NativeExpressionTokenDemand for Feed{
  fn next_token(&mut self)->std::io::Result<Option<Token>>{let row=self.rows.get(self.at);self.at+=1;Ok(row.map(|(t,_)|t.clone()))}
  fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{let(t,_)=self.rows.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(Some(if t.kind==TokenKind::Ident&&t.text=="in"{crate::OriginalTokenValue::Punct("in")}else if t.kind==TokenKind::Ident{crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false}}else{crate::OriginalTokenValue::Punct(match t.text.as_str(){":"=>":","?"=>"?","("=>"(",")"=>")","||"=>"||","&&"=>"&&","&"=>"&","!"=>"!","."=>".","?."=>"?.","=="=>"==","!="=>"!=","["=>"[","]"=>"]","<="=>"<=",">"=>">",">>"=>">>","+"=>"+","*"=>"*","-"=>"-",_=>return Err(std::io::ErrorKind::InvalidInput.into())})}))}
  fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{if self.fail_close{return Err(std::io::Error::from_raw_os_error(1450))}let(t,close)=self.rows.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(*close)}
  fn requires_original_values(&self)->bool{true}
 }
 #[test]fn actual_close_colon_controls_keep_original_scoped_and_ternary_decisions_without_spelling_inference(){
  use TokenKind::{Ident as I,Punctuation as P};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for (rows,allowed) in [
   (vec![(I,"value",None),(P,":",Some(true)),(I,"key",None)],true),
   (vec![(I,"value",None),(P,":",Some(false)),(I,"key",None)],false),
   (vec![(I,"a",None),(P,"?",None),(I,"b",None),(P,":",Some(false)),(I,"c",None)],true),
   // Old group.belongs_to is live for b, so b:c is a follow, not a ternary delimiter.
   (vec![(I,"a",None),(P,"?",None),(I,"b",None),(P,":",Some(true)),(I,"c",None)],false),
   // Calls clear group.belongs_to, permitting CloseColon as the ternary delimiter.
   (vec![(I,"a",None),(P,"?",None),(I,"f",None),(P,"(",None),(P,")",None),(P,":",Some(true)),(I,"c",None)],true),
   (vec![(P,":",Some(true)),(I,"child",None)],true),
   (vec![(P,":",Some(false)),(I,"child",None)],false),
  ]{let mut source=Feed::new(&rows);let output=parse_original_expression_demanded(&mut source,&a).unwrap();assert_eq!(output.parsed().diagnostics.is_empty(),allowed,"rows: {rows:?}");drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 }
 #[test]
 fn actual_original_conditional_witness_composes_group_and_preserves_colon_controls(){
  use TokenKind::{Ident as I,Punctuation as P};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let name=|text|(I,text,None);
  let punct=|text|(P,text,None);
  let colon=(P,":",Some(false));
  let yes=[name("a"),punct("?"),punct("("),name("b"),punct("?"),name("c"),colon,name("d"),punct(")"),colon,name("e")];
  let adjacent_call=[name("a"),punct("?"),name("f"),punct("("),name("b"),punct(")"),(P,":",Some(true)),name("c")];
  let scoped_colon=[name("a"),punct("?"),name("b"),(P,":",Some(true)),name("c")];
  let bare_chain=[name("a"),punct("?"),name("b"),punct("?"),name("c"),colon,name("d"),colon,name("e")];
  let missing_else=[name("a"),punct("?"),name("b"),colon];
  for (tokens,witnessed) in [(&yes[..],true),(&adjacent_call[..],true),(&scoped_colon[..],false),(&bare_chain[..],false),(&missing_else[..],false)] {
   let mut feed=Feed::new(tokens);
   let outcome=parse_original_expression_demanded(&mut feed,&admission).unwrap();
   assert_eq!(outcome.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),witnessed.then_some(OriginalSimpleKind::Complete),"{tokens:?}");
   drop(outcome);
   assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  assert!(parse_expression("a ? (b ? c : d) : e").original_simple_expression.is_none());
 }
 #[test]
 fn actual_original_membership_accepts_one_lhs_dot_field_with_an_exact_name_container() {
     use TokenKind::Ident;
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let name = |text| (Ident, text, None);
     let punct = |text| (crate::original_scalar_transport::original_punctuation_native_kind(text), text, None);
     let field = [name("rank"), punct("."), name("name"), name("in"), name("rank_names")];
     let negated = [punct("!"), punct("("), name("rank"), punct("."), name("name"),
         name("in"), name("rank_names"), punct(")")];
     let deeper = [name("rank"), punct("."), name("group"), punct("."), name("name"), name("in"), name("rank_names")];
     let safe = [name("rank"), punct("?."), name("name"), name("in"), name("rank_names")];
     let index = [name("rank"), punct("["), name("name"), punct("]"), name("in"), name("rank_names")];
     let rhs_field = [name("rank"), punct("."), name("name"), name("in"), name("container"), punct("."), name("rank_names")];
     let boolean_rhs = [name("rank"), punct("."), name("name"), name("in"), name("rank_names"), punct("&&"), name("flag")];
     let range = [name("rank"), punct("."), name("name"), name("in"), name("first"), name("to"), name("last")];
     for (tokens, expected) in [
         (&field[..], true), (&negated[..], true), (&deeper[..], false), (&safe[..], false),
         (&index[..], false), (&rhs_field[..], false), (&boolean_rhs[..], false), (&range[..], false),
     ] {
         let mut feed = Feed::new(tokens);
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.then_some(OriginalSimpleKind::Complete), "{tokens:?}");
         if std::ptr::eq(tokens.as_ptr(), field.as_ptr()) {
             assert!(output.parsed().diagnostics.is_empty());
             assert!(matches!(output.parsed().expr.as_ref().map(|expr| &expr.kind),
                 Some(ExprKind::Binary { op, lhs, rhs }) if op == "in"
                     && matches!(&lhs.kind, ExprKind::Member { object, selector, via_colon: false }
                         if selector == "name" && matches!(&object.kind, ExprKind::Ident(name) if name == "rank"))
                     && matches!(&rhs.kind, ExprKind::Ident(name) if name == "rank_names")));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_bare_membership_is_an_entire_condition_without_low_precedence_tails() {
     use TokenKind::Ident;
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let name = |text| (Ident, text, None);
     let punct = |text| (crate::original_scalar_transport::original_punctuation_native_kind(text), text, None);
     let plain_list = [name("index"), name("in"), name("list")];
     let plain_name = [name("index"), name("in"), name("entries")];
     let grouped_list = [punct("!"), punct("("), name("index"), name("in"), name("list"), punct(")")];
     let boolean_lhs = [name("index"), punct("&&"), name("flag"), name("in"), name("entries")];
     let boolean_rhs = [name("index"), name("in"), name("entries"), punct("&&"), name("flag")];
     let range = [name("index"), name("in"), name("first"), name("to"), name("last")];
     let conditional = [name("index"), name("in"), name("flag"), punct("?"), name("first"),
         (TokenKind::Punctuation, ":", Some(false)), name("second")];
     let trailing = [name("index"), name("in"), name("entries"), name("tail")];
     let split = [name("index"), name("i"), name("n"), name("entries")];
     for (tokens, expected) in [
         (&plain_list[..], true), (&plain_name[..], true), (&grouped_list[..], true),
         (&boolean_lhs[..], false), (&boolean_rhs[..], false), (&range[..], false),
         (&conditional[..], false), (&trailing[..], false), (&split[..], false),
     ] {
         let mut feed = Feed::new(tokens);
         let outcome = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(outcome.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.then_some(OriginalSimpleKind::Complete), "{tokens:?}");
         if expected {
             assert!(outcome.parsed().diagnostics.is_empty());
         } else if std::ptr::eq(tokens.as_ptr(), boolean_lhs.as_ptr()) {
             assert!(matches!(outcome.parsed().expr.as_ref().map(|expr| &expr.kind),
                 Some(ExprKind::Binary { op, lhs, .. }) if op == "in"
                     && matches!(&lhs.kind, ExprKind::Binary { op, .. } if op == "&&")));
         } else if std::ptr::eq(tokens.as_ptr(), boolean_rhs.as_ptr()) {
             assert!(matches!(outcome.parsed().expr.as_ref().map(|expr| &expr.kind),
                 Some(ExprKind::Binary { op, rhs, .. }) if op == "in"
                     && matches!(&rhs.kind, ExprKind::Binary { op, .. } if op == "&&")));
         }
         drop(outcome);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(parse_expression("index in list").original_simple_expression.is_none());
 }
 #[test]
 fn actual_original_grouped_membership_witness_preserves_outer_boolean_binding() {
     use TokenKind::Ident;
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let name = |text| (Ident, text, None);
     let punct = |text| (crate::original_scalar_transport::original_punctuation_native_kind(text), text, None);
     let negated = [punct("!"), punct("("), name("e"), name("in"), name("result"), punct(")"),
         punct("&&"), punct("!"), punct("("), name("e"), name("in"), name("second"), punct(")")];
     let indexed = [punct("!"), punct("("), name("entry"), name("in"), name("second"), punct(")"),
         punct("||"), punct("("), name("first"), punct("["), name("entry"), punct("]"),
         punct("!="), name("second"), punct("["), name("entry"), punct("]"), punct(")")];
     let ungrouped = [name("e"), name("in"), name("result"), punct("&&"), name("second")];
     let inner_boolean = [punct("("), name("e"), name("in"), name("result"), punct("&&"), name("second"), punct(")")];
     let range = [punct("("), name("e"), name("in"), name("first"), name("to"), name("second"), punct(")")];
     let split_in = [punct("("), name("e"), name("i"), name("n"), name("result"), punct(")")];
     for (tokens, expected) in [
         (&negated[..], Some("&&")), (&indexed[..], Some("||")),
         (&ungrouped[..], None), (&inner_boolean[..], None), (&range[..], None), (&split_in[..], None),
     ] {
         let mut feed = Feed::new(tokens);
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         let parsed = output.parsed();
         assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.map(|_| OriginalSimpleKind::Complete), "{tokens:?}");
         if let Some(expected) = expected {
             assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
             let Some(ExprKind::Binary { op, lhs, rhs }) = parsed.expr.as_ref().map(|expr| &expr.kind)
                 else { panic!("missing outer boolean"); };
             assert_eq!(op, expected);
             let membership = |expr: &Expr| matches!(&expr.kind, ExprKind::Unary { op, value }
                 if op == "!" && matches!(&value.kind, ExprKind::Group(inner)
                     if matches!(&inner.kind, ExprKind::Binary { op, .. } if op == "in")));
             assert!(membership(lhs));
             if expected == "&&" {
                 assert!(membership(rhs));
             } else {
                 assert!(matches!(&rhs.kind, ExprKind::Group(inner)
                     if matches!(&inner.kind, ExprKind::Binary { op, lhs, rhs }
                         if op == "!=" && matches!(&lhs.kind, ExprKind::Index { .. })
                             && matches!(&rhs.kind, ExprKind::Index { .. }))));
             }
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_comparison_witness_requires_single_operators_and_pinned_binding() {
  use TokenKind::{Ident as I,Punctuation as P};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let name=|text|(I,text,None);
  let punct=|text|(P,text,None);
  let mixed=[name("a"),punct("=="),name("b"),punct("||"),name("c"),punct("<="),name("d"),punct("&&"),name("e")];
  let grouped=[(TokenKind::Operator,"!",None),punct("("),name("a"),punct("||"),name("b"),punct(")"),punct("&&"),name("c")];
  let split=[name("a"),punct("&"),punct("&"),name("b")];
  let missing=[name("a"),punct("||")];
  for (tokens,witnessed) in [(&mixed[..],true),(&grouped[..],true),(&split[..],false),(&missing[..],false)] {
   let mut feed=Feed::new(tokens);
   let outcome=parse_original_expression_demanded(&mut feed,&admission).unwrap();
   assert_eq!(outcome.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),witnessed.then_some(OriginalSimpleKind::Complete),"{tokens:?}");
   if std::ptr::eq(tokens.as_ptr(), mixed.as_ptr()) {
       let Some(ExprKind::Binary { op, lhs, rhs }) = outcome.parsed().expr.as_ref().map(|value| &value.kind) else { panic!("actual mixed comparison root") };
       assert_eq!(op,"||");
       assert!(matches!(&lhs.kind, ExprKind::Binary { op, .. } if op=="=="));
       assert!(matches!(&rhs.kind, ExprKind::Binary { op, lhs, .. }
           if op=="&&" && matches!(&lhs.kind, ExprKind::Binary { op, .. } if op=="<=")));
   }
   drop(outcome);
   assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  assert!(parse_expression("a == b || c <= d && e").original_simple_expression.is_none());
 }

 #[test]
 fn actual_original_arithmetic_bitwise_witness_preserves_shift_binding_and_token_width() {
  use TokenKind::{Ident as I,Punctuation as P};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let name=|text|(I,text,None);
  let punct=|text|(P,text,None);
  let mixed=[name("a"),punct("&"),name("b"),punct("=="),name("c"),punct(">>"),name("d"),punct("<="),name("e"),punct("+"),name("f"),punct("*"),name("g")];
  let mut feed=Feed::new(&mixed);
  let outcome=parse_original_expression_demanded(&mut feed,&admission).unwrap();
  assert_eq!(outcome.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),Some(OriginalSimpleKind::Complete));
  let mut expression=outcome.parsed().expr.as_ref().unwrap();
  for expected in ["&","==",">>","<=","+","*"] {
      let ExprKind::Binary { op, rhs, .. } = &expression.kind else { panic!("missing pinned {expected} precedence"); };
      assert_eq!(op,expected);
      expression=rhs;
  }
  drop(outcome);

  let split=[name("a"),punct(">"),punct(">"),name("b")];
  let missing=[name("a"),punct("*")];
  for tokens in [&split[..],&missing[..]] {
      let mut feed=Feed::new(tokens);
      let outcome=parse_original_expression_demanded(&mut feed,&admission).unwrap();
      assert_ne!(outcome.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),Some(OriginalSimpleKind::Complete));
  }
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_close_colon_query_preserves_first_io_and_fresh_parser_recovery(){
  use TokenKind::{Ident as I,Punctuation as P};let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let rows=[(I,"value",None),(P,":",Some(true)),(I,"key",None)];let mut source=Feed::new(&rows);source.fail_close=true;assert_eq!(parse_original_expression_demanded(&mut source,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());let mut source=Feed::new(&rows);drop(parse_original_expression_demanded(&mut source,&a).unwrap());assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod original_empty_group_event_controls{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn same_native_empty_group_issues_null_and_one_actual_closing_warning(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut tokens=crate::lex("()) BAD").tokens.into_iter();let mut source=||{let next=tokens.next();assert!(next.as_ref().is_none_or(|token|token.text!="BAD"));Ok(next)};let mut clauses=crate::ParameterClauseCursor::new(0);let mut source=crate::ParameterExpressionDemand::new(&mut source,&mut clauses).original();let root=crate::parse_original_expression_demanded(&mut source,&a).unwrap();assert!(root.parsed().diagnostics.is_empty());assert!(matches!(&root.parsed().expr.as_ref().unwrap().kind,ExprKind::Literal(value)if value.as_str()=="null"));let events=root.parsed().original_input_notices().unwrap().as_slice();assert_eq!(events.len(),1);assert_eq!(events[0].kind(),crate::OriginalInputNoticeKind::EmptyParentheses);assert_eq!(events[0].span(),Span::new(1,2));assert_eq!(source.take_boundary().unwrap().span,Span::new(2,3));drop(root);drop(source);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}
