//! `typesof(/T/verb)` and `typesof(/T/proc)`: the path names a type only when `T` itself declares something in that namespace.
//! DreamMaker (516) rejects the rest as "undefined type path" (probe: `typesof(/mob/living/carbon/verb)` with no verb declared on
//! `/mob/living/carbon`, even with verbs on its subtype or procs on it). Master carried such a path unseen because dmbc lowered any
//! path ending in `/proc` or `/verb` to a string without asking the resolver.
use super::*;

struct Host {
    /// (owner, verb) pairs that declare something.
    declared: Vec<(&'static str, bool)>,
}
impl dm_ir::Resolver for Host {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
        match query {
            Q::HasNamespaceMembers { owner, verb } => M::Presence(
                self.declared
                    .iter()
                    .any(|(path, v)| SymbolId::of(path) == owner && *v == verb),
            ),
            _ => M::Missing,
        }
    }
}

fn compile(source: &str, host: &Host) -> Result<(), Vec<LowerError>> {
    let ast = dm_syntax::parse(source);
    let inputs = crate::ProcedureInputs::default();
    let symbols = dm_ir::SymbolTable::default();
    crate::compile_simple_proc_with_resolver(&ast.items[0].children, &inputs, &symbols, host).map(|_| ())
}

const VERB: &str = "/proc/probe()\n    return typesof(/mob/living/carbon/verb)\n";
const PROC: &str = "/proc/probe()\n    return typesof(/mob/living/carbon/proc)\n";

#[test]
fn an_undeclared_verb_namespace_is_an_undefined_type_path() {
    // Declared on a subtype and procs on the owner itself do not count.
    let host = Host {
        declared: vec![("/mob/living/carbon/human", true), ("/mob/living/carbon", false)],
    };
    let errors = compile(VERB, &host).expect_err("no verb on /mob/living/carbon");
    assert_eq!(errors[0].reason, "/mob/living/carbon/verb: undefined type path");
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
}

#[test]
fn an_undeclared_proc_namespace_is_an_undefined_type_path() {
    let host = Host {
        declared: vec![("/mob/living/carbon", true)],
    };
    let errors = compile(PROC, &host).expect_err("only a verb on /mob/living/carbon");
    assert_eq!(errors[0].reason, "/mob/living/carbon/proc: undefined type path");
}

#[test]
fn a_declared_namespace_is_a_path() {
    let host = Host {
        declared: vec![("/mob/living/carbon", true), ("/mob/living/carbon", false)],
    };
    compile(VERB, &host).expect("a verb is declared on the owner");
    compile(PROC, &host).expect("a proc is declared on the owner");
}

#[test]
fn the_global_namespace_is_not_judged() {
    let host = Host { declared: vec![] };
    compile("/proc/probe()\n    return typesof(/proc)\n", &host).expect("/proc has no owner type");
}
