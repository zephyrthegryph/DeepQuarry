use super::*;
pub(super) struct PendingWrite {
    pub(super) write: ClassifiedWrite,
    pub(super) key: Option<Vec<u8>>,
}
fn classify_pending(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    facts: &[ModifierFact],
    source_ordinal: &mut usize,
) -> Result<Vec<PendingWrite>, String> {
    let mut classified = Vec::with_capacity(writes.len());
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
            classified.push(PendingWrite {
                write: ClassifiedWrite {
                    source_ordinal: ordinal,
                    write: original.clone(),
                    default: DefaultValue::Scalar(value),
                    phase: None,
                    runtime_value: None,
                },
                key: None,
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
                classified.push(PendingWrite {
                    write: ClassifiedWrite {
                        source_ordinal: ordinal,
                        write,
                        default,
                        phase: Some(Phase::LiteralAllocation),
                        runtime_value: Some(RuntimeValue::SizedArray(dimensions.into())),
                    },
                    key: None,
                });
                continue;
            }
        }
        let mut parsed_runtime = None;
        let mut pending_key = None;
        let (default, phase) = match &write.value {
            InitializerValue::NoAuthoredValue => (DefaultValue::Scalar(SemanticValue::Null), None),
            InitializerValue::ArrayAllocation(_) => {
                return Err("array allocation lacks authored shape".into())
            }
            InitializerValue::Expression(value) => {
                let (evaluation, prepared) = evaluator.evaluate_prepared_write(&write, value)?;
                match evaluation {
                    Evaluation::Scalar(value) if !matches!(value, SemanticValue::List(_)) => {
                        (DefaultValue::Scalar(value), None)
                    }
                    evaluation => {
                        if constant_binding {
                            return Err("const initializer is not scalar".into());
                        }
                        let PreparedInitializerExpression { source: text, ast } = match prepared {
                            Some(prepared) => prepared,
                            None => {
                                let text = value
                                    .source_text(symbols)
                                    .ok_or("initializer spelling missing")?;
                                let parsed = dm_syntax::parse_expression(&text);
                                if !parsed.diagnostics.is_empty() {
                                    return Err("invalid initializer expression".into());
                                }
                                PreparedInitializerExpression {
                                    source: text,
                                    ast: parsed.expr.ok_or("missing initializer expression")?,
                                }
                            }
                        };
                        let expr = &ast;
                        let literal =
                            matches!(evaluation, Evaluation::Scalar(SemanticValue::List(_)))
                                || scalar_literal(expr, &write, symbols, &text, evaluator)?;
                        let default = if let Some(key) =
                            crate::initializer_tokens::construction_key(
                                expr, &text, &write, symbols, evaluator,
                            )? {
                            pending_key = Some(key);
                            DefaultValue::Scalar(SemanticValue::Null)
                        } else {
                            DefaultValue::Scalar(SemanticValue::Null)
                        };
                        parsed_runtime = Some(ast);
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
        classified.push(PendingWrite {
            write: ClassifiedWrite {
                source_ordinal: ordinal,
                write,
                default,
                phase,
                runtime_value,
            },
            key: pending_key,
        });
    }
    Ok(classified)
}
fn finish_pending(
    pending: Vec<PendingWrite>,
    debug_defined: bool,
    source_ordinal: &mut usize,
) -> Result<ClassifiedInitializers, String> {
    let mut tokens = crate::initializer_tokens::Tokens::new(debug_defined);
    let mut classified = Vec::with_capacity(pending.len());
    for PendingWrite { mut write, key } in pending {
        *source_ordinal = write.source_ordinal;
        if let Some(key) = key {
            let (token, canonical) = tokens.issue(key)?;
            write.default = DefaultValue::InitializerExpression { token, canonical };
        }
        classified.push(write);
    }
    let mut groups: Vec<RuntimeGroup> = Vec::new();
    let mut receiver_groups = std::collections::HashMap::new();
    for (write_index, write) in classified
        .iter()
        .enumerate()
        .filter(|(_, write)| write.phase.is_some())
    {
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
        groups[index].writes.push(write_index);
    }
    for group in &mut groups {
        if group.receiver.is_none() {
            // Stable partition: literal lists/sized arrays precede runtime calls;
            // each phase retains source order. Instance writes are never sorted.
            group
                .writes
                .sort_by_key(|index| classified[*index].phase == Some(Phase::Runtime));
        }
    }
    Ok(ClassifiedInitializers {
        writes: classified,
        groups,
    })
}
pub(super) fn classify_from_facts(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    facts: &[ModifierFact],
    source_ordinal: &mut usize,
    debug_defined: bool,
) -> Result<ClassifiedInitializers, String> {
    finish_pending(
        classify_pending(writes, symbols, evaluator, facts, source_ordinal)?,
        debug_defined,
        source_ordinal,
    )
}

pub(super) mod parallel;
