//! Request-owned identities for native-proven allocation defaults. Tokens own
//! no runtime value; executable construction remains a separate initializer.
use crate::initializer_policy::{CapturedInitializerEvaluator, Evaluation};
use dm_ir::{InitializerWrite, SemanticValue, SymbolTable};
use dm_syntax::{Expr, ExprKind};
use std::{collections::HashMap, sync::Arc};

pub struct Tokens {
    unique: bool,
    next: u32,
    shared: HashMap<Arc<[u8]>, u32>,
}
impl Tokens {
    pub fn new(debug_defined: bool) -> Self {
        Self {
            unique: debug_defined,
            next: 0,
            shared: HashMap::new(),
        }
    }
    pub fn issue(&mut self, key: Vec<u8>) -> Result<(u32, Arc<[u8]>), String> {
        if !self.unique {
            if let Some((retained, &token)) = self.shared.get_key_value(key.as_slice()) {
                return Ok((token, retained.clone()));
            }
        }
        let token = self.next;
        self.next = self
            .next
            .checked_add(1)
            .ok_or("initializer token space exhausted")?;
        let key: Arc<[u8]> = key.into();
        if !self.unique {
            self.shared.insert(key.clone(), token);
        }
        Ok((token, key))
    }
}
fn framed(output: &mut Vec<u8>, bytes: &[u8]) {
    output.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    output.extend_from_slice(bytes);
}
enum KeyError {
    RuntimeArgument,
    Failure(String),
}
impl From<String> for KeyError {
    fn from(error: String) -> Self {
        Self::Failure(error)
    }
}
impl From<&str> for KeyError {
    fn from(error: &str) -> Self {
        Self::Failure(error.into())
    }
}
pub fn construction_key(
    expression: &Expr,
    source: &str,
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<Option<Vec<u8>>, String> {
    let mut output = b"dm-native-initializer-expression-v1\0".to_vec();
    match construction(expression, source, write, symbols, evaluator, &mut output) {
        Ok(true) => Ok(Some(output)),
        Ok(false) | Err(KeyError::RuntimeArgument) => Ok(None),
        Err(KeyError::Failure(error)) => Err(error),
    }
}
fn argument(
    expression: &Expr,
    source: &str,
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    output: &mut Vec<u8>,
) -> Result<(), KeyError> {
    if construction(expression, source, write, symbols, evaluator, output)? {
        return Ok(());
    }
    let Evaluation::Scalar(value) =
        evaluator.evaluate_ast_write(write, expression, source, symbols)?
    else {
        return Err(KeyError::RuntimeArgument);
    };
    output.push(0);
    framed(output, &evaluator.initializer_token_scalar(&value)?);
    Ok(())
}
fn arguments(
    arguments: &[Expr],
    list: bool,
    source: &str,
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    output: &mut Vec<u8>,
) -> Result<(), KeyError> {
    output.extend_from_slice(&(arguments.len() as u64).to_le_bytes());
    for expression in arguments {
        if let ExprKind::Binary { op, lhs, rhs } = &expression.kind {
            if op == "=" {
                output.push(1);
                if list {
                    if let ExprKind::Ident(name) = &lhs.kind {
                        output.push(0);
                        framed(
                            output,
                            &SemanticValue::Text(name.as_bytes().into()).canonical_bytes(),
                        );
                    } else {
                        argument(lhs, source, write, symbols, evaluator, output)?;
                    }
                } else if let ExprKind::Ident(name) = &lhs.kind {
                    framed(output, name.as_bytes());
                } else {
                    return Err("initializer named argument lacks a captured name".into());
                }
                argument(rhs, source, write, symbols, evaluator, output)?;
                continue;
            }
        }
        output.push(0);
        argument(expression, source, write, symbols, evaluator, output)?;
    }
    Ok(())
}
fn new_key(
    path: dm_ir::SymbolId,
    args: &[Expr],
    source: &str,
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    output: &mut Vec<u8>,
) -> Result<(), KeyError> {
    output.push(2);
    output.extend_from_slice(&path.bits().to_le_bytes());
    // Native builtin container constructors accept association keys as values,
    // not only ordinary constructor parameter names. Their family remains New:
    // new/list(3) is a length allocation, unlike the one-item literal list(3).
    let associations =
        path == dm_ir::SymbolId::of("/list") || path == dm_ir::SymbolId::of("/alist");
    arguments(
        args,
        associations,
        source,
        write,
        symbols,
        evaluator,
        output,
    )
}
fn construction(
    expression: &Expr,
    source: &str,
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    output: &mut Vec<u8>,
) -> Result<bool, KeyError> {
    match &expression.kind {
        ExprKind::Group(inner) => {
            return construction(inner, source, write, symbols, evaluator, output)
        }
        ExprKind::Unary { op, value } if op == "new" => {
            let (path, args): (_, &[Expr]) = match &value.kind {
                ExprKind::TypePath(path) => (path, &[]),
                ExprKind::Call { callee, args } => {
                    let ExprKind::TypePath(path) = &callee.kind else {
                        return Ok(false);
                    };
                    (path, args)
                }
                _ => return Ok(false),
            };
            let ast = if let ExprKind::Call { callee, .. } = &value.kind {
                callee
            } else {
                value
            };
            match evaluator.evaluate_ast_write(write, ast, source, symbols)? {
                Evaluation::Scalar(SemanticValue::Type(path)) => {
                    new_key(path, args, source, write, symbols, evaluator, output)?;
                }
                Evaluation::Scalar(value @ SemanticValue::Procedure(_)) => {
                    // BYOND constructs from the proc reference value (tag0x26),
                    // not a fabricated class. Keep owner/namespace/occurrence
                    // in the expression identity; executable lowering already
                    // emits ProcPath followed by NEW for this captured target.
                    output.push(5);
                    framed(output, &evaluator.initializer_token_scalar(&value)?);
                    arguments(args, false, source, write, symbols, evaluator, output)?;
                }
                _ => {
                    return Err(
                        format!("initializer constructor target {path} is not captured").into(),
                    );
                }
            }
        }
        ExprKind::Ident(name) if name == "new" => {
            new_key(
                evaluator
                    .initializer_constructor_type(write)?
                    .ok_or("inferred initializer constructor type unavailable")?,
                &[],
                source,
                write,
                symbols,
                evaluator,
                output,
            )?;
        }
        ExprKind::Call { callee, args } => {
            let ExprKind::Ident(name) = &callee.kind else {
                return Ok(false);
            };
            match name.as_str() {
                "new" => new_key(
                    evaluator
                        .initializer_constructor_type(write)?
                        .ok_or("inferred initializer constructor type unavailable")?,
                    args,
                    source,
                    write,
                    symbols,
                    evaluator,
                    output,
                )?,
                "list" => {
                    output.push(1);
                    arguments(args, true, source, write, symbols, evaluator, output)?;
                }
                "alist" => {
                    output.push(4);
                    arguments(args, true, source, write, symbols, evaluator, output)?;
                }
                "newlist" => {
                    output.push(1);
                    output.extend_from_slice(&(args.len() as u64).to_le_bytes());
                    for value in args {
                        let Evaluation::Scalar(SemanticValue::Type(path)) =
                            evaluator.evaluate_ast_write(write, value, source, symbols)?
                        else {
                            return Err("newlist initializer type unavailable".into());
                        };
                        output.push(0);
                        new_key(path, &[], source, write, symbols, evaluator, output)?;
                    }
                }
                "sound" | "matrix" => {
                    output.push(3);
                    framed(output, name.as_bytes());
                    arguments(args, false, source, write, symbols, evaluator, output)?;
                }
                _ => return Ok(false),
            }
        }
        _ => return Ok(false),
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Host;
    impl dm_ir::Resolver for Host {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match query {
                dm_ir::ResolveQuery::Type(id)
                    if ["/datum/token_target", "/list", "/alist"]
                        .iter()
                        .any(|path| id == dm_ir::SymbolId::of(path)) =>
                {
                    dm_ir::ResolvedMeaning::Symbol(id)
                }
                _ => dm_ir::ResolvedMeaning::Unsupported(query),
            }
        }
    }
    fn expression(source: &str, symbols: &mut SymbolTable) -> dm_ir::SymbolicExpression {
        dm_ir::SymbolicExpression {
            tokens: dm_syntax::lex(source)
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
                .map(|token| dm_ir::ExpressionToken {
                    kind: token.kind,
                    text: symbols.intern(&token.text).unwrap(),
                    relative_span: token.span,
                })
                .collect::<Vec<_>>()
                .into(),
        }
    }
    #[test]
    fn captured_proc_and_verb_constructor_defaults_keep_exact_identity() {
        struct ProcHost;
        impl dm_ir::Resolver for ProcHost {
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                match query {
                    dm_ir::ResolveQuery::ProcedureValue {
                        owner, name, verb, ..
                    } if owner == dm_ir::SymbolId::of("/datum/target")
                        && name == dm_ir::SymbolId::of("callback") =>
                    {
                        dm_ir::ResolvedMeaning::Value(SemanticValue::Procedure(
                            dm_ir::ProcedureIdentity {
                                owner,
                                name,
                                verb,
                                occurrence: 0,
                            },
                        ))
                    }
                    dm_ir::ResolveQuery::Type(id) if id == dm_ir::SymbolId::of("/datum/target") => {
                        dm_ir::ResolvedMeaning::Symbol(id)
                    }
                    _ => dm_ir::Resolver::resolve(&Host, query),
                }
            }
        }
        let mut symbols = SymbolTable::default();
        for name in [
            "/datum/target",
            "callback",
            "/datum/token_target",
            "/obj",
            "value",
        ] {
            symbols.intern(name).unwrap();
        }
        let sources = [
            "new /datum/target/verb/callback()",
            "new /datum/target/verb/callback()",
            "new /datum/target/proc/callback()",
            "new /datum/token_target()",
        ];
        let writes: Vec<_> = sources
            .iter()
            .map(|source| InitializerWrite {
                target: dm_ir::InitializerTarget::Instance {
                    declaring_owner: dm_ir::SymbolId::of("/obj"),
                    receiver_owner: dm_ir::SymbolId::of("/obj"),
                    name: dm_ir::SymbolId::of("value"),
                },
                lexical_owner: dm_ir::SymbolId::of("/obj"),
                lexical_procedure: None,
                value: dm_ir::InitializerValue::Expression(expression(source, &mut symbols)),
                declared_array: None,
                declaration_flags: Some(0),
            })
            .collect();
        let evaluator = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &ProcHost,
            symbols: &symbols,
        };
        let classified = crate::initializer_policy::classify_with_token_mode(
            &writes, &symbols, &evaluator, false,
        )
        .unwrap();
        let tokens: Vec<_> = classified
            .writes
            .iter()
            .map(|write| {
                assert_eq!(write.phase, Some(crate::initializer_policy::Phase::Runtime));
                let crate::initializer_policy::DefaultValue::InitializerExpression {
                    token, ..
                } = &write.default
                else {
                    panic!("captured construction must retain native kind62 expression identity")
                };
                *token
            })
            .collect();
        assert_eq!(tokens[0], tokens[1]);
        assert_ne!(tokens[0], tokens[2]);
        assert_ne!(tokens[0], tokens[3]);
    }
    #[test]
    fn native_allocation_default_partitions_match_across_scopes_and_debug() {
        let cases = [
            ("one", "list(1,2)"),
            ("two", "list(1,2)"),
            ("other", "list(1,3)"),
            ("snd_a", "sound(null,1)"),
            ("snd_b", "sound(null,1)"),
            ("snd_c", "sound(null,0)"),
            ("mat_a", "matrix(1,0,0,0,1,0)"),
            ("mat_b", "matrix(1,0,0,0,1,0)"),
            ("mat_c", "matrix(2,0,0,0,1,0)"),
            ("new_a", "new /datum/token_target()"),
            ("new_b", "new /datum/token_target()"),
            ("global_one", "list(1,2)"),
        ];
        for debug in [false, true] {
            let bytes: &[u8] = if debug {
                include_bytes!(
                    "../../../fixtures/translation/initializer_token_identity/debug.native.bin"
                )
            } else {
                include_bytes!(
                    "../../../fixtures/translation/initializer_token_identity/probe.native.bin"
                )
            };
            let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
            let mut symbols = SymbolTable::default();
            symbols.intern("/datum/token_target").unwrap();
            let writes: Vec<_> = cases
                .iter()
                .map(|(name, value)| {
                    let owner = dm_ir::SymbolId::of(if *name == "global_one" {
                        "/"
                    } else {
                        "/obj/first"
                    });
                    InitializerWrite {
                        target: if *name == "global_one" {
                            dm_ir::InitializerTarget::Shared {
                                slot: dm_ir::SymbolId::of(name),
                                owner,
                                name: dm_ir::SymbolId::of(name),
                            }
                        } else {
                            dm_ir::InitializerTarget::Instance {
                                declaring_owner: owner,
                                receiver_owner: owner,
                                name: dm_ir::SymbolId::of(name),
                            }
                        },
                        lexical_owner: owner,
                        lexical_procedure: None,
                        value: dm_ir::InitializerValue::Expression(expression(value, &mut symbols)),
                        declared_array: None,
                        declaration_flags: Some(if *name == "global_one" { 8 } else { 0 }),
                    }
                })
                .collect();
            let evaluator = crate::driver_facts::DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: &Host,
                symbols: &symbols,
            };
            let classified = crate::initializer_policy::classify_with_token_mode(
                &writes, &symbols, &evaluator, debug,
            )
            .unwrap();
            let actual: Vec<_> = classified
                .writes
                .iter()
                .map(|write| match &write.default {
                    crate::initializer_policy::DefaultValue::InitializerExpression {
                        token,
                        ..
                    } => *token,
                    _ => panic!("proven allocation default must retain kind62"),
                })
                .collect();
            let expected: Vec<_> = cases
                .iter()
                .map(|(name, _)| {
                    native
                        .variables
                        .iter()
                        .find(|record| native.string(record.name) == Some(name.as_bytes()))
                        .unwrap()
                        .hidden_initializer_marker()
                        .unwrap()
                })
                .collect();
            for left in 0..cases.len() {
                for right in 0..cases.len() {
                    assert_eq!(
                        actual[left] == actual[right],
                        expected[left] == expected[right],
                        "DEBUG={debug}: {} vs {}",
                        cases[left].0,
                        cases[right].0
                    );
                }
            }
        }
    }
    #[test]
    fn folded_named_lists_and_newlist_share_proven_expression_keys() {
        let mut symbols = SymbolTable::default();
        symbols.intern("/datum/token_target").unwrap();
        let sources = [
            "list(1+1)",
            "list(2)",
            "list(a=1)",
            "list(\"a\"=1)",
            "newlist()",
            "list()",
            "newlist(/datum/token_target)",
            "list(new /datum/token_target())",
        ];
        let expressions: Vec<_> = sources
            .iter()
            .map(|source| expression(source, &mut symbols))
            .collect();
        let evaluator = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &Host,
            symbols: &symbols,
        };
        let mut tokens = Tokens::new(false);
        let mut ids = Vec::new();
        for value in expressions {
            let write = InitializerWrite {
                target: dm_ir::InitializerTarget::Shared {
                    slot: dm_ir::SymbolId::of("slot"),
                    owner: dm_ir::SymbolId::of("/"),
                    name: dm_ir::SymbolId::of("value"),
                },
                lexical_owner: dm_ir::SymbolId::of("/"),
                lexical_procedure: None,
                value: dm_ir::InitializerValue::Expression(value.clone()),
                declared_array: None,
                declaration_flags: Some(8),
            };
            let source = value.source_text(&symbols).unwrap();
            let parsed = dm_syntax::parse_expression(&source);
            ids.push(
                tokens
                    .issue(
                        construction_key(
                            parsed.expr.as_ref().unwrap(),
                            &source,
                            &write,
                            &symbols,
                            &evaluator,
                        )
                        .unwrap()
                        .unwrap(),
                    )
                    .unwrap()
                    .0,
            );
        }
        assert_eq!(ids[0], ids[1]);
        assert_eq!(ids[2], ids[3]);
        assert_eq!(ids[4], ids[5]);
        assert_eq!(ids[6], ids[7]);
        assert_ne!(ids[0], ids[2]);
    }
    #[test]
    fn runtime_global_list_arguments_preserve_native_null_default() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/phase1/native_token_runtime_arguments/global/probe.native.bin"
        ))
        .unwrap();
        let record = native
            .variables
            .iter()
            .find(|record| native.string(record.name) == Some(b"global_call".as_slice()))
            .unwrap();
        assert_eq!((record.kind, record.value), (0, 0));
        let mut symbols = SymbolTable::default();
        let write = InitializerWrite {
            target: dm_ir::InitializerTarget::Shared {
                slot: dm_ir::SymbolId::of("slot"),
                owner: dm_ir::SymbolId::of("/"),
                name: dm_ir::SymbolId::of("global_call"),
            },
            lexical_owner: dm_ir::SymbolId::of("/"),
            lexical_procedure: None,
            value: dm_ir::InitializerValue::Expression(expression(
                "list(make_value())",
                &mut symbols,
            )),
            declared_array: None,
            declaration_flags: Some(8),
        };
        let evaluator = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &Host,
            symbols: &symbols,
        };
        let result = crate::initializer_policy::classify(&[write], &symbols, &evaluator).unwrap();
        assert_eq!(
            result.writes[0].default,
            crate::initializer_policy::DefaultValue::Scalar(SemanticValue::Null)
        );
        assert_eq!(
            result.writes[0].phase,
            Some(crate::initializer_policy::Phase::Runtime)
        );
    }
    #[test]
    fn native_container_constructor_associations_preserve_family_identity() {
        for (family, bytes) in [
            ("list", include_bytes!("../../../fixtures/phase1/native_container_constructor_tokens/list/probe.native.bin").as_slice()),
            ("alist", include_bytes!("../../../fixtures/phase1/native_container_constructor_tokens/alist/probe.native.bin").as_slice()),
        ] {
            let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
            let names = ["assoc_a", "assoc_b", "literal", "length", "element"];
            let expressions = [
                format!("new/{family}(\"donor\"=null,\"antibodies\"=list())"),
                format!("new/{family}(donor=null,\"antibodies\"=list())"),
                format!("{family}(\"donor\"=null,\"antibodies\"=list())"),
                format!("new/{family}(3)"),
                format!("{family}(3)"),
            ];
            let mut symbols = SymbolTable::default();
            symbols.intern(&format!("/{family}")).unwrap();
            let writes: Vec<_> = expressions.iter().map(|source| InitializerWrite {
                target: dm_ir::InitializerTarget::Shared { slot: dm_ir::SymbolId::of("slot"), owner: dm_ir::SymbolId::of("/"), name: dm_ir::SymbolId::of("value") },
                lexical_owner: dm_ir::SymbolId::of("/"), lexical_procedure: None,
                value: dm_ir::InitializerValue::Expression(expression(source, &mut symbols)),
                declared_array: None, declaration_flags: Some(8),
            }).collect();
            let evaluator = crate::driver_facts::DriverEvaluator { pure_calls: None, resource_search_context: None, resolver: &Host, symbols: &symbols };
            let mut tokens = Tokens::new(false);
            let ids: Vec<_> = writes.iter().zip(&expressions).map(|(write,source)| {
                let parsed=dm_syntax::parse_expression(source);
                tokens.issue(construction_key(parsed.expr.as_ref().unwrap(),source,write,&symbols,&evaluator).unwrap().unwrap()).unwrap().0
            }).collect();
            let native_ids: Vec<_> = names.iter().map(|name| {
                let record=native.variables.iter().find(|record| native.string(record.name)==Some(name.as_bytes())).unwrap();
                assert_eq!(record.kind,62);
                record.value
            }).collect();
            for left in 0..names.len() { for right in 0..names.len() {
                assert_eq!(ids[left]==ids[right],native_ids[left]==native_ids[right],"{family}: {} / {}",names[left],names[right]);
            }}
        }
    }
    #[test]
    fn borrowed_scalar_ast_matches_captured_expression_policy() {
        use crate::initializer_policy::CapturedInitializerEvaluator;
        for source in ["2+3*4", "null", "list(make_value())", "'missing.txt'"] {
            let mut symbols = SymbolTable::default();
            let value = expression(source, &mut symbols);
            let write = InitializerWrite {
                target: dm_ir::InitializerTarget::Shared {
                    slot: dm_ir::SymbolId::of("slot"),
                    owner: dm_ir::SymbolId::of("/"),
                    name: dm_ir::SymbolId::of("value"),
                },
                lexical_owner: dm_ir::SymbolId::of("/"),
                lexical_procedure: None,
                value: dm_ir::InitializerValue::Expression(value.clone()),
                declared_array: None,
                declaration_flags: Some(8),
            };
            let evaluator = crate::driver_facts::DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: &Host,
                symbols: &symbols,
            };
            let parsed = dm_syntax::parse_expression(source);
            let captured = evaluator.evaluate_write(&write, &value);
            let borrowed = evaluator.evaluate_ast_write(
                &write,
                parsed.expr.as_ref().unwrap(),
                source,
                &symbols,
            );
            match (captured, borrowed) {
                (Ok(Evaluation::Scalar(a)), Ok(Evaluation::Scalar(b))) => assert_eq!(a, b),
                (Ok(Evaluation::Runtime), Ok(Evaluation::Runtime)) => (),
                (Err(a), Err(b)) => assert_eq!(a, b),
                _ => panic!("scalar AST policy differs: {source}"),
            }
        }
    }
    #[test]
    fn token_partition_obeys_final_debug_presence() {
        let mut shared = Tokens::new(false);
        let first = shared.issue(vec![9]).unwrap().1;
        let repeated = shared.issue(vec![9]).unwrap().1;
        assert!(Arc::ptr_eq(&first, &repeated));
        let mut shared = Tokens::new(false);
        assert_eq!(shared.issue(vec![1]).unwrap().0, 0);
        assert_eq!(shared.issue(vec![2]).unwrap().0, 1);
        assert_eq!(shared.issue(vec![1]).unwrap().0, 0);
        let mut debug = Tokens::new(true);
        assert_eq!(debug.issue(vec![1]).unwrap().0, 0);
        assert_eq!(debug.issue(vec![1]).unwrap().0, 1);
    }
}
