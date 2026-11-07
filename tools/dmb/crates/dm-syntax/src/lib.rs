//! Lossless lexical layer and a recovering structural parser for BYOND DM.
//!
//! This crate intentionally makes no claim to parse every expression yet. A declaration's
//! header and indented body are retained as tokens so later stages can diagnose unsupported
//! syntax without discarding the original source or changing declaration order.

use std::ops::Range;

mod audit;
mod native_indent_transition;
pub use native_indent_transition::{NativeIndentTransition, NativeIndentEmission, NativeIndentNotice};
mod boundary_scan;
mod stable_chunks;
pub use boundary_scan::{scan_top_level_boundaries, BoundaryCheckpoint, BoundaryScanError};
pub use stable_chunks::scan_stable_source_chunks_from;
mod declaration_type;
pub use declaration_type::{
    has_checker_qualifiers, is_original_static_type_modifier, normalize_declaration_type, project_declaration_type, DeclarationType,
};
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
    parse_proc_with_origins_at_span, parse_proc_with_origins_from_spans, ChunkReport,
    ProcedureWithOrigins, parse_original_proc_with_shared_parameters_from_spans,parse_original_proc_with_shared_parameters_from_window, StreamingAudit,parse_original_proc_with_origins_and_default_roots_from_spans, parse_proc_with_origins_and_default_roots_from_spans,
};
pub use statements::{
    parse_body_items, parse_body_items_with_context, parse_body_items_with_source, parse_proc_body,
    ControlOrigin, ForControl, ForListBinding, ForInitializer, ParsedBody, Statement, StatementKind,
    SwitchAlternative, SwitchCase, OriginalCaseCursor,
};
#[cfg(test)]
mod control_origin_tests;
pub use visit::{
    for_each_expression_child, try_for_each_expression_child, visit_expression, visit_projected_expression, visit_statement_view, visit_statements, NodeStep,
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
    /// Optional primary-token cursor: top-level assignment or suffix/terminator.
    /// Captured before declaration normalization, never a guessed header offset.
    pub declaration_cursor: Option<usize>,
    /// Local lexical qualifier fact; portable decoding never issues it.
    pub checker_qualifiers: u8,
    /// Primary grammar event DATA; portable decoding never grants it.
    pub original_outer_terminator: Option<bool>,
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
    Literal(LiteralText),
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
        via_colon: bool,
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
    pub(crate) original_simple_expression:Option<expression_parser::OriginalSimpleExpression>,
    pub(crate) original_input_notices:Option<OriginalInputNotices>,
    pub(crate) original_constructor_facts:Option<OriginalConstructorFacts>,
    pub(crate) original_input_failure:Option<OriginalInputFailure>,
    pub expr: Option<Expr>,
    pub diagnostics: Vec<Diagnostic>,
}

impl ParsedExpr{pub fn original_constructor_facts(&self)->Option<&OriginalConstructorFacts>{self.original_constructor_facts.as_ref()}pub fn original_input_notices(&self)->Option<&OriginalInputNotices>{self.original_input_notices.as_ref()}pub fn original_input_failure(&self)->Option<OriginalInputFailure>{self.original_input_failure}}
mod original_constructor_facts;
pub use original_constructor_facts::{OriginalConstructorFact,OriginalConstructorFacts};
mod original_input_notices;
pub use original_input_notices::{OriginalInputNotice,OriginalInputNoticeKind,OriginalInputNotices,OriginalInputFailure,OriginalInputExpected,original_input_type_name};
pub mod literal;
pub use literal::{shift_expression, LiteralText};

pub mod original_token_value;
pub use original_token_value::OriginalTokenValue;
mod expression_parser;
pub use expression_parser::{parse_expression,parse_expression_original_token_view,parse_expression_demanded,parse_original_expression_demanded,DemandedExpression,CompletedDemandedExpression,NativePrimitiveClauseMode,NativeExpressionReadRole,NativeExpressionRead,NativeExpressionTokenDemand,NativeExpressionTokenOccurrence,NativeTermExpectation,NativeDelimiterExpected,NativeDelimiterExpectation};
mod expression_continuation;
pub use expression_continuation::splice_expression_continuations;

mod declaration_parser;
use declaration_parser::*;
mod declaration_qualifiers;
pub use declaration_parser::{
    original_outer_terminator_observation_using,original_outer_terminator_observation_in_window_using, OriginalOuterTerminatorObservation,
    parse, parse_declaration_skeleton, primary_header_cursors, primary_header_facts,
    top_level_assignment_index, top_level_assignment_index_from_span_tokens, DeclarationSkeleton,
    PrimaryHeaderInput,
};
pub use declaration_qualifiers::{
    inherit_header_qualifiers, CHECKER_VAR_FINAL, CHECKER_VAR_MASK, CHECKER_VAR_PRIVATE,
    CHECKER_VAR_PROTECTED, UNKNOWN_HEADER_QUALIFIERS,
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
pub mod numeric_form;

#[cfg(test)]
mod constructor_boundary_tests;

mod local_variable_storage;
mod local_variable_syntax;
pub use local_variable_syntax::{
    ImplicitListInitializer, ImplicitListOrigin, LocalArraySyntax, LocalSourceKind,
    LocalVariableLedger, LocalVariableSyntax,
};
mod local_declaration;
pub use local_declaration::{local_type_path, project_local_declaration, LocalDeclaration};

pub mod native_special_forms;

#[cfg(test)]
mod procedure_origin_tests;

mod parameter_syntax;
mod shared_parameter_signature;
pub use shared_parameter_signature::{SharedParameterSignature,ProcedureParameters};
pub use parameter_syntax::{HeaderTypeDeclarationSyntax, ParameterSignature, ParameterSyntax,parameter_signature_with_default_roots,parameter_signature_original_with_default_roots,parameter_signature_original_plain_empty};

mod parameter_clauses;
pub use parameter_clauses::{parameter_clause_spans,parameter_clause_spans_in_window, ParameterClauseSpans,ParameterClauseCursor,ParameterExpressionDemand};
mod parameter_input_cursor;
pub use parameter_input_cursor::{ParameterInputCursor,ParameterInputFlow,ParameterInputFailure,RetainedParameterInput};
mod parameter_expressions;
pub use parameter_expressions::{ParameterDefaultSyntaxProvider,ParameterExpressions, ParameterInputSyntax};

mod setting_drop;
mod setting_prepare;
mod admitted_worklist;
mod body_literal_syntax;
pub use body_literal_syntax::{prepare_body_literal_syntax,PreparedBodyLiteralSyntax,BodyLiteralAdmission,drop_body_literal_syntax};
pub use setting_prepare::{prepare_setting_expression,prepare_setting_expression_with_original_literal_facts,retain_demanded_expression, SettingSyntaxFailure};
mod setting_expression;
pub use setting_expression::{
    visit_setting_literal_retention, SettingAdmission, SettingEvaluationFrame, SettingExpression, SettingRootLease,
    SharedSettingRetention,
};
mod setting_slots;
pub use setting_slots::SettingExpressionSlots;

mod setting_projection;
pub use setting_projection::{ProjectedExprView, SettingValueView, SettingView,SyntaxProjection};
pub use statements::{
    parse_body_items_with_context_and_settings, parse_body_items_with_admitted_literals, SettingStatement, SettingSyntaxProvider,
};

mod syntax_ledger_views;
pub use syntax_ledger_views::{ProjectedSyntaxExpr,ProjectedParameterSignature,ProjectedParameter,ProjectedHeaderTypeDeclaration,ProjectedParameterInput,ProjectedLocalLedger,ProjectedLocal,ProjectedArrayInitializer,ProjectedControlOrigins,ProjectedPendingBodies,ProjectedLiteralFragment,SyntaxViewError,ProjectedStatements,ProjectedStatement,ProjectedStatementKind,ProjectedForControl,ProjectedForInitializer,ProjectedSwitchCases,ProjectedSwitchCase,ProjectedSwitchAlternative};

pub use declaration_parser::{OriginalDeclarationFatal,OriginalDeclarationSkeleton,OriginalPrimaryHeader,OriginalHeaderFlow,OriginalDeclarationHeaderObserver,parse_original_declaration_skeleton_using,parse_original_declaration_skeleton_with_observer_using};

pub use syntax_ledger_views::ProjectedSettingExpression;

pub use statements::{OriginalBodyGrammarOutcome,OriginalBodyGrammarKind};

mod original_literal_data;
mod original_literal_projection;
pub use original_literal_projection::{OriginalLiteralOutputOwner,OriginalLiteralProjectionOwner};
pub use original_literal_data::{LiteralRawStorage,OriginalLiteralData,OriginalLiteralPool,OriginalLiteralRef,OriginalStringMode};

pub use lexer_items::{NativeLexicalPurpose,OriginalPunctuationFacts,OriginalIdentFacts,OriginalWhitespaceFacts,OriginalResourceFacts,OriginalCommentFacts,OriginalNumberFacts,NativeTokenCursor,OriginalPreparedBoundary,NativeTokenProgress,NativeTokenStep};
pub use lexer_items::{OriginalQuotedFrame,OriginalQuotedPart,OriginalQuotedPartKind,OriginalQuotedStep};

pub mod original_scalar_transport;

mod original_lexical_point;
pub use original_lexical_point::{OriginalLexicalNoticePoint,OriginalLexicalPointKind};

pub use declaration_parser::{OriginalPrimaryLiteralFacts,OriginalLiteralFactsView,OriginalLiteralRows,OriginalColonRows};

pub use original_token_value::OriginalCommentKind;

mod span_token_storage;
pub use span_token_storage::{OriginalTokenPageData, OriginalTokenPageLoan, SpanTokenStorage, SharedSpanTokens, TokenWindow, ORIGINAL_TOKEN_PAGE_ROWS};
pub use declaration_parser::OriginalDeclarationSyntax;

pub use declaration_parser::{
    OriginalCommittedItems, OriginalCommittedPrimary, OriginalItem, OriginalItems,
    OriginalPrimaryDemand, OriginalPrimaryLiveHeader, OriginalPrimaryProducerIdentity,
};

mod admitted_message;
pub use admitted_message::message_using as admitted_message_using;

mod original_failure_format;
pub use original_failure_format::{write_original_input_failure,write_original_term_failure,write_original_delimiter_failure};

mod setting_charge_counter;
pub use setting_charge_counter::SettingChargeCounter;
