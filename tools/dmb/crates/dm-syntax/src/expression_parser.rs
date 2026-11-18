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
pub(crate) fn parse_expression_span_tokens_with_original_literals_and_native_facts(
 source:&str,tokens:&[SpanToken],current_offset:usize,admission:&crate::SettingAdmission<'_>,
 facts:Option<crate::OriginalLiteralFactsView<'_>>,
)->(ParsedExpr,Option<NativeExpressionParserFacts>){
 let original=facts.is_some();let mut native=None;
 let parsed=parse_span_tokens_profile_native(source,tokens,current_offset,0,admission,facts,original,&mut|facts|native=Some(facts));
 (parsed,native)
}
/// SAME parser and original native tokens, normalized to one snippet's local
/// expression coordinates BEFORE parsing. No prior absolute AST is rebound.
pub(crate) fn parse_expression_span_tokens_with_literal_origin(source:&str,tokens:&[SpanToken],current_offset:usize,source_origin:usize,admission:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>)->ParsedExpr{let original=facts.is_some();parse_span_tokens_profile(source,tokens,current_offset,source_origin,admission,facts,original)}
fn parse_span_tokens_profile(source:&str,tokens:&[SpanToken],current_offset:usize,source_origin:usize,admission:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>,original_profile:bool)->ParsedExpr{
 parse_span_tokens_profile_native(source,tokens,current_offset,source_origin,admission,facts,original_profile,&mut |_|{})
}
fn parse_span_tokens_profile_native(source:&str,tokens:&[SpanToken],current_offset:usize,source_origin:usize,admission:&crate::SettingAdmission<'_>,facts:Option<crate::OriginalLiteralFactsView<'_>>,original_profile:bool,native:&mut dyn FnMut(NativeExpressionParserFacts))->ParsedExpr{
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
    finish_expression_with_literal_facts_native(owned,Vec::new(),Some(admission),facts.map(|view|{let(rows,origin)=view.raw_parts();(rows,origin,current_offset,source_origin)}),colons,original_profile,original_profile.then_some((source,current_offset,source_origin)),native)
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
 finish_expression_with_literal_facts_native(tokens,diagnostics,admission,literal_facts,colon_facts,original_profile,original_source,&mut |_|{})
}
fn finish_expression_with_literal_facts_native<'facts>(tokens:Vec<Token>,diagnostics:Vec<Diagnostic>,admission:Option<&crate::SettingAdmission<'_>>,literal_facts:Option<(crate::OriginalLiteralRows<'facts>,usize,usize,usize)>,colon_facts:Option<(crate::OriginalColonRows<'facts>,usize)>,original_profile:bool,original_source:Option<(&'facts str,usize,usize)>,native:&mut dyn FnMut(NativeExpressionParserFacts))->ParsedExpr {
    finish_expression_with_literal_facts_native_role(tokens,diagnostics,admission,literal_facts,colon_facts,original_profile,original_source,native,false)
}
fn finish_expression_with_literal_facts_native_role<'facts>(tokens:Vec<Token>,diagnostics:Vec<Diagnostic>,admission:Option<&crate::SettingAdmission<'_>>,literal_facts:Option<(crate::OriginalLiteralRows<'facts>,usize,usize,usize)>,colon_facts:Option<(crate::OriginalColonRows<'facts>,usize)>,original_profile:bool,original_source:Option<(&'facts str,usize,usize)>,native:&mut dyn FnMut(NativeExpressionParserFacts),optional_empty:bool)->ParsedExpr {
    let native_recovered=!diagnostics.is_empty();
    let cleanup=match crate::parser_cleanup::ParserCleanup::new(admission){Ok(value)=>value,Err(error)=>{if let Some(a)=admission{a.forward_operational_error(error)}return ParsedExpr::default()}};
    let mut parser = ExprParser {
        cleanup,
        native_recovered,
        native_deferred:false,
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
    // Only the actual interpolation optional-expression production owns this
    // empty entry branch. Required whole expressions keep prefix's missing-term
    // expectation; no Expr or complete-root receipt is invented for absence.
    let expr = if optional_empty&&parser.peek().is_none(){None}else{parser.expression(0)}.and_then(|value|value.into_default(admission));
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
    let exhausted=parser.index==parser.tokens.len()&&parser.input_failure.is_none()
      &&parser.expected_term.is_none()&&parser.expected_delimiter.is_none();
    let complete=if exhausted && parser.admission.is_some_and(|a|!a.is_stopped())
      &&!parser.native_recovered&&!parser.native_deferred{expr.as_ref().map(|root|root.span)}else{None};
    native(NativeExpressionParserFacts{complete,aggregate_complete:false,exhausted,
      recovered:parser.native_recovered,deferred:parser.native_deferred});
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
pub struct DemandedExpression{native_parser_facts:NativeExpressionParserFacts,parsed:ParsedExpr,tokens:Vec<Token>,expected_term:Option<NativeTermExpectation>,expected_delimiter:Option<NativeDelimiterExpectation>,lease:crate::SettingRootLease}
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
 pub fn into_completed_syntax(self,a:&crate::SettingAdmission<'_>)->std::io::Result<CompletedDemandedExpression>{
  self.into_completed_syntax_with_native_observation(a).map(|(syntax,_)|syntax)
 }
 /// Transient DATA paired with this actual immutable product, not a retained marker.
 pub fn into_completed_syntax_with_native_observation(mut self,a:&crate::SettingAdmission<'_>)->std::io::Result<(CompletedDemandedExpression,NativeExpressionParserFacts)>{
    if self.parsed.expr.is_none() || !self.parsed.diagnostics.is_empty()
        || self.parsed.original_input_failure.is_some()
        || self.expected_term.is_some() || self.expected_delimiter.is_some() {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "only an actual completed native expression can be sealed"));
    }
    if !a.matches_lease_domain(&self.lease) {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "completed native expression belongs to another resource owner"));
    }
    self.settle_completed_syntax(a)?;
    let self_facts=self.native_parser_facts;
    let Self { parsed, tokens, lease, .. } = self;
    let ParsedExpr { expr, .. } = parsed;
    let root=expr.expect("checked actual completed root");
    Ok((CompletedDemandedExpression {root,tokens,lease},self_facts))
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
 let cleanup=crate::parser_cleanup::ParserCleanup::new(Some(admission)).map_err(|error|admission.take_operational_error().unwrap_or(error))?;
 let mut parser=ExprParser{cleanup,native_recovered:false,native_deferred:false,admission:Some(admission),tokens:Vec::new(),index:0,ternary_then_depth:0,original_simple_incomplete:None,original_scope_prefix:None,original_profile,input_notices:crate::original_input_notices::Builder::default(),constructor_facts:crate::original_constructor_facts::Builder::default(),input_failure:None,expected_term:None,expected_delimiter:None,diagnostics:Vec::new(),literal_facts:None,colon_facts:None,original_source:None,demand:Some(input)};
 let expr=parser.expression(0).and_then(|value|value.into_default(Some(admission)));
 // Demand-mode recovery never requests a token after the first actual native
 // syntax failure. Ordinary whole expression recovery remains unchanged.
 if requires_end&&parser.diagnostics.is_empty(){let extra=parser.peek().map(|token|(token.span,format!("unexpected token in expression: {}",token.text)));if let Some((span,message))=extra{parser.error(span,message)}}
 let input=parser.demand.take().expect("same demanded parser owner");
 if let Some(actual)=input.failure.or_else(||admission.take_operational_error()){
  if let Some(expression)=expr{crate::setting_drop::drop_expression(expression,None)}return Err(actual)
 }
 if admission.is_stopped(){if let Some(expression)=expr{crate::setting_drop::drop_expression(expression,None)}return Err(admission.checkpoint().err().unwrap_or_else(||std::io::Error::new(std::io::ErrorKind::Other,"native expression operation stopped without a current failure")))}
 let original_simple_expression=if parser.diagnostics.is_empty(){expr.as_ref().and_then(|expr|original_simple_complete(expr,&parser.tokens,parser.original_profile))}else{parser.original_simple_incomplete};
 let exhausted=parser.index==parser.tokens.len()&&parser.expected_term.is_none()&&parser.expected_delimiter.is_none()
  &&parser.input_failure.is_none()&&(input.exhausted||input.cursor.boundary.is_some());
 let complete=if exhausted&&!parser.native_recovered&&!parser.native_deferred{expr.as_ref().map(|root|root.span)}else{None};
 let native_parser_facts=NativeExpressionParserFacts{complete,aggregate_complete:false,exhausted,recovered:parser.native_recovered,deferred:parser.native_deferred};
 Ok(DemandedExpression{native_parser_facts,parsed:ParsedExpr{expr,diagnostics:parser.diagnostics,original_simple_expression,original_input_failure:parser.input_failure,original_input_notices:parser.original_profile.then(||parser.input_notices.finish()),original_constructor_facts:parser.original_profile.then(||parser.constructor_facts.finish())},tokens:parser.tokens,expected_term:parser.expected_term,expected_delimiter:parser.expected_delimiter,lease:input.lease})
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

// Parser-only ownership. No source/header/model authority escapes this owner.
struct ParserExpr<'op> { value:Option<Expr>, nodes:usize, frontier:usize, cleanup:crate::parser_cleanup::ParserCleanup<'op,'op> }
impl<'op> std::ops::Deref for ParserExpr<'op>{type Target=Expr;fn deref(&self)->&Expr{self.value.as_ref().expect("live parser expression")}}
impl<'op> Drop for ParserExpr<'op>{fn drop(&mut self){if let Some(value)=self.value.take(){self.cleanup.drop_expression(value)}}}
impl<'op> ParserExpr<'op>{
 fn into_raw(mut self)->Expr{self.value.take().expect("live parser expression")}
 fn into_default(self,a:Option<&crate::SettingAdmission<'_>>)->Option<Expr>{if let Some(a)=a{if !admitted_drop_shape(&self,a){return None}}Some(self.into_raw())}
 fn set_end(&mut self,end:usize){self.value.as_mut().expect("live parser expression").span.end=end;}
}
struct ParserArgs<'op> { values:Vec<Expr>, nodes:usize, frontier:usize, cleanup:crate::parser_cleanup::ParserCleanup<'op,'op> }
impl<'op> ParserArgs<'op>{
 fn new(cleanup:crate::parser_cleanup::ParserCleanup<'op,'op>)->Self{Self{values:Vec::new(),nodes:0,frontier:0,cleanup}}
 fn len(&self)->usize{self.values.len()}fn is_empty(&self)->bool{self.values.is_empty()}
 fn into_raw(mut self)->Vec<Expr>{std::mem::take(&mut self.values)}
 fn push(&mut self,value:ParserExpr<'op>,a:Option<&crate::SettingAdmission<'_>>)->std::io::Result<()>{
  let nodes=self.nodes.checked_add(value.nodes).ok_or(std::io::ErrorKind::OutOfMemory)?;
  let frontier=self.values.len().checked_add(value.frontier).map(|next|self.frontier.max(next)).ok_or(std::io::ErrorKind::OutOfMemory)?;
  self.cleanup.ensure_nodes(a,frontier)?;self.values.try_reserve(1).map_err(|error|std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))?;self.values.push(value.into_raw());self.nodes=nodes;self.frontier=frontier;Ok(())
 }
}
impl<'op> Drop for ParserArgs<'op>{fn drop(&mut self){for value in self.values.drain(..){self.cleanup.drop_expression(value)}}}
struct ParserFields<'op> { values:Vec<(String,Expr)>, nodes:usize, frontier:usize, cleanup:crate::parser_cleanup::ParserCleanup<'op,'op> }
impl<'op> ParserFields<'op>{
 fn new(cleanup:crate::parser_cleanup::ParserCleanup<'op,'op>)->Self{Self{values:Vec::new(),nodes:0,frontier:0,cleanup}}
 fn into_raw(mut self)->Vec<(String,Expr)>{std::mem::take(&mut self.values)}
 fn push(&mut self,name:String,value:ParserExpr<'op>,a:Option<&crate::SettingAdmission<'_>>)->std::io::Result<()>{
  let nodes=self.nodes.checked_add(value.nodes).ok_or(std::io::ErrorKind::OutOfMemory)?;
  let frontier=self.values.len().checked_add(value.frontier).map(|next|self.frontier.max(next)).ok_or(std::io::ErrorKind::OutOfMemory)?;
  self.cleanup.ensure_nodes(a,frontier)?;self.values.try_reserve(1).map_err(|error|std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))?;self.values.push((name,value.into_raw()));self.nodes=nodes;self.frontier=frontier;Ok(())
 }
}
impl<'op> Drop for ParserFields<'op>{fn drop(&mut self){for(_,value)in self.values.drain(..){self.cleanup.drop_expression(value)}}}

#[derive(Clone,Copy)]
struct PrattContext { min_bp:u8, mode:PostfixMode, scoped:bool }
enum PrattContinuation<'op> {
    Group { span:Span, prefix:usize, context:PrattContext, then_depth:usize },
    Binary { lhs:ParserExpr<'op>, op:String, context:PrattContext },
    Then { condition:ParserExpr<'op>, context:PrattContext, then_depth:usize },
    Else { condition:ParserExpr<'op>, then_value:ParserExpr<'op>, context:PrattContext, then_depth:usize },
}

struct ExprParser<'op,'input> {
    cleanup:crate::parser_cleanup::ParserCleanup<'op,'op>,
    admission: Option<&'op crate::SettingAdmission<'op>>,
    tokens: Vec<Token>,
    index: usize,
    ternary_then_depth: usize,
    original_simple_incomplete:Option<OriginalSimpleExpression>,
    // Actual generic-ident prefix branch, never reconstructed from an IR tree.
    original_scope_prefix:Option<usize>,
    original_profile:bool,
    native_recovered:bool,
    native_deferred:bool,
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

impl<'op,'input> ExprParser<'op,'input> {
    fn cleanup_error(&mut self,error:std::io::Error){let error=self.admission.and_then(|a|a.take_operational_error()).unwrap_or(error);self.original_operational(error)}
    // release_child_roots pushes children in source order and pops LIFO.
    // While child i drains, exactly i earlier sibling roots remain pending.
    fn cleanup_frontier(&mut self,children:&[usize])->Option<usize>{
        let frontier=children.iter().enumerate().try_fold(1usize,|bound,(i,child)|i.checked_add(*child).map(|n|bound.max(n)));
        let Some(frontier)=frontier else{self.cleanup_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"parser cleanup frontier overflow"));return None};Some(frontier)
    }
    fn node_count(&mut self,children:&[usize],frontier:usize)->Option<usize>{
        let nodes=children.iter().try_fold(1usize,|n,child|n.checked_add(*child));
        let Some(nodes)=nodes else{self.cleanup_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"parser cleanup node count overflow"));return None};
        if let Err(error)=self.cleanup.ensure_nodes(self.admission,frontier){self.cleanup_error(error);return None}Some(nodes)
    }
    fn leaf(&mut self,value:Expr)->Option<ParserExpr<'op>>{let frontier=1;let nodes=self.node_count(&[],frontier)?;Some(ParserExpr{value:Some(value),nodes,frontier,cleanup:self.cleanup.clone()})}
    fn unary_node(&mut self,child:ParserExpr<'op>,make:impl FnOnce(Expr)->Expr)->Option<ParserExpr<'op>>{let frontier=child.frontier;let nodes=self.node_count(&[child.nodes],frontier)?;let value=make(child.into_raw());Some(ParserExpr{value:Some(value),nodes,frontier,cleanup:self.cleanup.clone()})}
    fn binary_node(&mut self,lhs:ParserExpr<'op>,rhs:ParserExpr<'op>,make:impl FnOnce(Expr,Expr)->Expr)->Option<ParserExpr<'op>>{let frontier=self.cleanup_frontier(&[lhs.frontier,rhs.frontier])?;let nodes=self.node_count(&[lhs.nodes,rhs.nodes],frontier)?;let value=make(lhs.into_raw(),rhs.into_raw());Some(ParserExpr{value:Some(value),nodes,frontier,cleanup:self.cleanup.clone()})}
    fn conditional_node(&mut self,condition:ParserExpr<'op>,then_value:ParserExpr<'op>,else_value:ParserExpr<'op>,make:impl FnOnce(Expr,Expr,Expr)->Expr)->Option<ParserExpr<'op>>{let frontier=self.cleanup_frontier(&[condition.frontier,then_value.frontier,else_value.frontier])?;let nodes=self.node_count(&[condition.nodes,then_value.nodes,else_value.nodes],frontier)?;let value=make(condition.into_raw(),then_value.into_raw(),else_value.into_raw());Some(ParserExpr{value:Some(value),nodes,frontier,cleanup:self.cleanup.clone()})}
    fn call_node(&mut self,callee:ParserExpr<'op>,args:ParserArgs<'op>,end:usize)->Option<ParserExpr<'op>>{let frontier=self.cleanup_frontier(&[callee.frontier,args.frontier])?;let nodes=self.node_count(&[callee.nodes,args.nodes],frontier)?;let start=callee.span.start;let value=Expr{span:Span::new(start,end),kind:ExprKind::Call{callee:Box::new(callee.into_raw()),args:args.into_raw()}};Some(ParserExpr{value:Some(value),nodes,frontier,cleanup:self.cleanup.clone()})}
    fn object_node(&mut self,object:ParserExpr<'op>,fields:ParserFields<'op>,end:usize)->Option<ParserExpr<'op>>{let frontier=self.cleanup_frontier(&[object.frontier,fields.frontier])?;let nodes=self.node_count(&[object.nodes,fields.nodes],frontier)?;let start=object.span.start;let value=Expr{span:Span::new(start,end),kind:ExprKind::ObjectInitializer{object:Box::new(object.into_raw()),fields:fields.into_raw()}};Some(ParserExpr{value:Some(value),nodes,frontier,cleanup:self.cleanup.clone()})}
    fn push_arg(&mut self,args:&mut ParserArgs<'op>,value:ParserExpr<'op>)->Option<()>{if let Err(error)=args.push(value,self.admission){self.cleanup_error(error);return None}Some(())}
    fn push_field(&mut self,fields:&mut ParserFields<'op>,name:String,value:ParserExpr<'op>)->Option<()>{if let Err(error)=fields.push(name,value,self.admission){self.cleanup_error(error);return None}Some(())}

    // Called only by this SAME literal production after it validated and
    // consumed the actual InterpPart/End delimiter. Not whole-input EOF.
    fn native_literal_child_facts(&self,child:&Expr)->NativeExpressionParserFacts{
     let complete=if !self.native_recovered&&!self.native_deferred&&self.input_failure.is_none()
       &&self.expected_term.is_none()&&self.expected_delimiter.is_none()
       &&self.admission.is_some_and(|a|!a.is_stopped()){Some(child.span)}else{None};
     NativeExpressionParserFacts{complete,aggregate_complete:false,exhausted:false,
       recovered:self.native_recovered,deferred:self.native_deferred}
    }
    fn original_operational(&mut self,error:std::io::Error){if let Some(input)=&mut self.demand{if input.failure.is_none(){input.failure=Some(error)}input.stopped=true;}else if let Some(a)=self.admission{a.forward_operational_error(error);}}
    fn primitive_mode(&mut self,mode:NativePrimitiveClauseMode)->Option<NativePrimitiveClauseMode>{match self.demand.as_mut(){Some(input)=>match input.cursor.source.set_original_primitive_clause_mode(mode){Ok(previous)=>Some(previous),Err(error)=>{self.original_operational(error);None}},None=>Some(NativePrimitiveClauseMode::default())}}
    fn original_delimiter_at(&mut self,expected:NativeDelimiterExpected,token:Option<Span>){if !self.original_profile||self.expected_delimiter.is_some()||self.expected_term.is_some()||self.input_failure.is_some(){return}self.expected_delimiter=Some(NativeDelimiterExpectation{token,expected});}
    fn original_delimiter(&mut self,expected:NativeDelimiterExpected){if !self.original_profile||self.expected_delimiter.is_some()||self.expected_term.is_some()||self.input_failure.is_some(){return}let token=self.peek().map(|token|token.span);self.original_delimiter_at(expected,token);}
    fn original_empty_call_slot(&mut self,start:usize){if !self.original_profile||self.expected_delimiter.is_some()||self.input_failure.is_some(){return}let Some(term)=self.expected_term else{return};let empty=match term.token_span(){None=>self.index==start,Some(span)=>self.index==start+1&&self.tokens.get(start).is_some_and(|token|token.span==span)};if empty{self.expected_delimiter=Some(NativeDelimiterExpectation{token:term.token_span(),expected:NativeDelimiterExpected::EmptyCall});}}

    fn original_implicit_new(&mut self,at:Span,has_args:bool)->Option<()>{self.native_deferred=true;if !self.original_profile{return Some(())}let Some(a)=self.admission else{self.original_operational(std::io::ErrorKind::InvalidInput.into());return None};match self.constructor_facts.push(at,has_args,a){Ok(())=>Some(()),Err(error)=>{self.original_operational(error);None}}}
    fn primitive_notice(&mut self,at:Span,kind:crate::OriginalInputNoticeKind)->Option<()>{self.native_recovered=true;let Some(a)=self.admission else{self.original_operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original primitive parser event lacks native admission"));return None};let result=(||{self.input_notices.push(at,kind,a)?;if let Some(input)=self.demand.as_mut(){let occurrence=input.occurrences.iter().find(|row|row.span()==at).copied().ok_or(std::io::ErrorKind::InvalidData)?;input.cursor.source.original_primitive_notice(occurrence,kind)?;}Ok(())})();match result{Ok(())=>Some(()),Err(error)=>{self.original_operational(error);None}}}
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
    fn named_call_node(&mut self,name:String,span:Span,end:usize,args:ParserArgs<'op>)->Option<ParserExpr<'op>>{let callee=self.leaf(Expr{span,kind:ExprKind::Ident(name)})?;self.call_node(callee,args,end)}
    fn scoped_name_node(&mut self,name:Token,span:Span)->Option<ParserExpr<'op>>{let end=name.span.end;let child=self.leaf(Expr{span:name.span,kind:ExprKind::Ident(name.text)})?;self.unary_node(child,|child|Expr{span:Span::new(span.start,end),kind:ExprKind::Unary{op:"::".into(),value:Box::new(child)}})}
    fn original_primitive_clauses(&mut self,mut lhs:ParserExpr<'op>,closing:Span)->Option<ParserExpr<'op>>{
      let(input,locate,start,argument_in,too_many)=match &lhs.kind{ExprKind::Call{callee,args}=>match &callee.kind{ExprKind::Ident(name)if name=="input"=>(true,false,callee.span,false,false),ExprKind::Ident(name)if name=="locate"=>(false,true,callee.span,args.first().is_some_and(|arg|matches!(&arg.kind,ExprKind::Binary{op,..}if op=="in")),args.len()>1),_=>return Some(lhs)},_=>return Some(lhs)};
      let previous=self.primitive_mode(NativePrimitiveClauseMode{as_clause:input,in_clause:true})?;
      let result=(||{
       if locate&&argument_in{self.primitive_notice(closing,crate::OriginalInputNoticeKind::LocateInArgument)?;}
       if input&&self.take_text("as").is_some(){let(types,end)=self.original_input_types(true,previous)?;lhs=self.unary_node(lhs,|lhs|Expr{span:Span::new(lhs.span.start,end),kind:ExprKind::TypeFilter{value:Box::new(lhs),types}})?;}
       self.primitive_mode(NativePrimitiveClauseMode{as_clause:previous.as_clause,in_clause:true})?;
       if self.take_text("in").is_some(){
        if locate&&too_many{self.primitive_notice(start,crate::OriginalInputNoticeKind::LocateTupleIn)?;}
        self.primitive_mode(NativePrimitiveClauseMode{as_clause:input,in_clause:true})?;
        let container=self.expression(0)?;lhs=self.binary_node(lhs,container,|lhs,container|Expr{span:Span::new(lhs.span.start,container.span.end),kind:ExprKind::Binary{op:"in".into(),lhs:Box::new(lhs),rhs:Box::new(container)}})?;
        if input{if let Some(marker)=self.take_text("as"){self.primitive_notice(marker.span,crate::OriginalInputNoticeKind::InPrecedesAs)?;let(_,end)=self.original_input_types(false,previous)?;lhs.set_end(end);}}
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
        self.native_recovered=true;
        self.diagnostics.push(Diagnostic {
            span,
            kind: DiagnosticKind::Expression,
            message: message.into(),
        });
    }

    fn expression(&mut self, min_bp: u8) -> Option<ParserExpr<'op>> {
        let admission = self.admission;
        let _frame = match admission {
            Some(admission) => Some(admission.parser_frame().ok()?),
            None => None,
        };
        self.expression_driver(min_bp,None,PostfixMode::Expression,false)
    }

    // Reuse the primary postfix grammar, but terminate a constructor target
    // after its FIRST argument list. Later follows bind to the new object.
    fn expression_from(&mut self,min_bp:u8,lhs:ParserExpr<'op>,mode:PostfixMode,scoped:bool)->Option<ParserExpr<'op>>{
        self.expression_driver(min_bp,Some(lhs),mode,scoped)
    }
    fn expression_driver(&mut self,min_bp:u8,initial:Option<ParserExpr<'op>>,mode:PostfixMode,scoped:bool)->Option<ParserExpr<'op>>{
        let previous=self.ternary_then_depth;
        let result=self.expression_driver_inner(min_bp,initial,mode,scoped);
        self.ternary_then_depth=previous;
        result
    }
    // ONE existing Pratt producer. Logical Group/binary/conditional returns
    // live in paid heap continuations, never additional recursive Rust frames.
    fn expression_driver_inner(&mut self,mut min_bp:u8,mut ready:Option<ParserExpr<'op>>,mut mode:PostfixMode,mut scoped:bool)->Option<ParserExpr<'op>>{
        let mut pending=crate::pratt_continuations::PrattContinuations::new(self.admission);
        let mut failed=false;
        'driver: loop {
            if self.pratt_operationally_stopped(){if let Some(value)=ready.take(){drop(value);}return None}
            let mut complete=false;
            if failed {
                let (value,context)=self.recover_pratt_failure(&mut pending)?;
                ready=Some(value);min_bp=context.min_bp;mode=context.mode;scoped=context.scoped;complete=true;failed=false;
            }
            while ready.is_none(){
                let prefix=self.index;
                if self.peek_role(NativeExpressionReadRole::Term).is_some_and(|token|token.kind==TokenKind::Punctuation&&token.text=="("){
                    let open=self.take_role(NativeExpressionReadRole::Term)?;
                    if self.original_profile{if let Some(close)=self.take_text(")"){
                        self.primitive_notice(close.span,crate::OriginalInputNoticeKind::EmptyParentheses)?;
                        ready=Some(self.leaf(Expr{span:Span::new(open.span.start,close.span.end),kind:ExprKind::Literal(crate::LiteralText::at("null".into(),open.span.start))})?);
                        scoped=self.original_scope_prefix==Some(prefix);break;
                    }}
                    let context=PrattContext{min_bp,mode,scoped};
                    pending.push(PrattContinuation::Group{span:open.span,prefix,context,then_depth:self.ternary_then_depth}).map_err(|error|self.original_operational(error)).ok()?;
                    min_bp=0;mode=PostfixMode::Expression;self.ternary_then_depth=0;continue;
                }
                if let Some(value)=self.prefix(){ready=Some(value);scoped=self.original_scope_prefix==Some(prefix);break}
                failed=true;continue 'driver;
            }
            let mut lhs=ready.take().unwrap();
            if !complete {loop {
            if self.admission.is_some_and(|a|a.checkpoint().is_err()){return None}
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
                    let mut fields = ParserFields::new(self.cleanup.clone());
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
                        self.push_field(&mut fields,name.text,value)?;
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
                    lhs = self.object_node(lhs,fields,end)?;
                    continue;
                }
                if self.original_profile&&mode==PostfixMode::Expression&&self.peek().is_some_and(|token|token.kind==TokenKind::Operator&&matches!(token.text.as_str(),"++"|"--")){let token=match self.take(){Some(token)=>token,None=>{drop(lhs);failed=true;ready=None;continue 'driver}};let op=if token.text=="++"{"post++"}else{"post--"};lhs=self.unary_node(lhs,|lhs|Expr{span:Span::new(lhs.span.start,token.span.end),kind:ExprKind::Unary{op:op.into(),value:Box::new(lhs)}})?;continue}
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
                        lhs = self.unary_node(lhs,|lhs|Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Unary {
                                op: op.into(),
                                value: Box::new(lhs),
                            },
                        })?;
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
                        lhs = self.unary_node(lhs,|lhs|Expr {
                            span: Span::new(lhs.span.start, selector_end),
                            kind: ExprKind::SafeMember {
                                object: Box::new(lhs),
                                selector,
                                via_colon: matches!(separator.text.as_str(),":"|"?:"),
                            },
                        })?;
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
                            lhs = self.binary_node(lhs,index,|lhs,index|Expr {
                                span: Span::new(lhs.span.start, end),
                                kind: ExprKind::SafeIndex {
                                    object: Box::new(lhs),
                                    index: Box::new(index),
                                },
                            })?;
                        }
                    }
                    continue;
                }
                if let Some(open) = self.take_text("(") {
                    scoped=false;
                    let original_pick = self.original_profile && mode == PostfixMode::Expression
                        && matches!(&lhs.kind, ExprKind::Ident(name) if name == "pick");
                    let mut args = ParserArgs::new(self.cleanup.clone());
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
                                    drop(lhs);failed=true;ready=None;continue 'driver;
                                }
                                let at = comma.span.start;
                                let slot=self.leaf(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                })?;self.push_arg(&mut args,slot)?;
                                continue;
                            }
                            let argument_start=self.index;
                            let Some(mut arg) = self.call_argument_expression() else {
                                self.original_empty_call_slot(argument_start);
                                self.error(open.span, "missing call argument");
                                break;
                            };
                            if self.take_text(";").is_some() {
                                let Some(value) = self.expression_nested(0) else {
                                    self.error(arg.span, "missing weighted pick value");
                                    break;
                                };
                                arg = self.binary_node(arg,value,|arg,value|Expr {
                                    span: Span::new(arg.span.start, value.span.end),
                                    kind: ExprKind::Binary {
                                        op: ";".into(),
                                        lhs: Box::new(arg),
                                        rhs: Box::new(value),
                                    },
                                })?;
                            }
                            self.push_arg(&mut args,arg)?;
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
                    lhs = self.call_node(lhs,args,end)?;
                    if mode != PostfixMode::Expression {
                        break;
                    }
                    if self.original_profile{
                        let Some(closing_span)=closing_span else{drop(lhs);failed=true;ready=None;continue 'driver};
                        match self.original_primitive_clauses(lhs,closing_span){Some(value)=>lhs=value,None=>{failed=true;ready=None;continue 'driver}}
                        continue;
                    }
                    // `in` is an optional locate clause, so it belongs inside
                    // an enclosing prefix operator (`!locate(T) in L`).
                    if matches!(&lhs.kind, ExprKind::Call { callee, args }
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate")
                            && args.len() <= 1)
                        && self.take_text("in").is_some()
                    {
                        let container=match self.expression(8){Some(value)=>value,None=>{drop(lhs);failed=true;ready=None;continue 'driver}};
                        lhs = self.binary_node(lhs,container,|lhs,container|Expr {
                            span: Span::new(lhs.span.start, container.span.end),
                            kind: ExprKind::Binary {
                                op: "in".into(),
                                lhs: Box::new(lhs),
                                rhs: Box::new(container),
                            },
                        })?;
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
                        lhs = self.binary_node(lhs,index,|lhs,index|Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Index {
                                object: Box::new(lhs),
                                index: Box::new(index),
                            },
                        })?;
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
                    lhs = self.unary_node(lhs,|lhs|Expr {
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
                    })?;
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
                lhs = self.unary_node(lhs,|lhs|Expr {
                    span: Span::new(lhs.span.start, end),
                    kind: ExprKind::TypeFilter {
                        value: Box::new(lhs),
                        types,
                    },
                })?;
                continue;
            }
            if min_bp <= 3 && self.take_text("?").is_some() {
                let context=PrattContext{min_bp,mode,scoped};let then_depth=self.ternary_then_depth;
                pending.push(PrattContinuation::Then{condition:lhs,context,then_depth}).map_err(|error|self.original_operational(error)).ok()?;
                self.ternary_then_depth+=1;min_bp=0;mode=PostfixMode::Expression;ready=None;continue 'driver;
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
                    self.original_simple_incomplete=Some(OriginalSimpleExpression{kind:OriginalSimpleKind::MissingArithmeticOperand,span:Span::new(lhs.span.start,self.tokens[original_operator].span.end),operator:Some(self.tokens[original_operator].span),original_profile:self.original_profile,bare_postfix_read:false,initializer_assignment:false});
                }
                self.native_recovered=true;
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
            let context=PrattContext{min_bp,mode,scoped};
            pending.push(PrattContinuation::Binary{lhs,op,context}).map_err(|error|self.original_operational(error)).ok()?;
            min_bp=right_bp;mode=PostfixMode::Expression;ready=None;continue 'driver;
            }}
            loop {
                if self.pratt_operationally_stopped(){drop(lhs);return None}
                match pending.pop(){
                None=>return Some(lhs),
                Some(PrattContinuation::Binary{lhs:prior,op,context})=>{
                    lhs=self.binary_node(prior,lhs,|prior,lhs|Expr{span:Span::new(prior.span.start,lhs.span.end),kind:ExprKind::Binary{op,lhs:Box::new(prior),rhs:Box::new(lhs)}})?;
                    min_bp=context.min_bp;mode=context.mode;scoped=false;ready=Some(lhs);continue 'driver;
                }
                Some(PrattContinuation::Group{span,prefix,context,then_depth})=>{
                    let close=self.take_text(")");
                    if self.pratt_operationally_stopped(){drop(lhs);return None}
                    let end=match close{Some(token)=>token.span.end,None=>{
                        self.original_delimiter(NativeDelimiterExpected::GroupRightParen);
                        if self.pratt_operationally_stopped(){drop(lhs);return None}
                        let eof=self.peek().is_none();
                        if self.pratt_operationally_stopped(){drop(lhs);return None}
                        if eof&&self.diagnostics.is_empty(){self.native_recovered=true;self.diagnostics.push(Diagnostic{span,kind:DiagnosticKind::IncompleteExpression,message:"unclosed group".into()});}else{self.error(span,"unclosed group");}
                        lhs.span.end
                    }};
                    lhs=self.unary_node(lhs,|lhs|Expr{span:Span::new(span.start,end),kind:ExprKind::Group(Box::new(lhs))})?;
                    min_bp=context.min_bp;mode=context.mode;scoped=self.original_scope_prefix==Some(prefix);self.ternary_then_depth=then_depth;ready=Some(lhs);continue 'driver;
                }
                Some(PrattContinuation::Then{condition,context,then_depth})=>{
                    self.ternary_then_depth=then_depth;
                    let colon=self.take_text(":");
                    if self.pratt_operationally_stopped(){drop(lhs);return None}
                    if colon.is_none(){self.original_delimiter(NativeDelimiterExpected::ConditionalColon);if self.pratt_operationally_stopped(){drop(lhs);return None}self.error(condition.span,"ternary expression requires :");lhs=condition;min_bp=context.min_bp;mode=context.mode;scoped=context.scoped;continue;}
                    pending.push(PrattContinuation::Else{condition,then_value:lhs,context,then_depth}).map_err(|error|self.original_operational(error)).ok()?;
                    min_bp=2;mode=PostfixMode::Expression;ready=None;continue 'driver;
                }
                Some(PrattContinuation::Else{condition,then_value,context,then_depth})=>{
                    lhs=self.conditional_node(condition,then_value,lhs,|condition,then_value,lhs|Expr{span:Span::new(condition.span.start,lhs.span.end),kind:ExprKind::Conditional{condition:Box::new(condition),then_value:Box::new(then_value),else_value:Box::new(lhs)}})?;
                    min_bp=context.min_bp;mode=context.mode;scoped=context.scoped;self.ternary_then_depth=then_depth;ready=Some(lhs);continue 'driver;
                }
            }}
        }
    }

    fn pratt_operationally_stopped(&self)->bool{
        self.admission.is_some_and(|a|a.is_stopped()) || self.demand.as_ref().is_some_and(|input|input.failure.is_some())
    }
    // Reproduce the prior recursive Option unwind without a second parser:
    // Group/conditional failures propagate, only a binary RHS recovers lhs.
    fn recover_pratt_failure(&mut self,pending:&mut crate::pratt_continuations::PrattContinuations<'_, '_,PrattContinuation<'op>>)->Option<(ParserExpr<'op>,PrattContext)>{
        loop {
            if self.pratt_operationally_stopped(){return None}
            match pending.pop(){
            Some(PrattContinuation::Binary{lhs,op,context})=>{self.error(lhs.span,format!("missing right operand for {op}"));return Some((lhs,context));}
            Some(PrattContinuation::Group{then_depth,..})|Some(PrattContinuation::Then{then_depth,..})|Some(PrattContinuation::Else{then_depth,..})=>{self.ternary_then_depth=then_depth;}
            None=>return None,
        }}
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

    // A complete Original template argument already has a paid literal owner
    // and iterative child teardown. Do not re-enter expression()/prefix() just
    // to return that finished literal. All embedded expressions keep real frames.
    fn call_argument_expression(&mut self)->Option<ParserExpr<'op>>{
        // The call loop has already issued this token while checking separators.
        // Never pull a future token to select the resource-only continuation.
        if !self.original_profile || self.tokens.get(self.index).is_none_or(|token|token.kind!=TokenKind::Interpolation){return self.expression_nested(0)}
        let previous=self.ternary_then_depth;
        self.ternary_then_depth=0;
        let result=(||{
            let a=self.admission?;
            a.checkpoint().ok()?; // before consuming the already-issued Term
            let token=self.take_role(NativeExpressionReadRole::Term)?;
            let value=self.original_interpolation(token)?;
            if a.checkpoint().is_err(){return None}
            if self.peek().is_none_or(|token|matches!(token.text.as_str(),","|")"|";")){return Some(value)}
            // A real expression follower needs its own actual argument frame.
            // Acquire it before following a call/index/operator recursively.
            let _frame=match a.parser_frame(){Ok(frame)=>frame,Err(_)=>{drop(value);return None}};
            self.expression_from(0,value,PostfixMode::Expression,false)
        })();
        self.ternary_then_depth=previous;
        result
    }

    fn expression_nested(&mut self, min_bp: u8) -> Option<ParserExpr<'op>> {
        let previous = self.ternary_then_depth;
        self.ternary_then_depth = 0;
        let result = self.expression(min_bp);
        self.ternary_then_depth = previous;
        result
    }

    fn original_prefab_tail(&mut self,start:&str,span:Span,namespace_dot:bool)->Option<ParserExpr<'op>>{
        let mut path=String::from(start);let mut end=span.end;let mut expects_name=true;
        while let Some(next)=self.peek_role(if expects_name{NativeExpressionReadRole::PathName{adjacent_to:end}}else{NativeExpressionReadRole::Follower}){if next.span.start!=end{break}if next.kind==TokenKind::Ident||next.text=="/"{expects_name=next.text=="/";path.push_str(&next.text);end=next.span.end;self.index+=1;}else if namespace_dot&&next.text=="."&&self.peek_at_role(self.index+1,NativeExpressionReadRole::Identifier).is_some_and(|kind|matches!(kind.text.as_str(),"proc"|"verb"|"var"))&&self.peek_at(self.index+2).is_some_and(|slash|slash.text=="/"){path.push('.');path.push_str(&self.tokens[self.index+1].text);end=self.tokens[self.index+1].span.end;self.index+=2;expects_name=false;}else{break}}
        if path==start&&start!="/"{self.error(span,format!("expected type path after {start}"));None}else{if path!="/"{path.truncate(path.trim_end_matches('/').len());}Some(self.leaf(Expr{span:Span::new(span.start,end),kind:ExprKind::TypePath(path)})?)}
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
        match outcome{Ok(value)=>Some(value),Err(actual)=>{if let Some(input)=self.demand.as_mut(){if input.failure.is_none(){input.failure=Some(actual)}input.stopped=true;}else if let Some(a)=admission{a.forward_operational_error(actual)}None}}
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
    fn original_interpolation(&mut self,begin:Token)->Option<ParserExpr<'op>>{
        let a=self.admission?;let result=(||{
            let data=self.original_template_part_at(self.index-1)?;
            if !matches!(data.value(),crate::OriginalTokenValue::InterpBegin(_)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual template prefix is not InterpBegin"))}
            let mut builder=crate::literal::OriginalTemplateBuilder::new_with_cleanup(a,self.cleanup.clone())?;builder.push_with_native_facts(data,begin.span,None,&[],None,false,a)?;
            let end=loop{
                a.checkpoint()?;let child_start=self.index;
                let Some(next)=self.peek()else{self.error(begin.span,"expected interpolation part or end");return Ok(None)};
                let empty=if next.kind==TokenKind::Interpolation{matches!(self.original_template_part_at(self.index)?.value(),crate::OriginalTokenValue::InterpPart(_)|crate::OriginalTokenValue::InterpEnd(_))}else{false};
                let child=if empty{None}else{
                    let Some(child)=self.expression_nested(0)else{return Ok(None)};Some(child)
                };
                let child_end=self.index;
                let Some(boundary)=self.take()else{if let Some(child)=child{drop(child)}self.error(begin.span,"expected interpolation part or end");return Ok(None)};
                if boundary.kind!=TokenKind::Interpolation{if let Some(child)=child{drop(child)}self.error(boundary.span,"expected interpolation part or end");return Ok(None)}
                let data=match self.original_template_part_at(self.index-1){Ok(data)=>data,Err(error)=>{if let Some(child)=child{drop(child)}return Err(error)}};
                let ended=match data.value(){crate::OriginalTokenValue::InterpPart(_)=>false,crate::OriginalTokenValue::InterpEnd(_)=>true,_=>{if let Some(child)=child{drop(child)}self.error(boundary.span,"expected interpolation part or end");return Ok(None)}};
                // SAME validated InterpPart/End closes this optional child role.
                let native=child.as_ref().map(|child|self.native_literal_child_facts(child));
                let child_tokens=&self.tokens[child_start..child_end];
                builder.push_with_native_facts(data,boundary.span,child.map(ParserExpr::into_raw),child_tokens,native,empty,a)?;
                if ended{break boundary.span.end}
            };
            let span=Span::new(begin.span.start,end);
            let source=if let Some(input)=self.demand.as_ref(){input.cursor.source.original_template_source(span)?.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual typed template source range is not issued"))?}else{
                let(source,current_offset,source_origin)=self.original_source.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual archived template input borrow is not issued"))?;
                let start=span.start.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).ok_or(std::io::ErrorKind::InvalidInput)?;let end=span.end.checked_sub(current_offset).and_then(|n|n.checked_add(source_origin)).ok_or(std::io::ErrorKind::InvalidInput)?;
                source.get(start..end).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"archived template exceeds its actual parser input"))?
            };
            let value=builder.finish(source,span.start,a)?;
            Ok(self.leaf(Expr{span,kind:ExprKind::Literal(value)}))
        })();
        match result{Ok(root)=>root,Err(error)=>{self.original_operational(error);None}}
    }

    fn prefix(&mut self) -> Option<ParserExpr<'op>> {
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
                self.scoped_name_node(name,span)
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
                Some(self.named_call_node(token.text,span,end,ParserArgs::new(self.cleanup.clone()))?)
            }
            TokenKind::Ident if token.text == "new" => {
                if self.peek().is_none() {
                    self.original_implicit_new(span,false)?;
                    return Some(self.named_call_node("new".into(),span,span.end,ParserArgs::new(self.cleanup.clone()))?);
                }
                if let Some(open) = self.take_text("(") {
                    self.original_implicit_new(span,true)?;
                    let mut args = ParserArgs::new(self.cleanup.clone());
                    if self.peek().is_some_and(|next| next.text != ")") {
                        loop {
                            if self.peek().is_some_and(|next| next.text == ",") {
                                let at = self.peek().unwrap().span.start;
                                let slot=self.leaf(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                })?;self.push_arg(&mut args,slot)?;
                                self.take();
                                continue;
                            }
                            let Some(arg) = self.expression_nested(0) else {
                                self.error(open.span, "missing constructor argument");
                                break;
                            };
                            self.push_arg(&mut args,arg)?;
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
                    return Some(self.named_call_node("new".into(),span,end,args)?);
                }
                let target = match self.peek() {
                    Some(next) if next.kind == TokenKind::Ident => {
                        let target = self.take().unwrap();
                        Some((
                            self.leaf(Expr {
                                span: target.span,
                                kind: ExprKind::Ident(target.text),
                            })?,
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
                    return Some(self.named_call_node("new".into(),span,span.end,ParserArgs::new(self.cleanup.clone()))?);
                };
                let value = self.expression_from(24, target, mode,false)?;
                Some(self.unary_node(value,|value|Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })?)
            }
            TokenKind::Ident if expression_null_identifier(&token.text) => Some(self.leaf(Expr {
                span,
                kind: ExprKind::Literal(crate::LiteralText::at(token.text, span.start)),
            })?),
            TokenKind::Ident => {self.original_scope_prefix=Some(self.index-1);Some(self.leaf(Expr {span,kind: ExprKind::Ident(token.text)})?)},
            TokenKind::Interpolation => self.original_interpolation(token),
            TokenKind::Number | TokenKind::String | TokenKind::Resource => self.literal_from_token(token).and_then(|value|self.leaf(Expr {span,kind:ExprKind::Literal(value)})),
            TokenKind::Operator if self.original_profile&&token.text=="+"=>{if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:Some(span)})}self.error(span,"Original unary plus is not a term");None},
            TokenKind::Operator if self.original_profile&&matches!(token.text.as_str(),"++"|"--")=>{let value=self.expression(26)?;Some(self.unary_node(value,|value|Expr{span:Span::new(span.start,value.span.end),kind:ExprKind::Unary{op:if token.text=="++"{"pre++".into()}else{"pre--".into()},value:Box::new(value)}})?)},
            TokenKind::Operator if matches!(token.text.as_str(), "-" | "+" | "!" | "~" | "*" | "&") => {
                if matches!(token.text.as_str(), "-" | "+")
                    && self.peek().is_some_and(|next| {
                        next.text == token.text && next.span.start == token.span.end
                    })
                {
                    self.take();
                    if self.peek().is_none() && self.diagnostics.is_empty() {
                    if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:None});}
                        self.native_recovered=true;
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
                    return Some(self.unary_node(value,|value|Expr {
                        span: Span::new(span.start, value.span.end),
                        kind: ExprKind::Unary {
                            op: if token.text == "+" {
                                "pre++".into()
                            } else {
                                "pre--".into()
                            },
                            value: Box::new(value),
                        },
                    })?);
                }
                if self.peek().is_none() && self.diagnostics.is_empty() {
                    if self.expected_term.is_none(){self.expected_term=Some(NativeTermExpectation{token:None});}
                    self.native_recovered=true;
        self.diagnostics.push(Diagnostic {
                        span,
                        kind: DiagnosticKind::IncompleteExpression,
                        message: format!("missing operand for unary {}", token.text),
                    });
                    return None;
                }
                let value = self.expression(26)?;
                Some(self.unary_node(value,|value|Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })?)
            }
            TokenKind::Punctuation if token.text == "(" => {
                if self.original_profile{if let Some(close)=self.take_text(")"){self.primitive_notice(close.span,crate::OriginalInputNoticeKind::EmptyParentheses)?;return Some(self.leaf(Expr{span:Span::new(span.start,close.span.end),kind:ExprKind::Literal(crate::LiteralText::at("null".into(),span.start))})?);}}
                let value = self.expression_nested(0)?;
                let end = self.take_text(")").map_or_else(
                    || {
                        self.original_delimiter(NativeDelimiterExpected::GroupRightParen);
                        if self.peek().is_none() && self.diagnostics.is_empty() {
                            self.native_recovered=true;
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
                Some(self.unary_node(value,|value|Expr {
                    span: Span::new(span.start, end),
                    kind: ExprKind::Group(Box::new(value)),
                })?)
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
                Some(self.leaf(Expr { span, kind: ExprKind::Ident("..".into()) })?)
            }
            TokenKind::Punctuation if token.text == "." => {
                if let Some(second) = self.take_text(".") {
                    Some(self.leaf(Expr {
                        span: Span::new(span.start, second.span.end),
                        kind: ExprKind::Ident("..".into()),
                    })?)
                } else if self.peek().is_some_and(|next| next.kind==TokenKind::Ident&&next.text!="in")
                {
                    // Pinned lexer reserves In as punctuation. Native span
                    // transport may spell that same keyword with Ident kind;
                    // it cannot turn bare Dot followed by In into a prefab.
                    self.original_prefab_tail(".",span,false)
                } else {
                    Some(self.leaf(Expr {
                        span,
                        kind: ExprKind::Ident(".".into()),
                    })?)
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
        for (op, l, r) in EXPRESSION_BINARY_OPS {
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
 parse_expression_with_primary_tokens_and_native_facts(source,admission).map(|(parsed,tokens,_)|(parsed,tokens))
}
pub(crate) fn parse_expression_with_primary_tokens_and_native_facts(source:&str,admission:Option<&crate::SettingAdmission<'_>>)->Result<(ParsedExpr,Vec<SpanToken>,Option<NativeExpressionParserFacts>),String>{
 parse_primary_expression_tokens_with_role(source,admission,false)
}
/// Same primary lexer/parser, at the literal producer's optional child role.
/// An empty result is still not a complete expression or a retained root.
pub(crate) fn parse_optional_interpolation_with_primary_tokens_and_native_facts(source:&str,admission:Option<&crate::SettingAdmission<'_>>)->Result<(ParsedExpr,Vec<SpanToken>,Option<NativeExpressionParserFacts>),String>{
 parse_primary_expression_tokens_with_role(source,admission,true)
}
fn parse_primary_expression_tokens_with_role(source:&str,admission:Option<&crate::SettingAdmission<'_>>,optional_empty:bool)->Result<(ParsedExpr,Vec<SpanToken>,Option<NativeExpressionParserFacts>),String>{
 if let Some(a)=admission{a.checkpoint().map_err(|_|"interpolation operation stopped".to_owned())?;}
 let lexical=lex(source);let mut spans=Vec::new();let count=lexical.tokens.len();
 spans.try_reserve_exact(count).map_err(|_|{if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary interpolation token geometry allocation refused"));}"primary interpolation token geometry allocation refused".to_owned()})?;
 if spans.capacity()>count.saturating_mul(4){if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary interpolation token geometry exposed excess"));}return Err("primary interpolation token geometry exposed excess".into())}
 for token in &lexical.tokens{if let Some(a)=admission{a.checkpoint().map_err(|_|"interpolation operation stopped".to_owned())?;}spans.push(SpanToken{kind:token.kind,span:token.span});}
  let mut native=None;
  let parsed=finish_expression_with_literal_facts_native_role(lexical.tokens,lexical.diagnostics,admission,None,None,false,None,&mut|facts|native=Some(facts),optional_empty);
  Ok((parsed,spans,native))
}

#[cfg(test)]mod original_colon_prefab_primary{
 use super::*;
 #[test]fn primary_colon_prefab_preserves_original_node_and_call_arguments_without_changing_ternary(){for text in[":child",":child/type",":proc/run"]{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);let value=parsed.expr.unwrap();assert_eq!(value.span,Span::new(0,text.len()));assert!(matches!(value.kind,ExprKind::TypePath(ref path)if path==text));}let call=parse_expression("filter(type=:child)");assert!(call.diagnostics.is_empty(),"{:?}",call.diagnostics);let ternary=parse_expression("a ? b : c");assert!(ternary.diagnostics.is_empty());assert!(matches!(ternary.expr.unwrap().kind,ExprKind::Conditional{..}));for text in[":",":(child)"]{assert!(!parse_expression(text).diagnostics.is_empty(),"invalid colon prefab {text}");}}
}

/// Source-neutral private grammar provenance. A caller cannot construct this
/// from diagnostics, an empty parse, a source hash or a semantic-model option.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) struct OriginalSimpleExpression{kind:OriginalSimpleKind,span:Span,operator:Option<Span>,original_profile:bool,bare_postfix_read:bool,initializer_assignment:bool}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) enum OriginalSimpleKind{Complete,OrdinaryCallStatement,SimpleAssignmentStatement,PlainAssignment,PostIncrementStatement,PostDecrementStatement,PrefixIncrementStatement,PrefixDecrementStatement,IndexedUpdateStatement,CrashStatement,PrefixCondition,MissingArithmeticOperand}
impl OriginalSimpleExpression{
 pub(crate) fn kind(self)->OriginalSimpleKind{self.kind}
 pub(crate) fn is_read_value(self)->bool{self.kind==OriginalSimpleKind::Complete||self.bare_postfix_read}
 pub(crate) fn is_initializer_assignment(self)->bool{self.original_profile&&self.initializer_assignment}
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

// Closed ordinary-dot follower chain. Every node and each actual field token
// keeps its consumed span. This supplies no call/safe/colon/grouped lvalue.
fn original_plain_member_chain(expr:&Expr,tokens:&[Token],depth:usize)->bool{
    original_member_read_chain_using(expr,tokens,depth,false)
}
// Safe-dot opt-in is used ONLY by the SafeIndex read receiver below. Existing
// plain-member lvalue/key/call routes retain their exact old closed helper.
fn original_member_read_chain_using(expr:&Expr,tokens:&[Token],mut depth:usize,allow_safe:bool)->bool{
    let mut value=expr;let mut actual=tokens;
    loop{
        let(object,selector,separator)=match &value.kind{
            ExprKind::Member{object,selector,via_colon:false}=>(object,selector,"."),
            ExprKind::SafeMember{object,selector,via_colon:false}if allow_safe=>(object,selector,"?."),
            _=>break,
        };
        let Some(next)=depth.checked_sub(1)else{return false};depth=next;
        let [receiver@..,dot,member]=actual else{return false};let(Some(first),Some(last))=(receiver.first(),receiver.last())else{return false};
        if dot.kind!=TokenKind::Punctuation||dot.text!=separator||member.kind!=TokenKind::Ident
            ||dot.span.end.checked_sub(dot.span.start)!=Some(separator.len())||dot.span.start<last.span.end||dot.span.end>member.span.start
            ||member.span.end.checked_sub(member.span.start)!=Some(selector.len())
            ||member.text!=*selector||!original_ascii_identifier(selector)
            ||value.span!=Span::new(first.span.start,member.span.end)
            ||object.span!=Span::new(first.span.start,last.span.end){return false}
        value=object;actual=receiver;
    }
    matches!((&value.kind,actual),(ExprKind::Ident(name),[only])
        if original_ordinary_call_name(name)&&simple_term(value,only))
}

// Exact safe field target, isolated from shared receiver/postfix capability.
fn original_safe_member_write_target(expr:&Expr,tokens:&[Token])->bool{
    let ExprKind::SafeMember{object,selector,via_colon:false}=&expr.kind else{return false};
    let at=tokens.partition_point(|token|token.span.end<=object.span.end);
    let(receiver,tail)=tokens.split_at(at);
    original_assignment_receiver(object,receiver)
        &&matches!(tail,[dot,name]if dot.kind==TokenKind::Punctuation&&dot.text=="?."
            &&dot.span.end.checked_sub(dot.span.start)==Some(2)
            &&name.kind==TokenKind::Ident&&name.text==*selector&&original_ascii_identifier(selector)
            &&name.span.end.checked_sub(name.span.start)==Some(selector.len())
            &&object.span.end<=dot.span.start&&dot.span.end<=name.span.start
            &&expr.span==Span::new(object.span.start,name.span.end))
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

// Pinned list_access consumes an expression inside each ordinary bracket.
// Indexed assignment targets only: '=', grouped logical-index and nested-key
// compounds reuse this shape proof. Reads/callees/updates do not borrow it, and a complete
// key value grants no semantic writability/purity.
fn original_complete_index_write_target(expr:&Expr,tokens:&[Token],depth:usize)->bool{
    let Some(depth)=depth.checked_sub(1)else{return false};
    let ExprKind::Index{object,index}=&expr.kind else{return false};
    let at=tokens.partition_point(|token|token.span.end<=object.span.end);
    let(receiver,tail)=tokens.split_at(at);
    let[open,key@..,close]=tail else{return false};
    let(Some(first),Some(last))=(key.first(),key.last())else{return false};
    let receiver_proved=original_assignment_receiver(object,receiver)
        ||matches!(&object.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(object,receiver,depth)
        ||original_complete_index_write_target(object,receiver,depth);
    receiver_proved
        &&open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
        &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
        &&object.span.end<=open.span.start&&open.span.end<=first.span.start
        &&index.span==Span::new(first.span.start,last.span.end)&&last.span.end<=close.span.start
        &&expr.span==Span::new(object.span.start,close.span.end)
        &&original_conditional_child(index,key,true,depth)
}

fn original_bare_postfix_key_write(expr:&Expr,object:&Expr,index:&Expr,tokens:&[Token])->bool{
    let [receiver,open,key@..,close]=tokens else{return false};
    matches!(&object.kind,ExprKind::Ident(name) if original_ordinary_call_name(name)
        &&receiver.span.end.checked_sub(receiver.span.start)==Some(name.len()))
        &&simple_term(object,receiver)&&original_bare_postfix_read(index,key)
        &&open.kind==TokenKind::Punctuation&&open.text=="["
        &&close.kind==TokenKind::Punctuation&&close.text=="]"
        &&open.span.end.checked_sub(open.span.start)==Some(1)
        &&close.span.end.checked_sub(close.span.start)==Some(1)
        &&object.span.end<=open.span.start&&open.span.end<=index.span.start
        &&index.span.end<=close.span.start&&expr.span==Span::new(object.span.start,close.span.end)
}

fn original_assignment_target(expr: &Expr, tokens: &[Token], original_profile: bool, plain_write: bool) -> bool {
    original_assignment_target_with_depth(expr,tokens,original_profile,plain_write,32)
}

// Group assignment keys retain the SAME remaining proof depth; never restart
// the recursive Index/Group target cycle at the root allowance.
fn original_assignment_target_with_depth(expr:&Expr,tokens:&[Token],original_profile:bool,plain_write:bool,depth:usize)->bool{
    // Pinned list/pick with no argument list is an ordinary Ident, including a
    // parameter named list. Keep this exact bare target out of receiver/follow
    // helpers: it does not admit list() or new index/member/callee shapes.
    if original_profile && matches!(tokens, [only]
        if matches!(&expr.kind, ExprKind::Ident(name) if matches!(name.as_str(),"list"|"pick"))
            && simple_term(expr, only)) {
        return true;
    }
    if original_assignment_receiver(expr, tokens)
        || (original_profile&&matches!(&expr.kind,ExprKind::Member{via_colon:false,..})
            &&original_plain_member_chain(expr,tokens,depth)) {
        return true;
    }
    let ExprKind::Index { object, index } = &expr.kind else { return false; };
    if original_profile&&plain_write&&original_bare_postfix_key_write(expr,object,index,tokens){return true}
    if original_profile && plain_write && (original_plain_index(expr, object, index, tokens, depth)
        || original_static_member_key_write(expr, object, index, tokens)
        || original_complete_index_write_target(expr,tokens,depth)) {
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

fn original_augmented_rhs_value(expr:&Expr,tokens:&[Token],depth:usize)->bool{
    let Some(depth)=depth.checked_sub(1)else{return false};
    if original_conditional_child(expr,tokens,true,depth)||original_postfix_call_argument(expr,tokens){return true}
    let(Some(first),Some(last))=(tokens.first(),tokens.last())else{return false};
    if expr.span!=Span::new(first.span.start,last.span.end){return false}
    match &expr.kind{
        ExprKind::Group(inner)=>{let[open,body@..,close]=tokens else{return false};
            open.kind==TokenKind::Punctuation&&open.text=="("&&close.kind==TokenKind::Punctuation&&close.text==")"
                &&original_augmented_rhs_value(inner,body,depth)},
        ExprKind::Binary{op,lhs,rhs}=>{let Some(binding)=original_binary_binding(op)else{return false};
            let split=tokens.partition_point(|token|token.span.end<=lhs.span.end);let(left,tail)=tokens.split_at(split);let Some((operator,right))=tail.split_first()else{return false};
            let binding_ok=|child:&Expr,minimum|match &child.kind{ExprKind::Binary{op,..}=>original_binary_binding(op).is_some_and(|at|at>=minimum),_=>true};
            (if op=="in" {operator.kind==TokenKind::Ident&&operator.text=="in"}
                else {matches!(operator.kind,TokenKind::Punctuation|TokenKind::Operator)&&operator.text==*op})
                && (!matches!(op.as_str(),"~="|"~!") || (operator.kind==TokenKind::Operator
                    &&operator.span.end.checked_sub(operator.span.start)==Some(2)
                    &&operator.span.start>=lhs.span.end&&operator.span.end<=rhs.span.start))
                &&binding_ok(lhs,binding)&&binding_ok(rhs,binding+1)
                &&original_augmented_rhs_value(lhs,left,depth)&&original_augmented_rhs_value(rhs,right,depth)},
        _=>false,
    }
}

// A direct ordinary call plus bounded plain fields supplies existing root
// equals/compound/postfix targets and indexed-root receivers. This is syntax
// DATA only: grouped/value/callee rights and safe/colon follows are separate.
fn original_call_result_member_root_write(expr:&Expr,tokens:&[Token],mut depth:usize)->bool{
 if !matches!(&expr.kind,ExprKind::Member{via_colon:false,..}){return false}
 let(mut current,mut actual)=(expr,tokens);
 while let ExprKind::Member{object,selector,via_colon:false}=&current.kind{
  let Some(next)=depth.checked_sub(1)else{return false};depth=next;
  let at=actual.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=actual.split_at(at);let(Some(first),Some(last))=(receiver.first(),receiver.last())else{return false};let[dot,name]=tail else{return false};
  if dot.kind!=TokenKind::Punctuation||dot.text!="."||dot.span.end.checked_sub(dot.span.start)!=Some(1)
   ||name.kind!=TokenKind::Ident||name.text!=*selector||!original_ascii_identifier(selector)||name.span.end.checked_sub(name.span.start)!=Some(selector.len())
   ||last.span.end>dot.span.start||dot.span.end>name.span.start||object.span!=Span::new(first.span.start,last.span.end)||current.span!=Span::new(first.span.start,name.span.end){return false}
  current=object;actual=receiver;
 }
 let ExprKind::Call{callee,..}=&current.kind else{return false};if !matches!(&callee.kind,ExprKind::Ident(n)if original_ordinary_call_name(n)){return false}
 let[head,open,_args@..,close]=actual else{return false};
 simple_term(callee,head)&&open.kind==TokenKind::Punctuation&&open.text=="("&&open.span.end.checked_sub(open.span.start)==Some(1)
  &&close.kind==TokenKind::Punctuation&&close.text==")"&&close.span.end.checked_sub(close.span.start)==Some(1)
  &&head.span.end<=open.span.start&&open.span.end<=close.span.start&&current.span==Span::new(head.span.start,close.span.end)
  &&original_composed_expression_mode(current,actual,false,depth,false,false)
}

// A null-safe member write after a direct call is a root '=' statement only.
// Walk the actual SafeMember nodes/tokens once; the same ordinary-call parser
// certifies the receiver and every argument at the remaining proof depth.
fn original_call_result_safe_chain_root_write(expr:&Expr,tokens:&[Token],mut depth:usize)->bool{
    if !matches!(&expr.kind,ExprKind::SafeMember{via_colon:false,..}){return false}
    let(mut value,mut actual)=(expr,tokens);
    while let ExprKind::SafeMember{object,selector,via_colon:false}=&value.kind{
        let Some(next)=depth.checked_sub(1)else{return false};depth=next;
        let[receiver@..,dot,name]=actual else{return false};
        let(Some(first),Some(last))=(receiver.first(),receiver.last())else{return false};
        if dot.kind!=TokenKind::Punctuation||dot.text!="?."||dot.span.end.checked_sub(dot.span.start)!=Some(2)
            ||name.kind!=TokenKind::Ident||name.text!=*selector||!original_ascii_identifier(selector)
            ||name.span.end.checked_sub(name.span.start)!=Some(selector.len())
            ||last.span.end>dot.span.start||dot.span.end>name.span.start
            ||object.span!=Span::new(first.span.start,last.span.end)
            ||value.span!=Span::new(first.span.start,name.span.end){return false}
        value=object;actual=receiver;
    }
    let ExprKind::Call{callee,..}=&value.kind else{return false};
    if !matches!(&callee.kind,ExprKind::Ident(name)if original_ordinary_call_name(name)){return false}
    let[head,open,_args@..,close]=actual else{return false};
    simple_term(callee,head)
        &&open.kind==TokenKind::Punctuation&&open.text=="("&&open.span.end.checked_sub(open.span.start)==Some(1)
        &&close.kind==TokenKind::Punctuation&&close.text==")"&&close.span.end.checked_sub(close.span.start)==Some(1)
        &&head.span.end<=open.span.start&&open.span.end<=close.span.start
        &&value.span==Span::new(head.span.start,close.span.end)
        &&original_composed_expression_mode(value,actual,false,depth,false,false)
}

fn original_grouped_logical_index_target(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let ExprKind::Index{object,index}=&expr.kind else{return false};
 let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
 let[open,key@..,close]=tail else{return false};
 (matches!(&object.kind,ExprKind::Ident(_))||matches!(&object.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(object,receiver,depth))
  &&open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
  &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
  &&object.span.end<=open.span.start&&open.span.end<=index.span.start&&index.span.end<=close.span.start
  &&(!matches!(&index.kind,ExprKind::Member{..})||original_plain_member_chain(index,key,depth))
  &&(if matches!(&index.kind,ExprKind::Group(_)){original_complete_index_write_target(expr,tokens,depth)}else if matches!(&index.kind,ExprKind::Binary{op,..}if op=="|"){original_mutation_run_geometry(index,key)&&original_complete_index_write_target(expr,tokens,depth)}else{original_plain_index(expr,object,index,tokens,depth)})
}

// Assignment-value DATA is lent only to an actual root RHS chain or a local
// initializer. General expression/read/callee roles do not consume this proof.
fn original_assignment_value_target(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 match &expr.kind{
  ExprKind::Ident(name)=>matches!(tokens,[token]if original_ordinary_call_name(name)&&simple_term(expr,token)
   &&token.span.end.checked_sub(token.span.start)==Some(name.len())),
  ExprKind::Member{via_colon:false,..}=>original_plain_member_chain(expr,tokens,depth),
  ExprKind::Index{object,index}=>{
   let at=tokens.partition_point(|token|token.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
   let[open,key@..,close]=tail else{return false};let(Some(first),Some(last))=(key.first(),key.last())else{return false};
   original_assignment_value_target(object,receiver,depth)
    &&open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
    &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
    &&object.span.end<=open.span.start&&open.span.end<=first.span.start&&last.span.end<=close.span.start
    &&index.span==Span::new(first.span.start,last.span.end)&&expr.span==Span::new(object.span.start,close.span.end)
    &&(!matches!(&index.kind,ExprKind::Member{..})||original_plain_member_chain(index,key,depth))
    &&original_conditional_child(index,key,true,depth)
  },_=>false
 }
}
// An ordinary direct call (optionally its ordinary final field) can supply an
// indexed root '=' receiver. No call-result lvalue gains value/update authority.
fn original_call_result_index_root_write(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 let ExprKind::Index{object,index}=&expr.kind else{return false};
 let at=tokens.partition_point(|token|token.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
 let[open,key@..,close]=tail else{return false};let(Some(first),Some(last))=(key.first(),key.last())else{return false};
 let proved=if let ExprKind::Call{callee,..}=&object.kind{
  matches!(&callee.kind,ExprKind::Ident(name)if original_ordinary_call_name(name))
   &&matches!(receiver,[head,left,_args@..,right]if simple_term(callee,head)
    &&left.kind==TokenKind::Punctuation&&left.text=="("&&left.span.end.checked_sub(left.span.start)==Some(1)
    &&right.kind==TokenKind::Punctuation&&right.text==")"&&right.span.end.checked_sub(right.span.start)==Some(1)
    &&head.span.end<=left.span.start&&left.span.end<=right.span.start&&object.span==Span::new(head.span.start,right.span.end))
   &&original_composed_expression_mode(object,receiver,false,depth,false,false)
 }else{original_call_result_member_root_write(object,receiver,depth)};
 proved&&open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
  &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
  &&object.span.end<=open.span.start&&open.span.end<=first.span.start&&last.span.end<=close.span.start
  &&index.span==Span::new(first.span.start,last.span.end)&&expr.span==Span::new(object.span.start,close.span.end)
  &&(!matches!(&index.kind,ExprKind::Member{..})||original_plain_member_chain(index,key,depth))
  &&original_conditional_child(index,key,true,depth)
}
// Existing root '=' statements may use a right-associated assignment chain.
// assignments. Every node/operator is checked at the remaining bounded depth;
// this helper is not used for general value/argument/callee roles.
fn original_root_assignment_chain_value(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return original_conditional_child(expr,tokens,true,depth)};
 if op!="="{return original_conditional_child(expr,tokens,true,depth)}
 let at=tokens.partition_point(|token|token.span.end<=lhs.span.end);let(target,tail)=tokens.split_at(at);let[equals,value@..]=tail else{return false};
 original_assignment_value_target(lhs,target,depth)
  &&equals.kind==crate::original_scalar_transport::original_punctuation_native_kind("=")&&equals.text=="="&&equals.span.end.checked_sub(equals.span.start)==Some(1)
  &&lhs.span.end<=equals.span.start&&equals.span.end<=rhs.span.start&&expr.span==Span::new(lhs.span.start,rhs.span.end)
  &&original_root_assignment_chain_value(rhs,value,depth)
}

// Three observed root compound forms; shared target/value roles remain unchanged.
fn original_observed_index_compound_root(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(remaining)=depth.checked_sub(1)else{return false};
 let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};
 let ExprKind::Index{object,index}=&lhs.kind else{return false};
 let at=tokens.partition_point(|t|t.span.end<=lhs.span.end);let(target,tail)=tokens.split_at(at);let[assignment,value@..]=tail else{return false};
 if assignment.kind!=crate::original_scalar_transport::original_punctuation_native_kind(op)||assignment.text!=*op
  ||assignment.span.end.checked_sub(assignment.span.start)!=Some(op.len())||lhs.span.end>assignment.span.start||assignment.span.end>rhs.span.start
  ||expr.span!=Span::new(lhs.span.start,rhs.span.end){return false}
 let receiver_end=target.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=target.split_at(receiver_end);let[open,key@..,close]=tail else{return false};
 let bracket=|t:&Token,w:&str|t.kind==TokenKind::Punctuation&&t.text==w&&t.span.end.checked_sub(t.span.start)==Some(1);
 if !bracket(open,"[")||!bracket(close,"]")||object.span.end>open.span.start||open.span.end>index.span.start||index.span.end>close.span.start
  ||lhs.span!=Span::new(object.span.start,close.span.end)||!matches!(&index.kind,ExprKind::Member{via_colon:false,..})
  ||!original_plain_member_chain(index,key,remaining){return false}
 let proved=if matches!(op.as_str(),"-="|"||=")&&matches!(&object.kind,ExprKind::Ident(n)if original_ordinary_call_name(n)){
  matches!(receiver,[one]if simple_term(object,one))&&original_complete_index_write_target(lhs,target,remaining)
 }else if op=="+="{
  let ExprKind::Index{object:inner,index:inner_key}=&object.kind else{return false};
  let[dot,inner_open,inner_tokens@..,inner_close]=receiver else{return false};
  original_return_slot_read(inner,std::slice::from_ref(dot))&&dot.span.end.checked_sub(dot.span.start)==Some(1)
   &&matches!(&inner_key.kind,ExprKind::Literal(v)if matches!(v.original_value(),Some(crate::OriginalTokenValue::String(_))))
   &&bracket(inner_open,"[")&&bracket(inner_close,"]")&&dot.span.end<=inner_open.span.start
   &&inner_open.span.end<=inner_key.span.start&&inner_key.span.end<=inner_close.span.start
   &&object.span==Span::new(dot.span.start,inner_close.span.end)
   &&original_conditional_child(inner_key,inner_tokens,true,remaining)&&original_conditional_child(index,key,true,remaining)
 }else{false};
 proved&&original_conditional_child(rhs,value,true,remaining)
}

// Root statement only: a strict plain-member logical write keeps its RHS
// as one independent bounded read proof, without assignment value authority.
fn original_plain_member_logical_root_assignment(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(remaining)=depth.checked_sub(1)else{return false};
 let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};
 if !matches!(op.as_str(),"||="|"&&=")||!matches!(&lhs.kind,ExprKind::Member{via_colon:false,..}){return false}
 let at=tokens.partition_point(|t|t.span.end<=lhs.span.end);let(target,tail)=tokens.split_at(at);let[assignment,value@..]=tail else{return false};
 original_plain_member_chain(lhs,target,remaining)
  &&assignment.kind==TokenKind::Operator&&assignment.text==*op&&assignment.span.end.checked_sub(assignment.span.start)==Some(3)
  &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start&&expr.span==Span::new(lhs.span.start,rhs.span.end)
  &&original_mutation_run_geometry(rhs,value)
  &&original_conditional_child(rhs,value,true,remaining)
}

// Geometry DATA only for the observed method-follow mutation targets.
fn original_mutation_run_geometry(expr:&Expr,tokens:&[Token])->bool{
 let(Some(first),Some(last))=(tokens.first(),tokens.last())else{return false};if expr.span!=Span::new(first.span.start,last.span.end){return false}
 let mut end=first.span.start;for t in tokens{if t.span.start<end||t.span.end.checked_sub(t.span.start)!=Some(t.text.len()){return false}end=t.span.end;if matches!(t.text.as_str(),"("|")"|"["|"]"|"."|",")&&t.kind!=TokenKind::Punctuation{return false}}true
}
fn original_mutation_follow_geometry(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};if !original_mutation_run_geometry(expr,tokens){return false}
 match &expr.kind{
  ExprKind::Ident(n)=>original_ordinary_call_name(n)&&matches!(tokens,[one]if simple_term(expr,one)),
  ExprKind::Member{object,selector,via_colon:false}=>{let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(run,tail)=tokens.split_at(at);let[dot,name]=tail else{return false};dot.text=="."&&dot.kind==TokenKind::Punctuation&&name.kind==TokenKind::Ident&&name.text==*selector&&original_ascii_identifier(selector)&&object.span.end<=dot.span.start&&dot.span.end<=name.span.start&&original_mutation_follow_geometry(object,run,depth)},
  ExprKind::Call{callee,args}=>{
   if args.len()>16||!matches!(&callee.kind,ExprKind::Ident(_)|ExprKind::Member{via_colon:false,..}){return false}
   let at=tokens.partition_point(|t|t.span.end<=callee.span.end);let(head,tail)=tokens.split_at(at);let[open,body@..,close]=tail else{return false};
   if open.text!="("||close.text!=")"||callee.span.end>open.span.start||!original_mutation_follow_geometry(callee,head,depth){return false}
   let mut rest=body;for(i,arg)in args.iter().enumerate(){if i!=0{let Some((comma,next))=rest.split_first()else{return false};if comma.text!=","||args[i-1].span.end>comma.span.start||comma.span.end>arg.span.start{return false}rest=next;}
    let at=rest.partition_point(|t|t.span.end<=arg.span.end);let(run,next)=rest.split_at(at);if !original_mutation_run_geometry(arg,run)||arg.span.start<open.span.end||arg.span.end>close.span.start{return false}rest=next;}
   rest.is_empty()
  },_=>false,
 }
}
fn original_mutation_receiver_has_call(mut value:&Expr)->bool{for _ in 0..32{match &value.kind{ExprKind::Call{..}=>return true,ExprKind::Member{object,via_colon:false,..}|ExprKind::Index{object,..}=>value=object,_=>return false}}false}
fn original_mutation_receiver_is_return_slot(mut value:&Expr)->bool{for _ in 0..32{match &value.kind{ExprKind::Index{object,..}=>value=object,ExprKind::Ident(n)=>return n==".",_=>return false}}false}
fn original_observed_mutation_target(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};if !original_mutation_run_geometry(expr,tokens){return false}
 match &expr.kind{
  ExprKind::Member{object,selector,via_colon:false}=>{let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(run,tail)=tokens.split_at(at);let[dot,name]=tail else{return false};dot.text=="."&&name.kind==TokenKind::Ident&&name.text==*selector&&original_ascii_identifier(selector)&&object.span.end<=dot.span.start&&dot.span.end<=name.span.start&&original_mutation_follow_geometry(object,run,depth)&&original_conditional_child(object,run,true,depth)},
  ExprKind::Index{object,index}=>{
   let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(run,tail)=tokens.split_at(at);let[open,key@..,close]=tail else{return false};
   if open.text!="["||close.text!="]"||object.span.end>open.span.start||open.span.end>index.span.start||index.span.end>close.span.start||!original_mutation_run_geometry(index,key){return false}
   let receiver=if matches!(&object.kind,ExprKind::Index{..}){original_observed_mutation_target(object,run,depth)}else if original_return_slot_read(object,run){matches!(run,[dot]if dot.span.end.checked_sub(dot.span.start)==Some(1))}else{original_mutation_follow_geometry(object,run,depth)&&original_conditional_child(object,run,true,depth)};
   receiver&&original_conditional_child(index,key,true,depth)
  },_=>false,
 }
}
fn original_observed_mutation_root_assignment(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};
 let eligible=match &lhs.kind{ExprKind::Member{object,via_colon:false,..}=>op=="="&&original_mutation_receiver_has_call(object),ExprKind::Index{object,index}=>matches!(op.as_str(),"="|"+=")&&(original_mutation_receiver_has_call(object)||original_mutation_receiver_is_return_slot(object)||matches!(&index.kind,ExprKind::Group(inner)if matches!(&inner.kind,ExprKind::Conditional{..}))),_=>false};if !eligible{return false}
 let at=tokens.partition_point(|t|t.span.end<=lhs.span.end);let(target,tail)=tokens.split_at(at);let[assignment,value@..]=tail else{return false};
 assignment.kind==TokenKind::Operator&&assignment.text==*op&&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())&&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start&&expr.span==Span::new(lhs.span.start,rhs.span.end)
  &&original_observed_mutation_target(lhs,target,depth)&&original_conditional_child(rhs,value,true,depth)
}

// Root += only. Reuse the existing complete indexed target and its key VALUE
// proof without widening shared read, callee, or initializer roles.
fn original_complete_index_root_add_assignment(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(remaining)=depth.checked_sub(1)else{return false};
 let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};if op!="+="{return false}
 let ExprKind::Index{object,..}=&lhs.kind else{return false};
 let at=tokens.partition_point(|token|token.span.end<=lhs.span.end);let(target,tail)=tokens.split_at(at);let[assignment,value@..]=tail else{return false};
 let end=target.partition_point(|token|token.span.end<=object.span.end);let(receiver,_)=target.split_at(end);
 (matches!(&object.kind,ExprKind::Ident(name)if original_ordinary_call_name(name))||matches!(&object.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(object,receiver,remaining))
  &&original_mutation_run_geometry(lhs,target)
  &&target.iter().all(|token|crate::original_scalar_transport::original_punctuation_storage_index(&token.text).is_none()||token.kind==crate::original_scalar_transport::original_punctuation_native_kind(&token.text))
  &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind("+=")&&assignment.text=="+="&&assignment.span.end.checked_sub(assignment.span.start)==Some(2)
  &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start&&expr.span==Span::new(lhs.span.start,rhs.span.end)
  &&original_complete_index_write_target(lhs,target,remaining)
  &&original_mutation_run_geometry(rhs,value)&&original_conditional_child(rhs,value,true,remaining)
}

fn original_simple_assignment(expr: &Expr, tokens: &[Token], original_profile: bool) -> bool {
    if original_profile && original_complete_index_root_add_assignment(expr,tokens,32) { return true; }
    if original_profile && original_plain_member_logical_root_assignment(expr, tokens, 32) { return true; }
    if original_profile && original_observed_mutation_root_assignment(expr, tokens, 32) { return true; }
    if original_profile && original_colon_member_root_assignment(expr, tokens, 32) { return true; }
    if original_profile && original_observed_index_compound_root(expr, tokens, 32) { return true; }
    let ExprKind::Binary { op, lhs, rhs } = &expr.kind else { return false; };
    let target_end = tokens.partition_point(|token| token.span.end <= lhs.span.end);
    let (target, tail) = tokens.split_at(target_end);
    let [assignment, value @ ..] = tail else { return false; };
    let Some(first) = target.first() else { return false; };
    // The new postfix-key write owns its '=' occurrence independently too.
    if original_profile&&op=="="&&matches!(&lhs.kind,ExprKind::Index{object,index}
        if original_bare_postfix_key_write(lhs,object,index,target))
        &&(assignment.kind!=crate::original_scalar_transport::original_punctuation_native_kind("=")
            ||assignment.span.end.checked_sub(assignment.span.start)!=Some(1)
            ||assignment.span.start<lhs.span.end||assignment.span.end>rhs.span.start){return false}
    let call_result_write=original_profile&&op=="="
        &&(original_call_result_member_root_write(lhs,target,32)
            ||original_call_result_safe_chain_root_write(lhs,target,32)
            ||original_call_result_index_root_write(lhs,target,32))
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind("=")
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(1)
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let plain = target.len() == 1;
    let logical_assignment=original_profile&&matches!(op.as_str(),"||="|"&&=")
        &&matches!((&lhs.kind,target), (ExprKind::Ident(name),[token])
            if original_ordinary_call_name(name)&&simple_term(lhs,token));
    let member_write=original_profile&&matches!(&lhs.kind,ExprKind::Member{via_colon:false,..});
    let safe_call_compound=original_profile
        &&matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&original_call_result_safe_chain_root_write(lhs,target,32)
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let call_member_compound=original_profile
        &&matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&original_call_result_member_root_write(lhs,target,32)
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let safe_member_write=(original_profile&&matches!(&lhs.kind,ExprKind::SafeMember{via_colon:false,..})
        &&original_safe_member_write_target(lhs,target))||safe_call_compound||call_member_compound;
    // Root statements reuse the SAME existing plain indexed lvalue. Arithmetic
    // updates may compose an independent Complete RHS, just as the bit/shift
    // updates already do. No assignment gains a general value/argument role.
    let conditional_key_compound=original_profile&&matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&matches!(&lhs.kind,ExprKind::Index{object,index}
            if original_conditional_key_compound_target(lhs,object,index,target,32))
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let nested_string_compound=original_profile
        &&matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&original_nested_string_index_compound_target(lhs,target,32)
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let sequential_compound=original_profile
        &&matches!(op.as_str(),"="|"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&original_sequential_index_compound_target(lhs,target,32)
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let nested_key_compound=original_profile
        &&matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&matches!(&lhs.kind,ExprKind::Index{object,index}if matches!(&index.kind,ExprKind::Index{..}|ExprKind::Call{..})
            &&(matches!(&object.kind,ExprKind::Ident(_))||matches!(&object.kind,ExprKind::Member{via_colon:false,..})
                &&original_plain_member_chain(object,&target[..target.partition_point(|t|t.span.end<=object.span.end)],32))
            &&matches!(&target[target.partition_point(|t|t.span.end<=object.span.end)..],[_open,key@..,_close]if original_exact_index_key_geometry(index,key,32)||original_compound_call_key_geometry(index,key,32))
            &&original_complete_index_write_target(lhs,target,32))
        &&assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
        &&assignment.span.end.checked_sub(assignment.span.start)==Some(op.len())
        &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start;
    let indexed_compound=sequential_compound||nested_key_compound||nested_string_compound||conditional_key_compound||(original_profile
        &&matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        &&matches!(&lhs.kind,ExprKind::Index{object,index}if original_plain_index(lhs,object,index,target,32))
        &&(!matches!(op.as_str(),"+="|"-="|"*="|"/=")
            ||(assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
                &&assignment.span.end.checked_sub(assignment.span.start)==Some(2)
                &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start)));
    let indexed_write = original_profile && matches!(op.as_str(), "=" | "+=")
        && matches!(&rhs.kind, ExprKind::Index { object, index }
            if original_plain_index(rhs, object, index, value, 32))
        && original_index_write_target(lhs, target, op == "+=");
    let return_slot = original_profile
        && matches!(target, [dot] if dot.kind == TokenKind::Punctuation
            && dot.text == "." && dot.span == lhs.span)
        && matches!(&lhs.kind, ExprKind::Ident(name) if name == ".");
    if !(logical_assignment || matches!(op.as_str(), "=" | "+=" | "-=" | "*=" | "/=")
        || ((plain||member_write||safe_member_write||indexed_compound) && matches!(op.as_str(), "%=" | "|=" | "&=" | "^=" | "<<=" | ">>=")))
        || !matches!(assignment.kind, TokenKind::Punctuation | TokenKind::Operator)
        || assignment.text.as_str() != op.as_str()
        || (logical_assignment && (assignment.kind!=TokenKind::Operator
            ||assignment.span.end.checked_sub(assignment.span.start)!=Some(3)
            ||assignment.span.start<lhs.span.end||assignment.span.end>rhs.span.start))
        || (!return_slot && !indexed_write && !safe_member_write && !indexed_compound && !call_result_write
            && !original_assignment_target(lhs, target, original_profile, op == "="))
        || expr.span != Span::new(first.span.start, rhs.span.end)
    {
        return false;
    }
    if original_profile&&op=="="
        &&(matches!(&lhs.kind,ExprKind::Ident(_))
            ||matches!(&lhs.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(lhs,target,32))
        &&matches!(&rhs.kind,ExprKind::Binary{op,..}if op=="="){
        return assignment.kind==crate::original_scalar_transport::original_punctuation_native_kind("=")
            &&assignment.span.end.checked_sub(assignment.span.start)==Some(1)
            &&lhs.span.end<=assignment.span.start&&assignment.span.end<=rhs.span.start
            &&original_root_assignment_chain_value(rhs,value,32);
    }
    if logical_assignment {
        return original_conditional_child(rhs,value,true,32);
    }
    if return_slot {
        // Exact implicit return-slot mutation remains a statement-root role.
        // Independent value children do not acquire assignment authority.
        return original_conditional_child(rhs,value,true,32)
            ||(op=="="&&original_return_slot_mini_constructor(rhs,value));
    }
    if safe_member_write||indexed_compound||call_result_write {
        return original_conditional_child(rhs,value,true,32);
    }
    if indexed_write || (original_profile && original_plain_assignment(expr, tokens)) {
        return true;
    }
    // Statement root only: keep the existing indexed target/operator proof
    // above, but compose its independently authenticated RHS. This does not
    // admit an indexed assignment as a call argument, read or C-for step.
    if original_profile && matches!(op.as_str(), "=" | "+=")
        && matches!(&lhs.kind, ExprKind::Index { .. })
    {
        return original_conditional_child(rhs, value, true, 32)
            ||(op=="="&&original_plain_assignment(rhs,value));
    }
    // Statement root only: the preceding SAME target proof already admits
    // exactly one ordinary dot field. Reuse the actual RHS composition;
    // do not turn the assignment into a Complete read/value expression.
    if member_write && matches!(op.as_str(), "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "|=" | "&=" | "^=" | "<<=" | ">>=") {
        return original_conditional_child(rhs, value, true, 32);
    }
    if original_profile && plain && matches!(op.as_str(), "+=" | "-=" | "*=" | "/=" | "%=" | "|=" | "&=" | "^=" | "<<=" | ">>=")
        && matches!(&lhs.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
    {
        return original_augmented_rhs_value(rhs, value, 32);
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
        "in" => 0,
        "||" => 1,
        "&&" => 2,
        "|" => 3,
        "^" => 4,
        "&" => 5,
        "==" | "!=" | "~=" | "~!" => 6,
        "<<" | ">>" => 7,
        "<" | "<=" | ">" | ">=" => 8,
        "+" | "-" => 9,
        "*" | "/" | "%" => 10,
        // Pinned Pow is left-binding (only Strength::Assign is right-binding),
        // matching the existing native Pratt (25, 26) primary production.
        "**" => 11,
        _ => return None,
    })
}

/// Check the exact token runs already consumed by the Original Pratt parser.
/// A group, argument, or typed interpolation starts a new expression.
// Actual In keeps pinned lowest precedence and independently witnessed value
// children. Ranges, nested assignments and split spellings remain unissued.
fn original_plain_membership(expr: &Expr, tokens: &[Token]) -> bool {
    matches!(&expr.kind,ExprKind::Binary{op,..}if op=="in")
        &&original_composed_expression(expr,tokens,true,32,false)
}

// Pinned NewImplicit with absent arguments. The actual term parser already
// issued arguments_present=false; this only witnesses its exact consumed shape.
// Contextual target inference remains with the native semantic consumer.
fn original_bare_new(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Call { callee, args } = &expr.kind else { return false; };
    matches!(tokens, [keyword] if args.is_empty()
        && keyword.kind == TokenKind::Ident && keyword.text == "new"
        && matches!(&callee.kind, ExprKind::Ident(name) if name == "new")
        && simple_term(callee, keyword) && expr.span == keyword.span)
}

// Pinned NewMiniExpr retains an actual ordinary name/field runtime target.
// Its optional positional arguments remain separate consumed children; this
// issues no NewImplicit hint, callable receiver, or writable target authority.
fn original_direct_dynamic_new(expr:&Expr,tokens:&[Token],depth:usize)->bool{
    let[keyword,tail@..]=tokens else{return false};
    let ExprKind::Unary{op,value}=&expr.kind else{return false};
    if op!="new"||keyword.kind!=TokenKind::Ident||keyword.text!="new"
        ||keyword.span.end.checked_sub(keyword.span.start)!=Some(3){return false}
    let(target,args,target_tokens,arguments)=if let ExprKind::Call{callee,args}=&value.kind{
        let at=tail.partition_point(|token|token.span.end<=callee.span.end);
        let(target,arguments)=tail.split_at(at);(callee.as_ref(),Some(args.as_slice()),target,arguments)
    }else{(value.as_ref(),None,tail,&[][..])};
    let target_ok=matches!((&target.kind,target_tokens),(ExprKind::Ident(name),[only])
        if original_ordinary_call_name(name)&&!matches!(name.as_str(),"null"|"__PROC__"|"__TYPE__"|"__IMPLIED_TYPE__")&&simple_term(target,only))
        ||matches!(&target.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(target,target_tokens,depth);
    if !target_ok||keyword.span.end>target.span.start||expr.span!=Span::new(keyword.span.start,value.span.end){return false}
    let Some(args)=args else{return arguments.is_empty()&&value.span==target.span};
    let[open,body@..,close]=arguments else{return false};
    if args.len()>16||open.kind!=TokenKind::Punctuation||open.text!="("||open.span.end.checked_sub(open.span.start)!=Some(1)
        ||close.kind!=TokenKind::Punctuation||close.text!=")"||close.span.end.checked_sub(close.span.start)!=Some(1)
        ||target.span.end>open.span.start||value.span!=Span::new(target.span.start,close.span.end){return false}
    let named_roster=args.iter().any(|argument|matches!(&argument.kind,ExprKind::Binary{op,..}if op=="="));
    let mut remaining=body;
    for(index,argument)in args.iter().enumerate(){
        if index!=0{let Some((comma,rest))=remaining.split_first()else{return false};
            if comma.kind!=TokenKind::Punctuation||comma.text!=","||comma.span.end.checked_sub(comma.span.start)!=Some(1)
                ||(named_roster&&(args[index-1].span.end>comma.span.start||comma.span.end>argument.span.start)){return false}remaining=rest;}
        let at=remaining.partition_point(|token|token.span.end<=argument.span.end);let(run,rest)=remaining.split_at(at);
        if !(original_constructor_named_argument(argument,run,depth)||original_conditional_child(argument,run,true,depth)){return false}remaining=rest;
    }
    remaining.is_empty()&&open.span.end<=args.first().map_or(close.span.start,|arg|arg.span.start)
        &&args.last().map_or(open.span.end,|arg|arg.span.end)<=close.span.start
}

// Constructor keyword DATA remains a role inside exact static/dynamic New.
// It does not lend '=' a binary precedence, ordinary call, lvalue or purity role.
fn original_constructor_named_argument(argument:&Expr,tokens:&[Token],depth:usize)->bool{
 let ExprKind::Binary{op,lhs,rhs}=&argument.kind else{return false};
 let ExprKind::Ident(name)=&lhs.kind else{return false};
 let [key,equals,value @ ..]=tokens else{return false};
 op=="="&&original_ordinary_call_name(name)&&simple_term(lhs,key)
  &&key.kind==TokenKind::Ident&&key.span.end.checked_sub(key.span.start)==Some(name.len())
  &&equals.kind==TokenKind::Operator&&equals.text=="="&&equals.span.end.checked_sub(equals.span.start)==Some(1)
  &&lhs.span.end<=equals.span.start&&equals.span.end<=rhs.span.start
  &&argument.span==Span::new(lhs.span.start,rhs.span.end)
  &&original_conditional_child(rhs,value,true,depth)
}

// Pinned NewPrefab with an absolute unmodified type path and an
// argument list that is explicitly present or genuinely absent. Existing static constructor semantics own
// target resolution and New dispatch; this is only its consumed syntax proof.
fn original_absolute_static_new(expr: &Expr, tokens: &[Token], depth: usize) -> bool {
    let [keyword, tail @ ..] = tokens else { return false; };
    let ExprKind::Unary { op, value } = &expr.kind else { return false; };
    // Pinned NewPrefab arguments() is optional. Its genuinely absent list
    // keeps the SAME static target, with no implicit-constructor hint.
    if let ExprKind::TypePath(path)=&value.kind{
        return op=="new"&&keyword.kind==TokenKind::Ident&&keyword.text=="new"
            &&keyword.span.end.checked_sub(keyword.span.start)==Some(3)
            &&keyword.span.end<=value.span.start
            &&expr.span==Span::new(keyword.span.start,value.span.end)
            &&path.starts_with('/')&&original_conditional_child(value,tail,false,depth)
    }
    let ExprKind::Call { callee, args } = &value.kind else { return false; };
    if op != "new" || keyword.kind != TokenKind::Ident || keyword.text != "new"
        || !matches!(&callee.kind, ExprKind::TypePath(path) if path.starts_with('/'))
        || args.len() > 16 { return false; }
    let at = tail.partition_point(|token| token.span.end <= callee.span.end);
    let (path, rest) = tail.split_at(at);
    let [open, body @ .., close] = rest else { return false; };
    if open.kind != TokenKind::Punctuation || open.text != "("
        || close.kind != TokenKind::Punctuation || close.text != ")"
        || value.span != Span::new(callee.span.start, close.span.end)
        || expr.span != Span::new(keyword.span.start, close.span.end)
        || !original_conditional_child(callee, path, false, depth) { return false; }
    let mut remaining = body;
    for (index, argument) in args.iter().enumerate() {
        if index != 0 {
            let Some((comma, rest)) = remaining.split_first() else { return false; };
            if comma.kind != TokenKind::Punctuation || comma.text != "," { return false; }
            remaining = rest;
        }
        let at = remaining.partition_point(|token| token.span.end <= argument.span.end);
        let (run, rest) = remaining.split_at(at);
        let named=original_constructor_named_argument(argument,run,depth)
            &&keyword.span.end.checked_sub(keyword.span.start)==Some(3)
            &&keyword.span.end<=callee.span.start
            &&open.span.end.checked_sub(open.span.start)==Some(1)
            &&close.span.end.checked_sub(close.span.start)==Some(1)
            &&callee.span.end<=open.span.start&&open.span.end<=argument.span.start
            &&argument.span.end<=close.span.start;
        if !named&&!original_conditional_child(argument, run, true, depth) { return false; }
        remaining = rest;
    }
    remaining.is_empty()
}

fn original_conditional_child(expr: &Expr, tokens: &[Token], conditional: bool, depth: usize) -> bool {
    original_composed_expression(expr, tokens, conditional, depth, false)
}

fn original_keyword_statement_call(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Call { callee, args } = &expr.kind else { return false };
    let mut receiver = callee.as_ref();
    while let ExprKind::Member { object, selector, via_colon: false }
        | ExprKind::SafeMember { object, selector, via_colon: false } = &receiver.kind {
        if !original_ordinary_call_name(selector) { return false; }
        receiver = object;
    }
    // The existing composed call proof below independently certifies this
    // direct ordinary-call receiver, every follower, and named argument token.
    (matches!(&receiver.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
        ||matches!(&receiver.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if original_ordinary_call_name(name))))
        && args.iter().any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="))
        && original_composed_expression(expr, tokens, false, 32, true)
}

// Only an '=' statement target may borrow this exact static key read. The
// existing ordinary-index helper also grants compound updates, so stays closed.
fn original_static_member_key_write(expr:&Expr,object:&Expr,index:&Expr,tokens:&[Token])->bool{
    let ExprKind::StaticMember{object:key_object,selector}=&index.kind else{return false};
    let at=tokens.partition_point(|token|token.span.end<=object.span.end);
    let(receiver,tail)=tokens.split_at(at);
    let[open,key@..,close]=tail else{return false};
    let[key_name,scope,member]=key else{return false};
    original_assignment_receiver(object,receiver)
        &&matches!(&key_object.kind,ExprKind::Ident(name)if original_ordinary_call_name(name)&&simple_term(key_object,key_name))
        &&scope.kind==TokenKind::Punctuation&&scope.text=="::"&&scope.span.end.checked_sub(scope.span.start)==Some(2)
        &&member.kind==TokenKind::Ident&&member.text==*selector&&original_ascii_identifier(selector)
        &&member.span.end.checked_sub(member.span.start)==Some(selector.len())
        &&open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
        &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
        &&object.span.end<=open.span.start&&open.span.end<=key_name.span.start
        &&key_name.span.end<=scope.span.start&&scope.span.end<=member.span.start&&member.span.end<=close.span.start
        &&index.span==Span::new(key_name.span.start,member.span.end)
        &&expr.span==Span::new(object.span.start,close.span.end)
        &&original_conditional_child(index,key,false,32)
}

// Called only from original_simple_assignment for actual root compound ops.
// Does NOT change original_plain_index, read/call roles, or assignment binding.
fn original_conditional_key_compound_target(expr:&Expr,object:&Expr,index:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 let ExprKind::Conditional{condition,then_value,else_value}=&index.kind else{return false};
 let at=tokens.partition_point(|token|token.span.end<=object.span.end);
 let(receiver,tail)=tokens.split_at(at);
 let[open,key@..,close]=tail else{return false};
 let(Some(first),Some(last))=(key.first(),key.last())else{return false};
 let question_at=key.partition_point(|token|token.span.end<=condition.span.end);
 let colon_at=key.partition_point(|token|token.span.end<=then_value.span.end);
 let(Some(question),Some(colon))=(key.get(question_at),key.get(colon_at))else{return false};
 (original_assignment_receiver(object,receiver)
   ||matches!(&object.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(object,receiver,depth))
  &&open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
  &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
  &&question.kind==TokenKind::Punctuation&&question.text=="?"&&question.span.end.checked_sub(question.span.start)==Some(1)
  &&colon.kind==TokenKind::Punctuation&&colon.text==":"&&colon.span.end.checked_sub(colon.span.start)==Some(1)
  &&condition.span.end<=question.span.start&&question.span.end<=then_value.span.start
  &&then_value.span.end<=colon.span.start&&colon.span.end<=else_value.span.start
  &&object.span.end<=open.span.start&&open.span.end<=first.span.start
  &&index.span==Span::new(first.span.start,last.span.end)&&last.span.end<=close.span.start
  &&expr.span==Span::new(object.span.start,close.span.end)
  &&original_conditional_child(index,key,true,depth)
}

// Narrow root mutation target: an already-proven plain index followed by an
// actual string key. This grants no read, argument, callee or postfix authority.
fn original_nested_string_index_compound_target(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 let ExprKind::Index{object,index}=&expr.kind else{return false};
 let ExprKind::Index{object:inner_object,index:inner_index}=&object.kind else{return false};
 if !matches!(&index.kind,ExprKind::Literal(value)if matches!(value.original_value(),Some(crate::OriginalTokenValue::String(_)))){return false}
 let at=tokens.partition_point(|token|token.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
 let[open,key@..,close]=tail else{return false};
 let bracket=|t:&Token,w:&str|t.kind==TokenKind::Punctuation&&t.text==w&&t.span.end.checked_sub(t.span.start)==Some(1);
 // The inherited plain-index proof accepts two transport token kinds for
 // brackets. This new authority requires the actual punctuation occurrences.
 let inner_at=receiver.partition_point(|token|token.span.end<=inner_object.span.end);
 let[inner_open,inner_key@..,inner_close]=&receiver[inner_at..]else{return false};
 (matches!(&inner_object.kind,ExprKind::Ident(_))||matches!(&inner_object.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(inner_object,&receiver[..inner_at],depth))
  &&bracket(inner_open,"[")&&bracket(inner_close,"]")
  &&inner_object.span.end<=inner_open.span.start&&inner_open.span.end<=inner_index.span.start
  &&inner_index.span.end<=inner_close.span.start
  &&(!matches!(&inner_index.kind,ExprKind::Member{..})||original_plain_member_chain(inner_index,inner_key,depth))
  &&original_plain_index(object,inner_object,inner_index,receiver,depth)
  &&bracket(open,"[")&&bracket(close,"]")&&object.span.end<=open.span.start
  &&open.span.end<=index.span.start&&index.span.end<=close.span.start
  &&expr.span==Span::new(object.span.start,close.span.end)
  &&original_conditional_child(index,key,false,depth)
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

// Two additional read followers from pinned list_access(). Keep this out of
// original_plain_index: that helper also authenticates mutation targets.
fn original_call_or_safe_read_index(expr: &Expr, tokens: &[Token], depth: usize) -> bool {
    let (object, index, separator) = match &expr.kind {
        ExprKind::Index { object, index } => {
            // Ordinary named call result only. Do not introduce an indexed
            // callable, a safe/method-call receiver, or keyed call arguments.
            let ExprKind::Call { callee, args } = &object.kind else { return false; };
            if !matches!(&callee.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
                || args.iter().any(|argument| matches!(&argument.kind,
                    ExprKind::Binary { op, .. } if op == "=")) {
                return false;
            }
            (object.as_ref(), index.as_ref(), "[")
        }
        ExprKind::SafeIndex { object, index } => {
            // The Pratt parser retains SafeIndex and requires the actual
            // one-token Original SafeLBracket, not a textual ? + [ rewrite.
            if !matches!(&object.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
                &&!matches!(&object.kind,ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..}|ExprKind::Index{..}|ExprKind::SafeIndex{..})
                &&!matches!(&object.kind,ExprKind::Call{callee,..}
                    if matches!(&callee.kind,ExprKind::Ident(name)if original_ordinary_call_name(name))
                        ||matches!(&callee.kind,ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..})){return false}
            (object.as_ref(), index.as_ref(), "?[")
        }
        _ => return false,
    };
    let (Some(first), Some(last)) = (tokens.first(), tokens.last()) else { return false; };
    if expr.span != Span::new(first.span.start, last.span.end) {
        return false;
    }
    let at = tokens.partition_point(|token| token.span.end <= object.span.end);
    let (receiver, tail) = tokens.split_at(at);
    let [open, key @ .., close] = tail else { return false; };
    let member_safe=separator=="?["&&matches!(&object.kind,ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..});
    // Preserve the existing direct-call guard. New ordinary/safe member-call
    // receivers add read-only geometry; the SAME bounded child proof below
    // still owns argument readiness. Mutation target helpers are unchanged.
    let call_safe=separator=="?["&&matches!(&object.kind,ExprKind::Call{..});
    let call_receipt=!call_safe||matches!((&object.kind,receiver),
        (ExprKind::Call{callee,..},[name,call_open,_args@..,call_close])
            if simple_term(callee,name)
                &&call_open.kind==TokenKind::Punctuation&&call_open.text=="("
                &&call_close.kind==TokenKind::Punctuation&&call_close.text==")"
                &&call_open.span.end.checked_sub(call_open.span.start)==Some(1)
                &&call_close.span.end.checked_sub(call_close.span.start)==Some(1)
                &&callee.span.end<=call_open.span.start&&call_open.span.end<=call_close.span.start
                &&object.span==Span::new(name.span.start,call_close.span.end))
        ||(call_safe&&matches!(&object.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..}))
            &&original_read_follow_receiver_geometry(object,receiver,depth));
    // Safe list_access consumes a full value key. The SAME bounded child
    // proof below still decides readiness; this lends no target/callee role.
    // The ordinary named-call-result Index branch keeps its old key cohort.
    let safe_key=separator=="?[";
    let key_receipt=safe_key||matches!(&index.kind,ExprKind::Ident(_)|ExprKind::Literal(_));
    // Keep field-token custody separately from the sole recursive value proof.
    let key_member_receipt=if safe_key&&matches!(&index.kind,ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..}) {
        let mut root=index;let mut remaining=depth;
        loop {match &root.kind {
            ExprKind::Member{object,via_colon:false,..}|ExprKind::SafeMember{object,via_colon:false,..}=>{
                let Some(next)=remaining.checked_sub(1)else{return false};remaining=next;root=object;
            },_=>break,
        }}
        !matches!(root.kind,ExprKind::Ident(_))||original_member_read_chain_using(index,key,depth,true)
    }else{true};
    // Every SafeLBracket is one actual punctuation occurrence.
    let member_receipt=(!member_safe||original_member_read_chain_using(object,receiver,depth,true)||original_direct_call_member_geometry(object,receiver)||original_read_follow_receiver_geometry(object,receiver,depth))
        &&(!safe_key||(open.kind==TokenKind::Punctuation&&open.span.end.checked_sub(open.span.start)==Some(2)
        &&close.kind==TokenKind::Punctuation&&close.span.end.checked_sub(close.span.start)==Some(1)
        &&object.span.end<=open.span.start&&open.span.end<=index.span.start&&index.span.end<=close.span.start));
    call_receipt&&member_receipt&&key_receipt&&key_member_receipt&&matches!(open.kind, TokenKind::Punctuation | TokenKind::Operator)
        && open.text == separator
        && matches!(close.kind, TokenKind::Punctuation | TokenKind::Operator)
        && close.text == "]"
        // A prior ordinary Index is a read receiver only when the SAME bounded
        // read kernel owns its brackets, receiver and key. Keep it out of the
        // shared mutation/callee helpers and consume its proof just once.
        && (if safe_key&&matches!(&object.kind,ExprKind::Index{..}) {
            original_composed_read_index(object,receiver,depth)
        }else{original_conditional_child(object, receiver, false, depth)})
        && original_conditional_child(index, key, false, depth)
}

// Bounded read-only ordinary index trees, including both nested keys and
// sequential follows. Keep outside original_plain_index, also used for lvalues.
fn original_nested_ordinary_read_index(expr: &Expr, tokens: &[Token], depth: usize) -> bool {
    let Some(depth) = depth.checked_sub(1) else { return false; };
    let (Some(first), Some(last)) = (tokens.first(), tokens.last()) else { return false; };
    if expr.span != Span::new(first.span.start, last.span.end) { return false; }
    match &expr.kind {
        ExprKind::Ident(name) => original_ordinary_call_name(name)
            && matches!(tokens, [only] if simple_term(expr, only)),
        ExprKind::Literal(value) => original_decimal(value.as_str())
            && matches!(tokens, [only] if simple_term(expr, only)),
        ExprKind::Index { object, index } => {
            // A numeric value is a key, never a new receiver cohort.
            if !matches!(&object.kind, ExprKind::Ident(_) | ExprKind::Index { .. }) { return false; }
            let at = tokens.partition_point(|token| token.span.end <= object.span.end);
            let (receiver, tail) = tokens.split_at(at);
            let [open, key @ .., close] = tail else { return false; };
            open.kind == TokenKind::Punctuation && open.text == "["
                && close.kind == TokenKind::Punctuation && close.text == "]"
                && original_nested_ordinary_read_index(object, receiver, depth)
                && original_nested_ordinary_read_index(index, key, depth)
        }
        _ => false,
    }
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

// Read value from exactly one ordinary name and its actual postfix operator.
// This supplies no receiver/callee/prefix or general lvalue authority.
fn original_bare_postfix_read(expr:&Expr,tokens:&[Token])->bool{
    let [name,operator]=tokens else{return false};
    let ExprKind::Unary{op,value}=&expr.kind else{return false};
    matches!(&value.kind,ExprKind::Ident(actual) if original_ordinary_call_name(actual)
        &&!matches!(actual.as_str(),"null"|"__PROC__"|"__TYPE__"|"__IMPLIED_TYPE__")
        &&name.kind==TokenKind::Ident&&name.text==*actual
        &&name.span.end.checked_sub(name.span.start)==Some(actual.len()))
        &&simple_term(value,name)&&operator.kind==TokenKind::Operator
        &&operator.span.end.checked_sub(operator.span.start)==Some(2)
        &&name.span.end<=operator.span.start
        &&expr.span==Span::new(name.span.start,operator.span.end)
        &&matches!((op.as_str(),operator.text.as_str()),("post++","++")|("post--","--"))
}
fn original_postfix_call_argument(expr:&Expr,tokens:&[Token])->bool{
    original_bare_postfix_read(expr,tokens)
}

// Exact implicit return-slot scalar DATA, shared with its standalone Original
// receipt. Positional argument use does not make Dot an ordinary name/callee.
fn original_return_slot_read(expr: &Expr, tokens: &[Token]) -> bool {
    matches!((&expr.kind,tokens),(ExprKind::Ident(name),[dot])
        if name=="."&&dot.kind==TokenKind::Punctuation&&dot.text=="."&&dot.span==expr.span)
}

fn original_return_slot_index(expr:&Expr,tokens:&[Token])->bool{original_return_slot_index_at(expr,tokens,32)}
fn original_return_slot_index_at(expr: &Expr, tokens: &[Token],depth:usize) -> bool {
    let Some(depth)=depth.checked_sub(1)else{return false};
    let ExprKind::Index{object,index}=&expr.kind else{return false};
    let[dot,open,key@..,close]=tokens else{return false};
    original_return_slot_read(object,std::slice::from_ref(dot))
        &&open.kind==TokenKind::Punctuation&&open.text=="["
        &&close.kind==TokenKind::Punctuation&&close.text=="]"
        &&expr.span==Span::new(dot.span.start,close.span.end)
        &&original_conditional_child(index,key,true,depth)
}

fn original_return_slot_recursive_call(expr:&Expr,tokens:&[Token])->bool{original_return_slot_recursive_call_at(expr,tokens,32)}
fn original_return_slot_recursive_call_at(expr: &Expr, tokens: &[Token],depth:usize) -> bool {
    let [dot, open, value @ .., close] = tokens else { return false; };
    let ExprKind::Call { callee, args } = &expr.kind else { return false; };
    let [argument] = args.as_slice() else { return false; };
    matches!(&callee.kind, ExprKind::Ident(name) if name == "." && callee.span == dot.span)
        && dot.kind == TokenKind::Punctuation && dot.text == "."
        && open.kind == TokenKind::Punctuation && open.text == "("
        && close.kind == TokenKind::Punctuation && close.text == ")"
        && expr.span == Span::new(dot.span.start, close.span.end)
        && original_return_slot_index_at(argument, value,depth)
}

// Root effect only; leave the shared target/read-key and postfix-value helpers
// unchanged. The scalar Dot and every delimiter/operator is its actual token.
fn original_return_slot_post_update(expr:&Expr,tokens:&[Token])->Option<OriginalSimpleKind>{
 let[dot,operator]=tokens else{return None};let ExprKind::Unary{op,value}=&expr.kind else{return None};
 if !original_return_slot_read(value,std::slice::from_ref(dot))||dot.span.end.checked_sub(dot.span.start)!=Some(1)
  ||operator.kind!=TokenKind::Operator||operator.span.end.checked_sub(operator.span.start)!=Some(2)
  ||dot.span.end>operator.span.start||expr.span!=Span::new(dot.span.start,operator.span.end){return None}
 match(op.as_str(),operator.text.as_str()){("post++","++")=>Some(OriginalSimpleKind::PostIncrementStatement),("post--","--")=>Some(OriginalSimpleKind::PostDecrementStatement),_=>None}
}
fn original_return_slot_index_compound(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};
 if !matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>="){return false}
 let ExprKind::Index{object,index}=&lhs.kind else{return false};let at=tokens.partition_point(|token|token.span.end<=lhs.span.end);let(target,tail)=tokens.split_at(at);
 let[dot,open,_key@..,close]=target else{return false};let[operator,value@..]=tail else{return false};
 let bracket=|t:&Token,text:&str|t.kind==TokenKind::Punctuation&&t.text==text&&t.span.end.checked_sub(t.span.start)==Some(1);
 original_return_slot_read(object,std::slice::from_ref(dot))&&dot.span.end.checked_sub(dot.span.start)==Some(1)
  &&bracket(open,"[")&&bracket(close,"]")&&dot.span.end<=open.span.start&&open.span.end<=index.span.start&&index.span.end<=close.span.start
  &&operator.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)&&operator.text==*op
  &&operator.span.end.checked_sub(operator.span.start)==Some(op.len())&&lhs.span.end<=operator.span.start&&operator.span.end<=rhs.span.start
  &&expr.span==Span::new(dot.span.start,rhs.span.end)&&original_return_slot_index_at(lhs,target,depth)
  &&original_conditional_child(rhs,value,true,depth)
}

fn original_return_slot_index_assignment(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Binary { op, lhs, rhs } = &expr.kind else { return false; };
    if op!="="{return original_return_slot_index_compound(expr,tokens,32)}
    let at = tokens.partition_point(|token| token.span.end <= lhs.span.end);
    let (target, tail) = tokens.split_at(at);
    let [equals, value @ ..] = tail else { return false; };
    op == "=" && equals.kind == TokenKind::Operator && equals.text == "="
        && expr.span == Span::new(lhs.span.start, rhs.span.end)
        && original_return_slot_index(lhs, target)
        // This is the separate exact implicit-return-slot target proof.
        // It must not make dot an ordinary writable name or argument key.
        && (original_return_slot_recursive_call(rhs, value)
            || original_conditional_child(rhs, value, true, 32))
}

// Pinned prefab separators already consumed by original_prefab_tail. The
// native value drops a terminal Slash; its actual token and span still count.
fn original_absolute_prefab(expr:&Expr,tokens:&[Token],path:&str)->bool{
    if !path.starts_with('/')||tokens.is_empty(){return false}
    let mut remaining=path;let mut cursor=expr.span.start;
    for(index,token)in tokens.iter().enumerate(){
        if token.span.start!=cursor||token.span.end.checked_sub(cursor)!=Some(token.text.len()){return false}
        cursor=token.span.end;
        if token.text=="/"||token.text=="."{
            if token.kind!=TokenKind::Punctuation{return false}
            if token.text=="."&&!(index>0&&tokens.get(index+1).is_some_and(|name|
                name.kind==TokenKind::Ident&&matches!(name.text.as_str(),"proc"|"verb"|"var"))
                &&tokens.get(index+2).is_some_and(|slash|slash.kind==TokenKind::Punctuation&&slash.text=="/")){return false}
            if index==tokens.len()-1&&token.text=="/"&&remaining.is_empty(){continue}
        }else if token.kind!=TokenKind::Ident||!original_ascii_identifier(&token.text){return false}
        let Some(tail)=remaining.strip_prefix(token.text.as_str())else{return false};remaining=tail;
    }
    remaining.is_empty()&&cursor==expr.span.end
}

// PROC_REF/VERB_REF expand to nameof(.proc/name)/nameof(.verb/name). Keep this DATA
// confined to the actual nameof argument; it is not an ordinary value/target.
fn original_nameof_relative_proc_argument(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::TypePath(path) = &expr.kind else { return false; };
    let [dot, namespace, slash, name] = tokens else { return false; };
    let (role,selector)=if let Some(selector)=path.strip_prefix(".proc/"){("proc",selector)}
        else if let Some(selector)=path.strip_prefix(".verb/"){("verb",selector)}else{return false};
    original_ascii_identifier(selector)
        && dot.kind == TokenKind::Punctuation && dot.text == "."
        && namespace.kind == TokenKind::Ident && namespace.text == role
        && slash.kind == TokenKind::Punctuation && slash.text == "/"
        && name.kind == TokenKind::Ident && name.text == selector
        && expr.span == Span::new(dot.span.start, name.span.end)
        && tokens.iter().all(|token| token.span.end.checked_sub(token.span.start) == Some(token.text.len()))
        && tokens.windows(2).all(|pair| pair[0].span.end == pair[1].span.start)
}

// Read-only index composition, deliberately outside shared mutation targets.
fn original_composed_read_index(expr:&Expr,tokens:&[Token],depth:usize)->bool{
    let Some(depth)=depth.checked_sub(1)else{return false};
    let ExprKind::Index{object,index}=&expr.kind else{return false};
    let at=tokens.partition_point(|token|token.span.end<=object.span.end);
    let(receiver,tail)=tokens.split_at(at);
    matches!(tail,[open,key@..,close]if open.kind==TokenKind::Punctuation&&open.text=="["
        &&close.kind==TokenKind::Punctuation&&close.text=="]"
        &&open.span.end.checked_sub(open.span.start)==Some(1)
        &&close.span.end.checked_sub(close.span.start)==Some(1)
        &&object.span.end<=open.span.start
        &&key.first().is_some_and(|first|open.span.end<=first.span.start)
        &&key.last().is_some_and(|last|last.span.end<=close.span.start)
        &&expr.span==Span::new(object.span.start,close.span.end)
        &&original_composed_expression_mode(object,receiver,false,depth,false,false)
        &&original_conditional_child(index,key,true,depth))
}

// A separate root condition receipt prevents prefix mutations from becoming
// generic Return/local/call-argument values. Each update is the existing exact
// bare-name prefix statement production, only in a comparison operand.
fn original_prefix_condition(expr:&Expr,tokens:&[Token],depth:usize)->bool{
    fn prove(expr:&Expr,tokens:&[Token],depth:usize)->Option<bool>{
        let depth=depth.checked_sub(1)?;
        if original_conditional_child(expr,tokens,true,depth){return Some(false)}
        if let ExprKind::Group(inner)=&expr.kind{
            let[open,body@..,close]=tokens else{return None};
            if open.kind!=TokenKind::Punctuation||open.text!="("||close.kind!=TokenKind::Punctuation||close.text!=")"
                ||expr.span!=Span::new(open.span.start,close.span.end){return None}
            return prove(inner,body,depth)
        }
        let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return None};
        let at=tokens.partition_point(|token|token.span.end<=lhs.span.end);
        let(left,tail)=tokens.split_at(at);let[operator,right@..]=tail else{return None};
        if !matches!(operator.kind,TokenKind::Operator|TokenKind::Punctuation)||operator.text!=*op
            ||expr.span!=Span::new(lhs.span.start,rhs.span.end){return None}
        if matches!(op.as_str(),"=="|"!="|"<"|"<="|">"|">="){
            let binding=original_binary_binding(op)?;
            if original_prefix_update_at(lhs,left,depth).is_none()
                ||matches!(&rhs.kind,ExprKind::Binary{op,..}if original_binary_binding(op).is_none_or(|at|at<=binding))
                ||!original_conditional_child(rhs,right,false,depth){return None}
            return Some(true)
        }
        if !matches!(op.as_str(),"&&"|"||"){return None}
        let binding=original_binary_binding(op)?;
        for(child,minimum)in[(lhs.as_ref(),binding),(rhs.as_ref(),binding+1)]{
            if matches!(&child.kind,ExprKind::Binary{op,..}if original_binary_binding(op).is_none_or(|at|at<minimum)){return None}
        }
        Some(prove(lhs,left,depth)?|prove(rhs,right,depth)?)
    }
    prove(expr,tokens,depth)==Some(true)
}

fn original_composed_expression(
    expr: &Expr, tokens: &[Token], conditional: bool, depth: usize, keyword_call: bool,
) -> bool {
    original_composed_expression_mode(expr,tokens,conditional,depth,keyword_call,true)
}
// Pinned In may own a To pair. A strict ordinary name/member may select
// this closed numeric range; no standalone To or input/locate clause is lent.
fn original_numeric_membership_range(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 let[head@..,in_token,lower,to_token,upper]=tokens else{return false};
 let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};
 let ExprKind::Binary{op:range,lhs:low,rhs:high}=&rhs.kind else{return false};
 op=="in"&&range=="to"
  &&(matches!((&lhs.kind,head),(ExprKind::Ident(name),[only])if original_ordinary_call_name(name)&&simple_term(lhs,only))
    ||matches!(&lhs.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(lhs,head,depth))&&matches!((&low.kind,&high.kind),(ExprKind::Literal(a),ExprKind::Literal(b))if original_decimal(a.as_str())&&original_decimal(b.as_str()))
  &&simple_term(low,lower)&&simple_term(high,upper)
  &&matches!(in_token.kind,TokenKind::Ident|TokenKind::Punctuation)&&in_token.text=="in"&&in_token.span.end.checked_sub(in_token.span.start)==Some(2)
  &&to_token.kind==TokenKind::Ident&&to_token.text=="to"&&to_token.span.end.checked_sub(to_token.span.start)==Some(2)
  &&lhs.span.end<=in_token.span.start&&in_token.span.end<=low.span.start&&low.span.end<=to_token.span.start&&to_token.span.end<=high.span.start
  &&rhs.span==Span::new(low.span.start,high.span.end)&&expr.span==Span::new(lhs.span.start,high.span.end)
  &&original_conditional_child(lhs,head,false,depth)
  &&original_conditional_child(low,std::slice::from_ref(lower),false,depth)&&original_conditional_child(high,std::slice::from_ref(upper),false,depth)
}
fn original_composed_expression_mode(
    expr:&Expr,tokens:&[Token],conditional:bool,depth:usize,keyword_call:bool,read_postfix:bool,
)->bool{
    let Some(depth) = depth.checked_sub(1) else { return false };
    if original_return_slot_recursive_call_at(expr, tokens,depth) {
        return true;
    }
    let (Some(first), Some(last)) = (tokens.first(), tokens.last()) else { return false };
    if expr.span != Span::new(first.span.start, last.span.end) { return false; }

    fn punctuation(token: &Token, spelling: &str) -> bool {
        matches!(token.kind, TokenKind::Punctuation | TokenKind::Operator)
            && token.text == spelling
    }
    fn child_prefix<'a>(child: &Expr, tokens: &'a [Token]) -> (&'a [Token], &'a [Token]) {
        tokens.split_at(tokens.partition_point(|token| token.span.end <= child.span.end))
    }

    let child_value=|child:&Expr,run:&[Token],conditional,depth|original_composed_expression_mode(child,run,conditional,depth,false,read_postfix);
    let receiver_value=|child:&Expr,run:&[Token],conditional,depth|original_composed_expression_mode(child,run,conditional,depth,false,false);
    match &expr.kind {
        ExprKind::Unary{op,..} if matches!(op.as_str(),"post++"|"post--") => read_postfix&&original_bare_postfix_read(expr,tokens),
        ExprKind::Unary{op,..} if matches!(op.as_str(),"pre++"|"pre--") => read_postfix&&original_prefix_update_at(expr,tokens,depth).is_some(),
        // Pinned list/input/pick without an argument list are bare identifiers.
        // Their call productions still have their own syntax.
        ExprKind::Ident(name) => original_return_slot_read(expr,tokens)
            ||((matches!(name.as_str(), "list" | "input" | "pick") || original_ordinary_call_name(name))
                &&matches!(tokens,[only]if simple_term(expr,only))),
        ExprKind::TypePath(path) => original_absolute_prefab(expr,tokens,path),
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
                    if !child_value(child, run, true, depth) { return false; }
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
            // A grouped ordinary member chain is the same completed read
            // child; the existing call production still proves its own arguments. Authenticate its
            // actual group delimiters and closed chain before the sole child proof.
            let grouped_member = matches!(&object.kind,ExprKind::Group(inner)
                if matches!(&inner.kind,ExprKind::Member{via_colon:false,..})
                    &&matches!(receiver,[open,body@..,close]
                        if open.kind==TokenKind::Punctuation&&open.text=="("
                        &&close.kind==TokenKind::Punctuation&&close.text==")"
                        &&open.span.end.checked_sub(open.span.start)==Some(1)
                        &&close.span.end.checked_sub(close.span.start)==Some(1)
                        &&open.span.end<=inner.span.start&&inner.span.end<=close.span.start
                        &&original_plain_member_chain(inner,body,depth)));
            let grouped_intersection=matches!(&object.kind,ExprKind::Group(inner)
                if matches!(&inner.kind,ExprKind::Binary{op,lhs,rhs}if op=="&"
                    &&matches!(&lhs.kind,ExprKind::Ident(_)|ExprKind::Member{via_colon:false,..})
                    &&matches!(&rhs.kind,ExprKind::Ident(_)|ExprKind::Member{via_colon:false,..}))
                &&matches!(receiver,[open,_body@..,close]
                    if open.kind==TokenKind::Punctuation&&open.text=="("&&open.span.end.checked_sub(open.span.start)==Some(1)
                    &&close.kind==TokenKind::Punctuation&&close.text==")"&&close.span.end.checked_sub(close.span.start)==Some(1)
                    &&open.span.end<=inner.span.start&&inner.span.end<=close.span.start));
            let grouped_logical=original_exact_grouped_logical_receiver(object,receiver);
            let grouped_call=matches!(&object.kind,ExprKind::Group(inner)if matches!(&inner.kind,ExprKind::Call{..}))
                &&original_read_follow_receiver_geometry(expr,tokens,depth);
            let mut group_base=object.as_ref();for _ in 0..32{match &group_base.kind{ExprKind::Member{object,via_colon:false,..}|ExprKind::SafeMember{object,via_colon:false,..}=>group_base=object,_=>break}}
            let grouped_call_chain=matches!(&group_base.kind,ExprKind::Group(inner)if matches!(&inner.kind,ExprKind::Call{..}));
            let ordinary_receiver = grouped_call || grouped_logical || grouped_intersection || grouped_member || matches!(&object.kind,
                ExprKind::Ident(_) | ExprKind::Member { via_colon: false, .. }
                    | ExprKind::SafeMember { via_colon: false, .. })
                // Ordinary call results use the same pinned Dot follow() as
                // zero-argument calls. The entire callee/argument prefix MUST
                // independently earn Complete below; this is read-only and
                // does not change the separate plain-member lvalue production.
                || (matches!(&object.kind, ExprKind::Call { callee, .. }
                    if matches!(&callee.kind, ExprKind::Ident(_)
                        | ExprKind::Member { via_colon: false, .. }
                        | ExprKind::SafeMember { via_colon: false, .. })))
                ||matches!(&object.kind,ExprKind::Group(inner)if matches!(&inner.kind,ExprKind::Ident(_)));
            ordinary_receiver
                &&(!grouped_call_chain||original_read_follow_receiver_geometry(expr,tokens,depth))
                && receiver_value(object, receiver, false, depth)
                && matches!(tail, [dot, name] if punctuation(dot, separator) && name.kind == TokenKind::Ident
                    && name.text == *selector && original_ascii_identifier(selector)
                    && ((!grouped_logical&&!grouped_intersection&&!grouped_member&&!matches!(&object.kind,ExprKind::Call{..}))
                        || (dot.kind==TokenKind::Punctuation
                            &&dot.span.end.checked_sub(dot.span.start)==Some(separator.len())
                            &&object.span.end<=dot.span.start&&dot.span.end<=name.span.start
                            &&name.span.end.checked_sub(name.span.start)==Some(selector.len()))))
        }
        ExprKind::StaticMember{object,selector}
        |ExprKind::Member{object,selector,via_colon:true}
        |ExprKind::SafeMember{object,selector,via_colon:true}=>{
            let(receiver,tail)=child_prefix(object,tokens);
            let spelling=match &expr.kind{ExprKind::StaticMember{..}=>"::",ExprKind::SafeMember{..}=>"?:",_=>":"};
            receiver_value(object,receiver,false,depth)
                &&matches!(tail,[separator,name]if punctuation(separator,spelling)
                    &&separator.span.end.checked_sub(separator.span.start)==Some(spelling.len())
                    &&name.kind==TokenKind::Ident&&name.text==*selector&&original_ascii_identifier(selector)
                    &&name.span.end.checked_sub(name.span.start)==Some(selector.len()))
        }
        ExprKind::Unary { op, .. } if op == "new" => original_direct_dynamic_new(expr, tokens, depth)
            || original_absolute_static_new(expr, tokens, depth),
        // Unary operands consume the SAME full primary/follow read. Keep
        // this out of the shared index mutation/callee productions.
        ExprKind::Unary{op,value} if matches!(op.as_str(),"!"|"-"|"~")
            && matches!(&value.kind,ExprKind::Index{..}|ExprKind::SafeIndex{..})=>{
            matches!(tokens,[prefix,child@..]if prefix.kind==TokenKind::Operator&&prefix.text==*op
                &&prefix.span.end.checked_sub(prefix.span.start)==Some(1)&&prefix.span.end<=value.span.start
                &&match &value.kind{ExprKind::Index{..}=>original_composed_read_index(value,child,depth),
                    ExprKind::SafeIndex{..}=>original_call_or_safe_read_index(value,child,depth),_=>false})
        }
        ExprKind::Unary { op, value } if matches!(op.as_str(), "!" | "-" | "~") => {
            matches!(tokens, [prefix, child @ ..] if punctuation(prefix, op)
                && (op != "~" || (prefix.kind==TokenKind::Operator
                    && prefix.span.end.checked_sub(prefix.span.start) == Some(1)
                    && prefix.span.end <= value.span.start))
                && (matches!(&value.kind, ExprKind::Ident(_) | ExprKind::Group(_)
                    | ExprKind::Call { .. } | ExprKind::Member { via_colon: false, .. }
                    | ExprKind::SafeMember { via_colon: false, .. }
                    | ExprKind::Unary { .. } | ExprKind::Literal(_))
                    // Pinned unary() wraps the entire primary input/locate
                    // in-clause, including its full-expression container.
                    // This lends no generic ungrouped Binary unary role.
                    || matches!(crate::native_special_forms::input(value),
                        Ok(Some(form)) if form.in_list.is_some())
                    || matches!(crate::native_special_forms::locate(value),
                        Ok(Some(form)) if form.in_list.is_some())
                    )
                && (child_value(value, child, false, depth)
                    // Exact logical negation of the pinned implicit return
                    // value; do not lend dot a new callee/member/lvalue role.
                    || (op == "!" && matches!((&value.kind,child), (ExprKind::Ident(name),[dot])
                        if name == "." && dot.kind == TokenKind::Punctuation
                            && dot.text == "." && dot.span == value.span))))
        }
        ExprKind::TypeFilter { value, types } => {
            // This is only the SAME primary input's known, nonempty `as`
            // union. No general cast/filter, ignored post-in annotation, or
            // unknown-type recovery is certified by matching DATA strings.
            if types.is_empty() || !matches!(crate::native_special_forms::input(expr),
                Ok(Some(form)) if form.in_list.is_none()) { return false; }
            let (call, tail) = child_prefix(value, tokens);
            let Some((as_keyword, mut remaining)) = tail.split_first() else { return false; };
            if as_keyword.kind != TokenKind::Ident || as_keyword.text != "as" { return false; }
            for (index, name) in types.iter().enumerate() {
                if index != 0 {
                    let Some((bar, tail)) = remaining.split_first() else { return false; };
                    if !punctuation(bar, "|") { return false; }
                    remaining = tail;
                }
                let Some((actual, tail)) = remaining.split_first() else { return false; };
                if actual.kind != TokenKind::Ident || actual.text != *name
                    || !crate::original_input_type_name(name) { return false; }
                remaining = tail;
            }
            remaining.is_empty() && child_value(value, call, false, depth)
        }
        ExprKind::Group(value) => {
            let [open, body @ .., close] = tokens else { return false; };
            if !punctuation(open, "(") || !punctuation(close, ")") { return false; }
            let grouped_assignment=if let ExprKind::Binary{op,lhs,rhs}=&value.kind{
                let at=body.partition_point(|token|token.span.end<=lhs.span.end);
                let(target,tail)=body.split_at(at);
                let target_allowed=if op=="="{original_assignment_target_with_depth(lhs,target,true,true,depth)
                    ||(matches!(&lhs.kind,ExprKind::Member{via_colon:false,..})&&original_mutation_receiver_has_call(lhs)&&original_observed_mutation_target(lhs,target,depth))
                    ||(original_return_slot_read(lhs,target)&&matches!(target,[dot]if dot.span.end.checked_sub(dot.span.start)==Some(1)))}else{
                    matches!(op.as_str(),"||="|"&&=")&&original_grouped_logical_index_target(lhs,target,depth)
                };
                target_allowed&&tail.split_first().is_some_and(|(equals,right)|
                    equals.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)&&equals.text==*op&&equals.span.end.checked_sub(equals.span.start)==Some(op.len())
                    &&lhs.span.end<=equals.span.start&&equals.span.end<=rhs.span.start
                    &&value.span==Span::new(lhs.span.start,rhs.span.end)
                    &&open.kind==TokenKind::Punctuation&&close.kind==TokenKind::Punctuation
                    &&open.span.end.checked_sub(open.span.start)==Some(1)&&close.span.end.checked_sub(close.span.start)==Some(1)
                    &&open.span.end<=lhs.span.start&&rhs.span.end<=close.span.start
                    &&child_value(rhs,right,true,depth))
            }else{false};
            child_value(value, body, true, depth)||grouped_assignment
        }
        ExprKind::SafeIndex { .. } => original_call_or_safe_read_index(expr, tokens, depth),
        ExprKind::Index { object, index } => {
            if original_call_or_safe_read_index(expr, tokens, depth)
                || original_plain_index(expr, object, index, tokens, depth)
                || original_updated_key_index(expr, object, index, tokens)
                || original_nested_ordinary_read_index(expr, tokens, depth)
                || original_composed_read_index(expr,tokens,depth) { return true; }
            let (receiver, tail) = child_prefix(object, tokens);
            (matches!(&object.kind, ExprKind::Ident(_) | ExprKind::Member { via_colon: false, .. })
                || (matches!(&object.kind, ExprKind::Index { .. }) && original_nested_string_index(expr)))
                && receiver_value(object, receiver, false, depth)
                && matches!(tail, [open, key @ .., close] if punctuation(open, "[")
                    && punctuation(close, "]")
                    && (matches!(&index.kind, ExprKind::Ident(_) | ExprKind::Literal(_))
                        || original_read_offset_key(index))
                    && child_value(index, key, false, depth))
        }
        ExprKind::Call { callee, args } => {
            if original_bare_new(expr, tokens) { return true; }
            let (head, rest) = child_prefix(callee, tokens);
            let [open, body @ .., close] = rest else { return false };
            if !punctuation(open, "(") || !punctuation(close, ")")
                || open.span.end.checked_sub(open.span.start)!=Some(1)
                || close.span.end.checked_sub(close.span.start)!=Some(1) { return false; }
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof")
                && matches!(args.as_slice(), [argument] if original_nameof_relative_proc_argument(argument, body))
            {
                return matches!(head, [name] if simple_term(callee, name))
                    && open.kind == TokenKind::Punctuation && close.kind == TokenKind::Punctuation
                    && callee.span.end <= open.span.start && open.span.end <= args[0].span.start
                    && args[0].span.end <= close.span.start;
            }
            let list_constructor = matches!(&callee.kind, ExprKind::Ident(name)
                if matches!(name.as_str(), "list" | "alist"));
            let arguments_match = |args: &[Expr], body: &[Token], keyword_call, trailing, postfix, exact_separator, omissions| {
                let exact_separator = exact_separator || (omissions && args.iter().any(|arg| arg.span.start == arg.span.end));
                let mut remaining = body;
                for (index, argument) in args.iter().enumerate() {
                    if index != 0 {
                        let Some((comma, rest)) = remaining.split_first() else { return false };
                        if !punctuation(comma, ",") || (exact_separator && (comma.kind!=TokenKind::Punctuation
                            ||comma.span.end.checked_sub(comma.span.start)!=Some(1)
                            || (omissions && (open.span.end > comma.span.start || comma.span.end > close.span.start
                                || args[index-1].span.end > comma.span.start || comma.span.end > argument.span.start)))) { return false; }
                        remaining = rest;
                    }
                    // The SAME Pratt call production records an omitted slot as
                    // a zero-width null at the consumed comma's start. It is not
                    // an authored null token, and this comma remains the next
                    // positional separator. Special primitive rosters opt out.
                    if omissions && argument.span.start == argument.span.end
                        && matches!(&argument.kind, ExprKind::Literal(value) if value.as_str() == "null" && value.original_value().is_none())
                    {
                        let Some(comma) = remaining.first() else { return false; };
                        if comma.kind != TokenKind::Punctuation || comma.text != ","
                            || comma.span.end.checked_sub(comma.span.start) != Some(1)
                            || argument.span.start != comma.span.start
                            || open.span.end > comma.span.start || comma.span.end > close.span.start { return false; }
                        continue;
                    }
                    let (run, rest) = child_prefix(argument, remaining);
                    let keyword = keyword_call && match &argument.kind {
                        ExprKind::Binary { op, lhs, rhs } if op == "=" => {
                            let (key, tail) = child_prefix(lhs, run);
                            let bare_key = matches!(&lhs.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
                                && matches!(key, [only] if simple_term(lhs, only));
                            // Static string keys are also native named icon arguments.
                            // This does not make a String an assignment target.
                            let string_key = (list_constructor || matches!(&callee.kind, ExprKind::Ident(name) if name == "icon"))
                                && matches!((&lhs.kind, key), (ExprKind::Literal(literal), [only])
                                    if only.kind == TokenKind::String && lhs.span == only.span
                                        && literal.as_str() == only.text
                                        && matches!(literal.original_value(), Some(crate::OriginalTokenValue::String(_))));
                            // Associative list keys are values, not writable names.
                            // Reuse the SAME bounded value proof for observed call,
                            // numeric and absolute-prefab keys. These are list values,
                            // never ordinary/icon named keys or assignment targets.
                            let computed_key = list_constructor
                                && (matches!(&lhs.kind, ExprKind::Call { callee, .. }
                                    if matches!(&callee.kind, ExprKind::Ident(name) if original_ordinary_call_name(name)))
                                    || matches!(&lhs.kind, ExprKind::Literal(value) if original_decimal(value.as_str())
                                        || value.original_prepared_body_parts(lhs.span).is_some())
                                    || matches!(&lhs.kind, ExprKind::TypePath(path) if path.starts_with('/')))
                                && child_value(lhs, key, true, depth);
                            (bare_key || string_key || computed_key)
                                && tail.split_first().is_some_and(|(equals, value)| punctuation(equals, "=")
                                    && (!computed_key || (equals.kind == TokenKind::Operator
                                        && equals.span.end.checked_sub(equals.span.start) == Some(1)
                                        && lhs.span.end <= equals.span.start && equals.span.end <= rhs.span.start))
                                    && (!matches!(&callee.kind,ExprKind::Ident(name)if name=="new")
                                        ||(equals.kind==TokenKind::Operator&&equals.span.end.checked_sub(equals.span.start)==Some(1)
                                            &&lhs.span.end<=equals.span.start&&equals.span.end<=rhs.span.start))
                                    && child_value(rhs, value, true, depth))
                        }
                        _ => false,
                    };
                    let post_argument = postfix && original_postfix_call_argument(argument, run);
                    if !keyword && !post_argument && !original_return_slot_read(argument, run)
                        && !child_value(argument, run, true, depth) { return false; }
                    remaining = rest;
                }
                // Pinned separated() consumes a trailing comma without
                // adding an expression. The roster above still excludes
                // synthetic nulls unless this ordinary-call branch explicitly
                // matched their actual comma occurrences above.
                remaining.is_empty() || (trailing && !args.is_empty()
                    && matches!(remaining, [comma] if punctuation(comma, ",")
                        && (!exact_separator || (comma.kind == TokenKind::Punctuation
                            && comma.span.end.checked_sub(comma.span.start) == Some(1)
                            && (!omissions || (open.span.end <= comma.span.start && comma.span.end <= close.span.start
                                && args.last().is_some_and(|last| last.span.end <= comma.span.start)))))))
            };
            if let Ok(Some(form)) = crate::native_special_forms::chained_dispatch(expr) {
                // Borrow the canonical dispatcher role; never certify arbitrary Call(Call).
                let dynamic=matches!(form.target,crate::native_special_forms::DispatchTarget::Dynamic(_));
                let ExprKind::Call { callee: primitive, args: targets } = &callee.kind else { return false };
                let [name, target_open, target_body @ .., target_close] = head else { return false };
                // Existing native lowering supports one or two dynamic target values.
                // Omitted/named/update arguments remain a separate frontier here.
                if dynamic && (!(1..=2).contains(&targets.len())
                    || [open,close,target_open,target_close].iter().any(|token|
                        token.kind!=TokenKind::Punctuation||token.span.end.checked_sub(token.span.start)!=Some(1))) { return false; }
                return callee.span == Span::new(name.span.start, target_close.span.end)
                    && simple_term(primitive, name)
                    && punctuation(target_open, "(") && punctuation(target_close, ")")
                    && arguments_match(targets, target_body, false, false, false, dynamic, false)
                    && arguments_match(args, body, false, false, false, dynamic, false);
            }
            // Pinned Dot + arguments is SelfCall, not an ordinary name or
            // a dynamic/member target. Reuse the exact argument roster and
            // independently witnessed children; dot alone gains no new role.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == ".") {
                return matches!(head, [dot] if dot.kind == TokenKind::Punctuation
                    && dot.text == "." && callee.span == dot.span)
                    && arguments_match(args, body, true, true, true, false, false);
            }
            // Pinned Super + arguments is ParentCall. The actual lexer
            // contributes ONE '..' punctuation occurrence; two Dot tokens
            // may build compatibility DATA but cannot issue this receipt.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "..") {
                return matches!(head, [super_token] if super_token.kind == TokenKind::Punctuation
                    && super_token.text == ".." && callee.span == super_token.span)
                    && arguments_match(args, body, true, true, true, false, false);
            }
            // Pinned input is its own primary primitive. Reuse the SAME
            // positional argument/delimiter proof; its optional typed union
            // is checked separately, without ordinary-call name admission.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "input") {
                return matches!(head, [keyword] if simple_term(callee, keyword))
                    && arguments_match(args, body, false, true, false, false, false);
            }
            // Pinned locate is a distinct primitive, not an ordinary call.
            // Issue the existing coordinate form and one-/two-argument lookup,
            // each with exact positional children. The in-clause/warning
            // context still has its separate primary proof and notices.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate") {
                let two_argument_boundary=args.len()!=2||matches!(args.as_slice(),[first,second]
                    if body.get(body.partition_point(|token|token.span.end<=first.span.end)).is_some_and(|comma|
                        comma.kind==TokenKind::Punctuation&&comma.text==","
                        &&comma.span.end.checked_sub(comma.span.start)==Some(1)
                        &&open.span.end<=first.span.start&&first.span.end<=comma.span.start
                        &&comma.span.end<=second.span.start&&second.span.end<=close.span.start));
                return two_argument_boundary&&matches!(crate::native_special_forms::locate(expr),Ok(Some(form))if form.in_list.is_none())
                    &&matches!(args.len(), 1 | 2 | 3) && matches!(head, [name] if simple_term(callee, name))
                    &&(args.len()!=2||(open.kind==TokenKind::Punctuation&&close.kind==TokenKind::Punctuation
                        &&open.span.end.checked_sub(open.span.start)==Some(1)
                        &&close.span.end.checked_sub(close.span.start)==Some(1)
                        &&callee.span.end<=open.span.start&&open.span.end<=close.span.start))
                    && arguments_match(args, body, false, false, false, args.len()==2, false);
            }
            // Pick's existing primary AST owns each optional weight/value.
            // Recheck only actual comma/semicolon runs and independent children.
            if matches!(&callee.kind,ExprKind::Ident(name)if name=="pick"){
                if args.is_empty()||!matches!(head,[keyword]if simple_term(callee,keyword)){return false}
                let mut remaining=body;
                for(index,argument)in args.iter().enumerate(){
                    if index!=0{let Some((comma,rest))=remaining.split_first()else{return false};if !punctuation(comma,","){return false}remaining=rest;}
                    let(run,rest)=child_prefix(argument,remaining);
                    let valid=if let ExprKind::Binary{op,lhs,rhs}=&argument.kind{if op==";"{
                        let(weight,tail)=child_prefix(lhs,run);
                        tail.split_first().is_some_and(|(semicolon,value)|punctuation(semicolon,";")
                            &&argument.span==Span::new(lhs.span.start,rhs.span.end)
                            &&child_value(lhs,weight,true,depth)&&child_value(rhs,value,true,depth))
                    }else{child_value(argument,run,true,depth)}}else{child_value(argument,run,true,depth)};
                    if !valid{return false}remaining=rest;
                }
                return remaining.is_empty()||matches!(remaining,[comma]if punctuation(comma,","));
            }
            // Pinned NewImplicit has a separate parenthesized argument list.
            // Require exact positional children and both delimiters.
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "new") {
                return args.len() <= 16 && matches!(head, [keyword] if simple_term(callee, keyword))
                    && arguments_match(args, body, true, true, false, true, false);
            }
            // Pinned list and alist share the same constructor argument grammar.
            if list_constructor {
                return matches!(head, [name] if simple_term(callee, name))
                    && arguments_match(args, body, true, true, false, false, false);
            }
            // The same Original follower already authenticated CloseColon
            // against this actual occurrence before emitting via_colon=true.
            // Admit only the authored zero-argument call on a bare receiver;
            // no byte-adjacency inference, dynamic chain or lvalue grant.
            if let ExprKind::Member { object, selector, via_colon: true } = &callee.kind {
                return args.is_empty() && body.is_empty()
                    && original_ordinary_call_name(selector)
                    && matches!(&object.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
                    && matches!(head, [receiver, colon, name]
                        if simple_term(object, receiver)
                            && colon.kind == TokenKind::Punctuation && colon.text == ":"
                            && name.kind == TokenKind::Ident && name.text == *selector
                            && callee.span == Span::new(receiver.span.start,name.span.end));
            }
            let ordinary = match &callee.kind {
                ExprKind::Ident(name) => original_ordinary_call_name(name),
                ExprKind::Member { selector, via_colon: false, .. }
                | ExprKind::SafeMember { selector, via_colon: false, .. } => original_ordinary_call_name(selector),
                _ => false,
            };
            let named_value_call = matches!(&callee.kind, ExprKind::Ident(name)
                if original_ordinary_call_name(name))
                // Ordinary dot-chain calls use the SAME named argument grammar
                // in value position. Reuse the exact closed receiver proof;
                // no safe/colon/call-result target is added by this receipt.
                || (matches!(&callee.kind, ExprKind::Member { selector, via_colon: false, .. }
                    if original_ordinary_call_name(selector))
                    && original_plain_member_chain(callee, head, depth));
            ordinary && receiver_value(callee, head, false, depth)
                && arguments_match(args, body, keyword_call || named_value_call, true, true, false, true)
        }
        ExprKind::Binary { op, lhs, rhs } => {
            if op=="in"&&matches!(&rhs.kind,ExprKind::Binary{op,..}if op=="to"){return original_numeric_membership_range(expr,tokens,depth)}
            // A primary clause is its own native production, not ordinary In.
            // Reuse its actual primary child and independently proved container;
            // the distinct warning/ignored-tail contexts remain unissued below.
            let input_in = op == "in" && matches!(crate::native_special_forms::input(expr),
                Ok(Some(form)) if form.in_list.is_some());
            let locate_in = op == "in" && matches!(crate::native_special_forms::locate(expr),
                Ok(Some(form)) if form.in_list.is_some() && form.args.len() <= 1);
            if input_in || locate_in {
                let (primary, tail) = child_prefix(lhs, tokens);
                let Some((in_keyword, container)) = tail.split_first() else { return false };
                if in_keyword.kind != TokenKind::Ident || in_keyword.text != "in"
                    || in_keyword.span.end.checked_sub(in_keyword.span.start) != Some(2)
                    || lhs.span.end > in_keyword.span.start
                    || in_keyword.span.end > rhs.span.start
                    || expr.span != Span::new(lhs.span.start, rhs.span.end)
                    || !child_value(rhs, container, true, depth) { return false; }
                if input_in {
                    // This same input's pre-as union is already separately
                    // authenticated by the existing TypeFilter child proof.
                    return child_value(lhs, primary, false, depth);
                }
                let ExprKind::Call { callee, args } = &lhs.kind else { return false };
                let [name, open, arguments @ .., close] = primary else { return false };
                matches!(&callee.kind, ExprKind::Ident(value) if value == "locate")
                    && simple_term(callee, name)
                    && punctuation(open, "(") && punctuation(close, ")")
                    && lhs.span == Span::new(name.span.start, close.span.end)
                    && match args.as_slice() {
                        [] => arguments.is_empty(),
                        [argument] => child_value(argument, arguments, true, depth),
                        _ => false,
                    }
            } else {
            // A primary input/locate in-clause is not an ordinary In value.
            // Its separate primitive origins/warnings are not lent by this
            // child-composition cohort (including locate's Err contexts).
            if op=="in"&&(!matches!(crate::native_special_forms::input(expr),Ok(None))
                ||!matches!(crate::native_special_forms::locate(expr),Ok(None))){return false}
            let Some(binding) = original_binary_binding(op) else { return false };
            // This pinned subset is left binding. A right child at the same
            // strength, or either looser child, needs an actual Group node.
            let correct_binding = |child: &Expr, minimum| match &child.kind {
                ExprKind::Binary { op, .. } => original_binary_binding(op).is_some_and(|at| at >= minimum),
                _ => true,
            };
            let (left, tail) = child_prefix(lhs, tokens);
            let Some((operator, right)) = tail.split_first() else { return false };
            (if op=="in" { matches!(operator.kind,TokenKind::Ident|TokenKind::Punctuation)&&operator.text=="in"
                    &&operator.span.end.checked_sub(operator.span.start)==Some(2)
                    &&lhs.span.end<=operator.span.start&&operator.span.end<=rhs.span.start }
                else { punctuation(operator,op) })
                && (!matches!(op.as_str(),"~="|"~!") || (operator.kind==TokenKind::Operator
                    &&operator.span.end.checked_sub(operator.span.start)==Some(2)
                    &&operator.span.start>=lhs.span.end&&operator.span.end<=rhs.span.start))
                && correct_binding(lhs, binding)
                && correct_binding(rhs, binding + 1)
                && child_value(lhs, left, false, depth)
                && child_value(rhs, right, false, depth)
            }
        }
        ExprKind::Conditional { condition, then_value, else_value } if conditional => {
            let (test, tail) = child_prefix(condition, tokens);
            let Some((question, tail)) = tail.split_first() else { return false };
            let (yes, tail) = child_prefix(then_value, tail);
            let Some((colon, no)) = tail.split_first() else { return false };
            // The same Original Pratt branch already distinguished Colon/
            // CloseColon at this consumed separator, using the live scope.
            question.kind==TokenKind::Punctuation&&question.text=="?"
                &&colon.kind==TokenKind::Punctuation&&colon.text==":"
                &&question.span.end.checked_sub(question.span.start)==Some(1)
                &&colon.span.end.checked_sub(colon.span.start)==Some(1)
                &&condition.span.end<=question.span.start&&question.span.end<=then_value.span.start
                &&then_value.span.end<=colon.span.start&&colon.span.end<=else_value.span.start
                && child_value(condition, test, false, depth)
                && child_value(then_value, yes, false, depth)
                // SAME Pratt else expression(2) permits right-associated ?:.
                && child_value(else_value, no, true, depth)
        }
        _ => false,
    }
}

// Exact root prefix-statement receipt, also inspected by the separate bare
// updated read-key role. No generic scalar/callee or shared lvalue admission.
fn original_prefix_update(expr: &Expr, tokens: &[Token]) -> Option<OriginalSimpleKind> {
    original_prefix_update_at(expr, tokens, 32)
}
fn original_prefix_update_at(expr: &Expr, tokens: &[Token], depth: usize) -> Option<OriginalSimpleKind> {
    let [operator, target @ ..] = tokens else { return None; };
    let (first, last) = (target.first()?, target.last()?);
    let ExprKind::Unary { op, value } = &expr.kind else { return None; };
    let target_matches = match &value.kind {
        ExprKind::Ident(name) => original_ordinary_call_name(name)
            && !matches!(name.as_str(), "null" | "__PROC__" | "__TYPE__" | "__IMPLIED_TYPE__")
            && matches!(target, [only] if simple_term(value, only)),
        ExprKind::Member { via_colon: false, .. } => depth.checked_sub(1)
            .is_some_and(|remaining| original_plain_member_chain(value, target, remaining)),
        _ => false,
    };
    if operator.kind != TokenKind::Operator
        || operator.span.end.checked_sub(operator.span.start) != Some(operator.text.len())
        || operator.span.end > first.span.start || !target_matches
        || value.span != Span::new(first.span.start, last.span.end)
        || expr.span != Span::new(operator.span.start, last.span.end) { return None; }
    match (op.as_str(), operator.text.as_str()) {
        ("pre++", "++") => Some(OriginalSimpleKind::PrefixIncrementStatement),
        ("pre--", "--") => Some(OriginalSimpleKind::PrefixDecrementStatement),
        _ => None,
    }
}

// Keep indexed mutations out of the existing postfix helpers used by
// read-index and positional-argument proofs.
// Root-only arithmetic-key postfix cohort. Shared postfix/read-key/lvalue roles stay unchanged.
fn original_offset_indexed_update_statement(expr: &Expr, tokens: &[Token], depth: usize) -> bool {
    let Some(remaining) = depth.checked_sub(1) else { return false; };
    let [head, open, left, arithmetic, right, close, update] = tokens else { return false; };
    let ExprKind::Unary { op, value } = &expr.kind else { return false; };
    let ExprKind::Index { object, index } = &value.kind else { return false; };
    let ExprKind::Binary { op: key_op, lhs, rhs } = &index.kind else { return false; };
    matches!(&object.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
        && simple_term(object, head) && original_read_offset_key(index)
        && matches!(key_op.as_str(), "+" | "-")
        && arithmetic.kind == TokenKind::Operator && arithmetic.text == *key_op
        && arithmetic.span.end.checked_sub(arithmetic.span.start) == Some(1)
        && simple_term(lhs, left) && simple_term(rhs, right)
        && left.span.end <= arithmetic.span.start && arithmetic.span.end <= right.span.start
        && open.kind == TokenKind::Punctuation && open.text == "["
        && close.kind == TokenKind::Punctuation && close.text == "]"
        && open.span.end.checked_sub(open.span.start) == Some(1)
        && close.span.end.checked_sub(close.span.start) == Some(1)
        && object.span.end <= open.span.start && open.span.end <= index.span.start
        && index.span == Span::new(left.span.start, right.span.end)
        && index.span.end <= close.span.start
        && value.span == Span::new(head.span.start, close.span.end)
        && update.kind == TokenKind::Operator
        && matches!((op.as_str(), update.text.as_str()), ("post++", "++") | ("post--", "--"))
        && update.span.end.checked_sub(update.span.start) == Some(2)
        && close.span.end <= update.span.start
        && expr.span == Span::new(head.span.start, update.span.end)
        && original_conditional_child(index, &tokens[2..5], false, remaining)
}

// Exact root update over one nested plain index key, not a shared postfix value.
fn original_nested_key_postfix_root(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(remaining)=depth.checked_sub(1)else{return false};
 let [head,open,key_head,key_open,key_value,key_close,close,update]=tokens else{return false};
 let ExprKind::Unary{op,value}=&expr.kind else{return false};
 let ExprKind::Index{object,index}=&value.kind else{return false};
 let ExprKind::Index{object:key_object,index:key_index}=&index.kind else{return false};
 let bracket=|t:&Token,s:&str|t.kind==TokenKind::Punctuation&&t.text==s&&t.span.end.checked_sub(t.span.start)==Some(1);
 matches!(&object.kind,ExprKind::Ident(n)if original_ordinary_call_name(n))&&simple_term(object,head)
  &&matches!(&key_object.kind,ExprKind::Ident(n)if original_ordinary_call_name(n))&&simple_term(key_object,key_head)&&simple_term(key_index,key_value)
  &&bracket(open,"[")&&bracket(key_open,"[")&&bracket(key_close,"]")&&bracket(close,"]")
  &&head.span.end<=open.span.start&&open.span.end<=key_head.span.start&&key_head.span.end<=key_open.span.start
  &&key_open.span.end<=key_value.span.start&&key_value.span.end<=key_close.span.start&&key_close.span.end<=close.span.start
  &&index.span==Span::new(key_head.span.start,key_close.span.end)&&value.span==Span::new(head.span.start,close.span.end)
  &&update.kind==TokenKind::Operator&&matches!((op.as_str(),update.text.as_str()),("post++","++")|("post--","--"))
  &&update.span.end.checked_sub(update.span.start)==Some(2)&&close.span.end<=update.span.start
  &&expr.span==Span::new(head.span.start,update.span.end)
  &&original_conditional_child(index,&tokens[2..6],false,remaining)
}
// The consuming Original follower has already authenticated Colon/CloseColon.
// Only this root '=' receipt consumes the colon-member target.
fn original_colon_member_root_assignment(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(remaining)=depth.checked_sub(1)else{return false};
 let ExprKind::Binary{op,lhs,rhs}=&expr.kind else{return false};if op!="="{return false}
 let ExprKind::Member{object,selector,via_colon:true}=&lhs.kind else{return false};
 let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
 let[colon,name,equals,value@..]=tail else{return false};
 let receiver_ok=match &object.kind{ExprKind::Ident(n)=>original_ordinary_call_name(n)&&matches!(receiver,[one]if simple_term(object,one)),ExprKind::Member{via_colon:false,..}=>original_plain_member_chain(object,receiver,remaining),_=>false};
 receiver_ok&&colon.kind==TokenKind::Punctuation&&colon.text==":"&&colon.span.end.checked_sub(colon.span.start)==Some(1)
  &&name.kind==TokenKind::Ident&&name.text==*selector&&original_ascii_identifier(selector)&&name.span.end.checked_sub(name.span.start)==Some(selector.len())
  &&object.span.end<=colon.span.start&&colon.span.end<=name.span.start&&lhs.span==Span::new(object.span.start,name.span.end)
  &&equals.kind==crate::original_scalar_transport::original_punctuation_native_kind("=")&&equals.text=="="&&equals.span.end.checked_sub(equals.span.start)==Some(1)
  &&lhs.span.end<=equals.span.start&&equals.span.end<=rhs.span.start&&expr.span==Span::new(lhs.span.start,rhs.span.end)
  &&original_conditional_child(rhs,value,true,remaining)
}

fn original_indexed_update_statement(expr: &Expr, tokens: &[Token]) -> bool {
    if original_nested_key_postfix_root(expr, tokens, 32) { return true; }
    if original_offset_indexed_update_statement(expr, tokens, 32) { return true; }
    let [receiver @ .., operator] = tokens else { return false; };
    let Some(first) = receiver.first() else { return false; };
    let ExprKind::Unary { op, value } = &expr.kind else { return false; };
    let ExprKind::Index { object, index } = &value.kind else { return false; };
    matches!((op.as_str(), operator.text.as_str()), ("post++", "++") | ("post--", "--"))
        && operator.kind == TokenKind::Operator
        && expr.span == Span::new(first.span.start, operator.span.end)
        && operator.span.end.checked_sub(operator.span.start) == Some(2)
        && value.span.end <= operator.span.start
        && (matches!(&object.kind, ExprKind::Ident(name) if original_ordinary_call_name(name))
            || matches!(&object.kind, ExprKind::Member { via_colon: false, .. })
                && {
                    let at=receiver.partition_point(|token| token.span.end<=object.span.end);
                    original_plain_member_chain(object,&receiver[..at],32)
                        && matches!(&receiver[at..],[open,key@..,close]
                            if open.kind==TokenKind::Punctuation&&open.text=="["
                            &&close.kind==TokenKind::Punctuation&&close.text=="]"
                            &&open.span.end.checked_sub(open.span.start)==Some(1)
                            &&close.span.end.checked_sub(close.span.start)==Some(1)
                            &&object.span.end<=open.span.start
                            &&key.first().is_some_and(|first|open.span.end<=first.span.start)
                            &&key.last().is_some_and(|last|last.span.end<=close.span.start))
                })
        && original_plain_index(value, object, index, receiver, 32)
}

// Geometry only: the existing independent receiver proof owns the call.
// Geometry-only read follower. The caller retains the sole bounded VALUE
// proof; this lends no assignment target, update, or callee authority.
fn original_read_follow_receiver_geometry(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(remaining)=depth.checked_sub(1)else{return false};
 let(Some(first),Some(last))=(tokens.first(),tokens.last())else{return false};
 if expr.span!=Span::new(first.span.start,last.span.end){return false}
 let punct=|t:&Token,text:&str|t.kind==TokenKind::Punctuation&&t.text==text&&t.span.end.checked_sub(t.span.start)==Some(text.len());
 match &expr.kind{
  ExprKind::Ident(name)=>original_ordinary_call_name(name)&&matches!(tokens,[only]if simple_term(expr,only)),
  ExprKind::Member{object,selector,via_colon:false}|ExprKind::SafeMember{object,selector,via_colon:false}=>{
   let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(run,tail)=tokens.split_at(at);let[dot,name]=tail else{return false};
   let spelling=if matches!(&expr.kind,ExprKind::SafeMember{..}){"?."}else{"."};
   punct(dot,spelling)&&name.kind==TokenKind::Ident&&name.text==*selector&&original_ordinary_call_name(selector)
    &&name.span.end.checked_sub(name.span.start)==Some(selector.len())&&object.span.end<=dot.span.start&&dot.span.end<=name.span.start
    &&original_read_follow_receiver_geometry(object,run,remaining)
  },
  ExprKind::Group(inner)=>matches!(tokens,[open,body@..,close]if matches!(&inner.kind,ExprKind::Call{..})
   &&punct(open,"(")&&punct(close,")")&&open.span.end<=inner.span.start&&inner.span.end<=close.span.start
   &&original_read_follow_receiver_geometry(inner,body,remaining)),
  ExprKind::Call{callee,args}=>{
   if args.len()>16{return false}
   let at=tokens.partition_point(|t|t.span.end<=callee.span.end);let(callee_tokens,tail)=tokens.split_at(at);let[open,body@..,close]=tail else{return false};
   let callee_ok=match &callee.kind{ExprKind::Ident(name)=>original_ordinary_call_name(name)&&matches!(callee_tokens,[only]if simple_term(callee,only)),
    ExprKind::Member{via_colon:false,..}|ExprKind::SafeMember{via_colon:false,..}=>original_member_read_chain_using(callee,callee_tokens,remaining,true),_=>false};
   if !callee_ok||!punct(open,"(")||!punct(close,")")||callee.span.end>open.span.start||open.span.end>close.span.start{return false}
   let mut end=open.span.end;for t in body{if t.span.start<end||t.span.end.checked_sub(t.span.start)!=Some(t.text.len())||t.span.end>close.span.start{return false}end=t.span.end;}
   let mut run=body;for(i,arg)in args.iter().enumerate(){if i!=0{let Some((comma,rest))=run.split_first()else{return false};if !punct(comma,",")||args[i-1].span.end>comma.span.start||comma.span.end>arg.span.start{return false}run=rest;}
    let at=run.partition_point(|t|t.span.end<=arg.span.end);let(actual,rest)=run.split_at(at);let(Some(first),Some(last))=(actual.first(),actual.last())else{return false};
    if arg.span!=Span::new(first.span.start,last.span.end)||arg.span.start<open.span.end||arg.span.end>close.span.start{return false}run=rest;
   }run.is_empty()
  },_=>false,
 }
}

fn original_direct_call_member_geometry(expr:&Expr,tokens:&[Token])->bool{
 let ExprKind::Member{object,selector,via_colon:false}=&expr.kind else{return false};let ExprKind::Call{callee,..}=&object.kind else{return false};
 let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
 let([head,open,_args@..,close],[dot,name])=(receiver,tail)else{return false};
 matches!(&callee.kind,ExprKind::Ident(n)if original_ordinary_call_name(n))&&simple_term(callee,head)
  &&open.kind==TokenKind::Punctuation&&open.text=="("&&open.span.end.checked_sub(open.span.start)==Some(1)
  &&close.kind==TokenKind::Punctuation&&close.text==")"&&close.span.end.checked_sub(close.span.start)==Some(1)
  &&callee.span.end<=open.span.start&&open.span.end<=close.span.start&&object.span==Span::new(callee.span.start,close.span.end)
  &&dot.kind==TokenKind::Punctuation&&dot.text=="."&&dot.span.end.checked_sub(dot.span.start)==Some(1)
  &&object.span.end<=dot.span.start&&dot.span.end<=name.span.start
  &&name.kind==TokenKind::Ident&&name.text==*selector&&original_ascii_identifier(selector)&&name.span.end.checked_sub(name.span.start)==Some(selector.len())
  &&expr.span==Span::new(object.span.start,name.span.end)
}
// Root-only nested indexed mutations; each inner prefix remains an independent read.
fn original_sequential_index_compound_target(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 let(object,index,spelling)=match &expr.kind{ExprKind::Index{object,index}=>(object,index,"["),ExprKind::SafeIndex{object,index}=>(object,index,"?["),_=>return false};
 if !matches!(&object.kind,ExprKind::Index{..})||!original_index_target_geometry(expr,tokens,depth){return false}
 let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);let[open,key@..,_close]=tail else{return false};
 open.text==spelling&&original_composed_read_index(object,receiver,depth)&&original_conditional_child(index,key,true,depth)
}
fn original_index_target_geometry(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 match &expr.kind{
  ExprKind::Ident(_)=>matches!(tokens,[one]if simple_term(expr,one)),
  ExprKind::Member{via_colon:false,..}=>original_plain_member_chain(expr,tokens,depth),
  ExprKind::Index{object,index}|ExprKind::SafeIndex{object,index}=>{
   let spelling=if matches!(&expr.kind,ExprKind::SafeIndex{..}){"?["}else{"["};
   let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);let[open,key@..,close]=tail else{return false};
   open.kind==TokenKind::Punctuation&&open.text==spelling&&open.span.end.checked_sub(open.span.start)==Some(spelling.len())
    &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
    &&object.span.end<=open.span.start&&open.span.end<=index.span.start&&index.span.end<=close.span.start
    &&expr.span==Span::new(object.span.start,close.span.end)
    &&original_index_target_geometry(object,receiver,depth)&&original_exact_index_key_geometry(index,key,depth)
  },_=>false,
 }
}
// Geometry only; the sole existing bounded child proof still owns values.
// Geometry only for a root compound's ordinary Call key. The existing
// complete indexed-target proof still owns the sole bounded key VALUE proof.
fn original_compound_call_key_geometry(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 if depth==0{return false}
 let ExprKind::Call{callee,args}=&expr.kind else{return false};
 let[head,open,body@..,close]=tokens else{return false};
 let punct=|t:&Token,text:&str|t.kind==TokenKind::Punctuation&&t.text==text&&t.span.end.checked_sub(t.span.start)==Some(text.len());
 if args.len()>16||!matches!(&callee.kind,ExprKind::Ident(n)if original_ordinary_call_name(n))||!simple_term(callee,head)
  ||!punct(open,"(")||!punct(close,")")||head.span.end>open.span.start||open.span.end>close.span.start
  ||expr.span!=Span::new(head.span.start,close.span.end){return false}
 let mut end=head.span.start;
 for t in tokens{
  if t.span.start<end||t.span.end.checked_sub(t.span.start)!=Some(t.text.len()){return false}end=t.span.end;
  if matches!(t.text.as_str(),"("|")"|",")&&t.kind!=TokenKind::Punctuation{return false}
 }
 let mut remaining=body;
 for (i,arg)in args.iter().enumerate(){
  if i!=0{let Some((comma,rest))=remaining.split_first()else{return false};if !punct(comma,",")||args[i-1].span.end>comma.span.start||comma.span.end>arg.span.start{return false}remaining=rest;}
  let at=remaining.partition_point(|t|t.span.end<=arg.span.end);let(run,rest)=remaining.split_at(at);
  let(Some(first),Some(last))=(run.first(),run.last())else{return false};
  if arg.span!=Span::new(first.span.start,last.span.end)||arg.span.start<open.span.end||arg.span.end>close.span.start{return false}remaining=rest;
 }
 remaining.is_empty()
}

fn original_exact_index_key_geometry(expr:&Expr,tokens:&[Token],depth:usize)->bool{
 let Some(depth)=depth.checked_sub(1)else{return false};
 match &expr.kind{
  ExprKind::Ident(_)|ExprKind::Literal(_)=>matches!(tokens,[one]if simple_term(expr,one)),
  ExprKind::Member{via_colon:false,..}=>original_plain_member_chain(expr,tokens,depth),
  ExprKind::Call{callee,args}=>matches!((&callee.kind,args.as_slice(),tokens),(ExprKind::Ident(_),[argument],[head,open,arg@..,close])
    if simple_term(callee,head)&&open.kind==TokenKind::Punctuation&&open.text=="("&&open.span.end.checked_sub(open.span.start)==Some(1)
    &&close.kind==TokenKind::Punctuation&&close.text==")"&&close.span.end.checked_sub(close.span.start)==Some(1)
    &&callee.span.end<=open.span.start&&open.span.end<=argument.span.start&&argument.span.end<=close.span.start&&expr.span==Span::new(callee.span.start,close.span.end)
    &&original_exact_index_key_geometry(argument,arg,depth)),
  ExprKind::Index{object,index}=>{
   let at=tokens.partition_point(|t|t.span.end<=object.span.end);let(receiver,tail)=tokens.split_at(at);
   let[open,key@..,close]=tail else{return false};
   open.kind==TokenKind::Punctuation&&open.text=="["&&open.span.end.checked_sub(open.span.start)==Some(1)
    &&close.kind==TokenKind::Punctuation&&close.text=="]"&&close.span.end.checked_sub(close.span.start)==Some(1)
    &&object.span.end<=open.span.start&&open.span.end<=index.span.start&&index.span.end<=close.span.start
    &&expr.span==Span::new(object.span.start,close.span.end)
    &&original_exact_index_key_geometry(object,receiver,depth)&&original_exact_index_key_geometry(index,key,depth)
  },_=>false,
 }
}
fn original_exact_grouped_logical_receiver(expr:&Expr,tokens:&[Token])->bool{
 let ExprKind::Group(inner)=&expr.kind else{return false};let ExprKind::Binary{op,lhs,rhs}=&inner.kind else{return false};
 let[open,body@..,close]=tokens else{return false};let Some(operator)=body.get(body.partition_point(|t|t.span.end<=lhs.span.end))else{return false};
 matches!(op.as_str(),"||"|"&&")&&operator.kind==crate::original_scalar_transport::original_punctuation_native_kind(op)
  &&operator.text==*op&&operator.span.end.checked_sub(operator.span.start)==Some(2)
  &&lhs.span.end<=operator.span.start&&operator.span.end<=rhs.span.start
  &&open.kind==TokenKind::Punctuation&&open.text=="("&&open.span.end.checked_sub(open.span.start)==Some(1)
  &&close.kind==TokenKind::Punctuation&&close.text==")"&&close.span.end.checked_sub(close.span.start)==Some(1)
  &&open.span.end<=inner.span.start&&inner.span.end<=close.span.start
  &&inner.span==Span::new(lhs.span.start,rhs.span.end)&&expr.span==Span::new(open.span.start,close.span.end)
}

// Statement root only. The shared post-update value/key helpers are unchanged.
fn original_call_member_post_update_root(expr:&Expr,tokens:&[Token])->Option<OriginalSimpleKind>{
 let[receiver@..,operator]=tokens else{return None};let first=receiver.first()?;
 let ExprKind::Unary{op,value}=&expr.kind else{return None};
 if operator.kind!=TokenKind::Operator||operator.span.end.checked_sub(operator.span.start)!=Some(2)
    ||value.span.end>operator.span.start||expr.span!=Span::new(first.span.start,operator.span.end)
    ||!original_call_result_member_root_write(value,receiver,32){return None}
 match(op.as_str(),operator.text.as_str()){
  ("post++","++")=>Some(OriginalSimpleKind::PostIncrementStatement),
  ("post--","--")=>Some(OriginalSimpleKind::PostDecrementStatement),_=>None,
 }
}

fn original_post_update(expr: &Expr, tokens: &[Token]) -> Option<OriginalSimpleKind> {
    let [receiver @ .., operator] = tokens else { return None; };
    let first = receiver.first()?;
    let ExprKind::Unary { op, value } = &expr.kind else { return None; };
    if !(original_assignment_receiver(value, receiver)
        || matches!(&value.kind,ExprKind::Member{via_colon:false,..})&&original_plain_member_chain(value,receiver,32))
        || operator.kind != TokenKind::Operator
        || operator.span.end.checked_sub(operator.span.start)!=Some(2)||value.span.end>operator.span.start
        || expr.span != Span::new(first.span.start, operator.span.end)
    {
        return None;
    }
    match (op.as_str(), operator.text.as_str()) {
        ("post++", "++") => Some(OriginalSimpleKind::PostIncrementStatement),
        ("post--", "--") => Some(OriginalSimpleKind::PostDecrementStatement),
        _ => None,
    }
}

/// A read's key may be the pinned pre/post update of one ordinary name. This
/// deliberately stays outside original_plain_index, also used for write targets.
fn original_updated_key_index(expr: &Expr, object: &Expr, index: &Expr, tokens: &[Token]) -> bool {
    let receiver_end = tokens.partition_point(|token| token.span.end <= object.span.end);
    let (receiver, tail) = tokens.split_at(receiver_end);
    let [open, key @ .., close] = tail else { return false; };
    let Some(first) = receiver.first() else { return false; };
    let ExprKind::Unary { value, .. } = &index.kind else { return false; };
    original_assignment_receiver(object, receiver)
        && matches!(&value.kind, ExprKind::Ident(_))
        && (original_post_update(index, key).is_some() || original_prefix_update(index, key).is_some())
        && matches!(open.kind, TokenKind::Punctuation | TokenKind::Operator) && open.text == "["
        && matches!(close.kind, TokenKind::Punctuation | TokenKind::Operator) && close.text == "]"
        && expr.span == Span::new(first.span.start, close.span.end)
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
        && matches!(&lhs.kind, ExprKind::Ident(name) if name == "input" || original_ordinary_call_name(name))
        && simple_term(lhs, name)
        && expr.span == Span::new(name.span.start, rhs.span.end)
        && original_conditional_child(rhs, value, true, 32)
}

// Root-only macro compound: (ordinary_name op= complete_value). Do not lend
// this witness to argument, return, callee, or shared assignment-target paths.
fn original_grouped_name_compound_assignment(expr: &Expr, tokens: &[Token]) -> bool {
    let ExprKind::Group(inner) = &expr.kind else { return false; };
    let ExprKind::Binary { op, lhs, rhs } = &inner.kind else { return false; };
    let [open, name, equals, value @ .., close] = tokens else { return false; };
    matches!(op.as_str(),"+="|"-="|"*="|"/="|"%="|"|="|"&="|"^="|"<<="|">>=")
        && matches!(&lhs.kind, ExprKind::Ident(target) if original_ordinary_call_name(target)
            && !matches!(target.as_str(), "null" | "__PROC__" | "__TYPE__" | "__IMPLIED_TYPE__"))
        && simple_term(lhs, name)
        && open.kind == TokenKind::Punctuation && open.text == "("
        && close.kind == TokenKind::Punctuation && close.text == ")"
        && equals.kind == crate::original_scalar_transport::original_punctuation_native_kind(op) && equals.text == *op
        &&equals.span.end.checked_sub(equals.span.start)==Some(op.len())&&lhs.span.end<=equals.span.start&&equals.span.end<=rhs.span.start
        &&open.span.end.checked_sub(open.span.start)==Some(1)&&close.span.end.checked_sub(close.span.start)==Some(1)
        &&open.span.end<=lhs.span.start&&rhs.span.end<=close.span.start
        && expr.span == Span::new(open.span.start, close.span.end)
        && inner.span == Span::new(name.span.start, rhs.span.end)
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

// Root read counterpart of the existing composed arithmetic-key Index proof.
// This stays out of shared lvalue/callee helpers. The SAME composed validator
// checks receiver, delimiters, binary binding and all child/root token spans.
// DATA-only eligibility shared by the two READ offset dispatches, never
// write/callee helpers. Existing numeric +/- keys remain; ordinary name+name
// is the additional cohort. Actual token/child proof still follows below.
fn original_read_offset_key(index: &Expr) -> bool {
    let ExprKind::Binary { op, lhs, rhs } = &index.kind else { return false; };
    if !matches!(op.as_str(), "+" | "-") || !matches!(&lhs.kind, ExprKind::Ident(_)) { return false; }
    if matches!(&rhs.kind, ExprKind::Literal(value) if original_decimal(value.as_str())) { return true; }
    let ordinary = |value: &Expr| matches!(&value.kind, ExprKind::Ident(name)
        if original_ordinary_call_name(name)
            && !matches!(name.as_str(), "null" | "__PROC__" | "__TYPE__" | "__IMPLIED_TYPE__"));
    op == "+" && ordinary(lhs) && ordinary(rhs)
}

fn original_offset_read_index(expr: &Expr, tokens: &[Token]) -> bool {
    matches!(&expr.kind, ExprKind::Index { index, .. }
        if original_read_offset_key(index))
        && original_conditional_child(expr, tokens, false, 32)
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
 // Legacy fixed-size flag: exact bare postfix and bounded plain-member/bare prefix updates carry read values.
 let bare_postfix_read=original_profile&&(original_bare_postfix_read(expr,tokens)||original_prefix_update(expr,tokens).is_some());
 let original_composed = original_profile && !bare_postfix_read
     && (original_literal || matches!(&expr.kind, ExprKind::TypePath(_) | ExprKind::Conditional { .. } | ExprKind::Unary { .. }
         | ExprKind::Call { .. } | ExprKind::Binary { .. } | ExprKind::Group(_) | ExprKind::TypeFilter { .. }
         | ExprKind::Member { .. } | ExprKind::SafeMember { .. } | ExprKind::StaticMember { .. } | ExprKind::Index { .. }))
     && original_conditional_child(expr, tokens, true, 32);
 let read_index = original_profile && original_call_or_safe_read_index(expr, tokens, 32);
 let dot_index = original_profile && original_return_slot_index(expr, tokens);
 let plain_index = original_profile && matches!(&expr.kind, ExprKind::Index { object, index }
     if original_plain_index(expr, object, index, tokens, 32)
         || original_updated_key_index(expr, object, index, tokens)
         || original_nested_ordinary_read_index(expr, tokens, 32)
         || original_offset_read_index(expr, tokens));
 let return_slot = original_profile && original_return_slot_read(expr,tokens);
 let kind=if original_profile&&matches!(&expr.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="CRASH")){if original_crash_statement(expr,tokens){OriginalSimpleKind::CrashStatement}else{return None}}else if complete||original_composed||plain_index||read_index||dot_index||return_slot||original_return_list(expr,tokens){OriginalSimpleKind::Complete}else if original_profile&&original_prefix_condition(expr,tokens,32){OriginalSimpleKind::PrefixCondition}else if original_positional_statement_call(expr,tokens)||(original_profile&&original_keyword_statement_call(expr,tokens)){OriginalSimpleKind::OrdinaryCallStatement}else if original_profile&&original_plain_assignment(expr,tokens){OriginalSimpleKind::PlainAssignment}else if original_simple_assignment(expr,tokens,original_profile)||(original_profile&&(original_grouped_field_assignment(expr,tokens)||original_grouped_name_compound_assignment(expr,tokens)||original_return_slot_index_assignment(expr,tokens))){OriginalSimpleKind::SimpleAssignmentStatement}else if original_profile&&original_indexed_update_statement(expr,tokens){OriginalSimpleKind::IndexedUpdateStatement}else if let Some(kind)=original_profile.then(||original_call_member_post_update_root(expr,tokens)).flatten(){kind}else if original_profile{original_post_update(expr,tokens).or_else(||original_return_slot_post_update(expr,tokens)).or_else(||original_prefix_update(expr,tokens))?}else{return None};
 // Preserve the statement kind: only a local initializer can consume this additional value role.
 let initializer_assignment=original_profile&&matches!(&expr.kind,ExprKind::Binary{op,..}if op=="=")
     &&original_root_assignment_chain_value(expr,tokens,32);
 Some(OriginalSimpleExpression{kind,span:expr.span,operator:None,original_profile,bare_postfix_read,initializer_assignment})
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


// These fixtures require Original composite punctuation (not the default
// Native5161687 lex() projection's separate ?/. or +/+ DATA rows).
#[cfg(test)]
fn actual_original_fixture_spans(source:&str,a:&crate::SettingAdmission<'_>)->std::io::Result<Vec<SpanToken>>{
    let mut cursor=crate::NativeTokenCursor::for_original_source_bytes(source.as_bytes());
    let mut tokens=Vec::new();
    loop{match cursor.next_bytes_available_using(source.as_bytes(),true,a,|_,_,message|panic!("valid Original fixture: {message}"))?{
        crate::NativeTokenStep::Token(token)=>tokens.push(token),
        crate::NativeTokenStep::End=>return Ok(tokens),
        other=>panic!("complete Original fixture did not terminate: {other:?}"),
    }}
}

#[cfg(test)]
#[test]
fn original_nested_ordinary_read_index_keeps_complete_brackets_and_refuses_lvalues() {
    let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let admission=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
    for (source,expected) in [
        ("L[R[i]]",Some(OriginalSimpleKind::Complete)),
        ("L[R[1]]",Some(OriginalSimpleKind::Complete)),
        ("L[R[42]]",Some(OriginalSimpleKind::Complete)),
        ("V[i]=L[L[i]]",Some(OriginalSimpleKind::SimpleAssignmentStatement)),
        ("L[R[i+1]]",Some(OriginalSimpleKind::Complete)),("L[R[-1]]",Some(OriginalSimpleKind::Complete)),("L[R[i++]]",Some(OriginalSimpleKind::Complete)),
        ("L[R[lookup(i)]]",Some(OriginalSimpleKind::Complete)),("L[R[S[i]]]",Some(OriginalSimpleKind::Complete)),("L[(R[i])]",Some(OriginalSimpleKind::Complete)),
        ("L[R[i]]=value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("L[R[i]]+=value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("L[R[i]]=V[i]",Some(OriginalSimpleKind::SimpleAssignmentStatement)),
    ] {
        let tokens=actual_original_fixture_spans(source,&admission).unwrap();
        if source=="L[R[i++]]"{assert!(tokens.iter().any(|token|token.kind==TokenKind::Operator&&token.text(source)=="++"));}
        let parsed=parse_expression_original_token_view(source,&tokens,0,&admission,None);
        if expected.is_some(){assert!(parsed.diagnostics.is_empty(),"{source}: {:?}",parsed.diagnostics);}
        assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}");
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
        ("input[input?.len]", true),
        ("input[input.len.extra]", true),
        ("input[length(input)]", true),
        ("input[input.len][1]", true),
    ] {
        let tokens = actual_original_fixture_spans(source,&admission).unwrap();
        if source=="input[input?.len]"{assert!(tokens.iter().any(|token|token.kind==TokenKind::Punctuation&&token.text(source)=="?."));}
        let parsed = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
        if expected { assert!(parsed.diagnostics.is_empty(), "{source}: {:?}", parsed.diagnostics); }
        assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
            expected.then_some(OriginalSimpleKind::Complete), "{source}");
    }
    // Lexing owns punctuation only. It succeeds; the whole expression parser
    // must still refuse because this fixture supplies no actual Colon rows.
    let source="input[input:len]";
    let tokens=actual_original_fixture_spans(source,&admission).unwrap();
    assert!(tokens.iter().any(|token|token.kind==TokenKind::Punctuation&&token.text(source)==":"&&token.span==Span::new(11,12)));
    let parsed=parse_expression_original_token_view(source,&tokens,0,&admission,None);
    assert!(parsed.expr.is_none());
    assert!(parsed.original_simple_expression.is_none());
    let error=admission.take_operational_error().expect("whole parser needs same-issued Colon/CloseColon facts");
    assert_eq!(error.kind(),std::io::ErrorKind::Unsupported);
    assert_eq!(error.to_string(),"Original whole-token colon facts are unissued");
    assert!(admission.is_stopped(),"whole-parser operational failure remains sticky after taking the original error");
    drop(parsed);
    assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());

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
        ("service.ready(arg).value(arg)", true),
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
            assert_eq!(after, crate::SettingChargeCounter::root_allocation_bytes()
                + owned + produced.tokens.capacity() * std::mem::size_of::<Token>()
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
 impl Feed{fn new(rows:&[(TokenKind,&str,Option<bool>)])->Self{let mut at=0;Self{rows:rows.iter().map(|&(kind,text,close)|{let span=Span::new(at,at+text.len());at=span.end;(Token{kind,span,text:text.into()},close)}).collect(),at:0,fail_close:false}}}
 impl NativeExpressionTokenDemand for Feed{
  fn next_token(&mut self)->std::io::Result<Option<Token>>{let row=self.rows.get(self.at);self.at+=1;Ok(row.map(|(t,_)|t.clone()))}
  fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{let(t,_)=self.rows.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(Some(if t.kind==TokenKind::Ident&&t.text=="in"{crate::OriginalTokenValue::Punct("in")}else if t.kind==TokenKind::Ident{crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false}}else{crate::OriginalTokenValue::Punct(match t.text.as_str(){":"=>":","?"=>"?","("=>"(",")"=>")","||"=>"||","&&"=>"&&","&"=>"&","!"=>"!","."=>".","?."=>"?.","=="=>"==","!="=>"!=","["=>"[","]"=>"]","<="=>"<=",">"=>">",">>"=>">>","+"=>"+","*"=>"*","-"=>"-",_=>return Err(std::io::ErrorKind::InvalidInput.into())})}))}
  fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{if self.fail_close{return Err(std::io::Error::from_raw_os_error(1450))}let(t,close)=self.rows.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(*close)}
  fn requires_original_values(&self)->bool{true}
 }
  #[test]
  fn actual_original_index_colon_member_read_requires_issued_close_colon_at_parser_phase(){
   use TokenKind::{Ident as I,Punctuation as P};
   let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
   for close in [Some(true),Some(false),None]{
    // Final producer VALUE controls, not inferred from authored whitespace.
    let rows=[(I,"input",None),(P,"[",None),(I,"input",None),(P,":",close),(I,"len",None),(P,"]",None)];
    let mut feed=Feed::new(&rows);
    let result=parse_original_expression_demanded(&mut feed,&a);
    if close.is_none(){let error=result.err().expect("unissued colon role must refuse");assert_eq!(error.kind(),std::io::ErrorKind::Unsupported);assert_eq!(error.to_string(),"actual Original Colon/CloseColon occurrence is unissued");}
    else{
     let output=result.unwrap();let parsed=output.parsed();
     assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind),close.filter(|value|*value).map(|_|OriginalSimpleKind::Complete));
     if close==Some(true){assert!(parsed.diagnostics.is_empty());assert!(matches!(parsed.expr.as_ref().map(|expr|&expr.kind),Some(ExprKind::Index{index,..})if matches!(&index.kind,ExprKind::Member{via_colon:true,selector,..}if selector=="len")));}
     else{assert!(!parsed.diagnostics.is_empty());}
     drop(output);
    }
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
   }
   // Keep the independent actual-IO scenario on its own real admission.
   let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
   let rows=[(I,"input",None),(P,"[",None),(I,"input",None),(P,":",Some(true)),(I,"len",None),(P,"]",None)];
   let mut feed=Feed::new(&rows);feed.fail_close=true;
   assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));
   assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 #[test]
 fn actual_original_zeroarg_colon_call_requires_its_same_close_colon_receipt() {
  use TokenKind::{Ident as I,Punctuation as P};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for (rows,expected) in [
   (vec![(I,"value",None),(P,":",Some(true)),(I,"dd_SortValue",None),(P,"(",None),(P,")",None)],true),
   (vec![(I,"value",None),(P,":",Some(false)),(I,"dd_SortValue",None),(P,"(",None),(P,")",None)],false),
   (vec![(I,"value",None),(P,":",Some(true)),(I,"dd_SortValue",None),(P,"(",None),(I,"arg",None),(P,")",None)],false),
   (vec![(I,"value",None),(P,".",None),(I,"nested",None),(P,":",Some(true)),(I,"dd_SortValue",None),(P,"(",None),(P,")",None)],false),
   (vec![(I,"value",None),(P,"(",None),(P,")",None),(P,":",Some(true)),(I,"dd_SortValue",None),(P,"(",None),(P,")",None)],false),
  ] {
   let mut source=Feed::new(&rows);
   let output=parse_original_expression_demanded(&mut source,&a).unwrap();
   assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::Complete),"{rows:?}");
   if expected {assert!(output.parsed().diagnostics.is_empty());}
   drop(output);
   assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  let rows=[(I,"value",None),(P,":",None),(I,"dd_SortValue",None),(P,"(",None),(P,")",None)];
  let mut source=Feed::new(&rows);
  assert_eq!(parse_original_expression_demanded(&mut source,&a).err().unwrap().kind(),std::io::ErrorKind::Unsupported,"spelling without actual CloseColon evidence cannot issue availability");
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let rows=[(I,"value",None),(P,":",Some(true)),(I,"dd_SortValue",None),(P,"(",None),(P,")",None)];
  let mut source=Feed::new(&rows);source.fail_close=true;
  assert_eq!(parse_original_expression_demanded(&mut source,&a).err().unwrap().raw_os_error(),Some(1450));
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
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
 // Reuse the established occurrence-aware transport, adding only issued
 // integer values and exact punctuation spellings needed by these controls.
 struct ScalarMembershipFeed(Feed);
 impl NativeExpressionTokenDemand for ScalarMembershipFeed {
     fn next_token(&mut self) -> std::io::Result<Option<Token>> { self.0.next_token() }
     fn original_value(&self, occurrence: NativeExpressionTokenOccurrence)
         -> std::io::Result<Option<crate::OriginalTokenValue<&str>>> {
         let (token, _) = self.0.rows.get(occurrence.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;
         if token.span != occurrence.span() { return Err(std::io::ErrorKind::InvalidInput.into()); }
         Ok(Some(if token.kind == TokenKind::Number {
             crate::OriginalTokenValue::Int(token.text.parse().map_err(|_| std::io::ErrorKind::InvalidData)?)
         } else if token.kind == TokenKind::Ident && token.text != "in" {
             crate::OriginalTokenValue::Ident { spelling: &token.text, whitespace: false }
         } else {
             let index = crate::original_scalar_transport::original_punctuation_storage_index(&token.text)
                 .ok_or(std::io::ErrorKind::InvalidInput)?;
             crate::OriginalTokenValue::Punct(crate::original_scalar_transport::original_punctuation_storage_value(index)
                 .ok_or(std::io::ErrorKind::InvalidInput)?)
         }))
     }
     fn original_close_colon(&self, occurrence: NativeExpressionTokenOccurrence) -> std::io::Result<Option<bool>> {
         self.0.original_close_colon(occurrence)
     }
     fn requires_original_values(&self) -> bool { true }
 }
 #[test]
 fn actual_original_scalar_membership_receipt_requires_the_entire_exact_three_token_production() {
     use TokenKind::{Ident as I, Number as N};
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let ident = |text| (I, text, None);
     let punct = |text| (crate::original_scalar_transport::original_punctuation_native_kind(text), text, (text == ":").then_some(true));
     for (rows, expected) in [
         (vec![ident("null"), ident("in"), ident("list")], true),
         (vec![(N, "0", None), ident("in"), ident("list")], true),
         (vec![(N, "42", None), ident("in"), ident("entries")], true),
         (vec![ident("null"), ident("in"), ident("list"), punct("("), punct(")")], true),
         (vec![ident("null"), ident("in"), ident("list"), punct("."), ident("key")], true),
         (vec![ident("null"), ident("in"), ident("list"), punct("["), (N, "1", None), punct("]")], true),
         (vec![ident("null"), ident("in"), ident("list"), punct("&&"), ident("flag")], true),
         (vec![ident("null"), punct("&&"), ident("flag"), ident("in"), ident("list")], true),
         (vec![ident("null"), ident("in"), ident("first"), ident("to"), ident("last")], false),
         (vec![ident("null"), ident("in"), ident("list"), ident("tail")], false),
     ] {
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.then_some(OriginalSimpleKind::Complete), "{rows:?}");
         if expected {
             assert!(output.parsed().diagnostics.is_empty());
             let expr = output.parsed.expr.as_mut().unwrap();
             assert!(original_plain_membership(expr, &output.tokens));
             let old = expr.span;
             expr.span.end += 1;
             assert!(!original_plain_membership(expr, &output.tokens), "root extent cannot be substituted");
             expr.span = old;
             let ExprKind::Binary { lhs, rhs, .. } = &expr.kind else { panic!("membership root"); };
             if rows.len()==3{
                 assert!(matches!(&lhs.kind,ExprKind::Literal(_)));
                 assert!(matches!(&rhs.kind,ExprKind::Ident(_)));
             }
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(parse_expression("null in list").original_simple_expression.is_none());
 }
 #[test]
 fn actual_original_bare_list_assignment_receipt_does_not_admit_constructor_or_follow_targets() {
     use TokenKind::{Ident as I, Number as N};
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let ident = |text| (I, text, None);
     let punct = |text| (crate::original_scalar_transport::original_punctuation_native_kind(text), text, (text == ":").then_some(true));
     for (target, expected) in [
         (vec![ident("list")], true),
         (vec![ident("list"), punct("("), punct(")")], false),
         (vec![ident("list"), punct("."), ident("key")], false),
         (vec![ident("list"), punct("?."), ident("key")], false),
         (vec![ident("list"), punct(":"), ident("key")], false),
         (vec![ident("list"), punct("["), (N, "1", None), punct("]")], true),
     ] {
         let mut rows = target;
         rows.extend([punct("-="), ident("null")]);
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.then_some(OriginalSimpleKind::SimpleAssignmentStatement), "{rows:?}");
         if expected {
             assert!(output.parsed().diagnostics.is_empty());
             if rows.len()==3{
             assert!(matches!(output.parsed().expr.as_ref().map(|expr| &expr.kind),
                 Some(ExprKind::Binary { op, lhs, rhs }) if op == "-="
                     && matches!(&lhs.kind, ExprKind::Ident(name) if name == "list")
                     && matches!(&rhs.kind, ExprKind::Literal(_))));
             }else{
                 assert!(matches!(output.parsed().expr.as_ref().map(|expr|&expr.kind),
                     Some(ExprKind::Binary{op,lhs,rhs})if op=="-="
                         &&matches!(&lhs.kind,ExprKind::Index{object,index}
                             if matches!(&object.kind,ExprKind::Ident(name)if name=="list")
                                 &&matches!(&index.kind,ExprKind::Literal(value)if value.as_str()=="1"))
                         &&matches!(&rhs.kind,ExprKind::Literal(value)if value.as_str()=="null")));
             }
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 struct PostUpdateFeed(Feed);
 impl NativeExpressionTokenDemand for PostUpdateFeed {
     fn next_token(&mut self) -> std::io::Result<Option<Token>> { self.0.next_token() }
     fn original_value(&self, occurrence: NativeExpressionTokenOccurrence) -> std::io::Result<Option<crate::OriginalTokenValue<&str>>> {
         let (token, _) = self.0.rows.get(occurrence.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;
         if token.span != occurrence.span() { return Err(std::io::ErrorKind::InvalidInput.into()); }
         Ok(Some(if token.kind == TokenKind::Ident {
             crate::OriginalTokenValue::Ident { spelling: &token.text, whitespace: false }
         } else {
             let at = crate::original_scalar_transport::original_punctuation_storage_index(&token.text)
                 .ok_or(std::io::ErrorKind::InvalidInput)?;
             crate::OriginalTokenValue::Punct(crate::original_scalar_transport::original_punctuation_storage_value(at)
                 .ok_or(std::io::ErrorKind::InvalidInput)?)
         }))
     }
     fn original_close_colon(&self, occurrence: NativeExpressionTokenOccurrence) -> std::io::Result<Option<bool>> {
         self.0.original_close_colon(occurrence)
     }
     fn requires_original_values(&self) -> bool { true }
 }

 #[test]
 fn actual_original_bare_postfix_read_values_keep_statement_kind_and_receipt_size() {
     #[allow(dead_code)] struct Prior { kind:OriginalSimpleKind,span:Span,operator:Option<Span>,original_profile:bool }
     assert!(std::mem::size_of::<OriginalSimpleExpression>()<=std::mem::size_of::<Prior>(),"private receipt must consume existing padding only");
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     let mut mismatches=Vec::new();
     for (spelling,expected) in [
         ("safety --",Some(OriginalSimpleKind::PostDecrementStatement)),
         ("! safety --",Some(OriginalSimpleKind::Complete)),
         ("counter ++ + amount",Some(OriginalSimpleKind::Complete)),
         ("consume ( counter ++ )",Some(OriginalSimpleKind::Complete)),
         ("L [ index -- ] = value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("L [ index -- ] += value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("object . index -- + value",None),
         ("( counter ++ ) . field",None),
         ("( counter ++ ) : field",None),
         ("( counter ++ ) :: field",None),
         ("( counter ++ ) [ key ]",None),
         ("( counter ++ ) ( )",None),
         ("consume ( ++ counter )",Some(OriginalSimpleKind::Complete)),
     ] {
         let rows:Vec<_>=spelling.split_whitespace().map(|text| (if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();
         let mut feed=PostUpdateFeed(Feed::new(&rows));
         let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
         let receipt=output.parsed().original_simple_expression;
         let actual=receipt.map(OriginalSimpleExpression::kind);if actual!=expected{mismatches.push((spelling,actual,expected));}
         if spelling=="safety --"{assert!(receipt.unwrap().is_read_value());}
         if expected.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{spelling}");}
         drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
 assert!(mismatches.is_empty(),"all assigned value-role matrix mismatches: {mismatches:?}");
 }
 #[test]
 fn actual_original_bare_postfix_read_proof_requires_exact_owned_occurrences() {
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     for operator in ["++","--"] {
         let rows=[(TokenKind::Ident,"counter",None),(TokenKind::Operator,operator,None)];
         let mut feed=PostUpdateFeed(Feed::new(&rows));
         let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
         let root=output.parsed().expr.as_ref().unwrap();let tokens=&output.tokens;
         assert!(original_bare_postfix_read(root,tokens));
         for mutation in 0..7 {
             let mut altered=tokens.clone();
             match mutation {
                 0=>altered[0].kind=TokenKind::Punctuation,
                 1=>altered[0].span.end-=1,
                 2=>altered[1].kind=TokenKind::Ident,
                 3=>altered[1].kind=TokenKind::Punctuation,
                 4=>altered[1].span.start+=1,
                 5=>altered[1].span.end+=1,
                 _=>altered[1].span.start=altered[0].span.end-1,
             }
             assert!(!original_bare_postfix_read(root,&altered),"{operator} mutation {mutation}");
         }
         drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
     let rows=[(TokenKind::Ident,"L",None),(TokenKind::Punctuation,"[",None),
         (TokenKind::Ident,"i",None),(TokenKind::Operator,"--",None),(TokenKind::Punctuation,"]",None),
         (crate::original_scalar_transport::original_punctuation_native_kind("="),"=",None),(TokenKind::Ident,"value",None)];
     let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
     let root=output.parsed().expr.as_ref().unwrap();assert!(original_simple_assignment(root,&output.tokens,true));
     for mutation in 0..7 {
         let mut altered=output.tokens.clone();match mutation {
             0=>altered[1].kind=TokenKind::Ident,
             1=>altered[1].span.end+=1,
             2=>altered[4].span.start-=1,
             3=>altered[5].kind=TokenKind::Ident,
             4=>altered[5].span.end+=1,
             5=>altered[5].span.start-=1,
             _=>altered[5].span.end=altered[6].span.start+1,
         }
         assert!(!original_simple_assignment(root,&altered,true),"index write mutation {mutation}");
     }
     drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_bare_postfix_read_keeps_first_io_and_real_quota_refund() {
     struct Failure{inner:PostUpdateFeed,pulls:usize,failed:bool}
     impl NativeExpressionTokenDemand for Failure {
         fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no pull after actual IO");self.pulls+=1;if self.pulls==2{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.inner.next_token()}
         fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no value after actual IO");self.inner.original_value(at)}
         fn requires_original_values(&self)->bool{true}
     }
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let rows=[(TokenKind::Ident,"counter",None),(TokenKind::Operator,"++",None)];
     let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     let mut feed=Failure{inner:PostUpdateFeed(Feed::new(&rows)),pulls:0,failed:false};
     let error=parse_original_expression_demanded(&mut feed,&admission).err().unwrap();
     assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(feed.pulls,2);
     assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     let denied=crate::SettingAdmission::new(&used,used.load(Ordering::Acquire),&||Ok(()));
     let mut feed=PostUpdateFeed(Feed::new(&rows));
     assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);
     assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
     assert!(output.parsed().original_simple_expression.unwrap().is_read_value());
     drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn actual_original_member_index_postfix_statements_keep_independent_roles() {
  use OriginalSimpleKind::IndexedUpdateStatement;
  let root=crate::SettingChargeCounter::root_allocation_bytes();
  let used=crate::SettingChargeCounter::try_new(root).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for (source,expected) in [
   ("GLOB . counts [ key ] ++",Some(IndexedUpdateStatement)),
   ("GLOB . counts [ key ] --",Some(IndexedUpdateStatement)),
   ("GLOB ?. counts [ key ] ++",None),
   ("GLOB : counts [ key ] ++",None),
   ("factory ( ) . counts [ key ] ++",None),
   ("GLOB . nested . counts [ key ] ++",None),
   ("GLOB . counts ?[ key ] ++",None),
   ("GLOB . counts [ key ] ++ ( )",None),
   ("consume ( GLOB . counts [ key ] ++ )",None),
  ] {
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();
   let mut feed=PostUpdateFeed(Feed::new(&rows));
   let out=parse_original_expression_demanded(&mut feed,&a).unwrap();
   assert_eq!(out.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}");
   if expected.is_some(){assert!(out.parsed().diagnostics.is_empty());}
   drop(out);assert_eq!(used.load(Ordering::Acquire),root);
  }
 }
 #[test]
 fn actual_original_member_index_postfix_requires_consumed_dot_and_operator_occurrences() {
  let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let rows=[(TokenKind::Ident,"GLOB",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"counts",None),(TokenKind::Punctuation,"[",None),(TokenKind::Ident,"key",None),(TokenKind::Punctuation,"]",None),(TokenKind::Operator,"++",None)];
  let mut feed=PostUpdateFeed(Feed::new(&rows));let mut out=parse_original_expression_demanded(&mut feed,&a).unwrap();
  let expr=out.parsed.expr.as_ref().unwrap();assert!(original_indexed_update_statement(expr,&out.tokens));
  for at in [1,3,5,6]{let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Ident;assert!(!original_indexed_update_statement(expr,&out.tokens));out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_indexed_update_statement(expr,&out.tokens));out.tokens[at]=old;assert!(original_indexed_update_statement(expr,&out.tokens));}
  drop(out);assert_eq!(used.load(Ordering::Acquire),root);
 }
 #[test]
 fn actual_original_member_index_postfix_preserves_first_io_quota_and_drop() {
  let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();
  let rows=[(TokenKind::Ident,"GLOB",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"counts",None),(TokenKind::Punctuation,"[",None),(TokenKind::Ident,"key",None),(TokenKind::Punctuation,"]",None),(TokenKind::Operator,"++",None)];
  struct F{inner:PostUpdateFeed,pulls:usize,fail:usize}
  impl NativeExpressionTokenDemand for F{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.fail{return Err(std::io::Error::from_raw_os_error(1450))}self.inner.next_token()}fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.inner.original_value(at)}fn requires_original_values(&self)->bool{true}}
  for fail in [1,4,8]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=F{inner:PostUpdateFeed(Feed::new(&rows)),pulls:0,fail};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,fail);assert_eq!(used.load(Ordering::Acquire),root);}
  let denied=crate::SettingAdmission::new(&used,root,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),root);
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let out=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(out.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::IndexedUpdateStatement);drop(out);assert_eq!(used.load(Ordering::Acquire),root);
 }
 #[test]
 fn actual_original_post_updates_are_one_dot_statements_or_plain_name_read_keys() {
     use OriginalSimpleKind::{Complete, PostIncrementStatement, PostDecrementStatement, SimpleAssignmentStatement, IndexedUpdateStatement};
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (spelling, expected) in [
         ("i ++", Some(PostIncrementStatement)),
         ("listfrom . len --", Some(PostDecrementStatement)),
         ("listfrom . len ++", Some(PostIncrementStatement)),
         ("L [ Li ++ ]", Some(Complete)),
         ("L [ Li -- ]", Some(Complete)),
         ("result += L [ Li ++ ]", Some(SimpleAssignmentStatement)),
         ("object : len --", None),
         ("object ?. len --", None),
         ("object . nested . len --", Some(PostDecrementStatement)),
         ("object ( ) . len --", Some(PostDecrementStatement)),
         ("L [ i ] --", Some(IndexedUpdateStatement)),
         ("L [ ++ Li ]", Some(Complete)),
         ("L [ object . Li ++ ]", None),
         ("L [ R [ Li ] ++ ]", None),
         ("L [ Li ++ ] = value", Some(SimpleAssignmentStatement)),
         ("L [ Li ++ ] += value", Some(SimpleAssignmentStatement)),
         ("L [ Li ++ ] tail", None),
     ] {
         let rows: Vec<_> = spelling.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(true))
         }).collect();
         let mut feed = PostUpdateFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{spelling}");
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(), "{spelling}"); }
         if spelling == "listfrom . len --" {
             let expr = output.parsed.expr.as_mut().unwrap();
             assert_eq!(original_post_update(expr, &output.tokens), Some(PostDecrementStatement));
             let old = expr.span;
             expr.span.end += 1;
             assert!(original_post_update(expr, &output.tokens).is_none());
             expr.span = old;
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_bare_new_keeps_absent_arguments_and_contextual_target_as_issued() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (spelling, expected, present) in [
         ("new", OriginalSimpleKind::Complete, false),
         ("new ( )", OriginalSimpleKind::Complete, true),
         ("sorter = new", OriginalSimpleKind::PlainAssignment, false),
     ] {
         let rows: Vec<_> = spelling.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert!(output.parsed().diagnostics.is_empty(), "{spelling}");
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), Some(expected), "{spelling}");
         let actual = output.parsed().original_constructor_facts().unwrap().as_slice();
         assert_eq!(actual.len(), 1);
         assert_eq!(actual[0].arguments_present(), present);
         let at = actual[0].span();
         assert_eq!(output.parsed().original_constructor_facts().unwrap().implicit_at_using(at, &admission).unwrap(), Some(present));
         assert_eq!(&output.tokens().iter().find(|token| token.span == at).unwrap().text, "new");
         if spelling == "new" {
             let expr = output.parsed.expr.as_mut().unwrap();
             assert!(original_bare_new(expr, &output.tokens));
             let old = expr.span;
             expr.span.end += 1;
             assert!(!original_bare_new(expr, &output.tokens));
             expr.span = old;
             let ExprKind::Call { callee, args } = &expr.kind else { panic!("native implicit-new representation"); };
             assert!(args.is_empty());
             assert!(matches!(&callee.kind, ExprKind::Ident(name) if name == "new"));
         } else {
             assert!(!original_bare_new(output.parsed().expr.as_ref().unwrap(), output.tokens()));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_bare_new_still_propagates_real_end_read_failure_and_quota() {
     struct FailEnd(ScalarMembershipFeed);
     impl NativeExpressionTokenDemand for FailEnd {
         fn next_token(&mut self) -> std::io::Result<Option<Token>> {
             if self.0.0.at == self.0.0.rows.len() { return Err(std::io::Error::from_raw_os_error(1450)); }
             self.0.next_token()
         }
         fn original_value(&self, at: NativeExpressionTokenOccurrence) -> std::io::Result<Option<crate::OriginalTokenValue<&str>>> { self.0.original_value(at) }
         fn requires_original_values(&self) -> bool { true }
     }
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let rows = [(TokenKind::Ident, "new", None)];
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let mut fail = FailEnd(ScalarMembershipFeed(Feed::new(&rows)));
     match parse_original_expression_demanded(&mut fail, &admission) {
         Err(error) => assert_eq!(error.raw_os_error(), Some(1450)),
         Ok(_) => panic!("actual end read error must survive"),
     }
     assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     let tiny = crate::SettingAdmission::new(&used, crate::SettingChargeCounter::root_allocation_bytes(), &|| Ok(()));
     let mut feed = ScalarMembershipFeed(Feed::new(&rows));
     match parse_original_expression_demanded(&mut feed, &tiny) {
         Err(error) => assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory),
         Ok(_) => panic!("the existing exact admission still decides"),
     }
     assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_sequential_index_reads_compose_in_arguments_without_new_write_or_callee_roles() {
     use OriginalSimpleKind::{Complete, SimpleAssignmentStatement};
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("L [ Li ] [ key ]", Some(Complete)),
         ("L [ Li ] [ key ] [ next ]", Some(Complete)),
         ("L [ R [ i ] ] [ key ]", Some(Complete)),
         ("L [ R [ S [ i ] ] ]", Some(Complete)),
         ("L [ 1 ] [ 42 ]", Some(Complete)),
         ("sorttext ( L [ Li ] [ key ] , R [ Ri ] [ key ] ) < 1", Some(Complete)),
         ("result += L [ Li ] [ key ]", Some(SimpleAssignmentStatement)),
         ("L [ Li ] [ key ] = value", Some(SimpleAssignmentStatement)),
         ("L [ Li ] [ key ] += value", None),
         ("L [ Li ] [ key ] ( )", None),
         ("L [ Li ] [ key ] . callback ( )", None),
         ("L [ Li ] [ key ] : callback ( )", None),
         ("L [ Li ] [ key ] ?. callback ( )", None),
         ("L [ Li ++ ] [ key ]", Some(Complete)),
         ("L [ Li ] [ key ++ ]", Some(Complete)),
         ("L [ Li ] [ object . key ]", Some(Complete)),
         ("L [ Li ] [ lookup ( key ) ]", Some(Complete)),
         ("L [ Li ] [ ( key ) ]", Some(Complete)),
         ("object : L [ Li ] [ key ]", Some(Complete)),
         ("object ?. L [ Li ] [ key ]", Some(Complete)),
         ("lookup ( ) [ Li ] [ key ]", Some(Complete)),
         ("1 [ Li ] [ key ]", Some(Complete)),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(true))
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(), "{source}"); }
         if source == "L [ Li ] [ key ]" {
             let expr = output.parsed.expr.as_mut().unwrap();
             assert!(original_nested_ordinary_read_index(expr, &output.tokens, 32));
             let old = expr.span;
             expr.span.end += 1;
             assert!(!original_nested_ordinary_read_index(expr, &output.tokens, 32));
             expr.span = old;
             assert!(!original_nested_ordinary_read_index(expr, &output.tokens, 1));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
     let source = format!("L{}", "[i]".repeat(40));
     let tokens = lex(&source).tokens;
     let parsed = parse_expression_tokens(&tokens);
     assert!(!original_nested_ordinary_read_index(parsed.expr.as_ref().unwrap(), &tokens, 32));
 }
 #[test]
 fn actual_original_direct_dynamic_new_keeps_runtime_target_and_has_no_implicit_hint() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("new path ( )", Some(OriginalSimpleKind::Complete)),
         ("L += new path ( )", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("new path", Some(OriginalSimpleKind::Complete)),
         ("new path ( value )", Some(OriginalSimpleKind::Complete)),
         ("new object . type ( )", Some(OriginalSimpleKind::Complete)),
         ("new object : type ( )", None),
         ("new object ?. type ( )", None),
         ("new path [ key ] ( )", None),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(true))
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if expected.is_some() {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             assert!(output.parsed().original_constructor_facts().unwrap().as_slice().is_empty(), "dynamic target is not implicit new");
         }
         if source == "new path ( )" {
             let expr = output.parsed.expr.as_mut().unwrap();
             assert!(original_direct_dynamic_new(expr, &output.tokens, 32));
             let old = expr.span;
             expr.span.end += 1;
             assert!(!original_direct_dynamic_new(expr, &output.tokens, 32));
             expr.span = old;
             assert!(matches!(&expr.kind, ExprKind::Unary { op, value } if op == "new"
                 && matches!(&value.kind, ExprKind::Call { callee, args }
                     if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "path"))));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 #[test]
 fn actual_original_indexed_rhs_composition_keeps_store_and_value_roles_separate() {
     use OriginalSimpleKind::{Complete, SimpleAssignmentStatement};
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("RGB [ 1 ] = clamp ( RGB [ 1 ] + value , 0 , 255 )", Some(SimpleAssignmentStatement)),
         ("colorsum [ 1 ] += RGB [ 1 ] * RGB [ 1 ]", Some(SimpleAssignmentStatement)),
         ("RGB [ i ] = flag ? left : right", Some(SimpleAssignmentStatement)),
         (". [ istate ] = 1", Some(SimpleAssignmentStatement)),
         (". [ istate ] = lookup ( value )", Some(SimpleAssignmentStatement)),
         (". [ istate ] = . ( . [ istate ] )", Some(SimpleAssignmentStatement)),
         ("lookup ( RGB [ 1 ] )", Some(Complete)),
         ("lookup ( RGB [ 1 ] = value )", None),
         ("value = ( RGB [ 1 ] = other )", Some(OriginalSimpleKind::PlainAssignment)),
         ("RGB [ 1 ] = ( value = other )", Some(SimpleAssignmentStatement)),
         ("RGB ?[ 1 ] = lookup ( value )", None),
         ("RGB [ i ++ ] = lookup ( value )", Some(SimpleAssignmentStatement)),
         ("get_list ( ) [ i ] = lookup ( value )", Some(SimpleAssignmentStatement)),
         ("RGB [ i ] [ j ] = lookup ( value )", Some(SimpleAssignmentStatement)),
         (". [ istate ] += 1", Some(SimpleAssignmentStatement)),
         ("lookup ( . [ istate ] = 1 )", None),
         (". [ istate + offset ] = 1", Some(SimpleAssignmentStatement)),
     ] {
         let rows:Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(false))
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if let Some(expected) = expected {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             if expected == SimpleAssignmentStatement {
                 let expr = output.parsed.expr.as_mut().unwrap();
                 let check = |e:&Expr,t:&[Token]| original_simple_assignment(e,t,true)
                     || original_return_slot_index_assignment(e,t);
                 assert!(check(expr,&output.tokens));
                 let span=expr.span;expr.span.end+=1;
                 assert!(!check(expr,&output.tokens),"changed whole-store span: {source}");expr.span=span;
                 let bracket=output.tokens.iter().position(|token| token.text=="[").unwrap();
                 let saved=output.tokens[bracket].text.clone();output.tokens[bracket].text="?[".into();
                 assert!(!check(expr,&output.tokens),"changed store bracket: {source}");output.tokens[bracket].text=saved;
                 assert!(check(expr,&output.tokens));
             }
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_dot_index_and_self_call_receipts_require_every_consumed_span() {
     use OriginalSimpleKind::{Complete, SimpleAssignmentStatement};
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         (". [ i ]", Some(Complete)),
         (". ( . [ i ] )", Some(Complete)),
         (". [ i ] = . ( . [ i ] )", Some(SimpleAssignmentStatement)),
         (". [ i ] += . ( . [ i ] )", Some(SimpleAssignmentStatement)),
         (". [ i ] = . ( i )", Some(SimpleAssignmentStatement)),
         (". ( . [ i ] , i )", Some(Complete)),
         (".. ( . [ i ] )", Some(Complete)),
         (". [ i ] [ i ]", Some(Complete)),
         (". ?[ i ]", None),
         (". [ i ++ ]", Some(Complete)),
         (". field ( . [ i ] )", None),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if let Some(expected) = expected {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             let expression = output.parsed.expr.as_mut().unwrap();
             let check = |expr: &Expr, tokens: &[Token]| {
                 if expected == SimpleAssignmentStatement {
                     original_return_slot_index_assignment(expr, tokens)
                 } else if source.starts_with(". (") || source.starts_with(".. (") {
                     original_conditional_child(expr, tokens, true, 32)
                 } else {
                     original_composed_expression(expr,tokens,true,32,false)
                 }
             };
             assert!(check(expression, &output.tokens), "{source}");
             let span = expression.span;
             expression.span.end += 1;
             assert!(!check(expression, &output.tokens), "changed root span: {source}");
             expression.span = span;
             let token_span = output.tokens[0].span;
             output.tokens[0].span.start += 1;
             assert!(!check(expression, &output.tokens), "changed Dot span: {source}");
             output.tokens[0].span = token_span;
             assert!(check(expression, &output.tokens), "same restored receipt: {source}");
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 // The two formerly unissued cases in the dot-index control above are
 // now witnessed by the same complete SelfCall argument grammar, not by
 // widening the return-slot index target helper.
 #[test]
 fn actual_original_self_calls_and_lookup_locate_keep_exact_children_and_roles() {
     use OriginalSimpleKind::{Complete, PlainAssignment, SimpleAssignmentStatement};
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     for(source,expected)in[
         (". ( )",Some(Complete)),(". ( rest )",Some(Complete)),
         (". ( rest , next )",Some(Complete)),(". ( key = rest )",Some(Complete)),
         (". ( rest , )",Some(Complete)),(". += . ( rest )",Some(SimpleAssignmentStatement)),
         ("value = . ( rest )",Some(PlainAssignment)),
         ("consume ( . ( rest ) )",Some(Complete)),
         (". ( , rest )",None),(". ( rest , , next )",None),
         (". ( rest ) ( )",None),(". ( rest ) = next",None),
         (". ( rest ) . field",Some(Complete)),(". : callback ( rest )",None),
         (".. ( rest )",Some(Complete)),
         ("locate ( REF ( icon ) )",Some(Complete)),
         ("value = locate ( REF ( icon ) )",Some(PlainAssignment)),
         ("locate ( x , y , z )",Some(Complete)),
         // Empty Locate was already issued by the unchanged zero-call path.
         ("locate ( )",Some(Complete)),("locate ( x , y )",Some(Complete)),
         ("locate ( x , y , z , other )",None),
         ("locate ( key = rest )",None),("locate ( rest , )",None),
         ("locate ( REF ( icon ) ) ( )",None),
     ]{
         let rows:Vec<_>=source.split_whitespace().map(|text|{
             let kind=if original_ascii_identifier(text){TokenKind::Ident}
                 else{crate::original_scalar_transport::original_punctuation_native_kind(text)};
             (kind,text,(text==":").then_some(false))
         }).collect();
         let mut feed=ScalarMembershipFeed(Feed::new(&rows));
         let mut output=parse_original_expression_demanded(&mut feed,&admission).unwrap_or_else(|e|panic!("{source}: {e}"));
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}");
         if expected.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}
         if source==". ( rest )"||source=="locate ( REF ( icon ) )"{
             let expr=output.parsed.expr.as_mut().unwrap();
             let check=|expr:&Expr,tokens:&[Token]|original_conditional_child(expr,tokens,true,32);
             assert!(check(expr,&output.tokens));
             let root=expr.span;expr.span.end+=1;assert!(!check(expr,&output.tokens));expr.span=root;
             let ExprKind::Call{callee,..}=&mut expr.kind else{panic!("same native Call node")};
             let head=callee.span;callee.span.start+=1;assert!(!check(expr,&output.tokens));
             let ExprKind::Call{callee,..}=&mut expr.kind else{unreachable!()};callee.span=head;
             let ExprKind::Call{args,..}=&mut expr.kind else{unreachable!()};
             let argument=args[0].span;args[0].span.start+=1;assert!(!check(expr,&output.tokens));
             let ExprKind::Call{args,..}=&mut expr.kind else{unreachable!()};args[0].span=argument;
             let spelling=output.tokens[0].text.clone();output.tokens[0].text="..".into();
             assert!(!check(expr,&output.tokens));output.tokens[0].text=spelling;
             assert!(check(expr,&output.tokens));
         }
         drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(parse_expression(".(rest)").original_simple_expression.is_none());
     assert!(parse_expression("locate(REF(icon))").original_simple_expression.is_none());
 }
 #[test]
 fn actual_original_parent_calls_require_one_super_and_independent_arguments() {
     use OriginalSimpleKind::{Complete, PlainAssignment, SimpleAssignmentStatement};
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     let mut cases=vec![
         (".. ( )".to_owned(),Some(Complete)), // pre-existing exact zero-call receipt
         (".. ( value )".to_owned(),Some(Complete)),
         (".. ( left , right )".to_owned(),Some(Complete)),
         (".. ( key = value )".to_owned(),Some(Complete)),
         (".. ( value , )".to_owned(),Some(Complete)),
         (".. ( value ++ )".to_owned(),Some(Complete)),
         (".. ( arglist ( values ) )".to_owned(),Some(Complete)),
         ("value = .. ( other )".to_owned(),Some(PlainAssignment)),
         (". = .. ( value )".to_owned(),Some(SimpleAssignmentStatement)),
         (". [ i ] = .. ( . [ i ] )".to_owned(),Some(SimpleAssignmentStatement)),
         ("consume ( .. ( value ) )".to_owned(),Some(Complete)),
         (". . ( value )".to_owned(),None),(". . ( )".to_owned(),None),
         ("... ( value )".to_owned(),None),("..".to_owned(),None),
         (".. [ value ]".to_owned(),None),
         (".. ( , value )".to_owned(),None),(".. ( value , , other )".to_owned(),None),
         (".. ( value ) = other".to_owned(),None),
         (".. ( value ) ( )".to_owned(),None),(".. ( value ) . field".to_owned(),Some(Complete)),
     ];
     cases.push((format!(".. ( {} )",["value";17].join(" , ")),Some(Complete)));
     for(source,expected)in cases{
         let rows:Vec<_>=source.split_whitespace().map(|text|{
             let kind=if original_ascii_identifier(text){TokenKind::Ident}
                 else{crate::original_scalar_transport::original_punctuation_native_kind(text)};
             (kind,text,None)
         }).collect();
         let mut feed=ScalarMembershipFeed(Feed::new(&rows));
         let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|error|panic!("{source}: {error}"));
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}");
         if expected.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}
         if source==".. ( value )"{
             let root=output.parsed.expr.as_mut().unwrap();
             let exact=|root:&Expr,tokens:&[Token]|original_conditional_child(root,tokens,true,32);
             assert!(exact(root,&output.tokens));
             let span=root.span;root.span.end+=1;assert!(!exact(root,&output.tokens));root.span=span;
             let ExprKind::Call{callee,..}=&mut root.kind else{panic!("same ParentCall node")};
             let span=callee.span;callee.span.start+=1;assert!(!exact(root,&output.tokens));
             let ExprKind::Call{callee,..}=&mut root.kind else{unreachable!()};callee.span=span;
             let ExprKind::Call{args,..}=&mut root.kind else{unreachable!()};
             let span=args[0].span;args[0].span.start+=1;assert!(!exact(root,&output.tokens));
             let ExprKind::Call{args,..}=&mut root.kind else{unreachable!()};args[0].span=span;
             let text=output.tokens[0].text.clone();output.tokens[0].text=".".into();
             assert!(!exact(root,&output.tokens));output.tokens[0].text=text;
             let kind=output.tokens[0].kind;output.tokens[0].kind=TokenKind::Ident;
             assert!(!exact(root,&output.tokens));output.tokens[0].kind=kind;
             assert!(exact(root,&output.tokens));
         }
         drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(parse_expression("..(value)").original_simple_expression.is_none(),"compatibility parser cannot issue Original parent authority");
 }
 #[test]
 fn actual_original_parent_call_keeps_real_end_error_and_admitted_storage() {
     struct FailEnd(ScalarMembershipFeed);
     impl NativeExpressionTokenDemand for FailEnd {
         fn next_token(&mut self)->std::io::Result<Option<Token>>{
             if self.0.0.at==self.0.0.rows.len(){return Err(std::io::Error::from_raw_os_error(1450));}
             self.0.next_token()
         }
         fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.0.original_value(at)}
         fn requires_original_values(&self)->bool{true}
     }
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let rows=[(TokenKind::Punctuation,"..",None),(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"value",None),(TokenKind::Punctuation,")",None)];
     let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     let mut fail=FailEnd(ScalarMembershipFeed(Feed::new(&rows)));
     assert_eq!(parse_original_expression_demanded(&mut fail,&a).err().expect("real read failure").raw_os_error(),Some(1450));
     assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     let tiny=crate::SettingAdmission::new(&used,crate::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
     let mut feed=ScalarMembershipFeed(Feed::new(&rows));
     assert_eq!(parse_original_expression_demanded(&mut feed,&tiny).err().expect("existing quota").kind(),std::io::ErrorKind::OutOfMemory);
     assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn actual_original_self_call_lookup_locate_preserve_first_read_failure_and_quota() {
     struct FailEnd(ScalarMembershipFeed);
     impl NativeExpressionTokenDemand for FailEnd {
         fn next_token(&mut self)->std::io::Result<Option<Token>>{
             if self.0.0.at==self.0.0.rows.len(){return Err(std::io::Error::from_raw_os_error(1450));}
             self.0.next_token()
         }
         fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.0.original_value(at)}
         fn requires_original_values(&self)->bool{true}
     }
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     for source in [". ( rest )","locate ( REF ( icon ) )"]{
         let rows:Vec<_>=source.split_whitespace().map(|text|{
             let kind=if original_ascii_identifier(text){TokenKind::Ident}
                 else{crate::original_scalar_transport::original_punctuation_native_kind(text)};
             (kind,text,None)
         }).collect();
         let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
         let mut fail=FailEnd(ScalarMembershipFeed(Feed::new(&rows)));
         let error=parse_original_expression_demanded(&mut fail,&admission).err().expect("same actual end read failure");
         assert_eq!(error.raw_os_error(),Some(1450),"{source}");
         assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
         let tiny=crate::SettingAdmission::new(&used,crate::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
         let mut feed=ScalarMembershipFeed(Feed::new(&rows));
         let error=parse_original_expression_demanded(&mut feed,&tiny).err().expect("existing admission must refuse");
         assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory,"{source}");
         assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 #[test]
 fn actual_original_list_root_assignments_do_not_become_read_values() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         (". |= i", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("( keys += ( islist ( key ) ? list ( key ) : key ) )", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("( keys += key )", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         (". |= i + j", Some(OriginalSimpleKind::SimpleAssignmentStatement)), (". |= __TYPE__", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("consume ( . |= i )", None), ("value = ( . |= i )", None),
         ("( object . keys += key )", None), ("( keys -= key )", None),
         ("( keys [ i ] += key )", None), ("( __TYPE__ += key )", None),
         ("consume ( ( keys += key ) )", None), ("value = ( keys += key )", None),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(true))
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(), "{source}"); }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
  #[test]
  fn actual_original_argument_call_member_reads_borrow_complete_receiver_without_lvalue_authority(){
   let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
   for(source,expected)in[
    ("rules_of ( check_obj ) . show_messages",true),
    ("ignore_show_messages || rules_of ( check_obj ) . show_messages",true),
    ("rules_of ( O ) . show_messages && include_objects",true),
    ("! ( cooldowns_view ( prey ) . slip_protect < limit )",true),
    ("consume ( combat_of ( source ) . force )",true),
    ("owner . method ( value ) . field . nested",true),
    ("factory ( ) . field",true),
    ("factory ( value ) . field = value",true),
    ("factory ( value ) . field += value",false),
    ("factory ( value ) . field ++",false),
    ("factory ( key = value ) . field",true),
    ("factory ( ( key = value ) ) . field",true),
    ("factory ( ++ value ) . field",false),
    ("factory ( value ) ?. field",true),
   ]{
    let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();
    let mut feed=ScalarMembershipFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();
    let expected_kind=if matches!(source,"factory ( value ) . field = value"|"factory ( value ) . field += value"){Some(OriginalSimpleKind::SimpleAssignmentStatement)}else if source=="factory ( value ) . field ++"{Some(OriginalSimpleKind::PostIncrementStatement)}else{expected.then_some(OriginalSimpleKind::Complete)};
    assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected_kind,"{source}");
    if expected{assert!(output.parsed().diagnostics.is_empty(),"{source}");assert!(output.parsed().original_simple_expression.unwrap().is_original());}
    drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
   }
  }
  #[test]
  fn actual_original_argument_call_member_read_checks_call_child_and_dot_field_occurrences(){
   let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
   let rows=[(TokenKind::Ident,"rules_of",None),(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"source",None),(TokenKind::Punctuation,")",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"force",None)];
   let mut feed=Feed::new(&rows);let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expression=output.parsed.expr.as_ref().unwrap();
   assert!(original_composed_expression(expression,&output.tokens,true,32,false));
   for index in [0usize,1,2,3,4,5]{let old=output.tokens[index].clone();output.tokens[index].span.end+=1;assert!(!original_composed_expression(expression,&output.tokens,true,32,false),"changed occurrence {index}");output.tokens[index]=old;}
   for(index,kind)in[(4,TokenKind::Ident),(4,TokenKind::Operator),(5,TokenKind::Punctuation)]{let old=output.tokens[index].kind;output.tokens[index].kind=kind;assert!(!original_composed_expression(expression,&output.tokens,true,32,false));output.tokens[index].kind=old;}
   let old=output.tokens[3].text.clone();output.tokens[3].text="]".into();assert!(!original_composed_expression(expression,&output.tokens,true,32,false));output.tokens[3].text=old;
   let compat=parse_expression("rules_of(source).force");assert!(compat.original_simple_expression.is_none_or(|proof|!proof.is_original()),"compatibility parse cannot lend current Original source authority");
   drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  #[test]
  fn actual_original_argument_call_member_read_keeps_first_actual_io_and_quota_refunds(){
   struct Stop{feed:Feed,pulls:usize,stop:usize,failed:bool}
   impl NativeExpressionTokenDemand for Stop{
    fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no pull after first actual IO");self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
    fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no fact loan after first actual IO");self.feed.original_value(o)}
    fn requires_original_values(&self)->bool{true}
   }
   let rows=[(TokenKind::Ident,"rules_of",None),(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"source",None),(TokenKind::Punctuation,")",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"force",None)];
   let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
   for stop in 1..=6{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:Feed::new(&rows),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
   let a=crate::SettingAdmission::new(&used,base,&||Ok(()));let mut feed=Feed::new(&rows);assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  }
 #[test]
 fn actual_original_call_result_and_safe_index_reads_keep_exact_follower_roles() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("rgb2num ( this_color , 1 ) [ 2 ]", true),
         ("ignoreGreyscale && rgb2num ( this_color , 1 ) [ 2 ] == 0", true),
         ("dir_counts ?[ state ]", true),
         ("consume ( dir_counts ?[ state ] )", true),
         ("rgb2num ( this_color , 1 ) [ 2 ] = value", false),
         ("dir_counts ?[ state ] = value", false),
         ("dir_counts ?[ state ] ++", false),
         ("rgb2num ( this_color , 1 ) [ 2 ] ( value )", false),
         ("dir_counts ?[ state ] ( value )", false),
         ("dir_counts ? [ state ]", false),
         ("dir_counts ?[ state ++ ]", true),
         ("dir_counts ?[ state ] [ key ]", true),
         ("object . method ( value ) [ 2 ]", true),
         ("rgb2num ( this_color , 1 ) [ key + 1 ]", true),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else if original_decimal(text) { TokenKind::Number }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         let call_index_write=source=="rgb2num ( this_color , 1 ) [ 2 ] = value";
         let wanted=if call_index_write{Some(OriginalSimpleKind::SimpleAssignmentStatement)}else{expected.then_some(OriginalSimpleKind::Complete)};
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),wanted,"{source}");
         if call_index_write{assert!(output.parsed().diagnostics.is_empty());assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind,ExprKind::Binary{op,lhs,..}if op=="="&&matches!(&lhs.kind,ExprKind::Index{object,..}if matches!(&object.kind,ExprKind::Call{..}))));}
         if expected {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             if source == "dir_counts ?[ state ] [ key ]" {
                 assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind,
                     ExprKind::Index { object, .. } if matches!(&object.kind,ExprKind::SafeIndex { .. })));
             } else if source.starts_with("dir_counts") {
                 assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind, ExprKind::SafeIndex { .. }));
             }
             if source.starts_with("rgb2num") || source.starts_with("dir_counts") {
                 let expression = output.parsed.expr.as_mut().unwrap();
                 if matches!(source,"rgb2num ( this_color , 1 ) [ 2 ]"|"dir_counts ?[ state ]") {
                     assert!(original_call_or_safe_read_index(expression, &output.tokens, 32));
                 }
                 assert!(original_composed_expression(expression, &output.tokens, true, 32, false));
                 let root_span = expression.span;
                 expression.span.end += 1;
                 assert!(!original_composed_expression(expression, &output.tokens, true, 32, false));
                 expression.span = root_span;
                 let bracket = output.tokens.iter().position(|token| matches!(token.text.as_str(), "[" | "?[")).unwrap();
                 let old = output.tokens[bracket].text.clone();
                 output.tokens[bracket].text = if old == "[" { "?[" } else { "[" }.into();
                 assert!(!original_composed_expression(expression, &output.tokens, true, 32, false));
                 output.tokens[bracket].text = old;
                 let object = match &mut expression.kind {
                     ExprKind::Index { object, .. } | ExprKind::SafeIndex { object, .. } => object,
                     _ => unreachable!(),
                 };
                 object.span.end += 1;
                 assert!(!original_composed_expression(expression, &output.tokens, true, 32, false));
             }
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(parse_expression("rgb2num(this_color,1)[2]").original_simple_expression.is_none());
     assert!(parse_expression("dir_counts?[state]").original_simple_expression.is_none());
 }

 #[test]
 fn actual_original_member_compound_values_and_negated_return_slot_keep_exact_roles(){
  use OriginalSimpleKind::{Complete,SimpleAssignmentStatement};
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut mismatches=Vec::new();
  for(source,expected)in[
   ("GLOB . next_station_date_change += 1 * 864000",Some(SimpleAssignmentStatement)),
   ("owner . count -= a + b",Some(SimpleAssignmentStatement)),
   ("owner . count *= choose ( a )",Some(SimpleAssignmentStatement)),
   ("owner . count /= ( a + b )",Some(SimpleAssignmentStatement)),
   ("r |= r << 4",Some(SimpleAssignmentStatement)),
   ("r &= mask | other",Some(SimpleAssignmentStatement)),
   ("r ^= choose ( value )",Some(SimpleAssignmentStatement)),
   ("consume ( r |= r << 4 )",None),
   ("consume ( owner . count += 1 * 2 )",None),
   ("owner . nested . count += 1 * 2",Some(SimpleAssignmentStatement)),
   ("owner . count += 1 *",None),("owner . count %= a + b",Some(SimpleAssignmentStatement)),
   ("! .",Some(Complete)),("! ! .",Some(Complete)),
   ("- .",Some(Complete)),("consume ( . )",Some(Complete)),(". field",None),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|{
    let kind=if original_ascii_identifier(text){TokenKind::Ident}else if original_decimal(text){TokenKind::Number}
     else{crate::original_scalar_transport::original_punctuation_native_kind(text)};(kind,text,None)
   }).collect();let mut feed=ScalarMembershipFeed(Feed::new(&rows));
   let output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   let actual=output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind);if actual!=expected{mismatches.push((source,actual,expected));}
   if expected.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}")}
   drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  assert!(mismatches.is_empty(),"all B matrix receipt mismatches: {mismatches:?}");
 }

 #[test]
 fn actual_original_named_value_calls_keep_assignment_only_in_argument_keys() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("getFlatIcon ( A , defdir = NORTH )", true),
         ("mutable_appearance ( I . icon , I . icon_state , plane = 8 , alpha = I . alpha )", true),
         ("value = getFlatIcon ( A , defdir = NORTH )", false),
         ("consume ( value . field = NORTH )", false),
         ("consume ( key = value = NORTH )", false),
         ("consume ( key += value )", false),
         ("getFlatIcon ( A , defdir = NORTH ) = value", false),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else if original_decimal(text) { TokenKind::Number }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         let proof = output.parsed().original_simple_expression;
         assert_eq!(proof.is_some_and(|proof| proof.kind() == OriginalSimpleKind::Complete), expected, "{source}");
         if expected {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind, ExprKind::Call { .. }));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 #[test]
 fn actual_original_bare_input_assignment_requires_an_exact_identifier_target() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("input = copytext ( input , 1 , max_length )", true),
         ("input ( ) = copytext ( value , 1 , max_length )", false),
         ("input [ key ] = copytext ( value , 1 , max_length )", false),
         ("input += copytext ( value , 1 , max_length )", false),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else if original_decimal(text) { TokenKind::Number }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.is_some_and(|proof|
             proof.kind() == OriginalSimpleKind::PlainAssignment), expected, "{source}");
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 struct ExpandedFeed(ScalarMembershipFeed);
 impl NativeExpressionTokenDemand for ExpandedFeed{
  fn next_token(&mut self)->std::io::Result<Option<Token>>{self.0.next_token()}
  fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{let(t,_)=self.0.0.rows.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}
   if t.kind==TokenKind::String{let raw=t.text.strip_prefix('"').and_then(|v|v.strip_suffix('"')).ok_or(std::io::ErrorKind::InvalidInput)?;if raw.contains(['\\','[',']']){return Err(std::io::ErrorKind::InvalidInput.into())}return Ok(Some(crate::OriginalTokenValue::String(raw)))}self.0.original_value(o)}
  fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{self.0.original_close_colon(o)}
  fn requires_original_values(&self)->bool{true}
 }
 fn expanded_feed(source:&str)->ExpandedFeed{let rows:Vec<_>=source.split_whitespace().map(|text|{let kind=if text.starts_with('"')&&text.ends_with('"'){TokenKind::String}else if original_decimal(text){TokenKind::Number}else if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)};(kind,text,(text==":").then_some(false))}).collect();ExpandedFeed(ScalarMembershipFeed(Feed::new(&rows)))}
 fn expanded_expect(source:&str,expected:Option<OriginalSimpleKind>){let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));assert_eq!(output.parsed().original_simple_expression.map(|p|{assert!(p.is_original());p.kind()}),expected,"{source}");if expected.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}




 #[test]fn actual_original_census_member_postfix_and_unary_index_values_keep_independent_roles(){
  use OriginalSimpleKind::{Complete,PostDecrementStatement,PostIncrementStatement};
  for(source,expected)in[("entry . handles . len --",Some(PostDecrementStatement)),("entry . handles . len ++",Some(PostIncrementStatement)),("! entries [ slot_known ( thing ) ]",Some(Complete)),("- effect_str [ corner ]",Some(Complete)),("~ entries [ slot_known ( thing ) ]",Some(Complete)),(". = - effect_str [ corner ]",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("entry ?. handles . len --",None),("factory ( ) . field --",Some(OriginalSimpleKind::PostDecrementStatement)),("entry . handles . len -- ( )",None),("consume ( entry . handles . len -- )",None)]{expanded_expect(source,expected);}
 }
 #[test]fn actual_original_census_right_conditional_and_implicit_new_named_values_keep_children(){
  use OriginalSimpleKind::Complete;
  for source in ["gone ? first : condition ? second : null","new ( timestamp = logger . now ( ) , category = category , )","new ( field = values [ key ] , other = value )"]{expanded_expect(source,Some(Complete));}
  for source in ["new ( object . field = value )","new ( field += value )","new ( , value )",r#"new ( "field" = value )"#]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_census_value_family_occurrences_depth_first_io_and_quota_stay_closed(){
  let sources=["entry . handles . len --","! entries [ slot_known ( thing ) ]","- effect_str [ corner ]","gone ? first : condition ? second : null","new ( field = value , other = other , )"];
  for source in sources{
   let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut output=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();assert!(output.parsed().original_simple_expression.is_some(),"{source}");
   let original=output.tokens[0].span;output.tokens[0].span=Span::new(original.start+1000,original.end+1000);assert!(original_simple_complete(output.parsed.expr.as_ref().unwrap(),&output.tokens,true).is_none(),"foreign root {source}");output.tokens[0].span=original;
   if !source.starts_with("entry") {assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,0,false));}
   for at in 0..output.tokens.len(){if matches!(output.tokens[at].text.as_str(),"."|"?"|":"|"="|"["){
    let kind=output.tokens[at].kind;output.tokens[at].kind=if kind==TokenKind::Operator{TokenKind::Ident}else{TokenKind::Operator};assert!(original_simple_complete(output.parsed.expr.as_ref().unwrap(),&output.tokens,true).is_none(),"wrong occurrence {source} token {at}");output.tokens[at].kind=kind;
   }}drop(output);assert_eq!(used.load(Ordering::Acquire),base);
   struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
   impl NativeExpressionTokenDemand for Stop{
    fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
    fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}
    fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed);self.feed.original_close_colon(o)}
    fn requires_original_values(&self)->bool{true}
   }
   for stop in[1,3,source.split_whitespace().count()+1]{let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
   let tight=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&tight).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  }
  expanded_expect("! entries [ slot_known ( thing ) ]",Some(OriginalSimpleKind::Complete));
 }
 #[test]fn actual_original_ordinary_call_omissions_keep_real_slot_arity_and_explicit_null_distinct(){
  use OriginalSimpleKind::Complete;
  for source in ["consume ( , first , , last )","consume ( , first , )","consume ( first , , last , )","object . ChangeTurf ( my_turf ( ) . type , , 1 )","object ?. consume ( , value )","consume ( null , , value )"]{expanded_expect(source,Some(Complete));}
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let output=parse_original_expression_demanded(&mut expanded_feed("consume ( null , , value )"),&a).unwrap();
  let ExprKind::Call{args,..}=&output.parsed().expr.as_ref().unwrap().kind else{panic!("same actual call")};
  assert_eq!(args.len(),3);assert!(matches!(&args[0].kind,ExprKind::Literal(value) if value.as_str()=="null"));assert!(args[0].span.start<args[0].span.end);assert_eq!(args[0].span,output.tokens().iter().find(|token|token.kind==TokenKind::Ident&&token.text=="null").unwrap().span,"authored null retains its actual nonzero token occurrence");
  assert!(matches!(&args[1].kind,ExprKind::Literal(value) if value.as_str()=="null"&&value.original_value().is_none()));assert_eq!(args[1].span.start,args[1].span.end);
  let commas=output.tokens().iter().filter(|token|token.text==",").collect::<Vec<_>>();assert_eq!(args[1].span.start,commas[1].span.start);assert!(matches!(&args[2].kind,ExprKind::Ident(value)if value=="value"));
  assert!(parse_expression("consume(null,,value)").original_simple_expression.is_none(),"compatibility parser does not grant Original authority");drop(output);assert_eq!(used.load(Ordering::Acquire),base);
  for source in ["call ( target ) ( , value )","call ( , target ) ( value )","pick ( , value )"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_ordinary_call_omissions_require_current_comma_kind_width_and_placeholder_span(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("object . consume ( , , first , , last , )"),&a).unwrap();
  assert!(original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,0,false));
  for at in 0..output.tokens.len(){if output.tokens[at].text==","{
   let kind=output.tokens[at].kind;output.tokens[at].kind=TokenKind::Operator;assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));output.tokens[at].kind=kind;
   let span=output.tokens[at].span;output.tokens[at].span.end+=1;assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));output.tokens[at].span=span;
   output.tokens[at].span=Span::new(span.start+1000,span.end+1000);assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false),"foreign comma occurrence at token {at}, original span {span:?}");output.tokens[at].span=span;
  }}
  let ExprKind::Call{args,..}=&mut output.parsed.expr.as_mut().unwrap().kind else{panic!("same call")};let span=args[1].span;args[1].span=Span::new(span.start+1,span.end+1);
  assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));
  let ExprKind::Call{args,..}=&mut output.parsed.expr.as_mut().unwrap().kind else{unreachable!()};args[1].span=span;
  assert!(original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_ordinary_call_omissions_keep_first_supplier_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no reads after first IO");self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no facts after first IO");self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let source="object . consume ( first , , last )";
  for stop in [1,7,source.split_whitespace().count()+1]{let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }
 #[test]fn actual_original_dynamic_dispatch_uses_two_real_positional_rosters_and_no_ordinary_name_grant(){let mut mismatches=Vec::new();use OriginalSimpleKind::Complete;
  for(source,wanted)in[("call ( proc_ref ) ( arglist ( call_args || list ( ) ) )",Some(Complete)),("call ( E , proc_ref ) ( arglist ( call_args || list ( ) ) )",Some(Complete)),("! ! call ( E , R . when ) ( )",Some(Complete)),("call ( make_target ( ) , make_name ( ) ) ( get_value ( ) )",Some(Complete)),("call ( ( holder || fallback ( ) ) , name ) ( value , other )",Some(Complete)),("call ( target ) ( . )",Some(Complete)),("call ( target )",None),("receiver . call ( target ) ( value )",None),("factory ( target ) ( value )",None),("call ( ) ( value )",None),("call ( a , b , c ) ( value )",None),("call ( target = value ) ( argument )",None),("call ( target ) ( argument = value )",None),("call ( , target ) ( value )",None),("call ( target ) ( , value )",None),("call ( target , ) ( value )",None),("call ( target ) ( value , )",None),("call ( target ) ( index ++ )",Some(Complete)),("call ( target ) ( value ; other )",None),("call_ext ( library , function ) ( value )",Some(Complete))]{let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));let actual=output.parsed().original_simple_expression.map(|p|{assert!(p.is_original());p.kind()});if actual!=wanted{mismatches.push((source,actual,wanted));}if wanted.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}
  assert!(!original_ordinary_call_name("call"));
  for source in ["call(target)(value)","call(E,name)()"]{assert!(parse_expression(source).original_simple_expression.is_none(),"compatibility AST cannot issue Original source authority");}
 assert!(mismatches.is_empty(),"all assigned value-role matrix mismatches: {mismatches:?}");
 }
 #[test]fn actual_original_dynamic_dispatch_checks_primitive_delimiters_separators_and_every_child_span(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed("call ( target , name ) ( value , other )");let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expr=output.parsed.expr.as_ref().unwrap();let exact=|tokens:&[Token]|original_composed_expression(expr,tokens,true,32,false);assert!(exact(&output.tokens));
  for at in 0..output.tokens.len(){
   if matches!(output.tokens[at].text.as_str(),"("|")"|",") {let kind=output.tokens[at].kind;output.tokens[at].kind=TokenKind::Operator;assert!(!exact(&output.tokens));output.tokens[at].kind=kind;let span=output.tokens[at].span;output.tokens[at].span.end+=1;assert!(!exact(&output.tokens));output.tokens[at].span=span;}
  }
  let kind=output.tokens[0].kind;output.tokens[0].kind=TokenKind::Punctuation;assert!(!exact(&output.tokens));output.tokens[0].kind=kind;let text=output.tokens[0].text.clone();output.tokens[0].text="factory".into();assert!(!exact(&output.tokens));output.tokens[0].text=text;assert!(exact(&output.tokens));
  let ExprKind::Call{callee,..}=&mut output.parsed.expr.as_mut().unwrap().kind else{panic!("actual chained call")};let ExprKind::Call{args,..}=&mut callee.kind else{panic!("same primary target list")};let saved=args[0].span;args[0].span.end+=1;assert!(!original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));let ExprKind::Call{callee,..}=&mut output.parsed.expr.as_mut().unwrap().kind else{unreachable!()};let ExprKind::Call{args,..}=&mut callee.kind else{unreachable!()};args[0].span=saved;
  assert!(original_composed_expression(output.parsed.expr.as_ref().unwrap(),&output.tokens,true,32,false));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_dynamic_dispatch_keeps_first_actual_io_and_existing_quota_refunds(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  for source in ["call ( proc_ref ) ( arglist ( call_args || list ( ) ) )","call ( E , proc_ref ) ( value , other )"]{
   for stop in [1,3,source.split_whitespace().count()+1]{let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
   let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,base,&||Ok(()));let mut feed=expanded_feed(source);assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  }
 }
 #[test]fn actual_original_authored_bitnot_equivalence_and_logical_assignments_keep_distinct_roles(){use OriginalSimpleKind::{Complete,SimpleAssignmentStatement};
  let mut mismatches=Vec::new();
  for(source,wanted)in[
   ("rec . queued &= ~ bit",Some(SimpleAssignmentStatement)),("rec . pend_union &= ~ rec . att_pend [ i ]",Some(SimpleAssignmentStatement)),("known &= ~ ( 1 << ( i - 1 ) )",Some(SimpleAssignmentStatement)),
   ("~ flag",Some(Complete)),("~ ~ flag",Some(Complete)),("~ ( flag + other )",Some(Complete)),("~ L [ i ]",Some(Complete)),("~ ( flag = other )",Some(Complete)),("~ ++ flag",Some(Complete)),("& flag",None),("* flag",None),
   ("between ~= via",Some(Complete)),("flat_size ~! add_size",Some(Complete)),("a ~= b & c",Some(Complete)),("a ~! b == c",Some(Complete)),("flag ? a ~= b : c ~! d",Some(Complete)),("a ~ = b",None),("a ~ ! b",None),("a ~= ( b = c )",Some(Complete)),
   ("caps ||= list ( )",Some(SimpleAssignmentStatement)),("temp_gender ||= get_visible_gender ( )",Some(SimpleAssignmentStatement)),("can_set_prefs &&= ! ! user . client . prefs",Some(SimpleAssignmentStatement)),
   ("consume ( flag ||= other )",None),("flag ||= other = value",None),("flag &&= index ++",Some(SimpleAssignmentStatement)),("holder . flag ||= other",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("L [ key ] &&= other",None),(". ||= other",None),("flag | | = other",None)
  ]{let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));let actual=output.parsed().original_simple_expression.map(|proof|{assert!(proof.is_original());proof.kind()});if actual!=wanted{mismatches.push((source,actual,wanted));}if wanted.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}
  assert!(mismatches.is_empty(),"all B matrix receipt mismatches: {mismatches:?}");
  for source in ["~ flag","a ~= b","a ~! b","flag ||= value","flag &&= value"]{assert!(parse_expression(source).original_simple_expression.is_none(),"compatibility tokens never mint Original: {source}");}
 }
 #[test]fn actual_original_operator_loans_check_kind_spelling_exact_extent_and_native_binding(){
  for(source,operator)in[("~ flag","~"),("a ~= b","~="),("a ~! b","~!"),("flag ||= value","||="),("flag &&= value","&&=")]{
   let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   let expr=output.parsed.expr.as_ref().unwrap();let exact=|tokens:&[Token]|if operator.ends_with('=')&&operator.len()==3{original_simple_assignment(expr,tokens,true)}else{original_composed_expression(expr,tokens,true,32,false)};
   assert!(exact(&output.tokens),"{source}");let at=output.tokens.iter().position(|t|t.text==operator).unwrap();let old=output.tokens[at].kind;output.tokens[at].kind=TokenKind::Ident;assert!(!exact(&output.tokens));output.tokens[at].kind=TokenKind::Punctuation;assert!(!exact(&output.tokens));output.tokens[at].kind=old;
   let old=output.tokens[at].text.clone();output.tokens[at].text="=".into();assert!(!exact(&output.tokens));output.tokens[at].text=old;
   let old=output.tokens[at].span;output.tokens[at].span.end+=1;assert!(!exact(&output.tokens));output.tokens[at].span=old;assert!(exact(&output.tokens));
   if matches!(operator,"~="|"~!") {for kind in [TokenKind::Ident,TokenKind::Punctuation]{assert!(!original_augmented_rhs_value(expr,&{let mut t=output.tokens.clone();t[at].kind=kind;t},32));}}
   drop(output);assert_eq!(used.load(Ordering::Acquire),root);
  }
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut feed=expanded_feed("a ~= b & c");let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert!(matches!(&output.parsed.expr.as_ref().unwrap().kind,ExprKind::Binary{op,lhs,..}if op=="&"&&matches!(&lhs.kind,ExprKind::Binary{op,..}if op=="~=")));
  let mut feed=expanded_feed("a ~! b == c");let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert!(matches!(&output.parsed.expr.as_ref().unwrap().kind,ExprKind::Binary{op,lhs,..}if op=="=="&&matches!(&lhs.kind,ExprKind::Binary{op,..}if op=="~!")));
 }
 #[test]fn actual_original_authored_operator_forms_keep_first_io_and_real_quota_refunds(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  for source in ["rec . queued &= ~ bit","rec . pend_union &= ~ rec . att_pend [ i ]","between ~= via","flat_size ~! add_size","caps ||= list ( )","can_set_prefs &&= ! ! user . client . prefs"]{
   for stop in [1,3]{let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
   let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,base,&||Ok(()));let mut feed=expanded_feed(source);assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  }
 }
 #[test]fn actual_original_plain_member_chains_and_grouped_reads_keep_exact_native_extents(){use OriginalSimpleKind::{Complete,SimpleAssignmentStatement};
  for(source,wanted)in[("GLOB . dview_mob . loc = center",Some(SimpleAssignmentStatement)),("GLOB . holder . current . loc",Some(Complete)),("GLOB . holder . current . loc = value",Some(SimpleAssignmentStatement)),("img . appearance_flags |= 512",Some(SimpleAssignmentStatement)),("obj . state &= mask",Some(SimpleAssignmentStatement)),("( center ) . x - dist",Some(Complete)),("block ( ( center ) . x - dist , ( center ) . z )",Some(Complete)),("GLOB . holder ?. loc = value",Some(SimpleAssignmentStatement)),("GLOB . holder : loc = value",None),("GLOB . holder ( ) . loc = value",None),("GLOB . holder . loc = target = value",Some(OriginalSimpleKind::SimpleAssignmentStatement))]{expanded_expect(source,wanted);}
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed("GLOB . dview_mob . loc = center");let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed.expr.as_mut().unwrap();assert!(original_simple_assignment(root,&output.tokens,true));let dot=output.tokens.iter().position(|t|t.text==".").unwrap();output.tokens[dot].kind=TokenKind::Ident;assert!(!original_simple_assignment(root,&output.tokens,true));output.tokens[dot].kind=TokenKind::Punctuation;let span=output.tokens[dot].span;output.tokens[dot].span.end+=1;assert!(!original_simple_assignment(root,&output.tokens,true));output.tokens[dot].span=span;
 }
 #[test]fn actual_original_compound_rhs_post_updates_are_contextual_not_general_values(){let mut mismatches=Vec::new();use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[("p += 4 * x ++ + 6",Some(SimpleAssignmentStatement)),("p -= ( x -- + 6 )",Some(SimpleAssignmentStatement)),("p |= x ++ << 4",Some(SimpleAssignmentStatement)),("p = x ++",Some(OriginalSimpleKind::PlainAssignment)),("consume ( p += x ++ )",None),("p += other = x ++",None),("p += 4 * owner . x ++ + 6",None),("p += 4 * L [ x ] ++ + 6",None),("p += 4 * + + x + 6",None)]{let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));let actual=output.parsed().original_simple_expression.map(|p|{assert!(p.is_original());p.kind()});if actual!=wanted{mismatches.push((source,actual,wanted));}if wanted.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}
 assert!(mismatches.is_empty(),"all assigned value-role matrix mismatches: {mismatches:?}");
 }
 #[test]fn actual_original_pick_weights_and_trailing_comma_keep_actual_arg_roster(){use OriginalSimpleKind::Complete;
  for(source,wanted)in[("pick ( 100 ; 1 , 90 ; 3 , 85 ; 4 )",Some(Complete)),("pick ( 100 ; 31 , 25 ; 30 , 5 ; 9 , )",Some(Complete)),("pick ( 1 , 2 , )",Some(Complete)),("pick ( weight ; value )",Some(Complete)),("pick ( , 1 )",None),("pick ( 1 , , 2 )",None),("pick ( weight ; )",None),("pick ( weight ; value = other )",None),("pick ( key = value )",None)]{expanded_expect(source,wanted);}
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed("pick ( 100 ; 1 , 90 ; 3 , )");let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed.expr.as_mut().unwrap();let form=crate::native_special_forms::pick(root).unwrap();assert_eq!(form.choices().filter(|v|v.weight.is_some()).count(),2);let semicolon=output.tokens.iter().position(|t|t.text==";").unwrap();output.tokens[semicolon].text=",".into();assert!(!original_composed_expression(root,&output.tokens,true,32,false));
 }
 #[test]fn actual_original_member_membership_and_bare_dynamic_new_remain_closed_roles(){use OriginalSimpleKind::Complete;
  for(source,wanted)in[("frequency in GLOB . antag_frequencies",Some(Complete)),("frequency in holder . tables . allowed",Some(Complete)),("frequency in GLOB . antag_frequencies && flag",Some(Complete)),("frequency in get_entries ( )",Some(Complete)),("frequency in GLOB ?. antag_frequencies",Some(Complete)),("new _bitfield",Some(Complete)),("new path ( )",Some(Complete)),("new path . type",Some(Complete)),("new path ( value )",Some(Complete)),("new __TYPE__",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_index_chain_and_static_return_slot_keys_are_exact_root_forms(){use OriginalSimpleKind::{Complete,SimpleAssignmentStatement};
  let mut mismatches=Vec::new();
  for(source,wanted)in[("bicon_cache [ icon_md5 ] = icon_base64 = icon2base64 ( target_icon )",Some(SimpleAssignmentStatement)),("L [ i ] = name = value",Some(SimpleAssignmentStatement)),("L [ i ] = name = other = value",None),("L [ i ] += name = value",None),("consume ( L [ i ] = name = value )",None),(". [ \"x\" ] = x",Some(SimpleAssignmentStatement)),(". [ \"color\" ]",Some(Complete)),(". [ key ++ ] = value",Some(SimpleAssignmentStatement)),(". [ \"x\" ] = name = value",None)]{let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));let actual=output.parsed().original_simple_expression.map(|proof|{assert!(proof.is_original());proof.kind()});if actual!=wanted{mismatches.push((source,actual,wanted));}if wanted.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}
  assert!(mismatches.is_empty(),"all B matrix receipt mismatches: {mismatches:?}");
 }
 #[test]fn actual_original_output_and_external_expression_receipts_do_not_supply_statement_routes(){use OriginalSimpleKind::Complete;
  for(source,wanted)in[("world . log << text",Some(Complete)),("call_ext ( ( library || detect ( ) ) , \"log_write\" ) ( log , message )",Some(Complete)),("call_ext ( ( library || detect ( ) ) , \"log_write\" ) ( perf_log , . )",Some(Complete)),("world . log << ( text = value )",Some(Complete)),("call_ext ( library = value , \"log_write\" ) ( message )",None),("call_ext ( library , \"log_write\" , extra ) ( message )",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_expanded_cohort_keeps_first_io_and_zero_headroom_denial(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  for source in ["GLOB . dview_mob . loc = center","p += 4 * x ++ + 6","pick ( 100 ; 1 , )","frequency in GLOB . antag_frequencies","new _bitfield","L [ i ] = name = value",". [ \"x\" ] = x","world . log << text","call_ext ( ( library || detect ( ) ) , \"log_write\" ) ( log , message )"]{
   for stop in [1,3]{let base=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&counter,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(counter.load(Ordering::Acquire),base);}
   let base=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&counter,base,&||Ok(()));let mut feed=expanded_feed(source);assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),base);
  }
 }



 #[test]
 fn actual_original_indexed_arithmetic_updates_reuse_plain_targets_and_complete_rhs(){let mut mismatches=Vec::new();
  use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[
   ("HSV1 [ 1 ] -= HSV1 [ 1 ] >> 8",Some(SimpleAssignmentStatement)),
   ("HSV [ 1 ] -= HSV [ 1 ] >> 8",Some(SimpleAssignmentStatement)),
   ("GLOB . language_name_conflicts [ L . name ] += L",Some(SimpleAssignmentStatement)),
   ("values [ i ] *= left + right * factor",Some(SimpleAssignmentStatement)),
   ("values [ owner . key ] /= count ? total : fallback",Some(SimpleAssignmentStatement)),
   ("values [ i ] -= ( other [ i ] >> 8 )",Some(SimpleAssignmentStatement)),
   ("consume ( values [ i ] -= value )",None),
   ("( values [ i ] -= value ) + other",None),
   ("values [ i ] -= other = value",None),
   ("values [ ++ i ] -= value",None),
   ("factory ( ) [ i ] -= value",None),
   ("values ?[ i ] -= value",None),
   ("values [ i ] -= ++ value",Some(SimpleAssignmentStatement)),
   ("values [ i ] -= value ++",Some(SimpleAssignmentStatement)),
   ("values [ i ] [ j ] -= value",None),
  ]{let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));let actual=output.parsed().original_simple_expression.map(|p|{assert!(p.is_original());p.kind()});if actual!=wanted{mismatches.push((source,actual,wanted));}if wanted.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}
 assert!(mismatches.is_empty(),"all assigned value-role matrix mismatches: {mismatches:?}");
 }
 #[test]
 fn actual_original_indexed_arithmetic_update_keeps_exact_operator_and_independent_children(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed("HSV [ 1 ] -= HSV [ 1 ] >> 8");
  let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expression=output.parsed.expr.as_ref().unwrap();
  assert!(original_simple_assignment(expression,&output.tokens,true));assert!(!original_simple_assignment(expression,&output.tokens,false));
  let operator=output.tokens.iter().position(|token|token.text=="-=").unwrap();
  let saved=output.tokens[operator].clone();
  output.tokens[operator].kind=TokenKind::Punctuation;assert!(!original_simple_assignment(expression,&output.tokens,true));output.tokens[operator]=saved.clone();
  output.tokens[operator].span.end+=1;assert!(!original_simple_assignment(expression,&output.tokens,true));output.tokens[operator]=saved.clone();
  output.tokens[operator].text="+=".into();assert!(!original_simple_assignment(expression,&output.tokens,true));output.tokens[operator]=saved;
  let rhs=output.tokens.iter().rposition(|token|token.text=="HSV").unwrap();let old=output.tokens[rhs].text.clone();output.tokens[rhs].text="foreign".into();assert!(!original_simple_assignment(expression,&output.tokens,true));output.tokens[rhs].text=old;
  drop(output);assert_eq!(used.load(Ordering::Acquire),base);
  assert!(parse_expression("HSV[1] -= HSV[1] >> 8").original_simple_expression.is_none_or(|proof|!proof.is_original()));
 }

 #[test]fn actual_original_indexed_division_uses_real_punctuation_kind_and_refuses_forged_operator(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed("values [ owner . key ] /= count ? total : fallback");let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expression=output.parsed.expr.as_ref().unwrap();let at=output.tokens.iter().position(|token|token.text=="/=").unwrap();assert_eq!(output.tokens[at].kind,TokenKind::Punctuation,"actual original producer maps slash punctuation this way");assert!(original_simple_assignment(expression,&output.tokens,true));output.tokens[at].kind=TokenKind::Operator;assert!(!original_simple_assignment(expression,&output.tokens,true),"other new arithmetic operators still require their own genuine Operator kind");drop(output);assert_eq!(used.load(Ordering::Acquire),root);
 }
 #[test]
 fn actual_original_indexed_arithmetic_update_keeps_first_io_and_real_credit_refunds(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no reads after first actual IO");self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no fact requests after first actual IO");self.feed.original_value(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="HSV [ 1 ] -= HSV [ 1 ] >> 8";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  for stop in[1,5,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));let mut feed=expanded_feed(source);assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
 }

 #[test]fn actual_original_nested_arithmetic_read_keys_compose_without_new_lvalues(){use OriginalSimpleKind::{Complete,SimpleAssignmentStatement};
  for(source,wanted)in[
   ("GLOB . traits_by_type [ key ] [ tname ]",Some(Complete)),
   ("readings [ ( i - 1 ) * ( 5 + 22 ) + 1 ]",Some(Complete)),
   ("( rule && rule . takes [ 1 ] [ 1 ] == \"stack\" ) ? rule : null",Some(Complete)),
   ("cp = readings [ ( i - 1 ) * ( 5 + 22 ) + 1 ]",Some(OriginalSimpleKind::PlainAssignment)),
   ("HSV [ 1 ] %= 1536",Some(SimpleAssignmentStatement)),
   ("HSV [ 1 ] &= flags | other",Some(SimpleAssignmentStatement)),
   ("HSV [ 1 ] %= name = value",None),
   ("consume ( HSV [ 1 ] %= 1536 )",None),
   ("L [ ( key = value ) ]",Some(Complete)),("L [ ++ i < 8 ]",Some(Complete)),
   ("readings [ ( i - 1 ) * ( 5 + 22 ) + 1 ] = value",Some(SimpleAssignmentStatement)),
   ("GLOB . traits_by_type [ key ] [ tname ] = value",Some(SimpleAssignmentStatement)),
   ("GLOB . traits_by_type [ key ] [ tname ] ( )",None),
  ]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_return_slot_values_dynamic_keys_and_safe_roots_keep_separate_roles(){use OriginalSimpleKind::{Complete,SimpleAssignmentStatement};
  let mut mismatches=Vec::new();
  for(source,wanted)in[
   (". |= T . loc",Some(SimpleAssignmentStatement)),(". -= M",Some(SimpleAssignmentStatement)),
   (". == 0",Some(Complete)),("( . != 0 ) && flag",Some(Complete)),
   (". [ state_data [ \"name\" ] ] = state_data [ \"dirs\" ]",Some(SimpleAssignmentStatement)),
   (". [ key + offset ]",Some(Complete)),(". [ key + offset ] = value",Some(SimpleAssignmentStatement)),
   ("remove_from ?. images -= image",Some(SimpleAssignmentStatement)),
   ("remove_from ?. images -= target = image",None),
   ("consume ( remove_from ?. images -= image )",None),
   ("consume ( . -= M )",None),(". [ key = other ] = value",None),
   (". [ key ++ ] = value",Some(SimpleAssignmentStatement)),(". [ state_data [ \"name\" ] ] = name = value",None),
   ("( remove_from ?. images ) -= image",None),("get_owner ( ) ?. images -= image",None),
  ]{let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap_or_else(|e|panic!("{source}: {e}"));let actual=output.parsed().original_simple_expression.map(|proof|{assert!(proof.is_original());proof.kind()});if actual!=wanted{mismatches.push((source,actual,wanted));}if wanted.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}drop(output);assert_eq!(used.load(Ordering::Acquire),root);}
  assert!(mismatches.is_empty(),"all B matrix receipt mismatches: {mismatches:?}");
 }
 #[test]fn actual_original_scope_paths_and_trailing_prefab_slash_keep_actual_tokens(){use OriginalSimpleKind::Complete;
  for(source,wanted)in[
   ("sometype == sometype :: abstract_type",Some(Complete)),
   ("nameof ( / datum / radiation_pulse_information :: source_ref )",Some(Complete)),
   ("nameof ( / datum . proc / remove_filter )",Some(Complete)),
   ("after ( in_atom , remove_duration , ( nameof ( / datum . proc / remove_filter ) ) , with = list ( \"value\" ) )",Some(Complete)),
   ("istype ( I , / obj / )",Some(Complete)),
   ("nameof ( / datum . foo / remove_filter )",None),
   ("nameof ( type :: field = value )",None),
  ]{expanded_expect(source,wanted);}
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["sometype :: abstract_type","nameof ( / datum . proc / remove_filter )","istype ( I , / obj / )"]{
   let mut feed=expanded_feed(source);let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expr=output.parsed.expr.as_mut().unwrap();
   assert!(original_composed_expression(expr,&output.tokens,true,32,false));
   let at=output.tokens.iter().position(|t|matches!(t.text.as_str(),"::"|".")||t.text=="/").unwrap();
   let saved=output.tokens[at].kind;output.tokens[at].kind=TokenKind::Ident;
   assert!(!original_composed_expression(expr,&output.tokens,true,32,false));output.tokens[at].kind=saved;
   let span=output.tokens[at].span;output.tokens[at].span.end+=1;
   assert!(!original_composed_expression(expr,&output.tokens,true,32,false));output.tokens[at].span=span;
   assert!(original_composed_expression(expr,&output.tokens,true,32,false));
   drop(output);assert_eq!(used.load(Ordering::Acquire),base);
  }
 }
 #[test]fn actual_original_membership_children_preserve_pinned_lowest_binding(){use OriginalSimpleKind::Complete;
  for(source,wanted)in[
   ("read_once ( level in using_map . station_levels )",Some(Complete)),
   ("holder && ( holder in hold_sources ( target , 100196 , trait ) )",Some(Complete)),
   ("( \"name\" in D . vars ) && D . vars [ \"name\" ] == \"hidden\"",Some(Complete)),
   ("left && flag in entries",Some(Complete)),("left in entries && flag",Some(Complete)),
   ("read_once ( level in using_map . station_levels = value )",None),
   ("value in first to last",None),("value i n entries",None),
   ("value in entries tail",None),
   ("input ( ) in choices",Some(Complete)),("input ( ) as text in choices",Some(Complete)),
   ("locate ( value ) in choices",Some(Complete)),("locate ( 1 , 2 , 3 ) in choices",None),
   ("locate ( value in choices )",None),
  ]{expanded_expect(source,wanted);}
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut feed=expanded_feed("holder && ( holder in hold_sources ( target , 100196 , trait ) )");let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expr=output.parsed.expr.as_mut().unwrap();
  let at=output.tokens.iter().position(|t|t.text=="in").unwrap();let saved=output.tokens[at].kind;output.tokens[at].kind=TokenKind::Punctuation;
  assert!(!original_composed_expression(expr,&output.tokens,true,32,false));
  assert!(!original_augmented_rhs_value(expr,&output.tokens,32));output.tokens[at].kind=saved;
  assert!(original_composed_expression(expr,&output.tokens,true,32,false));
  assert!(original_augmented_rhs_value(expr,&output.tokens,32));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_prefix_comparisons_issue_only_the_distinct_control_receipt(){use OriginalSimpleKind::{Complete,PlainAssignment};
  for(source,wanted)in[
   ("++ i <= colors . len",Some(Complete)),
   ("istype ( Ab , / turf / simulated / open ) && -- above_range > 0",Some(Complete)),
   ("( -- n > 0 ) && flag",Some(Complete)),
   ("-- n > ( 0 && flag )",Some(Complete)),
   ("consume ( ++ i <= colors . len )",Some(Complete)),
   ("value = ++ i <= colors . len",Some(PlainAssignment)),
   ("L [ ++ i <= colors . len ]",Some(Complete)),
   ("++ owner . i <= limit",Some(Complete)),("++ ( i ) <= limit",None),
   ("++ L [ i ] <= limit",None),("+ + i <= limit",None),
   ("++ i <= ( value = other )",Some(Complete)),
  ]{expanded_expect(source,wanted);}
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["-- n > 0 && flag","-- n > ( 0 && flag )"]{
   let mut feed=expanded_feed(source);let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expr=output.parsed.expr.as_mut().unwrap();
   assert!(!original_prefix_condition(expr,&output.tokens,32));assert!(original_conditional_child(expr,&output.tokens,true,32));
   if source.contains("( 0") {assert!(matches!(&expr.kind,ExprKind::Binary{op,rhs,..}if op==">"&&matches!(&rhs.kind,ExprKind::Group(_))));}
   else{assert!(matches!(&expr.kind,ExprKind::Binary{op,lhs,..}if op=="&&"&&matches!(&lhs.kind,ExprKind::Binary{op,..}if op==">")));}
   let at=output.tokens.iter().position(|t|t.text=="--").unwrap();let span=output.tokens[at].span;output.tokens[at].span.end+=1;
   assert!(!original_conditional_child(expr,&output.tokens,true,32));output.tokens[at].span=span;
   assert!(original_conditional_child(expr,&output.tokens,true,32));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
  }
 }
 #[test]fn actual_original_dynamic_field_reads_require_the_live_close_colon_occurrence(){use OriginalSimpleKind::Complete;
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["value : type","consume ( value : type )","value : type == wanted"]{
   let mut feed=expanded_feed(source);for(token,close)in&mut feed.0.0.rows{if token.text==":"{*close=Some(true)}}
   let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.map(|p|p.kind()),Some(Complete),"{source}");let expr=output.parsed.expr.as_mut().unwrap();
   let at=output.tokens.iter().position(|t|t.text==":").unwrap();output.tokens[at].text="::".into();
   assert!(!original_composed_expression(expr,&output.tokens,true,32,false));output.tokens[at].text=":".into();
   assert!(original_composed_expression(expr,&output.tokens,true,32,false));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
  }
  let mut unissued=expanded_feed("value : type");for(_,close)in&mut unissued.0.0.rows{*close=None}
  assert_eq!(parse_original_expression_demanded(&mut unissued,&a).err().unwrap().kind(),std::io::ErrorKind::Unsupported);
  let mut stopped=expanded_feed("value : type");stopped.0.0.fail_close=true;
  assert_eq!(parse_original_expression_demanded(&mut stopped,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_next_expression_cohort_preserves_first_io_and_quota_refunds(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}
   fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{self.feed.original_close_colon(o)}
   fn requires_original_values(&self)->bool{true}
  }
  for source in["GLOB . traits_by_type [ key ] [ tname ]","HSV [ 1 ] %= 1536",". |= T . loc","sometype :: abstract_type","read_once ( level in using_map . station_levels )","++ i <= colors . len"]{
   for stop in[1,3,source.split_whitespace().count()+1]{let base=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&counter,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450),"{source}, pull {stop}");assert_eq!(feed.pulls,stop);assert_eq!(counter.load(Ordering::Acquire),base);}
   let base=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&counter,base,&||Ok(()));let mut feed=expanded_feed(source);assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),base);
   assert!(parse_expression(source).original_simple_expression.is_none(),"compatibility token spelling alone is not Original authority: {source}");
  }
 }

 #[test]
 fn actual_original_prefix_read_key_keeps_pre_and_post_value_roles_and_exact_tokens(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[("L [ ++ i ]",true),("L [ -- i ]",true),("L [ i ++ ]",true),("L [ i -- ]",true),
   ("L [ ++ i . field ]",true),("L [ ++ L [ i ] ]",false),("L [ ++ ( i ) ]",false),("L [ + + i ]",false),
   ("L [ ++ i ] = value",false),("consume ( L [ ++ i ] = value )",false),("value = ++ i",false),("L [ ++ null ]",false),("L [ ++ __TYPE__ ]",false)]{
   let rows:Vec<_>=source.split_whitespace().map(|text|{let kind=if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)};(kind,text,None)}).collect();
   let mut feed=ScalarMembershipFeed(Feed::new(&rows));let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   assert_eq!(output.parsed().original_simple_expression.is_some_and(|proof|proof.is_original()&&proof.kind()==OriginalSimpleKind::Complete),expected,"{source}");
   if expected{let expression=output.parsed.expr.as_mut().unwrap();let ExprKind::Index{object,index}=&expression.kind else{panic!("actual read index")};assert_eq!(original_updated_key_index(expression,object,index,&output.tokens),source!="L [ ++ i . field ]","old private bare-key route remains closed for member prefix");
    if source=="L [ ++ i . field ]"{assert!(matches!(&index.kind,ExprKind::Unary{value,..}if matches!(&value.kind,ExprKind::Member{object,selector,via_colon:false}if selector=="field"&&matches!(&object.kind,ExprKind::Ident(name)if name=="i"))));}
    let ExprKind::Unary{op,..}=&index.kind else{panic!("actual update key")};let wanted=if source.contains("[ ++"){"pre++"}else if source.contains("[ --"){"pre--"}else if source.contains("i ++"){"post++"}else{"post--"};assert_eq!(op,wanted);
    let operator=output.tokens.iter().position(|token|matches!(token.text.as_str(),"++"|"--")).unwrap();let saved=output.tokens[operator].text.clone();output.tokens[operator].text=if saved=="++"{"--"}else{"++"}.into();assert!(!original_updated_key_index(expression,object,index,&output.tokens));assert!(!original_composed_expression(expression,&output.tokens,true,32,false));output.tokens[operator].text=saved;
   }
   drop(output);assert_eq!(used.load(Ordering::Acquire),root);
  }
 }
 #[test]
 fn actual_original_positional_return_slot_is_the_exact_existing_dot_receipt(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[("consume ( . )",true),("text ( format , . )",true),("text ( format , . [ i ] )",true),
   ("consume ( . = value )",false),("consume ( . + value )",true),("consume ( .. )",false),(". + value",true)]{
   let rows:Vec<_>=source.split_whitespace().map(|text|{let kind=if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)};(kind,text,None)}).collect();let mut feed=ScalarMembershipFeed(Feed::new(&rows));let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   assert_eq!(output.parsed().original_simple_expression.is_some_and(|proof|proof.is_original()&&proof.kind()==OriginalSimpleKind::Complete),expected,"{source}");
   if source=="consume ( . )"{let expression=output.parsed.expr.as_mut().unwrap();let ExprKind::Call{args,..}=&expression.kind else{panic!("actual call")};let child=&args[0];let dot=output.tokens.iter().position(|token|token.text==".").unwrap();assert!(original_return_slot_read(child,&output.tokens[dot..dot+1]));
    output.tokens[dot].kind=TokenKind::Ident;assert!(!original_return_slot_read(child,&output.tokens[dot..dot+1]));assert!(!original_composed_expression(expression,&output.tokens,true,32,false));output.tokens[dot].kind=TokenKind::Punctuation;
    let saved=output.tokens[dot].span;output.tokens[dot].span.start+=1;assert!(!original_return_slot_read(child,&output.tokens[dot..dot+1]));output.tokens[dot].span=saved;
   }drop(output);assert_eq!(used.load(Ordering::Acquire),root);
  }
  assert!(!parse_expression("consume(.)").original_simple_expression.is_some_and(|proof|proof.is_original()));
 }
 #[test]
 fn actual_original_prefix_key_and_dot_argument_keep_first_source_io_and_refund(){
  struct Stop{feed:ScalarMembershipFeed,pulls:usize,stop:usize}
  impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let root=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(root).unwrap();
  for(source,stops)in[("L [ ++ i ]",[1,3,6]),("consume ( . )",[1,3,5])]{let rows:Vec<_>=source.split_whitespace().map(|text|{let kind=if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)};(kind,text,None)}).collect();
   for stop in stops{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:ScalarMembershipFeed(Feed::new(&rows)),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),root);}
  }
 }

 #[test]
 fn actual_original_prefix_update_is_an_exact_statement_kind_not_a_read_or_postfix_value() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("++ fromIndex", Some(OriginalSimpleKind::PrefixIncrementStatement)),
         ("-- fromIndex", Some(OriginalSimpleKind::PrefixDecrementStatement)),
         ("++ global", Some(OriginalSimpleKind::PrefixIncrementStatement)),
         ("++ null", None), ("++ __TYPE__", None),
         ("++ object . field", Some(OriginalSimpleKind::PrefixIncrementStatement)), ("++ object : field", None),
         ("++ object ?. field", None), ("++ L [ i ]", None),
         ("L [ ++ i . field ]", Some(OriginalSimpleKind::Complete)), ("lookup ( ++ i )", Some(OriginalSimpleKind::Complete)),
         ("value = ++ i", Some(OriginalSimpleKind::PlainAssignment)), ("++ i = value", None),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(true))
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if let Some(kind @ (OriginalSimpleKind::PrefixIncrementStatement|OriginalSimpleKind::PrefixDecrementStatement)) = expected {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             let expr = output.parsed.expr.as_mut().unwrap();
             assert_eq!(original_prefix_update(expr, &output.tokens), Some(kind));
             assert!(original_post_update(expr, &output.tokens).is_none());
             let old = expr.span;
             expr.span.end += 1;
             assert!(original_prefix_update(expr, &output.tokens).is_none());
             expr.span = old;
             assert!(matches!(&expr.kind, ExprKind::Unary { op, value }
                 if matches!(op.as_str(), "pre++" | "pre--") && if source=="++ object . field"{matches!(&value.kind,ExprKind::Member{object,selector,via_colon:false}if selector=="field"&&matches!(&object.kind,ExprKind::Ident(name)if name=="object"))}else{matches!(&value.kind, ExprKind::Ident(_))}));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_postfix_argument_preserves_old_value_and_only_ordinary_positional_role() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     let mut mismatches = Vec::new();
     for (source, expected) in [
         ("inserted_list . Swap ( start ++ , end -- )", Some(OriginalSimpleKind::Complete)),
         ("consume ( i ++ )", Some(OriginalSimpleKind::Complete)),
         ("i ++", Some(OriginalSimpleKind::PostIncrementStatement)),
         ("value = i ++", Some(OriginalSimpleKind::PlainAssignment)), ("consume ( ++ i )", Some(OriginalSimpleKind::Complete)),
         ("consume ( object . i ++ )", None), ("consume ( L [ i ] ++ )", None),
         ("consume ( key = i ++ )", Some(OriginalSimpleKind::Complete)), ("consume ( i ++ + j )", Some(OriginalSimpleKind::Complete)),
         ("list ( i ++ )", Some(OriginalSimpleKind::Complete)), ("new ( i ++ )", Some(OriginalSimpleKind::Complete)),
         ("pick ( i ++ )", Some(OriginalSimpleKind::Complete)), ("consume ( __TYPE__ ++ )", None),
         ("consume ( i ++ ) = value", None),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         let actual=output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind);
         if actual!=expected{mismatches.push((source,actual,expected));}
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(), "{source}"); }
         if source == "inserted_list . Swap ( start ++ , end -- )" {
             let ExprKind::Call { args, .. } = &output.parsed().expr.as_ref().unwrap().kind else { panic!("actual call"); };
             assert!(matches!(&args[0].kind, ExprKind::Unary { op, value } if op == "post++"
                 && matches!(&value.kind, ExprKind::Ident(name) if name == "start")));
             assert!(matches!(&args[1].kind, ExprKind::Unary { op, value } if op == "post--"
                 && matches!(&value.kind, ExprKind::Ident(name) if name == "end")));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(mismatches.is_empty(),"all actual postfix/value matrix receipt mismatches: {mismatches:?}");
 }
 #[test]
 fn actual_original_subtraction_index_offset_reuses_only_the_existing_addition_read_role() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("result [ i - 1 ]", Some(OriginalSimpleKind::Complete)),
         ("result [ i + 1 ]", Some(OriginalSimpleKind::Complete)),
         ("result [ i - 42 ]", Some(OriginalSimpleKind::Complete)),
         ("shifts -= result [ i - 1 ]", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("result [ 1 - i ]", Some(OriginalSimpleKind::Complete)), ("result [ i - j ]", Some(OriginalSimpleKind::Complete)),
         ("result [ i - - 1 ]", Some(OriginalSimpleKind::Complete)), ("result [ i - 1 - 2 ]", Some(OriginalSimpleKind::Complete)),
         ("result [ i ++ - 1 ]", Some(OriginalSimpleKind::Complete)), ("result [ lookup ( i ) - 1 ]", Some(OriginalSimpleKind::Complete)),
         ("result [ object . i - 1 ]", Some(OriginalSimpleKind::Complete)), ("result [ ( i ) - 1 ]", Some(OriginalSimpleKind::Complete)),
         ("result [ i - 1 ] = value", Some(OriginalSimpleKind::SimpleAssignmentStatement)), ("result [ i - 1 ] += value", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("result [ i - 1 ] ( )", None), ("result [ i - 1 ] . callback ( )", None),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut raw=Feed::new(&rows);let mut at=0;
         for(token,_)in &mut raw.rows{
             while source.as_bytes().get(at).is_some_and(u8::is_ascii_whitespace){at+=1;}
             let end=at+token.text.len();assert_eq!(&source[at..end],token.text);
             token.span=Span::new(at,end);at=end;
         }
         let mut feed = ScalarMembershipFeed(raw);
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(), "{source}"); }
         if source == "result [ i - 1 ]" {
             assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind, ExprKind::Index { index, .. }
                 if matches!(&index.kind, ExprKind::Binary { op, lhs, rhs } if op == "-"
                     && matches!(&lhs.kind, ExprKind::Ident(name) if name == "i")
                     && matches!(&rhs.kind, ExprKind::Literal(value) if value.as_str() == "1"))));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 #[test]fn actual_original_absolute_new_absent_arguments_keeps_static_target_and_exact_occurrences(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in ["new / datum","new / datum / seed_pile"]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();
   let mut feed=ScalarMembershipFeed(Feed::new(&rows));let mut output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
   assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);assert!(output.parsed().diagnostics.is_empty());assert!(output.parsed().original_constructor_facts().unwrap().as_slice().is_empty());
   let root=output.parsed().expr.as_ref().unwrap();assert!(matches!(crate::native_special_forms::constructor(root).unwrap(),Some(crate::native_special_forms::Constructor::Static{args,..})if args.is_empty()));
   assert!(original_absolute_static_new(root,&output.tokens,32));assert!(!original_absolute_static_new(root,&output.tokens,0),"actual child still consumes proof depth");
   for mutation in 0..6{let mut tokens=output.tokens.clone();match mutation{
    0=>tokens[0].kind=TokenKind::Punctuation,
    1=>tokens[0].span.end-=1,
    2=>tokens[0].span.end=tokens[1].span.end,
    3=>tokens[1].kind=TokenKind::Operator,
    4=>tokens.last_mut().unwrap().kind=TokenKind::Operator,
    _=>tokens.last_mut().unwrap().span.end+=1,
   }assert!(!original_absolute_static_new(root,&tokens,32),"{source}, mutation {mutation}");}
   let root=output.parsed.expr.as_mut().unwrap();let old=root.span;root.span.end+=1;assert!(!original_absolute_static_new(root,&output.tokens,32));root.span=old;
   drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_original_absolute_new_absent_arguments_preserves_actual_end_io_and_quota(){
  struct FailEnd{inner:ScalarMembershipFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no pull after actual IO");match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no value after actual IO");self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Ident,"new",None),(TokenKind::Punctuation,"/",None),(TokenKind::Ident,"datum",None)];
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=FailEnd{inner:ScalarMembershipFeed(Feed::new(&rows)),failed:false};
  assert_eq!(parse_original_expression_demanded(&mut feed,&admission).err().unwrap().raw_os_error(),Some(1450));assert!(feed.failed);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let denied=crate::SettingAdmission::new(&used,used.load(Ordering::Acquire),&||Ok(()));let mut feed=ScalarMembershipFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let mut feed=ScalarMembershipFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn actual_original_member_safe_index_is_exact_read_value_not_write_or_callee(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(spelling,expected)in[
   ("object . factors ?[ id ]",true),("! isnull ( object . factors ?[ id ] )",true),
   ("object . nested . factors ?[ id ]",true),("object . factors ?[ id ] [ key ]",true),("object ?. factors ?[ id ]",true),
   ("object : factors ?[ id ]",false),("object ( ) ?[ id ]",true),
   ("object . factors ?[ get_key ( ) ]",true),("object . factors ?[ id ] = value",false),
   ("object . factors ?[ id ] += value",false),("++ object . factors ?[ id ]",false),
   ("object . factors ?[ id ] ( )",false),("object . factors ?[ id ] . field",false),
  ]{
   let rows:Vec<_>=spelling.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();
   let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
   assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::Complete),"{spelling}: {:?}",output.parsed().diagnostics);
   if expected{assert!(output.parsed().diagnostics.is_empty(),"{spelling}")}
   drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }

 #[test]fn actual_original_static_member_key_index_write_keeps_only_plain_statement_authority(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[
   ("abstracts [ sometype :: abstract_type ] = value",true),
   ("object . abstracts [ sometype :: abstract_type ] = value",true),
   ("abstracts [ sometype :: abstract_type ] += value",true),
   ("abstracts [ sometype :: abstract_type ] ++",false),
   ("sometype :: abstract_type = value",false),
   ("holder ?. abstracts [ sometype :: abstract_type ] = value",false),
   ("lookup ( ) [ sometype :: abstract_type ] = value",true),
   ("abstracts [ lookup ( ) :: abstract_type ] = value",true),
   ("abstracts [ sometype ?. abstract_type ] = value",true),
   ("abstracts [ sometype : abstract_type ] = value",true),
   ("abstracts [ sometype :: abstract_type ] ( )",false),
   ("consume ( abstracts [ sometype :: abstract_type ] = value )",false),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::SimpleAssignmentStatement),"{source}: {:?}",output.parsed().diagnostics);if expected{assert!(output.parsed().diagnostics.is_empty())}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  assert!(parse_expression("abstracts[sometype::abstract_type]=value").original_simple_expression.is_none());
 }
 #[test]fn actual_original_static_member_key_write_requires_exact_scope_brackets_and_child_spans(){
  let rows=[(TokenKind::Ident,"abstracts",None),(TokenKind::Punctuation,"[",None),(TokenKind::Ident,"sometype",None),(TokenKind::Punctuation,"::",None),(TokenKind::Ident,"abstract_type",None),(TokenKind::Punctuation,"]",None),(TokenKind::Operator,"=",None),(TokenKind::Ident,"value",None)];let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let ExprKind::Binary{lhs,..}=&output.parsed().expr.as_ref().unwrap().kind else{panic!("actual assignment")};let ExprKind::Index{object,index}=&lhs.kind else{panic!("actual index")};let tokens=&output.tokens[..6];assert!(original_static_member_key_write(lhs,object,index,tokens));
  for changed in 0..10{let mut changed_tokens=tokens.to_vec();match changed{
   0=>changed_tokens[0].text="foreign".into(),1=>changed_tokens[1].kind=TokenKind::Operator,2=>changed_tokens[1].span.end+=1,
   3=>changed_tokens[2].span.start+=1,4=>changed_tokens[3].kind=TokenKind::Operator,5=>changed_tokens[3].text=":".into(),
   6=>changed_tokens[3].span.end+=1,7=>changed_tokens[4].text="foreign".into(),8=>changed_tokens[5].kind=TokenKind::Operator,_=>changed_tokens[5].span.end+=1,
  }assert!(!original_static_member_key_write(lhs,object,index,&changed_tokens),"altered occurrence {changed}");}
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_static_member_key_write_keeps_first_end_io_quota_and_recovery(){
  struct FailEnd{inner:PostUpdateFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Ident,"abstracts",None),(TokenKind::Punctuation,"[",None),(TokenKind::Ident,"sometype",None),(TokenKind::Punctuation,"::",None),(TokenKind::Ident,"abstract_type",None),(TokenKind::Punctuation,"]",None),(TokenKind::Operator,"=",None),(TokenKind::Ident,"value",None)];let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut fail=FailEnd{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut fail,&a).err().unwrap().raw_os_error(),Some(1450));assert!(fail.failed);assert_eq!(used.load(Ordering::Acquire),fixed);
  let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::SimpleAssignmentStatement);drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
 }

 #[test]fn actual_original_dynamic_new_and_grouped_assignment_values_keep_closed_consuming_roles(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[
   ("new path ( value )",Some(OriginalSimpleKind::Complete)),("new source . type",Some(OriginalSimpleKind::Complete)),
   ("new source . type ( value )",Some(OriginalSimpleKind::Complete)),("new type ( null , dir )",Some(OriginalSimpleKind::Complete)),
   ("new stack_type ( map_spawn_container ( loc ) , - amount )",Some(OriginalSimpleKind::Complete)),
   ("new source ?. type ( value )",None),("new path [ key ] ( value )",None),("new source : type ( value )",None),("new path ( key = value )",Some(OriginalSimpleKind::Complete)),
   ("( table [ key ] = value )",Some(OriginalSimpleKind::Complete)),("table [ key ] || ( table [ key ] = value )",Some(OriginalSimpleKind::Complete)),
   ("( global_sink = value )",Some(OriginalSimpleKind::Complete)),("( table [ key ] += value )",None),
   ("table [ key ] || table [ key ] = value",None),("( table [ key ] = value ) ( )",None),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}: {:?}",output.parsed().diagnostics);if expected.is_some(){assert!(output.parsed().diagnostics.is_empty());assert!(output.parsed().original_constructor_facts().unwrap().as_slice().is_empty(),"explicit runtime target never issues implicit New hint");}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  for source in["new source.type(value)","table[key]||(table[key]=value)"]{assert!(parse_expression(source).original_simple_expression.is_none(),"unissued compatibility AST cannot mint an Original receipt");}
 }
 #[test]fn actual_original_dynamic_new_and_grouped_assignment_require_actual_delimiters_and_children(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,changes)in[("new source . type ( value , other )",10usize),("( table [ key ] = value )",8usize)]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expression=output.parsed().expr.as_ref().unwrap();assert!(original_conditional_child(expression,&output.tokens,true,32));assert!(!original_conditional_child(expression,&output.tokens,true,0));
   for change in 0..changes{let mut tokens=output.tokens.clone();if source.starts_with("new") {match change{
    0=>tokens[0].kind=TokenKind::Punctuation,1=>tokens[0].span.end+=1,2=>tokens[2].kind=TokenKind::Operator,3=>tokens[3].text="foreign".into(),4=>tokens[4].kind=TokenKind::Operator,5=>tokens[4].span.end+=1,6=>tokens[6].kind=TokenKind::Operator,7=>tokens[8].kind=TokenKind::Operator,8=>tokens[8].span.end+=1,_=>tokens[5].span.start+=1,
   }}else{match change{0=>tokens[0].kind=TokenKind::Operator,1=>tokens[0].span.end+=1,2=>tokens[3].text="foreign".into(),3=>tokens[5].kind=TokenKind::Punctuation,4=>tokens[5].span.end+=1,5=>tokens[6].span.start+=1,6=>tokens[7].kind=TokenKind::Operator,_=>tokens[7].span.end+=1,}}
    assert!(!original_conditional_child(expression,&tokens,true,32),"altered actual {source} occurrence{change}");
   }drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_original_dynamic_new_grouped_values_keep_first_end_io_quota_and_same_input_recovery(){
  struct FailEnd{inner:PostUpdateFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"table",None),(TokenKind::Punctuation,"[",None),(TokenKind::Ident,"key",None),(TokenKind::Punctuation,"]",None),(TokenKind::Operator,"=",None),(TokenKind::Ident,"new",None),(TokenKind::Ident,"source",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"type",None),(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"value",None),(TokenKind::Punctuation,")",None),(TokenKind::Punctuation,")",None)];let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut fail=FailEnd{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut fail,&a).err().unwrap().raw_os_error(),Some(1450));assert!(fail.failed);assert_eq!(used.load(Ordering::Acquire),fixed);
  let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
 }

 #[test]fn actual_original_conditional_key_compound_write_is_root_plus_equals_only(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected,expected_operator)in[
   ("GLOB . churn_census . power_edits [ istype ( source_datum ) ? source_datum . type : source ] += amount",true,Some("+=")),
   ("table [ condition ? yes : no ] += amount",true,Some("+=")),
   ("GLOB . churn_census . power_edits [ condition ? yes : no ] = amount",true,Some("=")),
   ("GLOB . churn_census . power_edits [ condition ? yes : no ] -= amount",false,None),
   ("GLOB ?. churn_census . power_edits [ condition ? yes : no ] += amount",false,None),
   ("lookup ( ) . power_edits [ condition ? yes : no ] += amount",false,None),
   ("( table [ condition ? yes : no ] += amount )",false,None),
   ("table [ condition ? yes : no ] ( )",false,None),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(false))).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::SimpleAssignmentStatement),"{source}: {:?}",output.parsed().diagnostics);if expected{assert!(output.parsed().diagnostics.is_empty());assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind,ExprKind::Binary{op,lhs,..}if Some(op.as_str())==expected_operator&&matches!(&lhs.kind,ExprKind::Index{index,..}if matches!(&index.kind,ExprKind::Conditional{..}))));}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_original_conditional_key_compound_write_requires_each_actual_source_occurrence(){
  let source="GLOB . churn_census . power_edits [ condition ? yes : no ] += amount";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(false))).collect();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(original_simple_assignment(root,&output.tokens,true));
  for changed in 0..12{let mut tokens=output.tokens.clone();match changed{
   0=>tokens[1].kind=TokenKind::Operator,1=>tokens[3].span.end+=1,2=>tokens[4].text="foreign".into(),3=>tokens[5].kind=TokenKind::Operator,4=>tokens[5].span.end+=1,5=>tokens[7].kind=TokenKind::Operator,6=>tokens[9].kind=TokenKind::Operator,7=>tokens[10].span.start+=1,8=>tokens[11].kind=TokenKind::Operator,9=>tokens[12].kind=TokenKind::Punctuation,10=>tokens[12].span.end+=1,_=>tokens[13].text="foreign".into(),
  }assert!(!original_simple_assignment(root,&tokens,true),"altered real occurrence{changed}");}
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_conditional_key_compound_keeps_first_end_io_quota_and_recovery(){
  struct FailEnd{inner:PostUpdateFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}
   fn original_close_colon(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed);self.inner.original_close_colon(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="table [ condition ? yes : no ] += amount";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(false))).collect();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut fail=FailEnd{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut fail,&a).err().unwrap().raw_os_error(),Some(1450));assert!(fail.failed);assert_eq!(used.load(Ordering::Acquire),fixed);
  let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::SimpleAssignmentStatement);drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
 }

 #[test]fn actual_original_safe_member_chain_safe_index_is_only_an_exact_read_follower(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[
   ("holder ?. rx ?. link_ends ?[ key ]",true),("holder . rx ?. link_ends ?[ key ]",true),
   ("holder ?. rx . link_ends ?[ key ]",true),("holder ?. rx ?. link_ends ?[ E . type ]",true),
   ("consume ( holder ?. rx ?. link_ends ?[ key ] )",true),
   ("holder ?. rx ?. link_ends ?[ key ] = value",false),("holder ?. rx ?. link_ends ?[ key ] ++",false),
   ("holder ?. rx ?. link_ends ?[ key ] ( )",false),("holder ?. rx ?. link_ends ? [ key ]",false),
   ("holder ?: rx ?[ key ]",false),("holder ?. rx : link_ends ?[ key ]",false),
   ("holder ?. method ( ) ?[ key ]",true),("holder ?. rx ?. link_ends ?[ key ?. value ]",true),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let result=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(result.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::Complete),"{source}: {:?}",result.parsed().diagnostics);if expected{assert!(result.parsed().diagnostics.is_empty())}drop(result);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  assert!(parse_expression("holder?.rx?.link_ends?[key]").original_simple_expression.is_none());
 }
 #[test]fn actual_original_safe_member_index_requires_every_real_safe_dot_bracket_and_child_span(){
  let rows=[(TokenKind::Ident,"holder",None),(TokenKind::Punctuation,"?.",None),(TokenKind::Ident,"rx",None),(TokenKind::Punctuation,"?.",None),(TokenKind::Ident,"link_ends",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"key",None),(TokenKind::Punctuation,"]",None)];let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(original_call_or_safe_read_index(root,&output.tokens,32));assert!(!original_call_or_safe_read_index(root,&output.tokens,0));
  for changed in 0..10{let mut tokens=output.tokens.clone();match changed{
   0=>tokens[1].kind=TokenKind::Operator,1=>tokens[1].span.end+=1,2=>tokens[1].text=".".into(),
   3=>tokens[3].kind=TokenKind::Operator,4=>tokens[3].span.start+=1,5=>tokens[4].text="foreign".into(),
   6=>tokens[5].kind=TokenKind::Operator,7=>tokens[5].span.end+=1,8=>tokens[6].span.start+=1,_=>tokens[7].span.end+=1,
  }assert!(!original_call_or_safe_read_index(root,&tokens,32),"altered actual source occurrence {changed}");}
  assert!(original_call_or_safe_read_index(root,&output.tokens,32));drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_safe_member_index_keeps_first_end_io_quota_and_same_input_recovery(){
  struct FailEnd{inner:PostUpdateFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Ident,"holder",None),(TokenKind::Punctuation,"?.",None),(TokenKind::Ident,"rx",None),(TokenKind::Punctuation,"?.",None),(TokenKind::Ident,"link_ends",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"key",None),(TokenKind::Punctuation,"]",None)];let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut fail=FailEnd{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut fail,&a).err().unwrap().raw_os_error(),Some(1450));assert!(fail.failed);assert_eq!(used.load(Ordering::Acquire),fixed);
  let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
 }

 #[test]fn actual_original_safe_index_member_key_keeps_exact_read_and_safe_member_roles(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[
   ("GLOB . rx_tables ?[ E . type ]",true),("tables ?[ E . type ]",true),
   ("GLOB . rx_tables ?[ E . owner . type ]",true),("E . rx ?. listeners",true),
   ("GLOB . rx_tables ?[ E . type ] = value",false),("GLOB . rx_tables ?[ E . type ] ++",false),
   ("GLOB . rx_tables ?[ E . type ] ( )",false),("GLOB . rx_tables ?[ E ?. type ]",true),
   ("GLOB . rx_tables ?[ E : type ]",true),("GLOB . rx_tables ?[ E . type ( ) ]",true),
   ("GLOB . rx_tables ? [ E . type ]",false),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,(text==":").then_some(true))).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
   assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::Complete),"{source}: {:?}",output.parsed().diagnostics);if expected{assert!(output.parsed().diagnostics.is_empty())}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_original_safe_index_member_key_requires_actual_key_dot_and_bracket_occurrences(){
  let rows=[(TokenKind::Ident,"GLOB",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"rx_tables",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"E",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"type",None),(TokenKind::Punctuation,"]",None)];
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(original_call_or_safe_read_index(root,&output.tokens,32));assert!(!original_call_or_safe_read_index(root,&output.tokens,0));
  for mutation in 0..9{let mut tokens=output.tokens.clone();match mutation{0=>tokens[5].kind=TokenKind::Operator,1=>tokens[5].span.end+=1,2=>tokens[6].text="other".into(),3=>tokens[4].span.start+=1,4=>tokens[3].kind=TokenKind::Operator,5=>tokens[3].span.end-=1,6=>tokens[3].span.start=tokens[2].span.end-1,7=>tokens[7].kind=TokenKind::Operator,_=>tokens[7].span.end+=1}assert!(!original_call_or_safe_read_index(root,&tokens,32),"mutation {mutation}");}
  drop(output);
  let safe_rows=[(TokenKind::Ident,"GLOB",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"rx_tables",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"E",None),(TokenKind::Punctuation,"?.",None),(TokenKind::Ident,"type",None),(TokenKind::Punctuation,"]",None)];
  let mut feed=PostUpdateFeed(Feed::new(&safe_rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(original_call_or_safe_read_index(root,&output.tokens,32));
  for mutation in 0..2 {let mut tokens=output.tokens.clone();if mutation==0{tokens[5].kind=TokenKind::Operator}else{tokens[5].span.end-=1}assert!(!original_call_or_safe_read_index(root,&tokens,32),"safe-dot occurrence mutation {mutation}");}
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_safe_index_member_key_keeps_actual_end_io_and_real_quota_refund(){
  struct FailEnd{inner:PostUpdateFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no token after actual IO");match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no value after actual IO");self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Ident,"GLOB",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"rx_tables",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"E",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"type",None),(TokenKind::Punctuation,"]",None)];
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=FailEnd{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&admission).err().unwrap().raw_os_error(),Some(1450));assert!(feed.failed);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let denied=crate::SettingAdmission::new(&used,used.load(Ordering::Acquire),&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_member_safe_index_requires_owned_name_dot_safe_bracket_and_child_extents(){
  let rows=[(TokenKind::Ident,"object",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"factors",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"id",None),(TokenKind::Punctuation,"]",None)];
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(original_call_or_safe_read_index(root,&output.tokens,32));assert!(!original_call_or_safe_read_index(root,&output.tokens,0));
  for mutation in 0..9{let mut tokens=output.tokens.clone();match mutation{
   0=>tokens[1].kind=TokenKind::Operator,1=>tokens[1].span.end+=1,2=>tokens[2].span.start+=1,
   3=>tokens[3].kind=TokenKind::Operator,4=>tokens[3].span.end-=1,5=>tokens[3].span.start=tokens[2].span.end-1,
   6=>tokens[4].span.end-=1,7=>tokens[5].kind=TokenKind::Operator,_=>tokens[5].span.end+=1,
  }assert!(!original_call_or_safe_read_index(root,&tokens,32),"mutation {mutation}");}
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_member_safe_index_keeps_actual_end_io_and_real_quota_refund(){
  struct FailEnd{inner:PostUpdateFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no token after actual IO");match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no value after actual IO");self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Ident,"object",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"factors",None),(TokenKind::Punctuation,"?[",None),(TokenKind::Ident,"id",None),(TokenKind::Punctuation,"]",None)];
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=FailEnd{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&admission).err().unwrap().raw_os_error(),Some(1450));assert!(feed.failed);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let denied=crate::SettingAdmission::new(&used,used.load(Ordering::Acquire),&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&admission).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_recursive_index_write_uses_complete_keys_without_new_update_or_receiver_roles(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[
   ("xgm_id_to_type [ initial ( gas_type . id ) ] = gas_path",true),
   ("file_data [ ranks ] [ key ] = list ( )",true),
   ("file_data [ ranks ] [ key ] [ rights ] = R . include_rights",true),
   ("table [ choose ( key ) ] = value",true),
   ("table [ ( target = other ) ] = value",true),
   ("table [ choose ( key ) ] += value",true),
   ("table ?[ choose ( key ) ] = value",false),
   ("holder ?. table [ choose ( key ) ] = value",false),
   ("factory ( ) [ choose ( key ) ] = value",true),
   ("table [ total += delta ] = value",false),
   ("table [ target = other ] = value",false),
   ("consume ( table [ choose ( key ) ] = value )",false),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected.then_some(OriginalSimpleKind::SimpleAssignmentStatement),"{source}: {:?}",output.parsed().diagnostics);
   if expected{assert!(output.parsed().diagnostics.is_empty())}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]
 fn actual_original_recursive_index_write_keeps_each_bracket_child_and_receiver_occurrence(){
  let source="file_data [ ranks ] [ initial ( gas_type . id ) ] = value";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let ExprKind::Binary{lhs,..}=&output.parsed().expr.as_ref().unwrap().kind else{panic!("actual assignment")};let end=output.tokens.iter().position(|token|token.text=="=").unwrap();let tokens=&output.tokens[..end];
  assert!(original_complete_index_write_target(lhs,tokens,32));assert!(!original_complete_index_write_target(lhs,tokens,0));assert!(!original_assignment_target(lhs,tokens,true,false));
  for mutation in 0..11{let mut changed=tokens.to_vec();match mutation{
   0=>changed[0].text="foreign".into(),1=>changed[1].kind=TokenKind::Operator,2=>changed[1].span.end+=1,
   3=>changed[2].span.start+=1,4=>changed[3].kind=TokenKind::Operator,5=>changed[4].kind=TokenKind::Operator,
   6=>changed[4].span.end+=1,7=>changed[4].span.start=changed[3].span.end-1,
   8=>changed[5].text="other".into(),9=>changed.last_mut().unwrap().kind=TokenKind::Operator,_=>changed.last_mut().unwrap().span.end+=1,
  }assert!(!original_complete_index_write_target(lhs,&changed,32),"exact index target occurrence {mutation}");}
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_recursive_index_group_assignment_never_restarts_remaining_proof_depth(){
  let source="table [ ( table [ ( table [ key ] = middle ) ] = other ) ] = value";
  let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();
  let ExprKind::Binary{lhs,..}=&output.parsed().expr.as_ref().unwrap().kind else{panic!("actual outerassignment")};let end=output.tokens.partition_point(|token|token.span.end<=lhs.span.end);let target=&output.tokens[..end];
  assert!(original_complete_index_write_target(lhs,target,32));
  assert!(!original_complete_index_write_target(lhs,target,4),"a Group '=' key cannot reset targetdepth to32");
  assert!(!original_assignment_target_with_depth(lhs,target,true,true,4));
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_recursive_index_write_keeps_first_mid_end_io_quota_and_recovery(){
  struct Stop{inner:PostUpdateFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.inner.next_token()}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}fn requires_original_values(&self)->bool{true}
  }
  let source="table [ initial ( gas_type . id ) ] = value";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  for stop in[1,rows.len()/2,rows.len()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{inner:PostUpdateFeed(Feed::new(&rows)),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert!(feed.failed);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let tight=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&tight).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::SimpleAssignmentStatement);drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]
 fn actual_original_constructor_named_arguments_keep_exact_key_value_and_constructor_roles(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let source="new / datum / admins ( ranks_from_rank_name ( admin_rank ) , ckey ( admin_key ) , force_active = 0 , protected = 1 )";
  let rows:Vec<_>=source.split_whitespace().map(|text|(if original_decimal(text){TokenKind::Number}else if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();
  let mut feed=ScalarMembershipFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();
  let root=output.parsed().expr.as_ref().unwrap();assert!(output.parsed().diagnostics.is_empty());assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);
  assert!(original_absolute_static_new(root,&output.tokens,32));assert!(!original_absolute_static_new(root,&output.tokens,0));
  let Some(crate::native_special_forms::Constructor::Static{args,..})=crate::native_special_forms::constructor(root).unwrap()else{panic!("same actual static constructor")};assert_eq!(args.len(),4);assert!(matches!(&args[2].kind,ExprKind::Binary{op,lhs,..}if op=="="&&matches!(&lhs.kind,ExprKind::Ident(name)if name=="force_active")));assert!(output.parsed().original_constructor_facts().unwrap().as_slice().is_empty());
  let key=output.tokens.iter().position(|t|t.text=="force_active").unwrap();let equals=key+1;let open=output.tokens.iter().position(|t|t.text=="(").unwrap();let close=output.tokens.len()-1;
  for mutation in 0..9{let mut tokens=output.tokens.clone();match mutation{
   0=>tokens[key].kind=TokenKind::String,1=>tokens[key].span.end+=1,2=>tokens[equals].kind=TokenKind::Punctuation,3=>tokens[equals].span.end+=1,4=>tokens[equals].text="+=".into(),5=>tokens[open].span.end+=1,6=>tokens[close].span.start-=1,7=>tokens[0].span.end+=1,_=>tokens[equals].span.start=tokens[key].span.start,
  }assert!(!original_absolute_static_new(root,&tokens,32),"exact named constructor occurrence {mutation}");}
  drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_constructor_named_arguments_keep_member_and_compound_keys_closed(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["new / datum ( object . key = value )","new / datum ( key += value )","new / datum ( key = value = other )","consume ( key = value )"]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let mut feed=ScalarMembershipFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(!original_absolute_static_new(root,&output.tokens,32),"{source}");
  }
 }
 #[test]
 fn actual_original_constructor_named_arguments_keep_first_end_io_quota_and_recovery(){
  struct FailEnd{inner:ScalarMembershipFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);match self.inner.next_token()?{Some(t)=>Ok(Some(t)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}fn requires_original_values(&self)->bool{true}
  }
  let rows=[(TokenKind::Ident,"new",None),(TokenKind::Punctuation,"/",None),(TokenKind::Ident,"datum",None),(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"key",None),(TokenKind::Operator,"=",None),(TokenKind::Ident,"value",None),(TokenKind::Punctuation,")",None)];
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut failed=FailEnd{inner:ScalarMembershipFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut failed,&a).err().unwrap().raw_os_error(),Some(1450));assert!(failed.failed);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let tight=crate::SettingAdmission::new(&used,used.load(Ordering::Acquire),&||Ok(()));let mut denied=ScalarMembershipFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut denied,&tight).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);
  let mut recovered=ScalarMembershipFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut recovered,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_absolute_new_keeps_static_path_and_positional_children_without_implicit_hints() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("new / list ( )", true),
         ("new / exception ( value , other , 0 )", true),
         ("new / datum / concrete ( value )", true),
         ("new / datum", true),
         ("new . datum ( )", false),
         ("new / datum { field = value } ( )", false),
         ("new / datum ( key = value )", true),
         ("new / datum ( value , )", false),
         ("new / datum ( , value )", false),
         ("new / datum [ key ] ( )", false),
         ("new / datum ( ) . field", false),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.then_some(OriginalSimpleKind::Complete), "{source}");
         if expected {
             assert!(output.parsed().diagnostics.is_empty(), "{source}");
             assert!(output.parsed().original_constructor_facts().unwrap().as_slice().is_empty());
             let expr = output.parsed.expr.as_mut().unwrap();
             assert!(original_absolute_static_new(expr, &output.tokens, 32));
             let Some(crate::native_special_forms::Constructor::Static { path, args }) =
                 crate::native_special_forms::constructor(expr).unwrap() else { panic!("same existing static meaning"); };
             assert!(path.starts_with('/'));
             assert_eq!(args.len(), if source.contains("exception") { 3 } else if source.contains("concrete") || source.contains("key = value") { 1 } else { 0 });
             let old = expr.span;
             expr.span.end += 1;
             assert!(!original_absolute_static_new(expr, &output.tokens, 32));
             expr.span = old;
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 struct ComposedFloatFeed(ScalarMembershipFeed);
 impl NativeExpressionTokenDemand for ComposedFloatFeed {
     fn next_token(&mut self) -> std::io::Result<Option<Token>> { self.0.next_token() }
     fn original_value(&self, at: NativeExpressionTokenOccurrence) -> std::io::Result<Option<crate::OriginalTokenValue<&str>>> {
         let (token, _) = self.0.0.rows.get(at.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;
         if token.span != at.span() { return Err(std::io::ErrorKind::InvalidInput.into()); }
         if token.kind == TokenKind::Number && token.text == "0.2" {
             // Fixture's issued f32 bits, never decoded from its raw spelling.
             return Ok(Some(crate::OriginalTokenValue::Float(f32::from_bits(0x3e4c_cccd))));
         }
         self.0.original_value(at)
     }
     fn original_close_colon(&self, at: NativeExpressionTokenOccurrence) -> std::io::Result<Option<bool>> { self.0.original_close_colon(at) }
     fn requires_original_values(&self) -> bool { true }
 }
 #[test]
 fn actual_original_member_assignment_and_name_offset_reads_keep_statement_and_read_roles() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("img . layer = MOB_LAYER - 0.2", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("img . layer = 4 - 0.2", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("img . layer = lookup ( value )", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("img . layer = flag ? left : right", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("result [ gap + i ]", Some(OriginalSimpleKind::Complete)),
         ("lookup ( result [ gap + i ] )", Some(OriginalSimpleKind::Complete)),
         ("img . layer = result [ gap + i ]", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("img : layer = value", None), ("img ?. layer = value", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("img . nested . layer = lookup ( value )", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("value = img . layer = other", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("lookup ( img . layer = value )", None),
         ("result [ gap + i ] = value", Some(OriginalSimpleKind::SimpleAssignmentStatement)),
         ("result [ gap + i ] ( )", None), ("result [ gap + i ] . callback ( )", None),
         ("result [ gap - i ]", Some(OriginalSimpleKind::Complete)), ("result [ gap + i ++ ]", Some(OriginalSimpleKind::Complete)),
         ("result [ gap + lookup ( i ) ]", Some(OriginalSimpleKind::Complete)), ("result [ gap + object . i ]", Some(OriginalSimpleKind::Complete)),
         ("result [ gap + i + next ]", Some(OriginalSimpleKind::Complete)),
     ] {
         let rows: Vec<_> = source.split_whitespace().map(|text| {
             let kind = if text == "0.2" || original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind, text, (text == ":").then_some(false))
         }).collect();
         let mut feed = ComposedFloatFeed(ScalarMembershipFeed(Feed::new(&rows)));
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind), expected, "{source}");
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(), "{source}"); }
         if source == "img . layer = MOB_LAYER - 0.2" {
             assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind, ExprKind::Binary { rhs, .. }
                 if matches!(&rhs.kind, ExprKind::Binary { rhs, .. }
                     if matches!(&rhs.kind, ExprKind::Literal(value)
                         if matches!(value.original_value(), Some(crate::OriginalTokenValue::Float(value)) if value.to_bits() == 0x3e4c_cccd)))));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
     let source = "img.layer = MOB_LAYER - 0.2";
     let tokens = lex(source).tokens.into_iter().map(|token| SpanToken { kind: token.kind, span: token.span }).collect::<Vec<_>>();
     let unissued = parse_expression_original_token_view(source, &tokens, 0, &admission, None);
     assert!(unissued.original_simple_expression.is_none(), "raw floating spelling cannot mint its typed leaf");
 }
 #[test]
 fn actual_original_unweighted_pick_arms_keep_existing_resource_bounds_and_order() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     let mut cases = Vec::new();
     for count in [1,2,10,16,17,19,32,64] {
         let arms = (1..=count).map(|value|value.to_string()).collect::<Vec<_>>().join(" , ");
         cases.push((format!("pick ( {arms} )"), Some(OriginalSimpleKind::Complete)));
     }
     cases.extend([
         ("pick ( 1 , 2 )".into(),Some(OriginalSimpleKind::Complete)),
         ("consume ( pick ( 1 , 2 ) )".into(),Some(OriginalSimpleKind::Complete)),
         ("result = pick ( 1 , 2 )".into(),Some(OriginalSimpleKind::PlainAssignment)),
         ("pick ( 1 , 2 , )".into(),Some(OriginalSimpleKind::Complete)),
         ("pick ( , 1 )".into(),None), ("pick ( 1 , , 2 )".into(),None),
         ("pick ( 1 ; 2 , 3 )".into(),Some(OriginalSimpleKind::Complete)),
         ("pick ( key = 1 , key = 2 )".into(),None),
         ("pick ( i ++ , 2 )".into(),Some(OriginalSimpleKind::Complete)),
         ("pick ( 1 , 2 ) = value".into(),None),
         ("pick ( 1 , 2 ) ( )".into(),None),
         ("pick ( 1 , 2 ) . field".into(),Some(OriginalSimpleKind::Complete)),
     ]);
     let mut mismatches=Vec::new();
     for (source, expected) in cases {
         let rows:Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind,text,None)
         }).collect();
         let mut feed=ScalarMembershipFeed(Feed::new(&rows));
         let mut output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
         let actual=output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind);
         if actual!=expected{mismatches.push((source.clone(),actual,expected));}
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(),"{source}"); }
         if source == "pick ( 1 , 2 )" {
             let expression=output.parsed.expr.as_mut().unwrap();
             let form=crate::native_special_forms::pick(expression).unwrap();
             assert_eq!(form.choices().count(),2);
             assert!(form.choices().all(|choice|choice.weight.is_none()));
             let old=expression.span;
             expression.span.end+=1;
             assert!(!original_composed_expression(expression,&output.tokens,true,32,false));
             expression.span=old;
             let old=output.tokens[3].text.clone();
             output.tokens[3].text=";".into();
             assert!(!original_composed_expression(expression,&output.tokens,true,32,false));
             output.tokens[3].text=old;
             assert!(original_composed_expression(expression,&output.tokens,true,32,false));

         }
         if source == "pick ( 1 , 2 ) . field" {
             let expression=output.parsed.expr.as_ref().unwrap();
             let ExprKind::Member{object,selector,via_colon:false}=&expression.kind else{panic!("actual Pick call followed by ordinary field")};
             assert_eq!(selector,"field");
             let form=crate::native_special_forms::pick(object).expect("SAME actual pick receiver");
             assert_eq!(form.choices().count(),2);assert!(form.choices().all(|choice|choice.weight.is_none()));
             let end=output.tokens.partition_point(|token|token.span.end<=object.span.end);
             assert_eq!(end,6,"actual complete pick receiver consumes both values and delimiters");
             assert!(original_composed_expression(object,&output.tokens[..end],false,32,false));
             let original_open=output.tokens[1].span;output.tokens[1].span.end+=1;
             assert!(!original_composed_expression(object,&output.tokens[..end],false,32,false),"borrowed call must independently reject malformed actual delimiter extent");
             assert!(!original_composed_expression(expression,&output.tokens,true,32,false),"outer field cannot restore a missing child receipt");
             output.tokens[1].span=original_open;
             assert!(original_composed_expression(object,&output.tokens[..end],false,32,false));
             assert!(original_composed_expression(expression,&output.tokens,true,32,false));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
     assert!(mismatches.is_empty(),"all actual Pick matrix mismatches: {mismatches:?}");
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
         (&field[..], true), (&negated[..], true), (&deeper[..], true), (&safe[..], true),
         (&index[..], true), (&rhs_field[..], true), (&boolean_rhs[..], true), (&range[..], false),
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
         (&boolean_lhs[..], true), (&boolean_rhs[..], true), (&range[..], false),
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
         (&ungrouped[..], Some("in")), (&inner_boolean[..], Some("grouped_in")), (&range[..], None), (&split_in[..], None),
     ] {
         let mut feed = Feed::new(tokens);
         let output = parse_original_expression_demanded(&mut feed, &admission).unwrap();
         let parsed = output.parsed();
         assert_eq!(parsed.original_simple_expression.map(OriginalSimpleExpression::kind),
             expected.map(|_| OriginalSimpleKind::Complete), "{tokens:?}");
         if let Some(expected) = expected {
             assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
             if expected=="grouped_in"{
                 assert!(matches!(&parsed.expr.as_ref().unwrap().kind,ExprKind::Group(inner)
                     if matches!(&inner.kind,ExprKind::Binary{op,..}if op=="in")));
                 drop(output);
                 assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
                 continue;
             }
             let Some(ExprKind::Binary { op, lhs, rhs }) = parsed.expr.as_ref().map(|expr| &expr.kind)
                 else { panic!("missing outer boolean"); };
             assert_eq!(op, expected);
             let membership = |expr: &Expr| matches!(&expr.kind, ExprKind::Unary { op, value }
                 if op == "!" && matches!(&value.kind, ExprKind::Group(inner)
                     if matches!(&inner.kind, ExprKind::Binary { op, .. } if op == "in")));
             if expected=="in"{
                 assert!(matches!(&lhs.kind,ExprKind::Ident(name)if name=="e"));
                 assert!(matches!(&rhs.kind,ExprKind::Binary{op,..}if op=="&&"));
             }else{assert!(membership(lhs));}
             if expected == "&&" {
                 assert!(membership(rhs));
             } else if expected=="||" {
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
 fn actual_original_power_expression_preserves_pinned_left_binding_and_unary_grouping() {
     let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission = crate::SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
     for (source, expected) in [
         ("2 ** 15", Some(OriginalSimpleKind::Complete)),
         ("a ** b ** c", Some(OriginalSimpleKind::Complete)),
         ("a ** ( b ** c )", Some(OriginalSimpleKind::Complete)),
         ("( a ** b ) ** c", Some(OriginalSimpleKind::Complete)),
         ("- a ** b", Some(OriginalSimpleKind::Complete)),
         ("- ( a ** b )", Some(OriginalSimpleKind::Complete)),
         ("a ** - b", Some(OriginalSimpleKind::Complete)),
         ("! a ** b", Some(OriginalSimpleKind::Complete)),
         ("a + b ** c * d", Some(OriginalSimpleKind::Complete)),
         ("( a + b ) ** c", Some(OriginalSimpleKind::Complete)),
         ("lookup ( a ** b )", Some(OriginalSimpleKind::Complete)),
         ("result = a ** b", Some(OriginalSimpleKind::PlainAssignment)),
         ("+ a ** b", None),
         ("a * * b", None),
         ("a **", None),
         ("a ** b **", None),
         ("a ** ( b ** c", None),
         ("a ** b = value", None),
     ] {
         let rows:Vec<_> = source.split_whitespace().map(|text| {
             let kind = if original_decimal(text) { TokenKind::Number }
                 else if original_ascii_identifier(text) { TokenKind::Ident }
                 else { crate::original_scalar_transport::original_punctuation_native_kind(text) };
             (kind,text,None)
         }).collect();
         let mut feed = ScalarMembershipFeed(Feed::new(&rows));
         let mut output = parse_original_expression_demanded(&mut feed,&admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}");
         if expected.is_some() { assert!(output.parsed().diagnostics.is_empty(),"{source}"); }
         if source == "a ** b ** c" {
             let expr = output.parsed.expr.as_mut().unwrap();
             assert!(original_conditional_child(expr,&output.tokens,true,32));
             let ExprKind::Binary { op, lhs, rhs } = &expr.kind else { panic!("actual power root"); };
             assert_eq!(op,"**");
             let ExprKind::Binary { op:inner, lhs:a, rhs:b } = &lhs.kind else { panic!("pinned/native equal-strength power folds LEFT"); };
             assert_eq!(inner,"**");
             assert!(matches!(&a.kind,ExprKind::Ident(name)if name=="a"));
             assert!(matches!(&b.kind,ExprKind::Ident(name)if name=="b"));
             assert!(matches!(&rhs.kind,ExprKind::Ident(name)if name=="c"));
             let original = expr.kind.clone();
             // Same bytes cannot authenticate an ungrouped right-associated
             // compatibility tree, even with individually valid child names.
             let forged_rhs = Expr { span:Span::new(b.span.start,rhs.span.end),
                 kind:ExprKind::Binary { op:"**".into(),lhs:b.clone(),rhs:rhs.clone() } };
             expr.kind = ExprKind::Binary { op:"**".into(),lhs:a.clone(),rhs:Box::new(forged_rhs) };
             assert!(!original_conditional_child(expr,&output.tokens,true,32));
             expr.kind = original;
             let root=expr.span;expr.span.end+=1;
             assert!(!original_conditional_child(expr,&output.tokens,true,32));expr.span=root;
             let at=output.tokens.iter().position(|token|token.text=="**").unwrap();
             let saved=output.tokens[at].text.clone();output.tokens[at].text="*".into();
             assert!(!original_conditional_child(expr,&output.tokens,true,32));output.tokens[at].text=saved;
             assert!(original_conditional_child(expr,&output.tokens,true,32));
         }
         if source == "- a ** b" {
             assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind,
                 ExprKind::Binary{op,lhs,..}if op=="**"&&matches!(&lhs.kind,ExprKind::Unary{op,..}if op=="-")));
         }
         if source == "- ( a ** b )" {
             assert!(matches!(&output.parsed().expr.as_ref().unwrap().kind,
                 ExprKind::Unary{op,value}if op=="-"&&matches!(&value.kind,ExprKind::Group(child)
                     if matches!(&child.kind,ExprKind::Binary{op,..}if op=="**"))));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
     }
 }
 #[test]
 fn actual_original_typed_input_preserves_primary_union_and_exact_argument_roles() {
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
     for (source, expected) in [
         ("input ( user , message , title , default ) as text | null", Some(OriginalSimpleKind::Complete)),
         ("input ( user , message , title , default ) as message | null", Some(OriginalSimpleKind::Complete)),
         ("input ( ) as null | text", Some(OriginalSimpleKind::Complete)),
         ("input ( ) as text | text | null", Some(OriginalSimpleKind::Complete)),
         ("input ( ) as num | null", Some(OriginalSimpleKind::Complete)),
         ("input ( ) as mob | obj | turf | area | icon | sound | file | key | password | color | anything | command_text", Some(OriginalSimpleKind::Complete)),
         ("input ( prompt ( ) ) as text", Some(OriginalSimpleKind::Complete)),
         ("input ( user , message , ) as text", Some(OriginalSimpleKind::Complete)),
         ("input ( user , message )", Some(OriginalSimpleKind::Complete)),
         ("( input ( ) as text | null )", Some(OriginalSimpleKind::Complete)),
         ("consume ( input ( ) as text | null )", Some(OriginalSimpleKind::Complete)),
         ("result = input ( user ) as text | null", Some(OriginalSimpleKind::PlainAssignment)),
         ("other ( user ) as text", None),
         ("value as text", None),
         ("input ( title = value ) as text", None),
         ("input ( , value ) as text", None),
         ("input ( ) as text |", None),
         ("input ( ) as ( text | null )", None),
         ("input ( ) as ( )", None),
         ("input ( ) as unknown_type", None),
         ("input ( ) as movable", None),
         ("input ( ) as atom", None),
         ("input ( ) as list", None),
         ("input ( ) in choices", Some(OriginalSimpleKind::Complete)),
         ("input ( ) as text in choices", Some(OriginalSimpleKind::Complete)),
         ("input ( ) as text = value", None),
     ] {
         let rows:Vec<_>=source.split_whitespace().map(|text| {
             let kind=if original_decimal(text){TokenKind::Number}
                 else if original_ascii_identifier(text){TokenKind::Ident}
                 else{crate::original_scalar_transport::original_punctuation_native_kind(text)};
             (kind,text,None)
         }).collect();
         let mut feed=ScalarMembershipFeed(Feed::new(&rows));
         let mut output=parse_original_expression_demanded(&mut feed,&admission).unwrap();
         assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),expected,"{source}");
         if expected.is_some(){assert!(output.parsed().diagnostics.is_empty(),"{source}");}
         if source=="input ( user , message , title , default ) as text | null" {
             let expression=output.parsed.expr.as_mut().unwrap();
             let form=crate::native_special_forms::input(expression).unwrap().unwrap();
             assert_eq!(form.types,["text","null"]);assert_eq!(form.args.len(),4);assert!(form.in_list.is_none());
             assert!(original_conditional_child(expression,&output.tokens,true,32));
             let old=if let ExprKind::TypeFilter{types,..}=&mut expression.kind{std::mem::replace(&mut types[0],"num".into())}else{panic!("actual primary TypeFilter")};
             assert!(!original_conditional_child(expression,&output.tokens,true,32),"accepted type DATA cannot replace the actual source union");
             if let ExprKind::TypeFilter{types,..}=&mut expression.kind{types[0]=old;}
             let as_at=output.tokens.iter().position(|token|token.text=="as").unwrap();
             let saved=output.tokens[as_at].text.clone();output.tokens[as_at].text="in".into();
             assert!(!original_conditional_child(expression,&output.tokens,true,32));output.tokens[as_at].text=saved;
             let bar_at=output.tokens.iter().position(|token|token.text=="|").unwrap();
             let saved=output.tokens[bar_at].text.clone();output.tokens[bar_at].text="||".into();
             assert!(!original_conditional_child(expression,&output.tokens,true,32));output.tokens[bar_at].text=saved;
             let span=expression.span;expression.span.end+=1;
             assert!(!original_conditional_child(expression,&output.tokens,true,32));expression.span=span;
             assert!(original_conditional_child(expression,&output.tokens,true,32));
         }
         if source=="input ( ) as unknown_type" {
             assert!(output.parsed().original_input_notices().unwrap().as_slice().iter().any(|notice|notice.kind()==crate::OriginalInputNoticeKind::BadInputType));
         }
         drop(output);
         assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
     }
 }

 #[test]
 fn actual_original_normal_primary_in_keeps_exact_primary_container_and_value_contexts(){
  use OriginalSimpleKind::{Complete,PlainAssignment};
  for(source,wanted)in[
   ("input ( user , message , title , default ) as null | anything in items",Some(Complete)),
   ("input ( ) in choices",Some(Complete)),
   ("consume ( input ( user ) as text | null in items )",Some(Complete)),
   ("result = input ( user ) as text in items",Some(PlainAssignment)),
   ("locate ( type ) in T",Some(Complete)),
   ("locate ( type ) in A . contents",Some(Complete)),
   ("locate ( integrated_ai ( ) ) in ai_card",Some(Complete)),
   ("locate ( ) in world",Some(Complete)),
   ("! locate ( type ) in choices || other",Some(Complete)),
   ("! input ( user ) as null | anything in choices",Some(Complete)),
   ("- locate ( type ) in choices",Some(Complete)),
   ("! ! ( locate ( type ) in slot_contents ( ) )",Some(Complete)),
   ("anchored || ( locate ( type ) in contents_of ( loc ) )",Some(Complete)),
   ("( locate ( type ) ) in items",Some(Complete)),
   ("( input ( ) ) in items",Some(Complete)),
   ("input ( ) in items as text",None),
   ("input ( ) as text in items as num",None),
   ("input ( ) as unknown_type in items",None),
   ("input ( title = value ) in items",None),
   ("input ( ) in ( ++ i < limit )",Some(Complete)),
   ("input ( ) in ( target = items )",Some(Complete)),
   ("locate ( value in choices )",None),
   ("locate ( 1 , 2 , 3 ) in items",None),
   ("locate ( type , source )",None),
   ("locate ( ) in items ; hidden ( )",None),
   ("locate ( ) in items tail",None),
  ]{expanded_expect(source,wanted);}
 }
 #[test]
 fn actual_original_primary_in_prefix_keeps_whole_container_and_generic_binary_denial(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut feed=expanded_feed("! locate ( type ) in choices || other");let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();
  let expr=output.parsed.expr.as_mut().unwrap();assert!(original_conditional_child(expr,&output.tokens,true,32));
  let ExprKind::Unary{op,value}=&mut expr.kind else{panic!("actual whole-primary unary")};assert_eq!(op.as_str(),"!");
  let ExprKind::Binary{op,lhs,rhs}=&mut value.kind else{panic!("actual primary In")};assert_eq!(op.as_str(),"in");
  assert!(matches!(&rhs.kind,ExprKind::Binary{op,..}if op=="||"),"the container keeps its full expression");
  let ExprKind::Call{callee,..}=&mut lhs.kind else{panic!("actual primary call")};
  let ExprKind::Ident(name)=&mut callee.kind else{panic!("actual locate head")};*name="lookup".into();
  let at=output.tokens.iter().position(|t|t.text=="locate").unwrap();output.tokens[at].text="lookup".into();
  assert!(!original_conditional_child(expr,&output.tokens,true,32),"generic Call-In may not borrow primary unary binding");
  drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]
 fn actual_original_primary_in_receipt_rejects_foreign_token_spans_and_child_data(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in ["input ( user ) as null | anything in items","locate ( ) in world","locate ( type ) in A . contents"]{
   let mut feed=expanded_feed(source);let mut output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   let expr=output.parsed.expr.as_mut().unwrap();assert!(original_conditional_child(expr,&output.tokens,true,32));
   let at=output.tokens.iter().position(|t|t.text=="in").unwrap();
   let saved=output.tokens[at].kind;output.tokens[at].kind=TokenKind::Punctuation;
   assert!(!original_conditional_child(expr,&output.tokens,true,32));output.tokens[at].kind=saved;
   let saved=output.tokens[at].text.clone();output.tokens[at].text="as".into();
   assert!(!original_conditional_child(expr,&output.tokens,true,32));output.tokens[at].text=saved;
   let saved=output.tokens[at].span;output.tokens[at].span.end+=1;
   assert!(!original_conditional_child(expr,&output.tokens,true,32));output.tokens[at].span=saved;
   let saved=expr.span;expr.span.end+=1;assert!(!original_conditional_child(expr,&output.tokens,true,32));expr.span=saved;
   if let ExprKind::Binary{rhs,..}=&mut expr.kind{rhs.span.start+=1;}
   assert!(!original_conditional_child(expr,&output.tokens,true,32));
   if let ExprKind::Binary{rhs,..}=&mut expr.kind{rhs.span.start-=1;}
   assert!(original_conditional_child(expr,&output.tokens,true,32));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
   assert!(parse_expression(source).original_simple_expression.is_none(),"compatibility source alone issues no Original receipt");
  }
 }
 #[test]
 fn actual_original_primary_in_preserves_first_read_error_and_quota_refunds(){
  struct FailEnd{feed:ExpandedFeed,failed:bool}
  impl NativeExpressionTokenDemand for FailEnd{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed,"no source pull after first actual IO");if self.feed.0.0.at==self.feed.0.0.rows.len(){self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed,"no token loan after first actual IO");self.feed.original_value(o)}
   fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed,"no colon loan after first actual IO");self.feed.original_close_colon(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  for source in ["input ( user ) as null | anything in items","locate ( ) in world","locate ( type ) in A . contents"]{
   let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=FailEnd{feed:expanded_feed(source),failed:false};
   let error=parse_original_expression_demanded(&mut feed,&a).err().expect("actual end read IO");assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);
   let tiny=crate::SettingAdmission::new(&used,base,&||Ok(()));let mut feed=expanded_feed(source);
   let error=parse_original_expression_demanded(&mut feed,&tiny).err().expect("real quota");assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  }
 }
 #[test]
 fn actual_original_typed_input_first_clause_mode_io_stops_before_union_without_a_proof() {
     struct Fail { feed:ScalarMembershipFeed, failed:bool, modes:usize }
     impl NativeExpressionTokenDemand for Fail {
         fn next_token(&mut self)->std::io::Result<Option<Token>> {
             assert!(!self.failed,"the first real clause-mode IO stops subsequent source pulls");self.feed.next_token()
         }
         fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(at)}
         fn original_close_colon(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{self.feed.original_close_colon(at)}
         fn requires_original_values(&self)->bool{true}
         fn set_original_primitive_clause_mode(&mut self,_:NativePrimitiveClauseMode)->std::io::Result<NativePrimitiveClauseMode>{self.modes+=1;self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}
     }
     let rows=[(TokenKind::Ident,"input",None),(TokenKind::Punctuation,"(",None),(TokenKind::Punctuation,")",None),(TokenKind::Ident,"as",None),(TokenKind::Ident,"text",None)];
     let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
     let admission=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
     let mut feed=Fail{feed:ScalarMembershipFeed(Feed::new(&rows)),failed:false,modes:0};
     let failure=parse_original_expression_demanded(&mut feed,&admission).err().expect("same primary IO, not an unissued nominal body");
     assert_eq!(failure.raw_os_error(),Some(1450));assert_eq!(feed.modes,1);
     assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
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

 #[test]
 fn actual_original_safe_index_complete_value_key_keeps_condition_and_closed_target_roles(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,wanted)in[
   ("GLOB . stat_input_keys ?[ nameof ( icon ) ]",true),
   ("table ?[ nameof ( icon ) ]",true),
   ("table ?[ list ]",true),("table ?[ input ]",true),("table ?[ . ]",true),
   ("GLOB . readers ?[ left + right ]",true),
   ("table ?[ table ?[ table ?[ nameof ( icon ) ] ] ]",true),
   ("GLOB . stat_input_keys ?[ nameof ( icon ) ] || GLOB . derived_read_vars ?[ nameof ( icon ) ]",true),
   ("factory ( ) [ nameof ( icon ) ]",true),
   ("factory ( ) ?[ nameof ( icon ) ]",true),
   ("table ?[ nameof ( icon ) ] = value",false),
   ("table ?[ nameof ( icon ) ] += value",false),
   ("table ?[ nameof ( icon ) ] ( value )",false),
  ]{
   let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();
   assert_eq!(output.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),wanted.then_some(OriginalSimpleKind::Complete),"{source}: {:?}",output.parsed().diagnostics);
   if wanted{assert!(output.parsed().diagnostics.is_empty())}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]
 fn actual_original_safe_complete_key_requires_owned_delimiters_and_each_child_occurrence(){
  let source="GLOB . readers ?[ nameof ( icon ) ]";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed().expr.as_ref().unwrap();
  assert!(original_call_or_safe_read_index(root,&output.tokens,32));assert!(!original_assignment_target(root,&output.tokens,true,true));
  for mutation in 0..8{let mut tokens=output.tokens.clone();match mutation{
   0=>tokens[3].kind=TokenKind::Operator,1=>tokens[3].span.end-=1,2=>tokens[4].text="foreign".into(),
   3=>tokens[6].text="other".into(),4=>tokens[6].span.end+=1,5=>tokens[8].kind=TokenKind::Operator,
   6=>tokens[8].span.end+=1,_=>tokens[3].span.start=tokens[2].span.end-1,
  }assert!(!original_call_or_safe_read_index(root,&tokens,32),"altered actual key occurrence {mutation}");}
 }
 #[test]
 fn actual_original_nested_safe_value_keys_keep_the_existing_remaining_depth(){
  let source="table ?[ table ?[ table ?[ nameof ( icon ) ] ] ]";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let root=output.parsed().expr.as_ref().unwrap();assert!(original_call_or_safe_read_index(root,&output.tokens,32));assert!(!original_call_or_safe_read_index(root,&output.tokens,3));drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_original_safe_complete_key_preserves_actual_end_io_quota_and_same_input_recovery(){
  struct End{inner:PostUpdateFeed,failed:bool}impl NativeExpressionTokenDemand for End{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);match self.inner.next_token()?{Some(token)=>Ok(Some(token)),None=>{self.failed=true;Err(std::io::Error::from_raw_os_error(1450))}}}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="GLOB . readers ?[ nameof ( icon ) ]";let rows:Vec<_>=source.split_whitespace().map(|text|(if original_ascii_identifier(text){TokenKind::Ident}else{crate::original_scalar_transport::original_punctuation_native_kind(text)},text,None)).collect();let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut failed=End{inner:PostUpdateFeed(Feed::new(&rows)),failed:false};assert_eq!(parse_original_expression_demanded(&mut failed,&a).err().unwrap().raw_os_error(),Some(1450));assert!(failed.failed);assert_eq!(used.load(Ordering::Acquire),fixed);
  let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let mut feed=PostUpdateFeed(Feed::new(&rows));assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let mut feed=PostUpdateFeed(Feed::new(&rows));let good=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(good.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::Complete);drop(good);assert_eq!(used.load(Ordering::Acquire),fixed);
 }

 #[test]fn actual_original_bare_prefix_value_keeps_statement_identity_and_closed_receivers(){
  use OriginalSimpleKind::*;
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,wanted)in[("++ i",Some(PrefixIncrementStatement)),("-- i",Some(PrefixDecrementStatement)),("consume ( ++ i )",Some(Complete)),("L ?[ -- i ]",Some(Complete)),("value = ++ i",Some(PlainAssignment)),("++ null",None),("++ object . field",Some(PrefixIncrementStatement)),("++ L [ i ]",None),("( ++ i ) . field",None),("( ++ i ) ( )",None),("++ i = value",None)]{
   let mut feed=expanded_feed(source);let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(output.parsed().original_simple_expression.map(|p|p.kind()),wanted,"{source}: {:?}",output.parsed().diagnostics);
   if let Some(proof)=output.parsed().original_simple_expression{if matches!(proof.kind(),PrefixIncrementStatement|PrefixDecrementStatement|Complete){assert!(proof.is_read_value())}}
   drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn actual_original_bare_prefix_value_authenticates_operator_name_depth_and_each_span(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed("++ i");let output=parse_original_expression_demanded(&mut feed,&a).unwrap();let expr=output.parsed().expr.as_ref().unwrap();assert!(original_conditional_child(expr,&output.tokens,false,32));assert!(!original_conditional_child(expr,&output.tokens,false,0));assert!(!original_composed_expression_mode(expr,&output.tokens,false,32,false,false));
  for mutation in 0..6{let mut tokens=output.tokens.clone();match mutation{0=>tokens[0].kind=TokenKind::Punctuation,1=>tokens[0].text="--".into(),2=>tokens[0].span.end-=1,3=>tokens[1].text="other".into(),4=>tokens[1].span.start+=1,_=>tokens[1].span.end+=1}assert!(!original_conditional_child(expr,&tokens,false,32),"actual prefix occurrence mutation {mutation}");}drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_bare_prefix_value_preserves_first_io_quota_and_same_input_recovery(){
  struct Stop{inner:ExpandedFeed,at:usize,calls:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.calls+=1;if self.calls==self.at{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.inner.next_token()}
   fn original_value(&self,at:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.inner.original_value(at)}
   fn requires_original_values(&self)->bool{true}
  }
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for at in[1,2,3]{let mut feed=Stop{inner:expanded_feed("++ i"),at,calls:0,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert!(feed.failed);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
  let denied=crate::SettingAdmission::new(&used,used.load(Ordering::Acquire),&||Ok(()));let mut feed=expanded_feed("++ i");assert_eq!(parse_original_expression_demanded(&mut feed,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);
  let mut feed=expanded_feed("++ i");let output=parse_original_expression_demanded(&mut feed,&a).unwrap();assert!(output.parsed().original_simple_expression.unwrap().is_read_value());drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_original_nameof_relative_proc_is_only_a_consumed_nameof_argument(){
  use OriginalSimpleKind::Complete;
  for(source,wanted)in[
   ("nameof ( . proc / sweep_step )",Some(Complete)),
   ("then ( ( nameof ( . proc / sweep_step ) ) )",Some(Complete)),
   ("after ( src , delay , ( nameof ( . proc / loop_timer_fired ) ) , key = \"loop_token\" )",Some(Complete)),
   ("safe_call ( ( nameof ( . proc / start_step ) ) )",Some(Complete)),
   ("nameof ( . foo / sweep_step )",None),
   ("consume ( . proc / sweep_step )",None),
   ("nameof ( . proc / sweep_step , other )",None),
   ("nameof ( . proc / sweep_step = value )",None),
   (". proc / sweep_step = value",None),
   ("nameof ( . proc / sweep_step ) ( )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("nameof(.proc/sweep_step)").original_simple_expression.is_none());
 }
 #[test]fn actual_original_nameof_relative_proc_requires_each_actual_path_occurrence(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("nameof ( . proc / sweep_step )"),&a).unwrap();
  assert!(output.parsed().original_simple_expression.is_some());
  for at in 1..7{
   let saved=output.tokens[at].clone();output.tokens[at].kind=if at==1||at==6{TokenKind::Operator}else{TokenKind::Number};
   assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));
   output.tokens[at]=saved.clone();output.tokens[at].span.end+=1;
   assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));
   output.tokens[at]=saved;
  }
  assert!(original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));
  drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_nameof_relative_proc_keeps_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="nameof ( . proc / sweep_step )";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  for stop in[1,4,8]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 #[test]fn actual_original_member_keyword_values_keep_current_callee_and_argument_roles(){
  use OriginalSimpleKind::Complete;
  for(source,wanted)in[
   ("list ( global . ref_many ( nameof ( participants ) , / datum , on_other_deleted = 2 ) )",Some(Complete)),
   ("consume ( object . method ( first , option = value ) )",Some(Complete)),
   ("consume ( object . nested . method ( option = value , last ) )",Some(Complete)),
   ("consume ( object . method ( option = ( value = other ) ) )",Some(Complete)),
   ("consume ( object . method ( option = value = other ) )",None),
   ("consume ( object . method ( object . key = value ) )",None),
   ("consume ( object . method ( option += value ) )",None),
   ("consume ( object ?. method ( option = value ) )",None),
   ("consume ( factory ( ) . method ( option = value ) )",None),
   ("consume ( object . method ( option = value ) = other )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("consume(object.method(option=value))").original_simple_expression.is_none());
 }
 #[test]fn actual_original_member_keyword_value_requires_actual_receiver_key_and_operator(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("consume ( object . method ( option = value ) )"),&a).unwrap();
  assert!(output.parsed().original_simple_expression.is_some());
  for at in[3,4,6,7]{let saved=output.tokens[at].clone();output.tokens[at].kind=TokenKind::Number;
   assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));output.tokens[at]=saved;}
  assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,2,false));
  assert!(original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));
  drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_member_keyword_value_keeps_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="consume ( object . method ( option = value ) )";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  for stop in[1,8,12]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 #[test]fn actual_original_member_prefix_value_keeps_root_identity_and_closed_receivers(){
  use OriginalSimpleKind::{Complete,PrefixIncrementStatement,PrefixDecrementStatement,SimpleAssignmentStatement};
  for(source,wanted)in[("++ lane . seq",Some(PrefixIncrementStatement)),("-- lane . seq",Some(PrefixDecrementStatement)),("J . id = ++ lane . seq",Some(SimpleAssignmentStatement)),("consume ( ++ lane . seq )",Some(Complete)),("++ lane . next . seq",Some(PrefixIncrementStatement)),("++ lane ?. seq",None),("++ lane : seq",None),("++ values [ key ]",None),("++ factory ( ) . seq",None),("( ++ lane . seq ) . field",None),("( ++ lane . seq ) ( )",None),("++ lane . seq = value",None)]{expanded_expect(source,wanted);}
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let output=parse_original_expression_demanded(&mut expanded_feed("++ lane . seq"),&a).unwrap();let proof=output.parsed().original_simple_expression.unwrap();assert_eq!(proof.kind(),PrefixIncrementStatement);assert!(proof.is_read_value());assert!(!original_composed_expression_mode(output.parsed().expr.as_ref().unwrap(),output.tokens(),true,32,false,false),"no receiver/callee value grant");drop(output);assert_eq!(used.load(Ordering::Acquire),base);
  assert!(parse_expression("++lane.seq").original_simple_expression.is_none(),"compatibility parse cannot supply Original authority");
 }
 #[test]fn actual_original_member_prefix_value_binds_each_token_target_span_and_remaining_depth(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut output=parse_original_expression_demanded(&mut expanded_feed("++ lane . next . seq"),&a).unwrap();
  assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),output.tokens(),32).is_some());assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),output.tokens(),2).is_none());assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),output.tokens(),true,2,false));
  for at in 0..output.tokens.len(){let saved=output.tokens[at].clone();output.tokens[at].kind=if saved.kind==TokenKind::Ident{TokenKind::Number}else if saved.kind==TokenKind::Operator{TokenKind::Punctuation}else{TokenKind::Operator};assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),&output.tokens,32).is_none(),"kind token {at}");output.tokens[at]=saved.clone();output.tokens[at].span.end+=1;assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),&output.tokens,32).is_none(),"width token {at}");output.tokens[at]=saved.clone();output.tokens[at].span=Span::new(saved.span.start+1000,saved.span.end+1000);assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),&output.tokens,32).is_none(),"foreign token {at}");output.tokens[at]=saved;}
  output.tokens[0].text="--".into();assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),&output.tokens,32).is_none());output.tokens[0].text="++".into();assert!(original_prefix_update_at(output.parsed().expr.as_ref().unwrap(),&output.tokens,32).is_some());drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_member_prefix_value_preserves_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,calls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.calls+=1;if self.calls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let source="J . id = ++ lane . seq";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();for stop in[1,6,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),calls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.calls,stop);assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));
 }


 #[test]fn actual_original_safe_index_after_ordinary_index_is_read_only_composition(){
  for(source,wanted)in[
   ("GLOB . type_trait_tables [ kind ] ?[ holder . type ]",Some(OriginalSimpleKind::Complete)),
   ("tables [ kind ] ?[ key ]",Some(OriginalSimpleKind::Complete)),
   ("tables [ kind ] [ row ] ?[ key ]",Some(OriginalSimpleKind::Complete)),
   ("consume ( tables [ kind ] ?[ key ] )",Some(OriginalSimpleKind::Complete)),
   ("tables [ kind ] ?[ key ] = value",None),
   ("tables [ kind ] ?[ key ] ++",None),
   ("++ tables [ kind ] ?[ key ]",None),
   ("tables [ kind ] ?[ key ] ( )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("tables[kind]?[key]").original_simple_expression.is_none(),"compatibility AST cannot issue Original authority");
 }
 #[test]fn actual_original_nested_safe_read_requires_each_bracket_occurrence_and_remaining_depth(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut output=parse_original_expression_demanded(&mut expanded_feed("GLOB . type_trait_tables [ kind ] ?[ holder . type ]"),&a).unwrap();let expr=output.parsed.expr.as_ref().unwrap();assert!(output.parsed.original_simple_expression.is_some());
  for at in[3,5,6,10]{let saved=output.tokens[at].clone();output.tokens[at].kind=TokenKind::Operator;assert!(!original_call_or_safe_read_index(expr,&output.tokens,32),"actual bracket kind at {at}");output.tokens[at]=saved.clone();output.tokens[at].span.end+=1;assert!(!original_call_or_safe_read_index(expr,&output.tokens,32),"actual bracket width at {at}");output.tokens[at]=saved;}
  let saved=output.tokens[6].span;output.tokens[6].span.start+=1000;output.tokens[6].span.end+=1000;assert!(!original_call_or_safe_read_index(expr,&output.tokens,32));output.tokens[6].span=saved;
  assert!(!original_call_or_safe_read_index(expr,&output.tokens,2));assert!(original_call_or_safe_read_index(expr,&output.tokens,32));drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_nested_safe_read_preserves_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let source="GLOB . type_trait_tables [ kind ] ?[ holder . type ]";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();for stop in[1,7,12]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }
 #[test]fn actual_original_associative_list_call_keys_are_values_not_named_targets(){
  use OriginalSimpleKind::Complete;
  for(source,wanted)in[
   ("list ( num2text ( 1459 ) = list ( ) , num2text ( 1343 ) = list ( 199 ) , )",Some(Complete)),
   ("alist ( key_for ( value ) = other )",Some(Complete)),
   ("consume ( list ( key_for ( value ) = other ) )",Some(Complete)),
   ("consume ( key_for ( value ) = other )",None),
   ("icon ( key_for ( value ) = other )",None),
   ("list ( key_for ( value ) += other )",None),
   ("list ( key_for ( value ) = other = last )",None),
   ("list ( object . key_for ( value ) = other )",None),
   ("list ( key_for ( value ) = other ) ( )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("list(num2text(1459)=list())").original_simple_expression.is_none());
 }
 #[test]fn actual_original_associative_call_key_requires_actual_operator_and_child_occurrences(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("list ( key_for ( value ) = other )"),&a).unwrap();
  assert!(output.parsed().original_simple_expression.is_some());
  for at in[2,6]{let saved=output.tokens[at].clone();output.tokens[at].kind=TokenKind::Number;
   assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));output.tokens[at]=saved;}
  let saved=output.tokens[6].span;output.tokens[6].span.end+=1;
  assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));output.tokens[6].span=saved;
  assert!(!original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,2,false));
  assert!(original_composed_expression(output.parsed().expr.as_ref().unwrap(),&output.tokens,true,32,false));
  drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_associative_call_key_keeps_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="list ( key_for ( value ) = other )";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  for stop in[1,7,10]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 #[test]fn actual_original_call_result_member_equals_is_only_an_exact_root_statement(){
  use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[
   ("rx_of ( src ) . look_seen_dir = dir",Some(SimpleAssignmentStatement)),
   ("factory ( ) . value = lookup ( current )",Some(SimpleAssignmentStatement)),
   ("factory ( argument ) . value += other",Some(SimpleAssignmentStatement)),
   ("factory ( argument ) ?. value = other",Some(SimpleAssignmentStatement)),
   ("factory ( argument ) : value = other",None),
   ("factory ( argument ) . value ++",Some(OriginalSimpleKind::PostIncrementStatement)),
   ("factory ( argument ) . child . value = other",Some(SimpleAssignmentStatement)),
   ("owner . factory ( argument ) . value = other",Some(SimpleAssignmentStatement)),
   ("consume ( factory ( argument ) . value = other )",None),
   ("( factory ( argument ) . value = other )",Some(OriginalSimpleKind::Complete)),
   ("factory ( argument ) . value = other = last",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("rx_of(src).look_seen_dir=dir").original_simple_expression.is_none());
 }
 #[test]fn actual_original_call_result_safe_chain_equals_requires_root_and_each_exact_follow(){
  use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[
   ("hud_of ( M ) ?. pullin ?. icon_state = \"pull1\"",Some(SimpleAssignmentStatement)),
   ("hud_of ( M ) ?. pullin ?. icon_state = dir",Some(SimpleAssignmentStatement)),
   ("hud_of ( M ) ?. pullin ?. icon_state += dir",Some(SimpleAssignmentStatement)),
   ("hud_of ( M ) ?. pullin ?. icon_state ++",None),
   ("hud_of ( M ) ?. pullin : icon_state = dir",None),
   ("owner . hud_of ( M ) ?. pullin ?. icon_state = dir",None),
   ("consume ( hud_of ( M ) ?. pullin ?. icon_state = dir )",None),
   ("( hud_of ( M ) ?. pullin ?. icon_state = dir )",None),
  ]{expanded_expect(source,wanted);}
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("hud_of ( M ) ?. pullin ?. icon_state = dir"),&a).unwrap();
  let ExprKind::Binary{lhs,..}=&output.parsed().expr.as_ref().unwrap().kind else{panic!("actual root assignment")};let at=output.tokens.partition_point(|token|token.span.end<=lhs.span.end);
  assert!(original_call_result_safe_chain_root_write(lhs,&output.tokens[..at],32));assert!(!original_call_result_safe_chain_root_write(lhs,&output.tokens[..at],2));
  for i in[1,3,4,5,6,7]{let saved=output.tokens[i].clone();output.tokens[i].span.end+=1;assert!(!original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));output.tokens[i]=saved.clone();output.tokens[i].kind=TokenKind::Operator;assert!(!original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));output.tokens[i]=saved;}
 }
 #[test]fn actual_original_call_result_named_arguments_keep_statement_role_and_real_receiver_proof(){
  for(source,wanted)in[
   ("linked_action ( ) . Trigger ( trigger_flags = trigger_flags )",Some(OriginalSimpleKind::OrdinaryCallStatement)),
   ("linked_action ( value ) ?. Trigger ( trigger_flags = flag , other = value )",Some(OriginalSimpleKind::OrdinaryCallStatement)),
   ("consume ( linked_action ( ) . Trigger ( trigger_flags = flag ) )",None),
   ("linked_action ( ) : Trigger ( trigger_flags = flag )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("linked_action().Trigger(trigger_flags=trigger_flags)").original_simple_expression.is_none());
 }
 #[test]fn actual_original_safe_call_compound_write_requires_target_operator_and_root_role(){
  for source in["holder ( ) . screen -= src","holder ( ) ?. screen -= src","holder ( ) ?. screen += src","holder ( ) ?. screen <<= 1","hud_of ( M ) ?. pullin ?. icon_state -= dir"]{
   expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));
  }
  for source in["consume ( holder ( ) ?. screen -= src )","( holder ( ) ?. screen -= src )","holder ( ) : screen -= src","holder ( ) ?. screen ++"]{expanded_expect(source,None);}
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("holder ( ) ?. screen -= src"),&a).unwrap();assert!(output.parsed().original_simple_expression.is_some());
  let at=output.tokens.iter().position(|token|token.text=="-=").unwrap();let saved=output.tokens[at].clone();output.tokens[at].kind=TokenKind::Number;assert!(!original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));output.tokens[at]=saved.clone();output.tokens[at].span.end+=1;assert!(!original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));output.tokens[at]=saved;assert!(original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));
 }
 #[test]fn actual_original_new_chain_and_grouped_logical_require_outer_operator_and_index_occurrences(){
  let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,indices,root)in[("a = b = value",&[1usize][..],true),("( GLOB . admin_states [ ui_rights ] ||= value )",&[2usize,4,6,7][..],false),("( states [ row . key ] ||= value )",&[4usize][..],false)]{
   let mut out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();
   let check=|tokens:&[Token]|if root{original_simple_assignment(expr,tokens,true)}else{original_composed_expression_mode(expr,tokens,false,32,false,false)};assert!(check(&out.tokens));
   for &at in indices{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!check(&out.tokens));out.tokens[at]=saved.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!check(&out.tokens));out.tokens[at]=saved;}
  }assert_eq!(used.load(Ordering::Acquire),floor);
 }
 #[test]fn actual_original_root_equals_chain_keeps_right_association_and_root_role(){
  let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let out=simple_original_literal_fixture("jmp_coords = coords = \"in nullspace\"",&a).unwrap();
  assert_eq!(out.parsed.original_simple_expression.as_ref().map(|p|p.kind()),Some(OriginalSimpleKind::SimpleAssignmentStatement));
  let ExprKind::Binary{op,lhs,rhs}=&out.parsed.expr.as_ref().unwrap().kind else{panic!("outer assignment")};assert_eq!(op,"=");assert!(matches!(&lhs.kind,ExprKind::Ident(n)if n=="jmp_coords"));
  assert!(matches!(&rhs.kind,ExprKind::Binary{op,lhs,rhs}if op=="="&&matches!(&lhs.kind,ExprKind::Ident(n)if n=="coords")&&matches!(&rhs.kind,ExprKind::Literal(v)if matches!(v.original_value(),Some(crate::OriginalTokenValue::String("in nullspace"))))));drop(out);assert_eq!(used.load(Ordering::Acquire),floor);
  expanded_expect("a = b = c = value",Some(OriginalSimpleKind::SimpleAssignmentStatement));
  for source in["consume ( a = b = value )","a = factory ( ) . field = value","a = b += value"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_grouped_index_logical_value_and_bare_compound_root_are_distinct(){
  for source in["( GLOB . admin_states [ ( 1 << 3 ) ] ||= new / datum / tgui_state / admin_state ( ( 1 << 3 ) ) )","( GLOB . admin_states [ ui_rights ] ||= new / datum / tgui_state / admin_state ( ui_rights ) )","invoke ( state = ( GLOB . admin_states [ rights ] ||= new / datum / state ( rights ) ) )"]{expanded_expect(source,Some(OriginalSimpleKind::Complete));}
  expanded_expect("( options &= ~ ( ( 1 << 0 ) ) )",Some(OriginalSimpleKind::SimpleAssignmentStatement));
  for source in["consume ( ( options &= mask ) )","( factory ( ) [ rights ] ||= value )","( GLOB ?. states [ rights ] ||= value )"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_nested_string_index_compound_is_root_only(){
  expanded_expect("food_recipes [ Rp ] [ \"Reagents\" ] -= rid",Some(OriginalSimpleKind::SimpleAssignmentStatement));
  for source in["consume ( food_recipes [ Rp ] [ \"Reagents\" ] -= rid )","factory ( ) [ Rp ] [ \"Reagents\" ] -= rid","food_recipes ?[ Rp ] [ \"Reagents\" ] -= rid","food_recipes [ Rp ] [ key ] -= rid"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_grouped_intersection_member_is_read_only(){
  expanded_expect("( target_admin_datum . ranks & GLOB . protected_ranks ) . len > 0",Some(OriginalSimpleKind::Complete));
  for source in["( target_admin_datum . ranks & GLOB . protected_ranks ) . len = value","( target_admin_datum . ranks & GLOB . protected_ranks ) . len ++","( factory ( ) & GLOB . protected_ranks ) . len"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_nested_string_compound_requires_each_bracket_and_operator(){
  let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed("food_recipes [ Rp ] [ \"Reagents\" ] -= rid"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_simple_assignment(expr,&out.tokens,true));
  for at in[1,3,4,6,7]{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!original_simple_assignment(expr,&out.tokens,true));out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_simple_assignment(expr,&out.tokens,true));out.tokens[at]=saved;}
  let ExprKind::Binary{lhs,..}=&expr.kind else{panic!()};assert!(!original_nested_string_index_compound_target(lhs,&out.tokens[..7],0));drop(out);assert_eq!(used.load(Ordering::Acquire),floor);
 }
 #[test]fn actual_original_early_receiver_families_require_each_new_occurrence(){
  let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,indices,role)in[
   ("( sched ?. meter || km_meter ( ) ) . attr",&[0usize,4,8,9][..],0),
   ("holder . rx ?. ledger ?[ \"kind\" ] ?[ what ]",&[1usize,3,5,7,8,10][..],0),
   ("rx_of ( worn_seen ) . worn_watched ++",&[1usize,3,4,6][..],1),
   ("succ [ index_of [ A ] ] |= i",&[1usize,3,5,6,7][..],2),
   ("masks [ negated ? 2 : 1 ] |= 1 << ( i - 1 )",&[1usize,3,5,7,8][..],2),
   ("own_table_of ( D ) . entries ?[ var_name ]",&[1usize,3,4,6,8][..],0),
   ("I . by_z [ at [ 2 ] ] ?[ k ] -= value",&[1usize,3,5,7,8,9,11,12][..],2),
   ("F [ initial ( D . field ) ] |= initial ( D . channel )",&[1usize,3,5,7,8,9][..],2),
  ]{
   let mut out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();let check=|tokens:&[Token]|match role{0=>original_composed_expression_mode(expr,tokens,false,32,false,false),1=>original_call_member_post_update_root(expr,tokens).is_some(),_=>original_simple_assignment(expr,tokens,true)};assert!(check(&out.tokens),"{source}");
   for &at in indices{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!check(&out.tokens),"kind {source} {at}");out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!check(&out.tokens),"width {source} {at}");out.tokens[at]=saved.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!check(&out.tokens),"foreign {source} {at}");out.tokens[at]=saved;}
   if role==0{assert!(!original_composed_expression_mode(expr,&out.tokens,false,1,false,false));}
  }assert_eq!(used.load(Ordering::Acquire),floor);
 }
 #[test]fn actual_original_early_receiver_families_keep_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}// Preserve the SAME issued Colon/CloseColon role before injecting a stream failure.
   fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed);self.feed.original_close_colon(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();
  for source in["( sched ?. meter || km_meter ( ) ) . attr","holder . rx ?. ledger ?[ \"kind\" ] ?[ what ]","rx_of ( worn_seen ) . worn_watched ++","succ [ index_of [ A ] ] |= i","masks [ negated ? 2 : 1 ] |= value","own_table_of ( D ) . entries ?[ var_name ]","I . by_z [ at [ 2 ] ] ?[ k ] -= value","F [ initial ( D . field ) ] |= value"]{
   for stop in[1,4,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut f=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};let error=parse_original_expression_demanded(&mut f,&a).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450),"source={source} stop={stop} error={error:?}");assert_eq!(f.pulls,stop);assert_eq!(used.load(Ordering::Acquire),floor);}
   let denied=crate::SettingAdmission::new(&used,floor,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),floor);
   let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();assert!(out.parsed.original_simple_expression.is_some());drop(out);assert_eq!(used.load(Ordering::Acquire),floor);
  }
 }
 #[test]fn actual_original_early_logical_group_and_successive_safe_index_keep_read_roles(){
  for source in["( sched ?. meter || km_meter ( ) ) . attr","holder . rx ?. ledger ?[ \"kind\" ] ?[ what ]","! ! holder . rx ?. ledger ?[ \"kind\" ] ?[ what ]","own_table_of ( D ) . entries ?[ var_name ]"]{expanded_expect(source,Some(OriginalSimpleKind::Complete));}
  for source in["( sched ?. meter || km_meter ( ) ) . attr = value","holder . rx ?. ledger ?[ \"kind\" ] ?[ what ] = value","holder . rx ?. ledger ?[ \"kind\" ] ?[ what ] ( )"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_early_call_member_compounds_and_post_updates_are_root_only(){
  for source in["rx_of ( source ) . sourced += A","rx_of ( worn_seen ) . worn_watched ++"]{let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();assert!(out.parsed.original_simple_expression.is_some(),"{source}");drop(out);assert_eq!(used.load(Ordering::Acquire),floor);}
  for source in["consume ( rx_of ( source ) . sourced += A )","consume ( rx_of ( worn_seen ) . worn_watched ++ )","owner . rx_of ( source ) . sourced += A"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_early_conditional_and_nested_index_keys_keep_root_compound_role(){
  for source in["masks [ negated ? 2 : 1 ] |= 1 << ( i - 1 )","succ [ index_of [ A ] ] |= i","F [ initial ( D . field ) ] |= initial ( D . channel )"]{expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));}
  expanded_expect("F [ choose ( a , b ) ] |= value",Some(OriginalSimpleKind::SimpleAssignmentStatement));
  for source in["consume ( masks [ negated ? 2 : 1 ] |= value )","consume ( succ [ index_of [ A ] ] |= i )"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_early_sequential_index_compounds_keep_complete_prefix_and_root_role(){
  for source in["I . by_z [ z ] [ k ] += ( holder . handle_slot || slot_of ( holder ) )","I . by_z [ at [ 2 ] ] ?[ k ] -= ( holder . handle_slot || slot_known ( holder ) )","I . by_z [ at [ 2 ] ] ?[ k ] = null"]{expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));}
  expanded_expect("factory ( ) [ z ] [ k ] += value",Some(OriginalSimpleKind::SimpleAssignmentStatement));
  for source in["consume ( I . by_z [ z ] [ k ] += value )","I . by_z [ z ] ?[ k ] ++"]{expanded_expect(source,None);}
 }
 #[test]fn actual_original_call_result_write_requires_each_call_dot_field_and_equals_occurrence(){
  let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut output=parse_original_expression_demanded(&mut expanded_feed("rx_of ( src ) . look_seen_dir = dir"),&a).unwrap();
  assert!(output.parsed().original_simple_expression.is_some());
  for at in[1,3,4,5,6]{let saved=output.tokens[at].clone();output.tokens[at].kind=if at==1||at==3||at==4{TokenKind::Operator}else{TokenKind::Number};
   assert!(!original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));output.tokens[at]=saved.clone();output.tokens[at].span.end+=1;
   assert!(!original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));output.tokens[at]=saved;
  }
  let ExprKind::Binary{lhs,..}=&output.parsed().expr.as_ref().unwrap().kind else{panic!("same root assignment")};let at=output.tokens.partition_point(|token|token.span.end<=lhs.span.end);
  assert!(!original_call_result_member_root_write(lhs,&output.tokens[..at],1));
  assert!(original_simple_assignment(output.parsed().expr.as_ref().unwrap(),&output.tokens,true));
  drop(output);assert_eq!(used.load(Ordering::Acquire),base);
 }
 #[test]fn actual_original_call_result_write_keeps_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}
  impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}
   fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed);self.feed.original_close_colon(o)}
   fn requires_original_values(&self)->bool{true}
  }
  let source="rx_of ( src ) . look_seen_dir = dir";let base=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(base).unwrap();
  for stop in[1,5,9]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);}
  let a=crate::SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
  expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));
 }

 #[test]fn actual_original_grouped_plain_member_reads_supply_independent_value_children(){
  for(source,wanted)in[
   ("( GLOB . input_router ) . type",Some(OriginalSimpleKind::Complete)),
   ("GLOB . input_router . click_is ( params , _sc_tt_shift_table . guarded ( ( GLOB . input_router ) . type , GLOB . input_router ) , \"inspect\" )",Some(OriginalSimpleKind::Complete)),
   ("GLOB . input_router . classify ( P , _sc_tt_click_catcher_table . guarded ( ( GLOB . input_router ) . type , GLOB . input_router ) )",Some(OriginalSimpleKind::Complete)),
   ("( GLOB . input_router ) . type = value",None),
   ("( GLOB . input_router ) . type ++",None),
   ("( GLOB . input_router ) . type ( )",Some(OriginalSimpleKind::Complete)),
   ("( GLOB ?. input_router ) . type",None),
   ("( factory ( ) . field ) . type",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("(GLOB.input_router).type").original_simple_expression.is_none(),"compatibility parse cannot issue Original authority");
 }
 #[test]fn actual_original_grouped_member_read_requires_each_group_and_dot_occurrence(){
  let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed("( GLOB . input_router ) . type"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_composed_expression_mode(expr,&out.tokens,false,32,false,false));
  for at in[0,2,4,5,6]{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!original_composed_expression_mode(expr,&out.tokens,false,32,false,false));out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_composed_expression_mode(expr,&out.tokens,false,32,false,false));out.tokens[at]=saved;}
  assert!(!original_composed_expression_mode(expr,&out.tokens,false,2,false,false));assert!(original_composed_expression_mode(expr,&out.tokens,false,32,false,false));drop(out);assert_eq!(used.load(Ordering::Acquire),floor);
 }
 #[test]fn actual_original_grouped_member_read_keeps_first_io_quota_and_drop(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let source="( GLOB . input_router ) . type";let floor=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(floor).unwrap();
  for stop in[1,4,8]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),floor);}
  let denied=crate::SettingAdmission::new(&used,floor,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),floor);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }


 #[test]fn actual_original_direct_call_safe_index_keeps_absolute_key_and_read_only_role(){
  for(source,wanted)in[
   ("capability_data ( O ) ?[ / datum / material_assembly ]",Some(OriginalSimpleKind::Complete)),
   ("consume ( capability_data ( O ) ?[ / datum / material_assembly ] )",Some(OriginalSimpleKind::Complete)),
   ("capability_data ( O ) ?[ key ]",Some(OriginalSimpleKind::Complete)),
   ("capability_data ( O ) ?[ key ] = value",None),
   ("capability_data ( O ) ?[ key ] ++",None),
   ("capability_data ( O ) ?[ key ] ( )",None),
   ("owner . capability_data ( O ) ?[ key ]",None),
   ("capability_data ( named = O ) ?[ key ]",Some(OriginalSimpleKind::Complete)),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("capability_data(O)?[/datum/material_assembly]").original_simple_expression.is_none());
 }
 #[test]fn actual_original_direct_call_safe_index_requires_call_and_key_occurrences_at_remaining_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed("capability_data ( O ) ?[ / datum / material_assembly ]"),&a).unwrap();
  assert!(out.parsed().original_simple_expression.is_some());let expr=out.parsed.expr.as_ref().unwrap();assert!(original_call_or_safe_read_index(expr,&out.tokens,32));assert!(!original_call_or_safe_read_index(expr,&out.tokens,1));
  for at in 0..out.tokens.len(){let saved=out.tokens[at].clone();out.tokens[at].span.end+=1;assert!(!original_call_or_safe_read_index(expr,&out.tokens,32),"changed occurrence width {at}");out.tokens[at]=saved.clone();out.tokens[at].kind=TokenKind::Number;assert!(!original_call_or_safe_read_index(expr,&out.tokens,32),"changed occurrence kind {at}");out.tokens[at]=saved;}
  for at in[1,3]{let saved=out.tokens[at].kind;out.tokens[at].kind=TokenKind::Operator;assert!(!original_call_or_safe_read_index(expr,&out.tokens,32),"call parentheses need actual punctuation");out.tokens[at].kind=saved;}
  assert!(original_call_or_safe_read_index(expr,&out.tokens,32));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_direct_call_safe_index_preserves_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let source="capability_data ( O ) ?[ / datum / material_assembly ]";let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for stop in[1,7,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }


 #[test]fn actual_original_nameof_relative_verb_uses_same_prefab_argument_role(){
  for(source,wanted)in[
   ("nameof ( . verb / unignore )",Some(OriginalSimpleKind::Complete)),
   ("new / datum / callback ( src , ( nameof ( . verb / mentorhelp ) ) )",Some(OriginalSimpleKind::Complete)),
   ("after ( src , delay , ( nameof ( . verb / fit_viewport ) ) , clock = 0 )",Some(OriginalSimpleKind::Complete)),
   ("nameof ( . foo / unignore )",None),("consume ( . verb / unignore )",None),
   ("nameof ( . verb / unignore , other )",None),(". verb / unignore = value",None),
   ("nameof ( . verb / unignore ) ( )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("nameof(.verb/unignore)").original_simple_expression.is_none());
 }
 #[test]fn actual_original_nameof_relative_verb_requires_namespace_and_each_consumed_occurrence(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed("nameof ( . verb / unignore )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_composed_expression(expr,&out.tokens,true,32,false));
  for at in 1..7{let saved=out.tokens[at].clone();out.tokens[at].kind=if at==1||at==6{TokenKind::Operator}else{TokenKind::Number};assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[at]=saved;}
  let role=out.tokens[3].text.clone();out.tokens[3].text="proc".into();assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"actual .verb AST cannot borrow a different namespace row");out.tokens[3].text=role;
  assert!(original_composed_expression(expr,&out.tokens,true,32,false));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_nameof_relative_verb_keeps_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let source="nameof ( . verb / unignore )";
  for stop in[1,4,8]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }


 #[test]fn actual_original_two_argument_locate_keeps_primary_positional_value_role(){
  for(source,wanted)in[
   ("locate ( / obj / structure / grille , T )",Some(OriginalSimpleKind::Complete)),
   ("! ( locate ( / obj / structure / grille , T ) )",Some(OriginalSimpleKind::Complete)),
   ("consume ( locate ( key , container ) )",Some(OriginalSimpleKind::Complete)),
   ("locate ( a , b , c , d )",None),
   ("locate ( key = value , container )",None),
   ("locate ( key , container ) in other",None),
   ("locate ( key , container ) = value",None),
   ("locate ( key , container ) ( )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("locate(/obj/structure/grille,T)").original_simple_expression.is_none());
 }
 #[test]fn actual_original_two_argument_locate_requires_each_token_and_remaining_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed("locate ( / obj / structure / grille , T )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();
  assert!(original_composed_expression(expr,&out.tokens,true,32,false));assert!(!original_composed_expression(expr,&out.tokens,true,1,false));
  for at in 0..out.tokens.len(){let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"kind {at}");out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"width {at}");out.tokens[at]=saved;}
  for at in[1,8,10]{let saved=out.tokens[at].kind;out.tokens[at].kind=TokenKind::Operator;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"actual parentheses/comma punctuation {at}");out.tokens[at].kind=saved;}
  let comma=out.tokens[8].span;out.tokens[8].span.start+=1000;out.tokens[8].span.end+=1000;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"same-width foreign comma is not the consumed separator");out.tokens[8].span=comma;
  assert!(original_composed_expression(expr,&out.tokens,true,32,false));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_two_argument_locate_preserves_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let source="locate ( / obj / structure / grille , T )";let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for stop in[1,6,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 #[test]fn actual_original_numeric_and_absolute_prefab_list_keys_are_bounded_values_only(){
  for(source,wanted)in[
   ("alist ( 100007 = patency ( ) )",Some(OriginalSimpleKind::Complete)),
   ("oracle_accumulate ( acc , alist ( 100007 = patency ( ) ) , 1 )",Some(OriginalSimpleKind::Complete)),
   ("list ( / datum / affliction_symptom / nausea = 80 )",Some(OriginalSimpleKind::Complete)),
   ("list ( \"Mild\" = list ( symptom_pool = list ( / datum / affliction_symptom / nausea = 80 ) ) )",Some(OriginalSimpleKind::Complete)),
   ("list ( / datum / key = alist ( 100007 = patency ( ) ) )",Some(OriginalSimpleKind::Complete)),
   ("consume ( 100007 = value )",None),("icon ( / datum / key = value )",None),
   ("100007 = value",None),("/ datum / key = value",None),
   ("list ( owner . field = value )",None),("list ( ( 100007 ) = value )",None),
   ("list ( 100007 += value )",None),("alist ( 100007 = value ) ( )",None),
  ]{expanded_expect(source,wanted);}
  assert!(parse_expression("alist(100007=patency())").original_simple_expression.is_none(),"compatibility parsing does not supply Original proof");
 }
 #[test]fn actual_original_numeric_prefab_keys_require_each_consumed_occurrence_and_remaining_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed("list ( / datum / key = alist ( 100007 = patency ( ) ) )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_composed_expression(expr,&out.tokens,true,32,false));assert!(!original_composed_expression(expr,&out.tokens,true,1,false));
  for at in 0..out.tokens.len(){let saved=out.tokens[at].clone();out.tokens[at].kind=if saved.kind==TokenKind::Number{TokenKind::Ident}else{TokenKind::Number};assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"changed kind {at}");out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"changed width {at}");out.tokens[at]=saved;}
  for at in 0..out.tokens.len(){if out.tokens[at].text!="="{continue}let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Punctuation;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"actual computed key equals kind");out.tokens[at]=saved.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_composed_expression(expr,&out.tokens,true,32,false),"foreign key equals");out.tokens[at]=saved;}
  assert!(original_composed_expression(expr,&out.tokens,true,32,false));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_numeric_prefab_list_keys_keep_first_io_quota_and_same_input_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let source="alist ( 100007 = patency ( ) )";let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for stop in[1,5,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 #[test]fn actual_original_bare_pick_variable_keeps_primitive_call_dispatch_and_roles(){
  for(source,wanted)in[("pick = resumed . value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("! pick",Some(OriginalSimpleKind::Complete)),("consume ( ( pick = value ) )",Some(OriginalSimpleKind::Complete)),("pick ( 1 , 2 )",Some(OriginalSimpleKind::Complete)),("pick . field",Some(OriginalSimpleKind::Complete)),("pick [ key ] = value",None)]{expanded_expect(source,wanted);}
  assert!(!original_ordinary_call_name("pick"));
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut owner=parse_original_expression_demanded(&mut expanded_feed("! pick"),&a).unwrap();let expr=owner.parsed.expr.as_ref().unwrap();assert!(original_composed_expression(expr,&owner.tokens,false,32,false));
  let saved=owner.tokens[1].clone();owner.tokens[1].span.end+=1;assert!(!original_composed_expression(expr,&owner.tokens,false,32,false));owner.tokens[1]=saved;owner.tokens[1].kind=TokenKind::Number;assert!(!original_composed_expression(expr,&owner.tokens,false,32,false));drop(owner);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_bare_pick_preserves_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,at:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{self.at+=1;if self.at==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for stop in[1,2,3]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed("! pick"),at:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.at,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed("! pick"),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect("! pick",Some(OriginalSimpleKind::Complete));
 }


 #[test]fn actual_original_return_slot_membership_keeps_bare_dot_and_both_in_transports(){
  let source="! admin_ckey && ( . in ( GLOB . admin_datums + GLOB . deadmins ) )";let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for punctuation_in in[false,true]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=expanded_feed(source);if punctuation_in{feed.0.0.rows.iter_mut().find(|(t,_)|t.text=="in").unwrap().0.kind=TokenKind::Punctuation;}
   let out=parse_original_expression_demanded(&mut feed,&a).unwrap();assert_eq!(out.parsed().original_simple_expression.map(|p|p.kind()),Some(OriginalSimpleKind::Complete));let ExprKind::Binary{op,rhs,..}=&out.parsed.expr.as_ref().unwrap().kind else{panic!("actual logical condition")};assert_eq!(op,"&&");let ExprKind::Group(membership)=&rhs.kind else{panic!("actual grouped In")};let ExprKind::Binary{op,lhs,..}=&membership.kind else{panic!("actual membership")};assert_eq!(op,"in");assert!(matches!(&lhs.kind,ExprKind::Ident(name)if name=="."),"Dot is never invented relative prefab .in");drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
  let parsed=parse_expression(". in values");assert!(parsed.diagnostics.is_empty());assert!(matches!(&parsed.expr.as_ref().unwrap().kind,ExprKind::Binary{op,lhs,..}if op=="in"&&matches!(&lhs.kind,ExprKind::Ident(name)if name==".")));assert!(parsed.original_simple_expression.is_none(),"compatibility AST cannot issue Original current rights");
 }
 #[test]fn actual_original_return_slot_in_requires_operator_and_dot_occurrences(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed(". in ( GLOB . admin_datums + GLOB . deadmins )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_composed_expression(expr,&out.tokens,true,32,false));
  let saved=out.tokens[1].clone();for kind in[TokenKind::Number,TokenKind::Operator]{out.tokens[1].kind=kind;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));}out.tokens[1]=saved.clone();out.tokens[1].span.end+=1;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[1]=saved.clone();out.tokens[1].span.start+=1000;out.tokens[1].span.end+=1000;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[1]=saved;
  let kind=out.tokens[0].kind;out.tokens[0].kind=TokenKind::Ident;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[0].kind=kind;assert!(original_composed_expression(expr,&out.tokens,true,32,false));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_return_slot_in_keeps_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let source="! admin_ckey && ( . in ( GLOB . admin_datums + GLOB . deadmins ) )";let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for stop in[1,6,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 #[test]fn actual_original_assignment_chain_complex_targets_keep_initializer_only_value_role(){
  use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[
   ("index = M . index_by_key [ key ] = list ( )",Some(SimpleAssignmentStatement)),
   ("trash = SSgarbage . items [ to_delete . type ] = new / datum / qdel_item ( to_delete . type )",Some(SimpleAssignmentStatement)),
   ("lines = GLOB . refresh_traced [ ref_text ] = list ( )",Some(SimpleAssignmentStatement)),
   ("a = object . field = other",Some(SimpleAssignmentStatement)),
   ("GLOB . holder . loc = target = value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),
   ("a = object ?. field = other",None),("a = object : field = other",None),
   ("a = factory ( ) . field = other",None),
   ("consume ( object . field = other )",None),("consume ( a = object . field = other )",None),
  ]{expanded_expect(source,wanted);}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["M . index_by_key [ key ] = list ( )","GLOB . capability_infos = list ( )"]{
   let output=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let proof=output.parsed().original_simple_expression.unwrap();assert_eq!(proof.kind(),SimpleAssignmentStatement);assert!(proof.is_initializer_assignment());assert!(!proof.is_read_value(),"initializer proof cannot promote general reads/arguments/returns");drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
  assert!(parse_expression("a=M.index_by_key[key]=list()").original_simple_expression.is_none());
 }
 #[test]fn actual_original_direct_call_index_equals_keeps_statement_only_target_authority(){
  use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[
   ("link_decls_cache ( ) [ E . sig ] = E",Some(SimpleAssignmentStatement)),
   ("type_blocks_cache ( ) [ B . block_type ] = built",Some(SimpleAssignmentStatement)),
   ("capability_runtime ( A ) . data [ C . key ] = D",Some(SimpleAssignmentStatement)),
   ("capability_runtime ( A ) . data [ / datum / cap_engine_state ] = state",Some(SimpleAssignmentStatement)),
   ("factory ( argument ) [ key ] += value",Some(SimpleAssignmentStatement)),("factory ( ) [ key ] ++",None),
   ("owner . factory ( ) [ key ] = value",Some(SimpleAssignmentStatement)),("factory ( ) ?. data [ key ] = value",None),
   ("factory ( ) [ key ] ( )",None),("consume ( factory ( ) [ key ] = value )",None),
   ("( factory ( ) [ key ] = value )",None),
  ]{expanded_expect(source,wanted);}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let output=parse_original_expression_demanded(&mut expanded_feed("factory ( ) [ key ] = value"),&a).unwrap();assert!(!output.parsed().original_simple_expression.unwrap().is_initializer_assignment());drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_assignment_value_and_call_index_require_exact_occurrences_and_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,call)in[("a = M . values [ row . key ] = value",false),("factory ( value ) . data [ row . key ] = value",true)]{
   let mut output=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let expr=output.parsed.expr.as_ref().unwrap();
   let check=|tokens:&[Token],depth|if call{let ExprKind::Binary{lhs,..}=&expr.kind else{unreachable!()};let at=tokens.partition_point(|t|t.span.end<=lhs.span.end);original_call_result_index_root_write(lhs,&tokens[..at],depth)}else{original_root_assignment_chain_value(expr,tokens,depth)};
   assert!(check(&output.tokens,32));assert!(!check(&output.tokens,1));
   for at in 0..output.tokens.len(){if !matches!(output.tokens[at].text.as_str(),"."|"["|"]"|"("|")"|"="){continue}if call&&output.tokens[at].text=="="{continue}
    let saved=output.tokens[at].clone();output.tokens[at].kind=TokenKind::Number;assert!(!check(&output.tokens,32),"forged kind {source}:{at}");output.tokens[at]=saved.clone();output.tokens[at].span.start+=1000;output.tokens[at].span.end+=1000;assert!(!check(&output.tokens,32),"foreign span {source}:{at}");output.tokens[at]=saved.clone();output.tokens[at].span.end+=1;assert!(!check(&output.tokens,32),"forged width {source}:{at}");output.tokens[at]=saved;
   }
   assert!(check(&output.tokens,32));drop(output);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
 }
 #[test]fn actual_original_assignment_families_keep_first_io_quota_and_same_input_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}
  }
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for source in["a = M . values [ key ] = list ( )","factory ( value ) . data [ key ] = value"]{
   for stop in[1,5,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
   let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));
  }
 }

 #[test]fn actual_original_return_slot_root_updates_do_not_grant_read_key_or_callee_roles(){
  for(source,wanted)in[(". ++",Some(OriginalSimpleKind::PostIncrementStatement)),(". --",Some(OriginalSimpleKind::PostDecrementStatement)),(". [ change_type ] += list ( change_desc )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("++ .",None),("consume ( . ++ )",None),("table [ . ++ ]",None),("( . ++ ) ( )",None),("consume ( . [ key ] += value )",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_return_slot_updates_require_every_occurrence_and_remaining_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed(". [ change_type ] += list ( change_desc )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_return_slot_index_compound(expr,&out.tokens,32));assert!(!original_return_slot_index_compound(expr,&out.tokens,1));
  for at in[0,1,2,3,4]{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!original_return_slot_index_compound(expr,&out.tokens,32),"kind {at}");out.tokens[at]=saved.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_return_slot_index_compound(expr,&out.tokens,32),"foreign {at}");out.tokens[at]=saved;}drop(out);
  let mut out=parse_original_expression_demanded(&mut expanded_feed(". ++"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_return_slot_post_update(expr,&out.tokens).is_some());for at in[0,1]{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(original_return_slot_post_update(expr,&out.tokens).is_none());out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(original_return_slot_post_update(expr,&out.tokens).is_none());out.tokens[at]=saved;}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_return_slot_updates_keep_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for source in[". ++",". [ change_type ] += list ( change_desc )"]{for stop in[1,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);}
  expanded_expect(". --",Some(OriginalSimpleKind::PostDecrementStatement));
 }

 #[test]fn actual_original_arithmetic_key_postfix_is_root_only(){
  for(source,wanted)in[("shed_by_class [ latency_class + 1 ] ++",Some(OriginalSimpleKind::IndexedUpdateStatement)),("values [ i - 1 ] --",Some(OriginalSimpleKind::IndexedUpdateStatement)),("consume ( values [ i + 1 ] ++ )",None),("table [ values [ i + 1 ] ++ ]",None),("values [ i + 1 ] ++ ( )",None),("++ values [ i + 1 ]",None),("factory ( ) [ i + 1 ] ++",None),("GLOB ?. values [ i + 1 ] ++",None)]{expanded_expect(source,wanted);}
  let native=crate::parse_expression("values[i+1]++");assert!(native.original_simple_expression.is_none());
 }
 #[test]fn actual_original_arithmetic_key_postfix_checks_geometry_and_remaining_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut out=parse_original_expression_demanded(&mut expanded_feed("values [ i + 1 ] ++"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_offset_indexed_update_statement(expr,&out.tokens,32));assert!(!original_offset_indexed_update_statement(expr,&out.tokens,1));
  for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_offset_indexed_update_statement(expr,&out.tokens,32),"kind {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_offset_indexed_update_statement(expr,&out.tokens,32),"foreign {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_offset_indexed_update_statement(expr,&out.tokens,32),"width {at}");out.tokens[at]=old;assert!(original_offset_indexed_update_statement(expr,&out.tokens,32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_arithmetic_key_postfix_keeps_first_io_quota_and_drop(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for stop in[1,4,8]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed("values [ i + 1 ] ++"),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed("values [ i + 1 ] ++"),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect("values [ i + 1 ] ++",Some(OriginalSimpleKind::IndexedUpdateStatement));
 }

 // Explicit admitted typed-template DATA drives the SAME demanded parser.
 // This fixture supplies no Source/Header/CurrentModel authority.
 fn prepared_template_key_fixture(callee:&str,a:&crate::SettingAdmission<'_>,stop:Option<usize>)->std::io::Result<DemandedExpression>{
  struct Input{source:String,tokens:Vec<Token>,data:Vec<Option<crate::OriginalLiteralData>>,at:usize,pulls:usize,stop:Option<usize>,failed:bool}
  impl NativeExpressionTokenDemand for Input{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.stop==Some(self.pulls){self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}let t=self.tokens.get(self.at).cloned();self.at+=usize::from(t.is_some());Ok(t)}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}if let Some(d)=self.data[o.ordinal()].as_ref(){return Ok(Some(d.value()))}Ok(Some(if t.kind==TokenKind::Ident{crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false}}else{crate::OriginalTokenValue::Punct(match t.text.as_str(){"("=>"(",")"=>")","="=>"=",_=>return Err(std::io::ErrorKind::InvalidInput.into())})}))}
   fn original_literal_data(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalLiteralRef<'_>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(self.data[o.ordinal()].as_ref().map(crate::OriginalLiteralData::as_view))}
   fn original_template_source(&self,span:Span)->std::io::Result<Option<&str>>{assert!(!self.failed);Ok(self.source.get(span.range()))}
   fn requires_original_values(&self)->bool{true}
  }
  let mut source=String::new();let mut tokens=Vec::new();let mut data=Vec::new();
  for(kind,text,value)in[(TokenKind::Ident,callee,None),(TokenKind::Punctuation,"(",None),(TokenKind::Interpolation,"\"head[",Some(crate::OriginalTokenValue::InterpBegin("head"))),(TokenKind::Ident,"x",None),(TokenKind::Interpolation,"]tail\"",Some(crate::OriginalTokenValue::InterpEnd("tail"))),(TokenKind::Operator,"=",None),(TokenKind::Ident,"value",None),(TokenKind::Punctuation,")",None)]{
   let start=source.len();source.push_str(text);tokens.push(Token{kind,span:Span::new(start,source.len()),text:text.into()});data.push(value.map(|v|crate::OriginalLiteralData::from_value_with_mode_using(text.into(),v,crate::OriginalStringMode::Normal,a)).transpose()?);
  }
  let mut feed=Input{source,tokens,data,at:0,pulls:0,stop,failed:false};let result=parse_original_expression_demanded(&mut feed,a);if let Some(stop)=stop{assert_eq!(feed.pulls,stop,"no supplier pull after first actual failure");}result
 }
 #[test]fn actual_original_prepared_interpolation_is_only_a_list_associative_key(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for callee in["list","alist"]{
   let out=prepared_template_key_fixture(callee,&a,None).unwrap();assert_eq!(out.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),Some(OriginalSimpleKind::Complete));assert!(out.parsed().diagnostics.is_empty());
   let ExprKind::Call{args,..}=&out.parsed().expr.as_ref().unwrap().kind else{panic!("actual list constructor")};let ExprKind::Binary{op,lhs,..}=&args[0].kind else{panic!("actual associative row")};assert_eq!(op,"=");let ExprKind::Literal(value)=&lhs.kind else{panic!("same actual prepared template")};let parts=value.original_prepared_body_parts(lhs.span).unwrap();assert_eq!(parts.expressions.len(),1);assert_eq!(parts.fragments.len(),2);assert!(matches!(&parts.expressions[0].kind,ExprKind::Ident(n)if n=="x"));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
  for callee in["consume","icon"]{let out=prepared_template_key_fixture(callee,&a,None).unwrap();assert!(out.parsed().original_simple_expression.is_none(),"template keys do not become ordinary/icon named arguments");drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);}
 }
 #[test]fn actual_original_template_list_key_keeps_fragment_and_equals_occurrences(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=prepared_template_key_fixture("list",&a,None).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_composed_expression(expr,&out.tokens,true,32,false));assert!(!original_composed_expression(expr,&out.tokens,true,1,false));
  for at in[2,3,4,5]{let saved=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[at]=saved.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_composed_expression(expr,&out.tokens,true,32,false));out.tokens[at]=saved;}
  assert!(original_composed_expression(expr,&out.tokens,true,32,false));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_template_list_key_preserves_first_io_quota_and_same_input_retry(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for stop in[1,4,9]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));assert_eq!(prepared_template_key_fixture("list",&a,Some(stop)).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),fixed);}
  let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(prepared_template_key_fixture("list",&denied,None).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);let healthy=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));drop(prepared_template_key_fixture("list",&healthy,None).unwrap());assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_plain_member_outer_assignment_chain_keeps_root_role(){
  use OriginalSimpleKind::SimpleAssignmentStatement;
  for(source,wanted)in[("src . bounds = parsed_bounds = list ( )",Some(SimpleAssignmentStatement)),("holder . field = target = value",Some(SimpleAssignmentStatement)),("holder ?. field = target = value",None),("holder : field = target = value",None),("factory ( ) . field = target = value",None),("consume ( holder . field = target = value )",None),("holder . field += target = value",None)]{expanded_expect(source,wanted);}
  assert!(parse_expression("src.bounds=parsed_bounds=list()").original_simple_expression.is_none());
 }

 #[test]fn actual_original_grouped_return_slot_assignment_keeps_existing_value_composition(){
  for source in["( . = .. ( ) )","( . = .. ( ) ) && lnif","! ( . = .. ( ) )","consume ( ( . = .. ( ) ) )"]{expanded_expect(source,Some(OriginalSimpleKind::Complete));}
  for source in["consume ( . = .. ( ) )",". = .. ( ) = other","( . += .. ( ) )","( . = .. ( ) ) ( )"]{expanded_expect(source,None);}
  assert!(parse_expression("(.=..())").original_simple_expression.is_none());
 }
 #[test]fn actual_original_grouped_return_slot_assignment_requires_its_own_occurrences_and_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed("( . = .. ( ) )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();
  assert!(original_composed_expression_mode(expr,&out.tokens,false,32,false,false));assert!(!original_composed_expression_mode(expr,&out.tokens,false,1,false,false));
  for at in[0usize,1,2,6]{let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Number;assert!(!original_composed_expression_mode(expr,&out.tokens,false,32,false,false),"kind {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_composed_expression_mode(expr,&out.tokens,false,32,false,false),"foreign {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_composed_expression_mode(expr,&out.tokens,false,32,false,false),"width {at}");out.tokens[at]=old;}
  assert!(original_composed_expression_mode(expr,&out.tokens,false,32,false,false));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_grouped_return_slot_assignment_keeps_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let source="( . = .. ( ) )";
  for stop in[1,4,8]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));
 }

 fn mutation_family_feed(source:&str)->ExpandedFeed{let mut f=expanded_feed(source);for(token,close)in &mut f.0.0.rows{if token.text==":"{*close=Some(true);}}f}
 #[test]fn actual_original_nested_key_postfix_and_colon_assignment_are_root_only(){
  for(source,wanted)in[("degrees [ edge [ 1 ] ] ++",Some(OriginalSimpleKind::IndexedUpdateStatement)),("degrees [ edge [ key ] ] --",Some(OriginalSimpleKind::IndexedUpdateStatement)),("owner : field = value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("stmt . value : exp = new / datum / node ( name )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("consume ( degrees [ edge [ 1 ] ] ++ )",None),("table [ degrees [ edge [ 1 ] ] ++ ]",None),("++ degrees [ edge [ 1 ] ]",None),("degrees [ edge [ 1 ] ] ++ ( )",None),("consume ( owner : field = value )",None),("owner : field += value",None),("owner : field ++",None),("factory ( ) : field = value",None),("owner ?. value : field = value",None)]{
   let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let out=parse_original_expression_demanded(&mut mutation_family_feed(source),&a).unwrap();assert_eq!(out.parsed().original_simple_expression.map(OriginalSimpleExpression::kind),wanted,"{source}");if wanted.is_some(){assert!(out.parsed().diagnostics.is_empty(),"{source}");}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
  assert!(parse_expression("degrees[edge[1]]++").original_simple_expression.is_none());assert!(parse_expression("owner:field=value").original_simple_expression.is_none());
 }
 #[test]fn actual_original_nested_key_postfix_and_colon_assignment_require_every_occurrence(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,proof)in[("degrees [ edge [ 1 ] ] ++",original_nested_key_postfix_root as fn(&Expr,&[Token],usize)->bool),("stmt . value : exp = value",original_colon_member_root_assignment as fn(&Expr,&[Token],usize)->bool)]{
   let mut out=parse_original_expression_demanded(&mut mutation_family_feed(source),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(proof(expr,&out.tokens,32));assert!(!proof(expr,&out.tokens,1));for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!proof(expr,&out.tokens,32),"kind {source} {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!proof(expr,&out.tokens,32),"foreign {source} {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!proof(expr,&out.tokens,32),"width {source} {at}");out.tokens[at]=old;assert!(proof(expr,&out.tokens,32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
  let out=parse_original_expression_demanded(&mut expanded_feed("owner : field = value"),&a).unwrap();assert!(out.parsed().original_simple_expression.is_none());
 }
 #[test]fn actual_original_nested_key_postfix_and_colon_assignment_keep_first_io_and_quota(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{self.feed.original_close_colon(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for source in["degrees [ edge [ 1 ] ] ++","stmt . value : exp = value"]{for stop in[1,4,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:mutation_family_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut mutation_family_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);}
 }

 #[test]fn actual_original_observed_index_compounds_keep_root_roles(){
  for(source,wanted)in[("needed [ stock . material . name ] -= stock . get_amount ( )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("admins_by_rank [ composed_rank . name ] ||= list ( )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),(". [ \"instances\" ] [ item . type ] += list ( item )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("consume ( needed [ stock . material . name ] -= value )",None),("consume ( admins_by_rank [ composed_rank . name ] ||= value )",None),("consume ( . [ \"instances\" ] [ item . type ] += value )",None),("factory ( ) [ composed_rank . name ] ||= value",None),("admins_by_rank ?[ composed_rank . name ] ||= value",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_observed_index_compounds_require_geometry_and_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["needed [ stock . material . name ] -= value","admins_by_rank [ composed_rank . name ] ||= value",". [ \"instances\" ] [ item . type ] += value"]{let mut out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_observed_index_compound_root(expr,&out.tokens,32));assert!(!original_observed_index_compound_root(expr,&out.tokens,1));for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_observed_index_compound_root(expr,&out.tokens,32),"foreign {source} {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_observed_index_compound_root(expr,&out.tokens,32),"width {source} {at}");out.tokens[at]=old;assert!(original_observed_index_compound_root(expr,&out.tokens,32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);}
 }
 #[test]fn actual_original_observed_index_compounds_keep_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for source in["needed [ stock . material . name ] -= value","admins_by_rank [ composed_rank . name ] ||= value",". [ \"instances\" ] [ item . type ] += value"]{for stop in[1,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));}
 }

 #[test]fn actual_original_dynamic_constructor_keywords_keep_their_constructor_role(){
  for(source,wanted)in[("new kw ( inline = 1 )",Some(OriginalSimpleKind::Complete)),("kw = new kw ( inline = 1 )",Some(OriginalSimpleKind::PlainAssignment)),("new target ( key = value , other )",Some(OriginalSimpleKind::Complete)),("new source . type ( key = lookup ( value ) )",Some(OriginalSimpleKind::Complete)),("new target ( object . key = value )",None),("new target ( key += value )",None),("new target ( key = value = other )",None),("new source ?. type ( key = value )",None),("new target [ key ] ( option = value )",None),("consume ( key = value )",Some(OriginalSimpleKind::Complete))]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_numeric_membership_range_keeps_to_context_and_exact_geometry(){
  for(source,wanted)in[("char in 48 to 57",Some(OriginalSimpleKind::Complete)),("( char in 65 to 90 ) || ( char in 97 to 122 ) || char == 95",Some(OriginalSimpleKind::Complete)),("consume ( char in 48 to 57 )",Some(OriginalSimpleKind::Complete)),("48 to 57",None),("char in first to last",None),("owner . char in 48 to 57",Some(OriginalSimpleKind::Complete))]{expanded_expect(source,wanted);}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed("char in 48 to 57"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_numeric_membership_range(expr,&out.tokens,32));assert!(!original_numeric_membership_range(expr,&out.tokens,1));
  for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_numeric_membership_range(expr,&out.tokens,32));out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_numeric_membership_range(expr,&out.tokens,32));out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_numeric_membership_range(expr,&out.tokens,32));out.tokens[at]=old;}
  drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_dynamic_constructor_named_occurrences_and_depth_stay_exact(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed("new kw ( inline = 1 , other = value )"),&a).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_direct_dynamic_new(expr,&out.tokens,32));assert!(!original_direct_dynamic_new(expr,&out.tokens,0));
  for at in[2usize,4,6,8,10]{let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_direct_dynamic_new(expr,&out.tokens,32),"kind {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_direct_dynamic_new(expr,&out.tokens,32),"foreign {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_direct_dynamic_new(expr,&out.tokens,32),"width {at}");out.tokens[at]=old;}
  assert!(out.parsed().original_constructor_facts().unwrap().as_slice().is_empty(),"dynamic target does not mint implicit new hint");drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_read_call_families_keep_first_io_quota_and_same_input_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed);self.feed.original_close_colon(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for source in["new kw ( inline = 1 )","char in 48 to 57","input . reset ( )"]{for stop in[1,4,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450),"{source}");assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));}
 }

 #[test]fn actual_original_call_member_chain_root_mutations_keep_bounded_fields_and_roles(){
  for(source,wanted)in[("target ( ) . particles . datum_flags |= ( 1 << 0 )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("factory ( value ) . child . field = value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("factory ( value ) . child . field ++",Some(OriginalSimpleKind::PostIncrementStatement)),("factory ( value ) . child . field [ key ] = other",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("consume ( factory ( value ) . child . field = value )",None),("consume ( factory ( value ) . child . field [ key ] = other )",None),("consume ( factory ( value ) . child . field ++ )",None),("factory ( value ) ?. child . field = value",None),("factory ( value ) : child . field = value",None),("owner . factory ( value ) . child . field = value",Some(OriginalSimpleKind::SimpleAssignmentStatement))]{expanded_expect(source,wanted);}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed("factory ( value ) . child . field = other"),&a).unwrap();let ExprKind::Binary{lhs,..}=&out.parsed.expr.as_ref().unwrap().kind else{unreachable!()};let target_end=out.tokens.partition_point(|t|t.span.end<=lhs.span.end);assert!(original_call_result_member_root_write(lhs,&out.tokens[..target_end],32));assert!(!original_call_result_member_root_write(lhs,&out.tokens[..target_end],1));
  for at in 0..target_end{let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_call_result_member_root_write(lhs,&out.tokens[..target_end],32));out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_call_result_member_root_write(lhs,&out.tokens[..target_end],32));out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_call_result_member_root_write(lhs,&out.tokens[..target_end],32));out.tokens[at]=old;}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_call_member_chain_keeps_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let source="factory ( value ) . child . field = other";for stop in[1,5,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));
 }

 #[test]fn actual_original_multi_argument_call_keys_keep_root_compound_role(){
  for(source,wanted)in[("bad_paths [ copytext ( line , 1 , - 1 ) ] |= model_key",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("F [ choose ( a , b ) ] |= value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("F [ choose ( ) ] |= value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("consume ( F [ choose ( a , b ) ] |= value )",None),("F [ choose ( a , b ) ] ++",None),("F [ choose ( a , b ) ] |= value ( ) ( )",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_multi_argument_call_key_geometry_checks_each_occurrence(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let source="bad_paths [ copytext ( line , 1 , - 1 ) ] |= model_key";let mut out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let ExprKind::Binary{lhs,..}=&out.parsed.expr.as_ref().unwrap().kind else{panic!("root compound")};let ExprKind::Index{index,..}=&lhs.kind else{panic!("key")};let start=out.tokens.partition_point(|t|t.span.end<=index.span.start);let end=out.tokens.partition_point(|t|t.span.start<index.span.end);assert!(original_compound_call_key_geometry(index,&out.tokens[start..end],32));assert!(!original_compound_call_key_geometry(index,&out.tokens[start..end],0));let target_end=out.tokens.partition_point(|t|t.span.end<=lhs.span.end);assert!(original_complete_index_write_target(lhs,&out.tokens[..target_end],32));assert!(!original_complete_index_write_target(lhs,&out.tokens[..target_end],1));
  for at in start..end{let old=out.tokens[at].clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_compound_call_key_geometry(index,&out.tokens[start..end],32),"foreign {at}");assert!(!original_simple_assignment(out.parsed.expr.as_ref().unwrap(),&out.tokens,true),"rootforeign {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_compound_call_key_geometry(index,&out.tokens[start..end],32),"width {at}");out.tokens[at]=old.clone();if matches!(old.text.as_str(),"("|")"|","){out.tokens[at].kind=TokenKind::Unknown;assert!(!original_compound_call_key_geometry(index,&out.tokens[start..end],32),"kind {at}");}out.tokens[at]=old;assert!(original_compound_call_key_geometry(index,&out.tokens[start..end],32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_multi_argument_call_key_preserves_first_io_quota_and_recovery(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let source="bad_paths [ copytext ( line , 1 , - 1 ) ] |= model_key";for stop in[1,7,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::SimpleAssignmentStatement));
 }

 #[test]fn actual_original_register_read_followers_and_member_ranges_keep_consuming_roles(){
  for(source,wanted)in[("A . topic_href ( ) ?[ key ]",Some(OriginalSimpleKind::Complete)),("site ( ) . station_materialization . department_areas ?[ department ]",Some(OriginalSimpleKind::Complete)),("director ( ) ?. local_alert_levels ?[ department_id ] == 2",Some(OriginalSimpleKind::Complete)),("director ( ) ?. squads ?[ agent . squad_id ]",Some(OriginalSimpleKind::Complete)),("( get_step ( M , 0 ) ) ?. loc ?. type",Some(OriginalSimpleKind::Complete)),("guarded ( ( materializer ( ) ) . type , materializer ( ) )",Some(OriginalSimpleKind::Complete)),("( materializer ( ) ) . type ( )",Some(OriginalSimpleKind::Complete)),("! ( B . lane in 1 to 6 )",Some(OriginalSimpleKind::Complete)),("consume ( B . lane in 1 to 6 )",Some(OriginalSimpleKind::Complete)),("B ?. lane in 1 to 6",None),("B . lane in low to high",None),("B . lane to 6",None),("A . topic_href ( ) ?[ key ] = value",None),("A . topic_href ( ) ?[ key ] ++",None),("A . topic_href ( ) ?[ key ] ( )",None),("( get_step ( M , 0 ) ) : type",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_register_read_followers_and_ranges_require_each_new_occurrence(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["A . topic_href ( ) ?[ key ]","director ( ) ?. squads ?[ agent . squad_id ]","( get_step ( M , 0 ) ) ?. loc ?. type","B . lane in 1 to 6"]{
   let mut out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let root=out.parsed.expr.as_ref().unwrap();assert!(original_conditional_child(root,&out.tokens,true,32),"{source}");assert!(!original_conditional_child(root,&out.tokens,true,1),"depth {source}");
   for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_conditional_child(root,&out.tokens,true,32),"kind {source} {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_conditional_child(root,&out.tokens,true,32),"foreign {source} {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_conditional_child(root,&out.tokens,true,32),"width {source} {at}");out.tokens[at]=old;}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
 }
 #[test]fn actual_original_register_read_followers_keep_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize,failed:bool}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.pulls==self.stop{self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}self.feed.next_token()}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);self.feed.original_value(o)}fn original_close_colon(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{assert!(!self.failed);self.feed.original_close_colon(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for source in["director ( ) ?. orders ?[ order_id ]","( get_step ( M , 0 ) ) ?. loc ?. type","B . lane in 1 to 6"]{for stop in[1,5,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop,failed:false};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450),"{source} {stop}");assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);expanded_expect(source,Some(OriginalSimpleKind::Complete));}
 }

 #[test]fn actual_original_register_mutation_targets_keep_explicit_consuming_roles(){
  use OriginalSimpleKind::{SimpleAssignmentStatement as S,Complete as C};
  for(source,wanted)in[("( pda ( ) . id . last_job_switch = now ( ) )",Some(C)),("pda ( ) . scanmode ( ) . name = value",Some(S)),("notes ( ) . storednotes [ notes ( ) . currentnote ] = notes ( ) . note",Some(S)),("B . ownegg ( ) . egg_name = B . egg_name",Some(S)),(". [ \"target\" ] [ \"name\" ] = target ( ) . name",Some(S)),("required_atoms [ ( flag ? pick ( possible_types ) : null ) ] += randum",Some(S)),("target ( ) . filter_data [ asked . kept [ \"name\" ] ] [ \"icon\" ] = new_icon",Some(S)),("vessel . ship ( ) . engines_state = ! vessel . ship ( ) . engines_state",Some(S)),("consume ( ( pda ( ) . id . field = value ) )",Some(C)),("consume ( pda ( ) . id . field = value )",None),("pda ( ) ?. id . field = value",None),("pda ( ) : id . field = value",None),("notes ( ) . storednotes [ key ] ++",None)]{expanded_expect(source,wanted);}
 }
 #[test]fn actual_original_register_mutation_target_geometry_and_budget_are_current(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in["B . ownegg ( ) . egg_name = value","notes ( ) . storednotes [ notes ( ) . currentnote ] = value",". [ \"target\" ] [ \"name\" ] = value","required_atoms [ ( flag ? yes : no ) ] += value"]{
   let mut out=parse_original_expression_demanded(&mut expanded_feed(source),&a).unwrap();let root=out.parsed.expr.as_ref().unwrap();assert!(original_observed_mutation_root_assignment(root,&out.tokens,32),"{source}");assert!(!original_observed_mutation_root_assignment(root,&out.tokens,1));for at in 0..out.tokens.len(){let saved=out.tokens[at].clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_observed_mutation_root_assignment(root,&out.tokens,32),"foreign {source} {at}");out.tokens[at]=saved.clone();out.tokens[at].span.end+=1;assert!(!original_observed_mutation_root_assignment(root,&out.tokens,32),"width {source} {at}");out.tokens[at]=saved;assert!(original_observed_mutation_root_assignment(root,&out.tokens,32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
 }
 #[test]fn actual_original_register_grouped_mask_and_method_assignments_keep_value_context(){
  for source in["( GLOB . admin_states [ ( 1 << 1 ) | ( 1 << 14 ) | ( 1 << 5 ) ] ||= new / datum / state ( ( 1 << 1 ) | ( 1 << 14 ) | ( 1 << 5 ) ) )","( pda ( ) . id . field = flag ? own_clock ( ) : world . time )"]{expanded_expect(source,Some(OriginalSimpleKind::Complete));}
  expanded_expect("( target ( ) ?. field = value )",None);
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=parse_original_expression_demanded(&mut expanded_feed("( GLOB . admin_states [ ( 1 << 1 ) | ( 1 << 5 ) ] ||= value )"),&a).unwrap();let root=out.parsed.expr.as_ref().unwrap();assert!(original_conditional_child(root,&out.tokens,true,32));assert!(!original_conditional_child(root,&out.tokens,true,1));for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_conditional_child(root,&out.tokens,true,32),"maskforeign {at}");out.tokens[at]=old;}drop(out);
 }
 #[test]fn actual_original_register_mutation_targets_preserve_first_io_quota_and_retry(){
  struct Stop{feed:ExpandedFeed,pulls:usize,stop:usize}impl NativeExpressionTokenDemand for Stop{fn next_token(&mut self)->std::io::Result<Option<Token>>{self.pulls+=1;if self.pulls==self.stop{Err(std::io::Error::from_raw_os_error(1450))}else{self.feed.next_token()}}fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.feed.original_value(o)}fn requires_original_values(&self)->bool{true}}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for source in["B . ownegg ( ) . egg_name = value",". [ \"target\" ] [ \"name\" ] = value","( GLOB . states [ ( 1 << 1 ) | ( 1 << 2 ) ] ||= value )"]{for stop in[1,5,source.split_whitespace().count()+1]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut feed=Stop{feed:expanded_feed(source),pulls:0,stop};assert_eq!(parse_original_expression_demanded(&mut feed,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(feed.pulls,stop);assert_eq!(used.load(Ordering::Acquire),fixed);}let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(parse_original_expression_demanded(&mut expanded_feed(source),&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);}
 }

 // Funded typed template fragments are supplied as DATA to the actual parser;
 // this fixture grants no Source/Header/CurrentModel authority.

 // Same actual typed template DATA, never a Source/Header/Current grant.
 fn literal_argument_fixture(follower:&str,a:&crate::SettingAdmission<'_>,stop:Option<usize>)->std::io::Result<DemandedExpression>{
  struct Input{source:String,tokens:Vec<Token>,data:Vec<Option<crate::OriginalLiteralData>>,at:usize,pulls:usize,stop:Option<usize>,failed:bool}
  impl NativeExpressionTokenDemand for Input{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.stop==Some(self.pulls){self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}let t=self.tokens.get(self.at).cloned();self.at+=usize::from(t.is_some());Ok(t)}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}if let Some(d)=self.data[o.ordinal()].as_ref(){return Ok(Some(d.value()))}Ok(Some(if t.kind==TokenKind::Ident{crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false}}else{crate::OriginalTokenValue::Punct(match t.text.as_str(){"("=>"(",")"=>")","."=>".","+"=>"+",_=>return Err(std::io::ErrorKind::InvalidInput.into())})}))}
   fn original_literal_data(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalLiteralRef<'_>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(self.data[o.ordinal()].as_ref().map(crate::OriginalLiteralData::as_view))}
   fn original_template_source(&self,span:Span)->std::io::Result<Option<&str>>{assert!(!self.failed);Ok(self.source.get(span.range()))}
   fn requires_original_values(&self)->bool{true}
  }
  let mut rows=vec![(TokenKind::Ident,"consume",None),(TokenKind::Punctuation,"(",None),(TokenKind::Interpolation,"\"outer[",Some(crate::OriginalTokenValue::InterpBegin("outer"))),(TokenKind::Ident,"inside",None),(TokenKind::Punctuation,"(",None),(TokenKind::Interpolation,"\"inner[",Some(crate::OriginalTokenValue::InterpBegin("inner"))),(TokenKind::Ident,"x",None),(TokenKind::Interpolation,"]\"",Some(crate::OriginalTokenValue::InterpEnd(""))),(TokenKind::Punctuation,")",None),(TokenKind::Interpolation,"]\"",Some(crate::OriginalTokenValue::InterpEnd("")))];
  match follower{"finish"=>(),"member"=>rows.extend([(TokenKind::Punctuation,".",None),(TokenKind::Ident,"field",None)]),"call"=>rows.extend([(TokenKind::Punctuation,"(",None),(TokenKind::Ident,"arg",None),(TokenKind::Punctuation,")",None)]),"binary"=>rows.extend([(TokenKind::Operator,"+",None),(TokenKind::Ident,"other",None)]),"missing_close"=>(),"deep_call"=>{rows.push((TokenKind::Punctuation,"(",None));for _ in 0..40{rows.extend([(TokenKind::Ident,"f",None),(TokenKind::Punctuation,"(",None)]);}rows.push((TokenKind::Ident,"arg",None));for _ in 0..40{rows.push((TokenKind::Punctuation,")",None));}rows.push((TokenKind::Punctuation,")",None));},_=>panic!("fixture role")}
  if follower!="missing_close"{rows.push((TokenKind::Punctuation,")",None));}
  let(mut source,mut tokens,mut data)=(String::new(),Vec::new(),Vec::new());
  for(kind,text,value)in rows{let at=source.len();source.push_str(text);tokens.push(Token{kind,span:Span::new(at,source.len()),text:text.into()});data.push(value.map(|v|crate::OriginalLiteralData::from_value_with_mode_using(text.into(),v,crate::OriginalStringMode::Normal,a)).transpose()?);}
  let mut input=Input{source,tokens,data,at:0,pulls:0,stop,failed:false};let result=parse_original_expression_demanded(&mut input,a);if let Some(stop)=stop{assert_eq!(input.pulls,stop);}result
 }
 #[test]fn actual_original_literal_arguments_keep_nested_template_owners_and_aliases(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));
  let out=literal_argument_fixture("finish",&a,None).unwrap();assert!(out.parsed().diagnostics.is_empty());
  let ExprKind::Call{args,..}=&out.parsed().expr.as_ref().unwrap().kind else{panic!("outercall")};let ExprKind::Literal(value)=&args[0].kind else{panic!("paidliteral")};
  let parts=value.original_prepared_body_parts(args[0].span).unwrap();assert_eq!(parts.expressions.len(),1);let ExprKind::Call{args:inner,..}=&parts.expressions[0].kind else{panic!("sameembeddedcall")};let ExprKind::Literal(child)=&inner[0].kind else{panic!("sameinnerliteral")};let child_parts=child.original_prepared_body_parts(inner[0].span).unwrap();assert!(matches!(&child_parts.expressions[0].kind,ExprKind::Ident(name)if name=="x"));
  let alias=value.clone();drop(out);assert!(used.load(Ordering::Acquire)>fixed);drop(alias);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_literal_argument_followers_keep_existing_expression_roles(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));
  for follower in["member","call","binary"]{let out=literal_argument_fixture(follower,&a,None).unwrap();assert!(out.parsed().diagnostics.is_empty(),"{follower}: {:?}",out.parsed().diagnostics);let ExprKind::Call{args,..}=&out.parsed().expr.as_ref().unwrap().kind else{panic!("outercall")};assert!(match follower{"member"=>matches!(&args[0].kind,ExprKind::Member{selector,..}if selector=="field"),"call"=>matches!(&args[0].kind,ExprKind::Call{args,..}if args.len()==1),"binary"=>matches!(&args[0].kind,ExprKind::Binary{op,..}if op=="+"),_=>false});drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);}
  let low=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));let error=literal_argument_fixture("deep_call",&low,None).err().unwrap();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert!(error.to_string().contains("stack-work"));assert_eq!(used.load(Ordering::Acquire),fixed);
  let out=literal_argument_fixture("missing_close",&a,None).unwrap();assert!(!out.parsed().diagnostics.is_empty());drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  assert!(parse_expression("consume(\"native\".field)").diagnostics.is_empty());
 }
 #[test]fn actual_original_literal_arguments_keep_first_io_quota_and_same_input_retry(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();
  for stop in[1,6,12]{let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));assert_eq!(literal_argument_fixture("finish",&a,Some(stop)).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),fixed);}
  let a=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(literal_argument_fixture("finish",&a,None).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);
  let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Err(std::io::Error::new(std::io::ErrorKind::Interrupted,"actual canceled literal input")));assert_eq!(literal_argument_fixture("finish",&a,None).err().unwrap().kind(),std::io::ErrorKind::Interrupted);assert_eq!(used.load(Ordering::Acquire),fixed);
  let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));drop(literal_argument_fixture("finish",&a,None).unwrap());assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 // Typed Original token/value fixture only; no Source/Header/Current grant.
 fn prepared_index_add_fixture(shape:&str,operator:&str,a:&crate::SettingAdmission<'_>,stop:Option<(usize,i32)>)->std::io::Result<DemandedExpression>{
  struct Input{source:String,tokens:Vec<Token>,data:Vec<Option<crate::OriginalLiteralData>>,at:usize,pulls:usize,stop:Option<(usize,i32)>,failed:bool}
  impl NativeExpressionTokenDemand for Input{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if let Some((at,raw))=self.stop{if self.pulls==at{self.failed=true;return Err(std::io::Error::from_raw_os_error(raw))}}let token=self.tokens.get(self.at).cloned();self.at+=usize::from(token.is_some());Ok(token)}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}if let Some(data)=&self.data[o.ordinal()]{return Ok(Some(data.value()))}Ok(Some(match t.kind{TokenKind::Ident=>crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false},TokenKind::Number if t.text=="1"=>crate::OriginalTokenValue::Int(1),_=>{let at=crate::original_scalar_transport::original_punctuation_storage_index(&t.text).ok_or(std::io::ErrorKind::InvalidInput)?;crate::OriginalTokenValue::Punct(crate::original_scalar_transport::original_punctuation_storage_value(at).ok_or(std::io::ErrorKind::InvalidInput)?)}}))}
   fn original_literal_data(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalLiteralRef<'_>>>{assert!(!self.failed);let token=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if token.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(self.data[o.ordinal()].as_ref().map(crate::OriginalLiteralData::as_view))}
   fn original_template_source(&self,span:Span)->std::io::Result<Option<&str>>{assert!(!self.failed);Ok(self.source.get(span.range()))}
   fn requires_original_values(&self)->bool{true}
  }
  let mut rows=Vec::new();match shape{"root"=>(),"call"=>rows.extend([(TokenKind::Ident,"consume",None),(TokenKind::Punctuation,"(",None)]),"group"=>rows.push((TokenKind::Punctuation,"(",None)),"outer"=>rows.extend([(TokenKind::Ident,"outer",None),(TokenKind::Operator,"=",None)]),_=>panic!("fixture shape")}
  rows.extend([(TokenKind::Ident,"GLOB",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"churn_census",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"signals",None),(TokenKind::Punctuation,"[",None),(TokenKind::Interpolation,"\"[",Some(crate::OriginalTokenValue::InterpBegin(""))),(TokenKind::Ident,"frequency",None),(TokenKind::Interpolation,"] [",Some(crate::OriginalTokenValue::InterpPart(" "))),(TokenKind::Ident,"source",None),(TokenKind::Punctuation,"?.",None),(TokenKind::Ident,"type",None),(TokenKind::Interpolation,"]\"",Some(crate::OriginalTokenValue::InterpEnd(""))),(TokenKind::Punctuation,"]",None),(TokenKind::Operator,operator,None),(TokenKind::Number,"1",None)]);
  if matches!(shape,"call"|"group"){rows.push((TokenKind::Punctuation,")",None));}
  let(mut source,mut tokens,mut data)=(String::new(),Vec::new(),Vec::new());for(kind,text,value)in rows{let at=source.len();source.push_str(text);tokens.push(Token{kind,span:Span::new(at,source.len()),text:text.into()});data.push(value.map(|value|crate::OriginalLiteralData::from_value_with_mode_using(text.into(),value,crate::OriginalStringMode::Normal,a)).transpose()?);}
  let mut input=Input{source,tokens,data,at:0,pulls:0,stop,failed:false};let result=parse_original_expression_demanded(&mut input,a);if let Some((at,_))=stop{assert_eq!(input.pulls,at,"supplier stops at first real failure");}result
 }
 #[test]fn actual_original_complete_index_root_add_keeps_existing_key_value_roster(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for source in ["GLOB . churn_census . draws [ D . type ] += 1","GLOB . churn_census . draws [ key ] += 1","GLOB . churn_census . draws [ 1 ] += 1","GLOB . churn_census . draws [ \"fixed\" ] += 1","GLOB . churn_census . draws [ rows [ key ] ] += 1","table [ key ] += 1","table [ key ++ ] += 1","table [ D :: type ] += 1"] {
   let mut feed=expanded_feed(source);let out=parse_original_expression_demanded(&mut feed,&a).unwrap();assert!(out.parsed().diagnostics.is_empty(),"{source}");let receipt=out.parsed().original_simple_expression.expect("actual complete indexed root write");assert_eq!(receipt.kind(),OriginalSimpleKind::SimpleAssignmentStatement);assert!(!receipt.is_read_value()&&!receipt.is_initializer_assignment());
   let expr=out.parsed.expr.as_ref().unwrap();let ExprKind::Binary{lhs,..}=&expr.kind else{panic!("assignment")};let end=out.tokens.partition_point(|t|t.span.end<=lhs.span.end);assert!(original_complete_index_write_target(lhs,&out.tokens[..end],31));assert!(original_complete_index_root_add_assignment(expr,&out.tokens,32));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
  for source in ["GLOB ?. churn_census . draws [ D . type ] += 1","factory ( ) . draws [ D . type ] += 1","consume ( GLOB . churn_census . draws [ D . type ] += 1 )","( GLOB . churn_census . draws [ D . type ] += 1 )","outer = GLOB . churn_census . draws [ D . type ] += 1","GLOB . churn_census . draws [ key += value ] += 1"] {
   let mut feed=expanded_feed(source);let out=parse_original_expression_demanded(&mut feed,&a).unwrap();assert!(out.parsed().diagnostics.is_empty(),"{source}: {:?}",out.parsed().diagnostics);assert!(!original_complete_index_root_add_assignment(out.parsed().expr.as_ref().unwrap(),&out.tokens,32),"new helper closed: {source}");drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
 }
 #[test]fn actual_original_prepared_template_index_add_reuses_complete_key_without_value_role(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let out=prepared_index_add_fixture("root","+=",&a,None).unwrap();assert!(out.parsed().diagnostics.is_empty());let receipt=out.parsed().original_simple_expression.unwrap();assert_eq!(receipt.kind(),OriginalSimpleKind::SimpleAssignmentStatement);assert!(!receipt.is_read_value()&&!receipt.is_initializer_assignment());
  let expr=out.parsed.expr.as_ref().unwrap();let ExprKind::Binary{lhs,..}=&expr.kind else{panic!("actual assignment")};let ExprKind::Index{object,index}=&lhs.kind else{panic!("actual indexed target")};let end=out.tokens.partition_point(|t|t.span.end<=lhs.span.end);let target=&out.tokens[..end];
  assert!(!original_plain_index(lhs,object,index,target,32),"old receiver roster rejects two plain member links");assert!(original_complete_index_write_target(lhs,target,32),"same existing bounded key proof already owns both children");assert!(original_complete_index_root_add_assignment(expr,&out.tokens,32));
  let ExprKind::Literal(value)=&index.kind else{panic!("actual retained typed template")};let parts=value.original_prepared_body_parts(index.span).unwrap();assert_eq!(parts.expressions.len(),2);assert!(matches!(&parts.expressions[1].kind,ExprKind::SafeMember{selector,via_colon:false,..}if selector=="type"));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  for shape in["call","group","outer"]{let out=prepared_index_add_fixture(shape,"+=",&a,None).unwrap();assert!(out.parsed().original_simple_expression.is_none(),"new root write cannot enter {shape} value role");drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);}
  for op in["-=","=","||="]{let out=prepared_index_add_fixture("root",op,&a,None).unwrap();assert!(!original_complete_index_root_add_assignment(out.parsed.expr.as_ref().unwrap(),&out.tokens,32),"new helper is += only");drop(out);}
  assert!(parse_expression("GLOB.churn_census.signals[\"[frequency] [source?.type]\"]+=1").original_simple_expression.is_none());assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_prepared_template_index_add_requires_every_current_occurrence(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=prepared_index_add_fixture("root","+=",&a,None).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(!original_complete_index_root_add_assignment(expr,&out.tokens,1));
  for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_complete_index_root_add_assignment(expr,&out.tokens,32),"kind {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_complete_index_root_add_assignment(expr,&out.tokens,32),"foreign {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_complete_index_root_add_assignment(expr,&out.tokens,32),"width {at}");out.tokens[at]=old;assert!(original_complete_index_root_add_assignment(expr,&out.tokens,32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_prepared_template_index_add_keeps_first_io_quota_and_retry(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let good=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let baseline=prepared_index_add_fixture("root","+=",&good,None).unwrap();let eof=baseline.tokens.len()+1;drop(baseline);assert_eq!(used.load(Ordering::Acquire),fixed);
  for raw in[1450,995]{for at in[1,10,eof]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let error=prepared_index_add_fixture("root","+=",&a,Some((at,raw))).err().expect("actual supplier failure");assert_eq!(a.take_operational_error().unwrap_or(error).raw_os_error(),Some(raw));drop(a);assert_eq!(used.load(Ordering::Acquire),fixed);}}
  let low=crate::SettingAdmission::new(&used,fixed,&||Ok(()));let error=prepared_index_add_fixture("root","+=",&low,None).err().expect("actual low quota failure");assert_eq!(low.take_operational_error().unwrap_or(error).kind(),std::io::ErrorKind::OutOfMemory);drop(low);assert_eq!(used.load(Ordering::Acquire),fixed);
  let out=prepared_index_add_fixture("root","+=",&good,None).unwrap();assert_eq!(out.parsed().original_simple_expression.unwrap().kind(),OriginalSimpleKind::SimpleAssignmentStatement);drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }

 fn member_logical_template_fixture(operator:&str,a:&crate::SettingAdmission<'_>,stop:Option<usize>)->std::io::Result<DemandedExpression>{
  struct Input{source:String,tokens:Vec<Token>,data:Vec<Option<crate::OriginalLiteralData>>,at:usize,pulls:usize,stop:Option<usize>,failed:bool}
  impl NativeExpressionTokenDemand for Input{
   fn next_token(&mut self)->std::io::Result<Option<Token>>{assert!(!self.failed);self.pulls+=1;if self.stop==Some(self.pulls){self.failed=true;return Err(std::io::Error::from_raw_os_error(1450))}let t=self.tokens.get(self.at).cloned();self.at+=usize::from(t.is_some());Ok(t)}
   fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}if let Some(d)=self.data[o.ordinal()].as_ref(){return Ok(Some(d.value()))}Ok(Some(if t.kind==TokenKind::Ident{crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false}}else{let at=crate::original_scalar_transport::original_punctuation_storage_index(&t.text).ok_or(std::io::ErrorKind::InvalidInput)?;crate::OriginalTokenValue::Punct(crate::original_scalar_transport::original_punctuation_storage_value(at).ok_or(std::io::ErrorKind::InvalidInput)?)}))}
   fn original_literal_data(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalLiteralRef<'_>>>{assert!(!self.failed);let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}Ok(self.data[o.ordinal()].as_ref().map(crate::OriginalLiteralData::as_view))}
   fn original_template_source(&self,span:Span)->std::io::Result<Option<&str>>{assert!(!self.failed);Ok(self.source.get(span.range()))}fn requires_original_values(&self)->bool{true}
  }
  let(mut source,mut tokens,mut data)=(String::new(),Vec::new(),Vec::new());
  for(kind,text,value)in[(TokenKind::Ident,"W",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"name",None),(TokenKind::Operator,operator,None),(TokenKind::Interpolation,"\"[",Some(crate::OriginalTokenValue::InterpBegin(""))),(TokenKind::Ident,"W",None),(TokenKind::Punctuation,".",None),(TokenKind::Ident,"handler",None),(TokenKind::Interpolation,"]\"",Some(crate::OriginalTokenValue::InterpEnd("")))]{
   let at=source.len();source.push_str(text);tokens.push(Token{kind,span:Span::new(at,source.len()),text:text.into()});data.push(value.map(|v|crate::OriginalLiteralData::from_value_with_mode_using(text.into(),v,crate::OriginalStringMode::Normal,a)).transpose()?);
  }
  let mut feed=Input{source,tokens,data,at:0,pulls:0,stop,failed:false};let result=parse_original_expression_demanded(&mut feed,a);if let Some(stop)=stop{assert_eq!(feed.pulls,stop);}result
 }
 #[test]fn actual_original_plain_member_logical_assignment_is_only_a_root_write(){
  for(source,wanted)in[("owner . field ||= lookup ( )",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("owner . state . field &&= value",Some(OriginalSimpleKind::SimpleAssignmentStatement)),("consume ( owner . field ||= value )",None),("( owner . field ||= value )",None),("outer = owner . field ||= value",None),("owner ?. field ||= value",None),("owner : field ||= value",None),("factory ( ) . field ||= value",None)]{expanded_expect(source,wanted);}
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for operator in["||=","&&="]{let out=member_logical_template_fixture(operator,&a,None).unwrap();let receipt=out.parsed().original_simple_expression.unwrap();assert_eq!(receipt.kind(),OriginalSimpleKind::SimpleAssignmentStatement);assert!(!receipt.is_read_value());assert!(!receipt.is_initializer_assignment());assert!(out.parsed().diagnostics.is_empty());let ExprKind::Binary{rhs,..}=&out.parsed.expr.as_ref().unwrap().kind else{panic!("actual logical write")};let ExprKind::Literal(value)=&rhs.kind else{panic!("actual template")};let parts=value.original_prepared_body_parts(rhs.span).unwrap();assert_eq!(parts.expressions.len(),1);assert_eq!(parts.fragments.len(),2);assert!(matches!(&parts.expressions[0].kind,ExprKind::Member{selector,via_colon:false,..}if selector=="handler"));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);}
  assert!(parse_expression("owner.field||=value").original_simple_expression.is_none());
 }
 #[test]fn actual_original_plain_member_logical_assignment_keeps_exact_geometry_and_depth(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut out=member_logical_template_fixture("||=",&a,None).unwrap();let expr=out.parsed.expr.as_ref().unwrap();assert!(original_plain_member_logical_root_assignment(expr,&out.tokens,32));assert!(!original_plain_member_logical_root_assignment(expr,&out.tokens,1));{let saved=out.tokens[6].clone();out.tokens[6].span.start+=1000;out.tokens[6].span.end+=1000;let ExprKind::Binary{rhs,..}=&expr.kind else{unreachable!()};assert!(!original_mutation_run_geometry(rhs,&out.tokens[4..]));assert!(!original_plain_member_logical_root_assignment(expr,&out.tokens,32));out.tokens[6]=saved;}for at in 0..out.tokens.len(){let old=out.tokens[at].clone();out.tokens[at].kind=TokenKind::Unknown;assert!(!original_plain_member_logical_root_assignment(expr,&out.tokens,32),"kind {at}");out.tokens[at]=old.clone();out.tokens[at].span.start+=1000;out.tokens[at].span.end+=1000;assert!(!original_plain_member_logical_root_assignment(expr,&out.tokens,32),"foreign {at}");out.tokens[at]=old.clone();out.tokens[at].span.end+=1;assert!(!original_plain_member_logical_root_assignment(expr,&out.tokens,32),"width {at}");out.tokens[at]=old;assert!(original_plain_member_logical_root_assignment(expr,&out.tokens,32));}drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_original_plain_member_logical_assignment_preserves_first_io_quota_and_recovery(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();for stop in[1,5,10]{let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));assert_eq!(member_logical_template_fixture("||=",&a,Some(stop)).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),fixed);}let denied=crate::SettingAdmission::new(&used,fixed,&||Ok(()));assert_eq!(member_logical_template_fixture("||=",&denied,None).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),fixed);let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));drop(member_logical_template_fixture("||=",&a,None).unwrap());assert_eq!(used.load(Ordering::Acquire),fixed);
 }

}

#[cfg(test)]mod original_empty_group_event_controls{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn same_native_empty_group_issues_null_and_one_actual_closing_warning(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut tokens=crate::lex("()) BAD").tokens.into_iter();let mut source=||{let next=tokens.next();assert!(next.as_ref().is_none_or(|token|token.text!="BAD"));Ok(next)};let mut clauses=crate::ParameterClauseCursor::new(0);let mut source=crate::ParameterExpressionDemand::new(&mut source,&mut clauses).original();let root=crate::parse_original_expression_demanded(&mut source,&a).unwrap();assert!(root.parsed().diagnostics.is_empty());assert!(matches!(&root.parsed().expr.as_ref().unwrap().kind,ExprKind::Literal(value)if value.as_str()=="null"));let events=root.parsed().original_input_notices().unwrap().as_slice();assert_eq!(events.len(),1);assert_eq!(events[0].kind(),crate::OriginalInputNoticeKind::EmptyParentheses);assert_eq!(events[0].span(),Span::new(1,2));assert_eq!(source.take_boundary().unwrap().span,Span::new(2,3));drop(root);drop(source);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
}

#[cfg(test)]mod original_icon_named_string_key_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]fn original_icon_string_key_requires_actual_literal_and_argument_roles(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  for(source,expected)in[
   ("icon('icons/effects/effects.dmi',\"icon_state\"=\"nothing\")",true),
   ("list(\"key\"=value)",true),("icon(\"key\"=value)",true),
   ("consume(\"key\"=value)",false),("owner.icon(\"key\"=value)",false),
   ("icon((\"key\")=value)",false),("icon(\"key\"+=value)",false),
   ("icon(\"key\"=value=other)",false),
  ]{
   let output=simple_original_literal_fixture(source,&a).unwrap_or_else(|e|panic!("{source}: {e}"));
   let parsed=output.parsed();
   assert_eq!(parsed.original_simple_expression.is_some_and(|proof|proof.kind()==OriginalSimpleKind::Complete),expected,"{source}: {:?}",parsed.diagnostics);
   if expected{
    assert!(parsed.diagnostics.is_empty(),"{source}");
    let mut root=parsed.expr.clone().unwrap();let span=root.span;
    let materialized=crate::lex(source).tokens;
    assert!(original_composed_expression(&root,&materialized,true,32,true),"same authentic root/tokens");
    root.span.end+=1;
    assert!(!original_composed_expression(&root,&materialized,true,32,true),"changed whole-call span");root.span=span;
    assert!(original_composed_expression(&root,&materialized,true,32,true),"restored authentic root/tokens");
   }
   drop(output);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
}

// Unit-test final-value input for unescaped scalar fixtures. This drives the
// real demanded parser; it grants no source/header/model/body authority.
#[cfg(test)]
pub(crate) fn simple_original_literal_fixture(source:&str,a:&crate::SettingAdmission<'_>)->std::io::Result<DemandedExpression>{
 struct Feed{tokens:Vec<Token>,at:usize}
 impl NativeExpressionTokenDemand for Feed{
  fn next_token(&mut self)->std::io::Result<Option<Token>>{let next=self.tokens.get(self.at).cloned();self.at+=usize::from(next.is_some());Ok(next)}
  fn original_value(&self,o:NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{
   let t=self.tokens.get(o.ordinal()).ok_or(std::io::ErrorKind::InvalidInput)?;if t.span!=o.span(){return Err(std::io::ErrorKind::InvalidInput.into())}
   Ok(Some(match t.kind{
    TokenKind::Ident=>crate::OriginalTokenValue::Ident{spelling:&t.text,whitespace:false},
    TokenKind::Number=>crate::OriginalTokenValue::Int(t.text.parse().map_err(|_|std::io::ErrorKind::InvalidInput)?),
    TokenKind::String|TokenKind::Resource=>{
     let raw=&t.text;if raw.len()<2||raw[1..raw.len()-1].contains('\\'){return Err(std::io::ErrorKind::InvalidInput.into())}
     if t.kind==TokenKind::String{crate::OriginalTokenValue::String(&raw[1..raw.len()-1])}else{crate::OriginalTokenValue::Resource(&raw[1..raw.len()-1])}
    },
    _=>{let index=crate::original_scalar_transport::original_punctuation_storage_index(&t.text).ok_or(std::io::ErrorKind::InvalidInput)?;
     crate::OriginalTokenValue::Punct(crate::original_scalar_transport::original_punctuation_storage_value(index).ok_or(std::io::ErrorKind::InvalidInput)?)},
   }))
  }
  fn requires_original_values(&self)->bool{true}
 }
 let lexical=crate::lex(source);if !lexical.diagnostics.is_empty(){return Err(std::io::ErrorKind::InvalidInput.into())}
 let mut raw=lexical.tokens.into_iter().filter(|t|!matches!(t.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment)).peekable();
 let mut tokens=Vec::new();
 while let Some(mut token)=raw.next(){
  // This test fixture emits the final producer's declared LShift/RShift
  // VALUE occurrence. The compatibility lexer splits these raw bytes; passing
  // those two raw tokens as final values must NOT acquire the same receipt.
  if matches!(token.text.as_str(),"<"|">")&&raw.peek().is_some_and(|next|next.text==token.text&&token.span.end==next.span.start){
   let next=raw.next().unwrap();token.span.end=next.span.end;token.text.push_str(&next.text);
   token.kind=crate::original_scalar_transport::original_punctuation_native_kind(&token.text);
  }
  tokens.push(token);
 }
 parse_original_expression_demanded(&mut Feed{tokens,at:0},a)
}

/// Canonical cursor/recovery DATA from the SAME actual expression parser;
/// independently supplied DATA cannot grant BODY/current-source authority.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct NativeExpressionParserFacts{
 complete:Option<Span>,aggregate_complete:bool,exhausted:bool,recovered:bool,deferred:bool,
}
impl NativeExpressionParserFacts{
 pub fn is_complete(self)->bool{self.complete.is_some()||self.aggregate_complete}
 pub fn complete_span(self)->Option<Span>{self.complete}
 pub fn exhausted(self)->bool{self.exhausted}
 pub fn recovered(self)->bool{self.recovered}
 pub fn deferred(self)->bool{self.deferred}
 /// Classification on an existing private child owner, never invented geometry.
 pub(crate) fn aggregate(complete:bool,recovered:bool,deferred:bool)->Self{
  Self{complete:None,aggregate_complete:complete&&!recovered&&!deferred,exhausted:false,recovered,deferred}
 }
}
/// One-byte retained classification. Positions are validated at private
/// adoption, then read from that SAME immutable root instead of duplicated.
#[repr(transparent)]
#[derive(Clone,Copy,Debug,Default,Eq,PartialEq)]
pub(crate) struct NativeExpressionParserState(u8);
impl NativeExpressionParserState{
 pub(crate) fn with_original_value(mut self,complete:bool)->Self{if complete{self.0|=64}else{self.0&=!64}self}
 pub(crate) fn original_value_complete(self)->bool{self.0&64!=0}
 pub(crate) fn for_root(facts:Option<NativeExpressionParserFacts>,span:Span)->Self{
  let Some(facts)=facts else{return Self(0)};
  if facts.is_complete()&&facts.complete_span()!=Some(span){return Self(0)}
  Self::encode(facts)
 }
 pub(crate) fn aggregate(facts:Option<NativeExpressionParserFacts>)->Self{
  let Some(facts)=facts else{return Self(0)};
  if facts.complete_span().is_some(){return Self(0)}
  Self::encode(facts)
 }
 fn encode(facts:NativeExpressionParserFacts)->Self{
  let mut bits=1;
  if facts.complete.is_some(){bits|=2}if facts.aggregate_complete{bits|=4}
  if facts.exhausted{bits|=8}if facts.recovered{bits|=16}if facts.deferred{bits|=32}
  Self(bits)
 }
 pub(crate) fn facts(self,span:Option<Span>)->Option<NativeExpressionParserFacts>{
  if self.0&1==0{return None}
  let complete=if self.0&2!=0{Some(span?)}else{None};
  Some(NativeExpressionParserFacts{complete,aggregate_complete:self.0&4!=0,
   exhausted:self.0&8!=0,recovered:self.0&16!=0,deferred:self.0&32!=0})
 }
}
const _:()=assert!(std::mem::size_of::<NativeExpressionParserState>()==1);
/// Native-only consumption report on an authenticated native token view.
/// Without actual Original facts this uses the native grammar profile; it
/// cannot mint an Original receipt. Caller still binds the actual source owner.
pub fn parse_expression_token_view_with_native_facts(
 source:&str,tokens:&[SpanToken],source_origin:usize,a:&crate::SettingAdmission<'_>,
 facts:Option<crate::OriginalLiteralFactsView<'_>>,
)->(ParsedExpr,Option<NativeExpressionParserFacts>){
 let original=facts.is_some();let mut native=None;
 let parsed=parse_span_tokens_profile_native(source,tokens,0,source_origin,a,facts,original,&mut|facts|native=Some(facts));
 (parsed,native)
}
/// Same admitted original-token parser, with a separate production report.
/// No mutable ParsedExpr marker, second parser or source/code authority.
pub fn parse_expression_original_token_view_with_native_facts(
 source:&str,tokens:&[SpanToken],source_origin:usize,a:&crate::SettingAdmission<'_>,
 facts:Option<crate::OriginalLiteralFactsView<'_>>,
)->(ParsedExpr,Option<NativeExpressionParserFacts>){
 let mut native=None;
 let parsed=parse_span_tokens_profile_native(source,tokens,0,source_origin,a,facts,true,&mut |facts|native=Some(facts));
 (parsed,native)
}

#[cfg(test)]
mod native_expression_consumption_controls{
 use super::*;
 #[test]fn native_expression_facts_record_real_exhaustion_recovery_and_no_public_marker(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,8<<20,&||Ok(()));
  for(source,complete)in[("value+1",true),("value+",false),("value extra",false)]{
   let lexed=crate::lex_spans(source);
   let(parsed,facts)=parse_expression_span_tokens_with_original_literals_and_native_facts(source,&lexed.tokens,0,&a,None);
   let facts=facts.expect("actual admitted parser report");
   assert_eq!(facts.is_complete(),complete,"{source}");
   if complete{assert_eq!(facts.complete_span(),parsed.expr.as_ref().map(|expr|expr.span));assert!(facts.exhausted());}
   else{assert!(facts.recovered()||facts.deferred()||!facts.exhausted());}
  }
 }
 #[test]fn native_expression_operational_failure_cannot_become_consumption(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let polls=std::cell::Cell::new(0);let checkpoint=||{polls.set(polls.get()+1);Err(std::io::Error::from_raw_os_error(1450))};
  let a=crate::SettingAdmission::new(&counter,8<<20,&checkpoint);let source="value+1";let tokens=crate::lex_spans(source);
  let(_,facts)=parse_expression_span_tokens_with_original_literals_and_native_facts(source,&tokens.tokens,0,&a,None);
  assert!(!facts.is_some_and(|facts|facts.is_complete()));
  let actual=a.take_operational_error().expect("first real operational failure");assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(polls.get(),1);
 }
}

#[cfg(test)]mod native_completed_owner_layout_controls{
 use super::*;
 struct PriorCompletedShape{root:Expr,tokens:Vec<Token>,lease:crate::SettingRootLease}
 #[test]fn native_completed_observation_does_not_grow_the_retained_product(){
  let old=std::mem::size_of::<PriorCompletedShape>();let new=std::mem::size_of::<CompletedDemandedExpression>();
  assert_eq!(new,old,"transient observation cannot enlarge retained completed roots");
  eprintln!("NATIVE_COMPLETED_OWNER_SIZE prior={old} current={new}");
 }
}

#[cfg(test)]mod optional_interpolation_entry_controls{
 use super::*;
 #[test]fn actual_optional_interpolation_entry_keeps_initial_io_latch_and_sticky_stop(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let polls=std::cell::Cell::new(0);let fail=||{polls.set(polls.get()+1);Err(std::io::Error::from_raw_os_error(1450))};let a=crate::SettingAdmission::new(&used,1<<20,&fail);
  assert!(parse_optional_interpolation_with_primary_tokens_and_native_facts("/* comment */",Some(&a)).is_err());let actual=a.take_operational_error().expect("same admission retains actual initial IO");assert_eq!(actual.raw_os_error(),Some(1450));assert!(a.is_stopped());assert!(parse_optional_interpolation_with_primary_tokens_and_native_facts("value",Some(&a)).is_err());assert_eq!(polls.get(),1);assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),fixed);
 }
 #[test]fn actual_optional_empty_interpolation_is_exhausted_without_a_required_root_grant(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  for source in ["", " ", "/* comment */", "/* ] inside comment */ "]{
   let(required,_,required_facts)=parse_expression_with_primary_tokens_and_native_facts(source,Some(&a)).unwrap();assert!(required.expr.is_none());assert!(!required_facts.unwrap().exhausted(),"required expression still needs a term");
   let(optional,tokens,native)=parse_optional_interpolation_with_primary_tokens_and_native_facts(source,Some(&a)).unwrap();let facts=native.unwrap();assert!(optional.expr.is_none()&&optional.diagnostics.is_empty());assert!(facts.exhausted()&&!facts.recovered()&&!facts.deferred());assert!(!facts.is_complete()&&facts.complete_span().is_none(),"optional absence is not a complete root");assert!(tokens.iter().all(|token|matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment)));
  }
  for source in ["value +", "@"]{let(_,_,native)=parse_optional_interpolation_with_primary_tokens_and_native_facts(source,Some(&a)).unwrap();let facts=native.unwrap();assert!(!facts.is_complete());assert!(facts.recovered()||facts.deferred()||!facts.exhausted(),"optional role cannot hide real failed/recovered input: {source}");}
  assert_eq!(used.load(std::sync::atomic::Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

// SAME existing Pratt operator DATA, shared with resource-only cleanup sizing.
        const EXPRESSION_BINARY_OPS: &[(&str, u8, u8)] = &[
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

fn expression_null_identifier(name:&str)->bool{name=="null"}
/// Only names whose actual prefix branch yields an immediate-drop Ident (or
/// path/selector DATA) can be removed from future cleanup coordination. Keep
/// contextual call/control names through the existing classifier, every real
/// infix identifier through the shared Pratt table, and all internal context
/// identifiers conservatively. This issues no expression/source authority.
pub(crate) fn cleanup_leaf_identifier(kind:TokenKind,name:&str)->bool{
 kind==TokenKind::Ident&&original_ordinary_call_name(name)
  &&!expression_null_identifier(name)&&!name.starts_with("__")
  &&!EXPRESSION_BINARY_OPS.iter().any(|(operator,_,_)|*operator==name)
}

#[cfg(test)]mod cleanup_identifier_geometry_controls{
 use super::*;
 #[test]fn actual_parser_leaf_identifier_classification_keeps_every_cleanup_production(){
  for name in["value","receiver","selector","user_name"]{
   assert!(cleanup_leaf_identifier(TokenKind::Ident,name));
   let parsed=parse_expression(name);assert!(parsed.diagnostics.is_empty());let expr=parsed.expr.unwrap();assert!(matches!(&expr.kind,ExprKind::Ident(_)));assert!(!crate::setting_drop::needs_drop_coordination(&expr));
  }
  for name in["new","null","as","in","to","input","locate","pick","return","__PROC__","__TYPE__","__IMPLIED_TYPE__"]{assert!(!cleanup_leaf_identifier(TokenKind::Ident,name),"contextual or operator token stays funded: {name}");}
  assert!(!cleanup_leaf_identifier(TokenKind::String,"value"));
  for(operator,_,_)in EXPRESSION_BINARY_OPS{if original_ascii_identifier(operator){assert!(!cleanup_leaf_identifier(TokenKind::Ident,operator));}}
 }
}

/// Resource DATA only. Number/null prefix productions are scalar in both
/// dialects. Static String/Resource tokens are scalar only under the genuine
/// Original typed-literal loan; interpolation remains a separate token kind.
pub(crate) fn cleanup_leaf_scalar_token(kind:TokenKind,name:&str,original_typed:bool)->bool{
 kind==TokenKind::Number || kind==TokenKind::Ident&&expression_null_identifier(name)
  || original_typed&&matches!(kind,TokenKind::String|TokenKind::Resource)
}

#[cfg(test)]mod scalar_group_continuation_tests{
 use super::*;
 use std::sync::atomic::Ordering;
 #[test]fn scalar_groups_keep_each_close_follow_and_outer_binding_power(){
  let parsed=parse_expression("((x)+y)(z)");assert!(parsed.diagnostics.is_empty());
  let root=parsed.expr.unwrap();assert_eq!(root.span,Span::new(0,10));
  let ExprKind::Call{callee,args}=root.kind else{panic!("outer call")};assert_eq!(args.len(),1);
  assert_eq!(callee.span,Span::new(0,7));let ExprKind::Group(sum)=callee.kind else{panic!("outer group")};
  let ExprKind::Binary{op,lhs,rhs}=sum.kind else{panic!("between-close binary")};assert_eq!(op,"+");
  assert!(matches!(lhs.kind,ExprKind::Group(_)));assert_eq!(lhs.span,Span::new(1,4));assert_eq!(rhs.span,Span::new(5,6));
  for source in ["a*((b)+c)","a?((b?c:d)):e","((x).field)","((f)(x))"]{
   let parsed=parse_expression(source);assert!(parsed.diagnostics.is_empty(),"{source}: {:?}",parsed.diagnostics);
   assert_eq!(parsed.expr.unwrap().span,Span::new(0,source.len()));
  }
  let broken=parse_expression("((x)");assert!(broken.diagnostics.iter().any(|d|d.kind==DiagnosticKind::IncompleteExpression && d.span==Span::new(0,1)));
  assert!(!parse_expression("()").diagnostics.is_empty());
 }
 #[test]fn scalar_groups_keep_default_cleanup_depth_refusal_and_exact_refund(){
  for count in [10usize,40] {
   let source=format!("{}x{}","(".repeat(count),")".repeat(count));let tokens=lex_spans(&source).tokens;
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=crate::SettingAdmission::new(&counter,128*1024*1024,&||Ok(()));
   let parsed=parse_expression_span_tokens_with_admission(&source,&tokens,0,&a);
   if count==10 {assert!(!a.is_stopped());assert!(parsed.diagnostics.is_empty());let mut value=parsed.expr.as_ref().unwrap();for _ in 0..count{let ExprKind::Group(child)=&value.kind else{panic!("group topology")};value=child;}assert!(matches!(&value.kind,ExprKind::Ident(name)if name=="x"));}
   else{assert!(a.is_stopped());assert!(a.take_operational_error().unwrap().to_string().contains("AST cleanup stack-work"));assert!(parsed.expr.is_none());}
   drop(parsed);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  let source=format!("{}x{}","f(".repeat(40),")".repeat(40));let tokens=lex_spans(&source).tokens;
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,128*1024*1024,&||Ok(()));
  let parsed=parse_expression_span_tokens_with_admission(&source,&tokens,0,&a);
  assert!(a.is_stopped());assert!(a.take_operational_error().unwrap().to_string().contains("stack-work"));
  drop(parsed);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn scalar_groups_preserve_real_first_io_cancel_and_retry(){
  use std::cell::Cell;
  let source="((x)+y)(z)";let tokens=lex_spans(source).tokens;
  for code in [1450,995] {for at in [0,tokens.len()+3,tokens.len()+8] {
   let calls=Cell::new(0);let poll=||{let n=calls.get();calls.set(n+1);if n==at{Err(std::io::Error::from_raw_os_error(code))}else{Ok(())}};
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=crate::SettingAdmission::new(&counter,128*1024*1024,&poll);let parsed=parse_expression_span_tokens_with_admission(source,&tokens,0,&a);
   assert!(a.is_stopped());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(code));drop(parsed);
   assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
   let retry=crate::SettingAdmission::new(&counter,128*1024*1024,&||Ok(()));let parsed=parse_expression_span_tokens_with_admission(source,&tokens,0,&retry);assert!(parsed.diagnostics.is_empty());assert!(!retry.is_stopped());drop(parsed);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }}
 }
}

#[cfg(test)]mod paid_pratt_driver_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]fn paid_pratt_driver_keeps_binding_power_right_association_and_failure_recovery(){
  let parsed=parse_expression("a + b * c ? d : e ? f : g");assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let ExprKind::Conditional{condition,else_value,..}=parsed.expr.unwrap().kind else{panic!("conditional")};
  let ExprKind::Binary{op,rhs,..}=&condition.kind else{panic!("conditionbinary")};assert_eq!(op,"+");assert!(matches!(&rhs.kind,ExprKind::Binary{op,..}if op=="*"));assert!(matches!(&else_value.kind,ExprKind::Conditional{..}));
  let parsed=parse_expression("a=b=c");assert!(parsed.diagnostics.is_empty());let ExprKind::Binary{op,rhs,..}=parsed.expr.unwrap().kind else{panic!("assignment")};assert_eq!(op,"=");assert!(matches!(&rhs.kind,ExprKind::Binary{op,..}if op=="="));
  for source in["a+)","a?b","x+(a?b)","a?(b+):c"]{let parsed=parse_expression(source);assert!(!parsed.diagnostics.is_empty(),"{source}");let root=parsed.expr.unwrap();assert_eq!(root.span.start,0);if source=="a+)"||source=="a?b"{assert!(matches!(root.kind,ExprKind::Ident(ref name)if name=="a"),"source={source} root={root:?} diagnostics={:?}",parsed.diagnostics);}else{assert!(matches!(root.kind,ExprKind::Binary{..}|ExprKind::Conditional{..}),"source={source} root={root:?} diagnostics={:?}",parsed.diagnostics);}}
 }
 #[test]fn paid_pratt_driver_keeps_default_ast_and_real_call_cleanup_refusals(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  for source in [format!("{}x", "a=".repeat(40)),format!("{}x", "a ? b : ".repeat(40)),format!("{}x{}","f(".repeat(40),")".repeat(40))]{
   let tokens=lex_spans(&source).tokens;let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));let out=parse_expression_span_tokens_with_admission(&source,&tokens,0,&a);assert!(a.is_stopped(),"source={source} diagnostics={:?}",out.diagnostics);assert_eq!(a.take_operational_error().unwrap().kind(),std::io::ErrorKind::OutOfMemory);drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }
 }
 #[test]fn paid_pratt_driver_operational_unwind_never_allocates_recovery_diagnostics(){
  let source=format!("{}x","a=".repeat(80));let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));
  let mut parser=ExprParser{cleanup:crate::parser_cleanup::ParserCleanup::new(Some(&a)).unwrap(),admission:Some(&a),tokens:lex(&source).tokens,index:0,ternary_then_depth:0,original_simple_incomplete:None,original_scope_prefix:None,original_profile:false,native_recovered:false,native_deferred:false,input_notices:crate::original_input_notices::Builder::default(),constructor_facts:crate::original_constructor_facts::Builder::default(),input_failure:None,expected_term:None,expected_delimiter:None,diagnostics:Vec::new(),demand:None,literal_facts:None,colon_facts:None,original_source:None};
  assert!(parser.expression(0).and_then(|value|value.into_default(Some(&a))).is_none());assert!(a.is_stopped());assert!(parser.diagnostics.is_empty(),"operational failure must not become one syntax diagnostic per suspended frame");assert!(!parser.native_recovered);
  assert_eq!(a.take_operational_error().unwrap().kind(),std::io::ErrorKind::OutOfMemory);drop(parser);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn paid_pratt_driver_preserves_first_io_cancel_quota_and_retry(){
  use std::cell::Cell;let source="((a+b)*c)?d:e";let tokens=lex_spans(source).tokens;let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  for code in [1450,995]{for at in[0,tokens.len()+3,tokens.len()+6]{
   let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let calls=Cell::new(0);let poll=||{let n=calls.get();calls.set(n+1);if n==at{Err(std::io::Error::from_raw_os_error(code))}else{Ok(())}};
   let a=crate::SettingAdmission::new(&used,128*1024*1024,&poll);let out=parse_expression_span_tokens_with_admission(source,&tokens,0,&a);assert!(a.is_stopped());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(code));drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
   let retry=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));let out=parse_expression_span_tokens_with_admission(source,&tokens,0,&retry);assert!(out.diagnostics.is_empty());assert!(!retry.is_stopped());drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
  }}
  let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let low=crate::SettingAdmission::new(&used,fixed+16*1024+200,&||Ok(()));let out=parse_expression_span_tokens_with_admission(source,&tokens,0,&low);assert!(low.is_stopped());assert_eq!(low.take_operational_error().unwrap().kind(),std::io::ErrorKind::OutOfMemory);drop(out);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
}

#[cfg(test)]mod parser_expression_cleanup_owner_controls{
 use super::*;use std::{cell::Cell,sync::atomic::Ordering};
 fn parser<'op>(source:&str,a:&'op crate::SettingAdmission<'op>)->ExprParser<'op,'static>{
  ExprParser{cleanup:crate::parser_cleanup::ParserCleanup::new(Some(a)).unwrap(),admission:Some(a),tokens:expression_tokens(lex(source).tokens),index:0,ternary_then_depth:0,original_simple_incomplete:None,original_scope_prefix:None,original_profile:false,native_recovered:false,native_deferred:false,input_notices:crate::original_input_notices::Builder::default(),constructor_facts:crate::original_constructor_facts::Builder::default(),input_failure:None,expected_term:None,expected_delimiter:None,diagnostics:Vec::new(),demand:None,literal_facts:None,colon_facts:None,original_source:None}
 }
 #[test]fn parser_owned_deep_roots_drop_without_poll_but_public_raw_escape_stays_bounded(){
  let source=format!("{}x","a = ".repeat(256));let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  for export in[false,true]{
   let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let calls=Cell::new(0);let canceled=Cell::new(false);let poll=||{calls.set(calls.get()+1);if canceled.get(){Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};
   let a=crate::SettingAdmission::new(&used,128*1024*1024,&poll);let mut parser=parser(&source,&a);let root=parser.expression(0).unwrap();assert_eq!(root.nodes,513);assert!(!a.is_stopped());assert!(parser.diagnostics.is_empty());
   if export{assert!(root.into_default(Some(&a)).is_none());assert!(a.is_stopped());assert_eq!(a.take_operational_error().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert!(parser.diagnostics.is_empty());drop(parser);assert_eq!(used.load(Ordering::Acquire),fixed);}
   else{let alias=parser.cleanup.clone();let before=calls.get();canceled.set(true);drop(root);assert_eq!(calls.get(),before,"private cleanup never polls a canceled supplier");drop(parser);assert!(used.load(Ordering::Acquire)>fixed,"same physical cleanup buffer remains held by actual alias");drop(alias);assert_eq!(used.load(Ordering::Acquire),fixed);}
  }
 }
 #[test]fn parser_owned_partial_argument_and_field_rows_keep_first_io_and_panic_cleanup(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let chain=format!("{}x","a = ".repeat(256));
  for source in[format!("consume({chain},panic_marker)"),format!("/datum/probe{{first={chain},second=panic_marker}}")]{for panic in[false,true]{
   let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));let mut tokens=lex(&source).tokens.into_iter();let failed=Cell::new(false);
   let mut feed=||{assert!(!failed.get(),"no pull after actual operational failure");let token=tokens.next();if token.as_ref().is_some_and(|t|t.text=="panic_marker"){failed.set(true);if panic{panic!("actual partial parser ownership unwind")}return Err(std::io::Error::from_raw_os_error(1450))}Ok(token)};
   let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||parse_expression_demanded(&mut feed,&a)));
   assert!(failed.get(),"deep first row really reached its later sibling");
   if panic{assert!(result.is_err());}else{assert_eq!(result.unwrap().err().unwrap().raw_os_error(),Some(1450));}
   assert_eq!(used.load(Ordering::Acquire),fixed,"all actual row roots/buffers retire before credits");
  }}
 }

 fn frontier_leaf<'op>(p:&mut ExprParser<'op,'_>)->ParserExpr<'op>{p.leaf(Expr{span:Span::new(0,1),kind:ExprKind::Ident("x".into())}).unwrap()}
 fn frontier_binary<'op>(p:&mut ExprParser<'op,'_>,lhs:ParserExpr<'op>,rhs:ParserExpr<'op>)->ParserExpr<'op>{p.binary_node(lhs,rhs,|lhs,rhs|Expr{span:Span::new(0,1),kind:ExprKind::Binary{op:"+".into(),lhs:Box::new(lhs),rhs:Box::new(rhs)}}).unwrap()}
 fn frontier_tree<'op>(p:&mut ExprParser<'op,'_>,depth:usize)->ParserExpr<'op>{if depth==0{return frontier_leaf(p)}let lhs=frontier_tree(p,depth-1);let rhs=frontier_tree(p,depth-1);frontier_binary(p,lhs,rhs)}
 fn actual_release_frontier(value:ParserExpr<'_>)->usize{
  let bound=value.frontier;let mut pending=Vec::with_capacity(bound);pending.push(value.into_raw());let mut peak=1;
  while let Some(value)=pending.pop(){crate::setting_drop::release_child_roots(value.kind,|child|{assert!(pending.len()<bound,"bound before every actual visitor push");pending.push(child);peak=peak.max(pending.len());});}peak
 }
 #[test]fn parser_cleanup_frontier_matches_actual_lifo_shapes_and_variable_arity(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&used,128*1024*1024,&||Ok(()));let mut p=parser("",&a);
  let root=frontier_tree(&mut p,6);assert_eq!(root.nodes,127);assert_eq!(root.frontier,7);assert_eq!(actual_release_frontier(root),7);
  let mut root=frontier_leaf(&mut p);for _ in 0..20{let lhs=frontier_leaf(&mut p);root=frontier_binary(&mut p,lhs,root);}assert_eq!(root.frontier,21);assert_eq!(actual_release_frontier(root),21);
  let mut root=frontier_leaf(&mut p);for _ in 0..20{let rhs=frontier_leaf(&mut p);root=frontier_binary(&mut p,root,rhs);}assert_eq!(root.frontier,2);assert_eq!(actual_release_frontier(root),2);
  let condition=frontier_tree(&mut p,2);let then_value=frontier_tree(&mut p,1);let else_value=frontier_tree(&mut p,3);let root=p.conditional_node(condition,then_value,else_value,|condition,then_value,else_value|Expr{span:Span::new(0,1),kind:ExprKind::Conditional{condition:Box::new(condition),then_value:Box::new(then_value),else_value:Box::new(else_value)}}).unwrap();assert_eq!(root.frontier,6);assert_eq!(actual_release_frontier(root),6);
  for fields in[false,true]{let head=frontier_leaf(&mut p);if fields{let mut rows=ParserFields::new(p.cleanup.clone());for i in 0..5{let child=frontier_tree(&mut p,if i==4{3}else{0});p.push_field(&mut rows,format!("f{i}"),child).unwrap();}assert_eq!(rows.frontier,8);let root=p.object_node(head,rows,1).unwrap();assert_eq!(root.frontier,9);assert_eq!(actual_release_frontier(root),9);}else{let mut rows=ParserArgs::new(p.cleanup.clone());for i in 0..5{let child=frontier_tree(&mut p,if i==4{3}else{0});p.push_arg(&mut rows,child).unwrap();}assert_eq!(rows.frontier,8);let root=p.call_node(head,rows,1).unwrap();assert_eq!(root.frontier,9);assert_eq!(actual_release_frontier(root),9);}}
  drop(p);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn parser_cleanup_frontier_keeps_deep_unary_small_and_alias_refund_nonpoll(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let polls=Cell::new(0);let stopped=Cell::new(false);let poll=||{polls.set(polls.get()+1);if stopped.get(){Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};
  let a=crate::SettingAdmission::new(&used,fixed+256*1024,&poll);let payload=a.reserve(1025*std::mem::size_of::<Expr>()).unwrap();let mut p=parser("",&a);let mut root=frontier_leaf(&mut p);for _ in 0..1024{root=p.unary_node(root,|value|Expr{span:Span::new(0,1),kind:ExprKind::Group(Box::new(value))}).unwrap();}assert_eq!(root.nodes,1025);assert_eq!(root.frontier,1);assert!(!a.is_stopped());
  let alias=p.cleanup.clone();let before=polls.get();stopped.set(true);drop(root);assert_eq!(polls.get(),before);assert!(!a.is_stopped());drop(p);drop(payload);assert!(used.load(Ordering::Acquire)>fixed);drop(alias);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn parser_cleanup_frontier_keeps_growth_denial_first_io_and_partial_rows_safe(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  for fields in[false,true]{for code in[1450,995]{let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let fail=Cell::new(false);let poll=||if fail.get(){Err(std::io::Error::from_raw_os_error(code))}else{Ok(())};let a=crate::SettingAdmission::new(&used,128*1024*1024,&poll);let mut p=parser("",&a);let mut args=ParserArgs::new(p.cleanup.clone());let mut named=ParserFields::new(p.cleanup.clone());let child=frontier_tree(&mut p,3);if fields{p.push_field(&mut named,"first".into(),child).unwrap();}else{p.push_arg(&mut args,child).unwrap();}let child=frontier_tree(&mut p,2);fail.set(true);let result=if fields{named.push("second".into(),child,Some(&a))}else{args.push(child,Some(&a))};assert!(result.is_err());assert!(a.is_stopped());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(code));drop(args);drop(named);drop(p);assert_eq!(used.load(Ordering::Acquire),fixed);}}
  let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let payload_bytes=129*std::mem::size_of::<Expr>();let a=crate::SettingAdmission::new(&used,fixed+payload_bytes+16*1024,&||Ok(()));let payload=a.reserve(payload_bytes).unwrap();let mut p=parser("",&a);let mut root=Some(frontier_leaf(&mut p));let mut refused=false;for _ in 0..64{let Some(lhs)=p.leaf(Expr{span:Span::new(0,1),kind:ExprKind::Ident("x".into())})else{refused=true;break};match p.binary_node(lhs,root.take().unwrap(),|lhs,rhs|Expr{span:Span::new(0,1),kind:ExprKind::Binary{op:"+".into(),lhs:Box::new(lhs),rhs:Box::new(rhs)}}){Some(value)=>root=Some(value),None=>{refused=true;break}}}assert!(refused);assert!(a.is_stopped());assert_eq!(a.take_operational_error().unwrap().kind(),std::io::ErrorKind::OutOfMemory);drop(root);drop(p);drop(payload);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
}
