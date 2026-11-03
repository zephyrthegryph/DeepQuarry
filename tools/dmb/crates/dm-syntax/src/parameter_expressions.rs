//! Original formal roots, owned exactly once by the existing signature receipt.
//! Presence is syntax only; metadata/current-owner admission is a separate gate.
use crate::parameter_syntax::ParameterToken;
use crate::{Expr, Span, TokenKind};
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ParameterInputSyntax {
    EmptyParens {
        span: Span,
        after_in: bool,
    },
    Union {
        span: Span,
        identifiers: Box<[Span]>,
        after_in: bool,
    },
}
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ParameterExpressions {
    pub(crate) default: Option<crate::SettingExpression>,
    pub(crate) source: Option<crate::SettingExpression>,
    pub(crate) dimensions: Box<[Option<crate::SettingExpression>]>,
    pub(crate) annotation: Option<crate::RetainedParameterInput>,
}
impl ParameterExpressions {
    /// DATA loan to the one existing retained default owner, not a source grant.
    pub fn default_root(&self)->Option<&crate::SettingExpression>{self.default.as_ref()}
    pub fn default(&self) -> Option<&Expr> {
        self.default.as_deref()
    }
    pub fn source(&self) -> Option<&Expr> {
        self.source.as_deref()
    }
    pub fn dimensions(&self) -> &[Option<crate::SettingExpression>] {
        &self.dimensions
    }
    pub fn annotation(&self) -> Option<&ParameterInputSyntax> {
        self.annotation.as_deref()
    }
    pub(crate) fn visit_roots<'a>(&'a self, mut f: impl FnMut(&'a Expr)) {
        if let Some(root)=&self.default{f(root.original_expression());}
        for e in self.source.iter().chain(self.dimensions.iter().filter_map(Option::as_ref))
        {
            f(e);
        }
    }
    pub(crate) fn visit_storage(&self, mut f: impl FnMut(usize, usize)) {
        if let Some(root)=&self.default{root.visit_root_storage(|p,n|f(p,n+2*std::mem::size_of::<usize>()));root.visit_retention_storage(&mut f);}
        for root in self.source.iter().chain(self.dimensions.iter().filter_map(Option::as_ref)){root.visit_root_storage(|p,n|f(p,n+2*std::mem::size_of::<usize>()));root.visit_retention_storage(&mut f);}

        if !self.dimensions.is_empty() {
            f(
                self.dimensions.as_ptr() as usize,
                std::mem::size_of_val(self.dimensions.as_ref()),
            );
        }
        if let Some(input)=&self.annotation{input.visit_storage(|address,_,capacity|f(address,capacity));}
    }
}
fn selected<T: ParameterToken>(tokens: &[T], span: Span) -> &[T] {
    let first = tokens.partition_point(|t| t.span().end <= span.start);
    let end = tokens.partition_point(|t| t.span().start < span.end);
    &tokens[first..end]
}
// Optional ROOT admission only. These bounds do not reject the original
// signature/path/body or change native compilation before borrowed consumers.
const MAX_ROOT_TOKENS: usize = 256;
const MAX_ROOT_BYTES: usize = 64 * 1024;
const MAX_ROOT_DELIMITERS: usize = 64;
const MAX_ROOT_RETAINED: usize = 1024 * 1024;
fn preflight<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    span: Span,
) -> Result<(), &'static str> {
    let width = span
        .end
        .checked_sub(span.start)
        .ok_or("formal optional root span reversed")?;
    if width > MAX_ROOT_BYTES {
        return Err("formal optional root byte admission exceeded");
    }
    let mut count = 0usize;
    let mut depth = 0usize;
    for token in tokens
        .iter()
        .filter(|t| !super::parameter_syntax::trivia(*t))
    {
        // A primary String is opaque to the token count, but may later demand
        // interpolation expression parsing. This is a conservative resource
        // envelope, NOT an interpolation grammar: escaped/raw '[' can refuse
        // too. Plain long literals do not demand child parsing and stay eligible.
        if token.kind() == TokenKind::String {
            let spelling = token.text(source);
            if spelling.contains('[') && spelling.len() > MAX_ROOT_TOKENS {
                return Err("formal optional interpolation work admission exceeded");
            }
        }
        count = count
            .checked_add(1)
            .ok_or("formal optional root token overflow")?;
        if count > MAX_ROOT_TOKENS {
            return Err("formal optional root token admission exceeded");
        }
        if matches!(token.kind(), TokenKind::Operator | TokenKind::Punctuation) {
            match token.text(source) {
                "(" | "[" | "{" => {
                    depth = depth
                        .checked_add(1)
                        .ok_or("formal optional root nesting overflow")?;
                    if depth > MAX_ROOT_DELIMITERS {
                        return Err("formal optional root nesting admission exceeded");
                    }
                }
                ")" | "]" | "}" => depth = depth.saturating_sub(1),
                _ => (),
            }
        }
    }
    Ok(())
}
fn root<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    span: Span,
    base: usize,
) -> Result<Box<Expr>, &'static str> {
    span.end
        .checked_add(base)
        .ok_or("formal expression origin overflow")?;
    let tokens = selected(tokens, span);
    if !tokens.iter().any(|t| !super::parameter_syntax::trivia(t)) {
        return Err("formal expression is empty");
    }
    preflight(source, tokens, span)?;
    #[cfg(test)]
    ROOT_PARSES.with(|n| n.set(n.get() + 1));
    let parsed = T::expression(source, tokens);
    if !parsed.diagnostics.is_empty() {
        return Err("formal expression requires unsupported primary grammar");
    }
    let mut expression = parsed.expr.ok_or("formal expression root unavailable")?;
    let retained = crate::local_variable_storage::expression(&expression, 0);
    if retained == usize::MAX || retained > MAX_ROOT_RETAINED {
        return Err("formal optional root retained admission exceeded");
    }
    crate::shift_expression(&mut expression, base);
    Ok(Box::new(expression))
}
fn shift(span: Span, base: usize) -> Result<Span, &'static str> {
    Ok(Span::new(
        span.start
            .checked_add(base)
            .ok_or("formal annotation origin overflow")?,
        span.end
            .checked_add(base)
            .ok_or("formal annotation origin overflow")?,
    ))
}
fn annotation<T:ParameterToken>(source:&str,tokens:&[T],span:Span,base:usize,after_in:bool)->Result<crate::RetainedParameterInput,&'static str>{
 let mut cursor=crate::ParameterInputCursor::compatibility(after_in);let mut any=false;
 for token in selected(tokens,span){if !super::parameter_syntax::trivia(token){any=true}
  match cursor.feed(token.kind(),shift(token.span(),base)?,token.text(source)){
   Ok(crate::ParameterInputFlow::Consumed|crate::ParameterInputFlow::ConsumedIdentifier)=>(),Ok(crate::ParameterInputFlow::Boundary)=>return Err(cursor.boundary_error()),
   Err(crate::ParameterInputFailure::Syntax{..})=>return Err("formal annotation is not an original identifier union"),Err(crate::ParameterInputFailure::Operational(_))=>return Err("formal annotation allocation refused"),
  }
 }
 if !any{return Err("formal input annotation is empty")}
 cursor.finish().map_err(|error|match error{crate::ParameterInputFailure::Syntax{expected:"identifier",..}=>"formal annotation union is incomplete",crate::ParameterInputFailure::Syntax{..}=>"formal annotation is not an original identifier union",crate::ParameterInputFailure::Operational(_)=>"formal annotation allocation refused"})
}
/// Syntax DATA source for already-produced roots. Source/header/current-role
/// authority remains with the actual caller; a span is not an ownership grant.
pub trait ParameterDefaultSyntaxProvider{
 fn produced_clauses(&mut self,_parameter:usize,_span:Span)->Result<crate::ParameterClauseSpans,&'static str>{Err("actual formal expression clause producer is unissued")}
 fn default_root(&mut self,parameter:usize,assignment:Span,expression:Span)->Result<crate::SettingExpression,&'static str>;
 fn input_annotation(&mut self,_parameter:usize,_marker:Span,_annotation:Span,_after_in:bool)->Result<crate::RetainedParameterInput,&'static str>{Err("actual demanded input annotation is unissued")}
 fn trailing_semicolon(&mut self,_parameter:usize,_semicolon:Span)->Result<(),&'static str>{Err("actual trailing semicolon parser observation is unissued")}
 fn source_root(&mut self,_parameter:usize,_marker:Span,_expression:Span)->Result<crate::SettingExpression,&'static str>{Err("actual demanded source expression is unissued")}
 fn dimension_root(&mut self,_parameter:usize,_dimension:usize,_brackets:Span,_expression:Span)->Result<crate::SettingExpression,&'static str>{Err("actual demanded dimension expression is unissued")}
}
fn expression_span<T:ParameterToken>(source:&str,tokens:&[T],span:Span,base:usize)->Result<Span,&'static str>{
 source.get(span.range()).ok_or("formal demanded root span escaped actual source")?;let chosen=selected(tokens,span);let mut significant=chosen.iter().filter(|token|!super::parameter_syntax::trivia(*token));let first=significant.next().ok_or("formal demanded root has no actual primary tokens")?;let last=significant.last().unwrap_or(first);shift(Span::new(first.span().start,last.span().end),base)
}
fn checked_loan(root:crate::SettingExpression,expected:Span)->Result<crate::SettingExpression,&'static str>{if root.current_offset()!=0||root.original_expression().span!=expected{return Err("formal demanded root differs from actual original token geometry")}Ok(root)}
pub(crate) fn issue<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    brackets: &[Span],
    base: usize,
 ) -> Result<Option<Box<ParameterExpressions>>, &'static str> {issue_with_default_provider(source,tokens,brackets,base,0,&mut None)}
pub(crate) fn issue_with_default_provider<T:ParameterToken>(source:&str,tokens:&[T],brackets:&[Span],base:usize,parameter:usize,defaults:&mut Option<&mut dyn ParameterDefaultSyntaxProvider>)->Result<Option<Box<ParameterExpressions>>,&'static str>{issue_with_profile(source,tokens,brackets,base,parameter,defaults,false)}
pub(crate) fn issue_original_with_default_provider<T:ParameterToken>(source:&str,tokens:&[T],brackets:&[Span],base:usize,parameter:usize,defaults:&mut Option<&mut dyn ParameterDefaultSyntaxProvider>)->Result<Option<Box<ParameterExpressions>>,&'static str>{issue_with_profile(source,tokens,brackets,base,parameter,defaults,true)}
fn issue_with_profile<T:ParameterToken>(source:&str,tokens:&[T],brackets:&[Span],base:usize,parameter:usize,defaults:&mut Option<&mut dyn ParameterDefaultSyntaxProvider>,original:bool)->Result<Option<Box<ParameterExpressions>>,&'static str>{
    let tokens=if let Some(last)=tokens.iter().rposition(|token|!super::parameter_syntax::trivia(token)){
     if tokens[last].text(source)==";"{if let Some(provider)=defaults.as_mut(){provider.trailing_semicolon(parameter,shift(tokens[last].span(),base)?)?;&tokens[..last]}else{tokens}}else{tokens}
    }else{tokens};
    let first = tokens.first().ok_or("formal token input empty")?;
    let last = tokens.last().unwrap();
    let span = Span::new(first.span().start, last.span().end);
    let clauses = if original{match defaults.as_mut(){Some(provider)=>{let mut parts=provider.produced_clauses(parameter,shift(span,base)?)?;let local=|point:Span|->Result<Span,&'static str>{Ok(Span::new(point.start.checked_sub(base).ok_or("produced clause before current parameter source")?,point.end.checked_sub(base).ok_or("produced clause before current parameter source")?))};parts.parameter=local(parts.parameter)?;parts.assignment=parts.assignment.map(local).transpose()?;parts.annotation=parts.annotation.map(local).transpose()?;parts.source=parts.source.map(local).transpose()?;parts.post_source_annotation=parts.post_source_annotation.map(local).transpose()?;parts},None=>crate::parameter_clauses::clause_spans(source,tokens,span)?}}else{crate::parameter_clauses::clause_spans(source,tokens,span)?};
    let after=|marker|if original{clauses.after_original(marker)}else{clauses.after(marker)};
    if clauses.assignment.is_none()
        && clauses.source.is_none()
        && clauses.annotation.is_none()
        && brackets.is_empty()
    {
        return Ok(None);
    }
    // Preserve current native unsupported semantics until semicolon ABI/notes
    // are proven; a path receipt does not imply this expression receipt exists.
    if tokens
        .iter()
        .rev()
        .find(|t| !super::parameter_syntax::trivia(*t))
        .is_some_and(|t| t.text(source) == ";")
    {
        return Err("formal trailing semicolon needs original ABI diagnostic support");
    }
    let default=match clauses.assignment{
      None=>None,
      Some(mark)=>Some(if let Some(provider)=defaults.as_mut(){
       let chosen=selected(tokens,after(mark));let mut significant=chosen.iter().filter(|token|!super::parameter_syntax::trivia(*token));let first=significant.next().ok_or("formal demanded default has no actual primary tokens")?;let last=significant.last().unwrap_or(first);
       let expected=shift(Span::new(first.span().start,last.span().end),base)?;let root=provider.default_root(parameter,shift(mark,base)?,expected)?;
       if root.current_offset()!=0||root.original_expression().span!=expected{return Err("formal demanded default root differs from actual original token geometry")}
       root
      }else{crate::SettingExpression::compatibility(*root(source,tokens,after(mark),base)?)}),
    };
    let in_source = clauses
        .source
        .map(|m| {
          if let Some(provider)=defaults.as_mut(){let expected=expression_span(source,tokens,after(m),base)?;let root=provider.source_root(parameter,shift(m,base)?,expected)?;checked_loan(root,expected)}
          else{root(source,tokens,after(m),base).map(|value|crate::SettingExpression::compatibility(*value))}
        })
        .transpose()?;
    let annotation = clauses
        .annotation
        .map(|m| {
            let after_in=clauses.source.is_some_and(|s|s.start<m.start);
            if let Some(provider)=defaults.as_mut(){let expected=expression_span(source,tokens,after(m),base)?;let input=provider.input_annotation(parameter,shift(m,base)?,expected,after_in)?;let actual=match &*input{ParameterInputSyntax::Union{span,after_in,..}|ParameterInputSyntax::EmptyParens{span,after_in}=>(*span,*after_in)};if actual!=(expected,after_in){return Err("actual demanded input annotation differs from current token geometry")}Ok(input)}else{annotation(source,tokens,after(m),base,after_in)}
        })
        .transpose()?;
    let mut dimensions = Vec::new();
    brackets
        .len()
        .checked_mul(std::mem::size_of::<Option<crate::SettingExpression>>())
        .ok_or("formal dimension capacity overflow")?;
    dimensions
        .try_reserve_exact(brackets.len())
        .map_err(|_| "formal dimension allocation refused")?;
    for (ordinal,bracket) in brackets.iter().enumerate() {
        let within = selected(tokens, *bracket);
        let count = within
            .iter()
            .filter(|t| !super::parameter_syntax::trivia(*t))
            .count();
        let first = within
            .iter()
            .find(|t| !super::parameter_syntax::trivia(*t))
            .ok_or("formal dimension original brackets unavailable")?;
        let last = within
            .iter()
            .rev()
            .find(|t| !super::parameter_syntax::trivia(*t))
            .unwrap();
        if count < 2 {
            return Err("formal dimension original brackets unavailable");
        }
        let inside = Span::new(first.span().end, last.span().start);
        dimensions.push(if count == 2 {
            None
        } else {
            Some(if let Some(provider)=defaults.as_mut(){let expected=expression_span(source,tokens,inside,base)?;let value=provider.dimension_root(parameter,ordinal,shift(*bracket,base)?,expected)?;checked_loan(value,expected)?}else{crate::SettingExpression::compatibility(*root(source,tokens,inside,base)?)})
        });
    }
    Ok(Some(Box::new(ParameterExpressions {
        default,
        source: in_source,
        dimensions: dimensions.into(),
        annotation,
    })))
}

#[cfg(test)]
thread_local! {static ROOT_PARSES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]
mod tests {
    use super::*;
    fn original(source: &str) -> crate::ProcedureParameters {
        let cold = crate::parse_declaration_skeleton(source);
        assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
        crate::parse_proc_with_origins_from_spans(source, cold.items[0].span, &cold.tokens, 0)
            .unwrap()
            .parameters
    }
    #[test]
    fn original_formal_roots_are_retained_once_and_as_is_not_an_expression() {
        let source="/proc/p(obj/item/x[first()][2][] = list(\"é,()\", list(1,2)) as mob|obj|null in view(7), y=3)\n    return x\n";
        let before = ROOT_PARSES.with(|n| n.get());
        let signature = original(source);
        assert_eq!(
            ROOT_PARSES.with(|n| n.get()) - before,
            5,
            "default/source/two dimensions plus second default only"
        );
        let entry = &signature.entries().unwrap()[0];
        let roots = entry.expressions().unwrap().unwrap();
        assert!(std::ptr::eq(
            roots.default().unwrap(),
            entry.expressions().unwrap().unwrap().default().unwrap()
        ));
        assert_eq!(roots.dimensions().len(), 3);
        assert!(roots.dimensions()[2].is_none());
        assert_eq!(
            &source[roots.default().unwrap().span.range()],
            "list(\"é,()\", list(1,2))"
        );
        assert_eq!(&source[roots.source().unwrap().span.range()], "view(7)");
        let ParameterInputSyntax::Union {
            identifiers,
            after_in,
            ..
        } = roots.annotation().unwrap()
        else {
            panic!("union")
        };
        assert!(!after_in);
        assert_eq!(
            identifiers
                .iter()
                .map(|s| &source[s.range()])
                .collect::<Vec<_>>(),
            ["mob", "obj", "null"]
        );
    }
    #[test]
    fn every_original_root_point_moves_with_current_prefix_not_cached_offsets() {
        let source = "/proc/p(x[dimension()] = make(1) in choose(2))\n    return x\n";
        let prefix = "// current prefix\n\n";
        let shifted = format!("{prefix}{source}");
        let one = original(source);
        let two = original(&shifted);
        let a = one.entries().unwrap()[0].expressions().unwrap().unwrap();
        let b = two.entries().unwrap()[0].expressions().unwrap().unwrap();
        let mut old = Vec::new();
        a.visit_roots(|e| old.push(e.span));
        let mut new = Vec::new();
        b.visit_roots(|e| new.push(e.span));
        for (a, b) in old.iter().zip(new.iter()) {
            assert_eq!(b.start, a.start + prefix.len());
            assert_eq!(&source[a.range()], &shifted[b.range()]);
        }
    }
    #[test]
    fn post_in_annotation_empty_parens_and_unsupported_shapes_remain_distinct() {
        let signature = original("/proc/p(x in list(1) as text, y as ())\n    return x\n");
        assert!(matches!(
            signature.entries().unwrap()[0]
                .expressions()
                .unwrap()
                .unwrap()
                .annotation(),
            Some(ParameterInputSyntax::Union { after_in: true, .. })
        ));
        assert!(matches!(
            signature.entries().unwrap()[1]
                .expressions()
                .unwrap()
                .unwrap()
                .annotation(),
            Some(ParameterInputSyntax::EmptyParens { .. })
        ));
        for source in [
            "/proc/p(x as (mob|obj))\n    return x\n",
            "/proc/p(x=1;)\n    return x\n",
            "/proc/p(x=1+)\n    return x\n",
        ] {
            let signature = original(source);
            assert!(
                signature.entries().unwrap()[0].expressions().is_err(),
                "{source}"
            );
        }
    }
    #[test]
    fn parameter_capacity_observation_never_demands_lazy_literal_parsing() {
        let signature = original("/proc/p(x=\"[missing()]\")\n    return x\n");
        let Expr {
            kind: crate::ExprKind::Literal(literal),
            ..
        } = signature.entries().unwrap()[0]
            .expressions()
            .unwrap()
            .unwrap()
            .default()
            .unwrap()
        else {
            panic!("literal")
        };
        assert!(literal.retained_parts().is_none());
        let before = signature.retained_bytes();
        assert!(literal.retained_parts().is_none());
        literal.parts().unwrap();
        assert!(signature.retained_bytes() > before);
    }
    #[test]
    fn optional_root_work_is_bounded_before_parser_without_losing_type_paths() {
        for expression in [
            std::iter::repeat_n("1", 600).collect::<Vec<_>>().join("+"),
            format!("{}1{}", "(".repeat(128), ")".repeat(128)),
            format!("\"{}\"", "[missing()]".repeat(7000)),
            format!("\"[{}1]\"", "!".repeat(4000)),
        ] {
            let source = format!("/proc/p(x={expression})\n    return 1\n");
            let before = ROOT_PARSES.with(|n| n.get());
            let signature = original(&source);
            let entry = &signature.entries().unwrap()[0];
            assert_eq!(entry.type_path(&source).unwrap(), None);
            assert!(entry.expressions().unwrap_err().contains("admission"));
            assert_eq!(
                ROOT_PARSES.with(|n| n.get()),
                before,
                "optional refusal precedes ExprParser"
            );
            assert_ne!(signature.retained_bytes(), usize::MAX);
            assert!(signature.retained_bytes() <= signature.header().end * 128 + 1024);
        }
    }
    #[test]
    fn empty_and_refused_roots_do_not_inflate_every_original_parameter() {
        let arguments = std::iter::repeat_n("a", 2048).collect::<Vec<_>>().join(",");
        let source = format!("/proc/p({arguments})\n    return 1\n");
        let signature = original(&source);
        assert_eq!(signature.entries().unwrap().len(), 2048);
        assert!(signature
            .entries()
            .unwrap()
            .iter()
            .all(|p| p.expressions().unwrap().is_none()));
        assert!(signature.retained_bytes() <= signature.header().end * 128 + 1024);
    }
    #[test]
    fn plain_long_literal_is_not_rejected_as_interpolation_work() {
        let source = format!("/proc/p(x=\"{}\")\n    return 1\n", "x".repeat(4096));
        let signature = original(&source);
        assert!(signature.entries().unwrap()[0]
            .expressions()
            .unwrap()
            .is_some());
    }
}

#[cfg(test)]mod demanded_default_owner_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 struct Provider{root:crate::SettingExpression,calls:usize,parameter:usize,assignment:Span,expression:Span}
 impl ParameterDefaultSyntaxProvider for Provider{
  fn default_root(&mut self,parameter:usize,assignment:Span,expression:Span)->Result<crate::SettingExpression,&'static str>{assert_eq!((parameter,assignment,expression),(self.parameter,self.assignment,self.expression));self.calls+=1;Ok(self.root.clone())}
 }
 fn demanded(source:&str,offset:usize,a:&crate::SettingAdmission<'_>)->crate::DemandedExpression{let mut tokens=crate::lex(source).tokens;for token in &mut tokens{token.span.start+=offset;token.span.end+=offset;}let mut input=tokens.into_iter();crate::parse_expression_demanded(&mut||Ok(input.next()),a).unwrap()}
 #[test]fn actual_demanded_default_is_the_same_existing_parameter_root_without_second_pratt_parse_and_retry_keeps_owner(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let source="/proc/p(x=1+2)\n    return x\n";let start=source.find("1+2").unwrap();let syntax=demanded("1+2",start,&a);let root=crate::retain_demanded_expression(syntax,&a).unwrap();let identity=root.clone();let mut provider=Provider{root,calls:0,parameter:0,assignment:Span::new(start-1,start),expression:Span::new(start,start+3)};let parsed=crate::parse_declaration_skeleton(source);let before=ROOT_PARSES.with(|n|n.get());
  let issued=crate::parse_proc_with_origins_and_default_roots_from_spans(source,parsed.items[0].span,&parsed.tokens,0,Some(&mut provider)).unwrap();assert_eq!(ROOT_PARSES.with(|n|n.get()),before);assert_eq!(provider.calls,1);let entry=&issued.parameters.entries().unwrap()[0];let actual=entry.expressions().unwrap().unwrap().default_root().unwrap();assert!(actual.same_root(&identity));drop(issued);
  let retried=crate::parse_proc_with_origins_and_default_roots_from_spans(source,parsed.items[0].span,&parsed.tokens,0,Some(&mut provider)).unwrap();assert_eq!(ROOT_PARSES.with(|n|n.get()),before);assert_eq!(provider.calls,2);assert!(retried.parameters.entries().unwrap()[0].expressions().unwrap().unwrap().default_root().unwrap().same_root(&identity));drop(retried);drop(provider);drop(identity);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_default_provider_missing_or_wrong_geometry_is_refused_without_raw_default_parse(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let source="/proc/p(x=1+2)\n    return x\n";let parsed=crate::parse_declaration_skeleton(source);let start=source.find("1+2").unwrap();let wrong=crate::retain_demanded_expression(demanded("1+2",0,&a),&a).unwrap();let before=ROOT_PARSES.with(|n|n.get());let mut provider=Provider{root:wrong,calls:0,parameter:0,assignment:Span::new(start-1,start),expression:Span::new(start,start+3)};let issued=crate::parse_proc_with_origins_and_default_roots_from_spans(source,parsed.items[0].span,&parsed.tokens,0,Some(&mut provider)).unwrap();assert!(issued.parameters.entries().unwrap()[0].expressions().unwrap_err().contains("geometry"));assert_eq!(ROOT_PARSES.with(|n|n.get()),before);drop(issued);drop(provider);
  struct Missing;impl ParameterDefaultSyntaxProvider for Missing{fn default_root(&mut self,_:usize,_:Span,_:Span)->Result<crate::SettingExpression,&'static str>{Err("actual demanded default root is unissued")}}
  let issued=crate::parse_proc_with_origins_and_default_roots_from_spans(source,parsed.items[0].span,&parsed.tokens,0,Some(&mut Missing)).unwrap();assert_eq!(issued.parameters.entries().unwrap()[0].expressions().unwrap_err(),"actual demanded default root is unissued");assert_eq!(ROOT_PARSES.with(|n|n.get()),before);drop(issued);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_demanded_default_retention_foreign_domain_and_first_io_retract_unpublished_root(){
  let one=Arc::new(AtomicUsize::new(0));let two=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&one,1<<24,&poll);let b=crate::SettingAdmission::new(&two,1<<24,&poll);let result=crate::retain_demanded_expression(demanded("1+2",0,&a),&b);assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::InvalidInput));assert_eq!(one.load(Ordering::Acquire),0);assert_eq!(two.load(Ordering::Acquire),0);
  let syntax=demanded("1+2",0,&a);let tiny=crate::SettingAdmission::new(&one,1,&poll);assert!(matches!(crate::retain_demanded_expression(syntax,&tiny),Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(one.load(Ordering::Acquire),0);
  let syntax=demanded("1+2",0,&a);let fail=||Err(std::io::Error::from_raw_os_error(1450));let failed=crate::SettingAdmission::new(&one,1<<24,&fail);assert!(matches!(crate::retain_demanded_expression(syntax,&failed),Err(crate::SettingSyntaxFailure::Operational(_))));assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(one.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod demanded_other_root_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn demanded(text:&str,span:Span,a:&crate::SettingAdmission<'_>)->crate::SettingExpression{
  let mut tokens=crate::lex(&text[span.range()]).tokens.into_iter();let mut source=||Ok(tokens.next().map(|mut token|{token.span=Span::new(token.span.start+span.start,token.span.end+span.start);token}));let root=crate::parse_expression_demanded(&mut source,a).unwrap();crate::retain_demanded_expression(root,a).unwrap()
 }
 #[test]fn actual_source_and_dimension_loans_use_the_same_admitted_root_without_optional_pratt_replay(){
  let text="x[1+2] = 3 in y";let tokens=crate::lex_spans(text).tokens;let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let dimension=demanded(text,Span::new(2,5),&a);let default=demanded(text,Span::new(9,10),&a);let source=demanded(text,Span::new(14,15),&a);
  struct Loans<'a>{dimension:&'a crate::SettingExpression,default:&'a crate::SettingExpression,source:&'a crate::SettingExpression,calls:usize}
  impl ParameterDefaultSyntaxProvider for Loans<'_>{fn default_root(&mut self,p:usize,m:Span,e:Span)->Result<crate::SettingExpression,&'static str>{assert_eq!((p,m,e),(0,Span::new(7,8),Span::new(9,10)));self.calls+=1;Ok(self.default.clone())}fn source_root(&mut self,p:usize,m:Span,e:Span)->Result<crate::SettingExpression,&'static str>{assert_eq!((p,m,e),(0,Span::new(11,13),Span::new(14,15)));self.calls+=1;Ok(self.source.clone())}fn dimension_root(&mut self,p:usize,index:usize,m:Span,e:Span)->Result<crate::SettingExpression,&'static str>{assert_eq!((p,index,m,e),(0,0,Span::new(1,6),Span::new(2,5)));self.calls+=1;Ok(self.dimension.clone())}}
  let mut loans=Loans{dimension:&dimension,default:&default,source:&source,calls:0};let before=ROOT_PARSES.with(|n|n.get());let roots=issue_with_default_provider(text,&tokens,&[Span::new(1,6)],0,0,&mut Some(&mut loans)).unwrap().unwrap();assert_eq!(ROOT_PARSES.with(|n|n.get()),before);assert_eq!(loans.calls,3);assert!(std::ptr::eq(roots.source().unwrap(),source.original_expression()));assert!(std::ptr::eq(roots.dimensions()[0].as_deref().unwrap(),dimension.original_expression()));assert!(std::ptr::eq(roots.default().unwrap(),default.original_expression()));drop(roots);drop(loans);drop((dimension,default,source));assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_source_and_dimension_provider_failure_never_falls_back_to_optional_parser(){
  struct Deny;impl ParameterDefaultSyntaxProvider for Deny{fn default_root(&mut self,_:usize,_:Span,_:Span)->Result<crate::SettingExpression,&'static str>{Err("no demanded default")}}
  for(text,brackets)in[("x in y",vec![]),("x[1]",vec![Span::new(1,4)])]{let tokens=crate::lex_spans(text).tokens;let before=ROOT_PARSES.with(|n|n.get());assert!(issue_with_default_provider(text,&tokens,&brackets,0,0,&mut Some(&mut Deny)).is_err());assert_eq!(ROOT_PARSES.with(|n|n.get()),before);}
 }
}
