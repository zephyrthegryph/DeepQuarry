//! Capture procedure-shared declarations from typed bodies, before lowering.
//! Body spelling dictionaries are small local deltas, never copies of the tree.
use dm_ir::{
    InitializerValue, ProcedureIdentity, ProcedureStaticDeclaration, ProcedureStaticIdentity,
    SymbolTable,
};
use dm_syntax::{Item, Span, Statement, StatementKind};
use std::{collections::HashSet, sync::Arc};

#[path = "procedure_static_duplicates.rs"]
mod duplicates;
#[path = "procedure_static_lexical.rs"]
mod lexical;
pub use duplicates::{duplicate_static_declaration, DuplicateStaticDeclaration};

#[path = "procedure_static_inventory.rs"]
mod inventory;
pub use inventory::StaticInventory;
#[path = "procedure_static_layout.rs"]
mod layout;
pub use layout::StaticLayout;

/// Immutable lexical overlay. A miss is authoritative only for the exact
/// captured procedure inventory; other procedure contexts stay unsupported.
pub struct StaticResolver<'a, R: dm_ir::Resolver> {
    domain_version: Option<u128>,
    underlying_version: Option<u128>,
    pub underlying: &'a R,
    inventory: Arc<StaticInventory>,
}
impl<'a, R: dm_ir::Resolver> StaticResolver<'a, R> {
    pub fn new(
        underlying: &'a R,
        plans: &[(ProcedureIdentity, StaticPlan)],
    ) -> Result<Self, String> {
        Self::from_plans(
            underlying,
            plans.iter().map(|(identity, plan)| (*identity, plan)),
        )
    }
    pub fn from_plans<'p>(
        underlying: &'a R,
        plans: impl IntoIterator<Item = (ProcedureIdentity, &'p StaticPlan)>,
    ) -> Result<Self, String> {
        Self::from_inventory(underlying, Arc::new(StaticInventory::from_plans(plans)?))
    }
    pub fn from_inventory(
        underlying: &'a R,
        inventory: Arc<StaticInventory>,
    ) -> Result<Self, String> {
        let domain_version = underlying
            .domain_version(dm_ir::ReadDomain::Tree)
            .map(|base| {
                let mut hash = xxhash_rust::xxh3::Xxh3::new();
                hash.update(b"dm-procedure-static-domain-v1\0");
                hash.update(&base.to_le_bytes());
                let mut captured: Vec<_> = inventory.procedures.iter().collect();
                captured.sort();
                hash.update(&(captured.len() as u64).to_le_bytes());
                for procedure in captured {
                    hash.update(&procedure.owner.bits().to_le_bytes());
                    hash.update(&procedure.name.bits().to_le_bytes());
                    hash.update(&[u8::from(procedure.verb)]);
                    hash.update(&procedure.occurrence.to_le_bytes());
                }
                hash.update(&(inventory.declarations.len() as u64).to_le_bytes());
                for declaration in inventory.declarations.values() {
                    let bytes = declaration.canonical_bytes();
                    hash.update(&(bytes.len() as u64).to_le_bytes());
                    hash.update(&bytes);
                }
                hash.digest128()
            });
        Ok(Self {
            domain_version,
            underlying_version: underlying.domain_version(dm_ir::ReadDomain::Tree),
            underlying,
            inventory,
        })
    }
}
impl<R: dm_ir::Resolver> dm_ir::Resolver for StaticResolver<'_, R> {
    fn observes_reads(&self) -> bool {
        // The immutable static inventory has no observer; delegated host reads do.
        self.underlying.observes_reads()
    }

    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        match domain {
            dm_ir::ReadDomain::OwnerProcedureStatic(procedure) => {
                self.inventory.certificate(procedure)
            }
            dm_ir::ReadDomain::Tree => {
                if self.underlying.domain_version(domain) == self.underlying_version {
                    self.domain_version
                } else {
                    None
                }
            }
            other => self.underlying.domain_version(other),
        }
    }
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        match query {
            dm_ir::ResolveQuery::ProcedureStatic { procedure, name }
                if self.inventory.procedures.contains(&procedure) =>
            {
                self.inventory
                    .declarations
                    .get(&ProcedureStaticIdentity { procedure, name })
                    .map(|declaration| {
                        dm_ir::ResolvedMeaning::ProcedureStatic(Arc::clone(declaration))
                    })
                    .unwrap_or(dm_ir::ResolvedMeaning::Missing)
            }
            dm_ir::ResolveQuery::ProcedureStatic { .. } => {
                dm_ir::ResolvedMeaning::Unsupported(query)
            }
            _ => self.underlying.resolve(query),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StaticOrigin {
    pub span: Span,
    pub header_span: Span,
    pub encounter: u32,
}
#[derive(Debug)]
pub struct StaticPlan {
    pub procedure: ProcedureIdentity,
    pub declarations: Vec<ProcedureStaticDeclaration>,
    pub origins: Vec<StaticOrigin>,
    pub symbols: SymbolTable,
    pub executable_body: Vec<Item>,
}
const STORED_LOCAL_QUALIFIERS: &[(&str, u32)] = &[("static", 1), ("const", 2), ("global", 8)];
fn stored_local_modifier(component: &str) -> u32 {
    STORED_LOCAL_QUALIFIERS
        .iter()
        .find_map(|(name, bit)| (*name == component).then_some(*bit))
        .unwrap_or(0)
}
/// Negative-only eligibility check over already expanded source. Most bodies
/// fail the cheap substring guard; candidates use the same streaming lexical
/// core as the parser. Only exact identifier tokens can be stored qualifiers.
/// Unknown or malformed lexical input remains a candidate so this optimization
/// never replaces the authoritative capture diagnostics.
pub fn may_contain_stored_declarations(expanded_source: &str) -> bool {
    if !STORED_LOCAL_QUALIFIERS
        .iter()
        .any(|(name, _)| expanded_source.contains(name))
    {
        return false;
    }
    let mut candidate = false;
    let diagnostics = dm_syntax::visit_tokens(expanded_source, |token| match token.kind {
        dm_syntax::TokenKind::Ident => {
            candidate |= stored_local_modifier(token.text(expanded_source)) != 0;
        }
        dm_syntax::TokenKind::Unknown | dm_syntax::TokenKind::Interpolation => candidate = true,
        _ => (),
    });
    candidate || !diagnostics.is_empty()
}
#[cfg(test)]
#[path = "procedure_static_prefilter_tests.rs"]
mod prefilter_tests;
/// Apply the same negative proof to the actual prepared body, including bodies
/// transformed by a caller's ABI policy. No source-only admission is assumed.
pub fn items_may_contain_stored_declarations(items: &[Item]) -> bool {
    items.iter().any(|item| {
        may_contain_stored_declarations(&item.header)
            || items_may_contain_stored_declarations(&item.children)
    })
}
pub fn capture(procedure: ProcedureIdentity, body: &[Item]) -> Result<StaticPlan, String> {
    capture_owned(procedure, body.to_vec())
}

/// Capture startup facts and filter executable items by moving their storage.
pub fn capture_owned(procedure: ProcedureIdentity, body: Vec<Item>) -> Result<StaticPlan, String> {
    let mut plan = capture_declarations(procedure, &body)?;
    let removed: HashSet<_> = plan
        .origins
        .iter()
        .map(|origin| (origin.header_span.start, origin.header_span.end))
        .collect();
    plan.executable_body = filter_executable_items(body, &removed);
    Ok(plan)
}

/// Apply an already authenticated startup declaration roster without reparsing.
pub fn filter_executable_items(items: Vec<Item>, removed: &HashSet<(usize, usize)>) -> Vec<Item> {
    items
        .into_iter()
        .filter(|item| !removed.contains(&(item.header_span.start, item.header_span.end)))
        .map(|mut item| {
            item.children = filter_executable_items(item.children, removed);
            item
        })
        .collect()
}

/// Capture the same owned startup facts and source origins as [`capture`],
/// without copying executable items. `executable_body` is empty; callers that
/// need a filtered body must use `capture`. Neither path changes the input AST.
pub fn capture_declarations(
    procedure: ProcedureIdentity,
    body: &[Item],
) -> Result<StaticPlan, String> {
    let parsed = dm_syntax::parse_body_items(body);
    if !parsed.diagnostics.is_empty() {
        return Err(format!(
            "invalid procedure static body: {:?}",
            parsed.diagnostics
        ));
    }
    fn captured_headers(items: &[Item], headers: &mut HashSet<(usize, usize)>) {
        for item in items {
            if item.header.trim_start().starts_with("var/") {
                headers.insert((item.header_span.start, item.header_span.end));
            }
            captured_headers(&item.children, headers);
        }
    }
    let mut headers = HashSet::new();
    captured_headers(body, &mut headers);
    capture_statement_declarations(procedure, &parsed, &headers)
}

/// Reuse the authenticated body statement model observed during startup.
pub fn capture_issued_statements(
    procedure: ProcedureIdentity,
    body: &crate::frontend::StatementBody,
) -> Result<StaticPlan, String> {
    capture_statement_declarations(procedure, body.parsed(), body.declaration_headers())
}

fn capture_statement_declarations(
    procedure: ProcedureIdentity,
    parsed: &dm_syntax::ParsedBody,
    headers: &HashSet<(usize, usize)>,
) -> Result<StaticPlan, String> {
    if !parsed.diagnostics.is_empty() {
        return Err(format!(
            "invalid procedure static body: {:?}",
            parsed.diagnostics
        ));
    }
    let mut plan = StaticPlan {
        procedure,
        declarations: Vec::new(),
        origins: Vec::new(),
        symbols: SymbolTable::default(),
        executable_body: Vec::new(),
    };
    let mut names = HashSet::new();
    walk(procedure, &parsed.statements, &mut plan, &mut names, &[])?;
    if plan
        .origins
        .iter()
        .any(|origin| !headers.contains(&(origin.header_span.start, origin.header_span.end)))
    {
        return Err(
            "inline procedure static extraction requires an authoritative statement rewrite".into(),
        );
    }
    Ok(plan)
}

fn walk(
    procedure: ProcedureIdentity,
    statements: &[Statement],
    plan: &mut StaticPlan,
    names: &mut HashSet<dm_ir::SymbolId>,
    outer_locals: &[(dm_ir::SymbolId, Option<dm_ir::SymbolId>)],
) -> Result<(), String> {
    let mut locals = outer_locals.to_vec();
    let mut local_owner: Option<Arc<[(dm_ir::SymbolId, Option<dm_ir::SymbolId>)]>> = None;
    for statement in statements {
        match &statement.kind {
            StatementKind::Var { declaration, value } => {
                let path = declaration
                    .strip_prefix("var/")
                    .or_else(|| declaration.strip_prefix("var "))
                    .ok_or("unsupported variable declaration")?;
                let declaration_path = path.split('[').next().unwrap_or(path).trim();
                let components: Vec<_> = declaration_path
                    .split('/')
                    .filter(|part| !part.is_empty())
                    .collect();
                let Some((name, prefix)) = components.split_last() else {
                    return Err("missing static name".into());
                };
                let mut modifiers = 0;
                let mut types = Vec::new();
                for component in prefix {
                    match *component {
                        "tmp" => modifiers |= 4,
                        other => {
                            let storage = stored_local_modifier(other);
                            if storage != 0 {
                                modifiers |= storage;
                            } else {
                                types.push(other);
                            }
                        }
                    }
                }
                if modifiers & 11 == 0 {
                    locals.push(lexical::local(declaration, &mut plan.symbols)?);
                    local_owner = None;
                    continue;
                }
                let name = plan
                    .symbols
                    .intern(name)
                    .map_err(|error| error.to_string())?;
                if !names.insert(name) {
                    return Err("same-name scoped procedure statics require a certified lexical slot policy".into());
                }
                let declared_type = if types.is_empty() {
                    None
                } else {
                    Some(
                        plan.symbols
                            .intern(&format!("/{}", types.join("/")))
                            .map_err(|error| error.to_string())?,
                    )
                };
                let array =
                    crate::procedure::parse_array(declaration, declared_type, &mut plan.symbols)?;
                let initializer = if let Some(value) = value {
                    let relative_start = value
                        .span
                        .start
                        .checked_sub(statement.header_span.start)
                        .ok_or("static expression outside header")?;
                    let relative_end = value
                        .span
                        .end
                        .checked_sub(statement.header_span.start)
                        .ok_or("static expression outside header")?;
                    let text = statement
                        .raw_header
                        .get(relative_start..relative_end)
                        .ok_or("static expression capture mismatch")?;
                    InitializerValue::Expression(crate::procedure::expression(
                        text,
                        &mut plan.symbols,
                    )?)
                } else if let Some(array) = &array {
                    InitializerValue::ArrayAllocation(Arc::clone(array))
                } else {
                    InitializerValue::NoAuthoredValue
                };
                let encounter =
                    u32::try_from(plan.origins.len()).map_err(|_| "too many procedure statics")?;
                plan.declarations.push(ProcedureStaticDeclaration {
                    identity: ProcedureStaticIdentity { procedure, name },
                    declared_type,
                    modifiers,
                    declared_array: array,
                    initializer,
                    lexical_locals: Arc::clone(
                        local_owner.get_or_insert_with(|| Arc::from(locals.clone())),
                    ),
                });
                plan.origins.push(StaticOrigin {
                    span: statement.span,
                    header_span: statement.header_span,
                    encounter,
                });
            }
            StatementKind::If {
                then_branch,
                else_branch,
                ..
            } => {
                walk(procedure, then_branch, plan, names, &locals)?;
                walk(procedure, else_branch, plan, names, &locals)?;
            }
            StatementKind::While { body, .. }
            | StatementKind::DoWhile { body, .. }
            | StatementKind::Spawn { body, .. }
            | StatementKind::Label { body, .. } => walk(procedure, body, plan, names, &locals)?,
            StatementKind::For { control, body } => {
                let declarations: Vec<&str> = match control {
                    dm_syntax::ForControl::All { declaration } => vec![declaration],
                    dm_syntax::ForControl::Each { binding, .. }
                    | dm_syntax::ForControl::Range { binding, .. } => vec![binding],
                    dm_syntax::ForControl::Pair {
                        key_binding,
                        value_binding,
                        ..
                    } => vec![key_binding, value_binding],
                    dm_syntax::ForControl::CStyle {
                        initializer: Some(dm_syntax::ForInitializer::Declare { declaration, .. }),
                        ..
                    } => vec![declaration],
                    _ => Vec::new(),
                };
                if declarations.iter().any(|declaration| {
                    declaration
                        .split('/')
                        .any(|part| stored_local_modifier(part) != 0)
                }) {
                    return Err("shared for-control declaration is not supported".into());
                }
                let mut loop_locals = locals.clone();
                for declaration in declarations {
                    if declaration.trim_start().starts_with("var") {
                        loop_locals.push(lexical::local(declaration, &mut plan.symbols)?);
                    }
                }
                walk(procedure, body, plan, names, &loop_locals)?;
            }
            StatementKind::Switch {
                cases, else_branch, ..
            } => {
                for case in cases {
                    walk(procedure, &case.body, plan, names, &locals)?;
                }
                walk(procedure, else_branch, plan, names, &locals)?;
            }
            StatementKind::Try {
                body,
                catch_body,
                catch_binding,
                ..
            } => {
                walk(procedure, body, plan, names, &locals)?;
                let mut catch_locals = locals.clone();
                if let Some(declaration) = catch_binding {
                    catch_locals.push(lexical::local(declaration, &mut plan.symbols)?);
                }
                walk(procedure, catch_body, plan, names, &catch_locals)?;
            }
            _ => (),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn immutable_static_overlay_preserves_underlying_read_observers() {
        use dm_ir::Resolver;
        struct Host(bool);
        impl Resolver for Host {
            fn observes_reads(&self) -> bool {
                self.0
            }
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                dm_ir::ResolvedMeaning::Unsupported(query)
            }
        }
        let observing = Host(true);
        let immutable = Host(false);
        let id = identity();
        let observed = StaticResolver::new(&observing, &[(id, capture(id, &[]).unwrap())]).unwrap();
        let unobserved =
            StaticResolver::new(&immutable, &[(id, capture(id, &[]).unwrap())]).unwrap();
        assert!(observed.observes_reads());
        assert!(!unobserved.observes_reads());
    }
    #[test]
    fn domain_version_certifies_empty_static_inventory_and_invalidates_new_declarations() {
        use dm_ir::{ReadDomain, Resolver};
        struct Base;
        impl Resolver for Base {
            fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                dm_ir::ResolvedMeaning::Unsupported(query)
            }
            fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
                (domain == ReadDomain::Tree).then_some(9)
            }
        }
        let id = identity();
        let base = Base;
        let empty = capture(id, &[]).unwrap();
        let old = StaticResolver::new(&base, &[(id, empty)]).unwrap();
        let parsed = dm_syntax::parse("var/static/value = 1\n");
        let changed = capture(id, &parsed.items).unwrap();
        let new = StaticResolver::new(&base, &[(id, changed)]).unwrap();
        assert_ne!(
            old.domain_version(ReadDomain::Tree),
            new.domain_version(ReadDomain::Tree)
        );
        let query = dm_ir::ResolveQuery::ProcedureStatic {
            procedure: id,
            name: dm_ir::SymbolId::of("value"),
        };
        assert_eq!(old.resolve(query), dm_ir::ResolvedMeaning::Missing);
        assert!(matches!(
            new.resolve(query),
            dm_ir::ResolvedMeaning::ProcedureStatic(_)
        ));
    }
    fn identity() -> ProcedureIdentity {
        ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/datum/x"),
            name: dm_ir::SymbolId::of("read"),
            verb: false,
            occurrence: 1,
        }
    }
    #[test]
    fn nested_statics_are_startup_facts_not_executable_declarations() {
        let source = "/datum/x/proc/read()\n    var/static/list/cache = list(1)\n    if(1)\n        var/static/count = 2\n    var/local = 3\n    return cache\n";
        let parsed = dm_syntax::parse(source);
        let proc = &parsed.items[0];
        let plan = capture(identity(), &proc.children).unwrap();
        assert_eq!(plan.declarations.len(), 2);
        assert_eq!(
            plan.symbols.text(plan.declarations[0].identity.name),
            Some("cache")
        );
        assert_eq!(
            plan.declarations[0].declared_type,
            Some(dm_ir::SymbolId::of("/list"))
        );
        assert_eq!(plan.origins[0].encounter, 0);
        assert_eq!(plan.origins[1].encounter, 1);
        assert_eq!(plan.executable_body.len(), 3);
        assert!(plan.executable_body[0].children.is_empty());
        assert!(plan.executable_body[1].header.contains("var/local"));
        assert!(matches!(
            plan.declarations[0].initializer,
            InitializerValue::Expression(_)
        ));
    }
    #[test]
    fn owned_capture_matches_borrowed_and_moves_executable_headers() {
        let mut parsed = dm_syntax::parse(
            "/proc/p()\n    var/static/cache = 1\n    if(1)\n        return cache\n",
        );
        assert!(parsed.diagnostics.is_empty());
        let body = std::mem::take(&mut parsed.items[0].children);
        let conditional = body[1].header.as_ptr();
        let nested = body[1].children[0].header.as_ptr();
        let borrowed = capture(identity(), &body).unwrap();
        let owned = capture_owned(identity(), body).unwrap();
        assert_eq!(owned.procedure, borrowed.procedure);
        assert_eq!(owned.declarations, borrowed.declarations);
        assert_eq!(owned.origins, borrowed.origins);
        assert_eq!(owned.symbols.ordered(), borrowed.symbols.ordered());
        assert_eq!(owned.executable_body, borrowed.executable_body);
        assert_eq!(owned.executable_body[0].header.as_ptr(), conditional);
        assert_eq!(owned.executable_body[0].children[0].header.as_ptr(), nested);
    }
    #[test]
    fn same_name_scoped_statics_fail_closed() {
        let parsed = dm_syntax::parse(
            "/proc/p()\n    var/static/x = 1\n    if(1)\n        var/static/x = 2\n",
        );
        assert!(capture(identity(), &parsed.items[0].children)
            .unwrap_err()
            .contains("same-name"));
    }
    #[test]
    fn declaration_capture_matches_full_capture_and_owns_its_facts() {
        let parsed = dm_syntax::parse(
            "/proc/p()\n    var/static/list/cache = list(1)\n    if(1)\n        var/const/count = 2\n        while(count)\n            count--\n    var/local = 3\n    return cache\n",
        );
        assert!(parsed.diagnostics.is_empty());
        let body = &parsed.items[0].children;
        let original = body.clone();
        let full = capture(identity(), body).unwrap();
        let declarations = capture_declarations(identity(), body).unwrap();
        assert_eq!(body, &original);
        assert_eq!(declarations.procedure, full.procedure);
        assert_eq!(declarations.declarations, full.declarations);
        assert_eq!(declarations.origins, full.origins);
        assert_eq!(declarations.symbols.ordered(), full.symbols.ordered());
        assert!(declarations.executable_body.is_empty());
        assert!(!full.executable_body.is_empty());
        drop(parsed);
        assert_eq!(
            declarations
                .symbols
                .text(declarations.declarations[0].identity.name),
            Some("cache")
        );
        assert_eq!(declarations.origins.len(), 2);
        assert!(matches!(
            declarations.declarations[0].initializer,
            InitializerValue::Expression(_)
        ));
    }
    #[test]
    fn declaration_capture_preserves_failure_admission() {
        for source in [
            "/proc/p()\n    var/static/x = 1\n    if(1)\n        var/static/x = 2\n",
            "/proc/p()\n    for(var/static/x = 1; x; x--)\n        return x\n",
        ] {
            let parsed = dm_syntax::parse(source);
            let body = &parsed.items[0].children;
            assert_eq!(
                capture(identity(), body).unwrap_err(),
                capture_declarations(identity(), body).unwrap_err()
            );
        }
    }
}
