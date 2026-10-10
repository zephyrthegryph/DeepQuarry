//! Definitive resolver absence is a source error; opaque answers are not.
use super::*;
use crate::LowerErrorKind;

struct MissingCallHost {
    opaque: bool,
}
impl Resolver for MissingCallHost {
    fn resolve(&self, query: Q) -> M {
        match query {
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
            Q::Proc { name, .. } if name == SymbolId::of("member_only") => M::Missing,
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
    let ast = dm_syntax::parse("/proc/probe(receiver)\n    return receiver.member_only()\n");
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
