//! Lossless lexical layer and a recovering structural parser for BYOND DM.
//!
//! This crate intentionally makes no claim to parse every expression yet. A declaration's
//! header and indented body are retained as tokens so later stages can diagnose unsupported
//! syntax without discarding the original source or changing declaration order.

use std::ops::Range;

mod audit;
mod boundary_scan;
mod stable_chunks;
pub use boundary_scan::{scan_top_level_boundaries, BoundaryCheckpoint, BoundaryScanError};
pub use stable_chunks::scan_stable_source_chunks_from;
mod declaration_type;
pub use declaration_type::{normalize_declaration_type, project_declaration_type, DeclarationType};
pub mod map;
mod pending_body;
mod scope_map;
mod statements;
pub use pending_body::{
    termination_after, termination_after_with_context, BodyTermination, PendingBody,
};
pub use scope_map::{ScopeCheckpoint, ScopeMap};
mod lexical_scope;
mod reference_roles;
pub use lexical_scope::{local_name, Binding, BindingId, BindingValue, LexicalScopes, ScopeError};
pub use reference_roles::{
    arglist_argument, assignment_target_access, call_target, is_global_receiver,
    is_literal_identifier, named_argument, reference_node_name, CallTarget, NamedArgument,
    ReferenceAccess,
};
mod visit;
pub use audit::{
    audit_source_streaming, for_each_parsed_chunk, for_each_source_chunk,
    for_each_source_chunk_with_limits, for_each_stable_source_chunk, parse_proc_at_span,
    ChunkReport, StreamingAudit,
};
pub use statements::{
    parse_body_items, parse_body_items_with_context, parse_body_items_with_source, parse_proc_body,
    ForControl, ForInitializer, ParsedBody, Statement, StatementKind, SwitchAlternative,
    SwitchCase,
};
pub use visit::{
    for_each_expression_child, visit_expression, visit_statement_view, visit_statements, NodeStep,
    TypedVisitor, VisitDecision, VisitReport,
};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Hash)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
    pub fn range(self) -> Range<usize> {
        self.start..self.end
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    pub span: Span,
    pub kind: DiagnosticKind,
    pub message: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum DiagnosticKind {
    Lexical,
    Expression,
    /// Recognized syntax reached EOF while a required operand or group close was missing.
    IncompleteExpression,
    /// A comma-separated leaf inside an indented local var group is illegal.
    InvalidDeclarationGroup,
    Statement,
    Indentation,
    Unsupported,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum TokenKind {
    Ident,
    Number,
    String,
    Resource,
    Interpolation,
    Operator,
    Punctuation,
    Whitespace,
    Newline,
    Comment,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
    pub text: String,
}

/// A token view into the caller's source. Large preprocessing passes can use these spans
/// without allocating a separate `String` for every punctuation or identifier token.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SpanToken {
    pub kind: TokenKind,
    pub span: Span,
}

impl SpanToken {
    pub fn text(self, source: &str) -> &str {
        &source[self.span.range()]
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SpannedLexed {
    pub tokens: Vec<SpanToken>,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Lexed {
    pub tokens: Vec<Token>,
    pub diagnostics: Vec<Diagnostic>,
}

mod lexer_items;
use lexer_items::*;
pub use lexer_items::{
    lex, lex_spans, lexical_balance, lookahead_after, next_significant_token, quoted_end,
    visit_comment_spans, visit_tokens, visit_tokens_while, LexerLookahead, LexicalBalance,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ItemKind {
    Type,
    Proc,
    Verb,
    Var,
    /// A comma-separated leaf inside an indented local var group is illegal.
    InvalidDeclarationGroup,
    Statement,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Item {
    pub kind: ItemKind,
    /// Source spelling, including whether a path was relative.
    pub header: String,
    pub span: Span,
    pub header_span: Span,
    pub indent: usize,
    pub children: Vec<Item>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct AstFile {
    pub items: Vec<Item>,
    pub tokens: Vec<Token>,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExprKind {
    Ident(String),
    Literal(String),
    TypePath(String),
    Unary {
        op: String,
        value: Box<Expr>,
    },
    Binary {
        op: String,
        lhs: Box<Expr>,
        rhs: Box<Expr>,
    },
    Conditional {
        condition: Box<Expr>,
        then_value: Box<Expr>,
        else_value: Box<Expr>,
    },
    Call {
        callee: Box<Expr>,
        args: Vec<Expr>,
    },
    Member {
        object: Box<Expr>,
        selector: String,
        via_colon: bool,
    },
    StaticMember {
        object: Box<Expr>,
        selector: String,
    },
    TypeFilter {
        value: Box<Expr>,
        types: Vec<String>,
    },
    ObjectInitializer {
        object: Box<Expr>,
        fields: Vec<(String, Expr)>,
    },
    SafeMember {
        object: Box<Expr>,
        selector: String,
    },
    Index {
        object: Box<Expr>,
        index: Box<Expr>,
    },
    SafeIndex {
        object: Box<Expr>,
        index: Box<Expr>,
    },
    Group(Box<Expr>),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ParsedExpr {
    pub expr: Option<Expr>,
    pub diagnostics: Vec<Diagnostic>,
}

mod expression_parser;
pub use expression_parser::parse_expression;
mod expression_continuation;
pub use expression_continuation::splice_expression_continuations;

mod declaration_parser;
use declaration_parser::*;
pub use declaration_parser::{
    parse, parse_declaration_skeleton, top_level_assignment_index, DeclarationSkeleton,
};

#[cfg(test)]
mod tests {
    include!("lib_tests_1.rs");
    include!("lib_tests_2.rs");
}

mod statement_filter;
pub use statement_filter::filter_statements;

mod statement_view;
pub use statement_view::{StatementMask, StatementView};
