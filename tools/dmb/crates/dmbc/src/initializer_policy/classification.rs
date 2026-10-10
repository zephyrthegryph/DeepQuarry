#[path = "classification/transform.rs"]
mod transform;
use super::*;
pub(super) struct PendingWrite {
    pub(super) write: ClassifiedWrite,
    pub(super) key: Option<Vec<u8>>,
    pub(super) accepted: Option<Arc<artifact::SemanticClassification>>,
    pub(super) parsed_runtime_source: Option<String>,
}
fn classify_pending<'a>(
    writes: impl ExactSizeIterator<Item = &'a InitializerWrite>,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    facts: &[ModifierFact],
    source_ordinal: &mut usize,
) -> Result<Vec<PendingWrite>, String> {
    let mut classified = Vec::with_capacity(writes.len());
    for (ordinal, original) in writes.enumerate() {
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
                accepted: None,
                parsed_runtime_source: None,
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
                    accepted: None,
                    parsed_runtime_source: None,
                });
                continue;
            }
        }
        let mut parsed_runtime = None;
        let mut parsed_runtime_source = None;
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
                        // The evaluated tree is used only to distinguish literal-list
                        // construction. Do not retain it while preparing the runtime
                        // AST and evaluating constructor arguments again.
                        let scalar_list =
                            matches!(evaluation, Evaluation::Scalar(SemanticValue::List(_)));
                        drop(evaluation);
                        let prepared = match prepared {
                            Some(prepared) => prepared,
                            None => PreparedInitializerExpression::parse_captured(value, symbols)?
                                .ok_or("missing initializer expression")?,
                        };
                        let (text, ast, authored) = prepared.into_parts();
                        let parser_issued = authored.as_ref() == Some(value);
                        let expr = &ast;
                        if let Some(matrix) =
                            transform::fold(&write, expr, &text, symbols, evaluator)?
                        {
                            classified.push(PendingWrite {
                                write: ClassifiedWrite {
                                    source_ordinal: ordinal,
                                    write,
                                    default: DefaultValue::Transform(matrix),
                                    phase: None,
                                    runtime_value: None,
                                },
                                key: None,
                                accepted: None,
                                parsed_runtime_source: None,
                            });
                            continue;
                        }
                        let literal =
                            scalar_list || scalar_literal(expr, &write, symbols, &text, evaluator)?;
                        let default = if let Some(key) =
                            crate::initializer_tokens::construction_key(
                                expr, &text, &write, symbols, evaluator,
                            )? {
                            pending_key = Some(key);
                            DefaultValue::Scalar(SemanticValue::Null)
                        } else {
                            DefaultValue::Scalar(SemanticValue::Null)
                        };
                        if parser_issued {
                            parsed_runtime_source = Some(text);
                        }
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
            Some(RuntimeValue::Expression(Arc::new(
                parsed_runtime.ok_or("runtime expression missing")?,
            )))
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
            accepted: None,
            parsed_runtime_source,
        });
    }
    Ok(classified)
}
fn finish_pending(
    pending: impl ExactSizeIterator<Item = PendingWrite>,
    debug_defined: bool,
    source_ordinal: &mut usize,
) -> Result<ClassifiedInitializers, String> {
    let mut tokens = crate::initializer_tokens::Tokens::new(debug_defined);
    let mut classified = Vec::with_capacity(pending.len());
    let mut admitted_owners = Vec::with_capacity(pending.len());
    for PendingWrite {
        mut write,
        key,
        accepted,
        parsed_runtime_source: _,
    } in pending
    {
        let key = key.or_else(|| {
            accepted
                .as_ref()
                .and_then(|value| value.token_key().cloned())
        });
        *source_ordinal = write.source_ordinal;
        if let Some(key) = key {
            let (token, canonical) = tokens.issue(key)?;
            write.default = DefaultValue::InitializerExpression { token, canonical };
        }
        admitted_owners.push(accepted.map(ClassificationOwner::new));
        classified.push(write);
    }
    let mut groups: Vec<RuntimeGroup> = Vec::new();
    let mut receiver_groups = std::collections::HashMap::new();
    for (write_index, write) in classified.iter().enumerate() {
        // An authored unsized instance-array declaration owns an initializer
        // even though its null value emits no allocation or assignment.
        // Inherited arrays have no declared_array receipt on the current write.
        let empty_instance_initializer =
            matches!(write.write.target, InitializerTarget::Instance { .. })
                && matches!(write.write.value, InitializerValue::NoAuthoredValue)
                && write.write.declared_array.as_ref().is_some_and(|array| {
                    array.dimensions.len() == 1 && array.dimensions[0].is_none()
                });
        if write.phase.is_none() && !empty_instance_initializer {
            continue;
        }
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
        if write.phase.is_some() {
            groups[index].writes.push(write_index);
        }
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
        accepted: admitted_owners,
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
        classify_pending(writes.iter(), symbols, evaluator, facts, source_ordinal)?.into_iter(),
        debug_defined,
        source_ordinal,
    )
}

pub(super) mod artifact;
pub(super) mod parallel;

#[path = "classification/token_roster.rs"]
mod token_roster;
