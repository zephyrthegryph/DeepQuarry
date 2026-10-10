//! Captured initializer classification. Evaluation failure is never converted
//! into a runtime initializer; the evaluator explicitly distinguishes runtime.
use dm_ir::{
    ExpressionToken, InitializerTarget, InitializerValue, InitializerWrite, SemanticValue,
    SymbolId, SymbolTable, SymbolicExpression,
};
use std::sync::Arc;

pub enum Evaluation {
    Scalar(SemanticValue),
    Runtime,
}
/// Request-local syntax prepared by the evaluator's existing admission path.
/// It contains no cached resolution result or independent dependency domain.
pub struct PreparedInitializerExpression {
    pub source: String,
    pub ast: dm_syntax::Expr,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindingKnowledge {
    Modifiers(u32),
    /// Positive native mutable binding + exact resolved instance storage.
    /// This says nothing about persistence/tmp or unknown wire modifiers.
    MutableInstance {
        owner: SymbolId,
        name: SymbolId,
        receipt: u128,
    },
}
/// An immutable factory creates request-equivalent borrowed policy views in a
/// worker. It must invoke the operation exactly once and must not retain it.
/// Evaluation is independent across type buckets; ordinal diagnostics and token
/// issuance are merged by the caller in authored source order.
pub trait InitializerEvaluatorFactory: Sync {
    /// Certifies immutable non-resolver policy inputs. Opaque adapters decline
    /// semantic retention even when they can construct an evaluator.
    fn recording_policy_identity(&self) -> Option<u128> {
        None
    }
    /// Return true only when every resolver-backed evaluation in the operation
    /// uses this supplied recorder. Compatibility factories decline reuse.
    fn with_recording_evaluator(
        &self,
        _engine: Option<&crate::engine::EngineSnapshot>,
        _resolver: &dyn dm_ir::Resolver,
        _operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) -> bool {
        false
    }
    fn with_evaluator(
        &self,
        engine: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    );
}
#[derive(Clone, Copy)]
pub struct ParallelEvaluator<'a> {
    pub factory: &'a dyn InitializerEvaluatorFactory,
    pub engine: Option<&'a crate::engine::EngineSnapshot>,
}
pub trait CapturedInitializerEvaluator {
    fn parallel_evaluator(&self) -> Option<ParallelEvaluator<'_>> {
        None
    }

    /// Compatibility evaluators keep their exact evaluation/error behavior.
    /// Production may return the already parsed expression for runtime lowering.
    fn evaluate_prepared_write(
        &self,
        write: &InitializerWrite,
        value: &SymbolicExpression,
    ) -> Result<(Evaluation, Option<PreparedInitializerExpression>), String> {
        Ok((self.evaluate_write(write, value)?, None))
    }
    /// Borrow an already parsed subtree. Compatibility evaluators retain their
    /// existing captured-token path and lexical context checks.
    fn evaluate_ast_write(
        &self,
        write: &InitializerWrite,
        ast: &dm_syntax::Expr,
        source: &str,
        symbols: &SymbolTable,
    ) -> Result<Evaluation, String> {
        self.evaluate_write(write, &captured_scalar_subexpression(ast, source, symbols)?)
    }
    fn initializer_token_scalar(&self, value: &SemanticValue) -> Result<Vec<u8>, String> {
        if matches!(value, SemanticValue::Resource(_)) {
            return Err("initializer resource token requires captured content identity".into());
        }
        Ok(value.canonical_bytes())
    }
    /// Admit only the pinned intrinsic constructor after current callable lookup.
    /// Compatibility evaluators decline rather than treating a spelling as proof.
    fn initializer_intrinsic_constructor(&self, _write: &InitializerWrite, _name: &str) -> bool {
        false
    }
    fn initializer_constructor_type(
        &self,
        _write: &InitializerWrite,
    ) -> Result<Option<SymbolId>, String> {
        Ok(None)
    }
    fn pure_calls(&self) -> Option<&dyn dm_tree::constants::PureCalls> {
        None
    }
    fn evaluate(&self, owner: SymbolId, value: &SymbolicExpression) -> Result<Evaluation, String>;
    fn evaluate_write(
        &self,
        write: &InitializerWrite,
        value: &SymbolicExpression,
    ) -> Result<Evaluation, String> {
        if write.lexical_procedure.is_some() {
            return Err("procedure-static initializer evaluator context is unsupported".into());
        }
        self.evaluate(write.lexical_owner, value)
    }
    /// Source modifiers or positively captured inherited declaration facts.
    /// None remains unknown, rather than a fabricated zero modifier mask.
    fn declaration_modifiers(&self, write: &InitializerWrite) -> Result<Option<u32>, String> {
        Ok(write.declaration_flags)
    }
    fn instance_storage(
        &self,
        _write: &InitializerWrite,
    ) -> Result<Option<(SymbolId, SymbolId)>, String> {
        Ok(None)
    }
    fn binding_knowledge(
        &self,
        write: &InitializerWrite,
    ) -> Result<Option<BindingKnowledge>, String> {
        Ok(self
            .declaration_modifiers(write)?
            .map(BindingKnowledge::Modifiers))
    }
}
/// Borrow the same captured engine used by the frontend and cold writer. Only
/// exact positive declaration records supplement unknown inherited modifiers.
pub struct EngineCapturedEvaluator<'a> {
    pub engine: &'a crate::engine::EngineSnapshot,
    pub evaluator: &'a dyn CapturedInitializerEvaluator,
}
impl CapturedInitializerEvaluator for EngineCapturedEvaluator<'_> {
    fn parallel_evaluator(&self) -> Option<ParallelEvaluator<'_>> {
        let mut context = self.evaluator.parallel_evaluator()?;
        context.engine = Some(self.engine);
        Some(context)
    }

    fn evaluate_prepared_write(
        &self,
        write: &InitializerWrite,
        value: &SymbolicExpression,
    ) -> Result<(Evaluation, Option<PreparedInitializerExpression>), String> {
        self.evaluator.evaluate_prepared_write(write, value)
    }
    fn evaluate_ast_write(
        &self,
        write: &InitializerWrite,
        ast: &dm_syntax::Expr,
        source: &str,
        symbols: &SymbolTable,
    ) -> Result<Evaluation, String> {
        self.evaluator
            .evaluate_ast_write(write, ast, source, symbols)
    }
    fn initializer_token_scalar(&self, value: &SemanticValue) -> Result<Vec<u8>, String> {
        self.evaluator.initializer_token_scalar(value)
    }
    fn initializer_intrinsic_constructor(&self, write: &InitializerWrite, name: &str) -> bool {
        self.evaluator
            .initializer_intrinsic_constructor(write, name)
    }
    fn initializer_constructor_type(
        &self,
        write: &InitializerWrite,
    ) -> Result<Option<SymbolId>, String> {
        self.evaluator.initializer_constructor_type(write)
    }
    fn pure_calls(&self) -> Option<&dyn dm_tree::constants::PureCalls> {
        self.evaluator.pure_calls()
    }
    fn binding_knowledge(
        &self,
        write: &InitializerWrite,
    ) -> Result<Option<BindingKnowledge>, String> {
        if let Some(flags) = self.declaration_modifiers(write)? {
            return Ok(Some(BindingKnowledge::Modifiers(flags)));
        }
        let InitializerTarget::Instance {
            declaring_owner,
            name,
            ..
        } = write.target
        else {
            return Ok(None);
        };
        if self.engine.template_identity()
            != crate::intrinsic_initializer_facts::template_identity()
            || !crate::intrinsic_initializer_facts::certified(declaring_owner, name)
            || self.evaluator.instance_storage(write)? != Some((declaring_owner, name))
        {
            return Ok(None);
        }
        Ok(Some(BindingKnowledge::MutableInstance {
            owner: declaring_owner,
            name,
            receipt: crate::intrinsic_initializer_facts::identity(),
        }))
    }
    fn evaluate_write(
        &self,
        write: &InitializerWrite,
        value: &SymbolicExpression,
    ) -> Result<Evaluation, String> {
        self.evaluator.evaluate_write(write, value)
    }
    fn evaluate(&self, owner: SymbolId, value: &SymbolicExpression) -> Result<Evaluation, String> {
        self.evaluator.evaluate(owner, value)
    }
    fn declaration_modifiers(&self, write: &InitializerWrite) -> Result<Option<u32>, String> {
        if let Some(flags) = self.evaluator.declaration_modifiers(write)? {
            return Ok(Some(flags));
        }
        let (owner, name) = match write.target {
            InitializerTarget::ProcedureStatic(_) => return Ok(write.declaration_flags),
            InitializerTarget::Shared { owner, name, .. } => (owner, name),
            InitializerTarget::Instance {
                declaring_owner,
                name,
                ..
            } => (declaring_owner, name),
        };
        self.engine
            .declaration_modifiers(owner, name)
            .map_err(|error| format!("captured engine declaration modifiers: {error:?}"))
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DefaultValue {
    /// Certified intrinsic initial transform; ordinary matrices remain mutable.
    Transform([u32; 6]),
    Scalar(SemanticValue),
    InitializerExpression {
        token: u32,
        canonical: Arc<[u8]>,
    },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    LiteralAllocation,
    Runtime,
}
#[derive(Clone, Debug)]
pub struct ClassifiedWrite {
    pub source_ordinal: usize,
    pub write: InitializerWrite,
    pub default: DefaultValue,
    pub phase: Option<Phase>,
    /// Typed runtime value; dimensions come from captured constant facts.
    pub runtime_value: Option<RuntimeValue>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RuntimeValue {
    Expression(Arc<dm_syntax::Expr>),
    SizedArray(Arc<[u16]>),
}
#[derive(Clone, Debug)]
pub struct RuntimeGroup {
    /// None is the global/shared VM initializer. Class receivers are explicit.
    pub receiver: Option<SymbolId>,
    /// Indices into ClassifiedInitializers::writes; runtime ASTs have one owner.
    pub writes: Vec<usize>,
}
#[derive(Debug)]
pub struct ClassifiedInitializers {
    pub writes: Vec<ClassifiedWrite>,
    pub groups: Vec<RuntimeGroup>,
}
#[cfg(test)]
fn expression(text: &str, symbols: &mut SymbolTable) -> Result<SymbolicExpression, String> {
    let lexed = dm_syntax::lex(text);
    let tokens = lexed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        })
        .map(|token| {
            Ok(ExpressionToken {
                kind: token.kind,
                text: symbols
                    .intern(&token.text)
                    .map_err(|error| format!("{error:?}"))?,
                relative_span: token.span,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(SymbolicExpression {
        tokens: tokens.into(),
    })
}
/// Use spans issued by the parser of this exact captured spelling. The same
/// lexer and collision-checked dictionary retain token identities/adjacency;
/// no subtree parser or pure-call interpretation is introduced here.
pub(crate) fn captured_scalar_subexpression(
    expression: &dm_syntax::Expr,
    source: &str,
    symbols: &SymbolTable,
) -> Result<SymbolicExpression, String> {
    let source = source
        .get(expression.span.start..expression.span.end)
        .ok_or("initializer subtree span is outside captured expression")?;
    let parsed = dm_syntax::lex(source);
    if !parsed.diagnostics.is_empty() {
        return Err("initializer subtree tokenization failed".into());
    }
    let tokens = parsed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        })
        .map(|token| {
            let text = SymbolId::of(&token.text);
            if symbols.text(text) != Some(token.text.as_str()) {
                return Err("initializer subtree token spelling is not captured".into());
            }
            Ok(ExpressionToken {
                kind: token.kind,
                text,
                relative_span: token.span,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(SymbolicExpression {
        tokens: tokens.into(),
    })
}
fn scalar_literal(
    expr: &dm_syntax::Expr,
    write: &InitializerWrite,
    symbols: &SymbolTable,
    source: &str,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<bool, String> {
    use dm_syntax::ExprKind;
    Ok(match &expr.kind {
        ExprKind::TypePath(_) => true,
        ExprKind::Literal(raw) => {
            // Interpolated text can execute runtime expressions; spelling as a
            // literal is insufficient to certify an allocation-phase value.
            let id = SymbolId::of(raw);
            if symbols.text(id) != Some(raw.as_str()) {
                return Err("initializer literal spelling missing".into());
            }
            matches!(
                evaluator.evaluate_ast_write(write, expr, source, symbols)?,
                Evaluation::Scalar(_)
            )
        }
        ExprKind::Ident(name) => {
            let id = SymbolId::of(name);
            if symbols.text(id) != Some(name.as_str()) {
                return Err(format!("initializer symbol missing: {name}"));
            }
            matches!(
                evaluator.evaluate_ast_write(write, expr, source, symbols)?,
                Evaluation::Scalar(_)
            )
        }
        ExprKind::Group(value) => scalar_literal(value, write, symbols, source, evaluator)?,
        ExprKind::Unary { op, value } if matches!(op.as_str(), "!" | "+" | "-" | "~") => {
            scalar_literal(value, write, symbols, source, evaluator)?
        }
        ExprKind::Binary { op, lhs, rhs } if op != "=" => {
            scalar_literal(lhs, write, symbols, source, evaluator)?
                && scalar_literal(rhs, write, symbols, source, evaluator)?
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            scalar_literal(condition, write, symbols, source, evaluator)?
                && scalar_literal(then_value, write, symbols, source, evaluator)?
                && scalar_literal(else_value, write, symbols, source, evaluator)?
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "list") =>
        {
            let mut literal = true;
            for argument in args {
                let value = if let ExprKind::Binary { op, lhs, rhs } = &argument.kind {
                    if op == "=" {
                        (matches!(lhs.kind, ExprKind::Ident(_))
                            || scalar_literal(lhs, write, symbols, source, evaluator)?)
                            && scalar_literal(rhs, write, symbols, source, evaluator)?
                    } else {
                        scalar_literal(argument, write, symbols, source, evaluator)?
                    }
                } else {
                    scalar_literal(argument, write, symbols, source, evaluator)?
                };
                literal &= value;
            }
            literal
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "newlist") => {
            args.is_empty()
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") => {
            args.len() == 1 && dm_codegen_byond::nameof_reference(&args[0]).is_some()
        }
        ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if evaluator.pure_calls().is_some_and(|calls| calls.accepts(name))) =>
        {
            matches!(
                evaluator.evaluate_ast_write(write, expr, source, symbols)?,
                Evaluation::Scalar(_)
            )
        }
        _ => false,
    })
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClassificationIssue {
    pub source_ordinal: usize,
    pub reason: String,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClassificationError {
    pub issues: Vec<ClassificationIssue>,
}
impl std::fmt::Display for ClassificationError {
    fn fmt(&self, output: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for (index, issue) in self.issues.iter().enumerate() {
            if index != 0 {
                output.write_str("\n")?;
            }
            output.write_str(&issue.reason)?;
        }
        Ok(())
    }
}
impl std::error::Error for ClassificationError {}
#[derive(Clone, Copy)]
pub(crate) enum HeaderDomain {
    Client,
    World,
    Savefile,
}
impl HeaderDomain {
    fn label(self) -> &'static str {
        match self {
            Self::Client => "client",
            Self::World => "world",
            Self::Savefile => "savefile",
        }
    }
    fn validate(self, name: &str, value: &SemanticValue) -> Result<(), String> {
        match self {
            Self::Client => {
                crate::client_projection::project(name, value)
                    .map_err(|error| format!("client header property: {error:?}"))?
                    .ok_or("client header projection missing")?;
            }
            Self::World => {
                crate::world_projection::project([(name, value)])
                    .map_err(|error| format!("world header property: {error:?}"))?;
            }
            Self::Savefile => {
                crate::savefile_projection::project(value)?;
            }
        }
        Ok(())
    }
}
#[derive(Clone, Copy)]
pub(crate) enum ModifierFact {
    Header(HeaderDomain),
    Known(u32),
    MutableInstance,
}
mod modifier_facts;
use modifier_facts::{modifier_facts, modifier_facts_indexed};
/// Capture modifier dependencies once, exposing every missing boundary before
/// evaluating values. Classification then consumes these immutable answers.
pub fn classify_with_diagnostics(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<ClassifiedInitializers, ClassificationError> {
    classify_with_token_mode(writes, symbols, evaluator, false)
}
pub fn classify_with_token_mode(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    debug_defined: bool,
) -> Result<ClassifiedInitializers, ClassificationError> {
    let facts = modifier_facts(writes, symbols, evaluator)?;
    let mut source_ordinal = 0;
    classification::classify_from_facts(
        writes,
        symbols,
        evaluator,
        &facts,
        &mut source_ordinal,
        debug_defined,
    )
    .map_err(|reason| ClassificationError {
        issues: vec![ClassificationIssue {
            source_ordinal,
            reason,
        }],
    })
}
/// Compatibility caller retains string diagnostics; production uses ordinals.
pub fn classify(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<ClassifiedInitializers, String> {
    classify_with_diagnostics(writes, symbols, evaluator).map_err(|error| error.to_string())
}

#[cfg(test)]
#[path = "initializer_policy/tests.rs"]
mod tests;

mod classification;
pub(crate) use classification::artifact::SemanticClassification;
pub use classification::artifact::{InitializerArtifacts, InitializerReuse};

pub fn classify_with_reuse_on_executor(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: ParallelEvaluator<'_>,
    debug_defined: bool,
    executor: &dm_exec::BuildExecutor,
    reuse: InitializerReuse<'_>,
) -> Result<ClassifiedInitializers, ClassificationError> {
    classification::parallel::classify_with_reuse(
        writes,
        symbols,
        evaluator,
        debug_defined,
        executor,
        Some(reuse),
    )
}

pub fn classify_with_token_mode_on_executor(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: ParallelEvaluator<'_>,
    debug_defined: bool,
    executor: &dm_exec::BuildExecutor,
) -> Result<ClassifiedInitializers, ClassificationError> {
    classification::parallel::classify(writes, symbols, evaluator, debug_defined, executor)
}
