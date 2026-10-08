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
pub trait CapturedInitializerEvaluator {
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
    Scalar(SemanticValue),
    InitializerExpression { token: u32, canonical: Arc<[u8]> },
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
    Expression(dm_syntax::Expr),
    SizedArray(Arc<[u16]>),
}
#[derive(Clone, Debug)]
pub struct RuntimeGroup {
    /// None is the global/shared VM initializer. Class receivers are explicit.
    pub receiver: Option<SymbolId>,
    pub writes: Vec<ClassifiedWrite>,
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
enum HeaderDomain {
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
enum ModifierFact {
    Header(HeaderDomain),
    Known(u32),
    MutableInstance,
}
fn header_domain(
    write: &InitializerWrite,
    symbols: &SymbolTable,
) -> Result<Option<HeaderDomain>, String> {
    if write.declaration_flags.is_some() {
        return Ok(None);
    }
    if crate::savefile_projection::is_header_target(&write.target, symbols) {
        return Ok(Some(HeaderDomain::Savefile));
    }
    if crate::world_projection::is_header_target(&write.target, symbols) {
        return Ok(Some(HeaderDomain::World));
    }
    if let InitializerTarget::Instance {
        declaring_owner,
        name,
        ..
    } = write.target
    {
        let name = symbols
            .text(name)
            .ok_or("client property spelling unavailable")?;
        if declaring_owner == SymbolId::of("/client")
            && crate::client_projection::is_header_field(name)
        {
            return Ok(Some(HeaderDomain::Client));
        }
    }
    Ok(None)
}
fn modifier_facts(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<Vec<ModifierFact>, ClassificationError> {
    let mut facts = Vec::with_capacity(writes.len());
    let mut issues = Vec::new();
    for (ordinal, write) in writes.iter().enumerate() {
        let fact = (|| -> Result<ModifierFact, String> {
            if let Some(domain) = header_domain(write, symbols)? {
                return Ok(ModifierFact::Header(domain));
            }
            let knowledge = evaluator.binding_knowledge(write)?.ok_or_else(|| {
                let (owner, name) = match write.target {
                    InitializerTarget::Instance {
                        declaring_owner,
                        name,
                        ..
                    } => (declaring_owner, name),
                    InitializerTarget::Shared { owner, name, .. } => (owner, name),
                    InitializerTarget::ProcedureStatic(identity) => {
                        (identity.procedure.owner, identity.name)
                    }
                };
                format!(
                    "opaque initializer declaration modifiers: {}::{} (write {ordinal})",
                    symbols.text(owner).unwrap_or("<unknown owner>"),
                    symbols.text(name).unwrap_or("<unknown variable>")
                )
            })?;
            let flags = match knowledge {
                BindingKnowledge::Modifiers(flags) => flags,
                BindingKnowledge::MutableInstance {
                    owner,
                    name,
                    receipt,
                } => {
                    if write.declaration_flags.is_some()
                        || receipt == 0
                        || !matches!(write.target, InitializerTarget::Instance { declaring_owner, name: target_name, .. }
                            if owner == declaring_owner && name == target_name)
                    {
                        return Err("mutable instance knowledge disagrees with target".into());
                    }
                    return Ok(ModifierFact::MutableInstance);
                }
            };
            if write
                .declaration_flags
                .is_some_and(|source| source != flags)
            {
                return Err("captured initializer modifiers disagree with source facts".into());
            }
            if flags & !15 != 0 {
                return Err("unknown initializer modifiers".into());
            }
            Ok(ModifierFact::Known(flags))
        })();
        match fact {
            Ok(fact) => facts.push(fact),
            Err(reason) => issues.push(ClassificationIssue {
                source_ordinal: ordinal,
                reason,
            }),
        }
    }
    if issues.is_empty() {
        Ok(facts)
    } else {
        Err(ClassificationError { issues })
    }
}
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
    classify_from_facts(
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
fn classify_from_facts(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    facts: &[ModifierFact],
    source_ordinal: &mut usize,
    debug_defined: bool,
) -> Result<ClassifiedInitializers, String> {
    let mut classified = Vec::with_capacity(writes.len());
    let mut tokens = crate::initializer_tokens::Tokens::new(debug_defined);
    for (ordinal, original) in writes.iter().enumerate() {
        *source_ordinal = ordinal;
        // Header properties are certified ABI domains, not variables with
        // fabricated declaration flags. All domains share authored-value and
        // lexical validation, then delegate exact value policy to their writer.
        if let ModifierFact::Header(domain) = facts[ordinal] {
            let InitializerTarget::Instance {
                receiver_owner,
                name,
                ..
            } = original.target
            else {
                return Err("header classification fact has no instance target".into());
            };
            let label = domain.label();
            if original.lexical_owner != receiver_owner || original.lexical_procedure.is_some() {
                return Err(format!(
                    "{label} header lexical owner differs from receiver"
                ));
            }
            if original.declared_array.is_some() {
                return Err(format!("{label} header property cannot allocate an array"));
            }
            let InitializerValue::Expression(value) = &original.value else {
                return Err(format!(
                    "{label} header property requires an authored value"
                ));
            };
            let Evaluation::Scalar(value) = evaluator.evaluate_write(original, value)? else {
                return Err(format!(
                    "{label} header property requires a captured scalar"
                ));
            };
            let name = symbols
                .text(name)
                .ok_or_else(|| format!("{label} property spelling unavailable"))?;
            domain.validate(name, &value)?;
            classified.push(ClassifiedWrite {
                source_ordinal: ordinal,
                write: original.clone(),
                default: DefaultValue::Scalar(value),
                phase: None,
                runtime_value: None,
            });
            continue;
        }
        let constant_binding = match facts[ordinal] {
            ModifierFact::Known(flags) => flags & 2 != 0,
            ModifierFact::MutableInstance => false,
            ModifierFact::Header(_) => {
                return Err("header classification fact was not consumed".into())
            }
        };
        let write = original.clone();
        if let Some(array) = &original.declared_array {
            let unsized_only = array.dimensions.len() == 1 && array.dimensions[0].is_none();
            if !unsized_only {
                if !matches!(original.value, InitializerValue::ArrayAllocation(_)) {
                    return Err("explicit sized array initializer is unsupported".into());
                }
                let mut dimensions = Vec::with_capacity(array.dimensions.len());
                for dimension in array.dimensions.iter() {
                    let dimension = dimension.as_ref().ok_or("mixed unsized array dimensions")?;
                    let Evaluation::Scalar(SemanticValue::NumberBits(bits)) =
                        evaluator.evaluate_write(&write, dimension)?
                    else {
                        return Err("array dimension must be a constant integer".into());
                    };
                    let size = f32::from_bits(bits);
                    if !(0.0..=65535.0).contains(&size) || size.fract() != 0.0 {
                        return Err("invalid array dimension".into());
                    }
                    dimensions.push(size as u16);
                }
                if dimensions.is_empty() {
                    return Err("array has no dimensions".into());
                }
                if constant_binding {
                    return Err("const array allocation is unsupported".into());
                }
                // Native sized-array declarations retain null defaults; they
                // allocate during initialization without an expression token.
                let default = DefaultValue::Scalar(SemanticValue::Null);
                classified.push(ClassifiedWrite {
                    source_ordinal: ordinal,
                    write,
                    default,
                    phase: Some(Phase::LiteralAllocation),
                    runtime_value: Some(RuntimeValue::SizedArray(dimensions.into())),
                });
                continue;
            }
        }
        let mut parsed_runtime = None;
        let (default, phase) = match &write.value {
            InitializerValue::NoAuthoredValue => (DefaultValue::Scalar(SemanticValue::Null), None),
            InitializerValue::ArrayAllocation(_) => {
                return Err("array allocation lacks authored shape".into())
            }
            InitializerValue::Expression(value) => {
                match evaluator.evaluate_write(&write, value)? {
                    Evaluation::Scalar(value) if !matches!(value, SemanticValue::List(_)) => {
                        (DefaultValue::Scalar(value), None)
                    }
                    evaluation => {
                        if constant_binding {
                            return Err("const initializer is not scalar".into());
                        }
                        let text = value
                            .source_text(symbols)
                            .ok_or("initializer spelling missing")?;
                        let parsed = dm_syntax::parse_expression(&text);
                        if !parsed.diagnostics.is_empty() {
                            return Err("invalid initializer expression".into());
                        }
                        let expr = parsed
                            .expr
                            .as_ref()
                            .ok_or("missing initializer expression")?;
                        parsed_runtime = Some(expr.clone());
                        let literal =
                            matches!(evaluation, Evaluation::Scalar(SemanticValue::List(_)))
                                || scalar_literal(expr, &write, symbols, &text, evaluator)?;
                        let default = if let Some(key) =
                            crate::initializer_tokens::construction_key(
                                expr, &text, &write, symbols, evaluator,
                            )? {
                            let (token, canonical) = tokens.issue(key)?;
                            DefaultValue::InitializerExpression { token, canonical }
                        } else {
                            DefaultValue::Scalar(SemanticValue::Null)
                        };
                        (
                            default,
                            Some(if literal {
                                Phase::LiteralAllocation
                            } else {
                                Phase::Runtime
                            }),
                        )
                    }
                }
            }
        };
        let runtime_value = if phase.is_some() {
            Some(RuntimeValue::Expression(
                parsed_runtime.ok_or("runtime expression missing")?,
            ))
        } else {
            None
        };
        classified.push(ClassifiedWrite {
            source_ordinal: ordinal,
            write,
            default,
            phase,
            runtime_value,
        });
    }
    let mut groups: Vec<RuntimeGroup> = Vec::new();
    let mut receiver_groups = std::collections::HashMap::new();
    for write in classified.iter().filter(|write| write.phase.is_some()) {
        let receiver = match write.write.target {
            InitializerTarget::Shared { .. } => None,
            InitializerTarget::ProcedureStatic(_) => None,
            InitializerTarget::Instance { receiver_owner, .. } => Some(receiver_owner),
        };
        // The index accelerates lookup only; first encounter still determines
        // group order, and each group's writes retain their original order.
        let index = *receiver_groups.entry(receiver).or_insert_with(|| {
            let index = groups.len();
            groups.push(RuntimeGroup {
                receiver,
                writes: Vec::new(),
            });
            index
        });
        groups[index].writes.push(write.clone());
    }
    for group in &mut groups {
        if group.receiver.is_none() {
            // Stable partition: literal lists/sized arrays precede runtime calls;
            // each phase retains source order. Instance writes are never sorted.
            group
                .writes
                .sort_by_key(|write| write.phase == Some(Phase::Runtime));
        }
    }
    Ok(ClassifiedInitializers {
        writes: classified,
        groups,
    })
}

#[cfg(test)]
#[path = "initializer_policy/tests.rs"]
mod tests;
