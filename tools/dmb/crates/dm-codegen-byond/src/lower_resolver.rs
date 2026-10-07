//! Request-local lowering view. All project answers come from one immutable
//! resolver; the input structure contains only this procedure's lexical state.
use crate::simple::{LowerBindings, LowerError};
use dm_ir::{
    ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue, SymbolId, SymbolTable,
};
use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedSlot {
    pub symbol: SymbolId,
    pub owner: SymbolId,
    pub name: SymbolId,
}
pub struct ResolverProc {
    pub procedure: crate::SimpleProc,
    /// Exact resolver-issued slot tuples; no output slot is selected here.
    pub slots: BTreeMap<crate::Symbol, ResolvedSlot>,
    pub resources: BTreeMap<String, u128>,
}

#[derive(Clone, Debug, Default)]
pub struct ProcedureInputs {
    pub current_proc_path: Option<String>,
    pub current_type_path: Option<String>,
    pub parameters: Vec<String>,
    pub parameter_type_flags: Vec<u32>,
    pub parameter_value_sources: Vec<u32>,
    pub parameter_defaults: Vec<Option<String>>,
    pub parameter_types: HashMap<String, String>,
    /// Explicit captured FILE_DIR/source-directory context, never inferred here.
    pub resource_search_context: Option<u128>,
}
impl ProcedureInputs {
    pub(crate) fn lexical_bindings(&self) -> LowerBindings {
        LowerBindings {
            current_proc_path: self.current_proc_path.clone(),
            current_type_path: self.current_type_path.clone(),
            parameters: self.parameters.clone(),
            parameter_type_flags: self.parameter_type_flags.clone(),
            parameter_value_sources: self.parameter_value_sources.clone(),
            parameter_defaults: self.parameter_defaults.clone(),
            parameter_types: self.parameter_types.clone(),
            ..LowerBindings::default()
        }
    }
}
pub(crate) struct ProjectResolver<'a> {
    pub resolver: &'a dyn Resolver,
    pub symbols: &'a SymbolTable,
    pub slots: RefCell<BTreeMap<crate::Symbol, ResolvedSlot>>,
    pub resources: RefCell<BTreeMap<String, u128>>,
    pub resource_search_context: Option<u128>,
}
impl ProjectResolver<'_> {
    pub fn resource(&self, path: &str) -> Result<String, LowerError> {
        let path_id = SymbolId::of(path);
        let query = match self.resource_search_context {
            Some(search_context) => Q::ResourceIn {
                path: path_id,
                search_context,
            },
            None => Q::Resource(path_id),
        };
        match self.answer(query)? {
            M::Resource { path, content } => {
                let alias = self.text(query, path)?;
                let old = self.resources.borrow_mut().insert(alias.clone(), content);
                if old.is_some_and(|old| old != content) {
                    return Err(self.error(query, "conflicting captured resource content"));
                }
                Ok(alias)
            }
            M::Missing => Err(self.error(query, "resource missing in captured search context")),
            _ => Err(self.error(query, "invalid resource lookup answer")),
        }
    }
    pub fn answer(&self, query: Q) -> Result<M, LowerError> {
        match self.resolver.resolve(query) {
            M::Unsupported(_) => Err(self.error(query, "unsupported semantic query")),
            answer => Ok(answer),
        }
    }
    pub fn error(&self, query: Q, reason: &str) -> LowerError {
        LowerError {
            statement: String::new(),
            reason: format!("{reason}: {query:?}"),
        }
    }
    pub fn text(&self, query: Q, symbol: SymbolId) -> Result<String, LowerError> {
        self.symbols
            .text(symbol)
            .map(str::to_owned)
            .ok_or_else(|| self.error(query, "resolver symbol spelling unavailable"))
    }
    pub fn presence(&self, query: Q) -> Result<bool, LowerError> {
        match self.answer(query)? {
            M::Missing => Ok(false),
            M::Presence(value) => Ok(value),
            M::Member { .. } | M::Symbol(_) | M::Slot { .. } => Ok(true),
            _ => Err(self.error(query, "invalid presence answer")),
        }
    }
    pub fn declared_type(&self, query: Q) -> Result<Option<String>, LowerError> {
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::Member { data, .. } => data
                .declared_type
                .map(|id| self.text(query, id))
                .transpose(),
            _ => Err(self.error(query, "declared type metadata unavailable")),
        }
    }
    pub fn slot(&self, query: Q) -> Result<Option<String>, LowerError> {
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::Slot {
                symbol,
                owner,
                name,
            } => {
                let key = format!(
                    "var{}/{}",
                    self.text(query, owner)?.trim_end_matches('/'),
                    self.text(query, name)?
                );
                let slot = ResolvedSlot {
                    symbol,
                    owner,
                    name,
                };
                let old = self.slots.borrow_mut().insert(
                    crate::Symbol::new(crate::Table::Variable, &key),
                    slot.clone(),
                );
                if old.is_some_and(|old| old != slot) {
                    return Err(self.error(query, "conflicting slot tuple"));
                }
                Ok(Some(key))
            }
            _ => Err(self.error(query, "slot symbol spelling unavailable")),
        }
    }
    pub fn member_proc(&self, owner: &str, name: &str) -> Result<Option<String>, LowerError> {
        let owner_id = SymbolId::of(owner);
        let name_id = SymbolId::of(name);
        let proc_query = Q::Proc {
            owner: owner_id,
            name: name_id,
            verb: false,
        };
        let verb_query = Q::Proc {
            owner: owner_id,
            name: name_id,
            verb: true,
        };
        let procedure = self.answer(proc_query)?;
        let verb = self.answer(verb_query)?;
        let (answer, query, namespace) = match (procedure, verb) {
            (M::Missing, M::Missing) => return Ok(None),
            (answer, M::Missing) => (answer, proc_query, "proc"),
            (M::Missing, answer) => (answer, verb_query, "verb"),
            _ => {
                return Err(self.error(
                    proc_query,
                    "proc/verb selection requires explicit precedence metadata",
                ))
            }
        };
        match answer {
            M::Member { owner, name, .. } => Ok(Some(format!(
                "{}/{}/{}",
                self.text(query, owner)?.trim_end_matches('/'),
                namespace,
                self.text(query, name)?
            ))),
            _ => Err(self.error(query, "procedure declaration metadata unavailable")),
        }
    }
    pub fn constant(&self, name: &str) -> Result<Option<SemanticValue>, LowerError> {
        let query = Q::PredefinedConstant(SymbolId::of(name));
        match self.answer(query)? {
            M::Missing => Ok(None),
            M::Value(value) => Ok(Some(value)),
            _ => Err(self.error(query, "invalid predefined constant answer")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    struct Host {
        reads: Mutex<Vec<Q>>,
        answer: fn(Q) -> M,
    }
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            self.reads.lock().unwrap().push(query);
            (self.answer)(query)
        }
    }
    fn lower(
        source: &str,
        inputs: ProcedureInputs,
        symbols: &SymbolTable,
        host: &Host,
    ) -> Result<ResolverProc, Vec<LowerError>> {
        let ast = dm_syntax::parse(source);
        crate::compile_simple_proc_with_resolver(&ast.items[0].children, &inputs, symbols, host)
    }
    #[test]
    fn locals_need_no_project_snapshot_and_globals_query_host() {
        let host = Host {
            reads: Mutex::new(vec![]),
            answer: |query| match query {
                Q::GlobalVar(id) if id == SymbolId::of("counter") => M::Presence(true),
                _ => M::Unsupported(query),
            },
        };
        let symbols = SymbolTable::default();
        assert!(lower(
            "/proc/p(value)\n    return value\n",
            ProcedureInputs {
                parameters: vec!["value".into()],
                ..Default::default()
            },
            &symbols,
            &host
        )
        .is_ok());
        assert!(host.reads.lock().unwrap().is_empty());
        assert!(lower(
            "/proc/p()\n    return counter\n",
            Default::default(),
            &symbols,
            &host
        )
        .is_ok());
        assert!(host
            .reads
            .lock()
            .unwrap()
            .contains(&Q::GlobalVar(SymbolId::of("counter"))));
    }
    #[test]
    fn unsupported_queries_cannot_become_dynamic_fallback_success() {
        let host = Host {
            reads: Mutex::new(vec![]),
            answer: M::Unsupported,
        };
        let errors = lower(
            "/proc/p()\n    return missing.value\n",
            Default::default(),
            &SymbolTable::default(),
            &host,
        )
        .err()
        .unwrap();
        assert!(errors
            .iter()
            .any(|error| error.reason.contains("unsupported semantic query")));
    }
    #[test]
    fn captured_resource_context_is_demanded_without_filesystem_reads() {
        let mut symbols = SymbolTable::default();
        symbols.intern("assets/icon.dmi").unwrap();
        let host = Host {
            reads: Mutex::new(vec![]),
            answer: |query| match query {
                Q::ResourceIn {
                    path,
                    search_context: 77,
                } if path == SymbolId::of("icon.dmi") => M::Resource {
                    path: SymbolId::of("assets/icon.dmi"),
                    content: 123,
                },
                _ => M::Unsupported(query),
            },
        };
        let result = lower(
            "/proc/p()\n    return 'icon.dmi'\n",
            ProcedureInputs {
                resource_search_context: Some(77),
                ..Default::default()
            },
            &symbols,
            &host,
        )
        .unwrap();
        assert_eq!(result.resources.get("assets/icon.dmi"), Some(&123));
        assert_eq!(result.procedure.resources, ["assets/icon.dmi"]);
    }
}
