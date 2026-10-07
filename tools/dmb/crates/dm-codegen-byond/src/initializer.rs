//! Symbolic initializer writes through the shared expression/assignment lowerer.
//! Runtime scheduling, default-record packing and table IDs remain linker policy.
use crate::{
    lower_resolver::{ResolvedSlot, ResolverProc},
    ProcedureInputs, Symbol, Table,
};
use byond_dmb::bytecode::opcode;
use dm_ir::{
    InitializerTarget, InitializerValue, InitializerWrite, ResolveQuery, ResolvedMeaning, Resolver,
    SymbolTable,
};
#[derive(Debug)]
pub enum InitializerError {
    Unsupported(String),
    Invalid(String),
    Lowering(Vec<crate::LowerError>),
}
pub struct InitializerProcedure {
    pub write: InitializerWrite,
    pub code: ResolverProc,
}
pub struct InitializerContext<'a> {
    pub symbols: &'a SymbolTable,
    pub resource_search_context: Option<u128>,
    /// The caller maps the parser-only container to this write's captured source
    /// occurrence. No generated path is substituted for an authored source file.
    pub debug: Option<&'a dyn crate::DebugSourceProvider>,
}
pub fn lower_write<R: Resolver>(
    write: &InitializerWrite,
    context: InitializerContext<'_>,
    host: &R,
) -> Result<Option<InitializerProcedure>, InitializerError> {
    let expected_procedure = match write.target {
        InitializerTarget::ProcedureStatic(identity) => Some(identity.procedure),
        _ => None,
    };
    if write.lexical_procedure != expected_procedure
        || expected_procedure.is_some_and(|procedure| procedure.owner != write.lexical_owner)
    {
        return Err(InitializerError::Invalid(
            "initializer lexical procedure differs from target".into(),
        ));
    }
    let expression = match &write.value {
        InitializerValue::NoAuthoredValue => return Ok(None),
        InitializerValue::ArrayAllocation(_) => {
            return Err(InitializerError::Unsupported(
                "array initializer allocation is not implemented".into(),
            ))
        }
        InitializerValue::Expression(expression) => expression,
    };
    if write.declared_array.is_some() {
        return Err(InitializerError::Unsupported(
            "authored array initialization requires explicit allocation policy".into(),
        ));
    }
    let flags = write.declaration_flags.ok_or_else(|| {
        InitializerError::Unsupported("initializer declaration modifiers are unknown".into())
    })?;
    if flags & !0x0d != 0 {
        return Err(InitializerError::Unsupported(
            "const or unknown initializer modifiers require default-record evaluation".into(),
        ));
    }
    let text = expression.source_text(context.symbols).ok_or_else(|| {
        InitializerError::Invalid("initializer expression spelling unavailable".into())
    })?;
    let parsed = dm_syntax::parse_expression(&text);
    if !parsed.diagnostics.is_empty() {
        return Err(InitializerError::Unsupported(
            "initializer expression syntax cannot be lowered".into(),
        ));
    }
    let value = parsed
        .expr
        .ok_or_else(|| InitializerError::Invalid("initializer expression missing".into()))?;
    let code = lower_assignment(&write.target, write.lexical_owner, &value, context, host)?;
    Ok(Some(InitializerProcedure {
        write: write.clone(),
        code,
    }))
}

/// Lower an authored or policy-issued typed assignment. Declaration default
/// flags are intentionally outside this API (map overrides are assignments).
pub fn lower_assignment<R: Resolver>(
    target: &InitializerTarget,
    lexical_owner: dm_ir::SymbolId,
    value: &dm_syntax::Expr,
    context: InitializerContext<'_>,
    host: &R,
) -> Result<ResolverProc, InitializerError> {
    lower_assignments(
        &[(target.clone(), lexical_owner, value.clone())],
        lexical_owner,
        context,
        host,
    )
}

/// Ordered writes in one lexical/receiver scope, compiled as one VM unit.
/// Empty units are meaningful (e.g. an authored empty map initializer).
pub fn lower_assignments<R: Resolver>(
    assignments: &[(InitializerTarget, dm_ir::SymbolId, dm_syntax::Expr)],
    lexical_owner: dm_ir::SymbolId,
    context: InitializerContext<'_>,
    host: &R,
) -> Result<ResolverProc, InitializerError> {
    if context.symbols.text(lexical_owner).is_none() {
        return Err(InitializerError::Invalid(
            "initializer lexical owner spelling missing".into(),
        ));
    }
    if assignments
        .iter()
        .any(|(_, owner, _)| *owner != lexical_owner)
    {
        return Err(InitializerError::Unsupported(
            "mixed lexical initializer scopes".into(),
        ));
    }
    lower_scoped_assignments(assignments, context, host)
}

/// Ordered shared writes may have distinct lexical owners; receiver/lexical
/// instance writes still require one exact receiver. No procedure concatenation.
pub fn lower_scoped_assignments<R: Resolver>(
    assignments: &[(InitializerTarget, dm_ir::SymbolId, dm_syntax::Expr)],
    context: InitializerContext<'_>,
    host: &R,
) -> Result<ResolverProc, InitializerError> {
    let mut statements = Vec::with_capacity(assignments.len());
    let mut inputs = Vec::with_capacity(assignments.len());
    let mut slots = Vec::new();
    let mut instance = None;
    let mut receiver = None;
    for (target, owner, value) in assignments {
        let current_instance = matches!(target, InitializerTarget::Instance { .. });
        if instance.is_some_and(|previous| previous != current_instance) {
            return Err(InitializerError::Unsupported(
                "mixed shared and instance initializer writes".into(),
            ));
        }
        instance = Some(current_instance);
        if let InitializerTarget::Instance { receiver_owner, .. } = target {
            if receiver.is_some_and(|previous| previous != *receiver_owner) {
                return Err(InitializerError::Unsupported(
                    "mixed initializer receivers".into(),
                ));
            }
            receiver = Some(*receiver_owner);
        }
        let (statement, slot) = prepare_assignment(target, *owner, value, &context, host)?;
        statements.push(statement);
        let owner_text = context.symbols.text(*owner).ok_or_else(|| {
            InitializerError::Invalid("initializer lexical owner spelling missing".into())
        })?;
        inputs.push(ProcedureInputs {
            procedure_identity: match target {
                InitializerTarget::ProcedureStatic(identity) => Some(identity.procedure),
                _ => None,
            },
            current_type_path: (owner_text != "/").then(|| owner_text.to_owned()),
            resource_search_context: context.resource_search_context,
            ..ProcedureInputs::default()
        });
        if let Some(slot) = slot {
            slots.push(slot);
        }
    }
    let scopes = statements
        .iter()
        .zip(&inputs)
        .map(|(statement, inputs)| crate::typed_scopes::TypedScope {
            inputs,
            statements: std::slice::from_ref(statement),
        })
        .collect::<Vec<_>>();
    let mut code =
        crate::compile_typed_scopes_with_resolver(&scopes, context.symbols, host, context.debug)
            .map_err(InitializerError::Lowering)?;
    finish_initializer(&mut code, instance == Some(true))?;
    attach_target_slots(&mut code, slots)?;
    Ok(code)
}

fn attach_target_slots(
    code: &mut ResolverProc,
    slots: Vec<(Symbol, ResolvedSlot)>,
) -> Result<(), InitializerError> {
    // One scan per unit, rather than rescanning the common global initializer
    // for every write. Exact table/key identity remains the membership domain.
    let mut references = std::collections::HashSet::new();
    code.procedure.code.for_each_reference(|table, name| {
        references.insert(Symbol::new(table, name));
    });
    for (symbol, slot) in slots {
        if !references.contains(&symbol) {
            return Err(InitializerError::Invalid(
                "initializer did not emit its exact shared target".into(),
            ));
        }
        if code
            .slots
            .insert(symbol, slot.clone())
            .is_some_and(|previous| previous != slot)
        {
            return Err(InitializerError::Invalid(
                "initializer target slot conflicts with consumed reference".into(),
            ));
        }
    }
    Ok(())
}

type PreparedAssignment = (dm_syntax::Statement, Option<(Symbol, ResolvedSlot)>);
fn prepare_assignment<R: Resolver>(
    target: &InitializerTarget,
    lexical_owner: dm_ir::SymbolId,
    value: &dm_syntax::Expr,
    context: &InitializerContext<'_>,
    host: &R,
) -> Result<PreparedAssignment, InitializerError> {
    let text = |id| {
        context.symbols.text(id).ok_or_else(|| {
            InitializerError::Invalid("initializer symbol spelling unavailable".into())
        })
    };
    let lexical_owner = text(lexical_owner)?;
    if matches!(target, InitializerTarget::ProcedureStatic(identity) if identity.procedure.owner != dm_ir::SymbolId::of(lexical_owner))
    {
        return Err(InitializerError::Invalid(
            "static initializer lexical owner differs from procedure".into(),
        ));
    }
    let (owner, name) = match *target {
        InitializerTarget::ProcedureStatic(identity) => (identity.procedure.owner, identity.name),
        InitializerTarget::Shared { owner, name, .. } => (owner, name),
        InitializerTarget::Instance {
            receiver_owner,
            name,
            ..
        } => (receiver_owner, name),
    };
    let name_text = text(name)?;
    let lexed = dm_syntax::lex(name_text);
    if lexed.tokens.len() != 1 || lexed.tokens[0].kind != dm_syntax::TokenKind::Ident {
        return Err(InitializerError::Invalid(
            "initializer target is not one identifier".into(),
        ));
    }
    let query = match target {
        InitializerTarget::ProcedureStatic(identity) => ResolveQuery::ProcedureStatic {
            procedure: identity.procedure,
            name: identity.name,
        },
        _ => ResolveQuery::VarStorage { owner, name },
    };
    let meaning = host.resolve(query);
    let target_slot = match (target, meaning) {
        (
            InitializerTarget::ProcedureStatic(identity),
            ResolvedMeaning::ProcedureStatic(declaration),
        ) if declaration.identity == *identity => None,
        (
            InitializerTarget::Shared { slot, owner, name },
            ResolvedMeaning::Slot {
                symbol,
                owner: actual_owner,
                name: actual_name,
            },
        ) if *slot == symbol && *owner == actual_owner && *name == actual_name => {
            Some(ResolvedSlot {
                symbol,
                owner: actual_owner,
                name: actual_name,
            })
        }
        (
            InitializerTarget::Instance {
                declaring_owner,
                name,
                ..
            },
            ResolvedMeaning::InstanceField {
                declaring_owner: actual_owner,
                name: actual_name,
            },
        ) if *declaring_owner == actual_owner && *name == actual_name => None,
        (_, ResolvedMeaning::Unsupported(_)) => {
            return Err(InitializerError::Unsupported(
                "initializer target storage is unsupported".into(),
            ))
        }
        _ => {
            return Err(InitializerError::Invalid(
                "initializer target differs from exact resolver storage".into(),
            ))
        }
    };
    let owner_text = text(owner)?;
    let span = value.span;
    let target_expr = match *target {
        InitializerTarget::ProcedureStatic(_) => dm_syntax::Expr {
            span,
            kind: dm_syntax::ExprKind::Ident(name_text.to_owned()),
        },
        InitializerTarget::Shared { .. } => dm_syntax::Expr {
            span,
            kind: dm_syntax::ExprKind::Member {
                object: Box::new(dm_syntax::Expr {
                    span,
                    kind: if owner_text == "/" {
                        dm_syntax::ExprKind::Ident("global".into())
                    } else {
                        dm_syntax::ExprKind::TypePath(owner_text.to_owned())
                    },
                }),
                selector: name_text.to_owned(),
                via_colon: false,
            },
        },
        InitializerTarget::Instance { .. } => {
            if lexical_owner != owner_text {
                return Err(InitializerError::Unsupported(
                    "initializer receiver differs from its lexical owner".into(),
                ));
            }
            dm_syntax::Expr {
                span,
                kind: dm_syntax::ExprKind::Ident(name_text.to_owned()),
            }
        }
    };
    let statement = dm_syntax::Statement {
        span,
        header_span: span,
        raw_header: "initializer assignment".into(),
        kind: dm_syntax::StatementKind::Assign {
            target: target_expr,
            op: "=".into(),
            value: value.clone(),
        },
    };
    let slot = target_slot.map(|slot| {
        let key = if owner_text == "/" {
            name_text.to_owned()
        } else {
            format!("var{}/{name_text}", owner_text.trim_end_matches('/'))
        };
        (Symbol::new(Table::Variable, key), slot)
    });
    Ok((statement, slot))
}

fn finish_initializer(code: &mut ResolverProc, instance: bool) -> Result<(), InitializerError> {
    // Match the initializer VM receiver convention used by the existing
    // producer. This is an initializer entry, not an ordinary returning proc.
    if instance {
        for item in &mut code.procedure.code.items {
            if let crate::Item::Instruction(instruction) = item {
                if instruction.opcode == opcode::SET_VAR {
                    if let [crate::Word::Variable(crate::VariableWord::Field(field))] =
                        instruction.operands.as_slice()
                    {
                        instruction.operands =
                            vec![crate::Word::Variable(crate::VariableWord::SetCache(
                                Box::new(crate::VariableWord::Src),
                                Box::new(crate::VariableWord::SetCache(
                                    Box::new(crate::VariableWord::Src),
                                    Box::new(crate::VariableWord::Field(field.clone())),
                                )),
                            ))];
                    }
                }
            }
        }
    }
    let items = &mut code.procedure.code.items;
    if items.len() >= 3
        && matches!(&items[items.len()-3], crate::Item::Instruction(ins)
            if ins.opcode == opcode::PUSH_VAL && ins.operands == [crate::Word::Value(crate::ValueWord::Null)])
        && matches!(&items[items.len()-2], crate::Item::Instruction(ins)
            if ins.opcode == opcode::RET && ins.operands.is_empty())
        && matches!(&items[items.len()-1], crate::Item::Instruction(ins)
            if ins.opcode == opcode::END && ins.operands.is_empty())
    {
        items.truncate(items.len() - 3);
        items.push(crate::Item::Instruction(crate::Instruction {
            opcode: opcode::END,
            operands: Vec::new(),
        }));
    }
    if !matches!(items.last(),Some(crate::Item::Instruction(ins))
        if ins.opcode == opcode::END && ins.operands.is_empty())
        || items
            .iter()
            .any(|item| matches!(item,crate::Item::Instruction(ins) if ins.opcode == opcode::RET))
    {
        return Err(InitializerError::Unsupported(
            "initializer has an unsupported value-return epilogue".into(),
        ));
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ExpressionToken, SymbolId, SymbolicExpression};
    fn expression(text: &str, symbols: &mut SymbolTable) -> SymbolicExpression {
        SymbolicExpression {
            tokens: dm_syntax::lex(text)
                .tokens
                .into_iter()
                .filter(|t| {
                    !matches!(
                        t.kind,
                        dm_syntax::TokenKind::Whitespace
                            | dm_syntax::TokenKind::Newline
                            | dm_syntax::TokenKind::Comment
                    )
                })
                .map(|t| ExpressionToken {
                    kind: t.kind,
                    text: symbols.intern(&t.text).unwrap(),
                    relative_span: t.span,
                })
                .collect::<Vec<_>>()
                .into(),
        }
    }
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, q: ResolveQuery) -> ResolvedMeaning {
            match q {
                ResolveQuery::VarStorage { owner, name }
                    if owner == SymbolId::of("/") && name == SymbolId::of("counter") =>
                {
                    ResolvedMeaning::Slot {
                        symbol: SymbolId::of("exact-slot"),
                        owner,
                        name,
                    }
                }
                ResolveQuery::GlobalVar(name) if name == SymbolId::of("counter") => {
                    // A global presence alone does not certify its declared type.
                    ResolvedMeaning::Member {
                        owner: SymbolId::of("/"),
                        name,
                        fingerprint: 1,
                        data: std::sync::Arc::new(dm_ir::DeclarationMeaning::default()),
                    }
                }
                ResolveQuery::GlobalVar(_) => ResolvedMeaning::Missing,
                ResolveQuery::HasMemberVar { owner, name }
                    if owner == SymbolId::of("/datum/item") && name == SymbolId::of("amount") =>
                {
                    ResolvedMeaning::Presence(true)
                }
                ResolveQuery::DeclaredVarType { owner, name }
                    if owner == SymbolId::of("/datum/item") && name == SymbolId::of("amount") =>
                {
                    ResolvedMeaning::DeclaredType(None)
                }
                ResolveQuery::VarStorage { owner, name }
                    if owner == SymbolId::of("/datum/item") && name == SymbolId::of("amount") =>
                {
                    ResolvedMeaning::InstanceField {
                        declaring_owner: owner,
                        name,
                    }
                }
                _ => ResolvedMeaning::Unsupported(q),
            }
        }
    }
    #[test]
    fn static_startup_assignments_keep_separate_procedure_slots_in_one_unit() {
        struct StaticHost;
        impl Resolver for StaticHost {
            fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
                match query {
                    ResolveQuery::ProcedureStatic { procedure, name } => {
                        ResolvedMeaning::ProcedureStatic(std::sync::Arc::new(
                            dm_ir::ProcedureStaticDeclaration {
                                identity: dm_ir::ProcedureStaticIdentity { procedure, name },
                                declared_type: None,
                                modifiers: 1,
                                declared_array: None,
                                initializer: InitializerValue::NoAuthoredValue,
                            },
                        ))
                    }
                    other => ResolvedMeaning::Unsupported(other),
                }
            }
        }
        let mut symbols = SymbolTable::default();
        for text in ["/", "first", "second", "counter"] {
            symbols.intern(text).unwrap();
        }
        let targets = ["first", "second"].map(|name| {
            InitializerTarget::ProcedureStatic(dm_ir::ProcedureStaticIdentity {
                procedure: dm_ir::ProcedureIdentity {
                    owner: SymbolId::of("/"),
                    name: SymbolId::of(name),
                    verb: false,
                    occurrence: 0,
                },
                name: SymbolId::of("counter"),
            })
        });
        let value = dm_syntax::parse_expression("1").expr.unwrap();
        let assignments = targets
            .into_iter()
            .map(|target| (target, SymbolId::of("/"), value.clone()))
            .collect::<Vec<_>>();
        let code = lower_scoped_assignments(
            &assignments,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &StaticHost,
        )
        .unwrap();
        assert_eq!(code.procedure_statics.len(), 2);
        assert!(code
            .procedure_statics
            .values()
            .any(|identity| identity.procedure.name == SymbolId::of("first")));
        assert!(code
            .procedure_statics
            .values()
            .any(|identity| identity.procedure.name == SymbolId::of("second")));
        assert_eq!(code.procedure.code.items.iter().filter(|item|matches!(item,crate::Item::Instruction(instruction) if instruction.opcode==opcode::END)).count(),1);
    }
    #[test]
    fn shared_assignment_retains_exact_slot_receipt_without_output_tables() {
        let mut symbols = SymbolTable::default();
        symbols.intern("/").unwrap();
        symbols.intern("counter").unwrap();
        let write = InitializerWrite {
            target: InitializerTarget::Shared {
                slot: SymbolId::of("exact-slot"),
                owner: SymbolId::of("/"),
                name: SymbolId::of("counter"),
            },
            lexical_owner: SymbolId::of("/"),
            lexical_procedure: None,
            value: InitializerValue::Expression(expression("7", &mut symbols)),
            declared_array: None,
            declaration_flags: Some(8),
        };
        let result = lower_write(
            &write,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &Host,
        )
        .unwrap()
        .unwrap();
        assert_eq!(
            result
                .code
                .slots
                .get(&Symbol::new(Table::Variable, "counter"))
                .unwrap()
                .symbol,
            SymbolId::of("exact-slot")
        );
        assert!(matches!(result.code.procedure.code.items.last(),
            Some(crate::Item::Instruction(ins)) if ins.opcode == opcode::END));
        assert!(!result.code.procedure.code.items.iter().any(
            |item| matches!(item, crate::Item::Instruction(ins) if ins.opcode == opcode::RET)
        ));
        let mut code = result.code;
        let before = code.procedure.code.clone();
        let symbol = Symbol::new(Table::Variable, "counter");
        let slot = code.slots[&symbol].clone();
        attach_target_slots(&mut code, vec![(symbol.clone(), slot.clone()),
            (symbol.clone(), slot.clone())]).unwrap();
        assert_eq!(code.procedure.code, before);
        assert_eq!(code.slots.len(), 1);
        let mut conflicting = slot.clone();
        conflicting.name = dm_ir::SymbolId::of("different-name");
        assert!(matches!(attach_target_slots(&mut code, vec![(symbol, conflicting)]),
            Err(InitializerError::Invalid(message)) if message.contains("conflicts")));
        assert!(matches!(attach_target_slots(&mut code,
            vec![(Symbol::new(Table::String, "counter"), slot)]),
            Err(InitializerError::Invalid(message)) if message.contains("exact shared target")));
    }
    #[test]
    fn instance_initializer_uses_initializer_receiver_and_end_only() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/datum/item").unwrap();
        let name = symbols.intern("amount").unwrap();
        let write = InitializerWrite {
            target: InitializerTarget::Instance {
                declaring_owner: owner,
                receiver_owner: owner,
                name,
            },
            lexical_owner: owner,
            lexical_procedure: None,
            value: InitializerValue::Expression(expression("7", &mut symbols)),
            declared_array: None,
            declaration_flags: Some(0),
        };
        let result = lower_write(
            &write,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &Host,
        )
        .unwrap()
        .unwrap();
        assert!(result.code.procedure.code.items.iter().any(|item|
            matches!(item, crate::Item::Instruction(ins) if ins.opcode == opcode::SET_VAR
                && ins.operands == [crate::Word::Variable(crate::VariableWord::SetCache(
                    Box::new(crate::VariableWord::Src), Box::new(crate::VariableWord::Field("amount".into()))))])));
        assert!(!result.code.procedure.code.items.iter().any(
            |item| matches!(item, crate::Item::Instruction(ins) if ins.opcode == opcode::RET)
        ));
        let parsed = dm_syntax::parse_expression("7").expr.unwrap();
        let unit = lower_assignments(
            &[
                (write.target.clone(), owner, parsed.clone()),
                (write.target.clone(), owner, parsed),
            ],
            owner,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &Host,
        )
        .unwrap();
        assert_eq!(unit.procedure.code.items.iter().filter(|item|
            matches!(item,crate::Item::Instruction(ins) if ins.opcode==opcode::SET_VAR)).count(),2);
        assert_eq!(
            unit.procedure
                .code
                .items
                .iter()
                .filter(
                    |item| matches!(item,crate::Item::Instruction(ins) if ins.opcode==opcode::END)
                )
                .count(),
            1
        );
        let empty = lower_assignments(
            &[],
            owner,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &Host,
        )
        .unwrap();
        assert_eq!(
            empty.procedure.code.items,
            [crate::Item::Instruction(crate::Instruction {
                opcode: opcode::END,
                operands: Vec::new()
            })]
        );
    }
    #[test]
    fn unknown_modifiers_decline_and_no_value_does_not_invent_null() {
        let mut symbols = SymbolTable::default();
        let value = InitializerValue::Expression(expression("7", &mut symbols));
        let mut write = InitializerWrite {
            target: InitializerTarget::Shared {
                slot: SymbolId::of("s"),
                owner: SymbolId::of("/"),
                name: SymbolId::of("x"),
            },
            lexical_owner: SymbolId::of("/"),
            lexical_procedure: None,
            value,
            declared_array: None,
            declaration_flags: None,
        };
        assert!(matches!(
            lower_write(
                &write,
                InitializerContext {
                    symbols: &symbols,
                    resource_search_context: None,
                    debug: None
                },
                &Host
            ),
            Err(InitializerError::Unsupported(_))
        ));
        write.value = InitializerValue::NoAuthoredValue;
        assert!(lower_write(
            &write,
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None
            },
            &Host
        )
        .unwrap()
        .is_none());
    }
    #[test]
    fn shared_initializer_switches_lexical_scopes_in_one_code_namespace() {
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let owner = symbols.intern("/datum/item").unwrap();
        let name = symbols.intern("counter").unwrap();
        symbols.intern("amount").unwrap();
        let target = InitializerTarget::Shared {
            slot: SymbolId::of("exact-slot"),
            owner: root,
            name,
        };
        let first = dm_syntax::parse_expression("amount ? 7 : 8").expr.unwrap();
        let second = dm_syntax::parse_expression("counter ? 7 : 8").expr.unwrap();
        let code = lower_scoped_assignments(
            &[(target.clone(), owner, first), (target, root, second)],
            InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &Host,
        )
        .unwrap();
        assert_eq!(
            code.procedure
                .code
                .items
                .iter()
                .filter(
                    |item| matches!(item,crate::Item::Instruction(ins) if ins.opcode==opcode::END)
                )
                .count(),
            1
        );
        assert!(code.procedure.code.items.iter().any(|item|
            matches!(item,crate::Item::Instruction(ins) if ins.operands.contains(&crate::Word::Variable(crate::VariableWord::SetCache(
                Box::new(crate::VariableWord::Src),Box::new(crate::VariableWord::Field("amount".into()))))))));
        let labels = code
            .procedure
            .code
            .items
            .iter()
            .filter_map(|item| match item {
                crate::Item::Label(label) => Some(label),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert!(!labels.is_empty());
        assert_eq!(
            labels
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len(),
            labels.len()
        );
    }
}
