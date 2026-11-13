//! A typed, recovering procedure body layer over the lossless indentation tree.
//! Every statement retains its original header and absolute source byte spans.

use crate::{parse_expression, Diagnostic, DiagnosticKind, Expr, ExprKind, Item, ItemKind, Span};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Statement {
    pub kind: StatementKind,
    pub span: Span,
    pub header_span: Span,
    pub raw_header: String,
}

/// Name component consumed by the same actual for-list header tokens.
/// No copied text, secondary parse or source/BODY availability grant.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct ForListBinding{name:Span}
impl ForListBinding{pub fn name(self)->Span{self.name}}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ForControl {
    All {
        declaration: String,
        source_binding:Option<ForListBinding>,
    },
    Each {
        binding: String,
        source_binding:Option<ForListBinding>,
        iterable: Expr,
    },
    Pair {
        key_binding: String,
        value_binding: String,
        iterable: Expr,
    },
    Range {
        binding: String,
        start: Expr,
        end: Expr,
        step: Option<Expr>,
    },
    RangeImplicitArray {
        binding: String,
        end: Expr,
        step: Option<Expr>,
    },
    CStyle {
        initializer: Option<ForInitializer>,
        condition: Option<Expr>,
        step: Option<Expr>,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ForInitializer {
    Declare {
        declaration: String,
        value: Option<Expr>,
    },
    Expr(Expr),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SwitchAlternative {
    Exact(Expr),
    Range(Expr, Expr),
}

#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub enum OriginalCaseCursor{Token(Span),SourceEnd{offset:usize,fallback:Span}}
/// In-body authored anchors, distinct from the Original reader's cursor,
/// which may point past the item extent to a trailing token or source EOF.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OriginalCaseSite {
    pub header: Span,
    pub body: Span,
    pub cursor: Result<OriginalCaseCursor, &'static str>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SwitchCase {
    pub original_site:OriginalCaseSite,
    pub alternatives: Vec<SwitchAlternative>,
    pub body: Vec<Statement>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StatementKind {
    If {
        condition: Expr,
        then_branch: Vec<Statement>,
        else_branch: Vec<Statement>,
    },
    While {
        condition: Expr,
        body: Vec<Statement>,
    },
    DoWhile {
        body: Vec<Statement>,
        condition: Expr,
    },
    Spawn {
        delay: Option<Expr>,
        body: Vec<Statement>,
    },
    Set {
        attribute: String,
        relation: String,
        value: Expr,
    },
    /// SAME written setting; RHS borrows canonical ORIGINAL syntax with a
    /// checked scalar current-source projection. Never an executable Expr copy.
    ProjectedSet {
        attribute: String,
        relation: String,
        value: crate::SettingExpression,
    },
    For {
        control: ForControl,
        body: Vec<Statement>,
    },
    Switch {
        selector: Expr,
        cases: Vec<SwitchCase>,
        else_branch: Vec<Statement>,
        /// Actual primary else header, including an explicitly empty block.
        default_present: bool,
    },
    Try {
        body: Vec<Statement>,
        catch_binding: Option<String>,
        /// Number of actual original tree-path parameters issued by the primary ledger.
        catch_parameter_count: usize,
        catch_header_span: Span,
        catch_body: Vec<Statement>,
    },
    Throw(Expr),
    Label {
        name: String,
        body: Vec<Statement>,
    },
    Goto(String),
    Return(Option<Expr>),
    Var {
        declaration: String,
        value: Option<Expr>,
    },
    Assign {
        target: Expr,
        op: String,
        value: Expr,
    },
    Call(Expr),
    Expression(Expr),
    Break,
    BreakLabel(String),
    Continue,
    ContinueLabel(String),
    /// Keeps syntax available to diagnostics and future grammar extensions.
    Unsupported,
}

/// Exact primary-parser control delimiter, retained separately from expression
/// spans so whitespace and multiline conditions never require guessed offsets.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ControlOrigin {
    pub condition: Span,
    pub opening: Span,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ParsedBody {
    /// Private primary grammar provenance DATA; never source/model authority.
    pub original_grammar:Option<OriginalBodyGrammarOutcome>,
    pub statements: Vec<Statement>,
    pub control_origins: Vec<ControlOrigin>,
    pub local_variables: crate::LocalVariableLedger,
    pub diagnostics: Vec<Diagnostic>,
    /// Source-issued grammar context, kept separate to preserve semantic error order.
    pub pending_bodies: Vec<crate::PendingBody>,
}

impl ParsedBody {
    pub fn control_origin(&self, condition: Span) -> Option<Span> {
        self.control_origins
            .iter()
            .find(|origin| origin.condition == condition)
            .map(|origin| origin.opening)
    }
}

/// Parse the body of a structural `Proc` or `Verb` item. Unsupported forms are retained as
/// `StatementKind::Unsupported`. Some diagnostics are deferred, so an empty
/// diagnostic list does not certify coverage: callers must reject unsupported
/// nodes and unresolved/missing pending bodies before claiming a complete model.
pub fn parse_proc_body(proc: &Item) -> ParsedBody {
    let mut result = ParsedBody::default();
    if !matches!(proc.kind, ItemKind::Proc | ItemKind::Verb) {
        result.diagnostics.push(Diagnostic {
            span: proc.header_span,
            kind: DiagnosticKind::Statement,
            message: "expected a procedure or verb item".into(),
        });
        return result;
    }
    parse_body_items(&proc.children)
}

/// Parse a procedure body when its owning declaration is already known.
pub fn parse_body_items(items: &[Item]) -> ParsedBody {
    parse_body_items_using_settings(items, None, None, None,false)
}

/// Storage supplied by an ORIGINAL owner; this interface itself grants no source
/// authority. Native callers validate their exact current declaration receipt.
pub struct SettingStatement {
    pub attribute: String,
    pub relation: String,
    pub value: crate::SettingExpression,
}
#[derive(Clone, Copy)]
pub enum OriginalLeafBlockLink { ElseIf, Else, DoWhile }

pub trait SettingSyntaxProvider {
    #[cfg(debug_assertions)]
    fn traces_original_body_grammar(&self) -> bool { false }

    /// Optional SAME original expression producer. Some returns snippet-local
    /// syntax once; operational errors must escape the admitted BODY producer.
    /// None denotes the unchanged ordinary parser route, not original parity.
    fn original_expression(&self,_source:&str,_offset:usize)->std::io::Result<Option<crate::ParsedExpr>>{Ok(None)}
    fn setting(&self, item: &Item) -> Result<SettingStatement, Diagnostic>;
    /// Prove a separate Original return keyword directly before another
    /// issued token. Expression validity is decided by the expression parser.
    fn original_joined_return(&self, _header: Span) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Match the actual condition close and first inline statement token.
    fn original_inline_if_leaf(&self, _boundary: Span, _keyword: &'static str) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Authenticate the range header's var/name prefix, first separator and to.
    fn original_for_range_header(
        &self, _prefix: Span, _name: Span, _between: Span, _initialized: bool,
    ) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Authenticate the exact unmodified type path and as-anything prefix.
    /// Components and name belong to this body's existing local ledger.
    fn original_for_each_anything_prefix(
        &self, _prefix: Span, _name: Span, _type_components: &[Span],
    ) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Authenticate the declaration prefix or prefix step at its actual span.
    fn original_classic_for_tokens(&self, _span: Span, _name: Span, _declaration: bool) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Authenticate both classic-loop separators in the same Original body.
    fn original_classic_for_separators(&self, _first: Span, _second: Span) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Match the actual logical block opener between two committed items.
    fn original_statement_block_open(&self, _gap: Span) -> std::io::Result<bool> {
        Ok(false)
    }
    /// Match the exact Original block closes and next attached production.
    fn original_leaf_block_link(
        &self, _tail: Span, _next: Span, _link: OriginalLeafBlockLink, _closes: usize,
    ) -> std::io::Result<bool> { Ok(false) }
    /// Recognize an actual uninitialized var/static/name from this body.
    fn original_uninitialized_static_local(&self, _header: Span) -> std::io::Result<bool> { Ok(false) }
    /// Recognize the exact bare token and pinned terminator from this body.
    fn original_bare_loop_control(&self, _header: Span, _keyword: &'static str) -> std::io::Result<bool> { Ok(false) }
    fn switch_case_cursor(&self,_item:&Item)->Result<OriginalCaseCursor,&'static str>{Err("original switch block cursor was not issued")}
}

#[cfg(debug_assertions)]
fn trace_original_unissued_leaf(body_start: usize, leaf: Span, reason: &str, source: Option<&str>) {
    use std::{io::Write, sync::atomic::{AtomicUsize, Ordering}};
    static REMAINING: AtomicUsize = AtomicUsize::new(32);
    if REMAINING.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |left| left.checked_sub(1)).is_err() {
        return;
    }
    let snippet = source.and_then(|source| source.get(leaf.range())).map(|text| {
        let end = text.char_indices().nth(96).map_or(text.len(), |(at, _)| at);
        &text[..end]
    });
    let _ = writeln!(std::io::stderr().lock(),
        "original.body_leaf_unissued body_start={body_start} span={leaf:?} reason={reason} source={snippet:?}");
}

fn parse_body_items_using_settings(
    items: &[Item],
    settings: Option<&dyn SettingSyntaxProvider>,
    admission: Option<&crate::SettingAdmission<'_>>,
    source: Option<&str>,
    deferred_literal_purity:bool,
) -> ParsedBody {
    let mut result = ParsedBody::default();
    let mut origins = BodyOrigins {
        controls: &mut result.control_origins,
        locals: &mut result.local_variables,
        settings,
        admission,
        deferred_literal_purity,
        source,
        original_compound_complete:true,
        #[cfg(debug_assertions)]
        trace_unissued_leaf: settings.is_some() && {
            static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
            *ENABLED.get_or_init(|| std::env::var_os("DMB_ORIGINAL_TRACE_GRAMMAR_LEAF").is_some())
        },
        #[cfg(debug_assertions)]
        first_unissued_leaf: None,
        original_compound_seen_statement:false,
        original_loop_control:false,
        original_terminal_header:items.last().filter(|item|item.children.is_empty()).map(|item|item.header_span),
        original_grammar:&mut result.original_grammar,
    };
    if items.is_empty(){*origins.original_grammar=Some(OriginalBodyGrammarOutcome{prefix_settings:0,scope_roots:None,kind:OriginalBodyGrammarKind::Available,statement:None,expression:None,operator:None});}
    let mut diagnostics=BodyDiagnostics{rows:&mut result.diagnostics,settings,admission};
    let mut prefix_settings = 0;
    result.statements = parse_sequence_first(items, None, &mut diagnostics, &mut origins, Some(&mut prefix_settings));
    drop(diagnostics);
    let compound=origins.original_compound_complete&&origins.original_compound_seen_statement;
    #[cfg(debug_assertions)]
    let first_unissued = origins.first_unissued_leaf;
    result.local_variables.finish_source_order();
    finish_original_setting_prefix(&mut result, prefix_settings);
    if compound&&result.diagnostics.is_empty(){result.original_grammar=Some(OriginalBodyGrammarOutcome{prefix_settings,scope_roots:Some(result.statements.len()),kind:OriginalBodyGrammarKind::Available,statement:None,expression:None,operator:None});}
    #[cfg(debug_assertions)]
    if result.original_grammar.is_none() && result.diagnostics.is_empty()
        && !admission.is_some_and(|admission| admission.is_stopped())
    {
        if let (Some((leaf, reason)), Some(first)) = (first_unissued, items.first()) {
            if settings.is_some_and(|provider| provider.traces_original_body_grammar()) {
                trace_original_unissued_leaf(first.header_span.start, leaf, reason, source);
            }
        }
    }
    result
}

/// Issue pending-body context from the complete current lexical input.
pub fn parse_body_items_with_source(items: &[Item], source: &str) -> ParsedBody {
    parse_body_items_with_context(items, source, &|_| None)
}

pub fn parse_body_items_with_context(
    items: &[Item],
    source: &str,
    context: &dyn Fn(usize) -> Option<ItemKind>,
) -> ParsedBody {
    let mut parsed = parse_body_items_using_settings(items, None, None, Some(source), false);
    parsed.pending_bodies =
        crate::pending_body::pending_bodies(&parsed.statements, source, context);
    parsed
}

/// Native entry shares setting roots with the original declaration owner. A
/// provider refusal is final: there is deliberately no compatibility text retry.
/// Operational failure is extracted by the admitted caller before publication.
pub fn parse_body_items_with_context_and_settings(
    items: &[Item],
    source: &str,
    context: &dyn Fn(usize) -> Option<ItemKind>,
    settings: &dyn SettingSyntaxProvider,
    admission: &crate::SettingAdmission<'_>,
) -> ParsedBody {
    let mut parsed = parse_body_items_using_settings(items, Some(settings), Some(admission), Some(source),false);
    if admission.is_stopped() {
        return parsed;
    }
    parsed.pending_bodies =
        crate::pending_body::pending_bodies(&parsed.statements, source, context);
    parsed
}

// Stack-only context of the existing BODY parser. It borrows the one output
// Vec and actual producer; no parser/model/cache or second diagnostic walk.
struct BodyDiagnostics<'a>{rows:&'a mut Vec<Diagnostic>,settings:Option<&'a dyn SettingSyntaxProvider>,admission:Option<&'a crate::SettingAdmission<'a>>}
impl std::ops::Deref for BodyDiagnostics<'_>{type Target=Vec<Diagnostic>;fn deref(&self)->&Self::Target{self.rows}}
impl std::ops::DerefMut for BodyDiagnostics<'_>{fn deref_mut(&mut self)->&mut Self::Target{self.rows}}
/// One existing native parser pass owns control AND local declaration origins.
struct BodyOrigins<'a> {
    source: Option<&'a str>,
    original_compound_complete:bool,
    #[cfg(debug_assertions)]
    trace_unissued_leaf: bool,
    #[cfg(debug_assertions)]
    first_unissued_leaf: Option<(Span, &'static str)>,
    original_compound_seen_statement:bool,
    original_loop_control:bool,
    original_terminal_header:Option<Span>,
    original_grammar:&'a mut Option<OriginalBodyGrammarOutcome>,
    controls: &'a mut Vec<ControlOrigin>,
    locals: &'a mut crate::LocalVariableLedger,
    settings: Option<&'a dyn SettingSyntaxProvider>,
    admission: Option<&'a crate::SettingAdmission<'a>>,
    deferred_literal_purity:bool,
}
impl BodyOrigins<'_> {
    fn require_original(&mut self, issued: bool, _span: Span, _reason: &'static str) {
        #[cfg(debug_assertions)]
        if self.trace_unissued_leaf && !issued && self.first_unissued_leaf.is_none() {
            self.first_unissued_leaf = Some((_span, _reason));
        }
        self.original_compound_complete &= issued;
    }

    fn catch_parts(&mut self,source:&str,tokens:&[crate::SpanToken],base:usize){
        let mut start=0usize;
        for end in 0..=tokens.len(){
            if end<tokens.len()&&tokens[end].text(source)!=","{continue}
            if let Some(a)=self.admission{if let Err(actual)=a.checkpoint(){a.record_operational_error(actual);self.locals.decline("native catch operation stopped");return}}
            let segment=&tokens[start..end];let mut significant=segment.iter().filter(|token|!matches!(token.kind,crate::TokenKind::Whitespace|crate::TokenKind::Newline|crate::TokenKind::Comment));
            let Some(first)=significant.next()else{if end<tokens.len(){self.locals.decline("native catch parameter cannot be empty before comma");}if end==tokens.len(){break}start=end+1;continue};
            let mut previous_ident=false;for token in std::iter::once(first).chain(significant){if token.kind==crate::TokenKind::Ident{if previous_ident{self.locals.decline("native catch path identifiers require separators");return}previous_ident=true;}else if token.text(source)=="/"{previous_ident=false;}else{self.locals.decline("native catch parameter is not an original tree path");return}}
            let count=segment.iter().filter(|token|!matches!(token.kind,crate::TokenKind::Whitespace|crate::TokenKind::Newline|crate::TokenKind::Comment)).count();let has_var=count>1&&first.text(source)=="var";
            let _ = self.locals.issue(source,segment,has_var,base,crate::LocalSourceKind::CatchBinding,None,None);
            if end==tokens.len(){break}start=end+1;
        }
    }
    fn push(&mut self, origin: ControlOrigin) {
        self.controls.push(origin);
    }
    fn local_parts(
        &mut self,
        source: &str,
        lexed: &crate::SpannedLexed,
        base: usize,
        parts: &[&str],
        kind: crate::LocalSourceKind,
    ) {
        if !lexed.diagnostics.is_empty() {
            self.locals
                .decline("native local token query has lexical errors");
            return;
        }
        let mut statement_group_anchor = None;
        for (index, part) in parts.iter().enumerate() {
            let part = part.trim();
            // `part` is a slice supplied by the EXISTING native grammar, not
            // looked up by matching equal text or reparsed by checker policy.
            let start = part.as_ptr() as usize - source.as_ptr() as usize;
            let end = start + part.len();
            let first = lexed.tokens.partition_point(|t| t.span.end <= start);
            let last = lexed.tokens.partition_point(|t| t.span.start < end);
            let Some(tokens) = lexed.tokens.get(first..last) else {
                self.locals.decline("native local token slice unavailable");
                return;
            };
            let preceding = if index == 0 {
                None
            } else {
                let token = lexed.tokens[..first].iter().rev().find(|t| {
                    !matches!(
                        t.kind,
                        crate::TokenKind::Whitespace
                            | crate::TokenKind::Comment
                            | crate::TokenKind::Newline
                    )
                });
                match token {
                    Some(token) if token.text(source) == "," => Some(token.span),
                    _ => {
                        self.locals
                            .decline("native preceding comma token unavailable");
                        return;
                    }
                }
            };
            let anchor = self.locals.issue(
                source,
                tokens,
                index == 0,
                base,
                if index == 0 {
                    kind
                } else {
                    crate::LocalSourceKind::CommaContinuation
                },
                preceding,
                statement_group_anchor,
            );
            if index == 0 && kind == crate::LocalSourceKind::Statement {
                // Keep the first token issued by the same local grammar. A
                // continuation's own location is still its consumed comma.
                statement_group_anchor = anchor;
            }
        }
    }
    // The binding is the existing parse_for slice of its existing clause.
    fn for_list_binding(&self,source:&str,lexed:&crate::SpannedLexed,base:usize,binding:&str)->Option<ForListBinding>{
        if !lexed.diagnostics.is_empty(){return None}
        let start=(binding.as_ptr()as usize).checked_sub(source.as_ptr()as usize)?;let end=start.checked_add(binding.len())?;
        if source.get(start..end)?!=binding{return None}
        let first=lexed.tokens.partition_point(|token|token.span.end<=start);let last=lexed.tokens.partition_point(|token|token.span.start<end);
        let mut significant=lexed.tokens.get(first..last)?.iter().filter(|token|!matches!(token.kind,crate::TokenKind::Whitespace|crate::TokenKind::Newline|crate::TokenKind::Comment));let token=significant.next()?;
        if token.text(source)=="var"{
            // Type/array validity and name come from the SAME local producer.
            let a=base.checked_add(start)?;let b=base.checked_add(end)?;
            let row=self.locals.entries().ok()?.iter().find(|row|row.source_kind==crate::LocalSourceKind::ForBinding&&row.name.start>=a&&row.name.end<=b)?;
            return Some(ForListBinding{name:row.name})
        }
        if token.kind!=crate::TokenKind::Ident||significant.next().is_some(){return None}
        Some(ForListBinding{name:Span::new(base.checked_add(token.span.start)?,base.checked_add(token.span.end)?)})
    }
    fn local_binding(
        &mut self,
        source: &str,
        lexed: &crate::SpannedLexed,
        base: usize,
        binding: &str,
        kind: crate::LocalSourceKind,
    ) {
        if binding.starts_with("var/") || starts_keyword(binding, "var") {
            self.local_parts(source, lexed, base, &[binding], kind);
        }
    }
}

fn parse_sequence(items:&[Item],diagnostics:&mut BodyDiagnostics<'_>,origins:&mut BodyOrigins<'_>)->Vec<Statement>{parse_sequence_first(items,None,diagnostics,origins,None)}
// Same sequence parser with its existing single inline normalization loan. The
// remaining items keep their original ownership and source coordinates.
fn parse_sequence_first(items:&[Item],first:Option<&Item>,diagnostics:&mut BodyDiagnostics<'_>,origins:&mut BodyOrigins<'_>,mut root_prefix:Option<&mut usize>)->Vec<Statement>{
    let mut statements = Vec::new();
    let mut index = 0;
    while index < items.len() {
        if origins
            .admission
            .is_some_and(|admission| admission.checkpoint().is_err())
        {
            break;
        }
        let item = if index==0{first.unwrap_or(&items[index])}else{&items[index]};
        let header = item.header.trim();
        let local_statement = item.children.is_empty()
            && (header.starts_with("var/") || starts_keyword(header, "var"));
        let mut original_local_head = false;
        // Only the outer body parser can lend this prefix. A non-setting
        // closes it before that statement can recursively consume children.
        let initial_setting = root_prefix.is_some()
            && item.children.is_empty()
            && starts_keyword(header, "set");
        if !initial_setting {
            root_prefix = None;
        }
        // SAME primary consumption; unproved families/children never grant availability.
        let mut defer_joined_return = false;
        if header == "do" || starts_keyword(header,"if") || starts_keyword(header,"while") || starts_keyword(header,"switch")
            || starts_keyword(header,"for") {
            origins.original_compound_seen_statement=true;
        }else if !item.children.is_empty()||(!starts_keyword(header,"return")&&!original_ordinary_call_header(header)&&!original_simple_assignment_candidate(header)&&!original_post_increment_candidate(header)&&!original_crash_statement_candidate(header)&&!local_statement&&!initial_setting
            && !(matches!(header, "break" | "continue") && origins.original_loop_control)){
            // The actual Original output can join a keyword directly to
            // punctuation or an interpolation token. Let parse_one's same
            // provider lookup settle this only for the otherwise unknown leaf.
            defer_joined_return = item.children.is_empty() && possible_joined_return(header);
            origins.require_original(defer_joined_return, item.header_span, "statement_head");
        }
        if !item.children.is_empty()
            && (header == "var" || (header.starts_with("var/") && !header.contains('=')))
        {
            origins
                .locals
                .decline("native local declaration blocks are outside pinned parser grammar");
            parse_var_block(
                &item.children,
                &format!("{}/", header.trim_end_matches('/')),
                diagnostics,
                &mut statements,
                origins.deferred_literal_purity,
            );
            index += 1;
            continue;
        }
        if local_statement {
            let (parts, lexical) = split_case_alternatives_with_tokens(header);
            let base =
                item.header_span.start + (header.as_ptr() as usize - item.header.as_ptr() as usize);
            origins.local_parts(
                header,
                &lexical,
                base,
                &parts,
                crate::LocalSourceKind::Statement,
            );
            if parts.len() > 1 {
                origins.require_original(false, item.header_span, "multiple_local_declarations");
                parse_var_parts(item, "", diagnostics, &mut statements,origins.deferred_literal_purity);
                index += 1;
                continue;
            }
            original_local_head = original_single_local_head(header, &lexical);
            if !original_local_head && header.starts_with("var/static/") && !header.contains('=') {
                match origins.settings.map(|provider| provider.original_uninitialized_static_local(item.header_span)).transpose() {
                    Ok(actual) => original_local_head = actual == Some(true),
                    Err(actual) => {
                        origins.original_compound_complete = false;
                        if let Some(admission) = diagnostics.admission {
                            admission.record_operational_error(actual);
                        }
                        break;
                    }
                }
            }
        }
        if starts_keyword(header, "if") {
            let mut end = index + 1;
            while items
                .get(end)
                .is_some_and(|next| starts_keyword(next.header.trim(), "else"))
            {
                end += 1;
            }
            statements.push(parse_if(item, &items[index + 1..end], diagnostics, origins, false));
            index = end;
            continue;
        }
        if header == "do" {
            if let Some(next) = items.get(index + 1).filter(|next| {
                starts_keyword(next.header.trim(), "while") && next.children.is_empty()
            }) {
                if let Some(condition) =
                    parse_control_condition_origin(next, "while", diagnostics, origins)
                {
                    let witnessed = control_inline(next, "while").is_none()
                        && next.header.trim_end().ends_with(')')
                        && original_indented_block_boundary(item, origins)
                        && original_linked_leaf_block(item, next, OriginalLeafBlockLink::DoWhile, origins);
                    origins.require_original(witnessed, next.header_span, "do_while_boundary");
                    let parent = std::mem::replace(&mut origins.original_loop_control, false);
                    let body = parse_sequence(&item.children, diagnostics, origins);
                    origins.original_loop_control = parent;
                    statements.push(Statement {
                        kind: StatementKind::DoWhile {
                            body,
                            condition,
                        },
                        span: Span::new(item.span.start, next.span.end),
                        header_span: item.header_span,
                        raw_header: item.header.clone(),
                    });
                } else {
                    statements.push(unsupported(item));
                }
                index += 2;
                continue;
            }
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "do requires a following while condition".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        if header == "try" {
            let Some(catch) = items.get(index + 1) else {
                diagnostics.push(Diagnostic {
                    span: item.header_span,
                    kind: DiagnosticKind::Statement,
                    message: "try requires catch".into(),
                });
                statements.push(unsupported(item));
                index += 1;
                continue;
            };
            let catch_header = catch.header.trim();
            let catch_binding = if catch_header == "catch" {
                Some(None)
            } else if catch_header.starts_with("catch(") && catch_header.ends_with(')') {
                Some(Some(
                    catch_header[6..catch_header.len() - 1].trim().to_owned(),
                ))
            } else {
                None
            };
            if let Some(catch_binding) = catch_binding {
                let before_catch=origins.locals.storage().len();
                if catch_binding
                    .as_ref()
                    .is_some_and(|binding| !binding.trim().is_empty())
                {
                    let source = catch_header[6..catch_header.len() - 1].trim();
                    let lexical = crate::lex_spans(source);
                    let base = catch.header_span.start
                        + (source.as_ptr() as usize - catch.header.as_ptr() as usize);
                    if lexical.diagnostics.is_empty(){origins.catch_parts(source,&lexical.tokens,base)}else{origins.locals.decline("native catch token grammar unavailable");}
                }
                let catch_parameter_count=origins.locals.storage().len()-before_catch;
                statements.push(Statement {
                    kind: StatementKind::Try {
                        body: parse_sequence(&item.children, diagnostics, origins),
                        catch_binding,
                        catch_parameter_count,
                        catch_header_span: catch.header_span,
                        catch_body: parse_sequence(&catch.children, diagnostics, origins),
                    },
                    span: Span::new(item.span.start, catch.span.end),
                    header_span: item.header_span,
                    raw_header: item.header.clone(),
                });
                index += 2;
                continue;
            }
            diagnostics.push(Diagnostic {
                span: catch.header_span,
                kind: DiagnosticKind::Statement,
                message: "try requires catch".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        if starts_keyword(header, "catch") {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "catch without try".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        if starts_keyword(header, "else") {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "else without preceding if".into(),
            });
            statements.push(unsupported(item));
            index += 1;
            continue;
        }
        let statement = parse_one(item, diagnostics, origins, original_local_head, defer_joined_return);
        if let Some(count) = root_prefix.as_deref_mut() {
            if original_initial_setting(&statement) {
                *count += 1;
            } else {
                root_prefix = None;
                origins.require_original(false, item.header_span, "initial_setting");
            }
        }
        statements.push(statement);
        index += 1;
    }
    statements
}

fn parse_if(
    item: &Item,
    else_items: &[Item],
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
    require_continuation_proof: bool,
) -> Statement {
    let condition = parse_control_condition_origin(item, "if", diagnostics, origins);
    let newly_composed = condition.as_ref().is_some_and(|value| match &value.kind {
        ExprKind::Unary { .. } | ExprKind::Binary { .. } | ExprKind::Group(_) => true,
        ExprKind::Call { callee, args } => !args.is_empty()
            || matches!(&callee.kind, ExprKind::Member { .. } | ExprKind::SafeMember { .. }),
        _ => false,
    });
    let inline = control_inline(item, "if");
    let mut require_next_proof = false;
    if newly_composed || require_continuation_proof {
        // A compatibility Item can attach children after an authored ';'.
        let opening = inline.is_none()
            && item.header.trim_end().ends_with(')')
            && original_indented_block_boundary(item, origins);
        let continuation = match else_items {
            [] => true,
            [next] if opening && next.header.trim() == "else" =>
                original_indented_block_boundary(next, origins)
                    && original_linked_leaf_block(item, next, OriginalLeafBlockLink::Else, origins),
            [next, ..] if opening && next.header.trim_start().strip_prefix("else")
                    .is_some_and(|rest| starts_keyword(rest.trim_start(), "if")) =>
                original_linked_leaf_block(item, next, OriginalLeafBlockLink::ElseIf, origins),
            _ => false,
        };
        let inline_leaf = else_items.is_empty() && item.children.is_empty()
            && condition.as_ref().zip(inline).is_some_and(|(condition, inline)| {
                let keyword = if starts_keyword(inline, "return") {
                    "return"
                } else if inline == "continue" && origins.original_loop_control {
                    "continue"
                } else {
                    return false;
                };
                let start = item.header_span.start
                    + (inline.as_ptr() as usize - item.header.as_ptr() as usize);
                let boundary = Span::new(condition.span.end, start + keyword.len());
                match origins.settings.map(|provider| provider.original_inline_if_leaf(boundary, keyword)).transpose() {
                    Ok(value) => value == Some(true),
                    Err(actual) => {
                        if let Some(admission) = origins.admission {
                            admission.record_operational_error(actual);
                        }
                        false
                    }
                }
            });
        let issued = (opening && continuation) || inline_leaf;
        origins.require_original(issued, item.header_span, "if_boundary");
        // A newly admitted multi-link chain must prove each following link,
        // even when a nested condition is in the older simple cohort.
        require_next_proof = issued && (require_continuation_proof || else_items.len() > 1);
    }
    let then_branch = control_body_from_inline(item, inline, diagnostics, origins);
    let mut span = item.span;
    let else_branch = if let Some((other, remaining)) = else_items.split_first() {
        span.end = else_items.last().unwrap().span.end;
        let header = other.header.trim();
        if header == "else" {
            for extra in remaining {
                diagnostics.push(Diagnostic {
                    span: extra.header_span,
                    kind: DiagnosticKind::Statement,
                    message: "duplicate else clause".into(),
                });
            }
            parse_sequence(&other.children, diagnostics, origins)
        } else if let Some(rest) = header.strip_prefix("else").map(str::trim_start) {
            if !starts_keyword(rest, "if") {
                // Native inline-else compatibility drops surplus clauses; that
                // is not a fully consumed Original source scope.
                origins.require_original(remaining.is_empty(), other.header_span, "else_chain");
                let mut inline = other.clone();
                inline.header = rest.trim_end_matches(';').into();
                inline.header_span.start += other.header.find(rest).unwrap_or(0);
                parse_sequence(&[inline], diagnostics, origins)
            } else {
                let mut nested = other.clone();
                nested.header = rest.into();
                nested.header_span.start += other.header.find(rest).unwrap_or(0);
                vec![parse_if(&nested, remaining, diagnostics, origins, require_next_proof)]
            }
        } else {
            diagnostics.push(Diagnostic {
                span: other.header_span,
                kind: DiagnosticKind::Unsupported,
                message: "unsupported else clause".into(),
            });
            vec![unsupported(other)]
        }
    } else {
        Vec::new()
    };
    match condition {
        Some(condition) => Statement {
            kind: StatementKind::If {
                condition,
                then_branch,
                else_branch,
            },
            span,
            header_span: item.header_span,
            raw_header: item.header.clone(),
        },
        None => unsupported(item),
    }
}

// Item.header excludes structural delimiters. A same-line explicit
// semicolon can disappear there before indentation attaches the next item.
// Admit only the exact source gap of the indented block we can prove.
fn original_indented_block_boundary(item: &Item, origins: &BodyOrigins<'_>) -> bool {
    let Some(first) = item.children.first() else { return false; };
    let gap = Span::new(item.header_span.end, first.header_span.start);
    if let Some(provider) = origins.settings {
        return match provider.original_statement_block_open(gap) {
            Ok(value) => value,
            Err(actual) => {
                if let Some(admission) = origins.admission {
                    admission.record_operational_error(actual);
                }
                false
            }
        };
    }
    let Some(gap) = origins.source.and_then(|source| source.get(gap.range())) else { return false; };
    gap.contains('\n') && gap.bytes().all(|byte| matches!(byte, b' ' | b'\t' | b'\r' | b'\n'))
}

fn original_linked_leaf_block(
    item: &Item, next: &Item, link: OriginalLeafBlockLink, origins: &BodyOrigins<'_>,
) -> bool {
    let Some(mut last) = item.children.last() else { return false };
    let mut closes = 1;
    while let Some(child) = last.children.last() {
        if matches!(link, OriginalLeafBlockLink::DoWhile) || closes == 32 {
            return false;
        }
        let header = last.header.trim();
        let indented_if = starts_keyword(header, "if") && header.ends_with(')')
            && control_inline(last, "if").is_none();
        let indented_else_if = header.strip_prefix("else").map(str::trim_start)
            .is_some_and(|tail| starts_keyword(tail, "if") && tail.ends_with(')')
                && control_inline_header(tail, "if").is_none());
        if !(indented_if || indented_else_if || header == "else")
            || !original_indented_block_boundary(last, origins)
        {
            return false;
        }
        closes += 1;
        last = child;
    }
    let tail = Span::new(last.header_span.end, next.header_span.start);
    match origins.settings.map(|provider| provider.original_leaf_block_link(tail, next.header_span, link, closes)).transpose() {
        Ok(value) => value == Some(true),
        Err(actual) => {
            if let Some(admission) = origins.admission {
                admission.record_operational_error(actual);
            }
            false
        }
    }
}

fn possible_joined_return(header: &str) -> bool {
    header.starts_with("return") && !starts_keyword(header, "return")
}

fn parse_one(
    item: &Item,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
    mut original_local_head: bool,
    defer_joined_return: bool,
) -> Statement {
    let header = item.header.trim();
    let joined_return = if possible_joined_return(header) {
        match origins.settings.map(|provider| provider.original_joined_return(item.header_span)).transpose() {
            Ok(value) => value.unwrap_or(false),
            Err(actual) => {
                origins.original_compound_complete = false;
                if let Some(admission) = diagnostics.admission {
                    admission.record_operational_error(actual);
                }
                return unsupported(item);
            }
        }
    } else {
        false
    };
    if defer_joined_return {
        origins.require_original(joined_return, item.header_span, "joined_return");
    }
    if crate::return_has_block(header, !item.children.is_empty())
        || (joined_return && !item.children.is_empty())
    {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Unsupported,
            message: crate::RETURN_BLOCK_UNSUPPORTED.into(),
        });
        return unsupported(item);
    }
    let kind = if starts_keyword(header, "while") {
        let inline = control_inline(item, "while");
        // Only the actual parenthesized control and its nonempty indented
        // block are witnessed. Inline/recovery tails cannot borrow the proof.
        let mut witnessed = inline.is_none() && header.ends_with(')')
            && original_indented_block_boundary(item, origins);
        let condition = parse_control_condition_observed(item, "while", diagnostics, &mut |parsed| {
            witnessed &= parsed.original_simple_expression.is_some_and(|value| {
                value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
            });
        });
        let issued = witnessed && condition.is_some();
        origins.require_original(issued, item.header_span, "while_control");
        condition.map(|condition| {
            let parent = std::mem::replace(&mut origins.original_loop_control, issued);
            let body = control_body_from_inline(item, inline, diagnostics, origins);
            origins.original_loop_control = parent;
            StatementKind::While { condition, body }
        })
    } else if starts_keyword(header, "for") {
        let boundary = control_inline(item, "for").is_none() && header.ends_with(')')
            && original_indented_block_boundary(item, origins);
        let mut original_control = false;
        let control = parse_for(item, diagnostics, origins, &mut original_control);
        origins.require_original(boundary && original_control, item.header_span, "for_control");
        control.map(|control| {
            let parent = origins.original_loop_control;
            origins.original_loop_control = boundary && original_control
                && matches!(&control, ForControl::Each { .. });
            let body = control_body(item, "for", diagnostics, origins);
            origins.original_loop_control = parent;
            StatementKind::For { control, body }
        })
    } else if starts_keyword(header, "switch") {
        let parsed = parse_switch(item, diagnostics, origins);
        origins.require_original(parsed.is_some(), item.header_span, "switch_control");
        parsed
    } else if starts_keyword(header, "spawn") {
        parse_spawn(item, diagnostics, origins)
    } else if starts_keyword(header, "set") {
        match origins.settings {
            Some(provider) => match provider.setting(item) {
                Ok(setting) => Some(StatementKind::ProjectedSet {
                    attribute: setting.attribute,
                    relation: setting.relation,
                    value: setting.value,
                }),
                Err(error) => {
                    diagnostics.push(error);
                    None
                }
            },
            None => parse_set(item, diagnostics),
        }
    } else if header == "return" {
        if origins.original_terminal_header==Some(item.header_span){*origins.original_grammar=Some(OriginalBodyGrammarOutcome{prefix_settings:0,scope_roots:None,kind:OriginalBodyGrammarKind::Available,statement:Some(item.header_span),expression:None,operator:None});}
        Some(StatementKind::Return(None))
    } else if starts_keyword(header, "return")
        || joined_return
        // Original joins the keyword to Super, then separates punctuation.
        || header.strip_prefix("return..").is_some_and(|tail| tail.trim_start().starts_with('('))
    {
        let rest = header.strip_prefix("return").unwrap().trim_start();
        let leading = item.header.len() - item.header.trim_start().len();
        let offset = item.header_span.start + leading + (header.len() - rest.len());
        parse_expr_observed(rest,offset,diagnostics,&mut|parsed|{
            use crate::expression_parser::OriginalSimpleKind;
            let issued = parsed.original_simple_expression.is_some_and(|value| {
                matches!(value.kind(), OriginalSimpleKind::Complete | OriginalSimpleKind::PlainAssignment)
            });
            origins.require_original(issued, Span::new(offset, offset + rest.len()), "return_expression");
            if origins.original_terminal_header==Some(item.header_span){if let Some(actual)=parsed.original_simple_expression{*origins.original_grammar=OriginalBodyGrammarOutcome::from_simple_return(actual,offset,item.header_span);}}
        }).map(|expr| StatementKind::Return(Some(expr)))
    } else if starts_keyword(header, "throw") {
        let rest = header.strip_prefix("throw").unwrap().trim_start();
        parse_expr(
            rest,
            item.header_span.start + (rest.as_ptr() as usize - item.header.as_ptr() as usize),
            diagnostics,
        )
        .map(StatementKind::Throw)
    } else if let Some(label) = header.strip_prefix("goto ") {
        Some(StatementKind::Goto(label.trim().into()))
    } else if let Some(label) = header.strip_suffix(':') {
        Some(StatementKind::Label {
            name: label.trim().into(),
            body: parse_sequence(&item.children, diagnostics, origins),
        })
    } else if matches!(header, "break" | "continue") {
        let keyword = if header == "break" { "break" } else { "continue" };
        if origins.original_loop_control && item.children.is_empty() {
            match origins.settings.map(|provider| provider.original_bare_loop_control(item.header_span, keyword)).transpose() {
                Ok(actual) => origins.require_original(actual == Some(true), item.header_span, "loop_control_terminator"),
                Err(actual) => {
                    origins.original_compound_complete = false;
                    if let Some(admission) = diagnostics.admission {
                        admission.record_operational_error(actual);
                    }
                    return unsupported(item);
                }
            }
        }
        Some(if keyword == "break" { StatementKind::Break } else { StatementKind::Continue })
    } else if let Some(label) = header.strip_prefix("break ") {
        Some(StatementKind::BreakLabel(label.trim().into()))
    } else if let Some(label) = header.strip_prefix("continue ") {
        Some(StatementKind::ContinueLabel(label.trim().into()))
    } else if header.starts_with("var/") || starts_keyword(header, "var") {
        let parsed = parse_var(item, diagnostics, origins.deferred_literal_purity, &mut original_local_head);
        let issued = original_local_head && parsed.is_some();
        origins.require_original(issued, item.header_span, "local_declaration_or_initializer");
        origins.original_compound_seen_statement |= issued;
        parsed
    } else if !item.children.is_empty() {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Unsupported,
            message: "unsupported statement block".into(),
        });
        None
    } else {
        let ordinary_call=original_ordinary_call_header(header);
        let assignment=original_simple_assignment_candidate(header);
        let increment=original_post_increment_candidate(header);
        let crash=original_crash_statement_candidate(header);
        parse_expr_observed(header,item.header_span.start,diagnostics,&mut|parsed|{
            if ordinary_call || assignment || increment || crash {
                use crate::expression_parser::OriginalSimpleKind;
                let issued=parsed.original_simple_expression.is_some_and(|actual|match actual.kind(){
                    OriginalSimpleKind::OrdinaryCallStatement=>ordinary_call,
                    OriginalSimpleKind::SimpleAssignmentStatement | OriginalSimpleKind::PlainAssignment=>assignment,
                    OriginalSimpleKind::PostIncrementStatement | OriginalSimpleKind::PostDecrementStatement=>increment,
                    OriginalSimpleKind::CrashStatement=>crash,
                    OriginalSimpleKind::Complete => ordinary_call && parsed.expr.as_ref().is_some_and(|expr| {
                        let ExprKind::Call { callee, .. } = &expr.kind else { return false; };
                        if matches!(&callee.kind, ExprKind::Ident(_)) {
                            return true;
                        }
                        if !actual.is_original() {
                            return false;
                        }
                        // Complete consumed all argument and member tokens.
                        // Keep this statement role to identifier-rooted dot paths.
                        let mut receiver = callee.as_ref();
                        while let ExprKind::Member { object, via_colon: false, .. } = &receiver.kind {
                            receiver = object;
                        }
                        matches!(&receiver.kind, ExprKind::Ident(_))
                    }),
                    OriginalSimpleKind::MissingArithmeticOperand=>false,
                });
                origins.require_original(issued, item.header_span, "statement_expression");
                origins.original_compound_seen_statement|=issued;
            }
        }).map(|expr| match expr.kind {
            ExprKind::Binary { op, lhs, rhs } if is_assignment(&op) => StatementKind::Assign {
                target: *lhs,
                op,
                value: *rhs,
            },
            ExprKind::Call { .. } => StatementKind::Call(expr),
            _ => StatementKind::Expression(expr),
        })
    };
    match kind {
        Some(kind) => Statement {
            kind,
            span: item.span,
            header_span: item.header_span,
            raw_header: item.header.clone(),
        },
        None => unsupported(item),
    }
}

// A routing filter only. The consuming expression parser certifies the
// actual callee, complete parentheses, argument roots and separator tokens.
fn original_ordinary_call_header(header:&str)->bool{
    let Some((name,_))=header.strip_suffix(')').and_then(|head|head.split_once('('))else{return false};
    name.trim_end().split('.').all(crate::expression_parser::original_ordinary_call_name)
}

// Route only names whose assignment-shaped statements reach the generic
// expression parser. Its consuming token/AST proof decides acceptance.
fn original_crash_statement_candidate(header: &str) -> bool {
    header.strip_prefix("CRASH")
        .is_some_and(|tail| tail.trim_start().starts_with('(') && tail.ends_with(')'))
}

fn original_post_increment_candidate(header: &str) -> bool {
    header.strip_suffix("++").or_else(|| header.strip_suffix("--"))
        .is_some_and(|target| {
            let target = target.trim_end();
            if crate::expression_parser::original_ordinary_call_name(target) { return true; }
            // DATA classifier only. The expression receipt checks the actual
            // issued one-dot receiver, operator and every child/root span.
            target.split_once('.').is_some_and(|(receiver, member)|
                crate::expression_parser::original_ordinary_call_name(receiver.trim_end())
                    && crate::expression_parser::original_ascii_identifier(member.trim_start()))
        })
}

fn original_simple_assignment_candidate(header: &str) -> bool {
    // Macro expansions may leave a single enclosing expression group.
    let header = header.strip_prefix('(').and_then(|inner| inner.strip_suffix(')'))
        .map_or(header, str::trim);
    let Some((target, _)) = header.split_once('=') else { return false; };
    let target = target.trim_end_matches(['+', '-', '*', '/', '%', '|', '&', '^', '<', '>']).trim();
    // DATA routing only: the expression witness checks the exact bare
    // Ident/list target and permitted assignment operator.
    if matches!(target, "." | "list") { return true; }
    let name = target.split(['.', '[']).next().unwrap_or(target).trim_end();
    crate::expression_parser::original_ordinary_call_name(name)
        && !matches!(name, "break" | "continue" | "goto")
}

fn parse_set(item: &Item, diagnostics: &mut BodyDiagnostics<'_>) -> Option<StatementKind> {
    let header = item.header.trim();
    let rest = header.strip_prefix("set")?.trim_start();
    let equals = rest.find('=');
    let inside = rest.find(" in ");
    let (attribute, relation, value) =
        if equals.is_some_and(|at| inside.is_none_or(|other| at < other)) {
            let at = equals.unwrap();
            (rest[..at].trim(), "=", rest[at + 1..].trim())
        } else if let Some(at) = inside {
            (rest[..at].trim(), "in", rest[at + " in ".len()..].trim())
        } else {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "expected set attribute = value or set attribute in value".into(),
            });
            return None;
        };
    if attribute.is_empty() || value.is_empty() {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Statement,
            message: "missing set attribute or value".into(),
        });
        return None;
    }
    let value = parse_expr(
        value,
        item.header_span.start + item.header.find(value).unwrap_or(0),
        diagnostics,
    )?;
    Some(StatementKind::Set {
        attribute: attribute.into(),
        relation: relation.into(),
        value,
    })
}

fn parse_spawn(
    item: &Item,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
) -> Option<StatementKind> {
    let header = item.header.trim();
    let rest = header.strip_prefix("spawn")?.trim_start();
    let (delay, inline) = if rest.is_empty() {
        (None, "")
    } else if let Some(open) = rest.strip_prefix('(') {
        let mut depth = 1usize;
        let mut quote = None;
        let mut escaped = false;
        let mut close = None;
        for (at, ch) in open.char_indices() {
            if escaped {
                escaped = false;
                continue;
            }
            if ch == '\\' {
                escaped = true;
                continue;
            }
            if let Some(delimiter) = quote {
                if ch == delimiter {
                    quote = None;
                }
                continue;
            }
            match ch {
                '\'' | '"' => quote = Some(ch),
                '(' => depth += 1,
                ')' => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(at);
                        break;
                    }
                }
                _ => {}
            }
        }
        let Some(close) = close else {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Statement,
                message: "unclosed spawn delay".into(),
            });
            return None;
        };
        (Some(open[..close].trim()), open[close + 1..].trim())
    } else {
        (None, rest)
    };
    let delay = match delay.filter(|delay| !delay.is_empty()) {
        Some(delay) => Some(parse_expr(
            delay,
            item.header_span.start + item.header.find(delay).unwrap_or(0),
            diagnostics,
        )?),
        None => None,
    };
    let body = if inline.is_empty() {
        parse_sequence(&item.children, diagnostics, origins)
    } else {
        let mut inline_item = item.clone();
        inline_item.header = inline.into();
        inline_item.header_span.start += item.header.find(inline).unwrap_or(0);
        parse_sequence(&[inline_item], diagnostics, origins)
    };
    Some(StatementKind::Spawn { delay, body })
}

fn parse_var_block(
    items: &[Item],
    prefix: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
    statements: &mut Vec<Statement>,
    deferred_literal_purity:bool,
) {
    for item in items {
        let header = item.header.trim();
        if !item.children.is_empty() {
            if !header.is_empty()
                && header.split('/').all(|part| {
                    !part.is_empty()
                        && part
                            .bytes()
                            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
                })
            {
                parse_var_block(
                    &item.children,
                    &format!("{prefix}{header}/"),
                    diagnostics,
                    statements,
                    deferred_literal_purity,
                );
            } else {
                diagnostics.push(Diagnostic {
                    span: item.header_span,
                    kind: DiagnosticKind::Unsupported,
                    message: "unsupported local declaration group".into(),
                });
            }
        } else {
            let parts = split_case_alternatives(header);
            if parts.len() > 1 {
                let comma = item.header.find(parts[0]).unwrap_or(0) + parts[0].len();
                let comma = item.header[comma..].find(',').map(|at| comma + at).unwrap();
                diagnostics.push(Diagnostic {
                    span: Span::new(
                        item.header_span.start + comma,
                        item.header_span.start + comma + 1,
                    ),
                    kind: DiagnosticKind::InvalidDeclarationGroup,
                    message: ",: expected }".into(),
                });
            } else {
                parse_var_parts(item, prefix, diagnostics, statements,deferred_literal_purity);
            }
        }
    }
}

fn parse_var_parts(
    item: &Item,
    prefix: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
    statements: &mut Vec<Statement>,
    deferred_literal_purity:bool,
) {
    let header = item.header.trim();
    let parts = split_case_alternatives(header);
    let first_decl = parts[0].split('=').next().unwrap().trim();
    let combined = format!("{prefix}{first_decl}");
    let inherited = combined
        .rsplit_once('/')
        .map(|(base, _)| format!("{base}/"))
        .unwrap_or_else(|| "var ".into());
    let mut consumed = 0;
    for (index, part) in parts.into_iter().enumerate() {
        let part = part.trim();
        let Some(relative) = item.header[consumed..].find(part) else {
            diagnostics.push(Diagnostic {
                span: item.header_span,
                kind: DiagnosticKind::Unsupported,
                message: "local declaration occurrence unavailable".into(),
            });
            return;
        };
        let at = consumed + relative;
        consumed = at + part.len();
        let mut leaf = item.clone();
        leaf.header = part.into();
        leaf.header_span = Span::new(
            item.header_span.start + at,
            item.header_span.start + at + part.len(),
        );
        leaf.span = leaf.header_span;
        let prefix = if index == 0 { prefix } else { &inherited };
        if let Some(kind) = parse_var_header(&leaf, prefix, diagnostics,deferred_literal_purity,None) {
            statements.push(Statement {
                kind,
                span: leaf.span,
                header_span: leaf.header_span,
                raw_header: leaf.header,
            });
        }
    }
}

// Reuse the lexical window that issued the local-source receipt. Only the
// plain slash path is witnessed here. Modifiers, arrays and grouped locals
// need their own Original grammar evidence.
fn original_single_local_head(header: &str, lexical: &crate::SpannedLexed) -> bool {
    use crate::TokenKind;
    if !lexical.diagnostics.is_empty() { return false; }
    let mut tokens = lexical.tokens.iter().filter(|token| {
        !matches!(token.kind, TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment)
    });
    if !tokens.next().is_some_and(|token| token.kind == TokenKind::Ident && token.text(header) == "var") {
        return false;
    }
    for component in 0..16 {
        let Some(slash) = tokens.next() else { return component != 0; };
        if slash.text(header) == "=" { return component != 0; }
        if slash.text(header) != "/" { return false; }
        let Some(name) = tokens.next() else { return false; };
        let text = name.text(header);
        if name.kind != TokenKind::Ident
            || !crate::expression_parser::original_ascii_identifier(text)
            || matches!(text, "const" | "global" | "static" | "tmp" | "final")
        {
            return false;
        }
    }
    false
}

fn parse_var(item: &Item, diagnostics: &mut BodyDiagnostics<'_>,deferred_literal_purity:bool,original_head:&mut bool) -> Option<StatementKind> {
    if let Some(child) = item.children.first() {
        // A block indented under an initialized `var/name = value` is never
        // DM; the statement lowerer reports DreamMaker's error.
        diagnostics.push(Diagnostic {
            span: child.header_span,
            kind: DiagnosticKind::Unsupported,
            message: "statement block under a variable declaration".into(),
        });
        return None;
    }
    parse_var_header(item, "", diagnostics,deferred_literal_purity,Some(original_head))
}
fn parse_var_header(
    item: &Item,
    prefix: &str,
    diagnostics: &mut BodyDiagnostics<'_>,
    deferred_literal_purity:bool,
    mut original_head: Option<&mut bool>,
) -> Option<StatementKind> {
    let header = item.header.trim();
    let assignment = crate::local_variable_syntax::top_level_local_assignment(header);
    let declaration = format!(
        "{prefix}{}",
        header[..assignment.unwrap_or(header.len())].trim()
    );
    let name = declaration
        .strip_prefix("var/")
        .or_else(|| declaration.strip_prefix("var "))
        .or_else(|| declaration.strip_prefix("var\t"))
        .map(str::trim);
    if name.is_none_or(str::is_empty) {
        diagnostics.push(Diagnostic {
            span: item.header_span,
            kind: DiagnosticKind::Statement,
            message: "missing local variable name".into(),
        });
        return None;
    }
    let value = if let Some(at) = assignment {
        let source = header[at + 1..].trim();
        let offset =
            item.header_span.start + (source.as_ptr() as usize - item.header.as_ptr() as usize);
        let parsed = parse_expr_observed(source, offset, diagnostics, &mut |parsed| {
            if let Some(proof) = original_head.as_deref_mut() {
                *proof &= parsed.original_simple_expression.is_some_and(|value| {
                    use crate::expression_parser::OriginalSimpleKind;
                    // Real Original positional calls are Complete. Its
                    // statement-only keyed calls must not prove a local RHS.
                    value.kind() == OriginalSimpleKind::Complete
                        || (!value.is_original() && value.kind() == OriginalSimpleKind::OrdinaryCallStatement)
                });
            }
        })?;
        // `in` binds looser than `=` in DreamMaker, so `var/x = a in L` is `(var/x = a) in L`: the local gets `a`, and a
        // membership test whose result nobody reads (and that has no effect) is dropped.
        if !deferred_literal_purity && pure_local_membership(&parsed,None){
            let ExprKind::Binary{lhs,..}=parsed.kind else{unreachable!()};Some(*lhs)
        }else{Some(parsed)}
    } else {
        None
    };
    Some(StatementKind::Var { declaration, value })
}

fn parse_switch(
    item: &Item,
    diagnostics: &mut BodyDiagnostics<'_>,
    origins: &mut BodyOrigins<'_>,
) -> Option<StatementKind> {
    let header = item.header.trim();
    let mut witnessed = header.ends_with(')') && control_inline(item, "switch").is_none()
        && original_indented_block_boundary(item, origins);
    let mut inline_decimal_returns = false;
    let mut needs_case_cursor = false;
    let mut has_inline_case = false;
    let selector = parse_control_condition_observed(item, "switch", diagnostics, &mut |parsed| {
        inline_decimal_returns = matches!(parsed.expr.as_ref().map(|value| &value.kind),
            Some(ExprKind::Call { callee, args })
                if matches!(&callee.kind, ExprKind::Ident(name) if name == "length")
                    && matches!(args.as_slice(), [arg] if matches!(&arg.kind, ExprKind::Ident(name) if name == "input")));
        let previous_selector = inline_decimal_returns
            || matches!(parsed.expr.as_ref().map(|value| &value.kind), Some(ExprKind::Ident(_)));
        needs_case_cursor |= !previous_selector;
        witnessed &= parsed.original_simple_expression.is_some_and(|value| {
            value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
                && (previous_selector || value.is_original())
        });
    })?;
    let mut cases = Vec::new();
    let mut else_branch = Vec::new();
    let mut default_present=false;
    let mut index=0usize;
    while index<item.children.len(){
        if origins.admission.is_some_and(|admission|admission.checkpoint().is_err()){return None}
        let case=&item.children[index];
        let header = case.header.trim();
        if starts_keyword(header, "else") {
            witnessed &= index + 1 == item.children.len();
            default_present=true;
            if index + 1 != item.children.len() {
                diagnostics.push(Diagnostic {
                    span: case.header_span,
                    kind: DiagnosticKind::Statement,
                    message: "switch else must be final".into(),
                });
            }
            let inline = header
                .strip_prefix("else")
                .unwrap()
                .trim()
                .trim_end_matches(';')
                .trim();
            has_inline_case |= !inline.is_empty();
            else_branch = if inline.is_empty() {
                parse_sequence(&case.children, diagnostics, origins)
            } else {
                let mut nested = case.clone();
                nested.header = inline.into();
                nested.header_span.start += inline.as_ptr() as usize - case.header.as_ptr() as usize;
                nested.span.start = nested.header_span.start;
                parse_sequence(&[nested], diagnostics, origins)
            };
            witnessed &= if inline.is_empty() {
                header == "else" && original_indented_block_boundary(case, origins)
            } else {
                inline_decimal_returns && case.children.is_empty()
                    && matches!(else_branch.as_slice(), [statement] if matches!(&statement.kind, StatementKind::Return(Some(_))))
            };
            index+=1;
            continue;
        }
        let clause = control_clause(case, "if", diagnostics)?;
        let base = case.header_span.start + (clause.as_ptr() as usize - case.header.as_ptr() as usize);
        let offset_of = |part: &str| base + (part.as_ptr() as usize - clause.as_ptr() as usize);
        let mut alternatives = Vec::new();
        let alternatives_source = split_case_alternatives(clause.trim_end().strip_suffix(',').unwrap_or(clause));
        needs_case_cursor |= alternatives_source.len() != 1;
        witnessed &= !clause.trim_end().ends_with(',');
        for alternative in alternatives_source {
            let alternative = alternative.trim();
            let offset = offset_of(alternative);
            if let Some((lower, upper)) = split_top_level_keyword(alternative, "to") {
                needs_case_cursor = true;
                let lower = lower.trim();
                let upper = upper.trim();
                let lower = parse_expr_observed(lower, offset_of(lower), diagnostics, &mut |parsed| {
                    witnessed &= parsed.original_simple_expression.is_some_and(|value| {
                        value.is_original()
                            && value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
                    });
                })?;
                let upper = parse_expr_observed(upper, offset_of(upper), diagnostics, &mut |parsed| {
                    witnessed &= parsed.original_simple_expression.is_some_and(|value| {
                        value.is_original()
                            && value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
                    });
                })?;
                alternatives.push(SwitchAlternative::Range(lower, upper));
            } else {
                alternatives.push(SwitchAlternative::Exact(parse_expr_observed(
                    alternative,
                    offset,
                    diagnostics,
                    &mut |parsed| {
                        let decimal = matches!(parsed.expr.as_ref().map(|value| &value.kind),
                            Some(ExprKind::Literal(value)) if crate::expression_parser::original_decimal(value.as_str()));
                        needs_case_cursor |= !decimal;
                        witnessed &= parsed.original_simple_expression.is_some_and(|value| {
                            value.kind() == crate::expression_parser::OriginalSimpleKind::Complete
                                && (decimal || value.is_original())
                        });
                    },
                )?));
            }
        }
        if alternatives.is_empty() {
            diagnostics.push(Diagnostic {
                span: case.header_span,
                kind: DiagnosticKind::Statement,
                message: "empty switch case".into(),
            });
            return None;
        }
        // The original one-line body is parsed by the same sequence core.
        // Borrow following else/catch/while rows rather than cloning a roster.
        let mut next=index+1;
        let inline=control_inline(case,"if");
        has_inline_case |= inline.is_some();
        if inline.is_none() {
            witnessed &= header.ends_with(')') && original_indented_block_boundary(case, origins);
        }
        if let Some(inline)=inline{
            if starts_keyword(inline,"if"){while let Some(other)=item.children.get(next).filter(|next|starts_keyword(next.header.trim(),"else")){if origins.admission.is_some_and(|admission|admission.checkpoint().is_err()){return None}let continuation=other.header.trim().strip_prefix("else").unwrap_or("").trim_start();next+=1;if !starts_keyword(continuation,"if"){break}}}
            else if inline=="try"&&item.children.get(next).is_some_and(|next|starts_keyword(next.header.trim(),"catch")){next+=1;}
            else if inline=="do"&&item.children.get(next).is_some_and(|next|starts_keyword(next.header.trim(),"while")&&next.children.is_empty()){next+=1;}
        }
        let body=if let Some(inline)=inline{let mut nested=case.clone();nested.header=inline.into();nested.header_span.start+=inline.as_ptr() as usize-case.header.as_ptr() as usize;nested.span.start=nested.header_span.start;parse_sequence_first(&item.children[index..next],Some(&nested),diagnostics,origins,None)}else{control_body_from_inline(case,None,diagnostics,origins)};
        if inline.is_some() {
            witnessed &= inline_decimal_returns && next == index + 1 && case.children.is_empty()
                && matches!(body.as_slice(), [statement] if matches!(&statement.kind, StatementKind::Return(Some(_))));
        }
        cases.push(SwitchCase {
            original_site:OriginalCaseSite{
                header:case.header_span,body:case.span,
                cursor:origins.settings.map_or(Err("original switch block cursor provider unavailable"),|provider|provider.switch_case_cursor(case)),
            },
            alternatives,
            body,
        });
        index=next;
    }
    // Newly admitted alternatives may emit case-positioned diagnostics. Their
    // existing Original cursor must come from this body's consumed token tape.
    // Inline bodies retain the preceding narrow length(input)/decimal proof.
    witnessed &= !needs_case_cursor || (!has_inline_case
        && cases.iter().all(|case| case.original_site.cursor.is_ok()));
    origins.require_original(witnessed && !cases.is_empty(), item.header_span, "switch_cases");
    Some(StatementKind::Switch {
        selector,
        cases,
        else_branch,
        default_present,
    })
}

#[path = "statement_controls.rs"]
mod statement_controls;
use statement_controls::*;

#[cfg(test)]
mod tests {
    include!("statements_tests_1.rs");
}

/// An expression that only names and builds values: evaluating it changes nothing.
fn is_effect_free(expr:&Expr)->bool{is_effect_free_using(expr,None)}
fn is_effect_free_using(expr: &Expr,admission:Option<&crate::SettingAdmission<'_>>) -> bool {
    let _frame=match admission.map(|a|a.parser_frame()).transpose(){Ok(frame)=>frame,Err(_)=>return false};
    match &expr.kind {
        ExprKind::Literal(text) => text.parts().is_ok_and(|parts| {
            parts.is_none_or(|parts| parts.expressions.iter().all(|e|is_effect_free_using(e,admission)))
        }),
        ExprKind::Ident(_) | ExprKind::TypePath(_) => true,
        ExprKind::Group(inner) => is_effect_free_using(inner,admission),
        ExprKind::Member {
            object,
            via_colon: false,
            ..
        } => is_effect_free_using(object,admission),
        ExprKind::Unary { op, value } => {
            matches!(op.as_str(), "-" | "!" | "~") && is_effect_free_using(value,admission)
        }
        ExprKind::Binary { op, lhs, rhs } => {
            matches!(
                op.as_str(),
                "+" | "-"
                    | "*"
                    | "/"
                    | "%"
                    | "|"
                    | "&"
                    | "^"
                    | "=="
                    | "!="
                    | "<"
                    | ">"
                    | "<="
                    | ">="
            ) && is_effect_free_using(lhs,admission)
                && is_effect_free_using(rhs,admission)
        }
        ExprKind::Call { callee, args } => {
            matches!(&callee.kind, ExprKind::Ident(name) if name == "list")
                && args.iter().all(|e|is_effect_free_using(e,admission))
        }
        _ => false,
    }
}

fn pure_local_membership(expr:&Expr,a:Option<&crate::SettingAdmission<'_>>)->bool{
 let ExprKind::Binary{op,rhs,..}=&expr.kind else{return false};
 op=="in"&&matches!(&rhs.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="list"))&&match a{Some(a)=>is_effect_free_using(rhs,Some(a)),None=>is_effect_free(rhs)}
}
/// Same local-declaration normalization, delayed ONLY in the admitted body mode
/// so the classifier borrows canonical literal children instead of parsing early.
pub(crate) fn complete_body_literal_normalization(parsed:&mut ParsedBody,a:&crate::SettingAdmission<'_>)->std::io::Result<()>{
 let mut pending=crate::admitted_worklist::Worklist::new(a)?;pending.extend(parsed.statements.iter_mut())?;
 while let Some(st)=pending.pop(){
  a.checkpoint()?;
  match &mut st.kind{
   StatementKind::Var{value,..}=>{
    if value.as_ref().is_some_and(|e|pure_local_membership(e,Some(a))){
     let Expr{kind:ExprKind::Binary{lhs,rhs,..},..}=value.take().unwrap() else{unreachable!()};
     *value=Some(*lhs);crate::setting_drop::drop_expression(*rhs,None);
    }
    a.checkpoint()?;
   }
   StatementKind::If{then_branch,else_branch,..}=>{pending.extend(then_branch.iter_mut())?;pending.extend(else_branch.iter_mut())?;},
   StatementKind::While{body,..}|StatementKind::DoWhile{body,..}|StatementKind::Spawn{body,..}|StatementKind::For{body,..}|StatementKind::Label{body,..}=>pending.extend(body.iter_mut())?,
   StatementKind::Try{body,catch_body,..}=>{pending.extend(body.iter_mut())?;pending.extend(catch_body.iter_mut())?;},
   StatementKind::Switch{cases,else_branch,..}=>{for case in cases{pending.extend(case.body.iter_mut())?;}pending.extend(else_branch.iter_mut())?;},
   _=>(),
  }
 }
 Ok(())
}
/// Whole native body request only: the opaque return exposes no intermediate
/// unnormalized ParsedBody. Source/code authority remains the caller's receipt.
pub fn parse_body_items_with_admitted_literals(
 items:&[Item],source:&str,context:&dyn Fn(usize)->Option<ItemKind>,settings:&dyn SettingSyntaxProvider,
 admission:&crate::SettingAdmission<'_>,cleanup:crate::SettingRootLease,
)->std::io::Result<crate::PreparedBodyLiteralSyntax>{
 let mut parsed=parse_body_items_using_settings(items,Some(settings),Some(admission),Some(source),true);
 if !admission.is_stopped(){parsed.pending_bodies=crate::pending_body::pending_bodies(&parsed.statements,source,context);}
 crate::prepare_body_literal_syntax(parsed,cleanup,admission)
}

#[cfg(test)]
#[test]
fn switch_and_throw_spans_keep_their_exact_borrowed_occurrences() {
    let source = concat!(
        "/proc/probe(w, x)\n",
        "    switch(x)\n",
        "        if(\"x\", x)\n",
        "            return x\n",
        "        if(1 to 1)\n",
        "            throw w\n",
    );
    let tree = crate::parse(source);
    let body = parse_proc_body(&tree.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let StatementKind::Switch { cases, .. } = &body.statements[0].kind else {
        panic!("expected switch");
    };
    let SwitchAlternative::Exact(value) = &cases[0].alternatives[1] else {
        panic!("expected exact second alternative");
    };
    let value_at = source.find("\"x\", x)").unwrap() + 5;
    assert_eq!(value.span, Span::new(value_at, value_at + 1));
    let SwitchAlternative::Range(lower, upper) = &cases[1].alternatives[0] else {
        panic!("expected range");
    };
    let lower_at = source.find("1 to 1").unwrap();
    assert_eq!(lower.span, Span::new(lower_at, lower_at + 1));
    assert_eq!(upper.span, Span::new(lower_at + 5, lower_at + 6));
    let StatementKind::Throw(value) = &cases[1].body[0].kind else {
        panic!("expected throw");
    };
    let thrown_at = source.find("throw w").unwrap() + "throw ".len();
    assert_eq!(value.span, Span::new(thrown_at, thrown_at + 1));
}

#[cfg(test)]mod original_catch_parameters{
 use super::*;
 #[test]fn primary_catch_parameter_count_and_original_rows_come_from_every_tree_path(){let source="/proc/probe()\n    try\n        var/not_a_parameter=1\n        return 0\n    catch(var/datum/a,var/b,)\n        return b\n";let syntax=crate::parse(source);assert!(syntax.diagnostics.is_empty());let parsed=parse_body_items(&syntax.items[0].children);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let StatementKind::Try{catch_parameter_count,catch_header_span,..}=&parsed.statements[0].kind else{panic!("same native Try")};assert_eq!(*catch_parameter_count,2);let facts=parsed.local_variables.in_span(*catch_header_span).unwrap();assert_eq!(facts.len(),2);assert!(facts.iter().all(|fact|fact.source_kind==crate::LocalSourceKind::CatchBinding));assert_eq!(source.get(facts[0].name.range()),Some("a"));assert_eq!(source.get(facts[1].name.range()),Some("b"));assert_eq!(facts[0].type_path(source).unwrap().as_deref(),Some("/datum"));assert_eq!(facts[1].type_path(source).unwrap(),None);}
 #[test]fn primary_catch_zero_single_and_invalid_suffixes_do_not_invent_extra_rows(){for(binding,count)in[("",0),("var/a",1),("var/a,",1)]{let source=format!("/proc/probe()\n    try\n        return 0\n    catch({binding})\n        return 1\n");let syntax=crate::parse(&source);let parsed=parse_body_items(&syntax.items[0].children);let StatementKind::Try{catch_parameter_count,..}=parsed.statements[0].kind else{panic!("native Try")};assert_eq!(catch_parameter_count,count);}for binding in["var/a=1","var a",",var/a","var/a,,var/b"]{let source=format!("/proc/probe()\n    try\n        return 0\n    catch({binding})\n        return 1\n");let syntax=crate::parse(&source);let parsed=parse_body_items(&syntax.items[0].children);assert!(parsed.local_variables.entries().is_err(),"invalid catch path admitted: {binding}");}}
}

#[cfg(test)]mod original_inline_switch_else{
 use super::*;
 #[test]fn original_inline_case_if_owns_following_else_chain_before_the_next_case(){let source="/proc/probe(value)\n    switch(value)\n        if(1 || 2) if(value)\n            return 0\n        else if(value == 2)\n            return 1\n        else\n            return 2\n        if(3)\n            return 3\n";let syntax=crate::parse(source);assert!(syntax.diagnostics.is_empty(),"{:?}",syntax.diagnostics);let parsed=parse_body_items(&syntax.items[0].children);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let StatementKind::Switch{cases,else_branch,..}=&parsed.statements[0].kind else{panic!("actual switch")};assert_eq!(cases.len(),2);assert!(else_branch.is_empty());let StatementKind::If{then_branch,else_branch,..}=&cases[0].body[0].kind else{panic!("actual inner if")};assert!(matches!(then_branch[0].kind,StatementKind::Return(_)));let StatementKind::If{then_branch,else_branch,..}=&else_branch[0].kind else{panic!("actual else-if")};assert!(matches!(then_branch[0].kind,StatementKind::Return(_)));assert!(matches!(else_branch[0].kind,StatementKind::Return(_)));assert!(matches!(cases[1].body[0].kind,StatementKind::Return(_)));}
}

#[cfg(test)]mod original_inline_switch_outer_default{use super::*;#[test]fn actual_final_else_remains_distinct_from_following_switch_default(){let source="/proc/probe(value)\n    switch(value)\n        if(1 || 2) if(value)\n            return 0\n        else\n            return 1\n        else\n            return 2\n";let syntax=crate::parse(source);assert!(syntax.diagnostics.is_empty());let parsed=parse_body_items(&syntax.items[0].children);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let StatementKind::Switch{cases,else_branch,..}=&parsed.statements[0].kind else{panic!("actual switch")};assert_eq!(cases.len(),1);assert!(matches!(else_branch[0].kind,StatementKind::Return(_)));let StatementKind::If{else_branch,..}=&cases[0].body[0].kind else{panic!("actual inner if")};assert!(matches!(else_branch[0].kind,StatementKind::Return(_)));}}

#[cfg(test)]mod inline_control_primary_offset{use super::*;#[test]fn actual_inline_tail_offset_does_not_match_equal_text_inside_the_condition(){let source="/proc/probe(value)\n    if(value == \"return 1\") return 1\n";let syntax=crate::parse(source);assert!(syntax.diagnostics.is_empty());let parsed=parse_body_items(&syntax.items[0].children);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let StatementKind::If{then_branch,..}=&parsed.statements[0].kind else{panic!("actual if")};let tail=source.rfind("return 1").unwrap();assert_eq!(then_branch[0].header_span.start,tail);assert_eq!(then_branch[0].span.start,tail);assert!(matches!(then_branch[0].kind,StatementKind::Return(_)));}}

/// Opaque actual grammar result from the SAME statement/expression producer.
/// It is not the old Sem option, a CODE EOF witness or a current body grant.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub struct OriginalBodyGrammarOutcome{prefix_settings:usize,scope_roots:Option<usize>,kind:OriginalBodyGrammarKind,statement:Option<Span>,expression:Option<Span>,operator:Option<Span>}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalBodyGrammarKind{Available,SkippedMissingSimpleOperand}
impl OriginalBodyGrammarOutcome{
 pub fn scope_roots(self)->Option<usize>{self.scope_roots}
 fn from_simple_return(actual:crate::expression_parser::OriginalSimpleExpression,offset:usize,statement:Span)->Option<Self>{
  let shift=|span:Span|Some(Span::new(span.start.checked_add(offset)?,span.end.checked_add(offset)?));
  let expression=shift(actual.span())?;let operator=match actual.operator(){Some(span)=>Some(shift(span)?),None=>None};
  if expression.start<statement.start||expression.end>statement.end{return None}
  Some(Self{prefix_settings:0,scope_roots:None,kind:match actual.kind(){crate::expression_parser::OriginalSimpleKind::Complete|crate::expression_parser::OriginalSimpleKind::PlainAssignment=>OriginalBodyGrammarKind::Available,crate::expression_parser::OriginalSimpleKind::OrdinaryCallStatement|crate::expression_parser::OriginalSimpleKind::SimpleAssignmentStatement|crate::expression_parser::OriginalSimpleKind::PostIncrementStatement|crate::expression_parser::OriginalSimpleKind::PostDecrementStatement|crate::expression_parser::OriginalSimpleKind::CrashStatement=>return None,crate::expression_parser::OriginalSimpleKind::MissingArithmeticOperand=>OriginalBodyGrammarKind::SkippedMissingSimpleOperand},statement:Some(statement),expression:Some(expression),operator})
 }
 pub fn prefix_settings(self)->usize{self.prefix_settings}
 pub fn kind(self)->OriginalBodyGrammarKind{self.kind}
 pub fn statement_span(self)->Option<Span>{self.statement}
 pub fn expression_span(self)->Option<Span>{self.expression}
 pub fn operator_span(self)->Option<Span>{self.operator}
}

#[cfg(test)]mod original_body_outcome_tests{
 use super::*;
 fn outcome(text:&str)->ParsedBody{let parsed=crate::parse(&format!("/proc/probe(argument)\n{text}"));parse_proc_body(&parsed.items[0])}
 #[test]fn actual_original_available_body_provenance_is_closed_over_empty_void_simple_and_member_return(){
  for text in["","    return\n","    return 1\n","    return argument\n","    return argument + 1\n","    return argument.field\n","    return list(argument)\n"]{let body=outcome(text);assert!(body.diagnostics.is_empty(),"{text}: {:?}",body.diagnostics);assert_eq!(body.original_grammar.unwrap().kind(),OriginalBodyGrammarKind::Available,"{text}");}
 }
 #[test]
 fn original_return_list_witness_requires_exact_positional_arguments_and_nested_derived_shape() {
  for expression in [
    "list(mutable, value)",
    "list(drawn_from(nameof(value), rel(nameof(link), nameof(/datum/foreign::far))))",
  ] {
    let syntax = crate::parse(&format!("/proc/probe(mutable, value)\n    return {expression}\n"));
    let body = parse_proc_body(&syntax.items[0]);
    assert!(body.diagnostics.is_empty(), "{expression}: {:?}", body.diagnostics);
    assert_eq!(body.original_grammar.unwrap().kind(), OriginalBodyGrammarKind::Available);
  }
  for expression in [
    "list(mutable = value, value)",
    "list(mutable,)",
    "list(mutable, choose())",
    "list(other(nameof(value), rel(nameof(link), nameof(/datum/foreign::far))))",
    "list(drawn_from(nameof(value), rel(nameof(link), nameof(argument.far))))",
    "list(drawn_from(nameof(value), rel(nameof(link), nameof(/datum/foreign::far))), value)",
  ] {
    let syntax = crate::parse(&format!("/proc/probe(mutable, value)\n    return {expression}\n"));
    let body = parse_proc_body(&syntax.items[0]);
    assert!(body.original_grammar.is_none(), "unwitnessed {expression}");
  }
 }
 #[test]fn original_string_index_witness_requires_consumed_simple_receiver_key_and_delimiters(){
  let body=outcome("    return vars[\"probe\"]\n");
  let proof=body.original_grammar.unwrap();
  assert_eq!(proof.kind(),OriginalBodyGrammarKind::Available);
  let StatementKind::Return(Some(expr))=&body.statements[0].kind else{panic!("actual index return")};
  assert!(matches!(&expr.kind,ExprKind::Index{..}));
  assert_eq!(proof.expression_span(),Some(expr.span));
  for text in [
   "    return vars[\"probe\"\n",
   "    return vars?[\"probe\"]\n",
   "    return vars[\"probe key\"]\n",
   "    return vars[\"[probe]\"]\n",
   "    return vars[\"probe\"][\"next\"]\n",
   "    return vars[probe]\n",
  ]{assert!(outcome(text).original_grammar.is_none(),"unissued {text}");}
 }
 #[test]fn actual_original_missing_operand_receipt_comes_from_pratt_consumption_branch(){
  for text in["    return 1 +\n","    return argument *\n","    return\targument +\n","    return   argument +\n"]{let body=outcome(text);let proof=body.original_grammar.unwrap();assert_eq!(proof.kind(),OriginalBodyGrammarKind::SkippedMissingSimpleOperand);assert!(proof.operator_span().is_some());assert!(!body.diagnostics.is_empty());assert!(matches!(&body.statements[0].kind,StatementKind::Unsupported));assert_eq!(proof.statement_span(),Some(body.statements[0].header_span));}
 }
 #[test]fn unsupported_original_body_grammar_and_other_native_diagnostics_do_not_mint_skipped(){
  for text in["    return (1 +)\n","    throw\n","    goto\n","    return argument:field\n","    return 1\n    return 2\n"]{assert!(outcome(text).original_grammar.is_none(),"unissued {text}");}
 }
}

// Closed profile over SAME actual parsed native expressions, never a reparse,
// evaluation or blanket native-acceptance-to-old-Some inference.
fn original_setting_leaf(expr:&Expr)->bool{match &expr.kind{ExprKind::Ident(name)=>crate::expression_parser::original_ascii_identifier(name),ExprKind::Literal(text)=>text.as_str()=="null"||crate::expression_parser::original_decimal(text.as_str()),ExprKind::TypePath(path)=>path.starts_with('/')&&path.split('/').skip(1).all(crate::expression_parser::original_ascii_identifier),_=>false}}
fn original_setting_receiver(expr:&Expr)->bool{original_setting_leaf(expr)||matches!(&expr.kind,ExprKind::Index{object,index}if original_setting_leaf(object)&&original_setting_leaf(index))}
fn original_setting_expression(expr:&Expr)->bool{original_setting_leaf(expr)||match &expr.kind{ExprKind::Member{object,selector,via_colon:false}=>original_setting_receiver(object)&&crate::expression_parser::original_ascii_identifier(selector),ExprKind::Index{object,index}=>original_setting_leaf(object)&&original_setting_leaf(index),ExprKind::Binary{op,lhs,rhs}=>matches!(op.as_str(),"+"|"-"|"*"|"/"|"%"|"||"|"&&")&&original_setting_leaf(lhs)&&original_setting_leaf(rhs),_=>false}}
fn original_initial_setting(row:&Statement)->bool{match &row.kind{StatementKind::Set{attribute,relation,value}=>crate::expression_parser::original_ascii_identifier(attribute)&&matches!(relation.as_str(),"="|"in")&&original_setting_expression(value),StatementKind::ProjectedSet{attribute,relation,value}=>crate::expression_parser::original_ascii_identifier(attribute)&&matches!(relation.as_str(),"="|"in")&&original_setting_expression(value.original_expression()),_=>false}}
fn finish_original_setting_prefix(body:&mut ParsedBody, settings: usize){
 if settings==body.statements.len()&&!body.statements.is_empty()&&body.diagnostics.is_empty(){body.original_grammar=Some(OriginalBodyGrammarOutcome{prefix_settings:settings,scope_roots:None,kind:OriginalBodyGrammarKind::Available,statement:None,expression:None,operator:None});return}
 let Some(mut outcome)=body.original_grammar else{return};
 if body.statements.is_empty()&&outcome.statement.is_none(){return}
 if body.statements.len()!=settings+1||body.statements.last().map(|row|row.header_span)!=outcome.statement{body.original_grammar=None;return}outcome.prefix_settings=settings;body.original_grammar=Some(outcome);
}
#[cfg(test)]mod original_initial_setting_outcome_tests{use super::*;
 #[test]fn actual_native_setting_prefix_has_only_demonstrated_original_grammar(){for rhs in["x","x.type","x[_]","x[_].type","x || /datum/a","/datum/b","1+2"]{let syntax=crate::parse(&format!("/proc/probe(x)\n    set SpacemanDMM_return_type={rhs}\n    return null\n"));let body=parse_proc_body(&syntax.items[0]);let outcome=body.original_grammar.unwrap();assert_eq!(outcome.kind(),OriginalBodyGrammarKind::Available,"{rhs}");assert_eq!(outcome.prefix_settings(),1);assert!(outcome.statement_span().is_some());}}
 #[test]fn actual_native_setting_only_and_zero_argument_source_call_and_member_are_issued(){for code in["    set SpacemanDMM_return_type=x\n","    return choose()\n","    return choose().field\n"]{let syntax=crate::parse(&format!("/proc/probe(x)\n{code}"));let body=parse_proc_body(&syntax.items[0]);assert_eq!(body.original_grammar.unwrap().kind(),OriginalBodyGrammarKind::Available,"{code}");}}
 #[test]fn malformed_number_and_unissued_setting_shapes_never_gain_original_availability(){for code in["    return 123abc\n","    return 1e3\n","    set SpacemanDMM_return_type=missing_call()\n    return null\n","    return choose(1)\n"]{let syntax=crate::parse(&format!("/proc/probe(x)\n{code}"));let body=parse_proc_body(&syntax.items[0]);assert!(body.original_grammar.is_none(),"unissued {code}");}}
}

#[cfg(test)]
#[test]
fn joined_return_scope_uses_the_existing_provider_once_and_preserves_first_io() {
    struct Probe(std::cell::Cell<usize>);
    impl SettingSyntaxProvider for Probe {
        fn setting(&self, _: &Item) -> Result<SettingStatement, Diagnostic> {
            panic!("joined return never reads settings");
        }
        fn original_joined_return(&self, _: Span) -> std::io::Result<bool> {
            self.0.set(self.0.get() + 1);
            Err(std::io::Error::from_raw_os_error(1450))
        }
    }
    let source = "/proc/probe(argument)\n    if(argument)\n        return\"value\"\n";
    let parsed = crate::parse(source);
    let probe = Probe(std::cell::Cell::new(0));
    let root = crate::SettingChargeCounter::root_allocation_bytes();
    let used = crate::SettingChargeCounter::try_new(root).unwrap();
    let admission = crate::SettingAdmission::new(&used, root, &|| Ok(()));
    let body = parse_body_items_using_settings(
        &parsed.items[0].children, Some(&probe), Some(&admission), Some(source), false,
    );
    assert_eq!(probe.0.get(), 1);
    assert!(body.original_grammar.is_none());
    assert_eq!(admission.take_operational_error().unwrap().raw_os_error(), Some(1450));
}

#[cfg(test)]mod original_compound_if_witness_tests{
 use super::*;
 fn body(code:&str)->ParsedBody{let syntax=crate::parse(&format!("/proc/probe(argument)\n{code}"));parse_proc_body(&syntax.items[0])}
 #[test]fn same_primary_if_and_return_branches_issue_demonstrated_compound_scope(){
  for code in["    if(argument)\n        return 1\n","    if(argument)\n        return 1\n    return 2\n","    if(argument)\n        return 1\n    else\n        return 2\n","    if(argument)\n        argument = 1\n    return 2\n","    if(argument)\n        var/value = 1\n    return 2\n"]{let parsed=body(code);assert!(parsed.diagnostics.is_empty());let fact=parsed.original_grammar.unwrap();assert_eq!(fact.kind(),OriginalBodyGrammarKind::Available);assert_eq!(fact.scope_roots(),Some(parsed.statements.len()));}
 }
 #[test]fn unknown_statement_expression_or_recovery_never_inherits_compound_scope(){
  for code in["    if(argument)\n        return 1\n    else return 2\n    else if(argument)\n        return 3\n","    if(argument)\n        return 1 +\n    return 2\n","    if(choose(1))\n        return 1\n    return 2\n","    if(argument)\n        argument = other = 1\n    return 2\n","    if(argument)\n        var/value = other = 1\n    return 2\n","    if(argument)\n        return 1\n    throw\n"]{assert!(body(code).original_grammar.is_none(),"unissued {code}");}
 }
}

#[cfg(test)]
mod original_ordinary_statement_call_witness_tests{
 use super::*;
 fn body(code:&str)->ParsedBody{
  let primary=crate::parse(&format!("/proc/probe()\n{code}"));
  parse_proc_body(&primary.items[0])
 }

 #[test]
 fn original_scope_accepts_actual_ordinary_zero_argument_statement_call(){
  for code in ["    missing()\n","    missing()\n    return 0\n","    missing( )\n    return 0\n"]{
   let parsed=body(code);
   assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);
   assert!(matches!(parsed.statements[0].kind,StatementKind::Call(_)));
   let proof=parsed.original_grammar.expect("actual complete Original statement-call witness");
   assert_eq!(proof.kind(),OriginalBodyGrammarKind::Available);
   assert_eq!(proof.scope_roots(),Some(parsed.statements.len()));
  }
 }

 #[test]
 fn unsupported_or_recovering_statement_never_inherits_ordinary_call_witness(){
  for code in ["    missing(nested())\n","    missing(\n","    missing()\n    CRASH()\n","    missing()\n    input()\n","    missing()\n    var/static/value = 0\n"]{
   assert!(body(code).original_grammar.is_none(),"unissued {code}");
  }
 }
}

#[cfg(test)]
mod original_positional_statement_call_witness_tests{
 use super::*;
 fn body(code:&str)->ParsedBody{
  let primary=crate::parse(&format!("/proc/probe(argument)\n{code}"));
  parse_proc_body(&primary.items[0])
 }
 #[test]
 fn original_statement_call_uses_consumed_simple_argument_and_comma_tokens(){
  for code in ["    sink(argument)\n","    sink(argument, null, 42)\n    return 0\n","    sink ( argument , other )\n"]{
   let parsed=body(code);
   assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);
   let outcome=parsed.original_grammar.expect("issued ordinary statement call");
   assert_eq!(outcome.kind(),OriginalBodyGrammarKind::Available);
   assert_eq!(outcome.scope_roots(),Some(parsed.statements.len()));
  }
 }
 #[test]
 fn statement_call_witness_does_not_cover_other_argument_or_expression_grammars(){
  for code in ["    sink(key=argument)\n","    sink(,argument)\n","    sink(argument,)\n","    sink(argument.field)\n","    sink(other())\n","    sink((argument))\n","    sink(-1)\n","    return sink(argument)\n","    if(sink(argument))\n        return 0\n"]{
   assert!(body(code).original_grammar.is_none(),"unissued {code}");
  }
 }
}

#[cfg(test)]
mod original_single_local_witness_tests {
    use super::*;

    fn body(code: &str) -> ParsedBody {
        let syntax = crate::parse(&format!("/proc/probe(argument)\n{code}"));
        parse_proc_body(&syntax.items[0])
    }

    #[test]
    fn original_single_local_witness_uses_real_declaration_and_initializer() {
        for code in [
            "    var/value\n",
            "    var/datum/value = argument\n    return value\n",
            "    var/value = argument + 1\n    return value\n",
            "    var/turf/turf_at_coords = Safe_COORD_Location(argument)\n    return turf_at_coords\n",
            "    if(argument)\n        var/value = argument\n        return value\n",
        ] {
            let parsed = body(code);
            assert!(parsed.diagnostics.is_empty(), "{code}: {:?}", parsed.diagnostics);
            let proof = parsed.original_grammar.expect("single local declaration proof");
            assert_eq!(proof.kind(), OriginalBodyGrammarKind::Available, "{code}");
            assert_eq!(proof.scope_roots(), Some(parsed.statements.len()), "{code}");
            assert_eq!(parsed.local_variables.entries().unwrap().len(), 1, "{code}");
        }
    }

    #[test]
    fn original_single_local_witness_refuses_unproved_local_syntax() {
        for code in [
            "    var/list/value[2]\n    return value\n",
            "    var/static/value = 1\n    return value\n",
            "    var/value = 1, other = 2\n    return value\n",
            "    var/value = argument +\n    return value\n",
            "    var/value = choose(key=argument)\n    return value\n",
            "    var/value = choose(argument,)\n    return value\n",
            "    var/value = argument = 1\n    return value\n",
            "    var/value = argument in list()\n    return value\n",
        ] {
            let parsed = body(code);
            assert!(parsed.original_grammar.is_none(), "{code}");
        }
    }
}

#[cfg(test)]
mod original_mixed_setting_scope_tests {
    use super::*;

    fn body(code: &str) -> ParsedBody {
        let syntax = crate::parse(&format!("/proc/probe(x)\n{code}"));
        parse_proc_body(&syntax.items[0])
    }

    #[test]
    fn original_mixed_setting_scope_uses_consumed_outer_prefix() {
        let parsed = body(concat!(
            "    set SpacemanDMM_should_not_sleep = 1\n",
            "    set SpacemanDMM_return_type = x\n",
            "    var/value = x\n",
            "    if(value)\n",
            "        choose()\n",
            "    return value\n",
        ));
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let proof = parsed.original_grammar.expect("actual mixed scope proof");
        assert_eq!(proof.kind(), OriginalBodyGrammarKind::Available);
        assert_eq!(proof.prefix_settings(), 2);
        assert_eq!(proof.scope_roots(), Some(5));
        assert_eq!(proof.statement_span(), None);
    }

    #[test]
    fn original_mixed_setting_scope_does_not_adopt_unconsumed_or_nonprefix_settings() {
        for code in [
            "    var/value = x\n    set SpacemanDMM_return_type = x\n    return value\n",
            "    set SpacemanDMM_return_type = x\n    if(x)\n        set SpacemanDMM_made_up = 1\n    return x\n",
            "    set SpacemanDMM_return_type = choose()\n    var/value = x\n    return value\n",
            "    set SpacemanDMM_return_type = x\n        choose()\n    return x\n",
            "    set SpacemanDMM_return_type = x\n        choose()\n",
            "    set SpacemanDMM_return_type = x\n    var/value = x\n    return value +\n",
        ] {
            let parsed = body(code);
            assert!(parsed.original_grammar.is_none(), "{code}");
        }
    }
}

#[cfg(test)]
mod original_simple_assignment_witness_tests {
    use super::*;

    fn body(code: &str) -> ParsedBody {
        let source = crate::parse(&format!("/proc/probe(argument)\n{code}"));
        parse_proc_body(&source.items[0])
    }

    #[test]
    fn original_simple_assignment_witness_owns_actual_statement_operator_and_operands() {
        let parsed = body("    value = argument.field\n    return value\n");
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        assert!(matches!(&parsed.statements[0].kind, StatementKind::Assign { op, .. } if op == "="));
        let proof = parsed.original_grammar.expect("simple statement assignment proof");
        assert_eq!(proof.scope_roots(), Some(2));

        // The compatibility lexer splits compound operators into punctuation
        // characters. Its valid AST is insufficient for the Original proof.
        // The host control supplies real indivisible Original tokens.
        let split = body("    value += argument.field\n    return value\n");
        assert!(split.diagnostics.is_empty(), "{:?}", split.diagnostics);
        assert!(matches!(&split.statements[0].kind, StatementKind::Assign { op, .. } if op == "+="));
        assert!(split.original_grammar.is_none(), "split compatibility assignment");
        let nested = body("    if(argument)\n        value = 1\n    return argument\n");
        assert_eq!(nested.original_grammar.unwrap().scope_roots(), Some(2));
    }

    #[test]
    fn original_member_index_assignment_requires_an_exact_lvalue_and_operator() {
        for statement in ["argument.field = value", "argument[index] = value",
            "argument[42] = value", "argument[\"slot\"] = value", "argument.field[index] = value"] {
            let parsed = body(&format!("    {statement}\n    return value\n"));
            assert!(parsed.diagnostics.is_empty(), "{statement}: {:?}", parsed.diagnostics);
            assert!(matches!(&parsed.statements[0].kind, StatementKind::Assign { target, .. }
                if matches!(&target.kind, ExprKind::Member { .. } | ExprKind::Index { .. })));
            assert_eq!(parsed.original_grammar.expect(statement).scope_roots(), Some(2));
        }
        let split = body("    argument.field += value\n    return value\n");
        assert!(split.diagnostics.is_empty());
        assert!(split.original_grammar.is_none(), "compatibility lexer lacks the indivisible Original operator");
    }

    #[test]
    fn original_simple_assignment_witness_does_not_certify_other_productions() {
        for code in [
            "    value == argument\n    return value\n",
            "    value:field = argument\n    return value\n",
            "    value?.field = argument\n    return value\n",
            "    value?[1] = argument\n    return value\n",
            "    value[field + 1] = argument\n    return value\n",
            "    value[field][1] = argument\n    return value\n",
            "    value.field = other = argument\n    return value\n",
            "    value.field == argument\n    return value\n",
            "    value = other = argument\n    return value\n",
            "    value = choose(argument)\n    return value\n",
            "    value + = argument\n    return value\n",
            "    value =\n    return value\n",
            "    return (value = argument)\n",
            "    if(value = argument)\n        return value\n",
            "    break = 1\n    return value\n",
        ] {
            let parsed = body(code);
            assert!(parsed.original_grammar.is_none(), "{code}");
        }
    }
}

#[cfg(test)]
mod original_while_block_witness_tests {
    use super::*;

    fn body(code: &str) -> ParsedBody {
        let source = format!("/proc/probe(argument)\n{code}");
        let parsed = crate::parse(&source);
        parse_body_items_with_source(&parsed.items[0].children, &source)
    }

    #[test]
    fn original_while_block_witness_consumes_condition_and_indented_children() {
        for code in [
            "    while(argument)\n        return 0\n    return argument\n",
            "    while(1)\n        choose()\n    return argument\n",
            "    if(argument)\n        while(argument.field)\n            return 0\n",
        ] {
            let parsed = body(code);
            assert!(parsed.diagnostics.is_empty(), "{code}: {:?}", parsed.diagnostics);
            let proof = parsed.original_grammar.expect("actual while block proof");
            assert_eq!(proof.scope_roots(), Some(parsed.statements.len()), "{code}");
        }
    }

    #[test]
    fn original_while_block_witness_requires_source_gap_and_refuses_normalized_separator() {
        let source = "/proc/probe(argument)\n    while(argument) ;\n        return 0\n";
        let parsed = crate::parse(source);
        let item = &parsed.items[0].children[0];
        assert_eq!(item.header, "while(argument)");
        assert_eq!(item.children.len(), 1);
        assert!(source[item.header_span.end..item.children[0].header_span.start].contains(';'));
        assert!(parse_body_items_with_source(&parsed.items[0].children, source).original_grammar.is_none());
        let clean = crate::parse("/proc/probe(argument)\n    while(argument)\n        return 0\n");
        assert!(parse_proc_body(&clean.items[0]).original_grammar.is_none());
    }

    #[test]
    fn original_while_block_witness_refuses_unproved_condition_or_body() {
        for code in [
            "    while(argument) return 0\n    return argument\n",
            "    while(argument)\n    return argument\n",
            "    while(argument) ;\n        return 0\n",
            "    while(choose(argument))\n        return 0\n",
            "    while(argument)\n        continue\n",
            "    while(argument)\n        return argument +\n",
            "    while(argument))\n        return 0\n",
        ] {
            let parsed = body(code);
            assert!(parsed.original_grammar.is_none(), "{code}");
        }
    }
}

#[cfg(test)]
mod original_decimal_switch_block_witness_tests {
    use super::*;

    fn body(code: &str) -> ParsedBody {
        let source = format!("/proc/probe(argument)\n{code}");
        let parsed = crate::parse(&source);
        parse_body_items_with_source(&parsed.items[0].children, &source)
    }

    #[test]
    fn original_decimal_switch_block_witness_consumes_cases_default_and_following_root() {
        for code in [
            "    switch(argument)\n        if(1)\n            return 1\n    return 0\n",
            "    switch(argument)\n        if(1)\n            return 1\n        if(2)\n            return 2\n        else\n            return 0\n",
        ] {
            let parsed = body(code);
            assert!(parsed.diagnostics.is_empty(), "{code}: {:?}", parsed.diagnostics);
            let proof = parsed.original_grammar.expect("actual decimal switch scope");
            assert_eq!(proof.scope_roots(), Some(parsed.statements.len()));
        }
    }

    #[test]
    fn original_decimal_switch_block_witness_refuses_unproved_selector_cases_or_tails() {
        for code in [
            "    switch(argument) ;\n        if(1)\n            return 0\n",
            "    switch(argument)\n        if(1) ;\n            return 0\n",
            "    switch(rand(1,2))\n        if(1)\n            return 0\n",
            "    switch(argument)\n        if(1 || 2)\n            return 0\n",
            "    switch(argument)\n        if(1,2)\n            return 0\n",
            "    switch(argument)\n        if(1,)\n            return 0\n",
            "    switch(argument)\n        if(1 to 2)\n            return 0\n",
            "    switch(argument)\n        if(value)\n            return 0\n",
            "    switch(argument)\n        if(1) return 0\n",
            "    switch(argument)\n        if(1)\n            return 0\n        else return 1\n",
            "    switch(argument)\n        else\n            return 0\n",
            "    switch(argument))\n        if(1)\n            return 0\n",
        ] {
            let parsed = body(code);
            assert!(parsed.original_grammar.is_none(), "{code}");
        }
    }
}

#[cfg(test)]
mod original_for_each_witness_tests {
    use super::*;

    fn body(code: &str) -> (String, ParsedBody) {
        let source = format!("/proc/probe(items)\n{code}");
        let parsed = crate::parse(&source);
        let body = parse_body_items_with_source(&parsed.items[0].children, &source);
        (source, body)
    }

    #[test]
    fn original_for_each_proof_consumes_declared_or_reused_binding_and_actual_iterable_occurrence() {
        for (control, iterable_name) in [("var/datum/item in items", "items"), ("var/items in items", "items"), ("item in items", "items"), ("global in items", "items")] {
            let (source, parsed) = body(&format!("    for({control})\n        return 0\n    return items\n"));
            assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
            let StatementKind::For { control: ForControl::Each { iterable, .. }, .. } = &parsed.statements[0].kind
                else { panic!("actual ForList body"); };
            assert_eq!(&source[iterable.span.range()], iterable_name);
            assert_eq!(iterable.span.start, source.find(" in ").unwrap() + " in ".len());
            // Bare syntax reuses a binding; no declaration or existence proof
            // is invented even when no outer local was written in this fixture.
            assert_eq!(parsed.local_variables.entries().unwrap().iter()
                .filter(|row| row.source_kind == crate::LocalSourceKind::ForBinding).count(),
                usize::from(control.starts_with("var/")));
            let grammar = parsed.original_grammar.expect("genuine complete Original ForList witness");
            assert_eq!(grammar.scope_roots(), Some(2));
        }
    }

    #[test]
    fn original_for_each_proof_refuses_unissued_control_and_authored_separator() {
        for code in [
            "    for(var/item in items) return 0\n",
            "    for(var/item in items) ;\n        return 0\n",
            "    for(var/item in items)\n    return 0\n",
            "    for(var/item in items)\n        continue\n",
            "    for(null in items)\n        return 0\n",
            "    for(__PROC__ in items)\n        return 0\n",
            "    for(__TYPE__ in items)\n        return 0\n",
            "    for(__IMPLIED_TYPE__ in items)\n        return 0\n",
            "    for(var/item[] in items)\n        return 0\n",
            "    for(var/item = 1 in items)\n        return 0\n",
            "    for(var/key, value in items)\n        return 0\n",
            "    for(var/item in 1 to 4)\n        return 0\n",
            "    for(var/item = 1; item < 4; item++)\n        return 0\n",
            "    for(var/item in choose(items))\n        return 0\n",
            "    for(var/item in items.field)\n        return 0\n",
        ] {
            let (_, parsed) = body(code);
            assert!(parsed.original_grammar.is_none(), "{code}");
        }
    }
}

#[cfg(test)]
#[test]
fn classic_for_control_spans_keep_repeated_parts_at_their_authored_occurrences() {
    let source = concat!(
        "/proc/probe(path, x)\n",
        "    for(var/datum/T = path; T; T = initial(T.parent_type))\n",
        "        return T\n",
        "    for(x = 0; x; x = 0)\n",
        "        return x\n",
    );
    let tree = crate::parse(source);
    let body = parse_proc_body(&tree.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let StatementKind::For { control, .. } = &body.statements[0].kind else {
        panic!("expected material-template for loop");
    };
    let ForControl::CStyle { condition: Some(condition), .. } = control else {
        panic!("expected classic for condition");
    };
    let condition_at = source.find("; T;").unwrap() + 2;
    assert_eq!(condition.span, Span::new(condition_at, condition_at + 1));
    let StatementKind::For { control, .. } = &body.statements[1].kind else {
        panic!("expected repeated-expression for loop");
    };
    let ForControl::CStyle {
        initializer: Some(ForInitializer::Expr(initial)),
        condition: Some(condition),
        step: Some(step),
    } = control else {
        panic!("expected all three classic for expressions");
    };
    let initial_at = source.find("x = 0").unwrap();
    let condition_at = source.find("; x;").unwrap() + 2;
    let step_at = source.rfind("x = 0").unwrap();
    assert_eq!(initial.span, Span::new(initial_at, initial_at + 5));
    assert_eq!(condition.span, Span::new(condition_at, condition_at + 1));
    assert_eq!(step.span, Span::new(step_at, step_at + 5));
}
