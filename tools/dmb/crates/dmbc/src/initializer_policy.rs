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
pub trait CapturedInitializerEvaluator {
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
}
/// Borrow the same captured engine used by the frontend and cold writer. Only
/// exact positive declaration records supplement unknown inherited modifiers.
pub struct EngineCapturedEvaluator<'a> {
    pub engine: &'a crate::engine::EngineSnapshot,
    pub evaluator: &'a dyn CapturedInitializerEvaluator,
}
impl CapturedInitializerEvaluator for EngineCapturedEvaluator<'_> {
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
    ConstructorSequence(u32),
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
fn scalar_literal(
    expr: &dm_syntax::Expr,
    write: &InitializerWrite,
    symbols: &SymbolTable,
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
            let value = SymbolicExpression {
                tokens: Arc::from([ExpressionToken {
                    kind: dm_syntax::lex(raw)
                        .tokens
                        .first()
                        .ok_or("empty literal")?
                        .kind,
                    text: id,
                    relative_span: dm_syntax::Span {
                        start: 0,
                        end: raw.len(),
                    },
                }]),
            };
            matches!(
                evaluator.evaluate_write(write, &value)?,
                Evaluation::Scalar(_)
            )
        }
        ExprKind::Ident(name) => {
            let id = SymbolId::of(name);
            if symbols.text(id) != Some(name.as_str()) {
                return Err(format!("initializer symbol missing: {name}"));
            }
            let value = SymbolicExpression {
                tokens: Arc::from([ExpressionToken {
                    kind: dm_syntax::TokenKind::Ident,
                    text: id,
                    relative_span: expr.span,
                }]),
            };
            matches!(
                evaluator.evaluate_write(write, &value)?,
                Evaluation::Scalar(_)
            )
        }
        ExprKind::Group(value) => scalar_literal(value, write, symbols, evaluator)?,
        ExprKind::Unary { op, value } if matches!(op.as_str(), "!" | "+" | "-" | "~") => {
            scalar_literal(value, write, symbols, evaluator)?
        }
        ExprKind::Binary { op, lhs, rhs } if op != "=" => {
            scalar_literal(lhs, write, symbols, evaluator)?
                && scalar_literal(rhs, write, symbols, evaluator)?
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            scalar_literal(condition, write, symbols, evaluator)?
                && scalar_literal(then_value, write, symbols, evaluator)?
                && scalar_literal(else_value, write, symbols, evaluator)?
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "list") =>
        {
            let mut literal = true;
            for argument in args {
                let value = if let ExprKind::Binary { op, lhs, rhs } = &argument.kind {
                    if op == "=" {
                        (matches!(lhs.kind, ExprKind::Ident(_))
                            || scalar_literal(lhs, write, symbols, evaluator)?)
                            && scalar_literal(rhs, write, symbols, evaluator)?
                    } else {
                        scalar_literal(argument, write, symbols, evaluator)?
                    }
                } else {
                    scalar_literal(argument, write, symbols, evaluator)?
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
            let flags = evaluator.declaration_modifiers(write)?.ok_or_else(|| {
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
    let facts = modifier_facts(writes, symbols, evaluator)?;
    let mut source_ordinal = 0;
    classify_from_facts(writes, symbols, evaluator, &facts, &mut source_ordinal).map_err(|reason| {
        ClassificationError {
            issues: vec![ClassificationIssue {
                source_ordinal,
                reason,
            }],
        }
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
) -> Result<ClassifiedInitializers, String> {
    let mut classified = Vec::with_capacity(writes.len());
    let mut global_constructors = 0u32;
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
        let ModifierFact::Known(flags) = facts[ordinal] else {
            return Err("header classification fact was not consumed".into());
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
                if flags & 2 != 0 {
                    return Err("const array allocation is unsupported".into());
                }
                let default = if matches!(write.target,InitializerTarget::Shared{owner,..} if owner == SymbolId::of("/"))
                {
                    global_constructors = global_constructors
                        .checked_add(1)
                        .ok_or("constructor sequence overflow")?;
                    DefaultValue::ConstructorSequence(global_constructors)
                } else {
                    DefaultValue::Scalar(SemanticValue::Null)
                };
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
                        if flags & 2 != 0 {
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
                                || scalar_literal(expr, &write, symbols, evaluator)?;
                        let constructor = text.trim_start().starts_with("new ");
                        let default = if constructor
                            && matches!(write.target,InitializerTarget::Shared{owner,..} if owner == SymbolId::of("/"))
                        {
                            global_constructors = global_constructors
                                .checked_add(1)
                                .ok_or("constructor sequence overflow")?;
                            DefaultValue::ConstructorSequence(global_constructors)
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
    for write in classified.iter().filter(|write| write.phase.is_some()) {
        let receiver = match write.write.target {
            InitializerTarget::Shared { .. } => None,
            InitializerTarget::ProcedureStatic(_) => None,
            InitializerTarget::Instance { receiver_owner, .. } => Some(receiver_owner),
        };
        let index = match groups.iter().position(|group| group.receiver == receiver) {
            Some(index) => index,
            None => {
                groups.push(RuntimeGroup {
                    receiver,
                    writes: Vec::new(),
                });
                groups.len() - 1
            }
        };
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
mod tests {
    use super::*;
    struct Evaluator;
    impl CapturedInitializerEvaluator for Evaluator {
        fn evaluate(&self, _: SymbolId, value: &SymbolicExpression) -> Result<Evaluation, String> {
            if value.tokens.len() == 1 && value.tokens[0].text == SymbolId::of("2") {
                Ok(Evaluation::Scalar(SemanticValue::NumberBits(
                    2f32.to_bits(),
                )))
            } else {
                Ok(Evaluation::Runtime)
            }
        }
    }
    fn write(owner: SymbolId, name: SymbolId, value: InitializerValue) -> InitializerWrite {
        InitializerWrite {
            target: InitializerTarget::Shared {
                slot: SymbolId::of("slot"),
                owner,
                name,
            },
            lexical_owner: owner,
            lexical_procedure: None,
            value,
            declared_array: None,
            declaration_flags: Some(8),
        }
    }
    #[test]
    fn client_header_assignment_preserves_unknown_modifiers_without_runtime_code() {
        let mut symbols = SymbolTable::default();
        let client = symbols.intern("/client").unwrap();
        let name = symbols.intern("preload_rsc").unwrap();
        let mut header = write(
            client,
            name,
            InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
        );
        header.target = InitializerTarget::Instance {
            declaring_owner: client,
            receiver_owner: client,
            name,
        };
        header.declaration_flags = None;
        let result = classify(&[header.clone()], &symbols, &Evaluator).unwrap();
        assert!(result.groups.is_empty());
        assert_eq!(result.writes[0].write, header);
        assert!(
            matches!(result.writes[0].default,DefaultValue::Scalar(SemanticValue::NumberBits(bits)) if bits==2f32.to_bits())
        );
        header.target = InitializerTarget::Instance {
            declaring_owner: client,
            receiver_owner: SymbolId::of("/client/subtype"),
            name,
        };
        header.lexical_owner = SymbolId::of("/client/subtype");
        assert!(classify(&[header], &symbols, &Evaluator).is_ok());
    }
    #[test]
    fn global_literal_phase_is_stable_and_instances_keep_encounter_order() {
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let name = symbols.intern("x").unwrap();
        let runtime = write(
            root,
            name,
            InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
        );
        let literal = write(
            root,
            name,
            InitializerValue::Expression(expression("list(2)", &mut symbols).unwrap()),
        );
        let result = classify(
            &[runtime.clone(), literal.clone(), runtime],
            &mut symbols,
            &Evaluator,
        )
        .unwrap();
        assert_eq!(
            result.groups[0]
                .writes
                .iter()
                .map(|write| write.source_ordinal)
                .collect::<Vec<_>>(),
            [1, 0, 2]
        );
        let owner = symbols.intern("/datum/x").unwrap();
        let instance = |mut write: InitializerWrite| {
            write.target = InitializerTarget::Instance {
                declaring_owner: owner,
                receiver_owner: owner,
                name,
            };
            write.lexical_owner = owner;
            write.declaration_flags = Some(0);
            write
        };
        let result = classify(
            &[instance(result.writes[0].write.clone()), instance(literal)],
            &mut symbols,
            &Evaluator,
        )
        .unwrap();
        assert_eq!(
            result.groups[0]
                .writes
                .iter()
                .map(|write| write.source_ordinal)
                .collect::<Vec<_>>(),
            [0, 1]
        );
    }
    #[test]
    fn sized_array_uses_captured_integer_dimensions_and_const_runtime_rejects() {
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let name = symbols.intern("x").unwrap();
        let array = Arc::new(dm_ir::ArrayDeclaration {
            dimensions: Arc::from([Some(expression("2", &mut symbols).unwrap())]),
            element_type: None,
        });
        let mut item = write(
            root,
            name,
            InitializerValue::ArrayAllocation(Arc::clone(&array)),
        );
        item.declared_array = Some(array);
        let result = classify(&[item], &mut symbols, &Evaluator).unwrap();
        assert_eq!(result.writes[0].phase, Some(Phase::LiteralAllocation));
        assert_eq!(
            result.writes[0].default,
            DefaultValue::ConstructorSequence(1)
        );
        assert_eq!(
            result.writes[0].runtime_value,
            Some(RuntimeValue::SizedArray(Arc::from([2u16])))
        );
        let mut item = write(
            root,
            name,
            InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
        );
        item.declaration_flags = Some(2);
        assert!(classify(&[item], &mut symbols, &Evaluator)
            .unwrap_err()
            .contains("const"));
    }
    #[test]
    fn missing_modifier_preflight_reports_all_ordinals_and_queries_once() {
        struct Counting {
            queries: std::sync::Mutex<Vec<SymbolId>>,
            evaluations: std::sync::atomic::AtomicUsize,
        }
        impl CapturedInitializerEvaluator for Counting {
            fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
                self.evaluations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                Ok(Evaluation::Scalar(SemanticValue::NumberBits(
                    2f32.to_bits(),
                )))
            }
            fn declaration_modifiers(
                &self,
                write: &InitializerWrite,
            ) -> Result<Option<u32>, String> {
                let name = match write.target {
                    InitializerTarget::Shared { name, .. } => name,
                    _ => panic!("fixture target"),
                };
                self.queries.lock().unwrap().push(name);
                Ok(write.declaration_flags)
            }
        }
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/datum/probe").unwrap();
        let value = InitializerValue::Expression(expression("2", &mut symbols).unwrap());
        let mut writes = ["zeta", "alpha", "middle"]
            .into_iter()
            .map(|name| write(owner, symbols.intern(name).unwrap(), value.clone()))
            .collect::<Vec<_>>();
        writes[0].declaration_flags = None;
        writes[2].declaration_flags = None;
        let evaluator = Counting {
            queries: std::sync::Mutex::new(Vec::new()),
            evaluations: std::sync::atomic::AtomicUsize::new(0),
        };
        let error = classify_with_diagnostics(&writes, &symbols, &evaluator).unwrap_err();
        assert_eq!(
            error
                .issues
                .iter()
                .map(|issue| issue.source_ordinal)
                .collect::<Vec<_>>(),
            [0, 2]
        );
        assert!(error.issues[0]
            .reason
            .contains("/datum/probe::zeta (write 0)"));
        assert!(error.issues[1]
            .reason
            .contains("/datum/probe::middle (write 2)"));
        assert_eq!(
            *evaluator.queries.lock().unwrap(),
            [
                SymbolId::of("zeta"),
                SymbolId::of("alpha"),
                SymbolId::of("middle")
            ]
        );
        assert_eq!(
            evaluator
                .evaluations
                .load(std::sync::atomic::Ordering::Relaxed),
            0
        );
        evaluator.queries.lock().unwrap().clear();
        for write in &mut writes {
            write.declaration_flags = Some(8);
        }
        let result = classify_with_diagnostics(&writes, &symbols, &evaluator).unwrap();
        assert_eq!(result.writes.len(), 3);
        assert_eq!(evaluator.queries.lock().unwrap().len(), 3);
        assert_eq!(
            evaluator
                .evaluations
                .load(std::sync::atomic::Ordering::Relaxed),
            3
        );
    }
    #[test]
    fn nonmodifier_failure_keeps_failing_write_ordinal() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/").unwrap();
        let name = symbols.intern("value").unwrap();
        let first = write(
            owner,
            name,
            InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
        );
        let mut second = write(
            owner,
            name,
            InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
        );
        second.declaration_flags = Some(2);
        let error = classify_with_diagnostics(&[first, second], &symbols, &Evaluator).unwrap_err();
        assert_eq!(error.issues.len(), 1);
        assert_eq!(error.issues[0].source_ordinal, 1);
        assert!(error.issues[0].reason.contains("const initializer"));
    }
    #[test]
    fn savefile_header_scalar_keeps_unknown_flags_and_no_runtime_group() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/savefile").unwrap();
        let name = symbols.intern("byond_version").unwrap();
        let mut header = write(
            owner,
            name,
            InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
        );
        header.target = InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name,
        };
        header.declaration_flags = None;
        let result = classify_with_diagnostics(&[header.clone()], &symbols, &Evaluator).unwrap();
        assert_eq!(result.writes[0].write.declaration_flags, None);
        assert_eq!(result.writes[0].phase, None);
        assert!(result.groups.is_empty());
        header.value = InitializerValue::Expression(expression("run()", &mut symbols).unwrap());
        let error = classify_with_diagnostics(&[header], &symbols, &Evaluator).unwrap_err();
        assert_eq!(error.issues[0].source_ordinal, 0);
        assert!(error.issues[0]
            .reason
            .contains("savefile header property requires a captured scalar"));
    }
    #[test]
    fn world_header_exception_is_exact_and_does_not_cover_runtime_fields() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/world").unwrap();
        let name = symbols.intern("fps").unwrap();
        let mut header = write(
            owner,
            name,
            InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
        );
        header.target = InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name,
        };
        header.declaration_flags = None;
        let result = classify_with_diagnostics(&[header.clone()], &symbols, &Evaluator).unwrap();
        assert_eq!(result.writes[0].write.declaration_flags, None);
        assert_eq!(result.writes[0].phase, None);
        assert!(result.groups.is_empty());
        let runtime_name = symbols.intern("time").unwrap();
        header.target = InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name: runtime_name,
        };
        let error = classify_with_diagnostics(&[header.clone()], &symbols, &Evaluator).unwrap_err();
        assert!(error.issues[0]
            .reason
            .contains("opaque initializer declaration modifiers"));
        let child = symbols.intern("/world/child").unwrap();
        header.lexical_owner = child;
        header.target = InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: child,
            name,
        };
        assert!(classify_with_diagnostics(&[header], &symbols, &Evaluator)
            .unwrap_err()
            .issues[0]
            .reason
            .contains("opaque initializer declaration modifiers"));
    }
}
