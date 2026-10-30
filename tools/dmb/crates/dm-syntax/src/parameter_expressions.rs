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
    pub(crate) default: Option<Box<Expr>>,
    pub(crate) source: Option<Box<Expr>>,
    pub(crate) dimensions: Box<[Option<Box<Expr>>]>,
    pub(crate) annotation: Option<ParameterInputSyntax>,
}
impl ParameterExpressions {
    pub fn default(&self) -> Option<&Expr> {
        self.default.as_deref()
    }
    pub fn source(&self) -> Option<&Expr> {
        self.source.as_deref()
    }
    pub fn dimensions(&self) -> &[Option<Box<Expr>>] {
        &self.dimensions
    }
    pub fn annotation(&self) -> Option<&ParameterInputSyntax> {
        self.annotation.as_ref()
    }
    pub(crate) fn visit_roots<'a>(&'a self, mut f: impl FnMut(&'a Expr)) {
        for e in self
            .default
            .iter()
            .chain(self.source.iter())
            .chain(self.dimensions.iter().filter_map(Option::as_ref))
        {
            f(e);
        }
    }
    pub(crate) fn visit_storage(&self, mut f: impl FnMut(usize, usize)) {
        self.visit_roots(|expr| f(expr as *const Expr as usize, std::mem::size_of::<Expr>()));
        if !self.dimensions.is_empty() {
            f(
                self.dimensions.as_ptr() as usize,
                std::mem::size_of_val(self.dimensions.as_ref()),
            );
        }
        if let Some(ParameterInputSyntax::Union { identifiers, .. }) = &self.annotation {
            if !identifiers.is_empty() {
                f(
                    identifiers.as_ptr() as usize,
                    std::mem::size_of_val(identifiers.as_ref()),
                );
            }
        }
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
fn annotation<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    span: Span,
    base: usize,
    after_in: bool,
) -> Result<ParameterInputSyntax, &'static str> {
    let selected = selected(tokens, span);
    let count = selected
        .iter()
        .filter(|t| !super::parameter_syntax::trivia(*t))
        .count();
    let mut significant = selected
        .iter()
        .filter(|t| !super::parameter_syntax::trivia(*t));
    let first = significant
        .next()
        .ok_or("formal input annotation is empty")?;
    let last = selected
        .iter()
        .rev()
        .find(|t| !super::parameter_syntax::trivia(*t))
        .unwrap();
    let whole = shift(Span::new(first.span().start, last.span().end), base)?;
    if count == 2 && first.text(source) == "(" && last.text(source) == ")" {
        return Ok(ParameterInputSyntax::EmptyParens {
            span: whole,
            after_in,
        });
    }
    let mut identifiers = Vec::new();
    let upper = count
        .checked_add(1)
        .ok_or("formal annotation count overflow")?
        / 2;
    upper
        .checked_mul(std::mem::size_of::<Span>())
        .ok_or("formal annotation capacity overflow")?;
    identifiers
        .try_reserve_exact(upper)
        .map_err(|_| "formal annotation allocation refused")?;
    for (index, t) in std::iter::once(first).chain(significant).enumerate() {
        if index % 2 == 0 {
            if t.kind() != TokenKind::Ident {
                return Err("formal annotation is not an original identifier union");
            }
            identifiers.push(shift(t.span(), base)?);
        } else if t.text(source) != "|" {
            return Err("formal annotation union separator unsupported");
        }
    }
    if count % 2 == 0 {
        return Err("formal annotation union is incomplete");
    }
    Ok(ParameterInputSyntax::Union {
        span: whole,
        identifiers: identifiers.into(),
        after_in,
    })
}
pub(crate) fn issue<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    brackets: &[Span],
    base: usize,
) -> Result<Option<Box<ParameterExpressions>>, &'static str> {
    let first = tokens.first().ok_or("formal token input empty")?;
    let last = tokens.last().unwrap();
    let span = Span::new(first.span().start, last.span().end);
    let clauses = crate::parameter_clauses::clause_spans(source, tokens, span)?;
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
    let default = clauses
        .assignment
        .map(|m| root(source, tokens, clauses.after(m), base))
        .transpose()?;
    let in_source = clauses
        .source
        .map(|m| root(source, tokens, clauses.after(m), base))
        .transpose()?;
    let annotation = clauses
        .annotation
        .map(|m| {
            annotation(
                source,
                tokens,
                clauses.after(m),
                base,
                clauses.source.is_some_and(|s| s.start < m.start),
            )
        })
        .transpose()?;
    let mut dimensions = Vec::new();
    brackets
        .len()
        .checked_mul(std::mem::size_of::<Option<Box<Expr>>>())
        .ok_or("formal dimension capacity overflow")?;
    dimensions
        .try_reserve_exact(brackets.len())
        .map_err(|_| "formal dimension allocation refused")?;
    for bracket in brackets {
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
            Some(root(source, tokens, inside, base)?)
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
    fn original(source: &str) -> crate::ParameterSignature {
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
