//! Explicit current-source coordinates over SAME canonical original setting AST.
use crate::{Expr, SettingExpression, Span};
/// Source-coordinate DATA only. Equal extents do not establish equal source,
/// native parser issuance, a current recipe, semantic lookup or compiler rights.
/// The owning current recipe must separately establish every such capability.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct SyntaxProjection{original:Span,current:Span}
impl SyntaxProjection{
 pub fn new(original:Span,current:Span)->std::io::Result<Self>{let old=original.end.checked_sub(original.start);let now=current.end.checked_sub(current.start);if old.is_none()||old!=now{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"syntax projection extent differs or is reversed"))}Ok(Self{original,current})}
 pub fn original(self)->Span{self.original}
 pub fn current(self)->Span{self.current}
 pub fn span(self,span:Span)->Option<Span>{if span.start>span.end||span.start<self.original.start||span.end>self.original.end{return None}Some(Span::new(self.current.start.checked_add(span.start.checked_sub(self.original.start)?)?,self.current.start.checked_add(span.end.checked_sub(self.original.start)?)?))}
 pub fn inverse(self)->Self{Self{original:self.current,current:self.original}}
 pub fn then(self,next:Self)->std::io::Result<Self>{if self.current!=next.original{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"syntax projection intermediate window differs"))}Self::new(self.original,next.current)}
}
#[derive(Clone, Copy)]
pub struct ProjectedExprView<'a> {
    expression: &'a Expr,
    root: &'a SettingExpression,
}
impl<'a> ProjectedExprView<'a> {
    pub(crate) fn new(root: &'a SettingExpression, expression: &'a Expr) -> Self {
        Self { expression, root }
    }
    /// Explicitly ORIGINAL coordinates; never a current-source Expr substitute.
    pub fn original(self) -> &'a Expr {
        self.expression
    }
    pub fn current_span(self) -> Span {
        self.root
            .current_span_of(self.expression)
            .expect("issued setting child remains inside checked source projection")
    }
    pub fn current_span_of(self, original: &Expr) -> Option<Span> {
        self.root.current_span_of(original)
    }
    pub fn current_offset(self) -> usize {
        self.root.current_offset()
    }
}

#[derive(Clone, Copy)]
pub enum SettingValueView<'a> {
    Owned(&'a Expr),
    Projected(&'a SettingExpression),
}
impl<'a> SettingValueView<'a> {
    pub fn original(self) -> &'a Expr {
        match self {
            Self::Owned(e) => e,
            Self::Projected(e) => e.original_expression(),
        }
    }
    pub fn current_span(self) -> Span {
        match self {
            Self::Owned(e) => e.span,
            Self::Projected(e) => e.current_span(),
        }
    }
    pub fn is_projected(self) -> bool {
        matches!(self, Self::Projected(_))
    }
}
pub struct SettingView<'a> {
    pub attribute: &'a str,
    pub relation: &'a str,
    pub value: SettingValueView<'a>,
}
impl crate::Statement {
    pub fn setting(&self) -> Option<SettingView<'_>> {
        match &self.kind {
            crate::StatementKind::Set {
                attribute,
                relation,
                value,
            } => Some(SettingView {
                attribute,
                relation,
                value: SettingValueView::Owned(value),
            }),
            crate::StatementKind::ProjectedSet {
                attribute,
                relation,
                value,
            } => Some(SettingView {
                attribute,
                relation,
                value: SettingValueView::Projected(value),
            }),
            _ => None,
        }
    }
}

#[cfg(test)]mod syntax_projection_tests{use super::*;
 #[test]fn real_coordinate_windows_compose_both_directions_without_signed_overflow_or_ast_copy(){let forward=SyntaxProjection::new(Span::new(100,160),Span::new(500,560)).unwrap();let backward=SyntaxProjection::new(Span::new(500,560),Span::new(7,67)).unwrap();let full=forward.then(backward).unwrap();for span in [Span::new(100,100),Span::new(123,142),Span::new(160,160)]{assert_eq!(full.span(span),backward.span(forward.span(span).unwrap()));assert_eq!(full.inverse().span(full.span(span).unwrap()),Some(span));}assert_eq!(full.span(Span::new(123,142)),Some(Span::new(30,49)));assert_eq!(full.span(Span::new(99,100)),None);assert_eq!(full.span(Span::new(100,161)),None);assert_eq!(full.span(Span::new(142,123)),None);}
 #[test]fn projection_rejects_extent_and_intermediate_mismatch_and_keeps_real_eof_point(){assert!(SyntaxProjection::new(Span::new(10,9),Span::new(1,2)).is_err());assert!(SyntaxProjection::new(Span::new(10,20),Span::new(1,12)).is_err());let a=SyntaxProjection::new(Span::new(usize::MAX-5,usize::MAX),Span::new(0,5)).unwrap();assert_eq!(a.span(Span::new(usize::MAX,usize::MAX)),Some(Span::new(5,5)));assert_eq!(a.inverse().span(Span::new(0,5)),Some(Span::new(usize::MAX-5,usize::MAX)));let different=SyntaxProjection::new(Span::new(1,6),Span::new(10,15)).unwrap();assert!(a.then(different).is_err());}
}
