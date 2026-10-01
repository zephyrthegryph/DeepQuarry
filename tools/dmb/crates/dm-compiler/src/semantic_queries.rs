//! Lowering observes the same portable facts that Salsa tracks and disk memos
//! validate. Frozen bindings are invocation context, never a whole-project input.
use dm_codegen_byond::{
    capture_binding_reads, BindingFact, BindingWitness, FactValue, LowerBindings, LowerError,
    SimpleProc,
};
use dm_syntax::Item;
use salsa::Setter;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(crate) struct SemanticMemo {
    pub procedure: SimpleProc,
    pub dependencies: Vec<BindingWitness>,
}
impl SemanticMemo {
    pub fn valid_for(&self, bindings: &LowerBindings) -> bool {
        self.dependencies
            .iter()
            .any(|read| read.fact == BindingFact::SharedPresence)
            && self
                .dependencies
                .windows(2)
                .all(|pair| pair[0].fact < pair[1].fact)
            && self
                .dependencies
                .iter()
                .all(|read| bindings.binding_fact(&read.fact) == read.value)
    }
}

#[salsa::input]
struct FactInput {
    #[returns(ref)]
    value: FactValue,
}
#[salsa::input]
struct ProcedureInput {
    #[returns(ref)]
    scope: String,
    #[returns(ref)]
    body: Vec<Item>,
}

#[derive(Default)]
struct Context {
    bindings: Option<Arc<LowerBindings>>,
    candidate: Option<SemanticMemo>,
    facts: BTreeMap<String, BTreeMap<BindingFact, FactInput>>,
    executions: usize,
}
#[salsa::db]
trait SemanticDb: salsa::Database {
    fn context(&self) -> &Mutex<Context>;
}
#[salsa::db]
#[derive(Clone, Default)]
struct Database {
    storage: salsa::Storage<Self>,
    context: Arc<Mutex<Context>>,
}
#[salsa::db]
impl salsa::Database for Database {}
#[salsa::db]
impl SemanticDb for Database {
    fn context(&self) -> &Mutex<Context> {
        &self.context
    }
}

fn read_fact(db: &dyn SemanticDb, scope: &str, read: &BindingWitness) {
    let input = {
        let mut context = db.context().lock().unwrap();
        *context
            .facts
            .entry(scope.to_owned())
            .or_default()
            .entry(read.fact.clone())
            .or_insert_with(|| FactInput::new(db, read.value.clone()))
    };
    // The exact observation becomes an actual Salsa field dependency, including
    // unsuccessful lookups. A mismatch is an internal snapshot consistency error.
    assert_eq!(input.value(db), &read.value, "stale frozen skeleton fact");
}

#[salsa::tracked]
fn lower(db: &dyn SemanticDb, input: ProcedureInput) -> Result<SemanticMemo, Vec<LowerError>> {
    let scope = input.scope(db);
    let body = input.body(db);
    let (bindings, candidate) = {
        let mut context = db.context().lock().unwrap();
        context.executions += 1;
        (
            context.bindings.clone().expect("frozen lowering context"),
            context.candidate.clone(),
        )
    };
    let memo = if let Some(memo) = candidate.filter(|memo| memo.valid_for(&bindings)) {
        memo
    } else {
        let (procedure, dependencies) = capture_binding_reads(|| {
            dm_codegen_byond::compile_simple_proc_with_bindings(body, &bindings)
        });
        // Error outcomes also read their semantic dependencies: a newly declared
        // member can turn an error into a valid program at the next revision.
        for read in &dependencies {
            read_fact(db, scope, read);
        }
        SemanticMemo {
            procedure: procedure?,
            dependencies,
        }
    };
    for read in &memo.dependencies {
        read_fact(db, scope, read);
    }
    Ok(memo)
}

const MAX_GRAPH_BYTES: usize = 16 * 1024 * 1024;
const MAX_GRAPH_INPUTS: usize = 1024;
fn syntax_heap(items: &[Item]) -> usize {
    items.iter().fold(
        items.len().saturating_mul(std::mem::size_of::<Item>()),
        |n, item| {
            n.saturating_add(item.header.capacity())
                .saturating_add(syntax_heap(&item.children))
        },
    )
}
fn fact_heap(fact: &BindingFact) -> usize {
    use BindingFact::*;
    match fact {
        Field(a)
        | Global(a)
        | GlobalProc(a)
        | FieldType(a)
        | GlobalType(a)
        | UniqueMemberGlobal(a)
        | NumericConstant(a)
        | StringConstant(a)
        | ModifiedInstance(a) => a.capacity(),
        GlobalProcReturnType(a) => a.capacity(),
        MemberType(a, b) | MemberGlobal(a, b) | MemberProc(a, b) | DeclaredMemberProc(a, b)
        | MemberProcReturnType(a, b) | ParentProcReturnType(a, b) => {
            a.capacity().saturating_add(b.capacity())
        }
        SharedPresence => 0,
    }
}
fn value_heap(value: &FactValue) -> usize {
    match value {
        FactValue::Text(text) => text.capacity(),
        _ => 0,
    }
}
fn variable_heap(variable: &dm_codegen_byond::VariableWord) -> usize {
    use dm_codegen_byond::VariableWord::*;
    match variable {
        Field(s) | StaticField(s) | Global(s) | DynamicProc(s) | StaticProc(s) | StaticVerb(s) => {
            s.capacity()
        }
        Initial(v) | IsSaved(v) => {
            std::mem::size_of::<dm_codegen_byond::VariableWord>().saturating_add(variable_heap(v))
        }
        SetCache(a, b) => (2 * std::mem::size_of::<dm_codegen_byond::VariableWord>())
            .saturating_add(variable_heap(a))
            .saturating_add(variable_heap(b)),
        _ => 0,
    }
}
fn word_heap(word: &dm_codegen_byond::Word) -> usize {
    use dm_codegen_byond::{ValueWord, Word};
    match word {
        Word::Reference(symbol) => symbol.key.capacity(),
        Word::Branch(label) => label.capacity(),
        Word::Value(
            ValueWord::String(s)
            | ValueWord::Resource(s)
            | ValueWord::ProcPath(s)
            | ValueWord::Instance(s),
        ) => s.capacity(),
        Word::Value(ValueWord::ClassPath { path, .. }) => path.capacity(),
        Word::Variable(variable) => variable_heap(variable),
        _ => 0,
    }
}
fn memo_heap(memo: &SemanticMemo) -> usize {
    use dm_codegen_byond::{Item as CodeItem, Word};
    let p = &memo.procedure;
    let mut n = std::mem::size_of::<SemanticMemo>().saturating_add(
        p.code
            .items
            .capacity()
            .saturating_mul(std::mem::size_of::<CodeItem>()),
    );
    for item in &p.code.items {
        n = n.saturating_add(match item {
            CodeItem::Label(label) => label.capacity(),
            CodeItem::Instruction(code) => code.operands.iter().fold(
                code.operands
                    .capacity()
                    .saturating_mul(std::mem::size_of::<Word>()),
                |n, word| n.saturating_add(word_heap(word)),
            ),
        });
    }
    for strings in [
        &p.strings,
        &p.class_paths,
        &p.instance_paths,
        &p.resources,
        &p.local_names,
        &p.argument_names,
    ] {
        n = n.saturating_add(
            strings
                .capacity()
                .saturating_mul(std::mem::size_of::<String>()),
        );
        for text in strings {
            n = n.saturating_add(text.capacity());
        }
    }
    n = n
        .saturating_add(
            p.statement_origins
                .capacity()
                .saturating_mul(std::mem::size_of::<dm_codegen_byond::debug::StatementOrigin>()),
        )
        .saturating_add(p.argument_type_flags.capacity().saturating_mul(4))
        .saturating_add(p.argument_value_sources.capacity().saturating_mul(4))
        .saturating_add(
            p.format_templates
                .capacity()
                .saturating_mul(std::mem::size_of::<(String, Vec<u8>)>() + 32),
        );
    for (key, value) in &p.format_templates {
        n = n
            .saturating_add(key.capacity())
            .saturating_add(value.capacity());
    }
    n = n.saturating_add(
        memo.dependencies
            .capacity()
            .saturating_mul(std::mem::size_of::<BindingWitness>() + 256),
    );
    for read in &memo.dependencies {
        n = n
            .saturating_add(fact_heap(&read.fact))
            .saturating_add(value_heap(&read.value));
    }
    n
}
fn graph_charge(syntax: usize, memo: usize, identity: &str) -> usize {
    syntax
        .saturating_add(memo)
        .saturating_add(identity.len())
        .saturating_add(512)
        .saturating_mul(4)
}

/// A bounded live graph; portable memos survive query eviction and process exits.
#[derive(Default)]
pub(crate) struct SemanticQueries {
    db: Database,
    inputs: BTreeMap<String, ProcedureInput>,
    charged_bytes: usize,
    charges: BTreeMap<String, usize>,
}
impl SemanticQueries {
    pub fn compile(
        &mut self,
        identity: &str,
        body: &[Item],
        bindings: &LowerBindings,
        candidate: Option<SemanticMemo>,
    ) -> Result<SemanticMemo, Vec<LowerError>> {
        // Include symbolic results and Salsa fact copies without encoding JSON
        // on every hit. The multiplier covers cloned query values and tree nodes.
        let syntax = syntax_heap(body);
        let planned = graph_charge(syntax, candidate.as_ref().map_or(0, memo_heap), identity);
        let old = self.charges.get(identity).copied().unwrap_or(0);
        if (!self.inputs.contains_key(identity) && self.inputs.len() >= MAX_GRAPH_INPUTS)
            || self
                .charged_bytes
                .saturating_sub(old)
                .saturating_add(planned)
                > MAX_GRAPH_BYTES
        {
            *self = Self::default();
        }
        self.set_charge(identity, planned);
        let known = self
            .db
            .context
            .lock()
            .unwrap()
            .facts
            .get(identity)
            .cloned()
            .unwrap_or_default();
        for (fact, input) in known {
            let value = bindings.binding_fact(&fact);
            if input.value(&self.db) != &value {
                input.set_value(&mut self.db).to(value);
            }
        }
        {
            let mut context = self.db.context.lock().unwrap();
            context.bindings = Some(Arc::new(bindings.clone()));
            context.candidate = candidate;
        }
        let input = *self
            .inputs
            .entry(identity.to_owned())
            .or_insert_with(|| ProcedureInput::new(&self.db, identity.to_owned(), body.to_vec()));
        let result = lower(&self.db, input).clone();
        let mut context = self.db.context.lock().unwrap();
        context.bindings = None;
        context.candidate = None;
        drop(context);
        let memo = result.as_ref().map_or_else(
            |_| {
                let context = self.db.context.lock().unwrap();
                context.facts.get(identity).map_or(0, |facts| {
                    facts.iter().fold(0usize, |n, (fact, input)| {
                        n.saturating_add(256)
                            .saturating_add(fact_heap(fact))
                            .saturating_add(value_heap(input.value(&self.db)))
                    })
                })
            },
            memo_heap,
        );
        self.set_charge(identity, graph_charge(syntax, memo, identity));
        if self.charged_bytes > MAX_GRAPH_BYTES {
            *self = Self::default();
        }
        result
    }
    fn set_charge(&mut self, identity: &str, bytes: usize) {
        let previous = self.charges.insert(identity.to_owned(), bytes).unwrap_or(0);
        self.charged_bytes = self
            .charged_bytes
            .saturating_sub(previous)
            .saturating_add(bytes);
    }
    #[cfg(test)]
    fn executions(&self) -> usize {
        self.db.context.lock().unwrap().executions
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recorded_reads_and_salsa_invalidation_agree() {
        let body = dm_syntax::parse("/proc/f()\n    return value\n")
            .items
            .remove(0)
            .children;
        let mut bindings = LowerBindings::default();
        bindings.globals.insert("value".into());
        let mut queries = SemanticQueries::default();
        let first = queries
            .compile("f-body-frame", &body, &bindings, None)
            .unwrap();
        assert!(first.valid_for(&bindings));
        assert_eq!(queries.executions(), 1);
        bindings.globals.insert("unrelated".into());
        let same = queries
            .compile("f-body-frame", &body, &bindings, Some(first.clone()))
            .unwrap();
        assert_eq!(same, first);
        assert_eq!(queries.executions(), 1);
        bindings.globals.remove("value");
        bindings.fields.insert("value".into());
        let changed = queries
            .compile("f-body-frame", &body, &bindings, Some(first))
            .unwrap();
        assert_ne!(changed.procedure, same.procedure);
        assert_eq!(queries.executions(), 2);
    }
    #[test]
    fn cold_results_are_charged_and_oversized_memos_are_not_retained() {
        let body = dm_syntax::parse("/proc/f()\n    return 7\n")
            .items
            .remove(0)
            .children;
        let bindings = LowerBindings::default();
        let mut queries = SemanticQueries::default();
        let first = queries.compile("small", &body, &bindings, None).unwrap();
        assert!(queries.charged_bytes > graph_charge(syntax_heap(&body), 0, "small"));
        let before = queries.charged_bytes;
        queries
            .compile("small", &body, &bindings, Some(first.clone()))
            .unwrap();
        assert_eq!(queries.charged_bytes, before);
        let mut huge = first;
        huge.procedure.strings.push("x".repeat(MAX_GRAPH_BYTES / 4));
        let returned = queries
            .compile("huge", &body, &bindings, Some(huge))
            .unwrap();
        assert_eq!(
            returned.procedure.strings.last().unwrap().len(),
            MAX_GRAPH_BYTES / 4
        );
        assert!(queries.inputs.is_empty());
        assert!(queries.charges.is_empty());
        assert_eq!(queries.charged_bytes, 0);
        assert!(queries.compile("small", &body, &bindings, None).is_ok());
    }
    #[test]
    fn failed_negative_lookup_recovers_after_declaration() {
        let body = dm_syntax::parse("/proc/f()\n    return missing()\n")
            .items
            .remove(0)
            .children;
        let mut bindings = LowerBindings::default();
        bindings.shared = Some(Arc::new(Default::default()));
        let mut queries = SemanticQueries::default();
        assert!(queries.compile("f", &body, &bindings, None).is_err());
        bindings.global_procs.insert("missing".into());
        assert!(queries.compile("f", &body, &bindings, None).is_ok());
        assert_eq!(queries.executions(), 2);
    }

    #[test]
    fn proc_return_reads_invalidate_positive_and_negative_results() {
        let body = dm_syntax::parse("/proc/check()\n    return istype(fetch().payload)\n")
            .items.remove(0).children;
        let mut bindings = LowerBindings::default();
        let mut shared = dm_codegen_byond::SharedLowerBindings::default();
        shared.global_procs.insert("fetch".into());
        shared.member_types.insert("/datum/result".into(),
            [("payload".into(), "/datum/first".into())].into());
        bindings.shared = Some(Arc::new(shared));
        let (failure, reads) = capture_binding_reads(||
            dm_codegen_byond::compile_simple_proc_with_bindings(&body, &bindings));
        assert!(failure.is_err());
        assert!(reads.iter().any(|read| read.fact == BindingFact::GlobalProcReturnType("fetch".into())
            && read.value == FactValue::Absent));
        let mut queries = SemanticQueries::default();
        assert!(queries.compile("result", &body, &bindings, None).is_err());
        Arc::make_mut(bindings.shared.as_mut().unwrap()).global_proc_return_types
            .insert("fetch".into(), "/datum/result".into());
        let first = queries.compile("result", &body, &bindings, None).unwrap();
        assert!(first.valid_for(&bindings));
        assert_eq!(queries.executions(), 2);
        Arc::make_mut(bindings.shared.as_mut().unwrap()).global_proc_return_types
            .insert("unrelated".into(), "/datum/unrelated".into());
        assert_eq!(queries.compile("result", &body, &bindings, Some(first.clone())).unwrap(), first);
        assert_eq!(queries.executions(), 2);
        Arc::make_mut(bindings.shared.as_mut().unwrap()).member_types
            .get_mut("/datum/result").unwrap().insert("payload".into(), "/datum/second".into());
        let changed = queries.compile("result", &body, &bindings, Some(first.clone())).unwrap();
        assert_ne!(changed.procedure, first.procedure);
        assert_eq!(queries.executions(), 3);
        Arc::make_mut(bindings.shared.as_mut().unwrap()).global_proc_return_types.remove("fetch");
        assert!(!changed.valid_for(&bindings));
        assert!(queries.compile("result", &body, &bindings, Some(changed)).is_err());
        assert_eq!(queries.executions(), 4);
    }

    #[test]
    fn proc_return_member_shadowing_and_parent_changes_are_observed() {
        let body = dm_syntax::parse("/proc/check()\n    return istype(fetch().payload)\n")
            .items.remove(0).children;
        let mut bindings = LowerBindings {
            current_type_path: Some("/datum/owner/child".into()),
            current_proc_path: Some("/datum/owner/child/proc/check".into()),
            ..Default::default()
        };
        let mut shared = dm_codegen_byond::SharedLowerBindings::default();
        shared.parent_types.insert("/datum/owner/child".into(), "/datum/owner".into());
        shared.global_procs.insert("fetch".into());
        shared.global_proc_return_types.insert("fetch".into(), "/datum/global_result".into());
        for (owner, ty) in [("/datum/global_result", "/datum/a"), ("/datum/member_result", "/datum/b")] {
            shared.member_types.insert(owner.into(), [("payload".into(), ty.into())].into());
        }
        bindings.shared = Some(Arc::new(shared));
        let mut queries = SemanticQueries::default();
        let global = queries.compile("shadowing", &body, &bindings, None).unwrap();
        assert!(global.dependencies.iter().any(|read| read.fact
            == BindingFact::DeclaredMemberProc("/datum/owner/child".into(), "fetch".into())
            && read.value == FactValue::Boolean(false)));
        let shared = Arc::make_mut(bindings.shared.as_mut().unwrap());
        shared.known_member_procs.insert("/datum/owner".into(), ["fetch".into()].into());
        shared.member_proc_return_types.insert("/datum/owner".into(),
            [("fetch".into(), "/datum/member_result".into())].into());
        let member = queries.compile("shadowing", &body, &bindings, Some(global.clone())).unwrap();
        assert_ne!(member.procedure, global.procedure);
        assert!(member.dependencies.iter().any(|read| read.fact
            == BindingFact::MemberProcReturnType("/datum/owner/child".into(), "fetch".into())
            && read.value == FactValue::Text("/datum/member_result".into())));
        let parent_body = dm_syntax::parse("/proc/check()\n    return istype(..().payload)\n")
            .items.remove(0).children;
        bindings.current_proc_path = Some("/datum/owner/child/proc/fetch".into());
        let parent = queries.compile("parent", &parent_body, &bindings, None).unwrap();
        assert!(parent.dependencies.iter().any(|read| read.fact
            == BindingFact::ParentProcReturnType("/datum/owner/child".into(), "fetch".into())));
        Arc::make_mut(bindings.shared.as_mut().unwrap()).parent_types
            .insert("/datum/owner/child".into(), "/datum/missing".into());
        assert!(!parent.valid_for(&bindings));
        assert!(queries.compile("parent", &parent_body, &bindings, Some(parent)).is_err());
    }
}
