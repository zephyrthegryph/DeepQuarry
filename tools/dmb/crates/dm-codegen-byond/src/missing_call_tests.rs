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
                assert!(errors[0].reason.contains("unresolved"));
                assert!(errors[0].reason.contains("member_only"));
            }
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
