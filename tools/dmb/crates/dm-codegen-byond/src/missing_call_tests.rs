//! Definitive resolver absence is a source error; opaque answers are not.
use super::*;
use crate::LowerErrorKind;

struct MissingCallHost {
    opaque: bool,
}
impl Resolver for MissingCallHost {
    fn resolve(&self, query: Q) -> M {
        match query {
            Q::RuntimeType(owner) if owner == SymbolId::of("/datum") => M::Symbol(owner),
            Q::GlobalProc(name) if name == SymbolId::of("member_only") => {
                if self.opaque {
                    M::Unsupported(query)
                } else {
                    M::Missing
                }
            }
            Q::HasMemberProc { name, .. } if name == SymbolId::of("member_only") => {
                M::Presence(false)
            }
            Q::Proc { name, .. } if name == SymbolId::of("member_only") => {
                if self.opaque {
                    M::Unsupported(query)
                } else {
                    M::Missing
                }
            }
            _ => M::Unsupported(query),
        }
    }
}

#[test]
fn certified_missing_calls_are_source_errors_but_opaque_calls_are_unsupported() {
    let mut symbols = SymbolTable::default();
    symbols.intern("member_only").unwrap();
    symbols.intern("/datum/probe").unwrap();
    for (source, owner) in [
        ("/proc/probe()\n    return member_only()\n", None),
        (
            "/datum/probe/proc/probe()\n    return member_only()\n",
            Some("/datum/probe"),
        ),
        ("/proc/probe()\n    return global.member_only()\n", None),
    ] {
        let ast = dm_syntax::parse(source);
        let inputs = ProcedureInputs {
            current_type_path: owner.map(str::to_owned),
            ..Default::default()
        };
        for opaque in [false, true] {
            let errors = crate::compile_simple_proc_with_resolver(
                &ast.items[0].children,
                &inputs,
                &symbols,
                &MissingCallHost { opaque },
            )
            .err()
            .expect("missing/opaque call must not emit a procedure");
            assert_eq!(errors.len(), 1, "{source}: {errors:?}");
            assert_eq!(
                errors[0].kind,
                if opaque {
                    LowerErrorKind::UnsupportedModel
                } else {
                    LowerErrorKind::SourceError
                },
                "{source}: {errors:?}"
            );
            if opaque {
                assert!(errors[0].reason.contains("unsupported semantic query"));
            } else {
                assert_eq!(errors[0].reason, "member_only: undefined proc");
            }
        }
    }
}

#[test]
fn certified_missing_runtime_type_is_source_error_and_opaque_type_is_unsupported() {
    struct TypeHost(bool);
    impl Resolver for TypeHost {
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::RuntimeType(_) if !self.0 => M::Missing,
                _ => M::Unsupported(query),
            }
        }
    }
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/formerly_missing_type").unwrap();
    let ast = dm_syntax::parse("/proc/probe()\n    return new /datum/formerly_missing_type\n");
    for opaque in [false, true] {
        let errors = crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &ProcedureInputs::default(),
            &symbols,
            &TypeHost(opaque),
        )
        .err()
        .expect("missing type");
        assert_eq!(
            errors[0].kind,
            if opaque {
                LowerErrorKind::UnsupportedModel
            } else {
                LowerErrorKind::SourceError
            }
        );
        if !opaque {
            assert_eq!(
                errors[0].reason,
                "/datum/formerly_missing_type: undefined type path"
            );
        }
    }
}

#[test]
fn dynamic_receiver_call_is_not_a_certified_absence() {
    let ast =
        dm_syntax::parse("/proc/probe(receiver)\n    return call(receiver, \"member_only\")()\n");
    let inputs = ProcedureInputs {
        parameters: vec!["receiver".into()],
        ..Default::default()
    };
    assert!(crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &SymbolTable::default(),
        &MissingCallHost { opaque: true },
    )
    .is_ok());
}

#[test]
fn typed_receiver_missing_member_is_source_error_but_opaque_remains_unsupported() {
    let ast = dm_syntax::parse("/proc/probe(value)\n    return value.member_only()\n");
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum").unwrap();
    symbols.intern("member_only").unwrap();
    let inputs = ProcedureInputs {
        parameters: vec!["value".into()],
        parameter_types: [("value".into(), "/datum".into())].into(),
        ..Default::default()
    };
    for opaque in [false, true] {
        let errors = crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &inputs,
            &symbols,
            &MissingCallHost { opaque },
        )
        .err()
        .expect("expected lowering rejection");
        assert_eq!(
            errors[0].kind,
            if opaque {
                LowerErrorKind::UnsupportedModel
            } else {
                LowerErrorKind::SourceError
            }
        );
        if !opaque {
            assert_eq!(errors[0].reason, "value.member_only: undefined proc");
        }
    }
}

#[test]
fn untyped_dot_rejects_but_colon_records_exact_name_availability() {
    use std::sync::Mutex;
    struct Host(Mutex<Vec<Q>>, Option<bool>);
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            self.0.lock().unwrap().push(query);
            match query {
                Q::MemberCallableVerbName(_) => M::Presence(false),
                Q::MemberCallableName(_) => {
                    self.1.map(M::Presence).unwrap_or(M::Unsupported(query))
                }
                _ => M::Unsupported(query),
            }
        }
    }
    let inputs = ProcedureInputs {
        parameters: vec!["value".into()],
        ..Default::default()
    };
    let mut symbols = SymbolTable::default();
    symbols.intern("known").unwrap();
    for available in [None, Some(false), Some(true)] {
        let host = Host(Mutex::new(Vec::new()), available);
        let ast = dm_syntax::parse("/proc/probe(value)\n    return value:known()\n");
        let result = crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &inputs,
            &symbols,
            &host,
        );
        assert!(host
            .0
            .lock()
            .unwrap()
            .contains(&Q::MemberCallableName(SymbolId::of("known"))));
        match available {
            Some(true) => assert!(result.is_ok()),
            Some(false) => {
                let errors = result.err().expect("expected lowering rejection");
                assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
                assert_eq!(errors[0].reason, "value:known: undefined proc");
            }
            None => assert_eq!(
                result.err().expect("expected lowering rejection")[0].kind,
                LowerErrorKind::UnsupportedModel
            ),
        }
        let ast = dm_syntax::parse("/proc/probe(value)\n    return value.known()\n");
        let errors = crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &inputs,
            &symbols,
            &host,
        )
        .err()
        .expect("expected lowering rejection");
        assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
        assert_eq!(errors[0].reason, "value.known: undefined proc");
    }
}

#[test]
fn typed_native_method_without_source_reference_keeps_dynamic_dispatch() {
    struct Native;
    impl Resolver for Native {
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::RuntimeType(owner) if owner == SymbolId::of("/list") => M::Symbol(owner),
                Q::Proc {
                    owner,
                    name,
                    verb: false,
                } if owner == SymbolId::of("/list") && name == SymbolId::of("Copy") => {
                    M::IntrinsicProc {
                        declaring_owner: owner,
                        name,
                    }
                }
                Q::HasMemberProc { owner, name }
                    if owner == SymbolId::of("/list") && name == SymbolId::of("Copy") =>
                {
                    M::Presence(true)
                }
                _ => M::Unsupported(query),
            }
        }
    }
    let ast = dm_syntax::parse("/proc/probe(value)\n    return value.Copy()\n");
    let mut symbols = SymbolTable::default();
    symbols.intern("/list").unwrap();
    symbols.intern("Copy").unwrap();
    let inputs = ProcedureInputs {
        parameters: vec!["value".into()],
        parameter_types: [("value".into(), "/list".into())].into(),
        ..Default::default()
    };
    let result = crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &symbols,
        &Native,
    );
    assert!(result.is_ok(), "{:?}", result.err());
}

#[test]
fn safe_untyped_member_requires_name_presence_without_dot_type_restriction() {
    struct Host(bool);
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::MemberCallableName(_) => M::Presence(self.0),
                _ => M::Unsupported(query),
            }
        }
    }
    let ast = dm_syntax::parse("/proc/probe(value)\n    return value?.Copy()\n");
    let inputs = ProcedureInputs {
        parameters: vec!["value".into()],
        ..Default::default()
    };
    let mut symbols = SymbolTable::default();
    symbols.intern("Copy").unwrap();
    assert!(crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &symbols,
        &Host(true)
    )
    .is_ok());
    let errors = crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        &symbols,
        &Host(false),
    )
    .err()
    .expect("missing safe method rejects");
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
    assert_eq!(errors[0].reason, "value.Copy: undefined proc");
}

#[test]
fn catch_collision_uses_current_catch_and_previous_local_spans() {
    let source = "/proc/probe()\n    var/value = 1\n    try\n        throw 2\n    catch(var/value)\n        return value\n";
    let ast = dm_syntax::parse(source);
    let errors = crate::compile_simple_proc(&ast.items[0].children)
        .err()
        .expect("catch collision rejects");
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
    assert_eq!(errors[0].reason, "value: duplicate definition");
    let primary = errors[0].span.expect("parser-issued catch span");
    assert!(source[primary.start..primary.end].starts_with("catch("));
    assert_eq!(errors[0].related.len(), 1);
    let previous = errors[0].related[0].span;
    assert!(source[previous.start..previous.end].starts_with("var/value"));
}

#[test]
fn untyped_local_dot_rejects_even_known_member_name() {
    let ast = dm_syntax::parse("/proc/probe()\n    var/value\n    return value.Copy()\n");
    let mut symbols = SymbolTable::default();
    symbols.intern("Copy").unwrap();
    let errors = crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &ProcedureInputs::default(),
        &symbols,
        &MissingCallHost { opaque: true },
    )
    .err()
    .expect("untyped local dot rejects");
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
    assert_eq!(errors[0].reason, "value.Copy: undefined proc");
}

#[test]
fn dynamic_colon_verb_uses_native_verb_namespace_operand() {
    struct Host(bool);
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::MemberCallableName(_) => M::Presence(true),
                Q::MemberCallableVerbName(_) => M::Presence(self.0),
                _ => M::Unsupported(query),
            }
        }
    }
    let ast = dm_syntax::parse("/proc/probe(value)\n    return value:member_only()\n");
    let inputs = ProcedureInputs {
        parameters: vec!["value".into()],
        ..Default::default()
    };
    let mut symbols = SymbolTable::default();
    symbols.intern("member_only").unwrap();
    // Authenticated callable runtime: BYOND DynamicVerb 0xffde; mixed
    // proc/verb compiler control selects DynamicProc 0xffdd instead.
    for verb in [false, true] {
        let compiled = crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &inputs,
            &symbols,
            &Host(verb),
        )
        .ok()
        .expect("certified dynamic call");
        let mut ledger = crate::Ledger::default();
        ledger
            .assign(
                crate::Table::String,
                compiled
                    .procedure
                    .strings
                    .iter()
                    .map(|value| dm_ir::SymRef::String(value.id)),
            )
            .unwrap();
        let linked = crate::link_proc(&compiled.procedure.code, &ledger).unwrap();
        assert!(linked.words.contains(&if verb { 0xffde } else { 0xffdd }));
        assert!(!linked.words.contains(&if verb { 0xffdd } else { 0xffde }));
    }
}

#[test]
fn c_style_typed_local_records_current_native_receiver_reads() {
    struct Host(std::sync::Mutex<Vec<Q>>);
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            self.0.lock().unwrap().push(query);
            match query {
                Q::RuntimeType(owner) if owner == SymbolId::of("/list") => M::Symbol(owner),
                Q::Proc {
                    owner,
                    name,
                    verb: false,
                } if owner == SymbolId::of("/list")
                    && [SymbolId::of("Copy"), SymbolId::of("Add")].contains(&name) =>
                {
                    M::IntrinsicProc {
                        declaring_owner: owner,
                        name,
                    }
                }
                Q::HasMemberProc { owner, name }
                    if owner == SymbolId::of("/list")
                        && [SymbolId::of("Copy"), SymbolId::of("Add")].contains(&name) =>
                {
                    M::Presence(true)
                }
                _ => M::Unsupported(query),
            }
        }
    }
    let mut symbols = SymbolTable::default();
    for name in ["/list", "Copy", "Add"] {
        symbols.intern(name).unwrap();
    }
    for source in [
        include_str!(
            "../../../fixtures/native/for_initializer_receiver_diagnostics/for_typed_list_copy.dm"
        ),
        include_str!(
            "../../../fixtures/native/for_initializer_receiver_diagnostics/for_typed_list_add.dm"
        ),
    ] {
        let ast = dm_syntax::parse(source);
        let host = Host(Default::default());
        crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &ProcedureInputs::default(),
            &symbols,
            &host,
        )
        .unwrap();
        assert!(host.0.lock().unwrap().iter().any(
            |query| matches!(query, Q::Proc { owner, .. } if *owner == SymbolId::of("/list"))
        ));
    }
    let ast = dm_syntax::parse(include_str!(
        "../../../fixtures/native/for_initializer_receiver_diagnostics/for_untyped_dot.dm"
    ));
    let errors = crate::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &ProcedureInputs::default(),
        &symbols,
        &Host(Default::default()),
    )
    .err()
    .expect("untyped dot remains invalid");
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
    assert_eq!(errors[0].reason, "value.Copy: undefined proc");
}
